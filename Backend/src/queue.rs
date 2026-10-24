//! A durable Redis job queue with BullMQ's guarantees for the push relay: a job ID is accepted once, a job runs
//! until it succeeds or uses up its attempts with exponential backoff, a worker that dies mid-job hands the job
//! back, completed jobs disappear at once and failed ones are kept briefly and boundedly.
//!
//! A worker owns a job through its lock token: a worker that lost the lock can't renew, finish or retry the job.
//! A job whose worker stopped renewing is handed back once, and fails if it stalls again, as BullMQ's
//! `maxStalledCount` of 1 does.
//!
//! Keys under `queue:<name>:`: `job:<id>` (hash), `wait` and `active` (lists), `delayed` and `failed` (sorted by
//! time in milliseconds), `stalled` (set), `stalled-check` and `lock:<id>`.

use std::time::Duration;

use rand::Rng;
use redis::Script;
use serde::{Serialize, de::DeserializeOwned};

use crate::redis_store::RedisStore;

#[derive(Clone, Copy, Debug)]
pub struct RetryPolicy {
    pub attempts: u32,
    pub base_delay: Duration,
    /// BullMQ's backoff jitter: the delay is drawn from `[delay * (1 - jitter), delay]`.
    pub jitter: f64,
    pub keep_failed_for: Duration,
    pub keep_failed_count: u32,
}

