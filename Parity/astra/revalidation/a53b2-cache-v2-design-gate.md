# A53b2 cache-v2 design gate — reviewed 2026-10-03, not implemented

- At `51d7174`, prewarmer active leases do not cover completed entries; `RichNotificationCache` persists only JPEG bytes.
  Replace the media path with one atomic envelope per exact account/raw-chat/ordinary raw-message identity in `media-v2`.
  It must bind schema/policy version, random content revision, resource fingerprint, full-message eligibility, state and
  normalized bytes/digest. Normalize outside the lock. Prepare a revision before download; completion compares against the
  present matching revision and never recreates an evicted/missing record. A source/client token is job ownership, not permission.
- App and NSE transactions need a stable per-account file lock. Invalidation must cover matching content/edited/delete events
  even without a running job. Accepted invalidations survive source retirement; do not silently drop them when bounding queues.
  MainActor receipt can revoke local work and enqueue immutable keys, but durable cross-process visibility begins only after
  the utility transaction succeeds. A reader that acquires the lock first may still consume the previous revision. Failed writes
  cannot emit a successful acknowledgement. Atomic replacement/readback alone is not proof of power-loss durability.
- `TDLib.releaseForNotificationService`152–166 currently closes clients and unlocks without a media transaction drain.
  Flush already-accepted invalidations off-main before orderly DB handoff. The DB lock does not protect cache readers:
  `NotificationService` reads cache after its six-second owner-lock timeout. Abrupt termination and pre-ack reads remain limits.
  To prevent an already-copied stale record from later becoming an attachment, final publication must revalidate its exact
  revision under the same authority; an earlier locked read alone cannot prove no post-ack attachment.
- Backend `apns-payload-mapper.service.ts`57 forwards the raw `loc_key` as metadata.event, with no independent preview flag.
  Pinned TDLib `NotificationManager.cpp`2818–2919/3332–3354 maps raw GIF/DOC/ROUND and strips CHAT_/CHANNEL_ prefixes;
  `NotificationType.cpp`160–161 maps MESSAGE to Hidden. Any cache-only presentation allowlist must use exact supported raw
  message-family keys and peer kinds, not substring matching or normalized TD names. Hidden/secret/notext/unknown/aggregate
  and pinned events remain fail-closed. Such a policy is source-derived presentation evidence, not fresh server-settings proof.
- Required isolated tests: fresh/cache-only positives; concealment/preview denial; held download versus revoke; same-batch deny;
  edit/delete with no active job; two store instances; eviction versus late commit; invalid identity/schema/digest; failed revoke
  without acknowledgement; and declared pre-ack versus rejected post-ack read/commit order. Legacy JPEGs stay untouched/unread.
