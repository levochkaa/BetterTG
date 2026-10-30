# Channel story interactions — 2026-10-30

Scope: ST-1's channel/group story interaction list, from `3f1d895d` on `t3/refresh-goal-prompt`.
Implementation is in this audit's commit. Full parity remains open.

## Reference and behavior

Official Telegram `telegram-upstream/master`, `fb0e62ba8a147f0821da6aa63c09da7d79a10111`:

- `StoryItemSetContainerComponent.swift`: creator or statistics access, view-list expansion and per-story paging.
- `StoryItemSetViewListComponent.swift`: Reactions title, no Contacts/search, Reposts First and Recent First,
  sort visibility at 20 interactions and 10 forwards, No Reactions empty text and no peer context menu.
- `StoryChatContent.swift`: `canViewStats` comes from cached channel data.
- `StoryFooterPanelComponent.swift`: enabled view-count button, centred count as the list opens, and disappearing
  like/share controls.
- `EngineStoryViewListContext.swift`: `stories.getStoryReactionsList`, forwards-first flag and pagination.

The first three files are under `submodules/TelegramUI/Components/Stories/StoryContainerScreen/Sources/`;
the footer is under `StoryFooterPanelComponent/Sources/`; the engine context is under
`submodules/TelegramCore/Sources/TelegramEngine/Messages/`.

TDLibKit's pinned TDLib 1.8.69 schema and StoryManager distinguish `getStoryInteractions` (current user's
story, only story ID) from `getChatStoryInteractions` (chat ID plus story ID). `canGetInteractions` is
an own-story flag. The UI now resolves creator status or administrator/statistics access from the
current supergroup and full info, including groups; it does not infer access from edit/delete rights.
The session rechecks access before a page request, preserves the complete story key, and drops answers
after that chat's permission generation changes, story deletion or client retirement. Updates for
another chat do not invalidate this chat's request.

The channel footer opens the shared half/full list. Its carousel retains each story's list and chosen
order. Writable groups keep their reply panel and can open the permitted list by swiping up. Channel
rows reuse the existing profile, message-forward and story-repost destinations; personal blocking and
contact menus are disabled. A permission loss closes the list and its sort menu, removes its panels,
and disables reopening. Shared menu dismissal is scoped to the owning controller.

The shared loader now distinguishes failure from an empty result. First-page errors show Retry;
later-page errors keep loaded rows and retry the same offset. Failed requests do not cause an automatic
retry loop. Duplicate retry taps are ignored while loading. This also fixes misleading empty states
for the existing own-story list.

## Verification

Environment: Xcode 27.1, local unauthenticated iPhone 16 Pro Simulator, iOS 26.5,
`6DF66290-FE39-475C-91FA-0267B1718DDA`. Input and recordings used the thread's pinned `agent-device`.
No real story interactions, sends or account-data changes. Evidence is under
`/tmp/bettertg-channel-story-audit/`.

All nine changed Swift files were formatted together. Final `./build.sh build --simulator-id
6DF66290-FE39-475C-91FA-0267B1718DDA` passed in 31 s. The complete 977-line log,
`.build/logs/xcodebuild/build-Debug-20261030-042342-12383-17399.log`, has no warnings or errors.
Built and installed `BetterTG.debug.dylib` SHA-256 both matched
`8cfc7fbe78ff702a1f22aed175782ef38ca036f5a68931c3f7db5ca3fe70674c`.

Final-binary results:

- `-ui-probe-story-viewer` passed the existing state checks and channel rights, header thresholds,
  empty text, footer gating and own/chat request separation (`final-state-probe.txt`).
- `-ui-probe-story-viewer-ui channel viewers` passed Reactions without tabs/search, forwards-first
  default, recent-first changes, second-page requests and per-story list/query retention.
- `channel denied` made zero requests and kept the list closed. `channel revoke` closed the actual
  sort menu and list, discarded the panel and prevented reopening after the fixture revoked access.
- `channel retry` passed first-page and later-page failures, duplicate retry taps and same-offset
  retries: four requests, twenty rows, the first ten preserved. `channel failure` showed the error.
- `own carousel` retained the filtered list and its panel across paging, full height and cancellation.
  These UI reports are `final-channel-{viewers,denied,revoke,retry,failure}-probe.txt` and
  `final-own-carousel-probe.txt`.
- Manual Retry loaded the rows. The subsequent sort/reopen repeat was incomplete: Newest First's
  label matched two actionable elements, and `100 Views` was absent while the list remained open.
  On recovery the sort menu opened, but the click failed with `Ref @e54 needs a complete snapshot —
  the current frame only authorizes its emitted refs`. Device work stopped as required. The
  `042342-reopened.png` filename is misleading: it does not prove a reopened list. The fixture's sort
  menu was left open; normal phone entry was not restored.

The preceding warning-free build, `build-Debug-20261030-041432-3488-2700.log`, had installed dylib
`ae43976b0557bf45e4496f935fec6953112fb4d8ae87c5b72ea20b9968ebe413`. Its state and UI probes passed
channel viewers, denied access, empty state, permission loss, retry, the previous channel footer and
own carousel/full-height viewers. Reports are copied as `041432-*-probe.txt`; the files named
`final-channel-empty-probe.txt`, `final-channel-footer-probe.txt` and
`final-own-viewers-full-probe.txt` also belong to that earlier build.

That build's manual `final-gestures.mp4` (33.733 s, recording stopped) checked Retry, the sort menu,
Newest First selection, full-height expansion, horizontal paging to No Reactions and back with the
order retained, closing and reopening from the count. `final-sort-menu.png`, `final-failure.png` and
the reduced `final-closing.jpg` contact sheet were inspected. This is Simulator motion evidence,
not a physical-device or high-refresh-rate claim. The final build only changed permission-update
filtering: unchanged supergroup membership metadata no longer invalidates interaction requests.
Its final probes above rechecked the affected paths. A bounded final log read found no Auto Layout
conflicts, presentation warnings or app-termination messages.

## Limits and next

The fixture intercepts interaction requests and permission changes. It cannot prove real TDLib/server
permissions, network pagination, live rights updates, or profile/message/repost navigation on actual
channel data. Supergroup/full-info access and rejection of late server answers have source proof;
the fixture exercises the controller's permission-loss callback. Writable groups' list gesture is
implemented, but their reply-panel layout and central carousel footer have not had runtime proof.

Physical-device behavior, iOS 27, VoiceOver, RTL/Dynamic Type, writable-group runtime and performance
on large lists remain unverified. Story publishing/editing, statistics, the speed slider, other ST-1
omissions and dedicated-account Gallery/File delivery/recovery checks remain open. This checkpoint
does not complete the parity goal.

Next executable source gap: compare Telegram's story playback-speed slider with BetterTG's discrete
speed menu and port the missing interaction. Resume device work only after resolving the recorded
tool failure; do not count the interrupted manual repeat as a pass.