impl RetryPolicy {
    /// BullMQ's exponential backoff after `attempts_made` failed attempts.
    pub fn delay(&self, attempts_made: u32) -> Duration {
        let raw = self.base_delay.as_millis() as f64 * 2f64.powi(attempts_made.saturating_sub(1) as i32);
        let jittered = if self.jitter > 0.0 {
            let minimum = raw * (1.0 - self.jitter);
            (rand::thread_rng().r#gen::<f64>() * raw * self.jitter + minimum).floor()
        } else {
            raw.round()
        };
        Duration::from_millis(jittered as u64)
    }
}

#[derive(Clone)]
pub struct Queue {
    redis: RedisStore,
    prefix: String,
    pub policy: RetryPolicy,
    lock_duration: Duration,
    stall_interval: Duration,
}

/// A job a worker holds: its lock token must accompany the outcome.
pub struct Lease<T> {
    pub id: String,
    pub data: T,
    pub attempts_made: u32,
    token: String,
}

impl<T> Lease<T> {
    /// What a renewal task needs to keep the job locked.
    pub fn lock(&self) -> LockHandle {
        LockHandle { id: self.id.clone(), token: self.token.clone() }
    }
}

#[derive(Clone)]
pub struct LockHandle {
    id: String,
    token: String,
}

pub enum Outcome {
    Completed,
    /// Retry later unless the attempts are used up.
    Retry(String),
    /// Give up without retrying.
    Fail(String),
}

const ADD: &str = r#"
if redis.call('EXISTS', KEYS[1]) == 1 then return 0 end
redis.call('HSET', KEYS[1], 'data', ARGV[2], 'attempts_made', 0, 'created_at', ARGV[3])
redis.call('LPUSH', KEYS[2], ARGV[1])
return 1
"#;

/// Finishing removes the job even when its lock lapsed and the job was handed back meanwhile: the handed-back copy
/// then finds no data and is dropped. Only another worker's lock stops it.
const COMPLETE: &str = r#"
local holder = redis.call('GET', KEYS[3])
if holder and holder ~= ARGV[2] then return 0 end
redis.call('LREM', KEYS[1], 1, ARGV[1])
redis.call('DEL', KEYS[2])
if holder then redis.call('DEL', KEYS[3]) end
return 1
"#;

const RETRY: &str = r#"
local holder = redis.call('GET', KEYS[4])
if holder and holder ~= ARGV[4] then return 0 end
if redis.call('LREM', KEYS[1], 1, ARGV[1]) == 0 then return 0 end
redis.call('HINCRBY', KEYS[2], 'attempts_made', 1)
redis.call('HSET', KEYS[2], 'failed_reason', ARGV[3])
redis.call('ZADD', KEYS[3], ARGV[2], ARGV[1])
if holder then redis.call('DEL', KEYS[4]) end
return 1
"#;

const FAIL: &str = r#"
local now = tonumber(ARGV[2])
local keep_age = tonumber(ARGV[4])
local keep_count = tonumber(ARGV[5])
local holder = redis.call('GET', KEYS[4])
if holder and holder ~= ARGV[6] then return 0 end
if redis.call('LREM', KEYS[1], 1, ARGV[1]) == 0 then return 0 end
redis.call('HINCRBY', KEYS[2], 'attempts_made', 1)
redis.call('HSET', KEYS[2], 'failed_reason', ARGV[3])
redis.call('PEXPIRE', KEYS[2], keep_age)
redis.call('ZADD', KEYS[3], now, ARGV[1])
if holder then redis.call('DEL', KEYS[4]) end
local expired = redis.call('ZRANGEBYSCORE', KEYS[3], '-inf', now - keep_age)
for _, id in ipairs(expired) do
  redis.call('DEL', ARGV[7] .. 'job:' .. id)
  redis.call('ZREM', KEYS[3], id)
end
local excess = redis.call('ZCARD', KEYS[3]) - keep_count
if excess > 0 then
  local oldest = redis.call('ZRANGE', KEYS[3], 0, excess - 1)
  for _, id in ipairs(oldest) do redis.call('DEL', ARGV[7] .. 'job:' .. id) end
  redis.call('ZREMRANGEBYRANK', KEYS[3], 0, excess - 1)
end
return 1
"#;

const PROMOTE: &str = r#"
local ids = redis.call('ZRANGEBYSCORE', KEYS[1], '-inf', ARGV[1], 'LIMIT', 0, tonumber(ARGV[2]))
for _, id in ipairs(ids) do
  redis.call('ZREM', KEYS[1], id)
  redis.call('LPUSH', KEYS[2], id)
end
return #ids
"#;

/// Renews the caller's lock, or takes back a lapsed one; another worker's lock wins.
const EXTEND: &str = r#"
local holder = redis.call('GET', KEYS[1])
if holder == ARGV[1] then return redis.call('PEXPIRE', KEYS[1], ARGV[2]) end
if not holder then
  redis.call('SET', KEYS[1], ARGV[1], 'PX', ARGV[2])
  return 1
end
return 0
"#;

/// Hands back active jobs whose lock was missing at the previous check as well, so a job just moved to `active`
/// is never mistaken for a stalled one. Checks run at most once per interval across all workers. A job that
/// stalls a second time fails.
const RECOVER_STALLED: &str = r#"
if not redis.call('SET', KEYS[4], '1', 'PX', ARGV[2], 'NX') then return 0 end
local requeued = 0
for _, id in ipairs(redis.call('SMEMBERS', KEYS[3])) do
  if redis.call('EXISTS', ARGV[1] .. 'lock:' .. id) == 0 and redis.call('LREM', KEYS[1], 1, id) > 0 then
    local job = ARGV[1] .. 'job:' .. id
    if redis.call('HINCRBY', job, 'stalled_count', 1) > 1 then
      redis.call('HINCRBY', job, 'attempts_made', 1)
      redis.call('HSET', job, 'failed_reason', 'job stalled more than allowable limit')
      redis.call('PEXPIRE', job, ARGV[4])
      redis.call('ZADD', KEYS[5], ARGV[3], id)
    else
      redis.call('RPUSH', KEYS[2], id)
      requeued = requeued + 1
    end
  end
end
redis.call('DEL', KEYS[3])
for _, id in ipairs(redis.call('LRANGE', KEYS[1], 0, -1)) do
  if redis.call('EXISTS', ARGV[1] .. 'lock:' .. id) == 0 then redis.call('SADD', KEYS[3], id) end
end
return requeued
"#;

fn now_millis() -> i64 {
    time::OffsetDateTime::now_utc().unix_timestamp_nanos() as i64 / 1_000_000
}

impl Queue {
    pub fn new(redis: RedisStore, name: &str, policy: RetryPolicy) -> Self {
        Self {
            redis,
            prefix: format!("queue:{name}:"),
            policy,
            lock_duration: Duration::from_secs(30),
            stall_interval: Duration::from_secs(15),
        }
    }

