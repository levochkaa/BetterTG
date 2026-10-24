//! End-to-end relay check against a running API and worker: creates an installation and a subscription, sends an
//! encrypted Web Push in both encodings, checks the receipt and deduplication, waits for the worker to finish the
//! job when `SMOKE_REDIS_URL` is set, and deletes the installation.

use std::time::Duration;

use bettertg_backend::security::{base64url, random_bytes};
use bettertg_backend::web_push::ece;
use p256::SecretKey;
use rand::rngs::OsRng;
use redis::AsyncCommands;
use serde_json::{Value, json};
use url::Url;
use uuid::Uuid;

#[derive(Clone, Copy)]
enum Encoding {
    Aes128gcm,
    Aesgcm,
}

impl Encoding {
    fn name(self) -> &'static str {
        match self {
            Self::Aes128gcm => "aes128gcm",
            Self::Aesgcm => "aesgcm",
        }
    }
}

async fn checked(response: reqwest::Response, operation: &str) -> anyhow::Result<Value> {
    if !response.status().is_success() {
        anyhow::bail!("{operation} failed with HTTP {}", response.status());
    }
    Ok(response.json().await?)
}

async fn verify(http: &reqwest::Client, base_url: &Url, encoding: Encoding) -> anyhow::Result<()> {
    let installation = checked(
        http.post(base_url.join("api/v1/installations")?)
            .header("idempotency-key", Uuid::new_v4().to_string())
            .json(&json!({
                "apnsToken": hex::encode(random_bytes::<32>()),
                "apnsEnvironment": "sandbox",
                "appVersion": "smoke",
                "osVersion": std::env::consts::OS,
            }))
            .send()
            .await?,
        "installation creation",
    )
    .await?;
    let installation_id = installation["installationId"].as_str().unwrap_or_default().to_owned();
    let authorization = format!("Bearer {}", installation["managementSecret"].as_str().unwrap_or_default());
    let result = deliver(http, base_url, encoding, &installation_id, &authorization).await;
    let _ = http
        .delete(base_url.join(&format!("api/v1/installations/{installation_id}"))?)
        .header("authorization", &authorization)
        .send()
        .await;
    result
}

async fn deliver(
    http: &reqwest::Client,
    base_url: &Url,
    encoding: Encoding,
    installation_id: &str,
    authorization: &str,
) -> anyhow::Result<()> {
    let subscription = checked(
        http.post(base_url.join(&format!("api/v1/installations/{installation_id}/telegram-subscriptions"))?)
            .header("authorization", authorization)
            .send()
            .await?,
        "subscription creation",
    )
    .await?;
    // The endpoint names the public host; the smoke check talks to the API directly.
    let mut endpoint = Url::parse(subscription["endpoint"].as_str().unwrap_or_default())?;
    endpoint.set_scheme(base_url.scheme()).map_err(|_| anyhow::anyhow!("scheme"))?;
    endpoint.set_host(base_url.host_str())?;
    endpoint.set_port(base_url.port()).map_err(|_| anyhow::anyhow!("port"))?;

    let receiver =
        ece::parse_public_key(&base64url::decode(subscription["p256dhBase64url"].as_str().unwrap_or_default())?)
            .map_err(|error| anyhow::anyhow!("subscription key: {error}"))?;
    let auth_secret = base64url::decode(subscription["authBase64url"].as_str().unwrap_or_default())?;
    let sender = SecretKey::random(&mut OsRng);
    let salt = random_bytes::<16>();
    let message_id = match encoding {
        Encoding::Aes128gcm => 3,
        Encoding::Aesgcm => 4,
    };
    let plaintext = json!({ "data": {
        "loc_key": "MESSAGE_TEXT",
        "loc_args": ["Smoke", format!("{} relay verified", encoding.name())],
        "user_id": 1,
        "custom": { "from_id": 2, "msg_id": message_id },
    }})
    .to_string();
    let mut request = http
        .post(endpoint.clone())
        .header("content-type", "application/octet-stream")
        .header("content-encoding", encoding.name())
        .header("ttl", "60");
    let body = match encoding {
        Encoding::Aes128gcm => {
            ece::encrypt_aes128gcm(plaintext.as_bytes(), &sender, &receiver, &auth_secret, &salt, 4096)
        }
        Encoding::Aesgcm => {
            request = request
                .header("encryption", format!("salt={}", base64url::encode(salt)))
                .header("crypto-key", format!("dh={}", base64url::encode(ece::public_key_bytes(&sender))));
            ece::encrypt_aesgcm(plaintext.as_bytes(), &sender, &receiver, &auth_secret, &salt, 4096)
        }
    };
    let request = request.body(body);
    let first = request.try_clone().expect("buffered body").send().await?;
    let location = first.headers().get("location").and_then(|value| value.to_str().ok()).map(str::to_owned);
    let (201, Some(location)) = (first.status().as_u16(), location) else {
        anyhow::bail!("{} ingress failed with HTTP {}", encoding.name(), first.status());
    };
    let duplicate = request.send().await?;
    if duplicate.status().as_u16() != 201 {
        anyhow::bail!("{} deduplicated ingress failed with HTTP {}", encoding.name(), duplicate.status());
    }

    let Ok(redis_url) = std::env::var("SMOKE_REDIS_URL") else {
        tokio::time::sleep(Duration::from_millis(500)).await;
        return Ok(());
    };
    let digest = location.rsplit('/').next().unwrap_or_default();
    let job_key =
        format!("queue:telegram-web-push:job:{}-{digest}", subscription["subscriptionId"].as_str().unwrap_or_default());
    let mut redis = redis::Client::open(redis_url)?.get_multiplexed_async_connection().await?;
    for _ in 0..50 {
        if !redis.exists::<_, bool>(&job_key).await? {
            return Ok(());
        }
        if let Some(reason) = redis.hget::<_, _, Option<String>>(&job_key, "failed_reason").await? {
            anyhow::bail!("relay worker failed the smoke job: {reason}");
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    anyhow::bail!("relay worker did not complete the smoke job")
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = rustls::crypto::ring::default_provider().install_default();
    let mut base_url =
        Url::parse(&std::env::var("SMOKE_BASE_URL").unwrap_or_else(|_| "http://localhost:8080".to_owned()))?;
    if !base_url.path().ends_with('/') {
        base_url.set_path(&format!("{}/", base_url.path()));
    }
    let http = reqwest::Client::builder().timeout(Duration::from_secs(15)).build()?;
    verify(&http, &base_url, Encoding::Aes128gcm).await?;
    verify(&http, &base_url, Encoding::Aesgcm).await?;
    println!("Encrypted Web Push relay smoke passed for aes128gcm and aesgcm");
    Ok(())
}
