# Selection pan and deletion submenu separator — 2026-09-05

- Opt into UICollectionView's two-finger multiple-selection interaction, matching Telegram's
  two-finger history selection gesture. Native selection callbacks use the same displayed-message
  set, album-aware 100-source-message limit and eligibility rules as taps. Empty selection can
  survive a live pan until fingers lift; Cancel and final deselection clear native and custom state.
- Native selection is reconciled after snapshots; selection gestures suppress viewport anchor
  restoration that would fight edge scrolling. Capability checks are cancelled when selection
  changes. The context recognizer rejects a second finger rather than competing with the pan.
- The submenu now places a section divider between Back and deletion modes, as requested.
- Validation: SwiftFormat on every task-modified Swift file and warning-free wrapper build
  (`build-Debug-20260905-175726-36643-20849.log`). Live two-finger/edge-scroll verification pending.