    /// How often stalled jobs are looked for; a job is handed back after two looks without a lock.
    pub fn with_stall_interval(mut self, interval: Duration) -> Self {
        self.stall_interval = interval;
        self
    }

    pub fn stall_interval(&self) -> Duration {
        self.stall_interval
    }

    pub fn redis(&self) -> &RedisStore {
        &self.redis
    }

    pub fn job_key(&self, id: &str) -> String {
        format!("{}job:{id}", self.prefix)
    }

    fn key(&self, name: &str) -> String {
        format!("{}{name}", self.prefix)
    }

    /// Adds a job unless one with this ID exists in any state. Returns whether it was added.
    pub async fn add<T: Serialize>(&self, id: &str, data: &T) -> anyhow::Result<bool> {
        let mut connection = self.redis.connection().await?;
        let added: i64 = Script::new(ADD)
            .key(self.job_key(id))
            .key(self.key("wait"))
            .arg(id)
            .arg(serde_json::to_string(data)?)
            .arg(now_millis())
            .invoke_async(&mut connection)
            .await?;
        Ok(added == 1)
    }

    /// Waits up to `timeout` for a job and locks it. Uses its own connection: the wait blocks it.
    pub async fn take<T: DeserializeOwned>(
        &self,
        connection: &mut redis::aio::MultiplexedConnection,
        timeout: Duration,
    ) -> anyhow::Result<Option<Lease<T>>> {
        let id: Option<String> = redis::cmd("BLMOVE")
            .arg(self.key("wait"))
            .arg(self.key("active"))
            .arg("RIGHT")
            .arg("LEFT")
            .arg(timeout.as_secs_f64())
            .query_async(connection)
            .await?;
        let Some(id) = id else { return Ok(None) };
        let token = crate::security::random_token();
        let mut shared = self.redis.connection().await?;
        redis::cmd("SET")
            .arg(self.lock_key(&id))
            .arg(&token)
            .arg("PX")
            .arg(self.lock_duration.as_millis() as u64)
            .query_async::<()>(&mut shared)
            .await?;
        let (data, attempts_made): (Option<String>, Option<u32>) = redis::cmd("HMGET")
            .arg(self.job_key(&id))
            .arg("data")
            .arg("attempts_made")
            .query_async(&mut shared)
            .await?;
        let Some(data) = data else {
            // A job removed while waiting: drop the stray ID.
            self.finish(&id, &token, Outcome::Completed).await?;
            return Ok(None);
        };
        match serde_json::from_str(&data) {
            Ok(data) => Ok(Some(Lease { id, data, attempts_made: attempts_made.unwrap_or(0), token })),
            Err(error) => {
                self.finish(&id, &token, Outcome::Fail(format!("unreadable job data: {error}"))).await?;
                Ok(None)
            }
        }
    }

    fn lock_key(&self, id: &str) -> String {
        format!("{}lock:{id}", self.prefix)
    }

    /// Keeps a running job locked; call it every `lock_renewal_interval`. False once another worker holds it.
    pub async fn extend(&self, lock: &LockHandle) -> anyhow::Result<bool> {
        let mut connection = self.redis.connection().await?;
        let renewed: i64 = Script::new(EXTEND)
            .key(self.lock_key(&lock.id))
            .arg(&lock.token)
            .arg(self.lock_duration.as_millis() as u64)
            .invoke_async(&mut connection)
            .await?;
        Ok(renewed == 1)
    }

    pub fn lock_renewal_interval(&self) -> Duration {
        self.lock_duration / 3
    }

