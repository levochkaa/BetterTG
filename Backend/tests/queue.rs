//! The Redis job queue against a real Redis. Runs when `BETTERTG_TEST_REDIS_URL` is set, as in CI.

use std::time::Duration;

use bettertg_backend::queue::{Outcome, Queue, RetryPolicy};
use bettertg_backend::redis_store::RedisStore;
use redis::AsyncCommands;

const POLICY: RetryPolicy = RetryPolicy {
    attempts: 2,
    base_delay: Duration::from_millis(10),
    jitter: 0.0,
    keep_failed_for: Duration::from_secs(3600),
    keep_failed_count: 100,
};

async fn setup() -> Option<(Queue, String, redis::aio::MultiplexedConnection)> {
    let Ok(url) = std::env::var("BETTERTG_TEST_REDIS_URL") else {
        eprintln!("BETTERTG_TEST_REDIS_URL is not set; skipping");
        return None;
    };
    let store = RedisStore::new(&url).unwrap();
    let name = format!("test-{}", uuid::Uuid::new_v4());
    let connection = store.client().get_multiplexed_async_connection().await.unwrap();
    let queue = Queue::new(store, &name, POLICY).with_stall_interval(Duration::from_millis(20));
    Some((queue, format!("queue:{name}:"), connection))
}

#[tokio::test]
async fn accepts_a_job_id_once_and_removes_completed_jobs() {
    let Some((queue, prefix, mut redis)) = setup().await else { return };
    assert!(queue.add("job-1", &"payload").await.unwrap());
    assert!(!queue.add("job-1", &"other").await.unwrap());
    let lease = queue.take::<String>(&mut redis.clone(), Duration::from_secs(1)).await.unwrap().unwrap();
    assert_eq!((lease.id.as_str(), lease.data.as_str(), lease.attempts_made), ("job-1", "payload", 0));
    queue.settle(&lease, Outcome::Completed).await.unwrap();
    assert!(!redis.exists::<_, bool>(queue.job_key("job-1")).await.unwrap());
    assert_eq!(redis.llen::<_, u64>(format!("{prefix}active")).await.unwrap(), 0);
    assert_eq!(queue.depth().await.unwrap(), 0);
    assert!(queue.take::<String>(&mut redis, Duration::from_millis(100)).await.unwrap().is_none());
}

#[tokio::test]
async fn retries_with_backoff_then_keeps_the_failure() {
    let Some((queue, prefix, mut redis)) = setup().await else { return };
    queue.add("job-2", &"payload").await.unwrap();
    let lease = queue.take::<String>(&mut redis.clone(), Duration::from_secs(1)).await.unwrap().unwrap();
    queue.settle(&lease, Outcome::Retry("Shutdown".to_owned())).await.unwrap();
    assert_eq!(redis.zcard::<_, u64>(format!("{prefix}delayed")).await.unwrap(), 1);
    assert!(queue.take::<String>(&mut redis.clone(), Duration::from_millis(100)).await.unwrap().is_none());

    tokio::time::sleep(Duration::from_millis(30)).await;
    assert_eq!(queue.promote_due().await.unwrap(), 1);
    let retried = queue.take::<String>(&mut redis.clone(), Duration::from_secs(1)).await.unwrap().unwrap();
    assert_eq!(retried.attempts_made, 1);
    queue.settle(&retried, Outcome::Retry("Shutdown".to_owned())).await.unwrap();

    let job_key = queue.job_key("job-2");
    assert_eq!(redis.zcard::<_, u64>(format!("{prefix}failed")).await.unwrap(), 1);
    assert_eq!(redis.hget::<_, _, String>(&job_key, "failed_reason").await.unwrap(), "Shutdown");
    assert!(redis.pttl::<_, i64>(&job_key).await.unwrap() > 0);
    assert_eq!(queue.depth().await.unwrap(), 0);
    assert!(!queue.add("job-2", &"again").await.unwrap(), "a failed job keeps its ID while it is kept");
}

#[tokio::test]
async fn fails_unrecoverable_jobs_at_once() {
    let Some((queue, prefix, mut redis)) = setup().await else { return };
    queue.add("job-3", &"payload").await.unwrap();
    let lease = queue.take::<String>(&mut redis.clone(), Duration::from_secs(1)).await.unwrap().unwrap();
    queue.settle(&lease, Outcome::Fail("invalid_padding".to_owned())).await.unwrap();
    assert_eq!(redis.zcard::<_, u64>(format!("{prefix}failed")).await.unwrap(), 1);
    assert_eq!(redis.zcard::<_, u64>(format!("{prefix}delayed")).await.unwrap(), 0);
}

/// Waits out the stall check interval, then checks.
async fn recover(queue: &Queue) -> i64 {
    tokio::time::sleep(Duration::from_millis(25)).await;
    queue.recover_stalled().await.unwrap()
}

#[tokio::test]
async fn hands_back_a_job_whose_worker_died_once_then_fails_it() {
    let Some((queue, prefix, mut redis)) = setup().await else { return };
    queue.add("job-4", &"payload").await.unwrap();
    let lease = queue.take::<String>(&mut redis.clone(), Duration::from_secs(1)).await.unwrap().unwrap();
    assert_eq!(recover(&queue).await, 0, "a locked job is not stalled");
    assert_eq!(queue.recover_stalled().await.unwrap(), 0, "checks are spaced by the interval");

    redis.del::<_, ()>(format!("{prefix}lock:job-4")).await.unwrap();
    assert_eq!(recover(&queue).await, 0, "a job is stalled only after two checks");
    assert_eq!(recover(&queue).await, 1);
    let again = queue.take::<String>(&mut redis.clone(), Duration::from_secs(1)).await.unwrap().unwrap();
    assert_eq!(again.id, lease.id);
    assert!(!queue.settle(&lease, Outcome::Completed).await.unwrap(), "the first worker lost the job");
    assert_eq!(queue.depth().await.unwrap(), 1);

    redis.del::<_, ()>(format!("{prefix}lock:job-4")).await.unwrap();
    recover(&queue).await;
    assert_eq!(recover(&queue).await, 0, "a second stall fails the job");
    assert_eq!(redis.zcard::<_, u64>(format!("{prefix}failed")).await.unwrap(), 1);
    assert_eq!(queue.depth().await.unwrap(), 0);
}

#[tokio::test]
async fn keeps_a_lapsed_lock_unless_another_worker_took_the_job() {
    let Some((queue, prefix, mut redis)) = setup().await else { return };
    queue.add("job-5", &"payload").await.unwrap();
    let lease = queue.take::<String>(&mut redis.clone(), Duration::from_secs(1)).await.unwrap().unwrap();
    redis.del::<_, ()>(format!("{prefix}lock:job-5")).await.unwrap();
    assert!(queue.extend(&lease.lock()).await.unwrap(), "a lapsed lock is taken back");
    redis.set::<_, _, ()>(format!("{prefix}lock:job-5"), "someone-else").await.unwrap();
    assert!(!queue.extend(&lease.lock()).await.unwrap());
    assert!(!queue.settle(&lease, Outcome::Retry("Shutdown".to_owned())).await.unwrap());
    assert_eq!(redis.zcard::<_, u64>(format!("{prefix}delayed")).await.unwrap(), 0);
}
