//! An APNs provider client: one persistent HTTP/2 connection per APNs host, token authentication with an ES256
//! provider JWT per environment, refreshed every 50 minutes or when APNs says it expired.

use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

use bytes::Bytes;
use h2::client::SendRequest;
use http::{Method, Request};
use opentelemetry::KeyValue;
use p256::ecdsa::signature::Signer;
use p256::ecdsa::{Signature, SigningKey};
use p256::pkcs8::DecodePrivateKey;
use serde_json::json;
use tokio::net::TcpStream;
use tokio::sync::Mutex;
use tracing::info;
use url::Url;

use super::{ApnsRequest, ApnsResult};
use crate::config::Environment;
use crate::db::ApnsEnvironment;
use crate::security::{base64url, decode_base64_lenient};
use crate::telemetry::Metrics;

const PROVIDER_TOKEN_LIFETIME: Duration = Duration::from_secs(50 * 60);
const MAXIMUM_RESPONSE_BYTES: usize = 4096;
const INVALID_TOKEN_REASONS: &[&str] = &["BadDeviceToken", "DeviceTokenNotForTopic", "ExpiredToken", "Unregistered"];

struct Credentials {
    key_id: String,
    signing_key: Option<SigningKey>,
    token: std::sync::Mutex<Option<(String, Instant)>>,
}

struct Connection {
    sender: SendRequest<Bytes>,
    generation: u64,
}

/// The connection to one APNs host. Its lock is held while connecting, so a slow host delays only its own sends.
type Slot = Arc<Mutex<Option<Connection>>>;

const UNUSED: u64 = u64::MAX;

pub struct ApnsClient {
    dry_run: bool,
    sandbox_url: String,
    production_url: String,
    request_timeout: Duration,
    team_id: String,
    sandbox: Credentials,
    production: Credentials,
    slots: HashMap<String, Slot>,
    generations: AtomicU64,
    metrics: Arc<Metrics>,
}

/// A `.p8` key as PEM, with escaped newlines allowed, or as base64-encoded PEM.
fn normalize_auth_key(value: &str) -> anyhow::Result<String> {
    if value.contains("BEGIN PRIVATE KEY") {
        return Ok(value.replace("\\n", "\n"));
    }
    let decoded = decode_base64_lenient(value).ok_or_else(|| anyhow::anyhow!("APNs auth key is not base64"))?;
    Ok(String::from_utf8(decoded)?)
}

fn credentials(key_id: &str, inline_key: &str, key_file: &str) -> anyhow::Result<Credentials> {
    let value = if !inline_key.is_empty() {
        inline_key.to_owned()
    } else if !key_file.is_empty() {
        std::fs::read_to_string(key_file)?
    } else {
        String::new()
    };
    let signing_key = if value.trim().is_empty() {
        None
    } else {
        Some(
            SigningKey::from_pkcs8_pem(&normalize_auth_key(&value)?)
                .map_err(|error| anyhow::anyhow!("APNs auth key is not a P-256 PKCS#8 key: {error}"))?,
        )
    };
    Ok(Credentials { key_id: key_id.to_owned(), signing_key, token: Default::default() })
}

fn parse_reason(body: &[u8]) -> Option<String> {
    serde_json::from_slice::<serde_json::Value>(body).ok()?.get("reason")?.as_str().map(str::to_owned)
}

impl ApnsClient {
    pub fn new(environment: &Environment, metrics: Arc<Metrics>) -> anyhow::Result<Self> {
        let mut slots = HashMap::new();
        for url in [&environment.apns_sandbox_url, &environment.apns_production_url] {
            slots.entry(url.clone()).or_insert_with(Slot::default);
        }
        Ok(Self {
            dry_run: environment.apns_dry_run,
            sandbox_url: environment.apns_sandbox_url.clone(),
            production_url: environment.apns_production_url.clone(),
            request_timeout: Duration::from_millis(environment.apns_request_timeout_ms),
            team_id: environment.apple_team_id.clone(),
            sandbox: credentials(
                &environment.apns_sandbox_key_id,
                &environment.apns_sandbox_auth_key,
                &environment.apns_sandbox_auth_key_file,
            )?,
            production: credentials(
                &environment.apns_production_key_id,
                &environment.apns_production_auth_key,
                &environment.apns_production_auth_key_file,
            )?,
            slots,
            generations: AtomicU64::new(0),
            metrics,
        })
    }

