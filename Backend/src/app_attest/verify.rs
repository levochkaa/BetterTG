//! App Attest attestation and assertion checks, following Apple's "Validating apps that connect to your server"
//! as the `appattest-checker-node` package did for the NestJS backend.

use ciborium::Value;
use der::Decode;
use p256::ecdsa::signature::Verifier;
use p256::ecdsa::signature::hazmat::PrehashVerifier;
use p256::pkcs8::{DecodePublicKey, EncodePublicKey, LineEnding};
use sha2::{Digest, Sha256, Sha384};
use x509_cert::Certificate;
use x509_cert::der::DecodePem;

const APPLE_APP_ATTESTATION_ROOT_CA: &str = "-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----
";

const NONCE_EXTENSION_OID: &str = "1.2.840.113635.100.8.2";
const ECDSA_WITH_SHA256: &str = "1.2.840.10045.4.3.2";
const ECDSA_WITH_SHA384: &str = "1.2.840.10045.4.3.3";
const CURVE_P256: &str = "1.2.840.10045.3.1.7";
const CURVE_P384: &str = "1.3.132.0.34";

/// Why a check failed, named as `appattest-checker-node` named it.
#[derive(Clone, Copy, Debug, PartialEq, Eq, thiserror::Error)]
#[error("{0}")]
pub struct VerifyError(pub &'static str);

pub struct VerifiedAttestation {
    pub public_key_pem: String,
    pub receipt: Vec<u8>,
}

pub struct AppAttestVerifier {
    root: Certificate,
    app_id: String,
    /// Accepts keys from the development App Attest environment as well as production ones.
    allow_development: bool,
}

fn map_get<'a>(map: &'a [(Value, Value)], key: &str) -> Option<&'a Value> {
    map.iter().find(|(name, _)| name.as_text() == Some(key)).map(|(_, value)| value)
}

fn sign_count(authenticator_data: &[u8]) -> i32 {
    i32::from_be_bytes(authenticator_data[33..37].try_into().expect("4 bytes"))
}

/// The content of the DER element at the start of `bytes`, with its header and contents.
fn first_element(bytes: &[u8]) -> Option<&[u8]> {
    let (&_, rest) = bytes.split_first()?;
    let (&first_length, rest) = rest.split_first()?;
    let (length, header) = if first_length < 0x80 {
        (first_length as usize, 2)
    } else {
        let count = (first_length & 0x7f) as usize;
        if count == 0 || count > 4 || rest.len() < count {
            return None;
        }
        (rest[..count].iter().fold(0usize, |length, byte| (length << 8) | *byte as usize), 2 + count)
    };
    bytes.get(..header + length)
}

/// The signed part of a certificate, exactly as encoded.
fn tbs_bytes(certificate_der: &[u8]) -> Option<&[u8]> {
    let outer = first_element(certificate_der)?;
    let header = if outer[1] < 0x80 { 2 } else { 2 + (outer[1] & 0x7f) as usize };
    first_element(&outer[header..])
}

/// Whether `now` falls within the certificate's validity period.
fn is_current(certificate: &Certificate) -> bool {
    let validity = &certificate.tbs_certificate.validity;
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default();
    validity.not_before.to_unix_duration() <= now && now <= validity.not_after.to_unix_duration()
}

/// Whether the certificate is current and signed by `issuer`'s key.
fn verify_signed_by(certificate_der: &[u8], certificate: &Certificate, issuer: &Certificate) -> bool {
    if !is_current(certificate) {
        return false;
    }
    let Some(tbs) = tbs_bytes(certificate_der) else { return false };
    let Some(signature) = certificate.signature.as_bytes() else { return false };
    let digest = match certificate.signature_algorithm.oid.to_string().as_str() {
        ECDSA_WITH_SHA256 => Sha256::digest(tbs).to_vec(),
        ECDSA_WITH_SHA384 => Sha384::digest(tbs).to_vec(),
        _ => return false,
    };
    let key = &issuer.tbs_certificate.subject_public_key_info;
    let Some(point) = key.subject_public_key.as_bytes() else { return false };
    let curve = key
        .algorithm
        .parameters
        .as_ref()
        .and_then(|parameters| parameters.decode_as::<der::asn1::ObjectIdentifier>().ok());
    match curve.map(|oid| oid.to_string()).as_deref() {
        Some(CURVE_P256) => {
            let (Ok(key), Ok(signature)) =
                (p256::ecdsa::VerifyingKey::from_sec1_bytes(point), p256::ecdsa::Signature::from_der(signature))
            else {
                return false;
            };
            key.verify_prehash(&digest, &signature).is_ok()
        }
        Some(CURVE_P384) => {
            let (Ok(key), Ok(signature)) =
                (p384::ecdsa::VerifyingKey::from_sec1_bytes(point), p384::ecdsa::Signature::from_der(signature))
            else {
                return false;
            };
            key.verify_prehash(&digest, &signature).is_ok()
        }
        _ => false,
    }
}

