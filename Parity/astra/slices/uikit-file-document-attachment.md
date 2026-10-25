# UIKit file/document attachment slice

- **P0 flow:** pre-Liquid/current attachment-menu document flow, adapted to `UIDocumentPickerViewController` and TDLib
  `InputMessageDocument` / `sendMessageAlbum` with the existing immutable forum send context.
- Implemented: Files menu and cancellable multi-selection; security-scoped provider copies capped at 10; account/location rejection of
  stale picker completion; mutually exclusive photo/document strips; filename/size/remove accessibility; Dynamic Type row growth; exact
  document permission and General/reply topic; first-item caption; homogeneous 1–10 document album; partial-result retention of only
  unsent selections; duplicate-send serialization and composer→bubble flight. Temp ownership uses provisional persisted leases before
  any upload await, binds outcome-before-registration aliases to TDLib IDs, protects active files from remove/replace/deinit/scavenging,
  migrates failed IDs, and releases on global success/permanent delete even after ChatView closes. Lease paths require a generated UUID
  prefix and exact managed parent; unleased orphans expire after 24h and abandoned leases have a 30-day recovery ceiling.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-095820-86651-17797.log`; focused source/delta review clean.
  PID `82584` proved enabled Attach Files at `{{10,697},{250,42}}`, UIKit Recents/Search/Browse, exact Cancel AX hit and unchanged
  composer after cancellation. Evidence: `.build/ui-probe-evidence/document-attachment-*`; no file was selected or sent.
