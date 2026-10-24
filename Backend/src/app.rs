//! Wiring for the API and worker processes, and their graceful shutdown.

use std::net::SocketAddr;
use std::sync::Arc;

use tokio::sync::watch;
use tracing::{error, info};

use crate::apns::client::ApnsClient;
use crate::app_attest::AppAttestService;
use crate::config::Environment;
use crate::db;
use crate::http::{AppState, router};
use crate::installations::InstallationsService;
use crate::queue::Queue;
use crate::redis_store::RedisStore;
use crate::security::SecretBox;
use crate::telemetry::Metrics;
use crate::web_push::content_store::NotificationContentStore;
use crate::web_push::ingress::WebPushIngress;
use crate::web_push::job::{RETRY_POLICY, TELEGRAM_WEB_PUSH_QUEUE};
use crate::web_push::worker::{self, WebPushProcessor};

fn secret_box(environment: &Environment) -> anyhow::Result<Arc<SecretBox>> {
    Ok(Arc::new(SecretBox::new(
        &environment.encryption_current_key_id,
        &environment.encryption_keys,
        &environment.management_token_pepper,
    )?))
}

/// Turns true on SIGINT or SIGTERM.
fn shutdown_signal() -> watch::Receiver<bool> {
    let (sender, receiver) = watch::channel(false);
    tokio::spawn(async move {
        let interrupt = tokio::signal::ctrl_c();
        #[cfg(unix)]
        let terminate = async {
            if let Ok(mut signal) = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
                signal.recv().await;
            }
        };
        #[cfg(not(unix))]
        let terminate = std::future::pending::<()>();
        tokio::select! {
            _ = interrupt => {}
            _ = terminate => {}
        }
        let _ = sender.send(true);
    });
    receiver
}

pub fn state(environment: Environment) -> anyhow::Result<AppState> {
    let environment = Arc::new(environment);
    let secret_box = secret_box(&environment)?;
    let pool = db::connect(&environment.database_url)?;
    let redis = RedisStore::new(&environment.redis_url)?;
    let metrics = Arc::new(Metrics::new());
    Ok(AppState {
        installations: InstallationsService {
            pool: pool.clone(),
            redis: redis.clone(),
            secret_box: secret_box.clone(),
            bundle_id: environment.bundle_id.clone(),
            public_base_url: environment.public_base_url.clone(),
        },
        app_attest: AppAttestService::new(&environment, pool.clone(), redis.clone(), secret_box),
        ingress: WebPushIngress {
            pool: pool.clone(),
            redis: redis.clone(),
            queue: Queue::new(redis.clone(), TELEGRAM_WEB_PUSH_QUEUE, RETRY_POLICY),
            metrics,
        },
        content_store: NotificationContentStore::new(redis.clone()),
        environment,
        pool,
        redis,
    })
}

pub async fn run_api(environment: Environment) -> anyhow::Result<()> {
    let port = environment.port;
    let state = state(environment)?;
    let listener = tokio::net::TcpListener::bind(SocketAddr::from(([0, 0, 0, 0], port))).await?;
    info!(event = "api.started", port);
    let mut shutdown = shutdown_signal();
    axum::serve(listener, router(state).into_make_service_with_connect_info::<SocketAddr>())
        .with_graceful_shutdown(async move {
            let _ = shutdown.wait_for(|stop| *stop).await;
        })
        .await?;
    info!(event = "api.stopped");
    Ok(())
}

pub async fn run_worker(environment: Environment) -> anyhow::Result<()> {
    let secret_box = secret_box(&environment)?;
    let pool = db::connect(&environment.database_url)?;
    let redis = RedisStore::new(&environment.redis_url)?;
    let metrics = Arc::new(Metrics::new());
    let processor = Arc::new(WebPushProcessor {
        pool,
        secret_box,
        apns: ApnsClient::new(&environment, metrics.clone())?,
        content_store: NotificationContentStore::new(redis.clone()),
        metrics,
    });
    let queue = Queue::new(redis, TELEGRAM_WEB_PUSH_QUEUE, RETRY_POLICY);
    info!(event = "worker.started");
    let result = worker::run(queue, processor, shutdown_signal()).await;
    if let Err(error) = &result {
        error!(event = "worker.failed", error = %error);
    }
    info!(event = "worker.stopped");
    result
}