impl AppAttestVerifier {
    pub fn new(app_id: String, allow_development: bool) -> Self {
        let root = Certificate::from_pem(APPLE_APP_ATTESTATION_ROOT_CA).expect("Apple's App Attest root");
        Self { root, app_id, allow_development }
    }

    #[cfg(test)]
    pub fn with_root(root_der: &[u8], app_id: String, allow_development: bool) -> Self {
        Self { root: Certificate::from_der(root_der).unwrap(), app_id, allow_development }
    }

    /// Checks an attestation for `key_id` made over `challenge`, returning the key and the receipt to keep.
    pub fn verify_attestation(
        &self,
        key_id: &str,
        challenge: &[u8],
        attestation: &[u8],
    ) -> Result<VerifiedAttestation, VerifyError> {
        let parse_error = VerifyError("fail_parsing_attestation");
        let object: Value = ciborium::de::from_reader(attestation).map_err(|_| parse_error)?;
        let object = object.as_map().ok_or(parse_error)?;
        if map_get(object, "fmt").and_then(Value::as_text) != Some("apple-appattest") {
            return Err(parse_error);
        }
        let statement = map_get(object, "attStmt").and_then(Value::as_map).ok_or(parse_error)?;
        let authenticator_data = map_get(object, "authData").and_then(Value::as_bytes).ok_or(parse_error)?;
        if authenticator_data.len() < 88 {
            return Err(parse_error);
        }
        let chain = map_get(statement, "x5c").and_then(Value::as_array).ok_or(parse_error)?;
        let receipt = map_get(statement, "receipt").and_then(Value::as_bytes).ok_or(parse_error)?;
        let (Some(credential_der), Some(intermediate_der)) =
            (chain.first().and_then(Value::as_bytes), chain.get(1).and_then(Value::as_bytes))
        else {
            return Err(parse_error);
        };
        let credential = Certificate::from_der(credential_der).map_err(|_| parse_error)?;
        let intermediate = Certificate::from_der(intermediate_der).map_err(|_| parse_error)?;

        // 1. The credential certificate chains, through current certificates, to Apple's App Attest root.
        if !verify_signed_by(credential_der, &credential, &intermediate) {
            return Err(VerifyError("fail_credCert_verify_failure"));
        }
        if !verify_signed_by(intermediate_der, &intermediate, &self.root) {
            return Err(VerifyError("fail_intermediateCert_verify_failure"));
        }

        // 2-4. The certificate's nonce extension holds SHA-256(authData || SHA-256(challenge)).
        let client_data_hash = Sha256::digest(challenge);
        let nonce = Sha256::digest([authenticator_data.as_slice(), &client_data_hash[..]].concat());
        let extension = credential
            .tbs_certificate
            .extensions
            .iter()
            .flatten()
            .find(|extension| extension.extn_id.to_string() == NONCE_EXTENSION_OID)
            .ok_or(VerifyError("fail_nonce_missing"))?;
        let expected = [&[0x04, 0x20][..], &nonce[..]].concat();
        if !extension.extn_value.as_bytes().ends_with(&expected) {
            return Err(VerifyError("fail_nonce_mismatch"));
        }

        // 5. The key ID is the SHA-256 of the certificate's public key point.
        let spki = &credential.tbs_certificate.subject_public_key_info;
        let point = spki.subject_public_key.as_bytes().ok_or(parse_error)?;
        if point.len() < 65 || base64_standard(&Sha256::digest(&point[point.len() - 65..])) != key_id {
            return Err(VerifyError("fail_keyId_mismatch"));
        }

        // 6. The relying party is this app.
        if authenticator_data[..32] != Sha256::digest(self.app_id.as_bytes())[..] {
            return Err(VerifyError("fail_rpId_mismatch"));
        }
        // 7. A fresh key has signed nothing yet.
        if sign_count(authenticator_data) != 0 {
            return Err(VerifyError("fail_signCount_nonZero"));
        }
        // 8. The AAGUID names the App Attest environment: production always, development only where allowed.
        let aaguid = &authenticator_data[37..53];
        if aaguid != b"appattest\0\0\0\0\0\0\0" && !(self.allow_development && aaguid == b"appattestdevelop") {
            return Err(VerifyError("fail_aaguid_mismatch"));
        }
        // 9. The credential ID is the key ID.
        if authenticator_data[53..55] != [0, 32] {
            return Err(VerifyError("fail_credId_len_invalid"));
        }
        if base64_standard(&authenticator_data[55..87]) != key_id {
            return Err(VerifyError("fail_credId_mismatch"));
        }

        let public_key = p256::PublicKey::from_sec1_bytes(point).map_err(|_| parse_error)?;
        let public_key_pem = public_key.to_public_key_pem(LineEnding::LF).map_err(|_| parse_error)?;
        Ok(VerifiedAttestation { public_key_pem, receipt: receipt.clone() })
    }

