//! The worker: decrypts queued pushes, classifies them and sends the result to APNs, 20 at a time.

use std::sync::Arc;
use std::time::{Duration, Instant};

use base64::Engine as _;
use opentelemetry::KeyValue;
use sqlx::PgPool;
use time::OffsetDateTime;
use tokio::sync::{Semaphore, watch};
use tracing::{error, info, warn};

use super::classifier::{PushAction, classify};
use super::content_store::NotificationContentStore;
use super::decryptor::decrypt_telegram_payload;
use super::job::TelegramWebPushJob;
use crate::apns::client::ApnsClient;
use crate::apns::mapper::ApnsPayloadMapper;
use crate::apns::{ApnsRequest, ApnsResult};
use crate::db;
use crate::queue::{Lease, Outcome, Queue};
use crate::security::SecretBox;
use crate::telemetry::Metrics;

const CONCURRENCY: usize = 20;

pub struct WebPushProcessor {
    pub pool: PgPool,
    pub secret_box: Arc<SecretBox>,
    pub apns: ApnsClient,
    pub content_store: NotificationContentStore,
    pub metrics: Arc<Metrics>,
}

impl WebPushProcessor {
    /// Processes one job. Transient failures retry; a push that can't be read never will be, so it fails at once.
    pub async fn process(&self, job_id: &str, job: &TelegramWebPushJob) -> Outcome {
        let started = Instant::now();
        let outcome = self.deliver(job_id, job).await;
        self.metrics.processing_duration.record(started.elapsed().as_secs_f64() * 1000.0, &[]);
        outcome
    }

    async fn deliver(&self, job_id: &str, job: &TelegramWebPushJob) -> Outcome {
        let subscription = match db::find_subscription(&self.pool, job.subscription_id).await {
            Ok(Some(subscription)) if subscription.installation_status == "active" => subscription,
            Ok(_) => return Outcome::Completed,
            Err(error) => return Outcome::Retry(format!("database: {error}")),
        };
        let Ok(ciphertext) = base64::engine::general_purpose::STANDARD.decode(&job.ciphertext_base64) else {
            return Outcome::Fail("unreadable ciphertext".to_owned());
        };
        let payload = match decrypt_telegram_payload(&self.secret_box, &subscription, &ciphertext, &job.encryption) {
            Ok(payload) => payload,
            Err(invalid) => {
                self.metrics.decryption_failures.add(1, &[]);
                warn!(
                    event = "webpush.decryption_failed",
                    subscriptionId = %subscription.id,
                    reason = invalid.reason,
                );
                return Outcome::Fail(invalid.to_string());
            }
        };
        let loc_key = payload.data.loc_key.clone();
        let action = classify(&loc_key);
        self.metrics
            .classification
            .add(1, &[KeyValue::new("loc_key", loc_key.clone()), KeyValue::new("action", action.as_str())]);

        let custom = &payload.data.custom;
        let has_conversation = [&custom.from_id, &custom.chat_id, &custom.channel_id]
            .into_iter()
            .any(|identifier| identifier.as_ref().is_some_and(|identifier| identifier.is_truthy()));
        let content_token = if action == PushAction::Alert && has_conversation {
            match self.content_store.put(&payload.json).await {
                Ok(token) => Some(token),
                Err(error) => return Outcome::Retry(format!("redis: {error}")),
            }
        } else {
            None
        };
        let mapper = ApnsPayloadMapper { secret_box: &self.secret_box };
        let command = match mapper.map(action, &payload, job_id, OffsetDateTime::now_utc(), content_token.as_deref()) {
            Ok(Some(command)) => command,
            Ok(None) => {
                info!(
                    event = "webpush.ignored",
                    subscriptionId = %subscription.id,
                    locKey = %loc_key,
                    action = action.as_str(),
                );
                return Outcome::Completed;
            }
            Err(error) => return Outcome::Fail(error.to_string()),
        };

        let installation = match db::find_installation(&self.pool, subscription.installation_id).await {
            Ok(Some(installation)) => installation,
            Ok(None) => return Outcome::Completed,
            Err(error) => return Outcome::Retry(format!("database: {error}")),
        };
        let device_token = match self
            .secret_box
            .decrypt(&installation.apns_token_encrypted, &format!("installation:{}:apns-token", installation.id))
            .map(String::from_utf8)
        {
            Ok(Ok(token)) => token,
            _ => return Outcome::Fail("unreadable APNs token".to_owned()),
        };
        let push_type = command.push_type;
        let result = self
            .apns
            .send(&ApnsRequest {
                device_token,
                environment: installation.environment(),
                topic: installation.bundle_id.clone(),
                command,
            })
            .await;
        self.metrics.apns_requests.add(
            1,
            &[
                KeyValue::new("status", result.kind()),
                KeyValue::new("push_type", push_type.as_str()),
                KeyValue::new(
                    "reason",
                    match &result {
                        ApnsResult::Success => "none".to_owned(),
                        other => other.reason().unwrap_or("unknown").to_owned(),
                    },
                ),
            ],
        );

        match &result {
            ApnsResult::Retryable { reason, .. } => {
                Outcome::Retry(reason.clone().unwrap_or_else(|| "retryable APNs failure".to_owned()))
            }
            ApnsResult::Success => {
                info!(
                    event = "apns.delivered",
                    subscriptionId = %subscription.id,
                    locKey = %loc_key,
                    pushType = push_type.as_str(),
                );
                Outcome::Completed
            }
            ApnsResult::InvalidToken { .. } | ApnsResult::Permanent { .. } => {
                if matches!(result, ApnsResult::InvalidToken { .. })
                    && let Err(error) = db::disable_installation(&self.pool, installation.id).await
                {
                    return Outcome::Retry(format!("database: {error}"));
                }
                warn!(
                    event = "apns.delivery_failed",
                    subscriptionId = %subscription.id,
                    locKey = %loc_key,
                    result = result.kind(),
                    reason = result.reason().unwrap_or_default(),
                );
                Outcome::Completed
            }
        }
    }
}

