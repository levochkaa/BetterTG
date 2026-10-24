//! Web Push message encryption: RFC 8291 over RFC 8188 `aes128gcm`, and the legacy `aesgcm` draft Telegram still
//! sends, with its salt and sender key in HTTP headers. Byte-for-byte what the `http_ece` package produced and
//! accepted for the NestJS backend.

use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes128Gcm, Nonce};
use hkdf::Hkdf;
use p256::{PublicKey, SecretKey};
use sha2::Sha256;

const TAG_LENGTH: usize = 16;
const KEY_LENGTH: usize = 16;
const NONCE_LENGTH: usize = 12;
const SALT_LENGTH: usize = 16;

/// Why a message could not be decrypted, named as the relay's decryption-failure metric reports it.
#[derive(Clone, Copy, Debug, PartialEq, Eq, thiserror::Error)]
pub enum EceError {
    #[error("authentication_failed")]
    AuthenticationFailed,
    #[error("invalid_padding")]
    InvalidPadding,
    #[error("truncated_payload")]
    TruncatedPayload,
    #[error("invalid_record")]
    InvalidRecord,
    #[error("invalid_key_material_or_payload")]
    InvalidKeyMaterial,
}

impl EceError {
    pub fn reason(self) -> &'static str {
        match self {
            Self::AuthenticationFailed => "authentication_failed",
            Self::InvalidPadding => "invalid_padding",
            Self::TruncatedPayload => "truncated_payload",
            Self::InvalidRecord => "invalid_record",
            Self::InvalidKeyMaterial => "invalid_key_material_or_payload",
        }
    }
}

/// The `aesgcm` parameters from the `Encryption` and `Crypto-Key` headers.
pub struct LegacyParameters<'a> {
    pub salt: &'a [u8],
    pub sender_public_key: &'a [u8],
    pub record_size: usize,
}

struct ContentKey {
    key: [u8; KEY_LENGTH],
    nonce: [u8; NONCE_LENGTH],
}

fn hkdf(salt: &[u8], input: &[u8], info: &[&[u8]], output: &mut [u8]) {
    Hkdf::<Sha256>::new(Some(salt), input).expand_multi_info(info, output).expect("HKDF output length");
}

fn content_key(salt: &[u8], secret: &[u8], key_info: &[&[u8]], nonce_info: &[&[u8]]) -> ContentKey {
    let mut key = ContentKey { key: [0; KEY_LENGTH], nonce: [0; NONCE_LENGTH] };
    hkdf(salt, secret, key_info, &mut key.key);
    hkdf(salt, secret, nonce_info, &mut key.nonce);
    key
}

fn shared_secret(private_key: &SecretKey, public_key: &PublicKey) -> [u8; 32] {
    let shared = p256::ecdh::diffie_hellman(private_key.to_nonzero_scalar(), public_key.as_affine());
    (*shared.raw_secret_bytes()).into()
}

fn uncompressed(public_key: &PublicKey) -> [u8; 65] {
    use p256::elliptic_curve::sec1::ToEncodedPoint;
    public_key.to_encoded_point(false).as_bytes().try_into().expect("uncompressed P-256 point")
}

/// Reads an uncompressed P-256 point, rejecting anything off the curve.
pub fn parse_public_key(bytes: &[u8]) -> Result<PublicKey, EceError> {
    if bytes.len() != 65 || bytes[0] != 4 {
        return Err(EceError::InvalidKeyMaterial);
    }
    PublicKey::from_sec1_bytes(bytes).map_err(|_| EceError::InvalidKeyMaterial)
}

/// Reads a private scalar, left-padding the shorter form Node's `ECDH.getPrivateKey()` returns for a scalar with
/// leading zero bytes.
pub fn parse_private_key(bytes: &[u8]) -> Result<SecretKey, EceError> {
    if bytes.is_empty() || bytes.len() > 32 {
        return Err(EceError::InvalidKeyMaterial);
    }
    let mut padded = [0u8; 32];
    padded[32 - bytes.len()..].copy_from_slice(bytes);
    SecretKey::from_slice(&padded).map_err(|_| EceError::InvalidKeyMaterial)
}

fn record_nonce(base: &[u8; NONCE_LENGTH], counter: u64) -> [u8; NONCE_LENGTH] {
    let mut nonce = *base;
    for (index, byte) in counter.to_be_bytes()[2..].iter().enumerate() {
        nonce[NONCE_LENGTH - 6 + index] ^= byte;
    }
    nonce
}

