//! The relay from ingress to APNs against real PostgreSQL and Redis and a fake APNs server. Runs when
//! `BETTERTG_TEST_DATABASE_URL` and `BETTERTG_TEST_REDIS_URL` are set, as in CI.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use bettertg_backend::apns::client::ApnsClient;
use bettertg_backend::config::Environment;
use bettertg_backend::db::{self, ApnsEnvironment};
use bettertg_backend::installations::{InstallationsService, NewInstallationRequest};
use bettertg_backend::queue::{Outcome, Queue};
use bettertg_backend::redis_store::RedisStore;
use bettertg_backend::security::{SecretBox, base64url};
use bettertg_backend::telemetry::Metrics;
use bettertg_backend::web_push::content_store::NotificationContentStore;
use bettertg_backend::web_push::ece;
use bettertg_backend::web_push::ingress::{WebPushHeaders, WebPushIngress};
use bettertg_backend::web_push::job::{RETRY_POLICY, TelegramWebPushJob};
use bettertg_backend::web_push::worker::WebPushProcessor;
use bytes::Bytes;
use p256::SecretKey;
use p256::ecdsa::SigningKey;
use p256::pkcs8::{EncodePrivateKey, LineEnding};
use rand::rngs::OsRng;
use serde_json::{Value, json};
use tokio::net::TcpListener;

type Requests = Arc<Mutex<Vec<(http::HeaderMap, Value)>>>;

/// An h2c APNs stand-in answering with the given statuses and reasons in turn.
async fn fake_apns(responses: Vec<(u16, Option<&'static str>)>) -> (String, Requests) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let requests: Requests = Default::default();
    let responses = Arc::new(Mutex::new(responses.into_iter()));
    let seen = requests.clone();
    tokio::spawn(async move {
        loop {
            let (socket, _) = listener.accept().await.unwrap();
            let seen = seen.clone();
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
                    seen.lock().unwrap().push((parts.headers, serde_json::from_slice(&bytes).unwrap()));
                    let (status, reason) = responses.lock().unwrap().next().unwrap_or((200, None));
                    let response = http::Response::builder().status(status).body(()).unwrap();
                    let mut stream = respond.send_response(response, reason.is_none()).unwrap();
                    if let Some(reason) = reason {
                        stream.send_data(Bytes::from(json!({ "reason": reason }).to_string()), true).unwrap();
                    }
                }
            });
        }
    });
    (format!("http://{address}"), requests)
}

struct Relay {
    pool: sqlx::PgPool,
    redis: RedisStore,
    installations: InstallationsService,
    ingress: WebPushIngress,
    processor: WebPushProcessor,
    queue: Queue,
}

async fn relay(apns_url: &str) -> Option<Relay> {
    let (Ok(database_url), Ok(redis_url)) =
        (std::env::var("BETTERTG_TEST_DATABASE_URL"), std::env::var("BETTERTG_TEST_REDIS_URL"))
    else {
        eprintln!("BETTERTG_TEST_DATABASE_URL and BETTERTG_TEST_REDIS_URL are not set; skipping");
        return None;
    };
    let key = SigningKey::random(&mut OsRng).to_pkcs8_pem(LineEnding::LF).unwrap().to_string();
    let variables: HashMap<String, String> = [
        ("APNS_DRY_RUN", "false"),
        ("APNS_SANDBOX_URL", apns_url),
        ("APNS_PRODUCTION_URL", apns_url),
        ("APNS_SANDBOX_KEY_ID", "SBXKEY0001"),
        ("APNS_SANDBOX_AUTH_KEY", key.as_str()),
        ("APNS_PRODUCTION_KEY_ID", "PRDKEY0001"),
        ("APNS_PRODUCTION_AUTH_KEY", key.as_str()),
    ]
    .into_iter()
    .map(|(key, value)| (key.to_owned(), value.to_owned()))
    .collect();
    let environment = Environment::from_map(&variables).unwrap();
    let pool = db::connect(&database_url).unwrap();
    db::migrations::run(&pool).await.unwrap();
    let redis = RedisStore::new(&redis_url).unwrap();
    let secret_box = Arc::new(
        SecretBox::new(
            &environment.encryption_current_key_id,
            &environment.encryption_keys,
            &environment.management_token_pepper,
        )
        .unwrap(),
    );
    let metrics = Arc::new(Metrics::new());
    let queue = Queue::new(redis.clone(), &format!("relay-test-{}", uuid::Uuid::new_v4()), RETRY_POLICY);
    Some(Relay {
        installations: InstallationsService {
            pool: pool.clone(),
            redis: redis.clone(),
            secret_box: secret_box.clone(),
            bundle_id: "com.levochkaaa.BetterTG".to_owned(),
            public_base_url: "https://push.example.com".to_owned(),
        },
        ingress: WebPushIngress {
            pool: pool.clone(),
            redis: redis.clone(),
            queue: queue.clone(),
            metrics: metrics.clone(),
        },
        processor: WebPushProcessor {
            pool: pool.clone(),
            secret_box,
            apns: ApnsClient::new(&environment, metrics.clone()).unwrap(),
            content_store: NotificationContentStore::new(redis.clone()),
            metrics,
        },
        queue,
        pool,
        redis,
    })
}