/// Takes jobs until `shutdown` turns true, then lets the running ones finish.
pub async fn run(
    queue: Queue,
    processor: Arc<WebPushProcessor>,
    mut shutdown: watch::Receiver<bool>,
) -> anyhow::Result<()> {
    let slots = Arc::new(Semaphore::new(CONCURRENCY));
    let maintenance = tokio::spawn(maintain(queue.clone(), shutdown.clone()));
    let mut connection = None;
    while !*shutdown.borrow() {
        let permit = tokio::select! {
            permit = slots.clone().acquire_owned() => permit?,
            _ = shutdown.changed() => break,
        };
        if connection.is_none() {
            match queue_connection(&queue).await {
                Ok(opened) => connection = Some(opened),
                Err(error) => {
                    error!(event = "worker.redis_unavailable", error = %error);
                    tokio::time::sleep(Duration::from_secs(1)).await;
                    continue;
                }
            }
        }
        let lease: Lease<TelegramWebPushJob> =
            match queue.take(connection.as_mut().expect("connected"), Duration::from_secs(1)).await {
                Ok(Some(lease)) => lease,
                Ok(None) => continue,
                Err(error) => {
                    error!(event = "worker.take_failed", error = %error);
                    connection = None;
                    tokio::time::sleep(Duration::from_secs(1)).await;
                    continue;
                }
            };
        tokio::spawn(handle(queue.clone(), processor.clone(), lease, permit));
    }
    maintenance.abort();
    // Running jobs hold the permits; wait for them, at most 30 seconds.
    let _ = tokio::time::timeout(Duration::from_secs(30), slots.acquire_many(CONCURRENCY as u32)).await;
    processor.apns.close().await;
    Ok(())
}

/// A connection for the blocking take, whose replies may wait as long as the take's own timeout.
/// Runs one job with its lock renewed, and records the outcome. A panic counts as a failed attempt.
async fn handle(
    queue: Queue,
    processor: Arc<WebPushProcessor>,
    lease: Lease<TelegramWebPushJob>,
    _permit: tokio::sync::OwnedSemaphorePermit,
) {
    let renewal = {
        let queue = queue.clone();
        let lock = lease.lock();
        AbortOnDrop(tokio::spawn(async move {
            let mut interval = tokio::time::interval(queue.lock_renewal_interval());
            interval.tick().await;
            loop {
                interval.tick().await;
                if let Ok(false) = queue.extend(&lock).await {
                    return;
                }
            }
        }))
    };
    let (id, data) = (lease.id.clone(), lease.data.clone());
    let outcome = tokio::spawn(async move { processor.process(&id, &data).await })
        .await
        .unwrap_or_else(|_| Outcome::Retry("processing panicked".to_owned()));
    drop(renewal);
    match queue.settle(&lease, outcome).await {
        Ok(true) => {}
        Ok(false) => warn!(event = "worker.lease_lost"),
        Err(error) => error!(event = "worker.settle_failed", error = %error),
    }
}

/// Stops a task when its owner goes away, however it goes.
struct AbortOnDrop<T>(tokio::task::JoinHandle<T>);

impl<T> Drop for AbortOnDrop<T> {
    fn drop(&mut self) {
        self.0.abort();
    }
}

async fn queue_connection(queue: &Queue) -> redis::RedisResult<redis::aio::MultiplexedConnection> {
    let config = redis::AsyncConnectionConfig::new()
        .set_connection_timeout(Some(Duration::from_secs(5)))
        .set_response_timeout(Some(Duration::from_secs(10)));
    queue.redis().client().get_multiplexed_async_connection_with_config(&config).await
}

/// Promotes due retries twice a second and looks for stalled jobs every stall interval.
async fn maintain(queue: Queue, mut shutdown: watch::Receiver<bool>) {
    let mut promote = tokio::time::interval(Duration::from_millis(500));
    let mut stalled = tokio::time::interval(queue.stall_interval());
    loop {
        tokio::select! {
            _ = promote.tick() => {
                if let Err(error) = queue.promote_due().await {
                    warn!(event = "worker.promote_failed", error = %error);
                }
            }
            _ = stalled.tick() => {
                match queue.recover_stalled().await {
                    Ok(0) => {}
                    Ok(count) => warn!(event = "worker.stalled_jobs_requeued", count),
                    Err(error) => warn!(event = "worker.stall_check_failed", error = %error),
                }
            }
            _ = shutdown.changed() => return,
        }
    }
}
