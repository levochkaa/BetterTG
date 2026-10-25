# September 6 navigation and text-selection refinements

- Empty chat titles use the localized `User.DeletedAccount` fallback in the shared display-title model.
- Native navigation is hidden before the first transition frame. Owned controllers either retain their
  existing embedded bar or use a common 44pt UIKit bar, plain buttons and the message-list Back glyph.
  Navigation items remain the action/state model; asynchronous title/button changes feed the common
  renderer. Search uses an owned provider instead of registering a native bottom search toolbar. The host reserves only its own safe-area height and restores it on removal.
- List/chat searches retain their 36pt field at the safe-area top with 8pt bottom padding, inside 44pt chrome. The shared
  chat/pinned blur retains a pixel divider between navigation and the pinned message.
- Forum search uses the chat list's one-time initial offset and drag-end snapping. A native table
  footer reserves 44pt of search travel for short lists; UITableView owns its content size. Topic
  updates and later layouts do not reposition the list.
- Profile and folder tabs recalculate after their scrolling viewport receives its actual width:
  fitting tabs fill equal shares; overflowing tabs retain their content widths and scroll.
- Reactions appear at their final position without a sideways layout animation. There is no root Quote
  action. Text inside the extracted message becomes selectable; an explicit UIKit edit menu quotes that exact
  UTF-16 range with rebased entities and the original position. Link-preview descriptions are excluded.
  Selecting a hidden spoiler reveals it, following Telegram's text-selection behavior.
- Rich math renders its display list in explicit bottom-left coordinates; UITextView's implicit
  accessibility value is cleared so the redacted label remains authoritative for hidden spoilers.
- Source/build verification: `build-Debug-20260906-014542-65464-8267.log` passed without warnings.
  Live Photo, rich messages, selected-text Quote, the single Settings search, equal profile tabs and the Deleted Account fallback passed simulator readback. Short forum snapshots showed the expected hidden/revealed search geometry, but missed the idle animation regression investigated below. The own Live Photo also passed the 131×131 profile-grid crop → fullscreen 4:3 → same grid tile transition without a duplicate source image.


Final simulator evidence for this follow-up is under `.build/ui-probe-evidence/parity-fixes-20260906/`:
`final5` covers rich formulas, details, hidden/revealed spoiler accessibility and the single Live Photo send/save;
`final6` covers Live Photo autoplay/loop/hold/stop, profile tab widths and selection, one search field,
header scrolling, Deleted Account and thirteen text/emoji checks; `final8` covers selected-text Quote
and cancellation; `final9` covers initial/revealed/collapsed topic-search geometry and square-grid gallery transitions.
Simulator VFR recordings were decoded sequentially (`-i` before `-ss`) using media timestamps
and scene cues: stationary pauses can be compressed, so wall-clock tap times do not map directly
to media PTS; fast input seeking also returned misleading nearby frames.
The own Live Photo message was read back as sent with a native video component in Saved Messages
(message ID `1426016174080`); the retained own voice retry was sent as `1425958502400`.

The final no-selection Photos picker Cancel check also passed: one tap returned to Saved Messages
with an empty composer and no extra navigation pop, asset selection, send or save. The earlier
unresponsive Cancel observation was not reproduced after the context-menu ownership fixes.
