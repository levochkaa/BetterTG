# Own-story viewers carousel — 2026-10-30

Scope: ST-1's carousel and paging while an own story's viewers list stays open, from `1f81bf71`
on `t3/refresh-goal-prompt`. Implementation is in this audit's commit. Full parity remains open.
The old checkpoint's row-menu, channel-footer and admin-menu entries were stale: those paths already
existed. This slice addresses the remaining carousel gap.

## Reference and behavior

Official Telegram `telegram-upstream/master`, `fb0e62ba8a147f0821da6aa63c09da7d79a10111`:
`submodules/TelegramUI/Components/Stories/StoryContainerScreen/Sources/StoryItemSetContainerComponent.swift`.
Relevant paths: ItemLayout, updateScrolling, scrollViewWillEndDragging, viewListPanGesture and the
per-story viewLists. The local reference differs from that branch only by an unrelated Swiftgram import.

- The open list shows neighbouring own stories, with 12 pt gaps and side cards 54 pt narrower than the
  centre. UIKit scrolling snaps to a story; tapping a neighbour selects it, tapping the centre closes
  the list. The focused story keeps the controller's real media view and footer. Neighbours use photo
  or video thumbnails, not additional players. Thumbnail views/tasks are bounded to nearby cards.
- Horizontal list drags move cards and lists together. Selection needs 30% of the width, or 5% with
  velocity at least 200 pt/s; cancellation and the first/last bounds retain the current story. A
  committed change settles in 0.3 s, a return in 0.4 s; Reduce Motion uses 0.15 s.
- Each visited story owns its panel, query, loader, rows and scroll position for the viewer's lifetime.
  Switching preserves half/full height and the view-list pause. Closing restores the selected story;
  reopening reuses its panel. Story updates refresh metadata; deletion removes the cached panel.
- Cards receive updated stories and reject cancelled initial fetches. Closing/teardown cancels card
  work and page animations. A second gesture cannot interrupt the list's settle animation.

Frame inspection exposed a defect missed by state probes: resetting transform and assigning frame
inside a spring distorted cards and displaced counts during selection. Layout now changes bounds,
centre and transform directly. The list's extra 20 pt spacing rebases separately from the card index,
so both preserve their positions when selection changes.

The DEBUG UI fixture now has an explicit offline session, with no active-account dependency or
account-update subscriptions. Production session ownership remains unchanged. Its report starts with
`running`, preventing an old pass from being mistaken for a completed new launch.

## Verification

All seven changed Swift files were formatted together. Final wrapper build passed in 28 s:
`build-Debug-20261030-035902-88607-9587.log`; the complete 981-line log had zero warnings/errors.
Built and installed debug dylibs matched SHA-256
`e8a99c13807bb5565e14a48fbd86e29e7b65133bdf2aba9ff7cf81dbecb98449`.

Device: this thread's unauthenticated iPhone 16 Pro / iOS 26.5 Simulator,
`6DF66290-FE39-475C-91FA-0267B1718DDA`, driven through T3 Device and its pinned agent-device CLI.
The fixture contains two own photo stories and local interaction rows; no Telegram messages or
account data were changed.

| Check | Observed result |
| --- | --- |
| State probe | Selection stays within the poster and retains the list pause; 54/12 pt geometry, distance/velocity thresholds, cancellation and both edges pass. The existing story-state checks also pass. |
| `own carousel` UI probe | Story 1002 receives a distinct panel; returning to 1001 restores the same panel and its one-row Bob search result. Half/full height, pause and cancellation pass. Search uses the real field's debounce through a DEBUG entry point; the three-viewer fixture does not expose the search field visually. |
| Manual gestures | Upper-card paging and list paging select the matching story/list; a short drag returns, the last story does not cross to another poster, and full-height paging stays at y=60. Closing and reopening retain the selected story. |
| Motion | The earlier `035058` build's recording exposed the transform/frame defect. `035739` removed the distortion; final-build `final-gestures.mp4` and 20 fps release crops show the corrected transition after separate spacing rebasing. These earlier recordings are not final-binary proof. |
| Existing viewers regression | `own viewers-full` checks half at y=337, full at y=60 with the footer hidden, then closed at scale 1 with the view-list pause released. |
| Existing poster paging | `cube-commit 0.4` shows the next face during the drag, then Carol at rest. |

Bounded Simulator logs contained no matching Auto Layout conflict, presentation warning or terminating
exception. Normal launch was restored to phone entry. Local, non-durable reports, screenshots and recordings are in
`/tmp/bettertg-story-carousel-audit/`.

## Limits and next

Real story downloads/interactions, delayed metadata, video playback while switching, deletion or
account retirement during a gesture, large-list scroll/sort retention and memory use remain
unverified at runtime. Per-panel ownership and fetch/update cleanup have source proof only beyond
the fixture checks above. Accessibility adjustment is implemented but VoiceOver operation, RTL,
Dynamic Type, iPad, iOS 27 and physical devices remain unchecked.

Next executable Stories gap: the channel viewers list, after inspecting TDLib's current capabilities
and Telegram's channel-specific row/actions. The editor, statistics and other ST-1 omissions remain
open. Dedicated-account Gallery/File renewal, delivery and failure verification also remain pending.
This checkpoint does not complete the parity goal.