fn open(key: &ContentKey, counter: u64, record: &[u8]) -> Result<Vec<u8>, EceError> {
    Aes128Gcm::new_from_slice(&key.key)
        .expect("AES-128 key")
        .decrypt(&Nonce::from(record_nonce(&key.nonce, counter)), record)
        .map_err(|_| EceError::AuthenticationFailed)
}

fn seal(key: &ContentKey, counter: u64, plaintext: &[u8]) -> Vec<u8> {
    Aes128Gcm::new_from_slice(&key.key)
        .expect("AES-128 key")
        .encrypt(&Nonce::from(record_nonce(&key.nonce, counter)), plaintext)
        .expect("AES-GCM encryption")
}

fn webpush_key(
    salt: &[u8],
    auth_secret: &[u8],
    shared: &[u8; 32],
    receiver: &[u8; 65],
    sender: &[u8; 65],
) -> ContentKey {
    let mut input = [0u8; 32];
    hkdf(auth_secret, shared, &[b"WebPush: info\0", receiver, sender], &mut input);
    content_key(salt, &input, &[b"Content-Encoding: aes128gcm\0"], &[b"Content-Encoding: nonce\0"])
}

fn legacy_key(
    salt: &[u8],
    auth_secret: &[u8],
    shared: &[u8; 32],
    receiver: &[u8; 65],
    sender: &[u8; 65],
) -> ContentKey {
    let mut secret = [0u8; 32];
    hkdf(auth_secret, shared, &[b"Content-Encoding: auth\0"], &mut secret);
    let length = 65u16.to_be_bytes();
    let context: [&[u8]; 5] = [b"P-256\0", &length, receiver, &length, sender];
    let key_info = [&[b"Content-Encoding: aesgcm\0".as_slice()], &context[..]].concat();
    let nonce_info = [&[b"Content-Encoding: nonce\0".as_slice()], &context[..]].concat();
    content_key(salt, &secret, &key_info, &nonce_info)
}

/// Decrypts an `aes128gcm` body: salt, record size and the sender's key come from its header.
pub fn decrypt_aes128gcm(receiver: &SecretKey, auth_secret: &[u8], body: &[u8]) -> Result<Vec<u8>, EceError> {
    if body.len() < SALT_LENGTH + 5 {
        return Err(EceError::TruncatedPayload);
    }
    let salt = &body[..SALT_LENGTH];
    let record_size = u32::from_be_bytes(body[16..20].try_into().unwrap()) as usize;
    let key_id_length = body[20] as usize;
    let header_length = 21 + key_id_length;
    if body.len() < header_length {
        return Err(EceError::TruncatedPayload);
    }
    if record_size < 18 {
        return Err(EceError::InvalidRecord);
    }
    let sender = parse_public_key(&body[21..header_length])?;
    let receiver_public = uncompressed(&receiver.public_key());
    let key =
        webpush_key(salt, auth_secret, &shared_secret(receiver, &sender), &receiver_public, &uncompressed(&sender));

    let content = &body[header_length..];
    let mut plaintext = Vec::with_capacity(content.len());
    for (counter, record) in content.chunks(record_size).enumerate() {
        if record.len() <= TAG_LENGTH {
            return Err(EceError::InvalidRecord);
        }
        let last = (counter + 1) * record_size >= content.len();
        let data = open(&key, counter as u64, record)?;
        let delimiter = data.iter().rposition(|byte| *byte != 0).ok_or(EceError::InvalidPadding)?;
        if data[delimiter] != if last { 2 } else { 1 } {
            return Err(EceError::InvalidPadding);
        }
        plaintext.extend_from_slice(&data[..delimiter]);
    }
    Ok(plaintext)
}

/// Decrypts an `aesgcm` body with the parameters from its headers.
pub fn decrypt_aesgcm(
    receiver: &SecretKey,
    auth_secret: &[u8],
    parameters: &LegacyParameters<'_>,
    body: &[u8],
) -> Result<Vec<u8>, EceError> {
    if parameters.salt.len() != SALT_LENGTH {
        return Err(EceError::InvalidKeyMaterial);
    }
    if parameters.record_size < 3 {
        return Err(EceError::InvalidRecord);
    }
    let sender = parse_public_key(parameters.sender_public_key)?;
    let key = legacy_key(
        parameters.salt,
        auth_secret,
        &shared_secret(receiver, &sender),
        &uncompressed(&receiver.public_key()),
        &uncompressed(&sender),
    );

    let chunk = parameters.record_size + TAG_LENGTH;
    let mut plaintext = Vec::with_capacity(body.len());
    let mut start = 0;
    let mut counter = 0u64;
    while start < body.len() {
        let end = start + chunk;
        // A message whose last record is full has lost its final, shorter record.
        if end == body.len() {
            return Err(EceError::TruncatedPayload);
        }
        let end = end.min(body.len());
        if end - start <= TAG_LENGTH {
            return Err(EceError::InvalidRecord);
        }
        let data = open(&key, counter, &body[start..end])?;
        if data.len() < 2 {
            return Err(EceError::InvalidPadding);
        }
        let padding = u16::from_be_bytes([data[0], data[1]]) as usize;
        if padding + 2 > data.len() || data[2..2 + padding].iter().any(|byte| *byte != 0) {
            return Err(EceError::InvalidPadding);
        }
        plaintext.extend_from_slice(&data[2 + padding..]);
        start = end;
        counter += 1;
    }
    Ok(plaintext)
}

