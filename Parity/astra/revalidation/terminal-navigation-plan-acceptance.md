# Terminal navigation-plan acceptance — 2026-10-02

- A30b2 prerequisite worker `1584f4d` integrated as `3b629b4`. Preparation owns no transferred files; the coordinator rechecks
  ready/source generation, controller preflight, exact stack and transition/modal barriers before a one-shot synchronous commit.
  An accepted replacement is installed without a later rejection that could strand transferred composer files. Production commit
  constructors must not navigate or replace the client. Main is still the only opted-in production entry; Chat activation remains open.
- A bounded identity-snapshot pass visits each original eligible entry once, skips a deferred entry and preserves other routes.
  Changed readiness during a commit schedules one weak coalesced retry. Source/readiness/account changes before acceptance do not
  transfer ownership. This reworks the existing A30a transaction, with the same pinned ChatList/ChatInterfaceState references.
- Three Swift files formatted together; primary warning-free build
  `.build/logs/xcodebuild/build-Debug-20261002-172957-13872-9541.log` (8s); worker log copied with `worker-A30b2-plan-` prefix.
  Audit Simulator PID `14747`: expanded `-ui-probe-client-restoration` passes real coordinator/prepared-plan and isolated lifetime/file
  checks, two entries in one Ready, deferred-first skip, preflight changes, refused commit, terminal install and duplicate/reentrant
  readiness. A30b1/A28/A27/A16/A17 regressions pass beside it in `.build/ui-probe-evidence/astra-a30b2-plan-primary`.
- Actual Main regression: own query `111222` on groups → HOME → app icon, same PID and query; `7` typed without tap produces
  `1112227`. Visually inspected `search-restored-typing.png` records focus/cursor and selected folder; keyboard stayed hidden.
  Own query cleared with Close. No folder/message/account writes. This validates Main after the transaction change, not Chat recovery.
