# A30h member-tag editor renewal: integrated proof — 2026-10-03

- `a425767` (worker `6364773`, reviewed tree `736de4e`) keeps the existing editor/UITextField behind a separate exact
  Profile→Members→Tag hold. Generic Members parent binding and replacement gates are unchanged; stale parents remain
  quarantined until Back. Modal or navigation-transition presence alone does not veto this non-mutating hold. Save and its
  completion separately require the attached uncovered exact top; retention grants no action or parent-replacement authority.
- The existing edit session now accepts one tag mutation. Each explicit changed Save captures a Ready endpoint, validates fresh
  chat/actor/target identities, actor ownership, existing rights and the captured tag baseline, then dispatches setChatMemberTag
  once. Empty removal/16-character validation remain. Accepted ACK updates only the accepted baseline; changed raw text,
  edit revision, marked text or covered UI prevents stale completion from popping or overwriting the current editor.
- Native PID83507 on audit Simulator `59EB535C`/iOS26.5, fresh result07:08:36+04: `-ui-probe-profile-member-tag` PASS.
  Actual Tag editor and UIKit stack with production retention/session/authorization prove repeated Ready epochs, same field,
  UTF-16 selection, raw combining text, UITextInput marked text, preserved error, no automatic writes, exact identity/rights/
  conflict rejection, empty removal, predispatch zero writes, postdispatch one-write uncertainty/no replay, newer typing versus
  ACK, account/actor ABA, detached owner, Back hold release and owned-modal retention/covered completion. Endpoints are
  controlled; Profile/Members parents are value-only, not the whole production navigation coordinator.
- Existing regression baselines passed before integration: edit PID65071 at06:57:52; Members/Profile PID70630 at07:00:32/34.
  Integrated repeats also PASS: edit PID84987 at07:09:57; Members/Profile PID88099 at07:11:42/45. No live tag/rights mutation
  was issued. Evidence: `.build/ui-probe-evidence/astra-a30h-member-tag/`. Fresh file timestamps were checked after resolving
  each installed container; Simulator stayed booted and was not activated.
- One six-file SwiftFormat invocation was unchanged after integration. Worker `build-Debug-20261003-070542-81180-18385.log`
  PASS8s; primary `build-Debug-20261003-070745-82833-21963.log` PASS16s; complete logs zero warnings/errors. Independent review
  passed. Native endpoint-terminal counters do not prove exact Task.value completion. Full live parent renewal, authorized
  server Save, native input-method presentation, real edit menu and cancelled interactive Back remain unverified; the historical
  permission-denial smoke is not evidence for those paths.