    /// Checks an assertion over `client_data_hash` and returns its counter, which must exceed the stored one.
    pub fn verify_assertion(
        &self,
        client_data_hash: &[u8],
        public_key_pem: &str,
        assertion: &[u8],
    ) -> Result<i32, VerifyError> {
        let parse_error = VerifyError("fail_parsing_assertion");
        let object: Value = ciborium::de::from_reader(assertion).map_err(|_| parse_error)?;
        let object = object.as_map().ok_or(parse_error)?;
        let signature = map_get(object, "signature").and_then(Value::as_bytes).ok_or(parse_error)?;
        let authenticator_data = map_get(object, "authenticatorData").and_then(Value::as_bytes).ok_or(parse_error)?;
        if authenticator_data.len() < 37 {
            return Err(parse_error);
        }
        let nonce = Sha256::digest([authenticator_data.as_slice(), client_data_hash].concat());
        let key = p256::ecdsa::VerifyingKey::from_public_key_pem(public_key_pem)
            .map_err(|_| VerifyError("fail_invalid_publicKey"))?;
        let signature =
            p256::ecdsa::Signature::from_der(signature).map_err(|_| VerifyError("fail_signature_verification"))?;
        key.verify(&nonce, &signature).map_err(|_| VerifyError("fail_signature_verification"))?;
        if authenticator_data[..32] != Sha256::digest(self.app_id.as_bytes())[..] {
            return Err(VerifyError("fail_rpId_mismatch"));
        }
        Ok(sign_count(authenticator_data))
    }
}

