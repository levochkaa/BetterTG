# A50 selection-mode exit invalidation — 2026-10-03

- P1, bounded fix `0ae5853`; actual Saved Messages at `ddb9daa`/PID90027 and `aa52123`/PID5348 shows stale unselected-row circles after Cancel.
  `ChatView.endMessageSelection` saves only selected IDs and reconfigures those after setting isSelectingMessages=false.
  Other cells retain selectionActive/control/indicator and the old callbacks. A49 guards suppress stale actions but do not repair UI.
  The structural `endMessageSelection(reconfigure:false)` branch likewise needs all surviving rows reconfigured in that apply.
- Bounded plan: invalidate every message row already in the displayed snapshot on explicit mode exit, and every surviving
  message row in the structural snapshot when selected-message removal exits the mode. Keep stable IDs, ordinary per-selection
  targeted updates, permission checks and viewport restoration; no send/delete/poll mutation.
- `0ae5853`, reviewed tree `62c1bc70`, invalidates all displayed message rows on explicit exit, including deselect-last with an
  already-empty selected set. Structural selected-row removal invalidates all incoming surviving message rows in its own apply.
  Telegram pre-Liquid `8e7e5fe`, `ChatController.swift`7372–7384 updates selection state for every history item. No TDLib API change.
- Joint SwiftFormat0/7; full build `140935-21229-15672` PASS14s/zero warnings/errors. Audit59EB535C/iOS26.5 PID22663,
  fresh container `4844B0B0-0143-4DE3-A183-22684E32AD5E`, report14:10:24 passes existing delivery/A44/A49 action/touch probes.
  Same source/PID actual Saved Select→Cancel and Select→tap sole selected row both remove all visible selectors and restore
  empty composer; screenshots `a50-selection`, `a50-cancel-clean`, `a50-deselect-before`, `a50-deselect-clean` inspected.
  Structural model removal is source-reviewed, not exercised by this smoke or existing native probe; deletion race remains unverified.