    /// Records the outcome. False when the job no longer belongs to this lease: another worker took it over.
    pub async fn settle<T>(&self, lease: &Lease<T>, outcome: Outcome) -> anyhow::Result<bool> {
        let outcome = match outcome {
            Outcome::Retry(reason) if lease.attempts_made + 1 >= self.policy.attempts => Outcome::Fail(reason),
            other => other,
        };
        if let Outcome::Retry(reason) = outcome {
            let run_at = now_millis() + self.policy.delay(lease.attempts_made + 1).as_millis() as i64;
            let mut connection = self.redis.connection().await?;
            let settled: i64 = Script::new(RETRY)
                .key(self.key("active"))
                .key(self.job_key(&lease.id))
                .key(self.key("delayed"))
                .key(self.lock_key(&lease.id))
                .arg(&lease.id)
                .arg(run_at)
                .arg(reason)
                .arg(&lease.token)
                .invoke_async(&mut connection)
                .await?;
            return Ok(settled == 1);
        }
        self.finish(&lease.id, &lease.token, outcome).await
    }

    async fn finish(&self, id: &str, token: &str, outcome: Outcome) -> anyhow::Result<bool> {
        let mut connection = self.redis.connection().await?;
        let settled: i64 = match outcome {
            Outcome::Completed => {
                Script::new(COMPLETE)
                    .key(self.key("active"))
                    .key(self.job_key(id))
                    .key(self.lock_key(id))
                    .arg(id)
                    .arg(token)
                    .invoke_async(&mut connection)
                    .await?
            }
            Outcome::Retry(reason) | Outcome::Fail(reason) => {
                Script::new(FAIL)
                    .key(self.key("active"))
                    .key(self.job_key(id))
                    .key(self.key("failed"))
                    .key(self.lock_key(id))
                    .arg(id)
                    .arg(now_millis())
                    .arg(reason)
                    .arg(self.policy.keep_failed_for.as_millis() as i64)
                    .arg(self.policy.keep_failed_count)
                    .arg(token)
                    .arg(&self.prefix)
                    .invoke_async(&mut connection)
                    .await?
            }
        };
        Ok(settled == 1)
    }

    /// Moves delayed jobs that are due to the wait list.
    pub async fn promote_due(&self) -> anyhow::Result<i64> {
        let mut connection = self.redis.connection().await?;
        Ok(Script::new(PROMOTE)
            .key(self.key("delayed"))
            .key(self.key("wait"))
            .arg(now_millis())
            .arg(100)
            .invoke_async(&mut connection)
            .await?)
    }

    /// Hands back stalled jobs; returns how many. Does nothing when another worker checked within the interval.
    pub async fn recover_stalled(&self) -> anyhow::Result<i64> {
        let mut connection = self.redis.connection().await?;
        // A little shorter than the interval, so one worker's own timer never finds its previous mark.
        let throttle = self.stall_interval.saturating_sub(self.stall_interval / 10).max(Duration::from_millis(1));
        Ok(Script::new(RECOVER_STALLED)
            .key(self.key("active"))
            .key(self.key("wait"))
            .key(self.key("stalled"))
            .key(self.key("stalled-check"))
            .key(self.key("failed"))
            .arg(&self.prefix)
            .arg(throttle.as_millis() as u64)
            .arg(now_millis())
            .arg(self.policy.keep_failed_for.as_millis() as u64)
            .invoke_async(&mut connection)
            .await?)
    }

    /// Jobs waiting, delayed or running.
    pub async fn depth(&self) -> anyhow::Result<u64> {
        let mut connection = self.redis.connection().await?;
        let (wait, delayed, active): (u64, u64, u64) = redis::pipe()
            .llen(self.key("wait"))
            .zcard(self.key("delayed"))
            .llen(self.key("active"))
            .query_async(&mut connection)
            .await?;
        Ok(wait + delayed + active)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backs_off_exponentially_within_the_jitter_band() {
        let policy = RetryPolicy {
            attempts: 5,
            base_delay: Duration::from_secs(1),
            jitter: 0.5,
            keep_failed_for: Duration::from_secs(3600),
            keep_failed_count: 100,
        };
        for (attempts_made, raw) in [(1, 1000u64), (2, 2000), (3, 4000), (4, 8000)] {
            for _ in 0..50 {
                let delay = policy.delay(attempts_made).as_millis() as u64;
                assert!((raw / 2..=raw).contains(&delay), "{attempts_made}: {delay}");
            }
        }
        let exact = RetryPolicy { jitter: 0.0, ..policy };
        assert_eq!(exact.delay(3), Duration::from_secs(4));
    }
}