fn base64_standard(bytes: &[u8]) -> String {
    use base64::Engine as _;
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

/// Whether two PEM public keys are the same key, however they are formatted.
pub fn same_public_key(left: &str, right: &str) -> bool {
    match (p256::PublicKey::from_public_key_pem(left), p256::PublicKey::from_public_key_pem(right)) {
        (Ok(left), Ok(right)) => left == right,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use p256::ecdsa::SigningKey;
    use p256::ecdsa::signature::Signer;
    use rand::rngs::OsRng;
    use rcgen::{
        CertificateParams, CustomExtension, DnType, IsCa, KeyPair, PKCS_ECDSA_P256_SHA256, PKCS_ECDSA_P384_SHA384,
    };

    use der::Encode;

    use super::*;

    const APP_ID: &str = "7Z2WHPKU8W.com.levochkaaa.BetterTG";

    struct Device {
        verifier: AppAttestVerifier,
        key: SigningKey,
        key_id: String,
        attestation: Vec<u8>,
    }

    fn cbor(value: Value) -> Vec<u8> {
        let mut bytes = Vec::new();
        ciborium::ser::into_writer(&value, &mut bytes).unwrap();
        bytes
    }

    fn text(value: &str) -> Value {
        Value::Text(value.to_owned())
    }

    fn authenticator_data(key_id: &[u8], counter: i32, aaguid: &[u8; 16]) -> Vec<u8> {
        let mut data = Sha256::digest(APP_ID.as_bytes()).to_vec();
        data.push(0x40);
        data.extend(counter.to_be_bytes());
        data.extend(aaguid);
        data.extend([0, 32]);
        data.extend(key_id);
        data.extend([0xa5; 10]);
        data
    }

    /// A device key attested by a synthetic root → intermediate → credential chain shaped like Apple's.
    fn device(challenge: &[u8], aaguid: &[u8; 16]) -> Device {
        device_with(challenge, aaguid, false)
    }

    fn device_with(challenge: &[u8], aaguid: &[u8; 16], expired_intermediate: bool) -> Device {
        let root_key = KeyPair::generate_for(&PKCS_ECDSA_P384_SHA384).unwrap();
        let mut root_params = CertificateParams::new(Vec::<String>::new()).unwrap();
        root_params.distinguished_name.push(DnType::CommonName, "Test App Attestation Root CA");
        root_params.is_ca = IsCa::Ca(rcgen::BasicConstraints::Unconstrained);
        let root = root_params.self_signed(&root_key).unwrap();

        let intermediate_key = KeyPair::generate_for(&PKCS_ECDSA_P384_SHA384).unwrap();
        let mut intermediate_params = CertificateParams::new(Vec::<String>::new()).unwrap();
        intermediate_params.distinguished_name.push(DnType::CommonName, "Test App Attestation CA 1");
        intermediate_params.is_ca = IsCa::Ca(rcgen::BasicConstraints::Unconstrained);
        if expired_intermediate {
            intermediate_params.not_before = time::OffsetDateTime::now_utc() - time::Duration::days(30);
            intermediate_params.not_after = time::OffsetDateTime::now_utc() - time::Duration::days(1);
        }
        let intermediate = intermediate_params.signed_by(&intermediate_key, &root, &root_key).unwrap();

        let key = SigningKey::random(&mut OsRng);
        let point = key.verifying_key().to_encoded_point(false);
        let key_id_bytes = Sha256::digest(point.as_bytes());
        let key_id = base64_standard(&key_id_bytes);
        let data = authenticator_data(&key_id_bytes, 0, aaguid);
        let nonce = Sha256::digest([data.as_slice(), &Sha256::digest(challenge)[..]].concat());
        let mut nonce_extension = vec![0x30, 0x24, 0xa1, 0x22, 0x04, 0x20];
        nonce_extension.extend(nonce);

        let credential_key = KeyPair::from_pkcs8_der_and_sign_algo(
            &key.to_pkcs8_der().unwrap().as_bytes().into(),
            &PKCS_ECDSA_P256_SHA256,
        )
        .unwrap();
        let mut credential_params = CertificateParams::new(Vec::<String>::new()).unwrap();
        credential_params.distinguished_name.push(DnType::CommonName, key_id.clone());
        credential_params
            .custom_extensions
            .push(CustomExtension::from_oid_content(&[1, 2, 840, 113635, 100, 8, 2], nonce_extension));
        let credential = credential_params.signed_by(&credential_key, &intermediate, &intermediate_key).unwrap();

        let attestation = cbor(Value::Map(vec![
            (text("fmt"), text("apple-appattest")),
            (
                text("attStmt"),
                Value::Map(vec![
                    (
                        text("x5c"),
                        Value::Array(vec![
                            Value::Bytes(credential.der().to_vec()),
                            Value::Bytes(intermediate.der().to_vec()),
                        ]),
                    ),
                    (text("receipt"), Value::Bytes(b"receipt".to_vec())),
                ]),
            ),
            (text("authData"), Value::Bytes(data)),
        ]));
        let verifier = AppAttestVerifier::with_root(root.der(), APP_ID.to_owned(), true);
        Device { verifier, key, key_id, attestation }
    }

    use p256::pkcs8::EncodePrivateKey;

    fn assertion(device: &Device, client_data_hash: &[u8], counter: i32) -> Vec<u8> {
        let data = authenticator_data(&[], counter, &[0; 16])[..37].to_vec();
        let nonce = Sha256::digest([data.as_slice(), client_data_hash].concat());
        let signature: p256::ecdsa::Signature = device.key.sign(&nonce);
        cbor(Value::Map(vec![
            (text("signature"), Value::Bytes(signature.to_der().as_bytes().to_vec())),
            (text("authenticatorData"), Value::Bytes(data)),
        ]))
    }

    #[test]
    fn accepts_an_attestation_and_its_assertions() {
        let device = device(b"challenge-0123456789abcdef", b"appattestdevelop");
        let verified = device
            .verifier
            .verify_attestation(&device.key_id, b"challenge-0123456789abcdef", &device.attestation)
            .unwrap();
        assert_eq!(verified.receipt, b"receipt");
        assert!(same_public_key(
            &verified.public_key_pem,
            &device.key.verifying_key().to_public_key_pem(LineEnding::CRLF).unwrap()
        ));

        let client_data_hash = Sha256::digest(b"{\"apnsToken\":\"...\"}");
        let signed = assertion(&device, &client_data_hash, 3);
        assert_eq!(device.verifier.verify_assertion(&client_data_hash, &verified.public_key_pem, &signed), Ok(3));
        assert_eq!(
            device.verifier.verify_assertion(&Sha256::digest(b"other"), &verified.public_key_pem, &signed),
            Err(VerifyError("fail_signature_verification"))
        );
    }

    #[test]
    fn rejects_attestations_that_do_not_match() {
        let device = device(b"challenge-0123456789abcdef", b"appattestdevelop");
        let verifier = &device.verifier;
        assert_eq!(
            verifier.verify_attestation(&device.key_id, b"other-challenge-0123456789", &device.attestation).err(),
            Some(VerifyError("fail_nonce_mismatch"))
        );
        assert_eq!(
            verifier.verify_attestation("AAAA", b"challenge-0123456789abcdef", &device.attestation).err(),
            Some(VerifyError("fail_keyId_mismatch"))
        );
        let production =
            AppAttestVerifier { root: verifier.root.clone(), app_id: APP_ID.to_owned(), allow_development: false };
        assert_eq!(
            production.verify_attestation(&device.key_id, b"challenge-0123456789abcdef", &device.attestation).err(),
            Some(VerifyError("fail_aaguid_mismatch"))
        );
        let other_app =
            AppAttestVerifier { root: verifier.root.clone(), app_id: "X.other".to_owned(), allow_development: true };
        assert_eq!(
            other_app.verify_attestation(&device.key_id, b"challenge-0123456789abcdef", &device.attestation).err(),
            Some(VerifyError("fail_rpId_mismatch"))
        );
        let apple = AppAttestVerifier::new(APP_ID.to_owned(), true);
        assert_eq!(
            apple.verify_attestation(&device.key_id, b"challenge-0123456789abcdef", &device.attestation).err(),
            Some(VerifyError("fail_intermediateCert_verify_failure"))
        );
        assert_eq!(
            verifier.verify_attestation(&device.key_id, b"x", b"not cbor").err(),
            Some(VerifyError("fail_parsing_attestation"))
        );
    }

    #[test]
    fn accepts_the_production_aaguid_in_either_mode() {
        let production = device(b"challenge-0123456789abcdef", b"appattest\0\0\0\0\0\0\0");
        for allow_development in [false, true] {
            let verifier = AppAttestVerifier {
                root: production.verifier.root.clone(),
                app_id: APP_ID.to_owned(),
                allow_development,
            };
            assert!(
                verifier
                    .verify_attestation(&production.key_id, b"challenge-0123456789abcdef", &production.attestation)
                    .is_ok()
            );
        }
        let malformed = device(b"challenge-0123456789abcdef", b"appattest\0\0\0\0\0\0x");
        assert_eq!(
            malformed
                .verifier
                .verify_attestation(&malformed.key_id, b"challenge-0123456789abcdef", &malformed.attestation)
                .err(),
            Some(VerifyError("fail_aaguid_mismatch"))
        );
    }

    #[test]
    fn rejects_an_expired_intermediate() {
        let device = device_with(b"challenge-0123456789abcdef", b"appattestdevelop", true);
        assert_eq!(
            device
                .verifier
                .verify_attestation(&device.key_id, b"challenge-0123456789abcdef", &device.attestation)
                .err(),
            Some(VerifyError("fail_intermediateCert_verify_failure"))
        );
    }

    #[test]
    fn slices_the_signed_part_of_a_certificate() {
        let root = Certificate::from_pem(APPLE_APP_ATTESTATION_ROOT_CA).unwrap();
        let der = root.to_der().unwrap();
        assert_eq!(tbs_bytes(&der).unwrap(), root.tbs_certificate.to_der().unwrap());
        assert!(verify_signed_by(&der, &root, &root));
    }
}
