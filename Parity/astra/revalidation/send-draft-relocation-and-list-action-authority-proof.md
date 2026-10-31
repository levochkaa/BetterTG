# Send-draft relocation and list-action authority proof — 2026-10-02

- A26 worker `2e28fad` integrated as `e6efb3f`; five changed Swift files formatted together. Primary wrapper build
  `.build/logs/xcodebuild/build-Debug-20261002-161828-25210-228.log` passed without warnings (12s).
  Both stores persist filename-only references and resolve them against the current store. Legacy rebasing permits only the
  app-container UUID to change; wrong owner/name, external/traversal/symlink paths are rejected. All canonical/list loads use
  the resolver. Invalid/missing manifests survive for recovery and protect owned files from orphan pruning; failed legacy
  rewrite still returns the valid runtime draft. Enqueue IDs/outcomes, route/reply/caption/waveform, video thumbnail/origin and
  removal tombstone contracts are unchanged. Reference: pinned current/pre-Liquid `MediaBox.swift` 228–241/491–493 derives
  resource paths from the current base directory; no Postbox code was imported.
- Audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone 17 Pro/iOS 26.5, PID `27534`:
  `-media-probe-draft-relocation` passes real isolated stores across legacy/relative × move/copy, raw/encoded/token voice,
  canonical-before-list/stale adoption, outcome authority, video thumbnail/origin/tombstone, malformed/missing/symlink paths
  and injected migration-write failure. Result: `.build/ui-probe-evidence/astra-a26-primary/draft-relocation-probe.txt`.
  A14/A24 regressions pass in `astra-a26-voice`/`astra-a26-edit`. A12 initially fails in `astra-a26-drafts`: its DEBUG encoded
  voice fixture had an extensionless input, persisted as `.wav`, unlike production encoded `.ogg`. Worker `9dce6fc`, integrated
  as `f33c30b`, corrects only fixture filenames and diagnostic stages; production ownership validation is not relaxed.
  One Swift file formatted; warning-free build `build-Debug-20261002-162317-68150-27789.log` (8s). PID `71109` repeats A26/A12
  successfully in `astra-a26-final-relocation`/`astra-a26-final-drafts`. Historical failure output is retained.
- Production recovery uses only own draft `CDD62EC0-0614-4481-B007-119AD74DD113`: restore its backed-up legacy JSON beside
  the still-existing Ogg, then open Saved Messages. Retry appears and canonical loading migrates the reference to a filename.
  All metadata except the intended URL change matches the backup; Ogg SHA256 remains
  `c05b255f8c03e0983da8cecef40a4777cdc9dbf08b2b29033b8b3d9d69d0ae33`. Another wrapper install (`f33c30b`, PID `71109`)
  preserves identical relative JSON/Ogg and shows Retry. Long-press → **Discard Voice Message**, not Retry, removes this own
  draft through production UI. Send/recording voice stores are then empty and the mic returns. Recoverable backups, migrated
  and reinstalled files/captures: `astra-a26-ui` under `.build/ui-probe-evidence`. No message was sent or user draft removed.
  Real video reinstall remains unverified; the isolated video store probe is not camera/server proof.
- A29 worker `7513376` integrated as `114eafc`; six Swift files formatted together. Primary warning-free wrapper build
  `.build/logs/xcodebuild/build-Debug-20261002-162551-79894-26406.log` (15s). Main/folder/editor actions capture one controller
  source/client, gate reads and writes before/after suspension, stop stale bulk loops and fence late UI delivery. Covered
  parent controllers retain legitimate pushed-picker authority; stale chat row navigation remains available for recovery.
  Reference: pinned `ChatListController.swift` current 98/1187, pre-Liquid 91/1961 uses captured account context.
- Combined PID `99924`: `-ui-probe-list-action-authority -media-probe-draft-relocation -media-probe-draft-outcomes
  -media-probe-voice-finalization -ui-probe-composer-edit` all pass. Results: `astra-a29-primary`, `astra-a29-relocation`,
  `astra-a29-drafts`, `astra-a29-voice`, `astra-a29-edit`. A29 runs the production bulk helper with suspended fake RPCs:
  A→B/colliding IDs, replacement client, detached owner, cancellation and unscoped source produce no new writes; late writes
  deliver no old UI result; current errors and continued bulk behavior remain intact. UIKit attachment is injected here,
  not proved by this probe. Read-only production UI opens Settings, then All-tab Edit Folders → populated Chat Folders →
  empty New Folder → Back → Back to All. Settled screenshots `astra-a29-primary/current-screen.png` and `new-folder.png`
  confirm the two authority-gated pushes. An initial AX-only check falsely looked like a no-op: idb returns generic native
  navigation groups without those labels, and the earlier screenshot caught the outgoing menu transition. No folder/account/
  server mutation was attempted. Cold-launch attachment works; live account/dismissal mutation races still need real proof.
  Production/dependency prohibited-marker scan is empty, but these screenshots expose secondary chrome gap A32.