    pub async fn send(&self, request: &ApnsRequest) -> ApnsResult {
        let payload = request.command.payload.to_string();
        if payload.len() > 4096 {
            return ApnsResult::Permanent { status: None, reason: Some("PayloadTooLarge".to_owned()) };
        }
        if self.dry_run {
            return ApnsResult::Success;
        }
        let credentials = match request.environment {
            ApnsEnvironment::Sandbox => &self.sandbox,
            ApnsEnvironment::Production => &self.production,
        };
        let Some(provider_token) = self.provider_token(credentials) else {
            return ApnsResult::Permanent { status: None, reason: Some("MissingProviderCredentials".to_owned()) };
        };
        let authority = match request.environment {
            ApnsEnvironment::Sandbox => &self.sandbox_url,
            ApnsEnvironment::Production => &self.production_url,
        };

        let mut builder = Request::builder()
            .method(Method::POST)
            .uri(format!("{}/3/device/{}", authority.trim_end_matches('/'), request.device_token))
            .header("authorization", format!("bearer {provider_token}"))
            .header("apns-id", &request.command.delivery_id)
            .header("apns-topic", &request.topic)
            .header("apns-push-type", request.command.push_type.as_str())
            .header("apns-priority", request.command.priority)
            .header("apns-expiration", &request.command.expiration);
        if let Some(collapse_id) = &request.command.collapse_id {
            builder = builder.header("apns-collapse-id", collapse_id);
        }
        let Ok(http_request) = builder.body(()) else {
            return ApnsResult::Permanent { status: None, reason: Some("InvalidRequest".to_owned()) };
        };

        // A connection that fails or stops answering is dropped, so the next send opens a fresh one instead of
        // writing into a half-open socket.
        let used = AtomicU64::new(UNUSED);
        let attempt = async {
            let (sender, generation) = self.connection(authority).await.map_err(|_| "ConnectionError")?;
            used.store(generation, Ordering::Relaxed);
            Self::perform(sender, http_request, payload.into()).await
        };
        let result = tokio::time::timeout(self.request_timeout, attempt).await;
        let reason = match result {
            Ok(Ok((status, body))) => return self.classify(status, &body, credentials),
            Ok(Err(reason)) => reason,
            Err(_) => "Timeout",
        };
        let generation = used.load(Ordering::Relaxed);
        if generation != UNUSED {
            self.forget(authority, generation).await;
        }
        ApnsResult::Retryable { status: None, reason: Some(reason.to_owned()) }
    }