/// Encrypts as an application server would for `aes128gcm`, without padding. For tests and the smoke check.
pub fn encrypt_aes128gcm(
    plaintext: &[u8],
    sender: &SecretKey,
    receiver: &PublicKey,
    auth_secret: &[u8],
    salt: &[u8; SALT_LENGTH],
    record_size: usize,
) -> Vec<u8> {
    let sender_public = uncompressed(&sender.public_key());
    let key = webpush_key(salt, auth_secret, &shared_secret(sender, receiver), &uncompressed(receiver), &sender_public);
    let mut body = Vec::new();
    body.extend_from_slice(salt);
    body.extend_from_slice(&(record_size as u32).to_be_bytes());
    body.push(65);
    body.extend_from_slice(&sender_public);
    let data_per_record = record_size - TAG_LENGTH - 1;
    let mut start = 0;
    let mut counter = 0u64;
    loop {
        let end = (start + data_per_record).min(plaintext.len());
        let last = end >= plaintext.len();
        let mut record = plaintext[start..end].to_vec();
        record.push(if last { 2 } else { 1 });
        body.extend_from_slice(&seal(&key, counter, &record));
        if last {
            return body;
        }
        start = end;
        counter += 1;
    }
}

/// Encrypts as Telegram does for `aesgcm`, ending with a shorter record. For tests and the smoke check.
pub fn encrypt_aesgcm(
    plaintext: &[u8],
    sender: &SecretKey,
    receiver: &PublicKey,
    auth_secret: &[u8],
    salt: &[u8; SALT_LENGTH],
    record_size: usize,
) -> Vec<u8> {
    let key = legacy_key(
        salt,
        auth_secret,
        &shared_secret(sender, receiver),
        &uncompressed(receiver),
        &uncompressed(&sender.public_key()),
    );
    let data_per_record = record_size - 2;
    let mut body = Vec::new();
    let mut start = 0;
    let mut counter = 0u64;
    loop {
        let end = start + data_per_record;
        let last = end > plaintext.len();
        let mut record = vec![0u8, 0u8];
        record.extend_from_slice(&plaintext[start..end.min(plaintext.len())]);
        body.extend_from_slice(&seal(&key, counter, &record));
        if last {
            return body;
        }
        start = end;
        counter += 1;
    }
}

pub fn public_key_bytes(key: &SecretKey) -> [u8; 65] {
    uncompressed(&key.public_key())
}

#[cfg(test)]
mod tests {
    use rand::rngs::OsRng;

    use super::*;
    use crate::security::base64url;

    #[test]
    fn decrypts_the_rfc_8291_example() {
        let receiver =
            parse_private_key(&base64url::decode("q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94").unwrap()).unwrap();
        let auth_secret = base64url::decode("BTBZMqHH6r4Tts7J_aSIgg").unwrap();
        let body = base64url::decode(
            "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN",
        )
        .unwrap();
        assert_eq!(
            decrypt_aes128gcm(&receiver, &auth_secret, &body).unwrap(),
            b"When I grow up, I want to be a watermelon"
        );
    }

    #[test]
    fn round_trips_aes128gcm_across_records_and_rejects_tampering() {
        let receiver = SecretKey::random(&mut OsRng);
        let sender = SecretKey::random(&mut OsRng);
        let auth_secret = [7u8; 16];
        let plaintext: Vec<u8> = (0..300u16).map(|value| value as u8).collect();
        let mut body = encrypt_aes128gcm(&plaintext, &sender, &receiver.public_key(), &auth_secret, &[3; 16], 100);
        assert_eq!(decrypt_aes128gcm(&receiver, &auth_secret, &body).unwrap(), plaintext);
        let last = body.len() - 1;
        body[last] ^= 1;
        assert_eq!(decrypt_aes128gcm(&receiver, &auth_secret, &body), Err(EceError::AuthenticationFailed));
        assert_eq!(decrypt_aes128gcm(&receiver, &auth_secret, &body[..10]), Err(EceError::TruncatedPayload));
    }

