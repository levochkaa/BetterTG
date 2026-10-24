//! A shared Redis connection, opened on first use so the process starts while Redis is down and recovers once
//! it is back.

use std::time::Duration;

use redis::aio::{ConnectionManager, ConnectionManagerConfig};
use redis::{AsyncCommands, Client, RedisResult};
use tokio::sync::OnceCell;

#[derive(Clone)]
pub struct RedisStore {
    client: Client,
    manager: std::sync::Arc<OnceCell<ConnectionManager>>,
}

#[derive(Debug, thiserror::Error)]
pub enum RateLimitError {
    #[error("rate limit exceeded")]
    Exceeded,
    #[error(transparent)]
    Redis(#[from] redis::RedisError),
}

impl RedisStore {
    pub fn new(url: &str) -> anyhow::Result<Self> {
        Ok(Self { client: Client::open(url)?, manager: Default::default() })
    }

    pub fn client(&self) -> &Client {
        &self.client
    }

    pub async fn connection(&self) -> RedisResult<ConnectionManager> {
        self.manager
            .get_or_try_init(|| async {
                let config = ConnectionManagerConfig::new()
                    .set_connection_timeout(Some(Duration::from_secs(5)))
                    .set_response_timeout(Some(Duration::from_secs(5)))
                    .set_number_of_retries(3);
                ConnectionManager::new_with_config(self.client.clone(), config).await
            })
            .await
            .cloned()
    }

    pub async fn ping(&self) -> RedisResult<()> {
        let mut connection = self.connection().await?;
        redis::cmd("PING").query_async::<String>(&mut connection).await?;
        Ok(())
    }

    /// Allows `limit` hits per key; every hit restarts the `window_seconds` window.
    pub async fn enforce_rate_limit(&self, key: &str, limit: i64, window_seconds: i64) -> Result<(), RateLimitError> {
        let mut connection = self.connection().await?;
        let key = format!("rate-limit:{key}");
        let (count,): (i64,) = redis::pipe()
            .atomic()
            .incr(&key, 1)
            .expire(&key, window_seconds)
            .ignore()
            .query_async(&mut connection)
            .await?;
        if count > limit { Err(RateLimitError::Exceeded) } else { Ok(()) }
    }

    /// `SET key value EX ttl NX`; true when the key was set.
    pub async fn set_nx_ex(&self, key: &str, value: &str, ttl_seconds: u64) -> RedisResult<bool> {
        let mut connection = self.connection().await?;
        let result: Option<String> = redis::cmd("SET")
            .arg(key)
            .arg(value)
            .arg("EX")
            .arg(ttl_seconds)
            .arg("NX")
            .query_async(&mut connection)
            .await?;
        Ok(result.is_some())
    }

    pub async fn set_ex(&self, key: &str, value: &str, ttl_seconds: u64) -> RedisResult<()> {
        let mut connection = self.connection().await?;
        connection.set_ex::<_, _, ()>(key, value, ttl_seconds).await
    }

    pub async fn get(&self, key: &str) -> RedisResult<Option<String>> {
        let mut connection = self.connection().await?;
        connection.get(key).await
    }

    pub async fn get_del(&self, key: &str) -> RedisResult<Option<String>> {
        let mut connection = self.connection().await?;
        redis::cmd("GETDEL").arg(key).query_async(&mut connection).await
    }

    pub async fn del(&self, keys: &[String]) -> RedisResult<()> {
        if keys.is_empty() {
            return Ok(());
        }
        let mut connection = self.connection().await?;
        connection.del::<_, ()>(keys).await
    }
}
