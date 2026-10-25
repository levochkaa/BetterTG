# Accepted TDLib update provenance proof — 2026-10-02

- A13 worker `1eb9d23c75a335defd5a2df2274d9b6dc2504aaa` was independently reviewed and integrated as `7ab5643`.
  `TDLib.handle` captures account UUID/client ID into immutable notification userInfo; `td.py` generates exactly one post with
  unchanged name/raw object. Opt-in scoped subscribers extract payload/source before scheduler delivery and reject missing source.
  Voice/video durable cleanup and selected-document ownership use event account; ChatVM/forum UI additionally match frozen client.
  All 15 subscribers of send-success/send-failure/delete in these five consumers were migrated; legacy subscribers remain compatible.
- Worker warning-free build: `.build/logs/xcodebuild/worker-A13-build-Debug-20261002-152038-71499-21293.log`.
  Primary SwiftFormat covered all 11 changed Swift paths in one invocation (`0/10` changed, generated file excluded by config).
  Primary build passed without warnings in `.build/logs/xcodebuild/build-Debug-20261002-152748-427-24895.log`; generated output
  stayed unchanged after wrapper regeneration. The first primary attempt stalled before compilation while clang wrote to its
  SDK-discovery pipe; only that owned xcodebuild was interrupted, then the unchanged wrapper retry passed in 11s. Diagnostic:
  `.build/ui-probe-evidence/astra-a13-build-diagnostic/clang-81316.sample.txt`. No cache or Simulator reset was used.
- Wrapper launch on authorized Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iOS 26.5, PID `1577`, with
  `-media-probe-update-source`: `.build/ui-probe-evidence/astra-integrated-update-source/update-source-probe.txt` reports generated
  dispatch, delayed A→B delivery, colliding-ID isolation, old-client UI rejection, same-account durable ownership, unscoped rejection,
  exactly-once raw legacy payload and permanent-delete guards all passed. The real Saved Messages row remains accessible by idb.
- Probe scope: real generated dispatcher and Combine transport with an isolated NotificationCenter/in-memory consumers. It does
  not switch real accounts, touch user stores or exercise TDLib server outcomes. Production subscriber migration was source-reviewed.
  The existing active-client gate still drops callbacks arriving after a switch; safe inactive-client outcome recovery remains open.
  A12 route/temporary-ID matching, A14 finalization leases and A18/A19 VOD/PiP are unchanged.