    #[test]
    fn round_trips_aesgcm_with_header_parameters() {
        let receiver = SecretKey::random(&mut OsRng);
        let sender = SecretKey::random(&mut OsRng);
        let auth_secret = [9u8; 16];
        let salt = [5u8; 16];
        let plaintext = br#"{"data":{"loc_key":"MESSAGE_TEXT","loc_args":["Alice","Legacy payload"]}}"#;
        let body = encrypt_aesgcm(plaintext, &sender, &receiver.public_key(), &auth_secret, &salt, 4096);
        let sender_public = public_key_bytes(&sender);
        let parameters = LegacyParameters { salt: &salt, sender_public_key: &sender_public, record_size: 4096 };
        assert_eq!(decrypt_aesgcm(&receiver, &auth_secret, &parameters, &body).unwrap(), plaintext);

        // A body that ends on a full record has lost its last record.
        let exact = encrypt_aesgcm(&[1; 30], &sender, &receiver.public_key(), &auth_secret, &salt, 16);
        let short = LegacyParameters { record_size: 16, ..parameters };
        assert_eq!(decrypt_aesgcm(&receiver, &auth_secret, &short, &exact).unwrap(), [1; 30]);
        assert_eq!(
            decrypt_aesgcm(&receiver, &auth_secret, &short, &exact[..exact.len() - 20]),
            Err(EceError::TruncatedPayload)
        );
    }

    /// Produced by http_ece 1.2.1, which the NestJS backend used, with fixed keys and salt.
    #[test]
    fn matches_http_ece_byte_for_byte() {
        let receiver = parse_private_key(&[0x11; 32]).unwrap();
        let sender = parse_private_key(&[0x22; 32]).unwrap();
        let auth_secret = [0x33; 16];
        let salt = [0x44; 16];
        let plaintext = br#"{"data":{"loc_key":"MESSAGE_TEXT","loc_args":["Alice","Legacy payload"],"custom":{"from_id":1,"msg_id":3}}}"#;
        let legacy = base64url::decode(
            "yOWSLmwpmhD5dBLAr1n5xz706FN4KEWcX2la0mY_qrHSpKrISq7T9juoyeMpaGbADFwYDcwtIoSp4EPOfTtiHorvI9IBIDV3bV23OR5TLG30cWXI9TvVa28lHlsZ-iuPf15gqQtBbyPn4soxtQqBnGt3BZ_AXOKEvElZ75s",
        )
        .unwrap();
        let modern = base64url::decode(
            "RERERERERERERERERERERAAAAEBBBNZak5d8qj0bCBhS_1ennkZfFmBXcwS66tUF3TpIWJzzUBheiVNy32Ih6joTdVfkc_3bZ1XwW9UHw8Uz_OnJEoU6yRQWsawMHGOKBXzoep3SNavnQaoZ2EwBnKjLQ_qouEZaTYUaFvBvXDH0yhWfSHLrtWaPnzMxpcByH6J93zJDjvwMqzwCjhban_xZdgYGFldMmbzh2XZBaxqjdeCUI4Ih57DLCbynaffvxcRVmzObj2qWVKNrHA4EN9EYx2yTX-laJ9oqfoaPw6CoMYdHscgJQKKQs8tlRX5DPWP6Sw",
        )
        .unwrap();
        let sender_public = public_key_bytes(&sender);
        assert_eq!(
            base64url::encode(sender_public),
            "BNZak5d8qj0bCBhS_1ennkZfFmBXcwS66tUF3TpIWJzzUBheiVNy32Ih6joTdVfkc_3bZ1XwW9UHw8Uz_OnJEoU"
        );
        let parameters = LegacyParameters { salt: &salt, sender_public_key: &sender_public, record_size: 4096 };
        assert_eq!(decrypt_aesgcm(&receiver, &auth_secret, &parameters, &legacy).unwrap(), plaintext);
        assert_eq!(decrypt_aes128gcm(&receiver, &auth_secret, &modern).unwrap(), plaintext);
        assert_eq!(encrypt_aesgcm(plaintext, &sender, &receiver.public_key(), &auth_secret, &salt, 4096), legacy);
        assert_eq!(encrypt_aes128gcm(plaintext, &sender, &receiver.public_key(), &auth_secret, &salt, 64), modern);
    }

    #[test]
    fn pads_short_private_keys_like_node() {
        let mut bytes = [0u8; 32];
        bytes[31] = 1;
        assert_eq!(parse_private_key(&bytes[1..]).unwrap().to_bytes(), parse_private_key(&bytes).unwrap().to_bytes());
        assert!(parse_public_key(&[4; 65]).is_err());
    }
}