/// Registers an installation and subscription and pushes an encrypted Telegram message through the ingress.
async fn push(relay: &Relay, payload: &Value) -> uuid::Uuid {
    let created = relay
        .installations
        .create(
            &NewInstallationRequest {
                apns_token: &"AB".repeat(32),
                apns_environment: ApnsEnvironment::Sandbox,
                app_version: Some("test"),
                os_version: None,
            },
            None,
            &uuid::Uuid::new_v4().to_string(),
        )
        .await
        .unwrap();
    let installation = db::find_installation(&relay.pool, created.installation_id).await.unwrap().unwrap();
    let subscription = relay.installations.rotate_subscription(&installation).await.unwrap();
    let token = subscription.endpoint.rsplit('/').next().unwrap().to_owned();
    let receiver = ece::parse_public_key(&base64url::decode(&subscription.p256dh_base64url).unwrap()).unwrap();
    let auth_secret = base64url::decode(&subscription.auth_base64url).unwrap();
    let body = ece::encrypt_aes128gcm(
        payload.to_string().as_bytes(),
        &SecretKey::random(&mut OsRng),
        &receiver,
        &auth_secret,
        &[7; 16],
        4096,
    );
    let headers = WebPushHeaders { content_encoding: Some("aes128gcm"), ..Default::default() };
    relay.ingress.accept(&token, &body, &headers, "127.0.0.1").await.unwrap();
    assert!(relay.ingress.accept(&token, &body, &headers, "127.0.0.1").await.is_ok(), "duplicates are acknowledged");
    created.installation_id
}

async fn run_next(relay: &Relay) -> bool {
    let mut connection = relay.redis.client().get_multiplexed_async_connection().await.unwrap();
    let Some(lease) = relay.queue.take::<TelegramWebPushJob>(&mut connection, Duration::from_secs(1)).await.unwrap()
    else {
        return false;
    };
    let outcome = relay.processor.process(&lease.id, &lease.data).await;
    let retry = matches!(outcome, Outcome::Retry(_));
    relay.queue.settle(&lease, outcome).await.unwrap();
    retry
}

fn message() -> Value {
    json!({
        "loc_key": "CHAT_MESSAGE_TEXT",
        "loc_args": ["Alice", "Family", "Hello"],
        "user_id": 42,
        "custom": { "chat_id": 7, "msg_id": 9 },
    })
}

#[tokio::test]
async fn delivers_an_alert_and_serves_its_content_once() {
    let (apns_url, requests) = fake_apns(vec![(200, None)]).await;
    let Some(relay) = relay(&apns_url).await else { return };
    push(&relay, &message()).await;
    assert!(!run_next(&relay).await);
    assert_eq!(relay.queue.depth().await.unwrap(), 0, "one job for a duplicated push");

    let (headers, payload) = requests.lock().unwrap().pop().unwrap();
    assert_eq!(headers["apns-topic"], "com.levochkaaa.BetterTG");
    assert_eq!(headers["apns-push-type"], "alert");
    assert_eq!(payload["aps"]["alert"]["loc-key"], "CHAT_MESSAGE_TEXT");
    assert_eq!(payload["tg"]["conversation_title"], "Family");
    let token = payload["tg"]["notification_payload_token"].as_str().unwrap();
    let store = NotificationContentStore::new(relay.redis.clone());
    let content = store.take(token).await.unwrap().unwrap();
    assert_eq!(content["data"]["loc_args"], json!(["Alice", "Family", "Hello"]));
    assert!(store.take(token).await.unwrap().is_none());
}

#[tokio::test]
async fn retries_transient_apns_failures_and_disables_dead_tokens() {
    let (apns_url, requests) = fake_apns(vec![(503, Some("ServiceUnavailable")), (410, Some("Unregistered"))]).await;
    let Some(relay) = relay(&apns_url).await else { return };
    let installation_id = push(&relay, &message()).await;
    assert!(run_next(&relay).await, "503 retries");
    tokio::time::sleep(Duration::from_millis(1100)).await;
    relay.queue.promote_due().await.unwrap();
    assert!(!run_next(&relay).await);
    assert_eq!(requests.lock().unwrap().len(), 2);
    let installation = db::find_installation(&relay.pool, installation_id).await.unwrap().unwrap();
    assert_eq!(installation.status, "disabled");
}

#[tokio::test]
async fn drops_service_events_without_apns() {
    let (apns_url, requests) = fake_apns(vec![]).await;
    let Some(relay) = relay(&apns_url).await else { return };
    push(&relay, &json!({ "loc_key": "MESSAGE_MUTED", "custom": { "chat_id": 7 } })).await;
    assert!(!run_next(&relay).await);
    assert!(requests.lock().unwrap().is_empty());
}