    async fn perform(
        sender: SendRequest<Bytes>,
        request: Request<()>,
        payload: Bytes,
    ) -> Result<(u16, Vec<u8>), &'static str> {
        let mut sender = sender.ready().await.map_err(|_| "ConnectionError")?;
        let (response, mut stream) = sender.send_request(request, false).map_err(|_| "StreamError")?;
        stream.send_data(payload, true).map_err(|_| "StreamError")?;
        let response = response.await.map_err(|_| "StreamError")?;
        let status = response.status().as_u16();
        let mut body = response.into_body();
        let mut collected = Vec::new();
        while let Some(chunk) = body.data().await {
            let chunk = chunk.map_err(|_| "StreamError")?;
            let _ = body.flow_control().release_capacity(chunk.len());
            if collected.len() < MAXIMUM_RESPONSE_BYTES {
                collected.extend_from_slice(&chunk);
            }
        }
        Ok((status, collected))
    }

    fn classify(&self, status: u16, body: &[u8], credentials: &Credentials) -> ApnsResult {
        if status == 200 {
            return ApnsResult::Success;
        }
        let reason = parse_reason(body);
        if reason.as_deref() == Some("ExpiredProviderToken") {
            *credentials.token.lock().expect("token lock") = None;
        }
        if matches!(status, 429 | 500 | 503)
            || matches!(reason.as_deref(), Some("TooManyRequests" | "ExpiredProviderToken"))
        {
            return ApnsResult::Retryable { status: Some(status), reason };
        }
        match reason {
            Some(reason) if INVALID_TOKEN_REASONS.contains(&reason.as_str()) => {
                ApnsResult::InvalidToken { status, reason }
            }
            reason => ApnsResult::Permanent { status: Some(status), reason },
        }
    }

    fn provider_token(&self, credentials: &Credentials) -> Option<String> {
        let signing_key = credentials.signing_key.as_ref()?;
        if credentials.key_id.is_empty() || self.team_id.is_empty() {
            return None;
        }
        let mut cached = credentials.token.lock().expect("token lock");
        if let Some((token, created_at)) = cached.as_ref()
            && created_at.elapsed() < PROVIDER_TOKEN_LIFETIME
        {
            return Some(token.clone());
        }
        let issued_at = time::OffsetDateTime::now_utc().unix_timestamp();
        let header = base64url::encode(json!({ "alg": "ES256", "typ": "JWT", "kid": credentials.key_id }).to_string());
        let claims = base64url::encode(json!({ "iss": self.team_id, "iat": issued_at }).to_string());
        let signing_input = format!("{header}.{claims}");
        let signature: Signature = signing_key.sign(signing_input.as_bytes());
        let token = format!("{signing_input}.{}", base64url::encode(signature.to_bytes()));
        *cached = Some((token.clone(), Instant::now()));
        Some(token)
    }

    fn slot(&self, authority: &str) -> anyhow::Result<&Slot> {
        self.slots.get(authority).ok_or_else(|| anyhow::anyhow!("unknown APNs host"))
    }

    async fn connection(&self, authority: &str) -> anyhow::Result<(SendRequest<Bytes>, u64)> {
        let mut slot = self.slot(authority)?.lock().await;
        if let Some(connection) = slot.as_ref() {
            return Ok((connection.sender.clone(), connection.generation));
        }
        let url = Url::parse(authority)?;
        let host = url.host_str().ok_or_else(|| anyhow::anyhow!("APNs URL has no host"))?.to_owned();
        let port = url.port_or_known_default().unwrap_or(443);
        let tcp = TcpStream::connect((host.as_str(), port)).await?;
        tcp.set_nodelay(true)?;
        socket2::SockRef::from(&tcp).set_tcp_keepalive(
            &socket2::TcpKeepalive::new().with_time(Duration::from_secs(30)).with_interval(Duration::from_secs(10)),
        )?;
        let generation = self.generations.fetch_add(1, Ordering::Relaxed);
        let sender = if url.scheme() == "https" {
            let mut roots = rustls::RootCertStore::empty();
            roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
            let mut config = rustls::ClientConfig::builder().with_root_certificates(roots).with_no_client_auth();
            config.alpn_protocols = vec![b"h2".to_vec()];
            let server_name = rustls::pki_types::ServerName::try_from(host.clone())?;
            let tls = tokio_rustls::TlsConnector::from(Arc::new(config)).connect(server_name, tcp).await?;
            let (sender, connection) = h2::client::handshake(tls).await?;
            self.watch(authority, generation, connection)?;
            sender
        } else {
            // Plain-text HTTP/2 with prior knowledge, for local test servers only.
            let (sender, connection) = h2::client::handshake(tcp).await?;
            self.watch(authority, generation, connection)?;
            sender
        };
        self.event("connect", authority);
        info!(event = "apns.connection.opened", authority);
        *slot = Some(Connection { sender: sender.clone(), generation });
        Ok((sender, generation))
    }

    /// Drives the connection and forgets it once APNs closes it, sends GOAWAY or fails.
    fn watch<T>(
        &self,
        authority: &str,
        generation: u64,
        connection: h2::client::Connection<T, Bytes>,
    ) -> anyhow::Result<()>
    where
        T: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
    {
        let slot = self.slot(authority)?.clone();
        let metrics = self.metrics.clone();
        let authority = authority.to_owned();
        tokio::spawn(async move {
            let event = match connection.await {
                Ok(()) => "close",
                Err(error) if error.is_go_away() => "goaway",
                Err(_) => "error",
            };
            metrics
                .apns_connection_events
                .add(1, &[KeyValue::new("event", event), KeyValue::new("authority", authority)]);
            let mut slot = slot.lock().await;
            if slot.as_ref().is_some_and(|connection| connection.generation == generation) {
                *slot = None;
            }
        });
        Ok(())
    }

    /// Drops the connection `generation`, unless a newer one has replaced it.
    async fn forget(&self, authority: &str, generation: u64) {
        let Ok(slot) = self.slot(authority) else { return };
        let mut slot = slot.lock().await;
        if slot.as_ref().is_some_and(|connection| connection.generation == generation) {
            *slot = None;
        }
    }

    fn event(&self, event: &'static str, authority: &str) {
        self.metrics
            .apns_connection_events
            .add(1, &[KeyValue::new("event", event), KeyValue::new("authority", authority.to_owned())]);
    }

    /// Closes every connection: dropping the last sender lets each connection finish and close.
    pub async fn close(&self) {
        for slot in self.slots.values() {
            *slot.lock().await = None;
        }
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap as Map;

    use p256::pkcs8::{EncodePrivateKey, LineEnding};
    use rand::rngs::OsRng;
    use tokio::net::TcpListener;

    use super::*;
    use crate::apns::{ApnsCommand, PushType};

    struct Seen {
        sessions: usize,
        requests: Vec<(http::HeaderMap, Vec<u8>)>,
    }

    /// An h2c server that answers each request with the next canned response.
    async fn server(responses: Vec<(u16, Option<&'static str>)>) -> (String, Arc<std::sync::Mutex<Seen>>) {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let seen = Arc::new(std::sync::Mutex::new(Seen { sessions: 0, requests: Vec::new() }));
        let responses = Arc::new(std::sync::Mutex::new(responses.into_iter()));
        let shared = seen.clone();
        tokio::spawn(async move {
            loop {
                let (socket, _) = listener.accept().await.unwrap();
                shared.lock().unwrap().sessions += 1;
                let seen = shared.clone();
                let responses = responses.clone();
                tokio::spawn(async move {
                    let mut connection = h2::server::handshake(socket).await.unwrap();
                    while let Some(Ok((request, mut respond))) = connection.accept().await {
                        let (parts, mut body) = request.into_parts();
                        let mut bytes = Vec::new();
                        while let Some(Ok(chunk)) = body.data().await {
                            let _ = body.flow_control().release_capacity(chunk.len());
                            bytes.extend_from_slice(&chunk);
                        }
                        seen.lock().unwrap().requests.push((parts.headers, bytes));
                        let (status, reason) = responses.lock().unwrap().next().unwrap_or((500, None));
                        if status == 0 {
                            // Stop answering, as a half-open connection would.
                            std::future::pending::<()>().await;
                        }
                        let response = http::Response::builder().status(status).body(()).unwrap();
                        match reason {
                            None => {
                                respond.send_response(response, true).unwrap();
                            }
                            Some(reason) => {
                                let mut stream = respond.send_response(response, false).unwrap();
                                let body = json!({ "reason": reason }).to_string();
                                stream.send_data(Bytes::from(body), true).unwrap();
                            }
                        }
                    }
                });
            }
        });
        (format!("http://{address}"), seen)
    }

    fn client(endpoint: &str) -> ApnsClient {
        let key = SigningKey::random(&mut OsRng).to_pkcs8_pem(LineEnding::LF).unwrap().to_string();
        let variables: Map<String, String> = [
            ("APNS_DRY_RUN", "false"),
            ("APNS_SANDBOX_URL", endpoint),
            ("APNS_PRODUCTION_URL", endpoint),
            ("APNS_REQUEST_TIMEOUT_MS", "1000"),
            ("APPLE_TEAM_ID", "KLMNOPQRST"),
            ("APNS_SANDBOX_KEY_ID", "SBXKEY0001"),
            ("APNS_SANDBOX_AUTH_KEY", &key),
            ("APNS_PRODUCTION_KEY_ID", "PRDKEY0001"),
            ("APNS_PRODUCTION_AUTH_KEY", &key.replace('\n', "\\n")),
        ]
        .into_iter()
        .map(|(key, value)| (key.to_owned(), value.to_owned()))
        .collect();
        let environment = Environment::from_map(&variables).unwrap();
        ApnsClient::new(&environment, Arc::new(Metrics::new())).unwrap()
    }

    fn request(environment: ApnsEnvironment) -> ApnsRequest {
        ApnsRequest {
            device_token: "a".repeat(64),
            environment,
            topic: "com.example.App".to_owned(),
            command: ApnsCommand {
                delivery_id: "123e4567-e89b-52d3-a456-426614174000".to_owned(),
                push_type: PushType::Alert,
                priority: "10",
                expiration: "0".to_owned(),
                collapse_id: None,
                payload: json!({ "aps": { "alert": "Hello" } }),
            },
        }
    }

    fn key_id(headers: &http::HeaderMap) -> String {
        let token = headers["authorization"].to_str().unwrap().strip_prefix("bearer ").unwrap().to_owned();
        let header: serde_json::Value =
            serde_json::from_slice(&base64url::decode(token.split('.').next().unwrap()).unwrap()).unwrap();
        assert_eq!(header["alg"], "ES256");
        header["kid"].as_str().unwrap().to_owned()
    }

    #[tokio::test]
    async fn sends_apns_headers_and_reuses_one_http2_session() {
        let (endpoint, seen) = server(vec![(200, None), (200, None), (200, None)]).await;
        let client = client(&endpoint);
        assert_eq!(client.send(&request(ApnsEnvironment::Sandbox)).await, ApnsResult::Success);
        assert_eq!(client.send(&request(ApnsEnvironment::Sandbox)).await, ApnsResult::Success);
        assert_eq!(client.send(&request(ApnsEnvironment::Production)).await, ApnsResult::Success);
        let seen = seen.lock().unwrap();
        assert_eq!(seen.sessions, 1);
        assert_eq!(seen.requests.len(), 3);
        let key_ids: Vec<_> = seen.requests.iter().map(|(headers, _)| key_id(headers)).collect();
        assert_eq!(key_ids, ["SBXKEY0001", "SBXKEY0001", "PRDKEY0001"]);
        let (headers, body) = seen.requests.last().unwrap();
        assert_eq!(headers["apns-topic"], "com.example.App");
        assert_eq!(headers["apns-push-type"], "alert");
        assert_eq!(headers["apns-id"], "123e4567-e89b-52d3-a456-426614174000");
        assert_eq!(serde_json::from_slice::<serde_json::Value>(body).unwrap(), json!({ "aps": { "alert": "Hello" } }));
    }

    #[tokio::test]
    async fn classifies_retryable_and_invalid_token_responses() {
        let (endpoint, _) = server(vec![
            (503, Some("Shutdown")),
            (403, Some("ExpiredProviderToken")),
            (410, Some("Unregistered")),
            (400, Some("BadTopic")),
        ])
        .await;
        let client = client(&endpoint);
        let production = request(ApnsEnvironment::Production);
        assert_eq!(
            client.send(&production).await,
            ApnsResult::Retryable { status: Some(503), reason: Some("Shutdown".to_owned()) }
        );
        assert_eq!(
            client.send(&production).await,
            ApnsResult::Retryable { status: Some(403), reason: Some("ExpiredProviderToken".to_owned()) }
        );
        assert!(client.production.token.lock().unwrap().is_none());
        assert_eq!(
            client.send(&production).await,
            ApnsResult::InvalidToken { status: 410, reason: "Unregistered".to_owned() }
        );
        assert_eq!(
            client.send(&production).await,
            ApnsResult::Permanent { status: Some(400), reason: Some("BadTopic".to_owned()) }
        );
    }

    #[tokio::test]
    async fn drops_a_connection_that_stops_answering() {
        let (endpoint, seen) = server(vec![(0, None), (200, None)]).await;
        let client = client(&endpoint);
        assert_eq!(
            client.send(&request(ApnsEnvironment::Sandbox)).await,
            ApnsResult::Retryable { status: None, reason: Some("Timeout".to_owned()) }
        );
        assert_eq!(client.send(&request(ApnsEnvironment::Sandbox)).await, ApnsResult::Success);
        assert_eq!(seen.lock().unwrap().sessions, 2);
    }

    #[tokio::test]
    async fn reports_an_unreachable_host_as_retryable() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = format!("http://{}", listener.local_addr().unwrap());
        drop(listener);
        let result = client(&endpoint).send(&request(ApnsEnvironment::Sandbox)).await;
        assert_eq!(result.kind(), "retryable");
    }

    #[tokio::test]
    async fn refuses_oversized_payloads_and_succeeds_in_dry_run() {
        let environment = Environment::from_map(&Map::new()).unwrap();
        let client = ApnsClient::new(&environment, Arc::new(Metrics::new())).unwrap();
        let mut oversized = request(ApnsEnvironment::Sandbox);
        oversized.command.payload = json!({ "aps": { "alert": "x".repeat(5000) } });
        assert_eq!(client.send(&oversized).await.kind(), "permanent");
        assert_eq!(client.send(&request(ApnsEnvironment::Sandbox)).await, ApnsResult::Success);
    }
}
