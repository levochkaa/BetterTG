# Classic shell blur slice

- **P2 flow:** full-width folder/tab chrome and context-menu material, based on pre-Liquid `ChatListFilterTabContainerNode` selection
  geometry and classic UIKit material rather than Liquid Glass.
- Implemented: edge-to-edge bottom blur including safe area; rectangular scroll viewport; exact three-point segment line; selected accent
  text; ordinary system-material context menu; classic 16/10pt menu/highlight corners; all Glass-only APIs and marker strings removed.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-062914-33482-14249.log`; real account hierarchy/screenshot and long-press
  menu evidence `.build/ui-probe-evidence/classic-shell-*`; PID 33820 alive; Simulator booted.
- Deferred: remaining navigation/search/action surfaces still need a complete full-width/no-floating audit.
