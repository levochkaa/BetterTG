# BetterTG / Telegram iOS Parity

This is the checkpoint ledger for the UIKit + Combine + TDLibKit implementation. The goal prompt is
[PARITY_PROMPT.md](PARITY_PROMPT.md); editing either file does not start or resume a goal.

Implementation status and audit status are separate. Implementation: **done** (the recorded scope has its stated proof),
**implemented breadth** (main paths exist, listed limits), **partial** (known gaps), **next**, **queued**. Audit:
`pending`, `reviewed`, `needs-fix`, `fixed`, `runtime-blocked`. Proof kinds are source review, warning-free build,
deterministic probe, Simulator smoke and physical device or server. A proof belongs to its SHA, scenario and environment;
historical CLEAN, build or smoke results do not transfer to merged or changed code. Gifts, Stars, collectibles, boosts,
Premium, ads, livestreaming and Telegram infrastructure (Texture, SignalKit, Postbox, Display, ComponentFlow) are out of
scope. None of the states below claims complete Telegram parity.

## Current checkpoint — 2026-10-12, updated 2026-10-24

- Branch `codex/parity` (worktree `/Users/lev/.codex/worktrees/parity/BetterTG`). Stage 0 is closed by this ledger
  commit on top of `15701d2`. No push or PR.
- References: Telegram `telegram-upstream/master` = `f1dd7a2dbd` (release-13.0.0) for behavior, TDLib logic and new
  mechanics; classic pre-Liquid chrome baseline `8e7e5fefb1b0aba8335d8c28b62138183d61dc3d`; context-menu liquid morph
  `58ce7d6688`, `f44a25a649`, `11a469d1f8`, `7c2cfd6a1f`; system context-menu gesture reconstruction in
  `/Users/lev/Developer/CustomContextMenu` (UIKitCore iOS 27.0, 24A434).
- Toolchain: Xcode 27.1 (27A9275) since `57cd9507`, before it 27.0 (27A266a); iOS deployment target 26.0, TDLibKit `2.0.1-tdlib-1.8.69-ea3f69ce` (since `74531c64`; before it `2.0.0-tdlib-1.8.68-c15d3f5a`) from
  levochkaa/TDLibKit (native models plus the generated compat layer in `BetterTG/Shared`), Lottie 4.6.1, libwebp 1.6.0,
  FFmpeg 9.0 through `Packages/FFmpegBridge`, SwiftMath 1.7.3. Production code has no MobileVLCKit, TDLibKitDynamic or
  SwiftUI/hosting/representable UI.
- Context-menu gestures from CustomContextMenu are ported for every menu source (commit
  `feature(context-menu): port the system menu touch model`); see "Context-menu gestures" below. F2 is fixed in
  `89f1c14`.
- The liquid morph of menu buttons is ported (commit `feature(context-menu): morph menu buttons into the custom menu`);
  see "Liquid morph of menu buttons" below.
- Revalidation so far: F3-F7 and F9-F55 are fixed; F8 is a watch item. Foreground smoke B1-B10 (2026-10-14/15, `/tmp/b1-evidence` to `/tmp/b10-evidence`) covered returning from the background in the chat list, a chat, the chat and profile galleries, scroll to latest and the pinned banner (F48-F55). Localization of UI literals is merged from `codex/parity-l10n` (`e05d541`); 86 of 91 probes pass on the merged build and the other five are live-UI observations checked by hand. The F40 residual was fixed in `31caecd6`; F31 has its Simulator proof in its row.
- Checkpoint 2026-10-17, evening (`codex/parity` at the commit that adds this line, warning-free `./build.sh build`, Xcode MCP on the iPhone 18 Pro iOS 27.0 Simulator; test media sent to BetterTG test > UI test as the user allowed): besides the morning's closures (F39, the F40 residual, MD-14 drawing, the MD-11 poll attachment and contact tails, the sticker peek, Web App biometry, the context-menu release cases), the sending pass is done: F38 fixed by `ca333792` (the history moves once), F41 by `49fa071f` (cancel from a playing video's disc), F43's sizes measured, F56 found and fixed (`1d883a25`, TDLibKit's constant `typeID` for payload-free enum cases), the poll gallery's Save and Share fixed (`8fd54395`). MD-11 closed its remaining runtime tails: recent files search (`41bae1d9`), live location sending, panels, Extend, the proximity alert and Stop, recent hashtags with Delete, suggested and panel stickers and GIFs, the edit mode's Emoji item, polls with photo and link media. The media keyboard spans the window and its tabs swipe under the Liquid Glass folder capsule (`68448bc5`, `10c9d019`, `f6a4213d`). Liquid morph: proven with the keyboard up and on the iOS 26.5 runtime; Reduce Motion runtime proof stands. B-12 is closed by R-1. Accepted limits: F26's closing flash (UIKit's reparenting portal), F47's shorter glass travel, live locations update only in the foreground (A30), the A21/A22/A37/A39/A49/A51 bounded repairs. F41's album relayout is animated (`19b25a90`, `3c4caf97`). Profile Music and Voice rows play in their chat's playlist with the lock-screen info (`ac3b017e`); bot games open in their own screen (`c8839afd`); checklists are created and edited in ComposeTodoScreen's editor with Telegram's service lines (`7b42250d`, `d11a5cfc`). Blocked, as the user decided on 10-17: V-7's raise-to-listen and earpiece route, F22's timing, 120 Hz and haptics, and MD-15's lock-screen previous/next buttons (the Simulator draws no media platter) need a physical iPhone (both are `unavailable` to `devicectl`); A23 and A30's multi-account races need a second logged-in account. Next slice: a device pass and a two-account pass.
- Checkpoint 2026-10-24 (`codex/parity` at the commit that adds this line; work moved from Codex to Claude in T3 Code): the own-story slice the goal paused in on 10-18 is done, `71834019` (ST-1). Homebrew's SwiftFormat is now 0.64.0: `26a25923` enables the rules DoodleMaster adopted with it and reformats the sources (215 files), and `57cd9507` makes Xcode 27.1 (27A9275) the default. `./build.sh build` on Xcode 27.1 is warning-free, lint included; after the reformat `-media-probe-draft-outcomes`, `-ui-probe-notification-request`, `-ui-probe-notification-session-lifetime` and `-ui-probe-story-viewer` pass. `build.sh` now picks the iPhone 17 Pro iOS 26.5 Simulator (`8108A92F`), where the account is signed in. Next slice: the viewers list behind the footer (StoryItemSetViewListComponent, `getStoryInteractions`), then the channel footer and admin menu.
- Checkpoint 2026-10-24, later (`codex/parity` at the commit that adds this line, warning-free `./build.sh build` on Xcode 27.1, idb on the iPhone 17 Pro iOS 26.5 Simulator):
  - The menu glass stretches on iOS 26 as well (`0cd4967b`). It matches the system menu there: regular, flexible, grouping, flex variant 5.
  - The read time is a line of text atop the menu (`43222f7d`, ChatReadReportContextItem).
  - The finger that opens a menu no longer drives the swipe-to-reply under it (`dc7902bb`).
  - A message taller than the room above the menu keeps its size and scrolls with Telegram's hidden scroller. The reaction strip stays on the message and pins to the top only while the message reaches past it (`d45c55c5`).
  - Chat-list rows are BetterTG cards in the Settings style with all of Telegram's row content (`484c9fb5`).
  - Clang compilation caching is shared across worktrees; `clean-cache` and a disk preflight were added (`43271279`). Swift caching stays off because of Xcode's libcxxshim warning.
  - Submenus open as the system's stacked card (`5b83af40`). The geometry and springs were read from `_UIContextMenuStackedHierarchyLayout` on iOS 26.5 and 27.2, which match. Delete offers Telegram's presentDeleteMessageOptions choices. Long action titles wrap to two lines.
  - A closing submenu's glass blends into the menu while the card shrinks, as the system's does (`8b37f80a`). The chevron takes the row's color.
  - A submenu's glass materializes as its card opens and dematerializes as it closes, rim included (`e93fef67`). Read with LLDB from `navigateDownFromNode:`/`navigateUpFromNode:` on iOS 26.5: `setSuppressGlassBackground:` swaps the material for its `_identityGlass` inside the 0.85 / 0.4 s and 1 / 0.4 s springs. The header turns over on 1 / 0.2 s and the card clips until that spring settles.
  - On closing, BetterTG fades the submenu's glass on 1 / 0.3 s rather than the native 1 / 0.4 s shrink (`bddfe8ea`). On the shrink's spring the glass seemed to vanish at once with the card already small; the user asked for it to fade out the way it appears.
  - TDLibKit is on TDLib 1.8.69 (`74531c64`). The release `2.0.0-tdlib-1.8.69-ea3f69ce` had a generator bug: it missed TDLib's `//-` continued field docs, which made `forwardInfo.source` required. The fork fixes it in `275f35b7ec` and released `2.0.1-tdlib-1.8.69-ea3f69ce`. `-ui-probe-story-viewer` and `-ui-probe-message-metadata` pass, and Saved Messages shows its forwards.
  - Story viewers list (ST-1, `053e4c10`, `b27965cb`): the footer's counts or a swipe up open the own story's viewers at half or full height, as Telegram does; see ST-1. Next: the rows' context menu and the carousel of the other own stories beside the open list, then the channel footer and admin menu.
  - Chat chrome parity, 10-24 evening: the bottom status panel in the docked composer bar (G-15, G-16: Join, Mute/Unmute with search, Unblock, restrictions, Delete and Exit, secret chat handshake), the action bar for chats from someone new (S-18), ChatEmptyNode's empty states (S-19), stepping through several pins with the pinned list and Unpin All (S-20), the Unread Messages divider (S-21), verified/scam/fake marks (S-22), the date header calendar and the floating date (S-23), grouped plural counts (P-18). The profile header's buttons stay BetterTG's (PeerProfileMoreMenu keeps Mute in More by design); opening a chat at its first unread message is not ported.
  - Chat list rows and chat text, 10-24 night: Telegram's online and video chat markers (L-17), the auto-delete timer badge (L-18), media and album thumbnails (L-19), message type icons in place of the "↗︎" forward mark (L-20), entity formatting with spoiler dust and custom emoji (L-21), animated activity indicators in rows and the chat header (L-22), and expandable quotes folding to three lines (S-25).
  - Candidate, not started: TGS rendering off the main thread, as Telegram's rlottie/MultiAnimationRenderer does. Measured 10-24 on the iPhone 17 Pro iOS 26.5 Simulator: looping custom emoji in the reaction strip held menu motion to about 36 Hz. Lottie's automatic engine plays most TGS on its Core Animation engine, whose layer trees the render server composites every frame, and a few on its main-thread engine. `e8e8181b` works around it for the menu by freezing their layer clocks while the menu moves. A throwaway feasibility probe rendered `PlaneLogo.tgs` off the main thread with `LottieAnimationLayer` (main-thread engine) into 96×96 bitmaps: 54 of 54 frames non-empty, 1.2 ms a frame, no crash. A port would need a frame cache with a memory budget, synchronized loops, play-once and still frames for every TGS in the app.
- Runtime smoke after the merge (2026-10-12, Simulator iPhone 18 Pro, Xcode device interaction and idb, evidence `/tmp/rs2-*`; every test message deleted): PASS for photo gallery close (button and swipe), video close by Back, voice record/send/play/delete, sticker/emoji/GIF panel tabs, GIF in a bubble, photo attachment with caption, camera absence alert, forum reply and forward into a topic, deletion in a forum topic. Open defects:
  - D1: fixed as F39.
  - D2: fixed as F40. The cause was the chat under the gallery, not the video.
  - D3: GIFs fixed as F35. Re-check 2026-10-13: the free account's sticker and custom-emoji panel results are all static WebP (112 of 112 items), so the panel has nothing to animate; animated WebM stickers found by search do play in the panel.
  - D4: not reproduced 2026-10-13. A WebM sticker found by search played in the panel and, once sent, in its bubble (frames 0.25 s apart differ in a recording); the original report sent a static WebP sticker.
  - D5: fixed as F38.
  - D6: fixed as F37.
  - D7: fixed as F32.
  - D8: fixed as F36.
  - G1: fixed as F41.
- Tooling: since `75872177` the user allows Xcode MCP tools, including device interaction, for Simulator validation (AGENTS.md and CLAUDE.md); builds and runs stay on `build.sh`.
- Audit cursor: the chat timeline and media views were audited read-only at `224b76f9` (see "Post-merge audit" below);
  every other area is `pending`. Follow the full path action → state/ownership → TDLib → update → UI/cleanup per area.

## Stage 0 — one branch from three sources

### Sources

| Source | SHA | Role in the merge |
| --- | --- | --- |
| `main` (local, not pushed) | `bca8057` (prompt written at `24d5b2f`) | Toolchain, dependencies and current UI: Xcode 27, TDLibKit 1.8.68, liquid-lens folder picker, folder unread badges, Telegram context menu |
| `codex/parity-continuation` | `eb4e199` (2026-09-05…06) | Parity code already on TDLibKit 2; user UI decisions |
| `codex/a21e-previous-worker` (astra) | `0f0b479` (2026-10-02…03) | Independent revalidation: ownership/lifecycle fixes, account/client epochs, MediaCore, probes; TDLibKit 1.5.2 |

The parity lines share `7b0699d`. `7875f17` is the parity-continuation merge of `7b0699d` with main's TDLibKit 2
(`6dd705c`), before any of its UI decisions.

### Merge strategy

1. M1 `5af0512`: `codex/parity` from main ← parity-continuation (base `6dd705c`, five conflicting files), plus
   TDLib 1.8.68 adaptation of parity code. Xcode 27 build, 0 warnings.
2. M2 `2787f32`: `codex/parity-astra-tdlib2` from a21e ← `7875f17` (base `7b0699d`). Astra is ported to TDLibKit
   2.0.0 and `Packages/TDLibKitDynamic` is removed. Xcode 26.6 build, 0 warnings. Merging `7875f17` rather than main
   leaves the final merge a single base.
3. M3 `945051d`: `codex/parity` ← `codex/parity-astra-tdlib2` (single base `7875f17`). Conflicts are astra
   against parity-continuation and main's October work; the result is adapted to TDLib 1.8.68 and Xcode 27. A full
   recompile of 334 Swift files has 0 warnings.
4. `15701d2`: fix found by the Stage 0 smoke (F1).

All three histories are reachable from `codex/parity`. `main` and both source branches are unchanged.

### Merge decision ledger

| Area | Taken from | Why | Carried over from the other side |
| --- | --- | --- | --- |
| Toolchain, packages, build scripts, TDLib API | main | Prompt rule | Astra value-equality generator for native models; parity `script/td.py` path |
| Navigation chrome | parity-continuation `TelegramNavigationController` / `TelegramClassicNavigationChrome` | Identity: one classic bar on every screen | Astra navigation client restoration, now driven by `onDidShow` because the controller stays its own delegate. Astra `ClassicNavigation` (system bar variant), its diagnostics and probe are removed |
| Folder picker | main liquid lens strip | Identity | Parity item model (Forward to reuses the picker), resolved-width segment frames, viewport-width relayout |
| Context menu | main animation and scene keyboard lookup | Identity | Parity reactions strip and quote selection; parity keyboard ownership guard; astra `owner`/`onDismiss` and idempotent `finishDismissal` |
| Chat list ownership | parity `TelegramChatListStore` (ordered TDLib update store, on-demand paging) | Removes the hydration races astra fenced; pages beyond 200 chats; matches TDLib's list model | Astra `RootListAuthority` tickets, `RootScopeSettingsLoading`, owner-checked authorization, source-scoped send/delete/unread updates, navigation hydration through the current client, folder viewport restoration. Astra `RootChatProjection`/`RootChatInsertion` and their probes are removed; probe fixtures moved to `ProbeFixtures` |
| Timeline pipeline | astra frozen snapshot transactions, viewport authority, explicit message navigation | Concrete A22/A39/A49 defect fixes | Parity two-finger native selection, per-item album highlight (`highlightedMessageID`), animated highlight on reconfigure, gallery return (bounded wait for the committed row, immediate centering), all-chat-media gallery |
| Composer text | astra `ComposerText` semantic entities | A25 round-trip fix | Parity custom emoji become semantic entities; `ComposerText` derives the renderer attribute and keeps it across bridging; parity copy/cut payload, paste payload, atomic emoji edits; insertion goes through astra undo |
| Spoilers | astra `MessageTextSpoilerState`/store | Scoped reveal authority (A10) | Parity dust overlay, reveal animation, rich text, quote menu and persisted `CustomMessage.spoilersRevealed`; unscoped texts are caller-owned |
| Media views and galleries | astra origins, scoped clients, reveal sessions, playback contexts | Account/client isolation and ownership fixes | Parity live photos, inline GIF autoplay, crossfade/preserving image loads, transition geometry (no flash), thumbnail strip, Open in Chat return hooks (restored galleries keep them) |
| Video notes | astra `configure(message:backend:)` and download ownership | Lifecycle fixes | Parity same-note reconfigure keeps playback; parity progress/play-icon behavior |
| Forum topics list | parity collapsed classic search UI | Identity | Astra restoration, snapshot queue, ownership and scalar-update handling now read the classic search field; astra UISearchController renewal probe removed |
| Forward to | parity recipient flow (tap opens the chat with a pending forward) | User decision | Astra snapshot queue in topic picker, filtered by eligible topics |
| Profiles | parity shared-media tabs and gallery hooks | Identity | Astra restoration, effective info permission (`canEdit` uses it) |
| Voice drafts | astra canonical draft loading | Relocation via `SendDraftFileReference` never deletes | — |
| Docs | both AGENTS/CLAUDE build notes | — | — |

### Stage 0 proofs — 2026-10-12

- Build: `./build.sh build`, Xcode 27.0, full app recompile after M3 (334 Swift files) with 0 warnings
  (`.build/logs/xcodebuild/build-Debug-20261012-034326-50800-5062.log`); incremental builds after `15701d2` with 0
  warnings. M2 built separately on Xcode 26.6 with 0 warnings.
- Simulator smoke on `945051d` plus F1, iPhone 18 Pro, iOS 27.0 (`46AD65F9-D204-47F1-A765-B74D8322BC28`), real account; test
  writes only in Saved Messages and the private test forum `BetterTG test`:
  chat list and folder switching with unread badges and the lens; open chat; send text; send a photo from the library;
  gallery paging, More menu and swipe dismissal; voice hold-to-send and playback (microphone prompt first rejects a
  too-short clip as expected); video-note mode switch and recorder, which reports a capture failure because the
  Simulator has no camera; Saved Messages profile with Media/Files tabs and profile gallery; message context menu with the
  reaction strip; Forward to and the pending-forward block; forum topic list with hidden search; rich message, formulas
  and caller-owned spoiler reveal.
- Limits: no physical device, camera, system PiP or 120 Hz proof; no video-note playback (no reachable note); text
  spoilers in ordinary messages, multi-account switching and probes were not run after the merge.

### Stage 0 findings and follow-ups

| ID | Pri | Finding | State |
| --- | --- | --- | --- |
| F1 | P1 | Forwarding into Saved Messages reported "Telegram returned a different topic" although TDLib delivered it (Saved Messages topic vs empty destination topic); the forward stayed pending for a duplicate retry | fixed `15701d2`, Simulator smoke |
| F2 | P2 | Forward to shows its search field initially; identity requires it hidden like the main list | fixed `89f1c14`: pages scroll search out after the first page; Simulator smoke shows hidden search, pull-to-reveal and folder switching |
| F3 | P2 | Context-menu item casing is mixed (reply/edit/copy/delete vs Forward/Select) | fixed in the F3 slice: message, gallery and attach menu items use Telegram keys (`Conversation.ContextMenuForward`, `Conversation.ContextMenuSelect`, `Conversation.Pin`/`Unpin`, `Conversation.ContextMenuCopy`, `SharedMedia.ViewInChat`, `Gallery.SaveImage`/`SaveVideo`, `Common.Delete`, `Attachment.File`) with en fallbacks; Simulator shows them in the selected pack's casing. Labels without a Telegram key (Emoji, Stickers & GIFs, Save Live Photo/GIF/Animation/Sticker Frame) stay BetterTG English |
| F4 | P2 | Astra profile editor status uses `navigationItem.prompt`, which classic chrome does not render | fixed: `TelegramClassicNavigationChrome` observes `prompt` and renders it in a 30 pt row above the title row (folder flows and profile editors use it), reserving the height in the safe area and announcing it to VoiceOver; `-ui-probe-navigation-chrome-prompt` passed; Simulator settings screen unchanged without a prompt. A live Reconnecting/Saving state was not triggered |
| F5 | P2 | Forum search renewal after client restoration lost its probe with the UISearchController UI | fixed: `ForumTopicsSearchRenewalProbe` (`-ui-probe-forum-active-search`) drives the classic field: in-place renewal keeps field, text, UTF-16 selection and focus; an unfocused search only prepares for the navigation replacement and commits in place once refocused; IME, foreign modal, explicit Retry, stale control, pop, actor/account ABA, unknown actor and unloaded failure as in astra. Passed on iPhone 18 Pro iOS 27.0 |
| F6 | P2 | Reaction strip stickers load through the active client rather than the menu's captured client | fixed: `TelegramContextMenuReaction` carries the client that resolved its sticker; Simulator shows the animated reaction stickers |
| F7 | P2 | From M2: native-model deep `Hashable` cost in timeline diffing is unmeasured; `ChatVM._loadMessages` skips astra `replacingExisting` for already shown cursor messages; client activation keeps the previous client published until the async replacement exists; `ComposerTextProbe` lost its JSON round trip; new astra strings are not localized | partly resolved. History paging: reviewed, kept. A page read adds only unseen ids and still takes current values through the refresh token. Shown rows stay current through accepted TDLib updates, and re-reading them would only race those updates. Client activation: a defect. `ChatLocation.current` paired the selected account, which changes at once, with the still-published previous client, so a chat opened mid-switch carried the new account over the old client. It now takes the account from the same snapshot as the client, and `NavigationStorage.push` refuses during the gap. Simulator: open chat, Forward to and the pending-forward destination still work. `ComposerTextProbe` draft check: reviewed, no gap. TDLibKit 2 `TDNativeDraftMessage` is a view over a native td_api object and has no JSON transport, so building the draft and reading its content back already crosses the real boundary. Localization: done. Message summaries, pins and service messages are F18-F20; the remaining UI literals (about 750 sites) came from `codex/parity-l10n`, merged in `e05d541`: Telegram keys where meaning and text match, otherwise `BetterTG.strings` with Russian; three places that compared UI text with literals ("online" in the chat header and profile, "access" in the video-note error) now use state. The notification extension keeps English fallbacks because it has no `L10n`. Deep `Hashable`/equality cost: measured and fixed as F22. F7 is closed |
| F8 | P2 | During the F2 smoke, a tap sequence in Forward to (pull to reveal search, tap a folder, tap Close) ended in a real group chat without a pending forward; nothing was sent. A controlled repeat switched folders correctly | unreproduced in two controlled repeats (second on 2026-10-12: pull to reveal search, tap channels, tap Close returned to Saved Messages). `openDestination` checks cancellation after every await and only opens a chat with a pending forward, so a chat without one cannot come from this picker; the likeliest cause is an idb tap landing after the picker dismissed. Watch it |
| F9 | P1 | The old message press reset every ancestor recognizer by toggling `isEnabled` when it began, up to the window's system gates and the glass flex pan. Applied to the chat list, it left the table's `_UISwipeDismissalGestureRecognizer` recognizing every later tap (logged `st=3`), so rows stopped opening chats after a chat-preview menu | fixed in the gesture slice: the press relies on UIKit exclusivity, and ChatView no longer lets the message press recognize simultaneously; Simulator smoke opens the chat after a preview menu |
| F10 | P1 | Gesture port regression: a long press on the newest message lifted its preview so the menu appeared under the resting finger, and the release selected the action there (Select in the smoke; Delete was one row lower) | fixed: touches that do not begin on the menu, including the opening finger, highlight and select only after the scrubbing handoff, that is after moving past the 10 pt hysteresis; reactions follow the same rule; the probe covers the resting finger; Simulator: a release over Select keeps the menu open |
| F11 | P2 | Editing started with the caret at the start of the message text, so typing went before it. Telegram builds the edit state with `ChatTextInputState(inputText:)`, whose selection is after the text (`AccountContext/Sources/ChatController.swift:466`, `ChatControllerLoadDisplayNode.swift:4578`) | fixed: the composer moves the caret to the end when editing begins; Simulator edit appended at the end |
| F12 | P1 | A single-topic refresh merged the topic through the plain order merge, which moved pinned topics below unpinned ones (probe `forum-updates`: `[9,5,1,3]`) | fixed `2288147`: the topic is replaced in place and re-sorted through the pinned ranks, as in astra; `-ui-probe-forum-updates` passes |
| F13 | P2 | Forward to hid forum topics the forward may not enter. Telegram peer selection lists closed topics disabled (`ChatListNode`, closed thread info) | fixed `7f999d7`: every loaded topic is listed; disallowed ones are dimmed, not interactive and announced as closed; selection still requires an allowed topic; `-ui-probe-forward-forum-snapshot` passes |
| F14 | P2 | The folder chat selector's title fallbacks (username, phone, chat type) were unreachable: `displayTitle` already turned an empty title into Deleted Account | fixed `c7fc52c`: the selector checks TDLib's raw title first |
| F15 | P2 | The composer replaced marked text with the model echo, ending IME composition at every candidate; its custom emoji loaded through the active account instead of the chat's | fixed `dcadd35`: the echo is skipped while text is marked and equal; `ChatComposerView` hands `chatVM.client` to the emoji renderer, which drops placements without a client and ignores results from a replaced client |
| F16 | P2 | The folder "Add Chats" selector sorted 815 candidates alphabetically, so recent chats needed a search. Telegram's picker is the root chat list (`chatListFilterAddChatsController` → `ContactMultiselectionControllerNode`, `ChatListNode(location: .chatList(groupId: .root))`) | fixed `bf97289`: candidates follow the main list (pinned, then recent), then chats only in other folders, then the archive; position-only changes keep the open selector's rows in place as astra required. `-ui-probe-folder-flow` passes with list positions unrelated to titles and IDs; Simulator: the selector's first rows match the All tab |
| F17 | P2 | Folder pages other than the current one showed their search field after a search: ending the shared search called `setSearchActive(false)` on every page, which scrolled each to the top with search revealed and lost its position | fixed `b269602`: each page keeps the viewport and initial search offset it had when search began and returns there; Simulator: search on People, cancel, switch to Groups shows Groups with search hidden; client-restoration, root-list and folder-flow probes pass. A tap on the selected tab still scrolls to the top with search, like Telegram |
| F18 | P2 | Message summaries (chat list, reply and pinned previews, rich blocks, spoiler masks) used English literals, so the user's selected language pack (lowercase English) showed "Photo" or "Voice message" among lowercase UI | fixed `53994e9`: media kinds use Telegram's `Message.*` keys in `mediaContentKind` order (audio "title — performer"), BetterTG-only labels and unsupported placeholders use `BetterTG.strings` with Russian; the location card no longer compares its title with "Location". Simulator chat list shows "photo" and "voice message"; spoiler probe passes |
| F19 | P1 | Pins diverged from Telegram (`ChatControllerLoadDisplayNode` pinMessage/unpinMessage): Pin opened an action sheet, Unpin from the menu asked for confirmation, the banner close only hid locally, and Saved Messages offered no Pin and showed no banner because TDLib 1.8.68 tags its messages with a saved-messages topic | fixed `6bf311b`: channels and Saved Messages pin at once; private chats get "Pin for me and %@" / "Pin for me", groups "Pin and notify all members" / "Only Pin" as a submenu; menu Unpin is immediate; the banner close asks `Conversation.UnpinMessageAlert` when the loaded pinned message can be unpinned and hides it otherwise. Simulator in Saved Messages: Pin pinned at once, banner appeared, close → alert → Unpin removed it; `-ui-probe-pinned-message` passes. A pinned message outside the loaded history is handled in `3d3dcc1`: fresh properties decide whether to offer the alert, and Unpin goes by identifier. Smoke: the user's own long-standing Saved Messages pin now shows its banner; the alert appeared and Cancel kept it |
| F20 | P1 | Service messages showed generic titles without names ("A member left", "Chat title changed") where Telegram writes "Lev left the group" or "Lev changed group name to «X»" | fixed `2aeb746`: `ServiceMessageText` ports `universalServiceMessageString` for creation, title/photo, joins, invites, removals, leaves, link/request joins, pins (Telegram's 15-character text clip and media kinds), screenshots, voice chats and topic state/rename. Names are resolved in `getCustomMessage` before the row exists and travel in render and restoration values; the accessibility label reads them. Chat-list and topic-list previews keep the localized generic title (no name lookup there yet). Simulator: the forum's General shows "BetterTG test created the group \"BetterTG test\""; message-content, restoration and timeline probes pass |
| F21 | P2 | Group rows in the chat list showed the last message without its sender, and service actions as generic titles | fixed `36710af`, `7616f09`: group rows use Telegram's inline author prefix (ChatListItem `useInlineAuthorPrefix`, "You" or the sender's compact name), which keeps BetterTG's one-line preview; service previews use `ServiceMessageText` with names from a per-client user cache. Simulator: a member's name before the message text, and renaming the test forum showed "лева changed the group name to …" (renamed back). Extended `f26f021c`: service kinds that need more than names (checklist tasks marked or added, game scores, auto-delete timers, chat sharing, community, proximity) resolve ServiceMessageText's full context in the background, cached per message and client, and the chat or topic row redraws when it lands; before, a checklist row read `to "DELETED"`. Simulator 2026-10-18: marking "deploy" in UI test made the topic row read "you marked "deploy" as done" |
| F22 | P1 | Measured F7 cost: every timeline snapshot rebuilt `ChatMessageRenderValue` for each loaded message and deep-compared it; native models read each field through C++. `-ui-probe-timeline-value-cost` on Saved Messages: 30 messages, 1.1 ms per snapshot (0.97 ms comparing, about 37 us per message) on the Simulator, so a few hundred loaded messages exceed a 120 Hz frame per snapshot | fixed `4d50618`: `CustomMessage.renderRevision` is bumped by every published change and by quote expansion; a row with the same canonical object, revision and inputs is reused without building or comparing, otherwise the deep comparison runs as before and advances the stored revision. Probe: 0.008 ms per snapshot on the fast path; timeline, restoration, update-delivery, delivery, reactions, viewport and composer-edit probes pass; Simulator edit of a test message updated its bubble and was reverted. Device timing unmeasured |
| F23 | P1 | A folder page resting at its top hid chats that moved above the first row (a new pin or a new message): UIKit anchored the previous first row, so the moved chat slid under the navigation bar (pin smoke: the pinned row at y=30 behind the bar) | fixed `d2eab4b`: a page resting within the search height of its top keeps that offset across the snapshot; the immediate and the animated re-anchor are both corrected. Simulator: pinning the test forum shows it as the first visible row (unpinned afterwards); folder-flow, root-list, client-restoration and chat-list-store probes pass. Scrolled pages keep UIKit anchoring |
| F24 | P2 | Chat-list "Add to Folder" opened an action sheet, shown as a popover over the bottom folder picker; Telegram (ChatContextMenus) replaces the menu with a submenu of folders that do not hold the chat yet, and hides the item when there is none | fixed: the item is a submenu of the same menu with the folder list; it is omitted when no folder can take the chat. Remove from Folder stays a direct action. Xcode device interaction: the submenu opens in the same menu container with back and the folders, back returns, closing changes nothing |
| F25 | P3 | Stopped activity indicators in the reaction strip and the gallery Share/More buttons stayed in the accessibility tree as "Progress halted" over those controls | fixed: `UIActivityIndicatorView.setLoading` hides a stopped indicator from view and accessibility; the gallery share indicator moved above the toolbar because a hidden view inside the effect content view stayed exposed. Xcode device interaction: no indicator in the gallery tree before or after hiding chrome |
| F26 | P3 | Gallery More liquid morph: the "1 of 6" counter shows over the first menu row for two frames at the start and end of the morph (60 fps video); no flash otherwise | mostly fixed `6dfb935d`: the counter now sits below the bar's buttons, and in a new 60 fps recording the opening glass covers it from the first overlapping frame. Closing residual is UIKit's (10-17, 60 fps `more4.mp4`/`more5.mp4` with Xcode MCP taps): the counter is under the glass in the first closing frame and shows through it over the next two to three (about 50 ms) as the shrinking glass thins. A view dump 0.12 s into the close shows why ordering cannot help: UIKit hosts the closing glass through a reparenting portal it inserts next to the destination button inside the gallery bar (opacity 0.91, the menu root's portal at 0.09). Raising UIKit's morph container to the top of the window and ending the close on a rendered copy of the button in the menu's root left the frames unchanged, so both were dropped; Telegram's `LensTransitionContainer.animateOut` also closes into the button itself |
| F27 | P2 | Archiving a chat from the chat-list menu gave no feedback and no way back; Telegram (ChatListController.archiveChats) shows a bottom "Chat archived" toast with Undo | fixed `eb14ae1a`: `TelegramUndoToast` (dark glass, 5 s, replaces the visible toast, VoiceOver announcement) appears above the folder picker; Undo returns the chat to the main list. The first build's Undo was only as large as its title, so taps a few points off hit the toast body (Xcode device interaction: button 37×30 inside a 386×50 toast); the Undo area now spans the full height and right edge, as in UndoOverlayControllerNode. Simulator: archive the test forum, tap at the point that failed before, the toast closes and the forum returns to its place, read, muted and unpinned |
| F28 | P2 | Long-pressing a forum in the chat list stretched the row snapshot over the whole chat-preview container, because forums had no preview controller | fixed `0fd70756`: the menu previews `ForumTopicsViewController` in a context-preview mode, as Telegram previews forums with `ChatListControllerImpl(location: .forum, previewing: true)`. The menu owns the preview; topic selection and navigation recovery are off; the bar shows the title without Back. Simulator: the test forum preview lists General and UI test under its title |
| F29 | P2 | The forum topic list showed only the title: no member status, no way to the group's info, no More menu. Telegram (ChatListController.updateForum, openMoreMenu) shows "N members, M online" under the title, opens Group Info on a title tap, and offers View as Topics / View as Messages / Group Info / Add Member / New Topic | fixed `d4e0e24f`: subtitle from the supergroup member count (full info) and `updateChatOnlineMemberCount`, title tap opens the profile, More menu with View as Topics (checked), View as Messages and Group Info. View as Messages calls `toggleChatViewAsTopics` and replaces the page with the forum's history. Simulator: "BetterTG test / 1 member" (singular plural verified), title opens the profile, the switch works both ways and was reverted. Add Member and New Topic are not offered yet (no screens) |
| F30 | P2 | A forum read as messages showed the avatar and had no way back to topics; Telegram (rightNavigationButtonForChatInterfaceState) shows More instead, with the same menu plus Search | fixed `d4e0e24f`: the chat bar shows More in the avatar slot for a whole-forum history, with View as Topics, View as Messages (checked), Group Info and Search; View as Topics stores the choice and replaces the chat with the topic list. Simulator: menu shown and View as Topics restored the topic list |
| F31 | P2 | Forums had no way to create a topic; Telegram offers New Topic in the forum More menu (ForumCreateTopicScreen: name, icon color cycling through six colors, topic icon grid) and opens the new topic | fixed `6511163f`: UIKit port of the create mode (name field beside the icon, tap cycles Telegram's six colors, grid of the default icon plus TDLib's free topic icons from `getForumTopicDefaultIcons`, Done enabled for a non-empty name, spinner while creating, screen stays editable on failure); `createForumTopic` then opens the topic. Shown in both forum More menus when the user may create topics (owner, admin with manage topics, or a member the group allows). Simulator: created throwaway topics in the test forum, each opened at once. Premium emoji packs are not offered |
| F33 | P2 | Topics had no context menu; Telegram's `chatForumTopicMenuItems` offers Pin/Unpin, Mark as Read, Edit, Mute (Mute for… presets, sound, Mute Forever) or Unmute, Close/Reopen and Delete over a preview of the topic | fixed `266ca4e3`: the same items, permissions (manage topics, own topic, delete all messages; General can't be edited, closed or deleted; a closed topic hides Pin) and toasts; Edit reuses the topic screen in edit mode (`editForumTopic`, color fixed as in Telegram); Delete asks with Telegram's text. A new pin goes first (Telegram inserts it at 0; TDLib appends, so the order is rewritten with `setPinnedForumTopics`). Rows show the mute icon after the title and a grey badge when muted. Also fixed: a topic created while the list was covered by its chat stayed missing until the forum reopened (the hidden page applied an animated diff). Simulator on throwaway topics: pin (moves to the top live), close/reopen (service messages), edit name and icon, unmute, mute for 1 hour (toast), delete with confirmation; all throwaway topics deleted. Mark as Read not exercised (nothing unread). Notifications fixed `a54f97b1`/`11a82aa7`: Mute for… gains Custom (mute until a picked date) and the Mute menu gains Customize, Telegram's notificationPeerExceptionController, also from the profile's Mute menu: Always On/Off, message preview, a private chat's story notifications and author name, and the sound from `getSavedNotificationSounds` (own tones with swipe Delete and Upload Sound within `notification_sound_size_max`/`duration_max`, Default, None, Telegram's alert and classic tones recognized by TelegramCore's cloudSoundMapping file ids); a picked tone plays and Done applies everything with the muted toast for Always Off. The message menu offers Save for Notifications first for an mp3 or voice message under 1 MB and 60 s that isn't saved and won't disappear (`addSavedNotificationSound`, Sound Added toast). Simulator: Customize from UI test's menu and BetterTG test's profile; a 2 s voice note saved as Cloud Tone, picked for UI test with previews off, kept on reopening; Always Off muted the topic with the toast; the group was muted again afterwards. TDLib returns no built-in tones for this account (empty list, so Default shows without a name and Alert/Classic are empty); Upload Sound's file picker was not exercised (no mp3 in the Simulator). Select `7cf1b8b8` (chatForumTopicMenuItems' Select, selectPeerThread, forumSelectionOptions, the forum branch of toolbarActionSelected): the menu ends with Select after a separator, the list edits with the topic checked, taps check and uncheck topics, the title reads ChatList.SelectedTopics, Done replaces the right buttons, and the toolbar offers Read (a checked topic is unread; each is read up to its last message, then editing ends) and Delete (delete-all right, General not checked), which asks DeleteThreadsConfirmation, hides the topics behind the DeletedThreads toast and deletes them once it is gone; Undo brings them back. Xcode MCP 10-18 on throwaway topics: Select from Select A's menu checked it (1 topic selected, Read off), Select B and General made 3 with Delete off; without General "delete 2 topics" hid both under "deleted 2 topics" and they were gone after the toast; General with an unread gamebot reply and Select C enabled Read, which cleared General's badge and ended editing; Select F came back on Undo and stayed after 6 s, then went on a second delete. Telegram's 0.8 s progress overlay during the deletion is not shown (the rows are already hidden) |
| F34 | P3 | After deleting a topic an empty band stayed above the list: the search slot was open with the field collapsed until the user scrolled | fixed `c0607b2d`: the bar re-syncs with the table once each snapshot completes. Simulator: deleting a topic leaves the search field visible in its slot |
| F35 | P2 | Smoke D3 (GIF part): the panel's GIF tab showed still thumbnails; Telegram plays visible GIFs silently in a loop | fixed `32906af5`: the cells reuse the bubble's looping player, cropped to the square and playing while visible; its download goes through the shared animated-file demand so off-screen cells cancel pending downloads. Simulator: frames 0.6 s apart differ, GIFs keep playing after scrolling |
| F36 | P2 | Smoke D8: a delete in Saved Messages faded the bubble, then the rows stalled and closed the gap in steps | fixed `797da998`: every structural apply reconfigured every date header (20+ reloads in each delete's animated apply); headers now reload only when their title changes. Simulator, 60 fps slit-scan: the rows close the gap in one continuous curve |
| F37 | P3 | Smoke D6: holding the video-note button without a camera started capture, AVCapture failed and the chat said "Video-note capture stopped unexpectedly." | fixed `58c9d6ff`: `beginVideoNoteRecording` checks for a camera first, as the photo camera does, and shows "No camera is available for video messages." without starting a recorder. Simulator: holding in video mode shows that alert; the mic/video toggle still works |
| F32 | P2 | Smoke D7: a new sticker or GIF showed under the bubble moving up for 2–3 frames after sending; the temporary-to-final id swap crossfaded two bubbles of different widths (the sending clock makes the temporary one wider) | fixed `074ee6ec`: the new latest rows get the same additive position animation UIKit gives the first row above them, so they rise together as in Telegram's history list; `ChatTimelineLayout` replaces the temporary row in place (hidden at once, final row drawn above it). The insertion offset is read from measured cells, not the 80 pt estimate. Simulator, 60 fps recordings in Saved Messages: a text after text, a sticker after text and a text after a sticker all rise with the rows above, no overlap and no double bubble. Test messages deleted afterwards |
| F38 | P2 | Smoke D5: an uploading photo showed only the clock; Telegram draws a radial progress disc with a cancel cross (`ChatMessageInteractiveMediaNode`, `RadialProgressContentNode`) | fixed `884cf2eb`, `8094ab41`, `e9ececca`: a 50 pt disc (black 45%, 60% at night) with a rotating arc over every uploading photo and album tile; a tap on it deletes the sending message for everyone as `progressPressed` does, and other taps on the media wait for the upload. The arc survives album reconfiguration and the pending-to-sent id swap and fades out in 0.25 s; album tiles keep their send order; the reveal session keeps public media visible across the upload revision. The sent media is inserted in the turn that clears the composer, the composer shrinks in the same transaction, the rows glide by the composer change on the insertion curve, and the bubble draws the composer's decoded image at once (Telegram's `applyMediaResourceChanges`). Simulator, 60 fps recordings (round 13, `/tmp/d13-evidence`; earlier rounds `/tmp/d5-evidence`, `/tmp/d7-evidence` to `/tmp/d12-evidence`): the history moves once without the earlier 96-107 pt jump, the bubble shows its image 1 frame after the composer clears (was 7 blank frames), composer thumbnails stay until the clear, discs fade in about 0.25 s, cancel deletes the message. Residuals: the history drifts 1 pt (album) or 3 pt (single photo) for 1-3 frames before the move; the album's time-label background blinked for one frame in round 12. Test messages deleted. Re-measured 10-17 in BetterTG test → UI test (sending allowed by the user, messages kept; Xcode MCP and simctl recordings `/tmp/send-photo.mp4`, `/tmp/send-photo2.mp4`, `/tmp/send-album.mp4` to `send-album3.mp4`, row shift per frame): the sheet's send first staged the photo in the composer for 0.65 s, so the history jumped 110 pt up in one frame, 108 pt back and then glided. Fixed in `ca333792`: media the sheet sends at once stays out of the composer (Telegram's sheet sends without staging it there) and shows only if the send leaves it; a scheduled send still waits in the composer. After it the history stays still until the bubble arrives and then moves once, monotonically, 227 pt in about 0.3 s, with no drift before the move; the album's time label goes from 18:46 with the clock to 18:47 with the check without a background blink. Limit: 1.3 s pass between the sheet closing and the bubble (asset export and TDLib's pending message), while the composer shows its clock in place of the microphone |
| F39 | P2 | Smoke D1: closing a played video flew the cover back and the bubble showed the cover on the last frame | fixed `b17d77cc`: the gallery player keeps an `AVPlayerItemVideoOutput` and the close flies the frame on screen (the sample-buffer frame for FFmpeg VOD while paused); a buffering surface keeps its last frame instead of revealing the cover. Simulator (`/tmp/d6-evidence`, `/tmp/d14-evidence`): Back and swipe closes fly the current frame and the bubble never flashes the cover. The still frame was a residual: playback went on, so the bubble resumed about 0.7 s later in the clip. Fixed `356a6f56`: the transition view keeps the frame underneath and attaches a second AVPlayerLayer on the same player over it (Telegram flies the live video node), on open, interactive drag and close; FFmpeg VOD keeps the still frame. Xcode MCP 10-17 in "Pavel Durov" (`/tmp/f39-live.mp4`): during the 0.33 s swipe-down close the clip's animation keeps moving inside the flying frame and the bubble continues from it without a jump |
| F40 | P2 | Smoke D2: a swipe-down close of a video moved in 30-60 pt steps and the background cleared in 1-2 frames | fixed `d13c4041`, `51bb74f1`: the cause was the chat under the gallery. A photo from the same channel dragged worse than the video, and in Saved Messages photo drags run at 60 Hz. In the channel "Павел Дуров" the main thread was busy 4.9 s of 6.6 s (Time Profiler: about 66% in Lottie's `CoreAnimationLayer.setupAnimation`) because `TGSStickerView` restarted a play-once animation every cycle and Lottie's Core Animation engine rebuilt the layer tree each time. Stickers now play one loop from the shared phase (Lottie's loop `timeOffset`), and main-thread time fell to 0.2 s of 6.6 s. Also, a video handed back to its bubble zoomed x1.39 and shrank for 0.25 s, because AVPlayerLayer animated its gravity and size change implicitly; the reattach now disables actions and lays out at once. Simulator (`/tmp/d14-evidence` to `/tmp/d16-evidence`): the video drag in that channel went from 20 Hz with duplicated frames to 36-38 Hz, the background fades over 2-3 frames, and the landing has no zoom. The residual stall next to posts with animated emoji is fixed in `31caecd6`: the chat coming back under a closing gallery restarted every sticker and emoji at once, and Lottie built each animation on the main thread. Gallery dismissals now hold sticker playback until the gallery lands, then resume one sticker per frame. A/B in that channel with the same Xcode MCP drag (`/tmp/f40-A.mp4` without the hold, `/tmp/f40-d.mp4` and `/tmp/f40-final.mp4` with it): without the hold the fade froze at YAVG 126 for about 140 ms mid-drag; with it the fade runs continuously from YAVG 29 to 219 in nine 25-30 ms frames, and a cancel returns to the gallery in 0.33 s. The 130-190 ms delay before a drag starts was not re-measured because the touch moment is not visible in a recording |
| F41 | P2 | Smoke G1: the attachment picker offered only photos (`PHPickerFilter.images`), so videos couldn't be sent; Telegram's picker sends videos with the same radial progress | fixed `23bb507d`, `bfa2c515`: the picker accepts videos. `VideoSendTranscoder` converts the clip through TDLib file generation (`finishFileGeneration`) and the disc shows conversion as the first half of its arc. A tap on the disc cancels: in an album it deletes only that item, as Telegram's `progressPressed` does, and taps elsewhere on sending media do nothing. A sent video keeps the frame it was picked with (aspect fill, no spinner or play icon) until inline playback takes the bubble. The disc stays while the message is pending, as Telegram keeps the status while `isSending`: an album tile whose file uploaded before the rest replaces the arc with a check (`RadialCheckContentNode`), and a single bubble keeps the full ring until the server confirms. Simulator (`/tmp/g1r-evidence` to `/tmp/g1r4-evidence`): the arc grows monotonically, cancel deletes the message, the check transition takes 0.17-0.19 s, the discs fade over 0.19-0.25 s with no white frame, blur or play icon, the video plays inline for 12 s, and the gallery opens and closes without distortion. The converted file is 464x848 H.264 High L3.1 at 30 fps and 1.63 Mbit/s with AAC LC 44.1 kHz stereo, moov before mdat. Send took 98-195 s for a single 12 s video and 2-4.8 min for an album. Residuals: a tap on the check while the album is still sending is unverified; after cancelling the video of a two-item album, the remaining photo jumps from a 148 pt tile to a 210 pt bubble in one frame; the album's time background still blinks for 1-2 frames near a tile's completion (F38); media sizes: fixed as F43. Re-check 10-17 in UI test (allowed by the user): a tap on the uploaded photo's check while its album was sending removed the photo, as Telegram's progressPressed does (its status stays `.Fetching` at 100 % while the message sends), and the album became the single video. The disc of a sending video that already plays inline from its local file had no cancel action and any tap opened the gallery; fixed in `49fa071f` and rechecked: a tap on the disc at 50 % removed the video. No time background blink at completion (F38). Residual: an album that loses an item lays out again in one frame (a 243 pt two-item album became a 316 pt single video and the rows above jumped 73 pt), where Telegram animates the bubble's new layout; the timeline's diffable reconfigure would need to animate the row height together with viewport restoration. Tried 10-17 (UI test, photo + video album, the photo cancelled at 50 %, 60 fps `/tmp/f41f.mp4` frames 1726-1780): gliding the visible rows from their old screen positions after the reconfigure started one frame late (frame 1729 shows the final layout) and slid the row above over the already grown video for 0.3 s, so it was reverted (`/tmp/f41-glide-attempt.patch`). Fixed 10-17 (`19b25a90`, `3c4caf97`): the album row's transition starts right after the snapshot applies, with the viewport restored early, because the diffable completion arrives a frame after the layout commits. An album that becomes one message is Telegram's removed and inserted list item (a group entry exists only for two or more): the old bubble shrinks into its center and fades in 0.15 s (`animateRemoved`), the new one fades in over 0.2 s inside a height that grows from the old one, and every row moves over ListView's 0.4 s on the iOS 26 `.spring` (mass 1, stiffness 555.027, damping 47.118). An album that keeps two or more members moves its tiles from their drawn frames to the new mosaic over the same transition, a tile that left fades in 0.25 s (`animateRemovalFromBubble`), and a new one fades in. Simulator, UI test (Xcode MCP, 60 fps `/tmp/f41g.mp4`, `/tmp/f41h.mp4`): photo + video album, photo cancelled: the row above slid 609 to 451 pt in 6-28 pt steps with the new video's top edge 5 pt below it every frame, no jump; photo + video + photo album, video cancelled at 57 %: the video tile faded, the remaining photo grew from its 1/2-width tile to the full-width bottom tile and the top photo rose with the rows above. Sending an album shows no crossfade |
| F42 | P2 | Smoke S1/S2: after a photo was deleted with the keyboard up, a text row that scrolled back into view ("parity merge smoke" 03:48, once the forwarded message) collapsed to 11 pt and stayed so until the user scrolled; rows above shifted 21 pt down | fixed `20fb242b`: the reused cell came from a photo, and its text wrapper in the bubble stack was still hidden while the text view itself was visible, so the stack measured 0 and the cell kept only the 6 + 5 pt bubble insets. UIStackView counts each `isHidden = true` on an arranged subview made inside an animation block, and the photo cell had been configured that way several times, so one `isHidden = false` did not show the row. `setHiddenIfChanged` assigns only real changes to the bubble and row stack items (text and metadata wrappers, media, avatar) and to the forward avatar and reply quote icon. An offscreen probe reproduced 11 pt after three animated configures of a photo cell and measured 32 pt with the fix. Simulator (`/tmp/s1-evidence`, `/tmp/s2-evidence`, `/tmp/s3-evidence`): before the fix the S2 cycle collapsed 03:48 to 11 pt on the first try; with the fix two cycles kept all three rows at 32 pt and the forwarded message at 225 pt at about +2-8 s and +13-20 s |
| F43 | P2 | F41 residual: media bubbles kept BetterTG's 280 pt width and 140-320 pt height, while Telegram sizes images up to 300x380 and video to the bubble width with 250/360 pt height caps; a group left with one item still drew a one-tile mosaic | fixed `0e6404bc`: `TelegramMediaLayout` ports `ChatMessageInteractiveMediaNode` with the compact `ChatMessageItemLayoutConstants`: images fit 300x380 with a 170x74 minimum, video takes the widest bubble width with a 250 pt landscape and 360 pt portrait cap, animations aspect-fill to 480, stickers fit a 184 box (`ChatMessageStickerItemNode`), media without dimensions is 256x256. Albums fit 300x380 to the width (`ChatMessageBubbleItemNode`), and a group with one visual item renders as single media, as Telegram builds a mosaic only for two or more. Media lays out again when the cell width changes. Simulator (`/tmp/m1-evidence`): waterfall photo 300x199 (was 280x187), portraits 235-237x316, narrow photos 170x321/370, wide photos 300x74-115, portrait video 176-260x316, landscape video 268x249, video sticker and large emoji 184x184 without a bubble, video note 260x260, albums of 2-4 items within 300x380; a 5-item album is 303x491 because Telegram's mosaic targets 400 pt and rounds up for five or more. Across 23 hierarchy snapshots and 9 flings in two chats no cell changed height after appearing. Residuals: single portraits stop at 316 pt because the width bound (82% of the cell) limits them first; an album reduced to one item by deletion is unverified. Re-check 10-17 (Xcode MCP hierarchy, Swiftgram Чат, about 25 screens of history): the video stickers 🤜 and 🤩 are 184×184 cells without a bubble; no static WebP or TGS sticker and no GIF was in the loaded history. Sending pass 10-17 in BetterTG test → UI test (allowed by the user; Xcode MCP hierarchy): a saved GIF is a 300×311 pt bubble; the 👄 and 👍 duck, 👋 cherry and static 📖 WebP stickers are 184×184 cells without a bubble. After F56 the duck and cherry animate (frames 0.4 s apart differ, PSNR 12.6 and 15.0 dB) and the WebP's frames are identical; before it every sticker drew as a video sticker |
| F44 | P1 | Paging the gallery from a three-item album through a video to a five-item album crashed with `NSRangeException` | fixed `00cd4db9`: `centerSelection` asked the flow layout for an item the new strip did not have yet; item centers now come from the strip's own widths and spacing |
| F45 | P2 | Gallery "Show in Chat" landed a tall target with its middle off screen and left it there once off-screen rows self-sized | fixed `a2b496d4`: the target is centered again while rows self-size (up to four passes), and a row taller than the content area lands with its top under the navigation bar, as Telegram's `.center(.bottom)` does in its flipped list. Simulator (B1-b, `/tmp/b1-evidence`): an 880 pt post lands 8.3 pt under the bar; a 491 pt album is centered within 1.2 pt |
| F46 | P2 | The chat media gallery numbered and paged newest first; Telegram pages oldest to newest and the newest item reads "N of N" | fixed `efa5f8dc`: `getChatMessageCount` and `getChatMessagePosition` with the photo and video filter number items from the oldest; deletes shift the numbering. Simulator (B1-c): the newest photo opens as "2570 of 2570", 17 swipes step by ±1 across albums and a video with no shift after settle, and the strip order matches the tiles |
| F47 | P2 | The context menu glass did not react to a finger dragged across it; the system menu (and CustomContextMenu) stretches toward the finger and springs back | fixed `15de6f61`: the menu carries the system's flexible `_UIViewGlass` (variant 0, flexible, flex variant 5, no grouping) through `_setBackground:`, which installs UIKit's `_UIFlexInteraction`; interactive `UIGlassEffect` is the fallback. Simulator (B1-a, B2-b): the glass follows the finger, holds, and relaxes in 0.13-0.17 s with 1-2 pt overshoot (system 0.18-0.2 s); the menu stays open and nothing is selected. Residuals: the translation is about half of the Photos Sort UIMenu for the same vector (10/19 vs 21/29 pt; size stretch equal at +9), a compact menu without preview, so the reference is not the same menu type; in 1 of 2 runs the glass did not move during the drag and jumped once at release. Re-measured 10-17 with Xcode MCP `mt` drags on a chat-row menu (a chat, 60 fps `/tmp/f47-r1.mp4`, `/tmp/f47-r2.mp4`): the glass followed the finger in 2 of 2 runs. A 178 pt drag left off Pin moved the left edge 5 pt toward the finger (right edge 1.7 pt, width +3.3 pt); a 165 pt drag down off Unmute moved the bottom edge 6.3 pt with the top fixed. Both held while the finger held and relaxed in 0.20-0.21 s with a 1 pt overshoot; the menu stayed open and nothing ran. The stuck run did not recur; the smaller travel than the system menu stays the open residual |
| F48 | P1 | Smoke B1/B2: returning from the background showed "Waiting for authorization", then a white screen; after the first fix the open chat closed about 1.8 s after return, and the latest edge flashed for two frames before the restored viewport | fixed `d9bf1d4e`, `24adfa6b`, `6a1d03ea`, `e3389c5f`: the foreground ownership restore recreates the TDLib client, which reports `waitTdlibParameters` before `ready`. The root treated that as a logout and its transition removed the shared chat stack. A same-account renewal now keeps `loggedIn`, and a returning controller is brought back without removal. `AppLocalization` posted `appLanguageChanged` after every new client, so the root rebuilt the stack; it now posts only when the pack changed. The replacement chat controller starts under a snapshot of the old history and lands the restored viewport until its anchor holds (up to four passes). The chat list keeps its rows for up to 5 s while the renewed client reloads, and loads only once the account is ready. Simulator (B3, `/tmp/b3-evidence`; B4): four foreground cycles with no white or Login frame and no latest-edge flash; the chat stays open 10+ s; the Saved Messages viewport returns with Δ0 pt; the chat list keeps rows, tabs and position |
| F49 | P3 | Smoke B1-b: the message highlight after "Show in Chat" switched on and off in one frame; Telegram fades it out | fixed `5cff3c9a`: the highlight shows at once and fades over 0.3 s with a layer opacity animation, because UIView animations do not run inside the timeline snapshot apply. Simulator (B3-B): on for 1.09 s, then a monotonic 13-frame fade of about 0.22 s |
| F50 | P2 | Smoke B2-c, B6-D: "Scroll to latest message" after scrolling far up stopped short. In Saved Messages after a client renewal the first tap stopped inside a 2110 pt post days above the bottom, the second 46 pt short | fixed `22b2fb0e`: the animated scroll ran over rows that self-sized on the way, each resize moved the offset and ended the animation partway, and snapshot anchors and viewport restoration could write the offset mid-flight. As Telegram's list does before it animates to an item, the scroll now lays out the destination first, animates at most one screen over rows that already have their sizes, and owns the viewport until it lands. When the loaded rows don't reach the newest message, the history is reloaded there first (with a gap marker down to the loaded rows). Simulator (B7 D/E, `/tmp/b7-evidence`): one tap from Mar 2 in Saved Messages lands at the rest position of the newest message, and from Aug 29 in a group chat; the animated travel is about 655 pt (B6: about 1750 pt). Residual: in the Saved Messages run the whole history was already loaded (`more false`), so the reload branch is unverified on the Simulator |
| F51 | P1 | Smoke B4-C: returning from the background with the chat media gallery open turned the photo black, and its pages, counter and sender stopped loading; closing it moved the chat by 52 pt | fixed `eea34497`: the renewed client of the same account keeps the gallery's route. The gallery loads the chat and its items through the new client (`getChat`, `getMessages`), rebuilds its playback context and reveal session (revealed spoilers stay revealed when the revision is unchanged), re-enables history paging and reconfigures its pages, so the shown photo keeps its pixels and zoom. Image views keep their pixels on a same-account origin change until the owner reloads them. Simulator (B5-C, `/tmp/b5-evidence`): no black frame through the launch zoom, sharpness 1107-1116 vs 1110 before Home, pages 4/3/2/1 of 6 load with sender and date, the chat returns with Δ0 pt |
| F52 | P2 | Smoke B5/B8/B9: after returning from the background, chat list rows showed a neighbour's avatar or letter placeholders until the renewed client downloaded the photos | fixed `fc75debc`, `95a246ff`: the renewed client can reuse a file ID for another file, so held rows keep their own avatar (or the inline thumbnail) until the renewed client lists the chat again, and a renewed avatar replaces the old one only after it decodes. Held rows also take the decoded image cached by remote ID (F53). Simulator (B6, B7, B10; `/tmp/b10-evidence`): no neighbour avatar in any frame; rows are sharp 0.1-0.2 s after the launch zoom. Residual: every row shows letters for 6 frames (≈0.05 s) at the end of the launch zoom in one cycle and 3 frames in the other (B9: 10 and 9) |
| F53 | P2 | Smoke B5/B6-C: returning from the background in a chat drew the pinned banner at 2x scale, hid the scroll-to-latest button for 0.1-0.18 s, and blanked a photo bubble and the PDF thumbnail for a frame; after the fix the banner labels drew 4.3 pt lower and doubled during the handover | fixed `0cf9d03d`, `8f092a56`, `bbd886ed`: the old controller freezes its insets and banner once the client renews; the replacement starts under a snapshot of the old banner, which fades out over 0.2 s once the renewed client answers for the pinned message (or 1.5 s pass), and keeps the button its predecessor showed until the restored viewport lands. Decoded images are cached by remote ID within the account, so the renewed client finds the same pixels. The banner's text stack follows Telegram's layout (title at 6 pt, text 17 pt below it), so its labels keep their frames through a rebuild. Simulator (B7-C, B9-C, B10-C): the button and the photo stay in every frame, the PDF thumbnail is never blank, the labels keep 15.7 pt frames at y 112 and 129 before Home, after return and after reopening, with no doubled text; chat dy 0 |
| F54 | P1 | Smoke B6/B8/B9: returning from the background moved the chat list by +13/+57/+22 pt with an animated scroll and a white band, collapsed the list to a few dozen rows that grew back one at a time, and swapped pinned rows for 0.3 s | fixed `6e90f47f`: TDLib answers `loadChats` before the app has consumed the updates sent first, so ending the renewal hold on that answer dropped held rows. The hold now ends once the store lists the held chats the renewed client still lists, in the client's order (or at the 5 s deadline), and held rows keep their position meanwhile. Folder controllers whose folder survives the reload are reused, and a snapshot that lands away from the top keeps the topmost unchanged visible row in place. Simulator (B10, `/tmp/b10-evidence`): dy 0 in both cycles (top of the list and five rows down), no row animation and no white band after the launch zoom |
| F55 | P2 | Smoke B7-F/B8-F: returning from the background with the profile's shared media gallery open dismissed the gallery; after the first fix, closing it left every grid cell as a spoiler cover for 49 s and one cell as "Couldn't refresh" | fixed `3d22bf2f`, `283f097f`: a same-account renewal keeps the profile's gallery current; the profile skips revoke and leave while the gallery is open, and is replaced on the next main turn after the gallery is dismissed. The "Reconnecting" prompt waits 0.5 s. Shared items whose content the refresh cannot classify are confirmed with the tab's search filter. Simulator (B9-F, B10-F): the same photo stays sharp with no black frame, paging works, the live grid appears 0.25-0.48 s after the close with no scroll, and "Reconnecting" is never shown. Residuals: the sender name is missing for 6 frames at the end of the launch zoom; on close, 7 frames show the old grid with spoiler covers, 2 frames a letter avatar with a collapsed header and loading cells, and 2 frames blurry thumbnails; a rich message in the photo and video index drew a spoiler cover and a tap opened nothing: fixed `b65d80a0`, the grid shows the first photo, video or animation block of a rich message (or the first paid media item), as Telegram's grid shows a message's first image, and a tap opens the message in the chat because the gallery plays only photo and video messages. Simulator: a channel's rich post shows its picture in row 5 and opens at the post |
| F56 | P1 | Sending pass 10-17: every sticker in history drew as a video sticker (label 'Video sticker'), so TGS and WebP stickers never reached their own views. TDLibKit's generated instance `typeID` returns one constant for every payload-free case of 202 `TDNative*` enums: `TDNativeStickerFormat` always reports WebM, and the eleven payload-free `MessageContent` cases all report `messageUnsupported` | fixed `1d883a25`: the sticker view is chosen by the format case, and message content compares through `constructorID`, which maps the payload-free cases to their own constructors (rich content invalidation, service text reuse, the shared media cell signature). Xcode MCP 10-17 in UI test: the duck and cherry TGS stickers read 'animated sticker' and animate, the 📖 WebP is static. The generator bug stays in TDLibKit (`SchemaViews.swift`); fixing it there is a separate release |

### Post-merge audit — 2026-10-14

Read-only code audits at `224b76f9`; "confirmed" means the whole code path was traced in source. Status is updated as slices land.

| ID | Sev | Finding | Status |
|---|---|---|---|
| T1 | P1 | A jump to an old message merges a 50-message window into the latest page and leaves a permanent gap (`ChatVM.applyMessageWindow`); there is no newer-direction paging | fixed `f2f1b8c6`: each skipped range is recorded and loaded in 50-message pages from the side the user scrolls toward once its rows come within 12 rows; client restoration keeps the contiguous history above the newest gap |
| T2 | P2 | `ChatView.updateHighlightState` reconfigures rows and invalidates viewport restoration on every publish while a highlight is set | fixed `6d7150b4` |
| T3 | P2 | `updateHistoryInsets` treats the two-finger selection pan as idle scrolling | fixed `6d7150b4` |
| T4 | P2 | After a client change retires the timeline snapshot, rows render blank until restoration, and retire is never undone (A→B→A) | reviewed, no fix needed: an account switch rebuilds the root (`RootViewController.render` → `NavigationStorage.setRoot`), so a retired chat never returns to A; a same-account renewal replaces the controller under a snapshot of its history (F48), and a controller kept under the gallery is replaced when the gallery closes (F51). B3-B10 recorded no blank row in any foreground cycle |
| T5 | P3 | Two-finger selection ignores the menu's Select eligibility and the 100-item limit alert | fixed `b7a7499c`: no selection pan in a read-only topic; the limit shows the tap's alert once the pan ends |
| T6 | P3 | `mediaRevealSession.reconcile` of all messages runs on every enqueued demand | fixed `6c4703b5`: only rows whose canonical object or render revision changed are reconciled. Simulator (B2-c, `/tmp/b2-evidence`): no concealment placeholder stuck through flings in two chats; gallery returns land on the same bubble |
| T7 | P3 | `prepareGalleryReturn` reports success without a committed row | fixed `6d7150b4`: success only with the committed row, waiting up to 3 s |
| T8 | P3 | The all-chat-media gallery includes pending and self-destructing media; `loadNewer` can page from a temporary ID | fixed `3d7dd096` |
| T9 | P3 | `holdsComposerSendMessage` hides unrelated pending rows for 2 s; send alias eviction picks an arbitrary key; `messageHighlightTask` survives disappear | fixed `6d7150b4`, `1fa03419`: alias eviction takes the oldest key; the highlight task is cancelled on disappear; once the send returns, the composer hold keeps only the send's own pending rows |
| M1 | P1 | The gallery thumbnail strip loads spoiler and concealed media in the clear | fixed `3d7dd096`: the strip applies the page's reveal check |
| M2 | P2 | Gallery history paging reconciles stale opening copies with `replacingExisting: true`, undoing chat reveals and showing old files | fixed `3d7dd096`: pages only add messages, without replacing revisions |
| M3 | P2 | Live photo motion download is unscoped, never cancelled, and takes exclusive playback outside the gallery's audio coordination | fixed `3d7dd096`: cancelled on reuse and bound to the account that started it. The exclusive playback call was reviewed 2026-10-15: like voice and video notes, a Live Photo with sound stops voice playback through `Media.shared`, and gallery video takes the session through `GalleryPlaybackAudioSessionCoordinator`, which also stops `Media.shared`. The residual (a Live Photo started during a Picture in Picture gallery video switched the session under the PiP owner) is fixed in `30242357`: every `beginExclusivePlayback` caller (Live Photo, video notes, play-once voice, secret video) now pauses the PiP video and takes its session, as a voice note did. Build only: PiP was not run |
| M4 | P2 | GIFs on the FFmpeg path or without an inline owner ignore taps (the merge kept `onTap: nil`) | fixed `33c8323d` |
| M5 | P2 | Voice and video-note prefetch downloads are never cancelled | fixed `33c8323d`: cancelled when the row leaves the prefetch range unseen |
| M6 | P3 | A same-note reconfigure of a video note restarts its thumbnail load | fixed `33c8323d` |
| M7 | P3 | A gallery restored from PiP loses chat history paging (likely) | fixed `3d7dd096`: the restored gallery pages with its own history |
| M9 | P3 | Revision events reconfigure a bubble from the message captured at configure time (suspicion) | reviewed, no defect: the synchronous rebuild keeps the upload disc so it can fade out (F41), and ChatView reconfigures the row from the current message on the next main turn. Every media path asks for a permit (`requiresPermit: true`), and the stale key is current only as the predecessor of a public-to-public change, so the stale copy can show only pixels the previous revision already allowed; a spoiler edit shows the cover for that turn |

Reviewed and OK: TGS phase sync across loops, image loading and caches, animated file demand and download leases, inline media owners and pruning, gallery playback owners, Open in Chat account checks, video note playback and capture, reveal predecessors, custom emoji and frame caches, the F39 video output. Not reviewed: the profile avatar gallery, the profile shared-media gallery path, `GalleryFilePlayerView` range waiters, the video note writer finish path.

### Post-merge audit, second pass — 2026-10-15

Read-only code audits at `ba41fcd7`/`9a646c94` of profiles and shared media (P), the composer and sending (C), and the shell, chat list and accounts (L). "confirmed" means the whole code path was traced; runtime was not exercised by the audits.

| ID | Sev | Finding | Status |
|---|---|---|---|
| C-1 | P1 | Send rights combined `canPostMessages` with the chat's default permissions: channel owners and admins could not post (TDLib leaves a channel's defaults all false), group admins were bound by default restrictions, a restricted member's own permissions were ignored, a left basic group kept its composer | fixed `3ef0c699`: Telegram's banned-permission model (`CustomChat.allowsSending`): owner and admins bypass the defaults, a channel needs the post right, a restricted member is bound by both; basic-group status follows updates |
| L-1 | P1 | Chat deletion was wrong for every peer type: no "delete for me and X", groups only cleared history, channels and public groups had no item, an owner's delete for everyone used `deleteChatHistory(revoke:)` (rejected) with the error swallowed; no `leaveChat`, `deleteChat` or Clear History | fixed `eb525a29`: Telegram's `deletePeerChat` per peer type: delete for me or for both sides (with Telegram's warning), Delete and Stop for bots, leave for groups and channels (a left basic group is also removed), the owner's delete for everyone through `deleteChat` after a second warning, Clear History where Telegram offers it, status toasts and an error alert on failure. Build only: the destructive flows were not run on the user's account; the 5 s undo came with S-9 `9768eda9`; Appoint Another Owner (LeaveGroup.Text, AlertTransferHeaderComponent) names the server's future owner, which TDLib 1.8.68 has no request for, so it stays unported |
| L-2 | P1 | Chat list search only filtered titles of loaded rows; no TDLib chat, public or message search | fixed `708a2a1d`: Telegram's search sections over the main list and the archive: chats and contacts (`searchChats`, `searchContacts`, `searchChatsOnServer`), global public chats (`searchPublicChats`, Show More after three), and messages (`searchMessages`, paged); remote requests wait 400 ms, each query cancels the last, results of another account or client are dropped. Simulator: a query lists six matching chats, three public results and message hits; a message hit opens its chat at that message; Close Search returns to the list. Follow-ups: recent searches, the media/links/files filter tabs, query highlighting |
| P-1 | P2 | Any edit or unconfirmed delete of a loaded grid item closed the open shared-media gallery and its PiP at once | fixed `54604a45`: only the affected items are revoked; the gallery keeps their pages covered until their revision is admitted, PiP closes only for its own item |
| P-2 | P2 | A profile not opened from its own chat (forum Group Info, avatar Open Profile) stayed on "Reconnecting" with a blank grid after every foreground return | fixed `7c9c2c3b`: such a profile rebuilds itself through the renewed client |
| P-3 | P2 | A renewal with the avatar gallery open dismissed it and popped the profile | fixed `71681a32`: the gallery re-resolves its photos by remote ID on the renewed client (`getRemoteFile`) and keeps the shown pixels; the profile is replaced once it closes. Build only for the renewal |
| P-4 | P2 | Files, Links and Audio rows only jump to the message; Telegram opens the document, the URL or plays the track | fixed `b5313800`: a document downloads in place with progress and opens, a track plays, a link opens (a text link asks first); a long press keeps View in Chat. Simulator: a 7 KB .hex file opened the share sheet; Show in Chat on a link row opened the chat at that post |
| P-5 | P2 | Profiles opened away from their chat had no message, search or Message callbacks | fixed `7c9c2c3b` |
| P-6 | P3 | Gallery paging does not scroll the grid to the current item, so closing on an off-screen item fades | fixed `2139ccfe`. Simulator: after 14 pages in a 37-item grid the grid scrolled 317 pt and the shown item was in view on close |
| P-7 | P3 | Media sent while the profile is open never appears | fixed `2139ccfe`: `updateNewMessage` and `updateMessageSendSucceeded` add a matching message to the open tab. Build only |
| P-8 | P3 | Every grid snapshot reconfigures all cells and restarts uncached thumbnail loads | fixed `92299b14`: only cells whose readiness, revision, content type or reveal key changed are reconfigured |
| P-9 | P3 | The avatar gallery's downloads are never cancelled in TDLib | fixed `e0904b00`: shared download leases, cancelled in TDLib when no view needs the file |
| P-10 | P3 | Opening the avatar waits for two sequential requests; Telegram shows the current photo at once | fixed `0edcbc33`. Simulator: a user's gallery opens at once and becomes "1 of 3" when the list arrives |
| P-11 | P3 | Group and channel avatar galleries show only the current photo | fixed `0edcbc33`: earlier photos from `searchMessagesFilterChatPhoto`, paged |
| P-12 | P3 | The avatar gallery has no swipe-down dismissal and no Save/Share/Set as Main/Delete | fixed `790b4abd`: the media gallery's pan dismissal, Share and Save for unprotected chats, Set as Main and Delete on the own profile. Simulator: swipe down closes the gallery; footer shows close, share, counter, more. Set as Main and Delete were not run on the user's account |
| P-13 | P3 | The profile's own header avatar offered Open Profile and Search, which pushed copies | fixed `7c9c2c3b` |
| P-14 | P3 | "Administrators" is shown to every member and subscriber (suspicion: a retry footer for subscribers) | fixed `1c88c771`: shown only to the owner and admins, as in Telegram. Simulator: hidden in the profile of a group for a member |
| P-15 | P3 | Tapping a member opens the tag editor instead of the member's profile; no promote/restrict/remove | fixed `8dae1b0e`: a tap opens the member's profile; Send Message and tag editing are in the row menu. Promote, restrict and remove: G-7 `727e7704` (the row menu offers them as availableActionsForMemberOfPeer allows) |
| P-16 | P3 | Any group update resets the visible member rows and rereads all pages | fixed `5ccc920f`: only member count, status, activity or upgrade changes reread, and rows stay until replaced |
| P-17 | P3 | Voice, GIFs, Groups in Common and Members panes are missing | fixed `aa58932d`: Voice, GIFs and Groups in Common panes in Telegram's order, shown only with content. Simulator: a user's profile shows media, voice, links, gifs and groups (no files or music); voice lists a voice and a video message; groups lists the common groups with member counts. GIFs autoplay in the grid `5b65d15c` (PeerInfoGifPaneNode; Simulator: BetterTG test's gifs pane, frames 1.4 s apart differ at 19-26 dB PSNR). Members pane `2e6358c9` (PeerInfoMembersPaneNode, PeerInfoMembersContext): a group outside a topic with more than five readable members opens on a Members pane: Add Member first for whoever may invite, the account on top and up to 50 members by presence (a longer list keeps TDLib's recent order and pages 200 at a time), online in the accent color, bots with their history access, owner and admin labels in tinted pills, the account's Add Tag; a tap opens the member's profile, a long press opens Send Message, the tag, Promote and Restrict in a supergroup, and Remove. Round videos in the voice pane `c8a5be55` play in the floating circle (openChatMessage's voice playlist, OverlayInstantVideoNode); a second tap pauses or resumes them, and an incoming one is marked viewed. Verified 2026-10-18: a group (49 members) opens on members with лева online on top, True Mafia 'бот', Iris 'admin', presence and tags, paging to 'last seen a long time ago'; a long press shows Send Message (no rights here), a tap opens Iris's bot profile; BetterTG test (2 members) keeps media first; a contact's voice pane plays a round video in the corner circle, the circle pauses and resumes, and another row swaps the video |
| P-18 | P3 | A channel's profile read "10719795 subscribers" while its chat header read "10,719,795": plural counts fell back to the bare number | fixed `0a82bc42`: AppLocalization formats a plural count as PresentationStrings does, presentationStringsFormattedNumber with the locale's grouping separator from 1,000 up, and the profile no longer passes the bare number. Simulator 10-24: Telegram Tips' profile reads "10,719,754 subscribers" |
| P-19 | P3 | The Links pane listed a link as its message text with a generic icon | fixed `7cec2580` (ListMessageSnippetItemNode): a link row shows the link preview's picture, or the host's letter on Telegram's orange, at the left. Beside it are the preview's title (else the site or host) with the date, its description up to three lines, and the address without `https://` in the accent colour. A message without a preview takes its first web or email address, in its text or a media caption, with the host as the title, the message's own text as the description and a captioned photo as the picture. The chat list search's Links tab (L-23) uses the same rows without the description, as global search results do. Simulator 10-24: BetterTG test's Links pane showed LumberJack, the Telegram blog and telegram.org with pictures, descriptions and addresses; "telegram.org" in search's Links listed snippets, a lettered site and a captioned photo's link. Not ported: the author line of a global result |
| P-20 | P3 | The Files pane listed a file as its name under a generic document symbol | fixed `a1c11775` (ListMessageFileItemNode, generateExtensionImage and extensionColorsMap): a file row shows its JPEG preview with 6 pt corners or Telegram's 40 pt card. The card has a folded corner and the extension's gradient (red for slides and PDF, green for sheets, yellow for archives, blue for the rest), with the extension in rounded bold 15 pt, or 14 pt past three letters. Beside it are the name, the caption on a line, and the size with the full date; the chat list search's Files tab (L-23) puts the date at the right instead, as global results do. The download bar stays. Simulator 10-24, "receipt" in search's Files: PDF cards with the fold, previews for files that have them, sizes, a caption and dates. Music and voice `dbf0d26f` (ListMessageFileItemNode's audio, voice and round video items): a track shows its album cover with 6 pt corners under a play mark, or the play button on the accent colour, its title or file name, and its length with the performer, or the size without one. A voice message or round video shows the play button or the round video's frame, its sender (You for the account, named once TDLib gives the user), and its length with the full date. The search's Music and Voice tabs move the date to the right. Simulator 10-24: BetterTG test's Voice pane showed the play button, "you" and "0:02 • oct 18, 2026 at 01:46". Not ported: Telegram's status ring with the download arrow or pause over the icon, a channel's name as the sender |
| C-2 | P2 | Text was sent untrimmed and unsplit; the server rejected over-long text after the composer cleared; whitespace enabled Send | fixed `7e26234a`: trimmed and split at 4096 as `breakChatInputText`; captions over `message_caption_length_max` stop before send. Simulator: a 4576-character paste sent as two messages split at a full stop; "  c7 edit probe  " sent trimmed (test messages deleted) |
| C-3 | P2 | Failed text, photo, document, sticker and GIF messages had no Resend | fixed `45538cdf`: Resend and Resend N Messages in the message menu (`resendMessages`), as in Telegram's failed-message menu. A failed send was not reproduced on the Simulator |
| C-4 | P2 | A pending forward is lost on a same-account client renewal | fixed `aa6a69bb`: the composer transfer keeps the forward and moves its source to the renewed client of the same account. Simulator: a group message forwarded into Saved Messages stays in the composer after a 60 s background cycle and its chat controller replacement; cancelled without sending |
| C-5 | P2 | The album caption was attached to every item | fixed `00903bc7`: first item only |
| C-6 | P2 | A GIF took the input's text as caption and cleared it | fixed `00903bc7`: the GIF is sent alone, the text stays, only the reply clears. Simulator: GIF sent with "gif caption probe" in the input arrived without a caption and the text stayed (test GIF deleted) |
| C-7 | P2 | Edit mode left attachments, stickers and GIFs available | fixed `8f24e855`: editing offers only emoji input. Simulator: the attachment menu shows only Emoji, the picker only the emoji tabs |
| C-8 | P2 | Photos are re-encoded at full resolution (quality 0.92); Telegram scales to 1280 px (2560 HD) | fixed `9dbbe683`: ImageIO thumbnailing to 1280 px off main, orientation applied, sRGB, progressive JPEG 0.72 (Telegram: mozjpeg 72). Simulator: a 4:3 library photo sent as 1280x960 without an orientation tag; the bubble keeps its 4:3 shape. HD (2560 px) is not offered |
| C-9 | P3 | Slow mode and the voice/video note restriction are not modeled | fixed `20b97392`: a send during slow mode keeps the input and shows Telegram's slow mode notice with the time left; recording is hidden for a user who restricts voice and video notes. Residual: Telegram keeps the microphone and explains the restriction in a tooltip; no slow mode chat or restricting user was available to check |
| C-10 | P3 | The sticker sheet keeps the presenting client; a tap after a renewal is lost | fixed `52ea4c09`: the sheet closes when the client renews |
| C-11 | P3 | Cancelling an edit clears a pending forward | fixed `3fcc0fdd` |
| C-12 | P3 | An edit resets link preview options and caption-above-media | fixed `3fcc0fdd` |
| C-13 | P3 | Temporary files of picked photos, videos and Live Photos are never deleted | fixed `f124bbec`: picked media share the documents' lease store; removal deletes unleased files, a send leases them to its messages and deletes them 120 s after success, a failure keeps them for Resend. Simulator: removing a picked photo deleted its file at once; a sent photo's file was gone 2 min after the send |
| C-14 | P3 | The typing action is debounced 350 ms and sent while editing | fixed `1c57cc42`: sent on the first keystroke, renewed every 4 s, cancelled 4 s after the last, not while editing |
| C-15 | P3 | A sticker or GIF tapped during another send is dropped silently | fixed `52ea4c09`: it waits for the composer's send and goes out after it |
| C-16 | P3 | Edit mode survives deletion of the edited message (suspicion) | fixed `3fcc0fdd`: a permanent delete of the target ends the edit |
| L-3 | P2 | Secret chats never appear in the list | fixed `10bcbfa5`: listed as rows for their user with a green lock title, opened like private chats, sending only once the secret chat is ready. Build only: the account has no secret chat; creating one is out of scope |
| L-4 | P2 | Switching accounts could delete a recovered account's database, and a directory was removed with whichever client was published | fixed `45ee11f4`: only an account whose own client reports a sign-in step is discarded, with its own client |
| L-5 | P2 | Pinned chats can't be reordered (`setPinnedChats`) | fixed `c760ed93`: Reorder in a pinned chat's menu (Telegram's pinned-topic pattern; BetterTG has no list Edit mode) puts the page in table reorder mode with a Done button; pinned chats move only among pinned rows and each drop saves the whole pinned order with `setPinnedChats`. Simulator: Reorder shows handles on the six pinned rows and a Done button; Done leaves the order unchanged. A drag was not exercised, as it would change the user's pinned order |
| L-6 | P2 | Rows show no mention or reaction badge; Mark as Read keeps them | fixed `526d2d36`, `e1686bdb`: Telegram's @ and heart badges left of the unread count; Mark as Read also marks mentions seen and, as Telegram, leaves reactions. Build only |
| L-7 | P2 | Login handles only phone, code and 2FA (no email, sign-up, QR, resend, wrong number) | fixed `6dadea33`, `88f04c1d`: email address and code (with reset), sign-up with the terms of service, QR login (CoreImage QR; leaving it restarts an unfinished sign-in only), code types, resend with Telegram's countdown, Wrong number back to phone entry, password recovery by email. `-ui-probe-login-authorization` passes, including the new email, sign-up, QR, wrong-number, resend and recovery checks. A live login was not run (it needs signing out). Follow-ups: Apple/Google email sign-in, Reset Account, passkeys |
| L-8 | P2 | A notification for an inactive account does nothing | fixed `7280f2dc`: the tap finds the account by user ID, switches to it once a client is ready and opens the chat when that account is ready, as Telegram's `openChatWhenReady`. Build only: no second account is logged in |
| L-9 | P3 | An account switch shows "Waiting for authorization" until Ready | fixed `b68368de`: an account with a known user keeps the chat list shell (with a loading list) until its client reports a sign-in step or Ready. Simulator: a cold start shows the chat list and folder tabs without the Login screen; the switch itself needs a second account |
| L-10 | P3 | Folder updates rebuild every folder page and reload 100 chats per folder | fixed `2bccb649`: a surviving folder keeps its object and takes the new definition; only new or empty lists load. Simulator: folder tabs switch, and after a background cycle the list returns on the same tab |
| L-11 | P3 | Chat menu eligibility differs from `chatContextMenuItems` (Archive/Mute for Saved Messages, Mark as Unread for forums and channels, folder membership from loaded rows, swallowed pin errors) | fixed `eb525a29`: no Archive or Mute for Saved Messages, no Archive for service notifications, no Mark as Unread for forums; Add to Folder reads `chat_lists`; pin and folder limits show Telegram's limit alert; row actions report failures |
| L-12 | P3 | Voice, video note and rich drafts show "Draft:" with nothing after it | fixed `05b2c36d` |
| L-13 | P3 | Deleting a shared folder never offers to leave its chats | fixed `4b1f981c`: Telegram's flow: a link warning, then a sheet of the folder's groups and channels with the chats `getChatFolderChatsToLeave` suggests preselected, and `deleteChatFolder(leaveChatIds:)`. Telegram plural strings with %d now format the count. Build only (destructive). Undo toast `4f421ad1`: the folder tab and the chats it leaves hide at once, Telegram's removedChat toast (Folder X deleted, You also left N chats) offers Undo for 5 s, then the folder is deleted. Simulator on a throwaway shared folder: removal from the tab menu and from Chat Folders showed the toast and deleted the folder after it; Undo brought the tab back and the folder was still there 8 s later |
| L-14 | P3 | The app icon badge is never set locally (suspicion) | fixed `12d98a49`: the badge follows the main list's unread count outside muted chats. Simulator: the icon reads "3 new items" with one unmuted chat at 3 unread |
| L-15 | P3 | Sender names in row prefixes are cached per client and never refreshed | fixed `05b2c36d` |
| L-16 | P3 | Rows show no typing indicator | fixed `eaed32e9`: rows take `updateChatAction` and show Telegram's activity text (bare action in a private chat, name and action in a group, pair or count for several). Build only: nobody typed in the visible chats during a 30 s watch. The animated indicators followed in L-22 |
| L-17 | P3 | Rows showed no online marker | fixed `580130b4` (ChatListItem's PeerOnlineMarkerNode, PresentationResourcesChatList.recentStatusOnlineIcon, PeerUtils' isServicePeer): a person who is online right now gets Telegram's 14 pt green dot in a 2 pt ring of the row's colour, 2 pt inside the avatar's bottom right corner; it scales in and out when the presence changes in a shown row. The chat list store now takes `updateUserStatus`. Saved Messages, Telegram's service accounts, support and bots go without. Simulator 10-24: `-ui-probe-online-marker` marks every person, and the dots sat on the avatars' edge with rings in the card colour. Not seen live: nobody in the list was online during the check. Video chats `a7c2b782` (ChatListItem's onlineIsVoiceChat, PeerOnlineMarkerNode's VoiceChatIndicatorNode): a group or channel whose video chat has people in it gets the 22 pt green marker, overhanging the avatar by a point less a pixel, with three white bars rising and falling every 2.2 s while on screen; both markers scale in and out over 0.2 s, and found messages carry neither. Simulator 10-24: the probe flag marked every group in the groups folder with the moving bars, and without it no group showed one, as none had a video chat |
| L-18 | P3 | Rows didn't show a chat's auto-delete timer | fixed `47aec64c` (ChatListItem's avatarTimerBadge, AvatarBadgeView with its timeout icon, AvatarNode's badgeView, shortTimeIntervalString's large format): a chat with `message_auto_delete_time` gets a 24 pt badge flush in the avatar's bottom right corner. Its fill comes from the avatar's own picture, or the placeholder's last gradient colour: blurred to one colour, saturated 1.7× and darkened slightly. On it sits the period in bold ("1d", "1w", "1m", "1y"), white or grey on a light picture, inside a ring solid on the left and dashed on the right. It shrinks away while an online or video chat marker shows, and found messages carry none. Simulator 10-24: `-ui-probe-timer-badge` gave the groups folder day and year timers, and the badges showed Telegram's look, each fill taking its avatar's colour. Not seen live: no chat in the list has auto-delete on |
| L-19 | P2 | Rows named media in words only ("Photo: caption"), without Telegram's thumbnail | fixed `88e19215` (ChatListItem's contentImageSpecs and textLeftCutout, ChatListMediaPreviewNode, chatListItemStrings with `enableMediaEmoji` off): the last message's photo, video, GIF or round video, or a link preview's picture (photo, video, embed, GIF, document and album pages), shows as an 18 pt thumbnail a point into a 23 pt gap at the start of the text, after the author and the forward mark. It has 2 pt corners, or is round for a round video, and Telegram's MiniThumbnailPlay sits over a video. The text then reads the caption alone, or Photo, Live Photo, Video, GIF or Video Message without one; a GIF always reads GIF. Spoilered media keeps TDLib's blurred minithumbnail; self-destructing media and secret chats get none, and an activity, a draft or a service message hides it. Simulator 10-24: the channels folder showed photo, video, forwarded and link thumbnails with the play mark on videos, and a group's video read its caption after its thumbnail. Albums `cf9bae09`: a last message in an album loads the album's other messages once per client (`getChatHistory`, ten back) and shows up to three thumbnails oldest first, 2 pt apart, with the group's first caption, else the last message's kind; `-ui-probe-row-icons` passed the three-item cap, the first caption, the last kind and the width, and a channel's photo album showed three thumbnails and its caption, where it had read "photo". Reduced: none for files sent as documents |
| L-20 | P3 | A forward read as a "↗︎" character, and no row showed the kind of a voice message, music, poll, checklist, game, location, call or story reply | fixed `5c8e0dbf` (ChatListItem's messageTypeIcon, forwardedIconNode and offsets, PresentationResourcesChatList's icons, chatListItemStrings with `enableMediaEmoji` off): the last message leads with Telegram's icon in the mute icon's grey: the forward arrow for any forward (not the Verification Codes account), the story reply mark, or the kind's icon, with incoming and outgoing voice and video calls apart. The icon sits 4 pt before the text, or 6 pt before a thumbnail. A poll then reads its question without the 📊, and a voice message or music with a caption reads the caption alone. `-ui-probe-row-icons` passed the icon choice, the caption texts, the thumbnail kinds (caption, play mark, round, spoiler minithumbnail, none in secret chats) and every asset, and its render showed forward, voice, location, video and round rows in Telegram's look. Simulator 10-24: the channels folder showed the forward arrow before a forwarded photo's thumbnail. Not ported: the gift icon, and dropping the forward icon where Telegram names the original author instead |
| L-21 | P3 | Row text was plain: lines kept their breaks, spoilers read as the word Spoiler, and a captioned file led with its name | fixed `ab7fd2d7` (ChatListItem's stringWithAppliedEntities with bold, code and links plain and italicTextFont, its dustNode, foldLineBreaks, chatListItemStrings' file caption): a text message's, caption's or poll question's entities show italic, underline and strikethrough, and its spoilers hide under TelegramSpoilerView's dust over the hidden text. Line breaks fold into single spaces, and a file with a caption reads the caption alone. VoiceOver still reads each spoiler as the word. `-ui-probe-row-icons` passed the folding, italic, spoiler range, strikethrough and VoiceOver text, and its render showed the italic word and dust over the spoiler. Simulator 10-24: the channels folder read as before. Custom emoji `1375f9c5` (ChatListItem's customEmojiRanges, TextNodeWithEntities): a custom emoji in the row's text loads its sticker through CustomEmojiStickerRepository and plays over its stand-in emoji, which turns clear, while the row is on screen; one under a spoiler stays hidden. `-ui-probe-row-icons` drew a row with a custom emoji from TDLib's emoji stickers in place of its stand-in. Not ported: drafts' entities |
| L-22 | P3 | Activities read as text with a static "…" in rows and as plain text in the chat header | fixed `98b77875`, `357d1549` (ChatTitleActivityNode's typing, voice, video, upload, game and sticker indicators, ChatListTypingNode, ChatTitleView's activity state): a row with an activity leads with Telegram's 24 × 16 pt indicator 3 pt left of the text's edge, in the text's grey at 85 %, and drops the ellipsis. The chat header puts the same indicator before an activity status in its accent colour, centred with the text. The indicators are the swelling typing dots, the spreading voice arcs, the pulsing recording dot, the crossing upload bar, the chomping game dot and the looking sticker eyes, each redrawn through Telegram's cycle (0.7 to 2 s) while on screen. Several people acting show typing dots. `-ui-probe-row-icons` passed the indicator choice for typing, voice, upload and sticker activities, and its render showed each. Simulator 10-24: with `-ui-probe-header-activity` (a local typing action from the Telegram account), UI test's header read "Telegram is typing" after blue dots that changed size between frames. Reduced: the English-only sticker variant with the eyes inside "choosing" |
| L-23 | P2 | The chat list's search had no filters; Telegram's tabs find media, links, files, music and voice messages across all chats | fixed `2ba443d2` (ChatListSearchFilter's chats, media, links, files, music and voice tabs, ChatListSearchListPaneNode's searchMessages with the tab's filter, ChatListSearchMediaNode's grid, the empty states): the results open with BetterTG's folder strip of Chats, Media, Links, Files, Music and Voice. Chats keeps the chats and messages found. Each other tab runs TDLib's `searchMessages` over the chat list with photo and video, URL, document, audio, or voice and round video filter, 60 a page as the list scrolls. Media is a grid of three tiles a point apart, or four on a wide screen, each the photo or the video's thumbnail with its length, and a spoilered or self-destructing one shows only TDLib's blurred minithumbnail. The others are rows with the kind's icon, the summary and the date. An empty tab shows Telegram's Nothing Yet with the tab's line, and a tap opens the message in its chat. Simulator 10-24, "receipt": Files listed the receipt PDFs, Media showed a photo tile, Music showed "nothing yet / music from all your chats will be shown here." Channels and Apps `b09bdf7a` (ChatListSearchListPaneNode's `.channels` and `.apps` keys, searchRemotePeers with the channels scope): Channels runs the chat searches with TDLib's channel type filter and finds channel posts with `searchMessagesChatTypeFilterChannel`, and Apps runs them with the bot type filter and finds no messages. Neither lists Saved Messages or contacts. Simulator 10-24, "durov": Channels listed the two Durov channels, three public channels with their subscribers and channel posts; Apps listed three bots. Not ported: Apps' popular mini apps, the Topics, Downloads and Public Posts tabs, date and chat tokens, filters before a query is typed, the gallery for a media tile (it opens the chat), and Telegram's link snippet rows |
| L-24 | P2 | Focusing the chat list's search showed nothing until a query was typed; Telegram shows the People row and recent chats | fixed `ad86068f` (ChatListSearchListPaneNode with no query, ChatListRecentPeersListItem with HorizontalPeerItem, recentlySearchedPeers, ChatListSearchContainerNode.clearRecentSearch): search shows its results as soon as the field is focused. Before a query, the results list People: TDLib's top chats with people (`getTopChats`), each an 80 pt column with a 60 pt avatar, its unread count, the online marker and the first name. Below is Recent: `searchRecentlyFoundChats` with an empty query. A chat opened from the results joins Recent (`addRecentlyFoundChat`), a swipe removes one, and Clear asks with Telegram's menu before `clearRecentlyFoundChats`. The filter tabs work without a query too. Simulator 10-24: BetterTG test opened from a search came back under RECENT with clear, whose menu asked "do you want to clear your search history?" and emptied the list; this account has top chats turned off (TDLib: "Top chat computation is disabled"), so People stays hidden, and `-ui-probe-row-icons` rendered the row with three people and a badge |

Reviewed and OK: profile update provenance and history paging identity, grid edit/delete reconciliation, the gallery order and counter, avatar gallery list updates, editor write authorization, members paging; composer double-tap guards, `resolveSendContext` topic routing, draft isolation and clearing, edit attempt binding, document temporary-to-final IDs, picker import account checks, video conversion off main; chat list update isolation and ordering, row action scoping, preview read state, logout ownership. Not reviewed: `PeerProfileInfoPermission` and members restoration internals, voice/video note recording beyond A11-A17, quote selection UI, `ForwardMessagesViewController`, folder editor validation, the forum topic list, push relay internals.

### Voice/video note and message content audits — 2026-10-15

Read-only audits at `6c697153` (voice and video notes, V) and `1ac7d7e2` (message content, R).

| ID | Sev | Finding | Status |
|---|---|---|---|
| V-1 | P1 | View-once and self-destructing voice notes play like ordinary ones (no conceal, no `openMessageContent`, unlimited replay, prefetched) | fixed `e97e1adf`: a voice reveal key keeps them out of prefetch; the bubble shows the view-once or timer badge, can't be scrubbed, and opens `VoicePlayOnceViewController`, which re-reads the message on its client, decodes a private copy, calls `openMessageContent` and plays it once (screen recording shows Telegram's alert). Build and `-media-probe-media-reveal` pass; the real consume path needs a received view-once note, which the test account doesn't have |
| R-1 | P1 | Bot inline keyboards and reply keyboards never render (`Message.replyMarkup` is unread) | fixed `e90a3074`, `26c65325`: inline keyboards under bubbles (rows of 42 pt buttons, callback answers as alert or toast, URL buttons ask before leaving Telegram's hosts, copy, user, switch inline in this chat), and the reply keyboard as the input view (resize, one-time, force reply, placeholder, toggle button, `updateChatReplyMarkup`). Simulator: Hacker News shows Read and Comments under posts, Aéza's bot shows its payment button, and Read asked "open https://unfenced.land/?" (answered No). Callback buttons weren't pressed, since they reach the bot. Login URL, password callbacks and poll requests `5a7c8d1b`: login URL buttons ask `getLoginUrlInfo` and show BotLoginUrlAlert's Open Link alert with the Log in and Allow messages checks (`getLoginUrl`); password callbacks check `canTransferOwnership`, ask the password and send `callbackQueryPayloadDataWithPassword` with Telegram's error texts; `keyboardButtonTypeRequestPoll` opens the poll creator with the quiz locked. Switch inline to a chosen chat `0db3d477`: `targetChatChosen` opens the Forward picker as PeerSelectionController with `requestPeerType` (writable chats of the button's kinds only, Choose User/Bot/Group/Channel or Select Chat, forum chats pick a topic); this chat takes "@bot query" in its composer, another chat or topic opens with it in place of its draft; `targetChatInternalLink` opens TDLib's internal link. Xcode MCP 10-16 with `-ui-probe-bot-buttons` (`BotButtonsProbe`): unchecking Log in also unchecks and disables Allow messages and Open reports `authorize=true allowWriteAccess=false`; the quiz request shows "new quiz" with the correct answer on and disabled; `-ui-probe-bot-buttons-switch-inline groups` lists only groups under "choose a group", BetterTG test opens its topics and UI test comes back as `chat=BetterTG test topic=UI test`; with `-switch-inline-open` the UI test topic opens with "@probe_bot query" in its composer (cleared afterwards). Real bot, Xcode MCP 10-18 in UI test: "@gamebot " listed Math Battle, Corsairs and LumberJack, the picked game went out with its "Play LumberJack!" callback button, and the button's callback answered with the game's URL (opened in-app since `c8839afd`, see R-3). Not tested with a real bot: reply keyboards (they need a message to a bot outside UI test). Request buttons (phone, location, users, chat, poll) are handled. Web App `860753ca` (ChatControllerOpenWebApp, WebAppController, WebAppWebView): inline buttons call `openWebApp` in the chat and topic, reply keyboard buttons `getWebAppUrl`, after the launch terms alert on a bot's first launch; the sheet shows the page under the bot's header with TelegramWebviewProxy's ready, expand, close, theme, viewport and safe area events, main and secondary buttons (colours, progress, position), back and settings buttons, header, background and bottom bar colours, haptics, popups, links after a touch, t.me links, clipboard requests, inline queries and keyboard `web_app_data_send`; closing asks Close Anyway when the page needs it and ends with `closeWebApp`; More offers Open Bot, Reload Page, Settings and Privacy Policy. Xcode MCP 10-16 with `-ui-probe-web-app` on a local page: it got `theme_changed`, `viewport_changed h=756 expanded=true` and the safe areas; main and second showed Second and Probe Main side by side, back turned the close button into Back, header turned the header red, and Probe Main, Second and Back sent `main_button_pressed`, `secondary_button_pressed`, `back_button_pressed`; the popup's Alpha came back as `popup_closed {button_id: alpha}`; with confirm close a swipe down asked "Changes that you made may not be saved" and Close Anyway closed the sheet. Not tested with a real bot's Web App: none was opened. Storage, access and custom methods `51fec587`: DeviceStorage (string values per account and bot on this device, 5 MB, Telegram's VALUE_INVALID, KEY_INVALID and QUOTA_EXCEEDED), SecureStorage (WebAppSecureStorage's Keychain keys, at most ten per account and bot, `canRestore`, RESTORE_UNAVAILABLE, STORAGE_NOT_EMPTY, and WebAppSecureStorageTransferScreen's Import Data sheet for keys an account that is gone left behind), write access (`canBotSendMessages`, AllowWriteTitle's alert, `allowBotToSendMessages`), phone sharing (SharePhoneTitle's alert, unblocking first when needed, then the account's contact to the bot), custom methods (`sendWebAppCustomRequest`, `custom_method_invoked`), `web_app_setup_swipe_behavior` and `web_app_hide_keyboard`. Xcode MCP 10-16 with `-ui-probe-web-app`: device get returned null, save `device_storage_key_saved`, get the stored value, a number VALUE_INVALID, clear `device_storage_cleared`; secure save and get returned "secret" on the Simulator, restore with a key STORAGE_NOT_EMPTY, after clear RESTORE_UNAVAILABLE and get null; no swipe hid the grabber and a drag down left the sheet open; hide kb dismissed the keyboard from a focused field; write and phone showed "allow sending messages?" and "share phone number?" with Probe Bot's name, and Cancel sent `write_access_requested` and `phone_requested` with `cancelled` (OK wasn't pressed). `-ui-probe-secure-transfer` showed Import Data with the avatar, the bold bot name, ACCOUNT TO IMPORT DATA FROM, two accounts with "created on" dates and the check moving to the tapped one; Import closed the sheet. Deviations: `phone_requested: sent` follows `sendMessage` without waiting for the message to leave, and a failed `allowBotToSendMessages` reports `cancelled` where Telegram stays silent; custom methods weren't run (the probe has no bot). Device features `1aed1f88`..`46835947` (cherry-picked from `codex/parity-webapp-2`; WebAppController's fullscreen, orientation lock, QR scanner, biometry, location, sensors and home screen handlers) and `aeab5f42` (permissions and the biometric token keyed by the account that opened the Web App): fullscreen moves the header into floating close and more buttons and reports safe areas, the orientation lock follows the page, the QR scanner (WebAppQRScanner) reports codes and its closing, biometry asks the bot permission alert then Face ID and keeps the token in the Keychain per account and bot, location asks iOS then the bot ("requests access to your location"), sends Telegram's fix fields and has Geolocation in the bot's settings, accelerometer, gyroscope and orientation stream at the page's rate, and the home screen check answers `unknown` while add opens `t.me/<bot>` in Safari, as Telegram does. Xcode MCP 10-17 with `-ui-probe-web-app`: fullscreen gave `fullscreen_changed true` with the floating buttons and the top content safe area of 46, lock sent `web_app_toggle_orientation_lock`, exit gave `false`; qr opened "scan qr code" and close sent `scan_qr_popup_closed`; loc check gave `available true`, loc request asked iOS (Allow Once), then the bot's alert, and after allow (simulated 37.7816, -122.4011) sent the fix with `available true`; the sensors answered `UNSUPPORTED` as Telegram's handlers do without CoreMotion hardware; with Face ID enrolled in the Simulator bio info gave `available true, type face` and bio access showed "do you want to allow Probe Bot to use face id?"; home check gave `unknown` and home add opened t.me's Add to Home Screen page. Xcode MCP 10-17 (allowed by the user): yes in that alert gave `access_granted true`; bio token gave `updated`; bio auth showed the Face ID sheet, a simulated match returned `authorized` with the token, a non-match showed Face Not Recognized and its Cancel returned `failed`; bio clear gave `removed` and bio info then `token_saved false`. Not tested: a scanned code, rotation under the lock. Main Web App and attachment menu bots `6e4a0857`/`5fec50b8`/`1c31210e` (cherry-picked from `codex/parity-webapp-3`; ChatControllerOpenWebApp, ChatControllerOpenAttachmentMenu, AttachmentPanel, TelegramCore AttachMenuBots, webAppTermsAlertController, PeerInfo's Open App): a bot profile shows Open App when the bot has a main Web App and isn't fake or scam, and `startapp` links open it too; a bot that can join the attachment menu but hasn't asks for the terms (checkbox, terms link, Continue disabled until checked) and is added first; the page comes from `getMainWebApp` in the returned mode (compact, full size, fullscreen). The attachment sheet lists the account's attachment menu bots (`updateAttachmentMenuBots`, iOS animated and side menu icons, first TGS frame tinted) for the chat type after Gallery, none in secret chats; the tab row scrolls once the buttons don't fit; a bot's tab runs the terms and install if needed, then `openWebApp` with the chat, topic and the composer's reply at half height; `updateWebAppMessageSent` closes the sheet, clears the reply and scrolls down; the page's More menu gains Remove Bot with Telegram's confirmation; `closeWebApp` ends every launch. Xcode MCP 10-17 with `-ui-probe-attach-bots` and `-ui-probe-main-web-app` (the probe page replaces openWebApp and getMainWebApp, nothing is sent or installed): the sheet showed Gallery, Shop, Games and Probe (cart and gamepad icons tinted, Probe's fallback glyph), and the row scrolled to Sticker; Shop showed the terms with Continue disabled, the checkbox enabled it, and the page opened at half height under "Shop" with Privacy Policy and Reload Page in More; @levpoz_bot's profile showed Open App under the bio, which ran the terms and opened the page expanded under the bot's name. Not tested: Remove Bot (the probe bots aren't on TDLib's list), a real install, sending through a bot. Menu button, `startattach` and side menu bots `97d1b6ef`/`1cb92acf`/`07fa786c` (cherry-picked from `codex/parity-webapp-menu`; ChatTextInputPanelNode's menu button, MenuIconNode, ChatControllerOpenWebApp, OpenResolvedUrl's `.startAttach`, ChatController.presentAttachmentBot, PeerInfoSettingsItems' apps section, PeerInfoScreen.openBotApp): a bot whose `botInfo.menuButton` is a Web App shows the button's text in place of Menu, left of the composer, and opens it with `openWebApp` from the menu after the attachment menu checks (terms for a bot not added, the launch confirmation on a first launch); a t.me named-app URL goes through `getWebAppLinkUrl`. `startattach` links install the bot through the terms, then open it in the current chat, the linked chat or a Select Chat list filtered to the bot's chat types, with Telegram's ShortcutsAdded or ShortcutsSettingsAdded notice, AlreadyAdded or Unavailable. Settings lists `showInSideMenu` bots above Saved Messages with their icon and a NEW badge while the bot isn't added or its disclaimer stands; a tap runs the terms, accepts the disclaimer (kept per account and bot, as Telegram keeps it locally), adds the bot and opens `getWebAppUrl` with an empty URL at full size. Xcode MCP 10-17 (the probe page replaces every launch, adding only closes the terms, nothing is sent): `-ui-probe-bot-menu-button` showed "Open Probe" left of the plus in a bot chat, its tap showed the launch confirmation and launch opened the page at half height; `-ui-probe-settings-bots` listed Wallet and Mini Games with NEW and Probe without, Mini Games ran the terms with Continue disabled until the check and opened the page at full size, and its badge was gone on return; Wallet showed "Wallet shortcuts added in attachment menu and settings." over the page (Wallet's badge stays in the probe because its install never reaches TDLib's list); `-ui-probe-startattach` ran the terms, then "select chat", and the chosen chat opened with the page at half height and "Probe Attach shortcuts added in attachment menu and settings." Skipped: SVG icons (no SVG renderer), minimizing, `whitelisted_bots`, the animated `anim_webview` menu icon (an SF Symbol stands in), Telegram's top toast in Settings (bottom here). Open: Buy, emoji status, sharing to stories, invoices from the page |
| V-2 / R-6 | P2 | Playing a voice note or a non-secret video note never calls `openMessageContent`; no unlistened dot | fixed `91928761`: the first play of an incoming note calls `openMessageContent` on its client, the bubble shows the unlistened dot (sent notes in private chats until the peer listens), and `updateMessageContentOpened` re-reads the message. Build only (the only voice note in Saved Messages is off limits) |
| V-3 | P2 | A voice recording switched the session before stopping playback; a failed deactivation skipped the record category; a playing video note kept playing | fixed `ebb7341c`. Build only (the Simulator has no microphone, and the user's mic button is off limits) |
| V-4 | P2 | Nothing kept the screen awake while recording | fixed `365173c5`: recording holds the idle timer, as Telegram's `pushIdleTimerExtension`. Build only |
| V-5 | P2 | "Release to cancel" showed at 70 pt; release cancels only past 100 pt | fixed `4d403a33`. Build only |
| R-2 | P2 | Polls, live locations and checklists show a plain Edit that throws; Stop Poll/Quiz and Stop Live Location are missing | fixed `2b9d3e49`: Edit only for content `editMessage` changes; Stop Poll/Quiz after Telegram's confirmation (`stopPoll`) and Stop Sharing (`editMessageLiveLocation` with no location). Build only; the account has no open poll or live location to stop |
| R-3 | P2 | Game, story, checklist and giveaway messages fall to the unsupported fallback | fixed `120b5101`, `3b06a852`, `e142ba0a` (cherry-picked from `codex/parity-rich-content`): checklists with Telegram's task toggles (`markChecklistTasksAsDone`, optimistic with rollback), completed-by names, the N of M footer and Add a Task; games with photo, title and text, whose tap runs the Play callback; shared stories and story mentions loaded with `getStory`, with Telegram's expired texts. `-ui-probe-message-content` passes with five new fixtures and a toggle check; the screenshot shows both checklist styles, the game and both expired story states. A real checklist was marked on 10-18 (see below). Giveaways stay excluded (out of scope). Task menu `969b6b03`/`e47a1e0e` (ChatControllerOpenTodoContextMenu, ContextSourceContainer): a long press on a task opens Task and List tabs with Telegram's footer; the Task source lists the completion date, Check or Uncheck, Reply to Item (the reply carries `checklistTaskId`, the panel reads Reply to Checklist Item and reply snippets show the task with its check), Copy, Copy Link (`getMessageLink` with the task) and Edit Item, then Delete Item when another task remains (`editMessageChecklist`); a tab tap or an 80 pt horizontal swipe switches sources. Xcode MCP 10-16 with `-ui-probe-checklist-menu` (actions only log): a done task shows "completed today at 17:23" and Uncheck, an open task Check, both tabs and the footer render, List and a swipe back switch, Reply and Check log `reply 1` and `toggle 2`, a press outside the tasks opens only the List actions. Edit Item opens the checklist editor since `7b42250d` (see below). Shared stories open the story viewer (`45d3e06d`). Animated games `20fc9724` (ChatMessageGameBubbleContentNode prefers the animation, ChatMessageInteractiveMediaNode plays it muted under GAME): the bubble loops the animation in place and a tap still plays the game. Xcode MCP 10-16 with the probe's game-animation fixture: the GAME badge sits over the movie, which advances 5, 6, 1 across screenshots. Real game, Xcode MCP 10-18 in UI test with @gamebot's LumberJack: Play opened the page in Safari where Telegram pushes GameController; fixed `c8839afd` (ChatController's game callback, GameController, GameControllerNode, GameControllerTitleView): the launch terms the first time the bot opens ("GameBot", launch), then a pushed screen titled LumberJack over @gamebot with Share, the page under the bar; a round scored 1 with лева on the leaderboard; the page's Share (`share_score`) opened Share To and UI test received the game as an in-game share ("you scored 1 in LumberJack", "лева has just scored 1."); the bar's Share sent https://t.me/gamebot?game=LumberJack with its preview. Checklist editor `7b42250d` (ComposeTodoScreen, ChatControllerOpenAttachmentMenu's `.todo` and openTodoEditing): the attachment menu shows Checklist after Poll where TDLib takes checklists (not in secret chats, channels or channel direct messages, under the poll permission); a Premium account gets New Checklist (title, tasks with TDLib's `checklist_*_max` limits, the remaining-count footer, reorder handles, swipe Delete, Allow Others to Mark as Done with Allow Others to Add Tasks under it, Send once a title and a task are filled, Discard checklist items? before a sendable one goes), others Telegram's Checklists notice (the Premium demo's text, no purchase). Edit Item and Add a Task open the same editor (Edit Checklist on the task, or after the list; published tasks locked as Add a Task where the checklist can't be edited) and replace the list (`editMessageChecklist`) or append the new tasks (`addChecklistTasks`); text pasted with line breaks fills tasks by line. Service lines `d11a5cfc` (ServiceMessageStrings' todoCompletions and todoAppendTasks): "You marked "buy milk" as done.", "You added a new task "deploy" to "parity checklist".", names cut after 20 characters. Xcode MCP 10-18 in UI test (Premium account): New Checklist showed "you can add 28 more tasks.", turning Mark as Done off hid Add Tasks and on brought it back, Cancel asked "discard checklist items?" (No kept it), Send posted "parity checklist" as a group checklist with buy milk and write tests; a tap marked buy milk (лева under it); Edit Item on write tests opened Edit Checklist focused on it, and Save sent "write tests again" with a new "ship it" (edited); the message's Add a Task opened the editor on Add a Task and "deploy" arrived as an added task; pasting "alpha, blank, spaces, beta, gamma" lines filled alpha, beta and gamma. Not tested: Add a Task on someone else's checklist (needs a second account), the non-Premium notice on this Premium account |
| R-4 | P2 | A rolled dice shows only its emoji; the result is never visible | fixed `98880b5f`: the final state is drawn (five layers for 🎰); a fresh result plays once and holds the value, an older one shows the last frame; tapping shows Telegram's dice hint with Send; a text that is only a server dice emoji is sent as a roll. Simulator, Saved Messages: 🎲 rolled once to 3 and stayed still, the hint's Send rolled a 4, both test messages deleted |
| R-5 | P2 | Contact messages lack Send Message and Add Contact | fixed `98880b5f`: MESSAGE and ADD (VIEW CONTACT without an account) under the card, the card opens a Telegram user's profile, and the sheet offers Send Message and Add Contact (`addContact`, name only, number not shared). `-ui-probe-message-content` passes and the screenshot shows both button sets; Add Contact wasn't run so the account's contacts are unchanged |
| V-6 | P3 | The recording chat action was sent once and expired | fixed `365173c5`: repeated every 4 s for voice and video notes. Build only |
| V-7 | P3 | No playback speed, next-voice autoplay, raise-to-listen, playback header or muted video note autoplay | partly fixed `b800643a`, `df92e57f`: Telegram's playback header (play/pause, author over "Voice Message" or the group, 1X/1.5X/2X kept across notes, close, progress) and continuing with the chat's next voice note. `-ui-probe-voice-header` shows both header states and cycles the rate through Media; real playback wasn't run (the only Saved Messages voice note is off limits, and playing another chat's note would mark it listened). Open: raise-to-listen, video notes in the playlist, muted video note autoplay, the header outside the chat. Later `7fb372c7`, `017d8ebf`: round videos join the playlist (scrolled into view and played in their bubble), and a played voice note keeps going over the chat list with the header there and in other chats; `cda99aa0` continues with the chat's next voice note after the chat closes (build only: playing a note would mark someone's note listened). `72e67c9d` adds the floating round-video player (OverlayInstantVideoNode): a playing note whose bubble leaves the screen keeps playing in a 150 pt corner circle with radial progress, tap to pause, corner snap, fling to dismiss and the keyboard offset, and the bubble takes it back where it left off (build only: there is no own round video, and playing someone else's would mark it viewed). `afe6ec27` adds raise-to-listen (RaiseToListenActivator, DeviceProximityManager): raising the phone in a chat plays the oldest loaded unlistened voice note or round video, or starts a locked voice recording after Telegram's begin_record tone; leaving the ear stops it into the preview, and a phone still at the ear when the playlist ends records the reply. Voice notes follow the proximity sensor (earpiece at the ear, restart under 1.5 s, pause away from it), and Data and Storage has the Raise to Listen switch. The raise comes from CoreMotion's gesture manager by name after a selector check, with an attitude fallback. `-ui-probe-raise-to-listen` passed 11/11 in the Simulator with a simulated sensor (gesture source: system); the switch shows on through Xcode MCP and a chat opens and closes with the activator on. Earpiece gain and round video proximity `7e946518` (MediaPlayerAudioRenderer's `forAudioVideoMessage` NBandEQ global gain, SharedMediaPlayer's `controlPlaybackWithProximity` for `.instantVideo`): an MTAudioProcessingTap on the AVPlayer item's audio scales voice and round video samples by 12 dB when playback starts at the ear, 5 dB when the phone comes up during playback (Telegram's two values) and 0 dB on the speaker; round videos in their bubble and in the floating circle follow the proximity sensor while Raise to Listen is on (earpiece at the ear, restart under 1.5 s, pause away). `-ui-probe-raise-to-listen` 10-17 passes 19/19 with the simulated sensor, the gain measured on the samples the tap scaled: 5.00 dB at the ear during playback, 0.00 dB resumed on the speaker, 12.00 dB started at the ear, and a round video restarted from 0.90 s to 0 s on the earpiece at 5.00 dB and paused away from the ear. Still open: device proof of the raise and the earpiece route (no paired iPhone was reachable on 10-17) |
| V-8 | P3 | Voice playback never gave back the audio session | fixed `60181132`: the spoken-audio session Media activated is deactivated with `notifyOthersOnDeactivation` when playback ends |
| V-9 / R-7 | P3 | The voice view downloads through the global client and an unscoped `updateFile` | fixed `b8cb17c9`: downloads and cancels go through the message's playback backend, and only that source's `updateFile` is accepted. Build only |
| V-10 | P3 | Voice progress moves in whole seconds; scrubbing a stopped note starts it | fixed `b8cb17c9`: `Media` publishes a fractional position, and scrubbing a stopped note loads it paused at that point. Build only |
| V-11 | P3 | The 50 ms recording timer publishes the whole ChatView refresh 20 times a second | fixed `67e0ae29`: the tick publishes `recordingTimeChanged`, which updates only the composer's recording row (Telegram's ChatTextInputAudioRecordingTimeNode); crossing the 0.5 s pause threshold refreshes once. Build only (no microphone, and the mic button is off limits) |
| V-12 | P3 | Voice is recorded as 48 kHz WAV and encoded only after release | measured, not changed (`002cc8d6`): the codec probe encodes a minute of recorder-format PCM in 61 ms on the Simulator (a phone is a few times slower, still well under a second), so the wait a streaming encoder would remove is small. The PCM recording also backs pause, resume, trim and the PCM waveform; replacing it needs a measured send-latency problem first |
| V-13 | P3 | No view-once option when sending voice or video notes | voice fixed `2ce4b37b`: Telegram's play-once toggle on locked and previewed recordings in private chats with users, sent with `messageSelfDestructTypeImmediately` and kept in the send draft. The draft outcome, relocation and finalization probes pass with the new field; recording wasn't run (mic off limits). Video notes stay without it, as Telegram's own video toggle is disabled (`//viewOnceIsVisible = isLocked`) |
| V-14 | P3 | Logging out never purges the account's voice and video draft stores | fixed `72ad5192`: removing an account's TDLib directory also discards its voice send, voice recording and video note recording drafts. `-media-probe-draft-outcomes` passes with a new logout check; a real logout wasn't run |
| V-15 | P3 | Hold-to-send waveforms use unnormalized meter readings (suspicion) | confirmed and fixed `34c7e0e1`: finalization replaces the dB meter estimate with the recorded file's PCM waveform (Telegram's normalization, as the trim editor already used). Voice codec, finalization, draft outcome and relocation probes pass |
| V-16 | P3 | A successful send may delete the .ogg the sent message still points to (suspicion) | confirmed and fixed `49f9a5fc`: resolving a sent draft removes only its manifest; the uploaded file stays for the store's one-day abandoned-file sweep, so your own note replays without a download. Draft outcome, finalization and relocation probes pass with the new ownership. Video notes still delete their sent file (their store tombstones removals; not changed) |
| R-8 | P3 | Public polls have no View Results or voter list, no Unvote item; vote errors only logged | fixed `2e04fe53`, `811c20df`, `ecd9857c` (cherry-picked from `codex/parity-poll-results`): Retract Vote by Telegram's rules, failed votes roll back and report, Telegram's poll labels, voter counts, result marks and quiz explanation, and View Votes (N) opening `PollResultsViewController` (10 voters, then pages of 50). Build and `-ui-probe-message-content` pass; no vote was cast, so the live results screen is unverified. Feedback after a vote `160cf262`: success haptic for a vote and a right quiz answer plus confetti (ConfettiView), an error haptic, the bubble shake and the explanation opening on its own after a wrong one, and the Chat.Poll.HiddenResultsTooltip toast; the user's own die that lands on TDLib's success frame plays the haptic and confetti (animateDiceSuccess). Verified 10-18 in UI test: the wrong answer to the parity quiz wrong quiz opened the explanation, the right answer to parity quiz right dropped confetti (video frames), and 🎯 with value 6 dropped confetti on the success frame. The anonymous poll creator's preview `N votes >` / `< Vote` (`isPreviewingResults`) is ported in `d2ab8d03`; verified on the `-ui-probe-message-content` fixture (no second account to vote) |
| R-9 | P3 | Many service rows use generic titles without Telegram's values (calls, video chats, auto-delete, game score, proximity, web app data, theme, owner changes) | fixed `2de7def3`: calls, group calls, video chats (started, ended, scheduled, invitations), auto-delete timers by chat type, game scores, proximity alerts, web app data, themes and wallpapers use Telegram's ServiceMessageStrings wording with names, durations, times and distances. `-ui-probe-service-text` passes 18 cases against the active language pack. Owner left/changed keep BetterTG's titles: Telegram iOS has no wording for them yet. Extended `848b79bf`: ownership handovers (groupCreatorChange pending/applied), sharing protection toggles and requests (copyProtectionToggle/Request), the General topic hidden or unhidden, suggested profile photo/video and birthdate, bot write access by reason (website, attachment menu, Web App, request), users and chats shared with a bot (requestedPeer), Passport documents (botSentSecureValues), poll options added or deleted, suggested post approved/rejected, managed bots and community added/removed (names from updateCommunity) use Telegram's wording; group upgrade notices leave the timeline as in ChatHistoryEntriesForView. `-ui-probe-service-text` passes 31 cases on the iPhone 18 Pro iOS 27 Simulator. Real rows seen 2026-10-18 in BetterTG test > UI test: 'you added the option "gamma answer" to the poll' and 'you deleted the option "gamma answer" from the poll' after R-13's Add an Option and Remove. Open: the other kinds can't be produced in the test forum |
| R-10 | P3 | Service rows aren't tappable and show no media (pinned message jump, photo changes, wallpapers) | fixed `f74d952c`: pinned message, game score, repeated wallpaper, checklist and poll option rows scroll to their message; a chat photo change shows the photo and opens it in the avatar gallery. Build only; no such row was reached on the Simulator. Group call rows don't join a call (BetterTG has no calls) |
| R-11 | P3 | Bubbles lack the "edited" label, channel view counts and the comments button | fixed `614596d1`, `3895c1c9` (cherry-picked from `codex/parity-bubble-footer`): the status line shows edited, the view count and the signature; channel posts with a discussion group get Telegram's comments bar with avatars, which opens the group at the thread. Simulator: a channel shows "8.8K 14:28" and "46 comments" with three avatars, Comments threads `e869ab64`, `cfe0fbaa`, `874ddc35` (cherry-picked from `codex/parity-comment-threads`, with a fix for two implicit-self warnings): the bar opens the discussion chat with a `messageTopicThread` location, `getMessageThreadHistory`, the post as the thread head, "N Comments" title, "Comment" placeholder, sends and drafts into the thread, thread read state and receipts, and Telegram's non-member rule. Simulator: a channel post's "7 comments" opened "7 comments" with only its comments, the composer read "comment", and scrolling up ended at the forwarded post. Group reply threads open from the message menu: "View N Replies" in groups and "View Thread" for a comment in a discussion group (`42d8337f`, build only; the discussion group wasn't reachable from search on the Simulator). Missing: the "Discussion started" separator, the other album members in the head |
| R-12 | P3 | The content probe still audits 104 cases at TDLib 1.8.66; the schema has 107 | fixed: the probe records 107 cases at 1.8.68-c15d3f5a; the exhaustive switch already compiles against all 107 |
| R-13 | P3 | A long press on a poll answer opens only the message menu; polls open to new answers have no Add an Option | fixed `1d688a83`, `857b7693`: ChatControllerOpenPollContextMenu: a long press on an answer opens Vote or Retract Vote, Reply to Option, Copy, Copy Link (`getMessageLink` with `pollOptionId`) and Remove when `getPollOptionProperties` allows it, then 'Added by …' with the author's avatar; the option and poll tabs switch to the message actions. A reply to an answer shows the answer's text with a check in the reply header and 'Reply to Poll Option' in the panel. ChatMessagePollAddOptionNode: a poll with TDLib's `canAddOption` (TDLib folds in Telegram's open answers, closed, forwarded, local and `poll_answer_count_max` checks) gets an Add an Option field in BetterTG's answer style. With the keyboard up the input panel and jump buttons step aside, history scrolling, swipe to reply and the message menu stop, the other answers dim to 0.5 and the poll moves above the keyboard; typed text swaps Vote for Save, Save or Done sends `addPollOption` with the success haptic, 100 characters, no new lines; the draft survives cell reuse. Verified 2026-10-18 on the iPhone 18 Pro iOS 27 Simulator in BetterTG test > UI test: the menu's Vote, Retract Vote, Reply to Option (sent reply 'Reply from лева, alpha answer'), Copy Link (`https://t.me/c/<chat id>/2/83?option=MA`), Add an Option → Save ('gamma answer' added), its menu with Remove and 'added by you today at 02:38', Remove, and a history tap that puts the keyboard away with the draft and Save kept. Media and custom emoji for a new answer, fixed `e96cc5a2`, `cb5f8154`: once text is typed a paperclip opens the poll media flow (photo, video, sticker, location) with a 40-pt thumbnail that removes the media on tap; while editing a smiley replaces the plus and opens the emoji picker without stickers and GIFs, custom emoji stay as entities in `addPollOption`. Verified 2026-10-18 in UI test: 'photo answer' with a photo, 'tmp' with a sticker, remove and re-attach from the thumbnail, and 'emoji 😂' plus an animated custom emoji saved |

Reviewed and OK: recording gesture thresholds, interruptions and backgrounding to preview, off-main encoding, frozen send context for voice and video notes, note limits, video note playback ownership; media, file, location, poll voting, rich message, link preview, reaction, reply/quote/forward header, delivery and spoiler rendering. Not reviewed: video note writer and segment composer internals, the recorder state machine, note stores' reconciliation, FFmpeg transcode, invoices, animated emoji interactions, reactors list, text entity actions, translate and report.

### Forum topics, timeline, Forward, folders and quote audits — 2026-10-16

Read-only audits at `e1e0ad48`: forum topics and the chat timeline (T), the Forward picker, folder editor and quotes (F-x; the F-x ids are separate from the flow ledger's F numbers).

| ID | Sev | Finding | Status |
|---|---|---|---|
| T-1 | P1 | Reading inside a forum topic marks the whole forum read (`viewMessages` without a source); the notification quick reply did the same | fixed `9039faea`: topic routes pass `messageSourceForumTopicHistory` (TDLib's `ReadForumTopicQuery`), threads keep the thread source, a quick reply into a forum topic reads only that topic. Build only: no unread forum on the account |
| F-x1 | P1 | Forward eligibility uses the chat's default member permissions and ignores the user's own status (admins lose restricted groups, probably their channels; restricted members fail at send) | fixed `c0941081`: the picker, topics step and send check resolve the user's standing (supergroup, basic group, secret chat) and apply Telegram's `canSendMessagesToPeer` through `CustomChat.allowsSending`. Simulator: the channels tab now lists the two channels the account posts to |
| T-2 | P2 | The hidden General topic can't be reached; no Hide/Unhide | fixed `169948ec` (cherry-picked from `codex/parity-forum-chrome`): a hidden General stays as the first row tucked under the top past search, revealed by pulling; creators and topic managers get Hide/Unhide with Telegram's toasts. Probes only: the account has no forum it manages |
| T-3 | P2 | No pinned-message banner in forum topics or a forum read as messages | fixed `3a451814`, `261abd5c`: a topic shows its newest pin (`searchChatMessages` pinned filter with the topic), a forum read as messages shows the chat's pin; Pin in the menu follows. Probes only |
| T-4 | P2 | Every open clears unseen reactions (`readAllChatReactions` in `viewDidAppear`); no mention/reaction jump buttons | fixed `c3d95ae6`: no read-all on appear (TDLib reads reactions and mentions per viewed message); Telegram's @ and heart buttons stack above scroll-to-latest, jump to the earliest unread and clear on long press. Build only: the only unread reaction is in a private chat, opening it would send a read receipt |
| T-6 | P2 | The topic list reloads from page 1 after a deletion or a pin, dropping later pages | fixed `2cc6c0eb`: pins re-read page 1 and merge it, keeping later pages; a deleted last message re-reads only its topic and a 404 drops the row. `-ui-probe-forum-updates` passes |
| T-7 | P2 | A topic moving to the top can slide under the bar (no `restingTopOffset`; suspicion) | fixed `118f8b0b`: the chat list's resting-top correction, immediate and on completion |
| F-x2 | P2 | Forward options can't be changed from the composer block; no Change recipient, no "Sender names removed" | fixed `77f2706d`: tapping the block opens Telegram's forward options (names, captions, Change Recipient, Do Not Forward) in the custom menu; the picker's sheet is gone. Simulator: hide/show names and Change Recipient back into Saved Messages, nothing sent |
| F-x3 | P2 | The Forward topics step uses its own bar and an always-visible `UISearchBar` | fixed `352c7d1e`: the topics step uses `TelegramListNavigationBar` with search hidden under it, as the topic list. `-ui-probe-forward-forum-snapshot` passes |
| F-x4 | P2 | A same-account client renewal leaves the Forward picker on screen but dead | fixed `17787ea1`: the picker closes on a client change that makes it stale (the presenting chat is rebuilt on the new client). Build only |
| F-x5 | P2 | Saved Messages is first in Forward only when it is in the loaded page | fixed `b187fa47`: All Chats resolves the own chat with `createPrivateChat` and lists it first even when not loaded or archived. Simulator: still first |
| F-x13 | P2 | The folder Add Chats picker offers only loaded chats; no server or contact search | fixed `cf985c25` (cherry-picked from `codex/parity-folders`): the picker pages the main list and searches chats, server chats and contacts |
| F-x14 | P2 | Shared folders: no invite-link management, no new-chats prompt, `t.me/addlist` unhandled | fixed `24ffbe49`, `8cfe8912`, `8c081991` (cherry-picked from `codex/parity-folder-links`): `t.me/addlist` and `tg://addlist` open Telegram's preview sheet (`checkChatFolderInviteLink`, `addChatFolderByInviteLink`); the editor's Share Folder section creates, edits, copies, shares and revokes links; a shared folder's new chats show as a row in the editor (`getChatFolderNewChats`, `processChatFolderNewChats`). No background polling or chat-list banner. Build only: no addlist link to open |
| F-x24 | P2 | Quote is impossible in copy-protected chats (selection requires `canBeCopied`) | fixed `7fd0d5cb` (cherry-picked from `codex/parity-quote`): selection follows `canBeReplied` (not secret chats or self-destructing messages); protected messages offer only Quote and block copy and drag |
| T-5 | P3 | Typing isn't shown in a topic header; `actionStatus` keeps one sender | fixed `62eb5e38` (cherry-picked from `codex/parity-forum-topics`): actions tracked per sender and topic; a topic header shows who is acting there with the chat list's wording (no animated dots) |
| T-8 | P3 | Remote pins keep their chronological place until a page-1 reload | fixed `9b175f04`: any pin change re-reads page 1 for pin ranks. A pure remote reorder has no TDLib update |
| T-9 | P3 | One merged row badge in the topic list | fixed `0e8ecd18`: unread count and a separate @/reaction/poll badge; muting greys all but the mention badge |
| T-10 | P3 | No pinned-topic reorder | fixed `e6940cd2`: Reorder on a pinned topic for managers, saved per drop with `setPinnedForumTopics` |
| T-11 | P3 | No topic row swipes | fixed `235c83d5`: Telegram's trailing reveal options (Mute/Unmute, Delete, Close/Start; General: Start, Hide/Unhide), the last on a full swipe. Forum probes pass; no forum on the account to swipe |
| T-11b | P3 | The main chat list has no swipe actions either (found with T-11) | fixed `696812ea`: Telegram's reveal options (Mute/Unmute, Delete, Archive; Unarchive and Pin in the archive; leading Read/Unread and Pin), last on a full swipe; a pan from a side edge zone (width/6, 22...80 pt) reveals them and one from the middle switches folders, as Telegram's folder pan. Simulator: right edge showed unmute and delete, left edge read and pin, a middle pan changed folders; no action was pressed |
| T-17 | P3 | A thread chat lacks Telegram's "Discussion started" separator and shows one member of an album root (handoff residual) | fixed `514d2ce3`, `1140fe7c`: the pill under the root (or "No comments here yet..."), and every album member in the head. Simulator: a channel post's comments show the whole album and "discussion started" |
| T-12 | P3 | No Close/Reopen bar or avatar menu inside a topic | fixed `c9c49d68`, `34f371cc`: the Restart Topic bar in closed topics, and Telegram's topic avatar menu (Search, Close/Reopen for the forum's creator, topic managers and the topic's creator; never General). Simulator: in BetterTG test → UI test, holding the avatar showed search and close; search opened "search this chat"; Close wasn't pressed |
| T-13 | P3 | Forum search covers topic names only | fixed `40d8bcaf`: a Messages section from `searchChatMessages` below the topics, paged, opening the topic at the message. `-ui-probe-forum-*` (6) and the forward forum probe pass |
| T-14 | P3 | Rows that inherit the forum's mute don't refresh on a scope change (suspicion) | confirmed and fixed `56da4980`: forum and scope notification settings are observed and rows reconfigure when inherited mute flips |
| T-15 | P3 | Voice and video-note downloads prefetched for rows never shown kept going after the chat closed | fixed `4cb6bfb8`: deinit cancels them (`onlyIfPending`), as the prefetch cancel path already did. Build only |
| T-16 | P3 | Topic taps are ignored while a new search page loads | fixed `e2518a7d`: any displayed row of the current client opens |
| F-x6 | P3 | Forward ignores Telegram's content checks (public polls, quizzes and checklists to channels; closed secret chats) | fixed `c0941081`: public polls, quizzes and checklists never go to channels (Telegram's strings), secret chats must be ready, groups charging Stars per message are unavailable. Build only |
| F-x7 | P3 | The forward block shows the forwarder's full name from the first message; no "You", no multi-author line | fixed `77f2706d`: original authors once each, "You", "author: text" or "From: A, B". Simulator: "Hacker News: Neural networks…" |
| F-x8 | P3 | Forwarding own originals from Saved Messages doesn't default to hidden names | fixed `77f2706d`: own originals from Saved Messages start as a copy, and the names item is hidden as in Telegram. Build only |
| F-x9 | P3 | A pending forward lives only in ChatVM memory | fixed `25b04c1f` (cherry-picked from `codex/parity-forum-next`): saved per account and destination in `PendingMessageForwardStore`, prepared again on open, cleared on send, Do Not Forward or replacement, purged on logout. Simulator: a forward to Saved Messages survived leaving the chat, × cleared it for good; nothing sent |
| F-x10 | P3 | Forwarding from the gallery always pushes a new chat, even the same chat | fixed `77f2706d`: `ChatViewController.openForward` hands the draft to an open chat for the destination (pop to it) instead of pushing a second one; the gallery uses it. Simulator: Change Recipient to the same chat reused it |
| F-x11 | P3 | The Forward folder bar has no unread counters and never refreshes | fixed `919ca58f`: the main folder bar's configuration with `FolderUnreadStore` counters, refreshed on counter and folder changes. Simulator: "channels 25", "people 2" in the picker |
| F-x12 | P3 | `sendComment` is dead code | fixed `bf009209` |
| F-x15 | P3 | Shared folders still show chat-type and exclusion rows | fixed `f41f76ce` |
| F-x16 | P3 | The folder editor ignores pinned chats; an all-pinned folder can't be saved | fixed `215c9cfa`: pinned and included chats are one list; an existing folder saves with only a name |
| F-x17 | P3 | Back discards unsaved folder edits without asking | fixed `0c8cd312`: Back and the pop gesture ask Discard/Save when an existing folder's draft changed. Simulator: the alert appeared after a toggle; Discard left the folder unchanged |
| F-x18 | P3 | No per-folder chat limit before Save | fixed `bce1e2a6`: `chat_folder_chosen_chat_count_max` (secret chats counted apart as TDLib does) stops selection with Telegram's limit text, no Premium offer |
| F-x19 | P3 | No Recommended Folders | fixed `b3227783`: Recommended Folders with ADD, minus folders whose rules already exist |
| F-x20 | P3 | A new folder isn't named from a single chosen category | fixed `46ca41aa` |
| F-x21 | P3 | Renaming a folder drops custom emoji | fixed `00fcc607`: emoji entities outside the edited span are kept and shifted; the animate flag is kept |
| F-x22 | P3 | Add Chats from the folder menu saves the folder as it was when the menu opened | fixed `19501a1b` |
| F-x23 | P3 | The folder list counts only loaded chats | fixed `8c1cd8a1`: `getChatFolderChatCount` per folder. `-ui-probe-folder-flow` passes |
| F-x25 | P3 | No partial-text selection for copying in read-only chats; no Reply in Another Chat | fixed `8c5907e3`, `66e06f82`: selection follows `canBeCopied` with Quote only where replies work; Reply in Another Chat in the reply options opens the Forward picker as "Reply in..." and sends `InputMessageReplyToExternalMessage`. Build only |
| F-x26 | P3 | Quotes aren't trimmed; a whitespace-only quote isn't dropped | fixed `45f2f590`: Telegram's U+0020/U+000A trim before the limit, the position moves to the first kept character, a blank selection is a plain reply. `-custom-emoji-text-probe` passes 15/15 |
| F-x27 | P3 | An edited quoted message still highlights the old position instead of Telegram's not-found toast | fixed `f917de0e`: the nearest occurrence in the current text is highlighted, otherwise only the message with Telegram's "Quote not found" toast |
| F-x28 | P3 | The quote attaches after an async `getOption`; sending in that window drops it | fixed `18de2eda`: `MessageQuoteLengthStore` caches the option per client from updates; the quote is built synchronously (1024 until known) |
| F-x29 | P3 | Tapping the composer reply panel only scrolls; no reply options menu | fixed `0a220200`, `d61cbf75`: the reply panel opens View Message, Select Specific Quote, Remove Quote and Do Not Reply. Simulator: menu above the panel, Do Not Reply clears it |
| F-x30 | P3 | Reply panel titles fall back to "Reply" for channel posts and anonymous admins | fixed `754df51c`: the sender chat's title, also for voice and video note replies |
| F-x31 | P3 | Document and audio album captions probably can't be quoted (suspicion) | confirmed and fixed `c275505c`: a long press selects in the caption of the file under the finger and the quote replies to that file. Build only |

Reviewed and OK: forum topic VM ownership and update scoping, topic menu permissions, view as messages/topics, closed-topic writing rules, timeline identities and anchoring; Forward request checks, secret-chat copy mode, closed-topic destinations, send order and account dismissal; folder write sessions, removal and reorder; quote ranges, entities, spoilers, drafts and bubble expansion.


### Chat search, chat actions, stickers and stories — 2026-10-16

Audit and fixes from `codex/parity-chat-tools` and `codex/parity-stories` (cherry-picked; build fixes `126be625`, `489aee75`).

| ID | Sev | Finding | Status |
|---|---|---|---|
| S-1 | P1 | Chat search jumps to the newest of the first 50 matches only; no arrows, "N of M", "No Results" or paging | fixed `27867360`: a bottom panel replaces the composer with calendar, members, "N of M" and up/down, paging by 50. Simulator: Saved Messages "parity" showed 1 of 3, up stepped to 2 and 3 of 3 with the newer arrow enabled |
| S-2 | P2 | No jump to a date (`getChatMessageByDate` unused) | fixed `27867360`: Telegram's day picker; jumps to the first message of the day (Telegram keeps the time of day). Simulator: the calendar sheet opened from the panel, Done closed search at the chosen day |
| S-3 | P2 | No "from:" member search | fixed `27867360`: "from:" lists members (`searchChatMembers`), a token scopes the search |
| S-4 | P3 | Placeholder differs from "Search this chat" | fixed `27867360` |
| S-5 | P3 | No results-as-list mode | fixed `6130fed6`, `ac2e1185` (cherry-picked from `codex/parity-next4`): Show as List with author, text and date rows, paging, and a tap back to the chat at that result. Simulator: "3 messages" list for "parity", a row tap returned at 2 of 3 |
| S-6 | P3 | Matched text isn't highlighted in bubbles | fixed `2e376636`: Telegram's substring highlight in text and captions, not over hidden spoilers. Simulator: "parity" highlighted in three bubbles |
| S-7 | P2 | Profile lacks Mute, Auto-Delete, Clear Messages, Leave/Delete; the auto-delete timer can't be set | fixed `088af4eb`: a More menu with Telegram's mute presets, auto-delete 1 day/1 week/1 month/off, Clear Messages and the removal sheet |
| S-8 | P3 | No custom mute duration or Auto-Delete "Other…" | fixed `5e304bb9`: Mute until a date and time, Auto-Delete Other with Telegram's 16 periods. Build only |
| S-9 | P3 | Chat-list Delete/Clear runs at once; Telegram waits 5 s behind Undo | fixed `9768eda9`: the row hides at once and the request runs after the 5 s Undo toast; Undo restores it; Clear History waits without hiding. Build only: testing Undo means deleting a real chat |
| S-10 | P2 | The sticker tab is one flat list | fixed `f5ec896c`: Favorites, Recently Used and installed packs with titles |
| S-11 | P2 | A sticker in a message opens the gallery; no pack preview or Add/Remove | fixed `f5ec896c`, `128758cc`: the pack sheet with Add/Remove and Copy Link |
| S-12 | P3 | No Add to/Remove from Favorites, Remove from Recents | fixed `f5ec896c`, `128758cc` |
| S-13 | P3 | GIFs can't be saved from messages or deleted | fixed `f5ec896c`, `128758cc` |
| S-14 | P3 | GIF search only filters saved GIFs | fixed `c067585e`: inline queries to `animation_search_bot_username`, sent with `sendInlineQueryResultMessage` only on tap. Build only |
| S-15 | P3 | The emoji tab is a fixed list of 100 | fixed `a5be6b5e`: Telegram's emoji1 list in 8 categories with an icon bar and 20 recent per account. Simulator: the tab shows Smileys & People and the category bar |
| S-16 | P3 | No sticker pack search or trending packs | fixed `77743a0f`: installed and server pack search below matching stickers, Trending Stickers on an empty focused field. Build only |
| S-17 | P3 | Secret chats search returns nothing (Telegram searches locally) | fixed `49594c37`: `searchSecretMessages` with offset paging. Build only: no secret chat on the account |
| S-18 | P2 | TDLib's chat action bar (`chat.action_bar`) was never shown: a chat from someone new offered no Block, Report Spam, Add to Contacts, Share My Phone Number, Unarchive or Add Members, and the join request notice was missing | fixed `659c3844` (ChatReportPeerTitlePanelNode at the classic `8e7e5fef` layout, ChatInterfaceTitlePanelNodes, ChatControllerReport.reportPeer, shareAccountContact, addPeerContact, dismissPeerContactOptions, unarchivePeer, presentChatRequestAdminInfo): a 40 pt bar under the navigation bar takes the pinned message's place in the chat itself (not in threads or topics, not while the person is blocked), with 16 pt buttons, red for Block and the spam reports, accent otherwise, one filling the room left of the encircled close button and several spread with up to 110 pt between them; close sends `removeChatActionBar`. peerButtons over TDLib's cases: Report Spam gives a person Block (Report Spam for a deleted account) and a group or channel Report Spam and Leave, or Report Spam and Unarchive once archived; Report/Add/Block gives Block and Add to Contacts, or Block and Unarchive; Add Contact gives "Add Name to Contacts" when the number is known; then Share My Phone Number, Add Members (the contact picker) and the join request notice with both names in bold, whose tap explains when the request went and offers I understand, which removes the bar. Block opens Telegram's sheet: "Do you want to block…", Report Spam and Delete this Chat checked, Block in red: the person is blocked, a secret chat closed, and the chat reported and deleted (or only reported); Report Spam and Leave asks Telegram's question (none for a public chat), reports with `reportChat` and an empty option and leaves; Unarchive moves the chat back with `addChatToList` and default notification settings and Telegram's toast; Share My Phone Number asks with the account's formatted number and sends `sharePhoneNumber`. Simulator 10-24: `-ui-probe-action-bar` passed the rules for every bar and kind of chat, the titles and the layout (one button 338 pt from x 32, the close button 14 pt from the edge); with `-ui-probe-action-bar-fixture report-add-block` Telegram Tips showed red Block User and accent Add to Contacts in place of the pinned message, and close brought the pinned message back; `join-request` showed the two-line notice, and its tap gave the explanation and I understand, which removed the bar. No real chat had an action bar, so no action reached TDLib. Reduced: Add to Contacts asks only the names (Telegram opens NewContactScreen with its share-number exception), the emoji status notice and the registration info of `accountInfo` are not shown, and Telegram's accompanying block on deleting a group is left out |
| S-19 | P3 | An empty chat showed only "No messages here yet" in grey: no greeting sticker, no Saved Messages, secret chat or new group notes | fixed `02b5e97c` (ChatEmptyNode: ChatEmptyNodeRegularChatContent, GreetingChatContent, CloudChatContent, SecretChatContent, GroupChatContent and the content choice in updateLayout): the card sits on BetterTG's service pill (the date header's colours), centred, rounded up to 20 pt. A person's chat (not a bot, deleted or support account, scam, or a blocked person) shows the semibold title, "Send a message or tap on the greeting below." and a 160 pt greeting sticker picked at random from `getGreetingStickers`, which sends itself on a tap when stickers may be sent; Saved Messages shows the cloud and its four notes; a secret chat "You have invited … / … invited you to join a secret chat" by `isOutbound`, "Secret chats:" and four lines with locks; a group the account created (not a channel, broadcast group or direct messages chat) "You have created a group", "Groups can have:" and four checked lines with TDLib's `supergroup_size_max`; threads and the rest the plain placeholder. The view is kept while its kind holds, so the sticker stays, and shows only once the history is known empty (`aff67ade`; the old label flashed while a chat loaded). Simulator 10-24: `-ui-probe-empty-chat` passed the content choice for a person, a blocked person, deleted and support accounts, a thread, a group member and the group's creator, each content's texts and the card inside the history, and its renders of the group, cloud and secret cards matched Telegram's layout. No empty chat was opened live (none could be found without opening someone's history), so the sticker's tap is build-only. Not ported: the topic, Premium-required and paid-message contents, the business intro |
| S-20 | P2 | The pinned banner showed only the newest pin: no stepping through several pins, no position, no list or Unpin All | fixed `b9b56fd6` (ChatController.topPinnedMessageSignal and topPinnedScrollReferenceMessage, ChatPinnedMessageTitlePanelNode and AnimatedNavigationStripeNode at the classic `8e7e5fef` layout, openPinnedMessages, performRequestedUnpinAllMessages, performUpdatedClosedPinnedMessageId): ChatVM loads the newest 100 pins with TDLib's count; the banner shows the newest pin at or above the newest message on screen, a tap jumps to it and moves on to the previous pin (the newest after the oldest) until the user drags; the title reads Previous Message for the older of two pins and "Pinned Message #N" for any but the newest of more; a 2 pt stripe of one segment per pin, the shown one in the accent and the rest at half strength, slides to keep it in view. With several pins the close button becomes the list button: "N Pinned Messages", newest first, a row returns to the chat at its message; the bottom bar offers Unpin All Messages to whoever may pin (the newest pin's `can_be_pinned`), which hides the banner behind "N Messages Unpinned" with Undo and sends `unpinAllChatMessages` (`unpinAllForumTopicMessages` in a topic) once the toast is gone, or Don't Show Pinned Messages, which hides the banner with "Pinned Messages Hidden" and Undo. Simulator 10-24 in BetterTG test > UI test with a second pin added silently: the banner read Pinned Message with the list button and a two-segment stripe, a tap showed Previous Message and a second tap jumped to the oldest pin and wrapped to the newest; the list showed "2 pinned messages" and Unpin All Messages, a row returned to its message; Unpin All with Undo kept both pins after 7 s. The added pin was removed afterwards. A first try lost its Undo tap (the device tool's element tap missed), so Unpin All ran and the fixture's own pin was pinned again silently. `-ui-probe-pinned-selection` passed the selection, the titles and the stripe's geometry. Reduced: the list is BetterTG's search result list, not a chat; pins past the newest 100 are counted but not listed |
| S-21 | P3 | No Unread Messages divider in the history | fixed `b76a59d5` (ChatUnreadItem, ChatHistoryEntriesForView's UnreadEntry over fixedCombinedReadStates): a chat opened with unread messages keeps the `last_read_inbox_message_id` TDLib reports as it opens, and the timeline shows "Unread Messages" in the thread start notice's bar above the oldest loaded message past it, until the chat closes; threads and topics are left out. `-ui-probe-unread-divider` passed the placement (between the read and unread messages, an album by its newest message, none when the read state is outside the loaded messages or everything is read); Telegram Tips showed no divider. Not seen live: opening a chat with unread messages would mark someone's messages read. Not ported: opening the chat at the first unread message (BetterTG opens at the newest) |
| S-22 | P2 | Verified, scam and fake accounts and channels carried no mark anywhere | fixed `e2925281` (EmojiStatusComponent's `.verified`, `.scam`, `.fake`; PresentationResourcesChatList's verifiedIcon, scamIcon, fakeIcon; ChatListItem, ChatTitleView, PeerInfoHeaderNode): from TDLib's `verification_status` of the person or supergroup, the blue verified badge (an SF seal sized to the font), or the red outlined SCAM or FAKE label, which outranks it, follows the name in chat list rows, chat search results, the chat header and the profile title; topics, threads and Saved Messages go without; VoiceOver reads the mark on the profile title. Simulator 10-24: Telegram Tips showed the badge in its header and profile, and a "durov" search showed it on both Pavel Durov channels and not on an unverified namesake. Scam and fake not seen live. Not ported: bot verification icons and emoji statuses (Premium) |
| S-23 | P3 | A tap on a date header did nothing | fixed `64317d13` (ChatMessageDateHeader's action, ChatController.navigateToFirstDateMessage with `alreadyThere`, openCalendarSearch): a tap on a date pill opens the jump-to-date calendar on that day, and Done opens the chosen day at its first message; the pill is one VoiceOver header button. BetterTG's headers don't float, so a visible header always rests at its day, where Telegram opens the calendar. Simulator 10-24 in UI test: the Oct 18 pill opened the calendar on October 18, and Done brought "parity draft link", that day's first message, into view. Floating date `f01ee852` (ChatMessageDateHeaderNode's stick distance and updateFlashing, ListView's resetHeaderItemsFlashTimer): while the user drags or the history decelerates after a drag, and 0.3 s after, the date of the message at the top edge floats 6 pt under the top bars in the header's pill, fading in over 0.3 s and out over 0.4 s; it stays hidden while that day's own header rests in view, the next day's header pushes it up, and programmatic scrolls don't show it. Simulator 10-24 in UI test: a drag showed Oct 17 under the pinned banner during the deceleration, gone 2 s later. Not ported: Telegram's media calendar (CalendarMessageScreen) |
| S-24 | P3 | The message menu had no Speak | fixed `b7f260cd` (ChatInterfaceStateContextMenus' Speak under `isSpeakSelectionEnabled`, Speak.speakText): with iOS's Speak Selection on, a message with text gets Speak after Translate, reading the text aloud with AVSpeechSynthesizer in its detected language; a new Speak stops the previous one. Build only: Speak Selection is off in the Simulator. Not ported: Speak in the text selection menu |
| S-25 | P2 | Quotes and code blocks in messages showed as plain or monospaced text; the composer could make neither | fixed `ecca2674` (TextNode's TextNodeBlockQuoteData drawing and layout, stringWithAppliedEntities' `.Pre` and `.BlockQuote`, ChatMessageTextBubbleContentNode's colours), `cd55cb08` (ChatTextInputPanelNode's Format menu): a quote or code block gets the accent tint behind its paragraphs with 4 pt corners, the 3 pt accent line, the text 11 pt in and a point smaller, the quote or code icon at the top right, and a code block with a language its capitalized name above the code; 6 pt around each block, the time on its own line after a block that ends the text, the bubble widened for the icon's room. The composer's Format menu follows Telegram's order with Quote first and Code last. Simulator 10-24: `-ui-probe-text-blocks` passed the block ranges and layout and its render showed a wrapped quote and a "Swift" code block in Telegram's look; in UI test, Format → Quote on a selection sent "parity quote block check", which shows as a quote block with the time below. A tap on code copies it, as before. Expandable quotes `dae5ecb7` (InteractiveTextNode's collapsible block quote, its truncated third line and expand arrow, ChatMessageTextBubbleContentNode's expandedBlockIds and requestToggleBlockCollapsed): an expandable quote longer than three lines folds to three. The third line ends in an ellipsis clear of the arrow, and Telegram's chevron sits 6 pt from the block's right and 3 pt from its bottom. A tap on the quote opens it with the chevron turned up, giving the last line 16 pt beside the arrow or 10 pt under it, and a second tap folds it. The message keeps the state through reconfigures and edits. TextKit 1 hides the folded text with null glyphs and zero-height lines. `-ui-probe-text-blocks` passed the fold to three lines, the taller open state, a two-line quote left open and the tap; Simulator 10-24 in UI test: a six-line expandable quote sent there showed three lines with "lo…" and the arrow, a tap opened all six lines and grew the bubble, and another tap folded it. Not ported: the fade under the folded text, syntax highlighting, quote styling inside the composer, Pull Quote and Date |
| S-26 | P3 | Choosing a reaction just added its chip, with no animation | fixed `a4ec7f9c` (StandaloneReactionAnimation.animateReactionSelection, ReactionContextNode's ReactionItem with listAnimation = centerAnimation and applicationAnimation = aroundAnimation): once the chip of a standard reaction the user adds shows, from the menu's strip or a tap on another person's chip, TDLib's emoji reaction gives two TGS animations that play once above the chat. The center animation plays over the chip's icon, hidden meanwhile, and the around animation bursts over three times the icon's size around it. Reduce Motion skips them. Simulator 10-24 in UI test: 🤣 from the menu on "parity quote block check" burst small laughing faces around the chip while the 🤣 moved, then settled. The reaction was removed afterwards. Custom emoji `8aed59d8` (StandaloneReactionAnimation's generic_reaction_small_effect and generic_reaction_inline_pattern with InlineStickerItemLayer in its placeholders): a custom emoji reaction gets Telegram's bundled particle burst over three times the icon's size and the pattern throwing seven copies of the emoji, each drawn at the pattern's on-screen size once its first frame is ready; the chip keeps its icon. Simulator 10-24 in UI test: the account's custom heart quick reaction burst coloured particles and hearts around its chip; the reaction was removed afterwards. Not ported: the large effect of a long-pressed reaction and the animation of reactions others add |
| S-27 | P2 | A double tap on a message did nothing; Telegram toggles the quick reaction | fixed `6007f4b0` (ChatMessageBubbleItemNode's tapLongTapOrDoubleTapGesture, ChatController.updateMessageReaction with `.default`, reactionSettings.quickReaction): a double tap on a bubble outside its controls toggles the account's quick reaction from TDLib's `updateDefaultReactionType`, 👍 until TDLib names one. It comes off if chosen; otherwise it goes on with a light haptic and S-26's effect, where `getMessageAvailableReactions` offers it. Selection, read-only chats, service messages and messages being sent go without. Simulator 10-24 in UI test: double taps on "parity quote block check" added the account's quick reaction (a custom emoji heart) and took it off again, leaving the message as it was. Not ported: Telegram's single tap waits out the double tap, so here a double tap on a link also opens it; custom emoji reactions got no effect until `8aed59d8` |
| S-28 | P3 | A bubble's status showed neither a group message's reply count nor a pinned message's pin | fixed `89cb5771` (ChatMessageDateAndStatusNode's repliesIcon with the count and its pinned icon, ChatMessageBubbleItemNode's dateReplies and isPinned): in a group's own history, a message with replies starts its status with the replies icon and the thread's count. A pinned message without replies starts it with a pin, in any chat's history. Threads and forum topics show neither, as Telegram's reply thread location does, and channels keep their comments bar. `-ui-probe-status-line` passed the count in a group, the pin, the thread and the channel, and its render showed "12 12:00" after the replies icon and the pin before "12:01". UI test, a topic, kept its statuses without pins. BetterTG draws the icons with SF Symbols |
| ST-1 | P2 | No story viewer; shared stories and mentions were untappable, no rings | fixed `7fdaec19`, `45d3e06d`, `2dd7048d`, `31f7ef3f`: a UIKit viewer (segments, header, caption, quarter taps, hold to pause, drag to dismiss, poster paging, `openStory`/`closeStory`, story updates scoped to the client), opened from story bubbles, the profile avatar ring and chat list avatar rings. `-ui-probe-story-viewer` passes; no chat in the list had active stories at 05:31, so the viewer wasn't opened live. Cube, areas and More menu `1cf01869`/`04d987b7`/`4da5b432`/`c237a8ae` (cherry-picked from `codex/parity-story-viewer`), `4f9eccf0`, `2b1a9296` (StoryContainerScreen, StoryItemSetContainerComponent, StoryItemSetContainerViewSendMessage, StoryItemOverlaysView): posters turn on Telegram's cube (`calculateCubeTransform`: perspective 500, 40 pt gap, face dimming \|fraction\|·1.3, rubber band 600/0.4 at the ends, commit past 0.3 of the width or 100 pt/s on a 0.4 s spring; the side face shows the neighbour's first unseen story; Reduce Motion slides flat); story areas sit by `storyAreaPosition` (rotation, corner radius), the suggested reaction with its count and the weather draw over the story, and a tap on a location, venue, link or message shows Telegram's View Location, Open Link or View Message tooltip whose second tap opens `LocationViewController`, the link router or the message; More for someone else's story (`performOtherMoreAction`) offers Notify/Do Not Notify About Stories, Copy Link, Share (the Forward picker titled Share to, then `inputMessageStory`), Hide/Unhide Stories with Undo, Save to Gallery (Premium only, else Telegram's toast) and Report (`reportStory`); the story pauses under tooltips, menus and sheets. Xcode MCP 10-17: `-ui-probe-story-viewer` passed with the menu rules for contacts, muted and hidden posters, strangers, service accounts, bots, private, protected and own stories; `-ui-probe-story-viewer-ui` passed `cube 0.5` and `-0.5` (the neighbour's face showing, Bob's face turned), `cube-commit 0.4` (Carol shown, at rest) and `0.2` (back to Bob), `areas` location, venue, message, link and weather (two overlay areas, tooltips view location, view message, open link telegram.org, none for weather) and `menu` (do not notify, copy link, share, hide stories, save to gallery, report); a live swipe left turned to Carol 1/1 and a slow drag right back to Bob 2/3. Nothing reached TDLib (offline fixture). Replies and reactions (MessageInputPanelComponent, `performLikeAction`, `performLikeOptionsAction`, `activateInlineReaction`, the reaction context's `replyToStoryId` message): under a user's story a 40 pt glass field "Reply Privately...", under a group's where the account may write "Comment Story...", with the share button for a public forwardable story (Share then leaves the More menu) and the like button; a service account's, unsupported, live or closed story shows "You can't reply to this story"; the account's own, a bot's, a channel's story and a group it can't write to show none. The story sits above the panel (Telegram's bottom inset), the field rises with the keyboard over the story dimmed to 0.8 black, the story pauses while editing, Return or the send button sends `inputMessageReplyToStory` text with "Message Sent" and View in Chat; with the field empty the reactions from `getStoryAvailableReactions` show titled "Send reaction as a private message" (group: "as a message") and one sends as a reply with "Reaction Sent."; the like button sets Telegram's heart or takes the reaction back (`setStoryReaction`, optimistic, reverted on error), holding it on a user's story opens the reactions over it to slide onto one, picking the current one removes it; a tap on a suggested reaction area sets that reaction. Xcode MCP 10-18: `-ui-probe-story-viewer` passed the panel rules (user, contacts only, closed, service, bot, self, group, read-only group, channel, live, reaction text) and the menu without Share beside the panel; `-ui-probe-story-viewer-ui reply edit`, `like-options`, `send`, `areas reaction` and `menu` passed (panel at 779+60, story 715 pt; heart then none; 8 reactions titled; menu do not notify, copy link, hide, save, report); live taps sent 🔥 and 👏 from the strip with the toast above the panel, typed "Hello" and sent it, slid the held like onto 🥰. No chat in the list had active stories on 10-18, so nothing reached a real story. Speed and translation in More (`contextMenuSpeedItems`, `speedList`, `optionsRateImage`, `performTranslateTextAction`): a video story's menu starts with Playback Speed and the rate in a gauge icon, a level down Back, 0.5x, Normal, 1.5x, 2x with a check; the rate holds for later videos while the viewer is open; a caption in a language the user doesn't read (with Show Translate Button on) offers Translate before Report and opens the translation sheet. Xcode MCP 10-18: `-ui-probe-story-viewer` passed speed and translate; `-ui-probe-story-viewer-ui menu-video` passed (speed, do not notify, copy link, hide, save, report), picking 1.5x and 2x recorded the speed and the reopened menu showed a 2x gauge and the check on 2x. The account's own story `71834019` (StoryFooterPanelComponent, performMyMoreAction, performDeleteAction, AnimatedAvatarSetView, countString): in the reply panel's place, 10 pt under the story, a 44 pt footer with the latest three viewers' 30 pt avatars overlapping by 10 pt (the left one on top, the others cut 1.5 pt around it), the view count and Story.Footer.ViewCount's words or No Views, the reactions in red and the reposts in green once the story has views, and the delete button, whose sheet confirms Delete Story (`deleteStory`) and moves to the next story or closes; the More button opens the own menu: Playback Speed for a video, Save to or Remove from Profile (`toggleStoryIsPostedToChatPage`, Telegram's saved and removed toasts), Save to Gallery without Premium, and Copy Link and Share for a public story that is active or on the profile. Simulator 10-24 (`./build.sh run`, iPhone 17 Pro iOS 26.5, `8108A92F`): `-ui-probe-story-viewer` passed the own menu (active, expired on and off the profile, no username, live), the button, the footer counts, No Views, the views label and countString; `-ui-probe-story-viewer-ui own footer` passed (footer 787+44 under a 715 pt story, 3 views, 2 reactions, 1 repost, 3 avatars, no reply panel, More shown), `own menu` passed (save to profile, save, copy link, share), `own delete` passed (sheet Delete Story/Cancel, then story 1002 with no views); `menu` and `reply send` still pass. The account has no story of its own, so nothing reached a real one. The viewers list `053e4c10`, `b27965cb` (StoryItemSetViewListComponent, StoryItemSetContainerComponent's viewListDisplayState, `getStoryInteractions`). The footer's counts, or a swipe up on the own story, open it at half the screen, with the story shrunk above and the footer's counts gathered in white over its bottom. A pull up opens it to 60 pt from the top, and a pull down, the 30% or 5%-with-speed rule, or a tap on the story closes it. The title, or the All Viewers and Contacts tabs from 20 viewers on a public story, the sort button (Reactions First, Recent First) from 10 reactions, and search. Placeholder rows load into 60 pt rows: avatar, name, read checks or a green repost or forward icon, the time, the reaction with a red heart for ❤. The empty texts, with TDLib's `has_expired_viewers` in place of the Premium upsell. A row opens the viewer's profile, a forward's message or a repost's story. The channel admin's More menu (performMyChannelMoreAction) shows on stories the account may edit or delete: speed, Save to or Remove from Posts with the channel's or group page's toast, Save to Gallery, Copy Link and Share, Hide or Unhide Stories, Delete Story; `-ui-probe-story-viewer` checks it for a channel and a group. The channel footer `8d1a8d47` (StoryFooterPanelComponent's isChannel) takes the reply panel's place under a channel's story or a group the account can't write to: the eye with at least one view, the like button with the count (the account's own reaction counted at once), and Share for a public channel's forwardable story; `-ui-probe-story-viewer-ui channel` passed (views 1, Share, the like set ❤ 1). Holding a row lifts it with peerContextAction `8b07a45b`: Show or Hide My Stories, Delete Contact for a contact, Block User for anyone else, through `setMessageSenderBlockList` and `removeContacts`, with Telegram's toasts, and undo for the block and the deletion. `own viewers-menu` checks the menus offline; a live press on Bob's row lifted it with Block User, and nothing was chosen. Simulator 10-24: `-ui-probe-story-viewer` passed the header, empty-text, subtitle, geometry and drag-outcome rules; `-ui-probe-story-viewer-ui own viewers` (half at 337, story scale 0.38, rows Alice ❤, Bob, Carol's commented repost, the tap on Bob) and `own viewers-full` (full at 60, footer faded, closed back at scale 1) passed. Live idb swipes opened, expanded and closed it, and the earlier own, menu, reply, cube and areas probes still pass. The account has no story of its own, so no real interactions were loaded. Not ported: Telegram's speed slider (BetterTG's menu has no slider row), the carousel of the account's other stories beside an open viewers list, the channel viewers list, Who Can See, Edit Story and Edit Cover (no story editor), the upload status of a story being posted, the channel footer's repost button and the admin menu's Edit, Edit Cover and View Statistics (BetterTG has no story editor or statistics), stealth mode (Premium), HD/SD (TDLib gives one story quality), statistics, `UpgradedGift` areas; a location opens the viewer where Telegram searches stories by place |
| SE-1 | P2 | Settings had only accounts, theme, language, animated media, version and logout | fixed `cdd3c243`, `200e10e8`, `518def60`, `dfbbf295`, `f7cd0497`, `ae7084d4`, `b8e743a3` (cherry-picked from `codex/parity-settings`): profile header with Edit Profile (name, bio, birthday, photo, username with live availability), Saved Messages, Devices (sessions, terminate, inactive TTL), Chat Folders, Privacy and Security (blocked users, 2FA status, default auto-delete, eight rule editors with exceptions, account TTL), Notifications (scopes, exceptions, reset), Data and Storage (storage by type and chat, clear cache, network usage). Simulator (read-only): the header, Devices with 21 sessions, Privacy values (165 blocked, phone nobody (+1)), Notifications counts (32/11/12 exceptions) and Data totals (586.1 MB, 1.76 GB). Skipped: auto-download presets and Keep Media (BetterTG has no auto-download or periodic cleanup), Premium/Gifts/Business items, QR login, websites, change number |
| LK-1 | P2 | Telegram links other than language packs and folder invites opened Safari; @mentions weren't tappable | fixed `564e1032`, `ee0ac512`, `ede5d5d6`, `530e864c` (cherry-picked from `codex/parity-links`): `getInternalLinkType` routing for public chats, message links (chat, topic, comments), invite links with Telegram's join preview (join only on tap), bot start with the Start button, phone and token links, sticker sets, stories, Settings sections and Saved Messages; @mentions and text mentions open their chat. `-ui-probe-telegram-links` passes. Simulator: `bettertg://settings/devices` opened Devices, `bettertg://resolve?domain=telegram&post=1` opened Telegram News at its first post. Added `6ff9ab2b`, `33bbfea9`: `startgroup`/`startchannel` open a picker of manageable groups or channels, then the bot admin rights screen with the Admin Rights switch (Add Bot as Admin / as Member) or the Add Bot as Member alert; `msg?text=` puts the draft into the chosen chat's composer; game links share the game after a confirmation; TGProgressWindow's loading overlay shows while a link resolves and cancels it on tap. Simulator: the draft reached UI test's composer, LumberJack was sent to UI test, `startgroup&admin=delete_messages+pin_messages` made GameBot an admin of BetterTG test with those rights, `startgroup=parity` added it as a member and opened the group, `startchannel` listed only manageable channels; with `-ui-probe-slow-links` the overlay showed and a tap cancelled the link |


### Compose flow and message actions — 2026-10-16

From `codex/parity-media-audit` (compose) and `codex/parity-msg-actions` (message actions, M-x audit), cherry-picked.

| ID | Sev | Finding | Status |
|---|---|---|---|
| CO-1 | P2 | No compose entry, contacts list, New Group/Channel/Secret Chat or Add Contact | fixed `8e1a4612`, `14142dab`, `d6263ffe`, `74dc37aa`, `942bda55`, `941f0b44`: a pencil next to Settings opens New Message (contacts by name or last seen, letter index, contacts and global search), New Group (chips, counter, name, photo, auto-delete; `createNewBasicGroupChat` on Create), New Channel (intro, info, public/private link, subscribers), New Secret Chat, New Contact (`searchUserByPhoneNumber`, `addContact`/`importContacts` on Done). The classic bar now shows `navigationItem.subtitle`. Simulator (read-only): New Message rows, contacts with last seen and the index; New Group chip and "1/200000"; nothing was created |
| M-1 | P2 | No Copy Link | fixed `e5fddc03`. Simulator: Hacker News post copied `https://t.me/hacker_news_feed/132813` with Telegram's toast |
| M-2 | P2 | No Report | fixed `ea348b3d`: TDLib's reason pages and comment step, a report only on a chosen reason. Simulator: Report appears in a channel post menu (not opened) |
| M-3 | P2 | No Seen By | fixed `e925392b`: `getMessageViewers` sheet. Build only |
| M-4 | P3 | No who-reacted list | fixed `e925392b` as a menu item, and `f85fd719`: a long press on a reaction chip lists who chose that reaction. Build only |
| M-5 | P2 | No silent, scheduled or when-online sends | fixed `280e2f8f`: Send long-press menu and Telegram's schedule picker. Simulator: Saved Messages offers Set a Reminder, the picker reads "remind today at 07:30"; cancelled, nothing sent |
| M-6 | P2 | No Scheduled Messages screen | fixed `280e2f8f`: grouped list with Send Now, Reschedule, Copy, Delete, and the input calendar button. Build only: no chat has scheduled messages |
| M-7 | P2 | Scheduled messages could enter the normal history | fixed `280e2f8f` |
| M-8 | P3 | No Translate | fixed `ce574a59`: Show Translate Button in Settings > Language (off by default), Translate for messages not in the app or a system language (Telegram's canTranslateText), `translateText` sheet with Copy Translation. Build only |
| M-9 | P3 | No Save Image/Video in the message menu | fixed `6519446b`: Save Image/Video (with Photos permission and toasts) and Save to Files for documents and audio, hidden for protected, secret and self-destructing messages. Build only |
| M-10 | P3 | No link preview panel or remove-preview | fixed `a7bed387`: debounced `getLinkPreview` panel in the reply slot, × disables, a tap opens Move Up/Down, Enlarge/Shrink and Do Not Preview, kept in drafts. Simulator: typing https://telegram.org in Saved Messages showed "Telegram — a new era of messaging" and the options menu; text cleared, nothing sent |
| M-11 | P3 | No admin delete options (delete all from user, report spam, ban) | fixed `d7c453fb`: Telegram's admin sheet with Report Spam, Delete All From and Ban, run only on Proceed. Build only |
| M-12 | P3 | No read date in private chats | fixed `7549082a`: "read today at HH:MM" from `getMessageReadDate`, and the show-read-time alert. Build only |
| M-13 | P3 | Deleting several selected messages uses the plain delete, not the admin sheet | fixed `911d5161`: the admin sheet for multi-message selections, covering all senders. Build only |
| M-14 | P3 | The admin sheet bans but has no partial restriction options | fixed `911d5161`: Partially restrict with Telegram's rights list, applied with `setChatMemberStatus(restricted)` on Proceed. Build only |
| M-15 | P3 | Edits and media captions show no link preview panel | fixed `af1ba506` for text edits (Telegram has no caption preview); options change only the edit. Build only |
| M-16 | P3 | Save items only for single messages, not per album item | fixed `e09cd4f9`: the pressed album tile or file row is saved. Build only |
| M-17 | P3 | Translate lacks Do Not Translate languages, Change Language and the selection menu item | fixed `712772cb`: Do Not Translate languages, Change Language and the selection Translate. Build only |
| M-18 | P3 | The message menu showed no edit time, and a group's Seen By and reactions were plain rows at its end titled "Seen By" | fixed `d6efa960` (ChatReadReportContextItem, ReactionListContextMenuContent's merged items): an edited message's menu opens with "edited today at 22:48", yesterday, or Telegram's numeric medium date ("edited 10/17/26 at 22:48"), from TDLib's edit date. In a group one row sits atop the menu: N Seen, Listened for a voice message or Watched for a round video, Nobody Viewed/Listened/Watched dimmed and inert, N reactions, N reacted or R/S reacted; a shimmer and three placeholder circles while `getMessageViewers` loads, then up to three of the latest reactors' or the first viewers' 24 pt avatars at the trailing edge, 10 pt overlap, the first on top. It opens the reactions followed by the viewers who didn't react, or the viewers. Channels and private chats list no reactions, as Telegram. `-ui-probe-read-report` passed the wording, enabling and avatar rules and rendered the loading, seen and nobody-listened rows. UI test: the edited checklist's menu read "edited 10/17/26 at 22:48"; an own message given 🤣 showed "1 reaction" with the account's photo and opened "1 reacted" with the reaction and time; the reaction was then taken back. No group here lets TDLib list viewers, so a live Seen count wasn't shown. BetterTG keeps its sheet for the list (Telegram pushes it inside the menu with per-reaction tabs) and SF Symbols for the icons |
| B-1 | P2 | An empty bot chat showed "No messages here yet" instead of the bot description | fixed `7ea12c36` |
| B-2 | P2 | A bot chat without history had no Start button | fixed `7ea12c36` |
| B-3 | P2 | No "/" command suggestions or Menu button | fixed `7ea12c36` |
| B-4 | P2 | No inline bot mode ("@bot query") | fixed `7ea12c36`: list or strip results, paging, `sendInlineQueryResultMessage` on tap. Simulator: "@gif cats" in Saved Messages showed the GIF strip; cleared, nothing sent |
| B-5 | P3 | Tapping a /command in a message did nothing | fixed `22c14b1d` |
| B-6 | P3 | Reply keyboard phone, location, poll and request buttons show "unsupported" | fixed `c1eb5be8`: phone and location ask Telegram's "Share Your Phone Number?" / "Share Your Location?" and reply to the keyboard message only after OK; users and chat requests open a picker of peers TDLib accepts (`shareUsersWithBot`, `shareChatWithBot`). Poll, managed bot and Web App buttons stay unsupported. Build only: pressing would send |
| B-7 | P3 | A blocked bot has no Restart Bot | fixed `ef5d6b2b`: Restart Bot replaces the composer while the bot is on the block list; a tap unblocks and sends /start (or the link parameter). Build only: no blocked bot to open without blocking one |
| B-8 | P3 | The inline placeholder is a hint row, not in the input | fixed `7dcf851e`: the bot's placeholder sits greyed in the input after "@bot " (ChatTextInputPanelNode `contextPlaceholderNode`) and leaves on the next character; the hint row is gone. Simulator: "@gif " in BetterTG test → UI test showed "@gif Search GIFs" in the field over the GIF strip, "c" hid it; cleared, nothing sent |
| B-9 | P3 | No "@" member or recent inline bot suggestions | fixed `d4ab2e6f`: recent inline bots when "@" opens the input, group members from `searchChatMembers(mention)` sorted by name, also while editing. Simulator: in a group "@" listed members, a typed prefix narrowed them, picking a member put the member's @username in the input; cleared, nothing sent |
| B-10 | P3 | No bot info card above the first message of a non-empty chat | fixed `c1e2ba61`: a timeline row above the first date once the history reaches its start. Simulator: Rose showed "what can this bot do?" above Jul 29 /start; another bot (no description) showed none |
| B-11 | P3 | Inline bots needing location get no location or permission prompt | fixed `4706624e`: Telegram's ShareInlineBotLocationConfirmation alert (at most every 10 minutes per bot, the query waits), consent kept per bot, then one location fix with a 5 s timeout as `userLocation` for every page. Build only: no location bot was queried |
| B-12 | — | Mini Apps (menu web app, web app buttons) | fixed: superseded by R-1's Web App runtime (`860753ca` WKWebView with TelegramWebviewProxy, attachment menu bots, main Web App, the menu button, `startattach` and side menu bots through `07fa786c`); proofs are under R-1 |


### Group and channel management — 2026-10-16

From `codex/parity-groups` (cherry-picked; build fix `12f1b2ce`).

| ID | Sev | Finding | Status |
|---|---|---|---|
| G-1 | P2 | Edit had only title and description; admins without Change Info got no Edit | fixed `f449cf52`: photo, name, description, the management rows the rights allow, Delete for the owner. Simulator: a channel the account administers shows invite links, subscribers 33, administrators 33, removed users 1, recent actions |
| G-2 | P2 | No chat photo change | fixed `f449cf52` |
| G-3 | P2 | No Delete Group/Channel | fixed `f449cf52` |
| G-4 | P2 | No default permissions, slowmode or exceptions | fixed `36fa63ee` |
| G-5 | P2 | No Removed Users or unban | fixed `d033dc0a` |
| G-6 | P2 | Read-only admin list | fixed `0aeb8555`: add admin, rights editor, custom title, dismiss, sign messages and show authors. Simulator: 33 admins with "promoted by" lines and Add Admin |
| G-7 | P2 | No Promote, Restrict, Remove or Add Members | fixed `727e7704` |
| G-8 | P2 | No invite link management | fixed `1e480f34`, `12f1b2ce`, `afae09a9`: primary link, create/edit/revoke/delete, joined members, Get QR Code (Telegram's rounded QR with the plane logo, Share QR Code), owner-only Invite Links Created By Other Admins. Simulator: link menu shows Get QR Code; the sheet decoded back to the group's t.me link; Share QR Code opened the share sheet. The other-admins section stays hidden because no other admin has links |
| G-9 | P2 | No join requests | fixed `06fc4b8a` |
| G-10 | P2 | No Group/Channel Type | fixed `f26dd7d8`: public link check or private invite link, join-to-send, approve members, restrict saving |
| G-11 | P3 | No chat history, topics, hide members toggles | fixed `8c775528` |
| G-12 | P3 | Auto-delete missing from Edit | not a defect: Telegram keeps it in the More menu (S-7) |
| G-13 | P3 | No Recent Actions | fixed `91d5d6ef`: `getChatEventLog` by day with Telegram's sentences. Simulator: Telegram's empty state for the last 48 h |
| G-14 | P3 | No discussion group link setup | fixed `d7acd743`, `96e9dd60`: the discussion screen adds Create New Group above the candidates; it opens New Group with the channel name plus ' Chat', creates a supergroup and links it with `setChatDiscussionGroup`. Xcode MCP 10-18 (with the user's approval): Create on the private BetterTG parity channel made 'BetterTG parity channel Chat', returned to the channel's edit screen with Discussion showing it, and the discussion screen shows it selected with Unlink Group |
| G-15 | P2 | A channel the user can't post to, a broadcast group and a group or channel the user hasn't joined showed nothing under the history: no Join, Mute or search; a restricted member and a removed user saw nothing either, and a blocked person's chat kept the composer | fixed `0878386c` (ChatChannelSubscriberInputPanelNode, GlassControlPanelComponent, inputPanelForChatPresentationIntefaceState, togglePeerMuted): first as release 13's floating glass capsules, then restyled `f0cfdd77` in the classic chrome BetterTG keeps ("Appearance follows BetterTG main", no glass button backgrounds; classic panel at `8e7e5fef`): a bar of the composer's docked glass, as high as the resting composer (50 pt above the safe area, as Telegram's panel matches its text input panel), with the classic accent title in 17 pt: Join across the bar, Mute and Unmute centred at their title plus 24 pt, sliding 30 pt up or down with a fade as the classic panel does when one becomes the other; release 13's search button on the right and, for a broadcast group's member, the help button with GigagroupDescription on the left. A channel offers Join until joined and Mute meanwhile; a group offers Apply to Join Group, Join for a forum, or Join Group. Mute or Unmute follows the chat's own setting or its scope's and toggles as togglePeerMuted does (unmute, else mute forever), turning back if TDLib refuses; ChatVM now reads `updateChatNotificationSettings`. Join sends `joinChat`, with Telegram's request-sent toast and its too-many and private alerts. A chat that becomes writable gets the composer in the panel's place. The panel steps aside for search and selection. Threads, topics and direct messages chats keep their own panels. Simulator 10-24 (iPhone 17 Pro iOS 26.5): `-ui-probe-subscriber-panel` passed the action rules for every member status and the geometry; a channel showed Unmute with search, the search button opened in-chat search and closing it brought the panel back; Telegram Tips, opened by link, showed Join; after the restyle it shows the accent Join across the docked bar with search on the right. Neither Mute nor Join was pressed (both change the account), so the toggle, the join and the composer arriving after it are build-only. Not ported: the gift and suggested-post buttons (Stars), the joined group's Add Tag toast. The other input panels `da559d8f` (ChatUnblockInputPanelNode, ChatRestrictedInputPanelNode, DeleteChatInputPanelNode, ChatController.unblockPeer and deleteChat) share the panel as ChatStatusPanelView: a person the user blocked gets the accent Unblock, dimmed to 0.7 while `setMessageSenderBlockList` clears the block, after which the composer returns (a blocked bot keeps Restart Bot, a secret chat its own panel); a group member who can't send gets the restriction in 13 pt secondary text, up to two lines: the member's own (RestrictedText, or RestrictedTextTimed with stringForFullDate) or the group's (DefaultRestrictedText); a basic group the user left or was removed from and a supergroup or channel that banned them get a red Delete and Exit, which removes the basic group's history and chat or leaves the supergroup, as the chat list's Delete does, and closes the chat (Telegram's accompanying block of the peer is left out). An installed composer hides while a panel stands in for it, so blocking or a restriction arriving mid-chat swaps them; search and selection hide both and bring the right one back. Simulator 10-24: `-ui-probe-status-panel` passed the panel choice for writable, banned, restricted, read-only and left chats, the three restriction texts and each style's geometry; Telegram Tips showed Join with search and no help in the accessibility tree; UI test's composer hid for search and selection and came back. Unblock, the restriction and Delete and Exit weren't reached live (no blocked person's chat could be opened without the swipe that unblocks, no restricted or left group) |
| G-16 | P3 | A secret chat waiting for its keys or closed showed nothing under the history | fixed `2efd251c` (SecretChatHandshakeStatusInputPanelNode, inputPanelForChatPresentationIntefaceState's `.terminated`): the status panel reads DialogList.AwaitingEncryption with the person's name for the side that started the chat and Conversation.EncryptionProcessing for the other, in the classic 15 pt primary text, and a closed secret chat gets Delete and Exit, which deletes it from the lists. `-ui-probe-status-panel` passed the pending, closed and ready cases. Build only: the account has no secret chat |
| G-17 | P3 | The chat header's title showed neither a secret chat's lock nor a muted chat's speaker | fixed `5aa77e37` (ChatTitleView's titleLeftIcon `.lock` and titleRightIcon `.mute`, PresentationResourcesChat's chatTitleLockIcon and chatTitleMuteIcon): a secret chat's title starts with a lock in the title's colour, and a chat muted on its own, not by its scope, ends with a small grey speaker. A verified title goes without the speaker, as ChatTitleView leaves it off, and topics and threads go without both. The speaker follows `updateChatNotificationSettings` while the chat is open. `-ui-probe-title-icons` rendered the lock, the speaker, both, and a verified title without them; BetterTG draws them with SF Symbols. Not seen live: opening a muted chat would read its unread messages |

Approve New Members asks whether to apply the change to existing invite links (`27bb1653`, `toggleSupergroupJoinByRequest` with `applyToInviteLinks`); verified 2026-10-18 on BetterTG test with one link, both on and off. Not ported: collectible link ordering, Recent Actions filters and bubbles. Switches in these screens apply on tap, so the Simulator check stayed on list and detail screens.


### Media sending and gallery audit — 2026-10-16

From `codex/parity-gallery-audit` (cherry-picked; a ChatVM conflict with the bot slice kept both helpers).

| ID | Sev | Finding | Status |
|---|---|---|---|
| MD-1 | P2 | Protected media offered Share, Save and Forward that failed after the tap | fixed `d98b305c` |
| MD-2 | P2 | No Send as File(s) for picked photos and videos | fixed `097b4157` |
| MD-3 | P2 | No Send Without Grouping | fixed `097b4157`: groups of up to 10, already-sent groups leave the composer on a later failure |
| MD-4 | P2 | No spoilers (`hasSpoiler` always false) | fixed `097b4157`. Simulator: two attached photos, Send long press listed Set a Reminder, Send as Files, Send Without Grouping, Hide With Spoiler; spoiler blurred the thumbnails; removed, nothing sent |
| MD-5 | P3 | No Move Caption Up | fixed `097b4157` (offered with a caption) |
| MD-6 | P2 | Music from Files went out as a generic file | fixed `91931949`: mp3/m4a/flac as audio with tag title, performer and cover |
| MD-7 | P2 | Music had no header, stopped with its chat, had no playlist | fixed `11f5ffff`: the media header for music, swipe for older/newer, continues over the chat list. Xcode MCP 10-17 (playing someone else's mp3 allowed by the user): global search "mp3" found an mp3 in a group; its play button downloaded and played it (0:08 of 2:33 in the bubble) and the header showed the file name over "unknown artist" with pause and close; close stopped playback and removed the header |
| MD-8 | P3 | Gallery menu had no Reply | fixed `2b2d610f` |
| MD-9 | — | Silent, scheduled and when-online for media and files | already correct |
| MD-10 | — | Gallery seek, speed, PiP, captions, View in Chat, thumbnail strip, live photos | already correct |
| MD-11 | P2 | No Location, Contact or Poll sending | partly fixed `6a3588d8`/`32b4fe6d`/`5626b969`: the attach menu gains Location (LocationPickerViewController on MapKit: current location, live location for a period, search), Poll (CreatePollViewController after ComposePollScreen: question, description, options, anonymous/multiple/adding options/revoting/shuffle, quiz with correct answers and explanation, duration limit) and Contact. Xcode MCP 10-16: the menu lists all three; location asks for permission, then shows the map, send current/live location and an empty places list; the poll creator shows Telegram's group defaults; the contact picker opens; each cancels with nothing sent. Live location `d8d2f703` (LiveLocationManager: per account/client from updateActiveLiveLocationMessages, first fix at once then at most every 4 s with heading, nil edit on stop), the sharing panel in chat and chat list with Stop Sharing `6dabb990`, venue search through the venue bot (venue_search_bot_username, else @foursquare, getInlineQueryResults) with address search `3cd8ab0b`, and the bubble's remaining-time ring and "updated X ago" `48085deb`. Xcode MCP 10-16 at a simulated San Francisco location: the picker lists the bot's places (Yerba Buena Gardens, SFMOMA) and pins them on the map. Xcode MCP 10-17 in UI test (sending allowed by the user), at a simulated San Francisco location: Share My Live Location For 15 Minutes sent the location; the chat showed the live location panel (you), the chat list its panel (sharing with BetterTG test), and the bubble the map, "updated just now" and the ring at 14. Location viewer `5a33102c`/`fbe12ab1`/`8b9b8bcd` (cherry-picked from `codex/parity-location-viewer`, LocationViewController/LocationViewControllerNode): tapping a location, venue or live location bubble, the chat's live location panel or the chat list panel opens Telegram's viewer instead of Apple Maps: venue icon or pin, title, address, distance or "you are here", driving/walking times or Get Directions, Open In with the installed map apps and Share, map type and tracking buttons; a live location lists the chat's active live locations (searchChatRecentLocationMessages plus updates) as avatar pins and rows with the time left, Show All, Share My Live Location, Extend (`editMessageLiveLocation`) and Stop. `7c918859` fixes its timer warning; `aac394ee` makes the classic chrome run UIAction bar items (Share and Show All did nothing) and turns the empty system Close items of the viewer, translation and contact details into Close. Xcode MCP 10-16 with `-ui-probe-location-viewer` (`53619ddc`) at a simulated San Francisco location: venue pin, "750 Howard St • 0.4 miles away", Get Directions opens Apple Maps (no other maps app), the map type menu switches to hybrid, Share opens Open In (Maps, Share, Cancel), Close dismisses; the plain location shows its distance but no address: MKReverseGeocodingRequest fails with GEOError -15 in the Simulator and on the host Mac, and Telegram's compactDisplayAddress then gives an empty address too. Xcode MCP 10-17 with that live location: the viewer listed Sharing Location… (tap to add time, ring 14) and Stop Sharing Location (updated 1 minute ago); tap to add time asked "for how long do you want to extend" and 1 hour turned the ring into 1h with "updated just now"; the chat list panel's close offered Stop Sharing Location, which removed the panel, and the bubble then read "Live location ended" without the ring. Not tested: other people's live rows (nobody else shares in UI test), travel times (MapKit gives none in the Simulator). Proximity alerts `2be5b5d7`/`ee28643b` (cherry-picked from `codex/parity-proximity`, LocationDistancePickerScreen): the viewer's bell on a live location sets or clears the alert radius (`setProximityAlertRadius` through the live location edit) with the radius circle on the map, asks to share a live location first, and confirms with Telegram's toasts. Xcode MCP 10-17 with the live location: the bell opened Proximity Alert with the radius circle on the map, Notify Me Within 0.3 mi showed "proximity alert set, we will notify you once any group member is within 0.3 mi from you" for about 6 s (`/tmp/prox2.mp4`) and switched the bell; tapping it again showed "proximity alert canceled" (`/tmp/prox.mp4`). Not tested: an alert firing (needs a second member nearby). Limit: updates only in the foreground (When In Use, TDLib clients close in the background). Poll custom emoji and media `171f4504`/`306d1515`/`0ce2aecb`: questions, answers and explanations draw custom emoji, the creator takes custom emoji in the question and answers, and polls show TDLib 1.8.68 media as Telegram does: answers get 40 pt thumbnails with 10 pt corners (ChatMessagePollOptionNode), the poll's own media sits above the question (attachedMedia), the quiz solution shows its media under the explanation, and taps follow openPollMedia. Xcode MCP 10-16 with the `-ui-probe-message-content` poll-media quiz (`361e84dd`): the proof passes with three polls, the question and first answer end with the account's custom emoji, the place sits above the question and both answers reserve their thumbnails; the map snapshots stayed gray placeholders in the probe (cause not checked). Poll creator media `5cb168fc`..`a0038a52` (cherry-picked from `codex/parity-poll-attach`; ComposePollScreen, PollAttachmentScreen, ListComposePollOptionComponent): the description row, each option with text and the quiz explanation get an attach button that the media's 40 pt thumbnail replaces; the attachment sheet opens on the gallery with one item and the poll's subtitle, with File, Location ("Add This Location", no live location), Sticker alone and Link; tapping attached media offers Replace and Delete, picks become `inputPollMedia` (photo, video, GIF, sticker, location, venue, document, audio, link), and discarding removes picked files. Xcode MCP 10-16 with `-ui-probe-poll-attach`: the POLL and 1 thumbnails showed on the description and the first option; the poll's Delete brought back the paperclip; the option's Replace opened the sheet with gallery, sticker, location and link (description: gallery, file, location), Sticker read "add sticker to this option" and a tapped sticker replaced the option's thumbnail; Cancel then asked "discard poll?" and Yes closed with nothing sent. Xcode MCP 10-17 with full photo access granted (allowed by the user): the description's Replace asked iOS for photo access, Allow Full Access opened the sheet's gallery (recents, "add media to the poll description", the Simulator's 2 videos with 0:12 badges and 6 photos), and a tapped photo replaced the POLL thumbnail with its own; Cancel → discard poll? → yes closed with nothing sent. Xcode MCP 10-17 in UI test (sending allowed by the user): a poll with a gallery photo on its description went out with the photo over the question; a poll whose first option had the link https://telegram.org (Add Link, Done) went out with the link's thumbnail beside "telegram". Input suggestions `e975e801` (ChatInterfaceStateContextQueries' hashtag, emojiSearch and emoji queries; HashtagChatInputContextPanelNode, EmojisChatInputContextPanelNode, InlineReactionSearchPanel): "#word" lists recently used hashtags (searchHashtags) with swipe-to-Delete, and a public chat adds "Use #tag" with the hashtag badge and "Use #tag@username" with the chat's photo from four characters; ":word" shows the emoji bubble with its arrow at the caret (getKeywordEmojis for one letter, then searchEmojis in the keyboard language and English); a lone emoji shows the sticker grid (getStickers), a tap sends and clears the input, a long press opens Send Silently, Add to/Remove from Favorites and View Pack; editing keeps hashtags, mentions and emoji. Xcode MCP 10-16: in the test group ":smi" showed the bubble over the caret and picking 😀, 😃, 😅 or 😄 replaced the keyword; 😄 and 😃 then showed stickers; in Swiftgram Chat "#swift" showed "use #swift" (accent badge) and "use #swift@swiftgramchat" (the group's photo), and picking the second put it into the input; the composer was cleared, nothing was sent. The private group listed no hashtags because TDLib learns them only from sent messages. Xcode MCP 10-17 in UI test: after sending "#bettertgtest hashtag probe", "#bet" listed #bettertgtest, a left swipe revealed Delete and Delete removed it; "😄" showed the stickers and a tap sent the minion sticker and cleared the input. The suggested sticker menu gains Schedule Message after Send Silently `49f2a8d8` (InlineReactionSearchPanel): it opens the schedule picker (a reminder in Saved Messages, Send When Online where allowed), and the sticker goes out at the picked time. Xcode MCP 10-17 (allowed by the user): holding the first suggested sticker for 😄 in the test group opened the peek, sliding to the second switched it, and holding on opened Send Without Sound, Schedule Message, Add to Favorites and View Sticker Set; Schedule Message opened the picker ("send today at 15:15") and Cancel closed it; the composer was cleared, nothing was sent. The emoji and sticker panel replaces the keyboard `98d31335` (Telegram's `.media` input mode, ChatEntityKeyboardInputNode, textInputAccessoryItems): a composer button before the reply keyboard button shows stickers, emoji (while text is present) or the keyboard; the panel is a UIInputViewController at keyboard height with the emoji, custom emoji, sticker and GIF tabs; emoji insert at the caret, a backspace key deletes there and a globe key returns to the system keyboard, both only on the emoji tabs; stickers and GIFs send while the panel stays up; the search field opens the full-height "Emoji and Stickers" sheet with the keyboard and returns to the panel on Done; the attachment sheet's Sticker tab and the edit mode's Emoji item open the panel; the scheduled and reply keyboard buttons hide while it is up. Xcode MCP 10-17 in the test group with nothing sent: the stickers button opened the panel on the favorites at keyboard height and turned into the keyboard button; the emoji tab showed the globe and backspace keys; emoji went in at the caret and backspace removed exactly one; the globe and the keyboard button brought back the system keyboard; search opened the sheet with trending packs, Done returned the panel, and a tap in the history closed it. Xcode MCP 10-17 in UI test: a sticker and a GIF sent from the panel with the panel staying up; editing a message, the attach button morphed into a menu with only Emoji (keyboard up), which opened the panel with only the emoji and Custom Emoji tabs, as ChatEntityKeyboardInputNode drops stickers and GIFs while editing; an emoji went in and the edit saved ("edited"). Poll media and the poll creator still use the sheet. Poll attachment tails `66ec2167`..`036d86b9`, fix `6a014ad5` (cherry-picked from `codex/parity-poll-attach-tails`; PollAttachmentScreen, AttachmentController's switchToController and animateSwitchTransition, AttachmentFileController, ComposePollScreen, ListComposePollOptionComponent, RadialProgressContentNode, ChatTextLinkEditController, AlertWebpagePreviewComponent, MediaPlaybackHeaderPanelComponent): the poll's media sheet stays open while Gallery, File and Location swap its content with the 0.23 s snapshot fade and 10 pt dip; the File tab lists Select from Gallery, Select from Files and RECENTLY SENT FILES (`searchOutgoingDocumentMessages`); media uploads before the poll is sent (`preliminaryUploadFile`) under a radial ring whose tap removes it, and Send waits with a toast; the link editor shows the page's preview (`getLinkPreview`); Replace and Delete show the media above the menu; a poll's audio gets the playback header with its link back to the message. Xcode MCP 10-17 with `-ui-probe-poll-attach`: the Link option's editor previewed telegram.org ("Telegram – a new era of messaging"); the sticker option opened its peek with Replace and Delete, the photo option its photo above them. `upload`: the ring stopped at 90 %, Send showed "please wait / poll media is still uploading…", and a tap on the ring removed the photo. `tabs`: Gallery, File and Location switched in one sheet and back; the File tab first drew its panel squeezed to the left over the rows because the list was a table view controller, fixed in `6a014ad5` and rechecked full width; Location asked for permission (Allow Once) and showed the map with Add This Location. Nothing was sent. Not ported, as in Telegram: Camera and Audio buttons (ComposePollScreen offers gallery, file and location for the description and gallery, sticker, location and link for options; audio is only for rich text). Recent files search `41bae1d9` (AttachmentFileSearchItem): past ten recent files the header shows Search sent files; the query runs `searchOutgoingDocumentMessages` after 0.6 s, YOUR CHATS shows three files and Show More past four, No Results describes the query, and the attachment panel hides while searching. Xcode MCP 10-17 in the description's File tab of a new poll in UI test: "receipt" listed receipt_info.pdf and two Receipt PDFs with Show More, which listed the rest; "receiptzzqx" showed No Results with the query; the close button brought back the list and the panel; a found PDF attached to the description (the poll was discarded). Deviation: the list is empty while a query runs where Telegram shows placeholder rows. Not ported: multiple selection, since PollAttachmentScreen keeps `mediaReferences.first!` and Telegram's Select adds nothing to a poll. Limits: a failed upload falls back to the local file; the link preview is plain text; a video in the menu shows a frame; the audio header needs a real poll with audio. Sticker peek `6ab8691b`/`e01cce02`/`7b4df7a0` (cherry-picked from `codex/parity-sticker-peek`; PeekController with StickerPreviewPeekContent, ChatEntityKeyboardInputNode, InlineReactionSearchPanel): holding a sticker in the panel, the sheet or the suggestions opens the preview over a blurred dim, sliding over other stickers switches it, holding on opens the menu (Send Without Sound, Schedule Message, Add to or Remove from Favorites, View Sticker Set, Remove from Recents in Recently Used), sliding onto a row and lifting picks it, a short hold closes on lift, and a tap on the dim closes the open menu. Xcode MCP 10-17 with `-ui-probe-sticker-peek` (12 generated stickers): a hold on 😀 opened it, sliding went to 👍, 🔥, 👍, ❤️ and 🎉, the menu opened for 🎉 and stayed after the lift; a dim tap closed it; a short hold on ❤️ closed on lift; holding 🎉 into the menu and sliding onto Remove from Recents logged `chose` and `removeFromRecent`. Not covered: custom emoji and GIF peek, premium stickers, Edit Sticker. Poll media gallery `785cb4de` (GalleryController's pollOption entries, galleryMessageCaptionText, ChatItemGalleryFooterContentNode): an answer's photo, video or GIF opens a standalone gallery that pages through every answer with visual media, captioned with the answer; the poll's own media is captioned with its description and the solution's with the explanation; pages keep the poll message's identity, so share and save resolve the page from the fresh poll, while forward and delete stay hidden as in Telegram; deleting the poll closes the gallery. Xcode MCP 10-17 with `-ui-probe-poll-gallery` (a fake quiz: two photo answers, a place, an empty answer, poll and explanation photos): the probe passed (two answer pages, captions, selection, fresh-poll resolution); the gallery opened on "2 of 2" with "Second answer", Share and no Delete; More offered only Save Image (not tapped); a swipe gave "1 of 2" with "First answer"; a pinch zoomed the photo; Share on the fake message showed Couldn't Share Media, as expected without a real file. Real poll `8fd54395`: Save Image and Share on a sent poll's photo said "Couldn't Save Media, Telegram doesn't allow this media to be exported", because the export check built its asset from the poll message itself; it now takes the gallery page's asset. Xcode MCP 10-17 after the fix: Save Image wrote the photo to Photos (PhotoKit insert, success) and Share opened the share sheet with a 417 KB JPEG. Contact selection `3ddded31` (cherry-picked from `codex/parity-contacts`, ContactSelectionController/ContactListNode): Telegram contacts with presence under letters, then phonebook-only people, the access rows, searchContacts plus phonebook prefix search, checkmarks with the Send count panel; several people go without vCards, one card opens DeviceContactInfo's field filter (`DeviceContactFieldsViewController`). Pasted and camera images take up to 100 (`11c2dd34`). Xcode MCP 10-16 without phonebook access: letters, presence, access rows, two checks show Send 2, a name search finds and unchecks, Cancel closes with nothing sent. Not tested: phonebook rows and the field filter (no access granted), sending. Contacts `b03f1a3d`..`668a025c` (cherry-picked from `codex/parity-poll-attach-tails`; DeviceContactData's parseAppSpecificContactReference, ContactListNode's existingNormalizedPhoneNumbers and existingPeerIds, PhoneNumberFormat): a phonebook card with a Telegram link (`https://t.me/@id<ID>`) counts as that contact, and cards sharing a number or user with a listed contact drop out of the list and search; phone numbers take the server's country masks (`getPhoneNumberInfoSync`) in the vCard field filter and in a received contact's details. Xcode MCP 10-17 with `-ui-probe-contact-format`: +79991234567 became +7 999 123 4567, +442071234567 +44 2071 234567, 14155550123 +1 415 555 0123; the Ada Lovelace details showed +7 999 123 4567 under the name and +44 2071 234567 in the Phone row. Not ported, as in Telegram: the contact note (Telegram passes an empty note; `CNContactNoteKey` needs an Apple entitlement) and global search in the contact picker (ContactSelectionControllerNode uses cloud and device contacts only). Limits: a number without a server mask stays as typed. Contact bubble `7b2c0ed0` (ChatMessageContactBubbleContentNode): the bubble reads the vCard (`CNContactVCardSerialization`) and lists phones, then emails, then the organization, five lines at most, phones in the server's masks; Xcode MCP 10-17: a contact sent to UI test shows the number in the server's mask. Panel width `68448bc5`: the emoji and sticker panel is an `UIInputView` sized to the window; its fixed 320 pt frame had squeezed it to 320 of 402 pt (Xcode MCP: 402 pt). Swiped tabs `10c9d019`/`f6a4213d` (EntityKeyboardComponent's paged content, EntityKeyboardBottomPanelComponent): the emoji, custom emoji, sticker and GIF pages swipe in a `UIPageViewController` under the chat list's Liquid Glass folder capsule, whose lens follows the finger; a tap switches and a second tap scrolls to the top; the globe and backspace stand beside the capsule on the emoji tabs, and the tabs give up padding until they fit between them (the chat list's folders still scroll); in the search sheet the capsule sits above the keyboard. Xcode MCP 10-17 in UI test: a swipe from stickers to GIFs with the lens following (60 fps `/tmp/pager-swipe.mp4`), tabs of 58, 114, 75 and 49 pt between x 53 and 349 with the keys at 6 and 356 pt (they had scrolled and clipped 'emoji'), Custom Emoji shows the keys, the search sheet keeps the tabs above the keyboard and Done returns the panel |
| MD-12 | P3 | System PHPicker instead of Telegram's attach sheet grid | fixed `b77b38b1`/`581edc01`/`5edc57f1`/`22d015f5`: the attach button opens Telegram's attachment sheet (AttachmentController) with Gallery, File, Location, Poll, Contact and Sticker tabs; Gallery is MediaPickerScreen's grid on PHCachingImageManager (camera tile, albums, up to 100 numbered picks, selected-only view, limited-access banner and denied placeholder, discard confirmation), loading picks four at a time. Xcode MCP 10-16: the sheet and its tabs open, the photo permission prompt appears, Don't Allow shows the placeholder with Go to Settings, Poll and Location open from their tabs. Xcode MCP 10-17 with full photo access (granted at the user's go-ahead) in BetterTG test / UI test: the grid showed the camera tile over two rows, two 0:12 videos and the photos; tapping two circles numbered them 1 and 2 with "2 selected" and Send 2 under the SD quality button, unchecking renumbered to 1, and Cancel asked "cancel selection?" and yes closed with nothing sent. No full-screen preview; the camera tile opens the existing camera |
| MD-13 | P3 | Picks over 10 are dropped | fixed `94e9ede5`: the gallery picks up to 100 items and sends them in albums of 10; files are uncapped. Build only: nothing was sent. Pasted and camera images keep the 10 cap |
| MD-14 | P3 | No View Once timer, video quality, Send in HD or editor | fixed `b77b38b1`/`581edc01`: the sheet's menu offers Send in High Quality (2560 px), View Once in private chats (`messageSelfDestructTypeImmediately`, which turns scheduling off), spoiler, grouping and caption position, and remembers the HD switch. Build only. Timers and video quality `4646390e`: the More menu's Send With Timer (LegacyMessageInputPanel's presentTimeoutSetup) offers View Once, 3, 10 or 30 seconds (`messageSelfDestructTypeTimer`) and Do Not Delete with the tooltips; picked videos get TGPhotoQualityController's 240p-1080p presets capped by their size, defaulting to the server's auto-download preset for the network (`videoUploadBitrate`), and the transcoder takes the preset's size, bitrates, channels and frame rate. Build only: the menus need picked items, and full library access was not granted. Photo crop `06da6bc0`/`81dc90c7` (cherry-picked from `codex/parity-photo-crop`, TGPhotoCropController/TGPhotoCropView): holding a grid photo offers Edit, which opens the crop editor (pan and zoom to 10x with rubber banding, eight handles, 90 degree turns, mirror, the straightening dial to 45 degrees, Original, Square and six ratios along the longer side, RESET, Cancel with Discard Changes); the crop picks the photo, shows in its cell and is rendered from the full photo at the send size. Xcode MCP 10-16 with `-ui-probe-photo-crop` (`b7dd7879`) on a drawn 1600x1200 photo: a turn and a mirror flip the content as Telegram's content mirror does, the ratio menu lists 2:3 to 9:16 for the turned photo, 3:4 locks the frame while a handle drags it, the dial reads 22 degrees and the photo zooms to cover the frame, Cancel asks Discard Changes, RESET restores the photo, Done gives 883x1178 for the 3:4 crop and the whole 1600x1200 photo untouched. Re-check 10-17 with full library access in UI test (allowed by the user): holding a grid photo offered Edit, which opened Crop; Rotate and Mirror, Done picked the photo with its turned thumbnail, and the sent photo is the turned, mirrored portrait (23:06). Video trim and mute `623ba43f`/`70b7137e` (cherry-picked from `codex/parity-video-edit`, TGMediaPickerGalleryVideoScrubber/TrimView, TGVideoEditAdjustments, TGMediaVideoConverter): holding a grid video offers Edit, which opens the player with the frame scrubber (handles, at least 1 s, no trim under 1.5 s, slow motion only mutes), Mute with its toast and Cancel with Discard Changes; the edit picks the video, rides in the TDLib conversion string (`;trim=a-b;gif`), the transcoder reads only the trimmed range and a muted video goes out as `inputMessageAnimation` at the Animation preset, ungrouping the selection as TGMediaAssetsController does. Xcode MCP 10-16 with `-ui-probe-video-edit` (`97e9e3a5`, stall fixed in `43273251`) on a generated 6 s 1280x720 video with a tone: dragging the handles to 0:00.9 and 0:05.1 and Mute gave `trim 0.90–5.10 s, muted: sent as a GIF, bettertg-video-medium-v1;trim=0.895-5.099;gif` and the transcoder wrote 4.23 s at 848x464 with no sound. Re-check 10-17 in UI test: holding a grid video offered Edit, the end handle cut the last quarter, Mute and Done picked it, and the sent video arrived (22:56). Photo tools `07f867ee`/`3bb7390f`/`7868466e`/`b0d54026` (cherry-picked from `codex/parity-photo-tools`, TGPhotoToolsController and the PG*Tool renderers on Metal): the editor's Crop and Tools tabs; Enhance, Brightness, Contrast, Saturation, Warmth, Fade, Highlights, Shadows, Vignette, Grain and Sharpen sliders with PGPhotoTool's values, Tint with shadow and highlight swatches, Curves with All, Red, Green and Blue; a live preview, double tap to reset, the value HUD, holding the photo shows the original, Discard Changes on Cancel; the photo goes out rendered at 2560 px and scaled to the send size. Xcode MCP 10-16 with `-ui-probe-photo-tools`: Enhance reads +0.71 and Contrast +0.82 as the preview changes, a Curves drag lifts the shadows, a blue shadow tint colors the gradient, Done gives "edited 1280×960" with every change. Re-check 10-17 in UI test: grid Edit, Tools, brightness +1.00 and saturation +0.61 brightened the preview, Done and Send delivered the brighter photo (23:10). Blur and the Curves histogram `94ecc490`..`454e3d8f` (cherry-picked from `codex/parity-photo-blur`; PGBlurTool, PGPhotoBlurPass, PGPhotoGaussianBlurFilter, TGPhotoEditorRadialBlurView, TGPhotoEditorLinearBlurView, PGPhotoHistogramGenerator, TGHistogramView): a Tilt Shift tab between Tint and Curves with Off, Radial and Linear, Telegram's two-pass Gaussian and focus masks after Enhance and Sharpen in the Metal chain, on-photo controls (drag the centre, drag the ring or lines for falloff and size, pinch, rotate Linear outside its band), and the luminance and channel histogram under Curves. Xcode MCP 10-16 with `-ui-probe-photo-tools blur`: Radial kept a sharp circle around its centre and a drag moved it from TL onto TR, which turned sharp; Linear kept a sharp horizontal band through TL and TR with dashed edges and blurred BL and BR; Curves showed the histogram's spikes under all, red, green and blue; Done returned "edited 1280×960" with the Linear blur applied. The Crop tab shows the original photo as Telegram does. Video crop and scrubber zoom `f3067470`..`9e9ba7a8` (cherry-picked from `codex/parity-video-crop`; TGPhotoCropController forVideo, TGPhotoAvatarPreviewController, TGMediaPickerGalleryVideoScrubber's zoom): the video editor gets Video and Crop tabs; Crop turns by quarters without the dial, with handles, pan and pinch, Rotate, Mirror, the photo's aspect ratio sheet and RESET over the looping video, which pauses while the crop moves; the crop rides in the conversion string (`;crop=…;turn=…;mirror`), the transcoder applies it through AVMutableVideoComposition and the scrubber's frames show the cropped shape; holding a trim handle or the playhead still for 0.25 s zooms the strip about it with exact frames, and lifting zooms back out. Xcode MCP 10-16 with `-ui-probe-video-edit crop` (`a3b54d3c`): Rotate and Mirror turned and flipped the playing video, the ratio sheet listed original to 9:16, 3:4 locked the frame, a corner drag and a pinch zoomed in, Done gave `crop 319,236 484×363 of 1280×720, turned left, mirrored` and the transcoder wrote 6.00 s at 352×480 with sound; with `-ui-probe-video-edit` a held start handle zoomed the strip into the frames from 1.0 to 1.67 s (a simctl recording) and returned after the lift. Xcode MCP's device interaction timed out with "main thread did not execute" whenever `activationBundleId` was passed; without it every step ran. The grid's Edit menu and sending: re-checked 10-17 in UI test (below). AUTO straightening `fa363ea8` (cherry-picked from `codex/parity-crop-auto`; TGPhotoCropController's RESET/AUTO button): Telegram reads the angle from the phone's tilt when its own camera took the photo (PGCameraShotMetadata.deviceAngle), which current Telegram no longer passes; BetterTG's photos come through the system picker, so Vision's VNDetectHorizonRequest gives the angle. AUTO shows while the whole photo is in the frame with no locked ratio and an angle from 5° to under 45°, springs the dial to it and turns into RESET, which restores the whole photo; touching the photo, frame or dial hides it, and the editor waits for the spring before Done, Cancel or a tab switch. Edited video grid thumbnails `831d4cbc` (TGMediaEditingContext, MediaPickerGridItem): a video with a crop or a moved trim start shows the frame at the trim start, cut, turned and mirrored like a cropped photo's cell; Telegram's own thumbnail leaves the crop out. Xcode MCP 10-17 with `-ui-probe-photo-crop auto`: Vision found 8.00° on the tilted sea horizon, AUTO levelled it with the dial near 8 and became RESET, RESET restored the tilt and AUTO, and a drag in the dial area put RESET back in AUTO's place. `-ui-probe-video-edit crop` after Rotate and Mirror: the grid thumbnail is 255×455, turned left and mirrored, converted 6.00 s at 464×848 with sound. Video cover `2648a382`/`9cecb2f1`/`b7d37a5a` (cherry-picked from `codex/parity-video-cover`; MediaEditorScreen's cover editing, VideoScrubberComponent's cover position, `InputVideo.cover`): in broadcast channels and Saved Messages a video of 60 s or longer gets Edit Cover in the editor; it opens Select Frame with a scrubber over the video's frames, Save Cover puts the frame's thumbnail on the button, and the picked frame is written as a JPEG and sent as the video's `cover`. The cover follows the video's crop; Telegram leaves the crop out. Xcode MCP 10-17 with `-ui-probe-video-edit cover` (64 s video): Edit Cover opened Select Frame, a drag moved the handle to the "40" frame, Save Cover put that thumbnail on the button, and Done wrote the cover at 39.31 s, 1280×720, 32 KB, converted 64.00 s at 848×464 with sound. The landscape toolbar does not apply: BetterTG's iPhone app is portrait only, and Telegram keeps the editor portrait on iPad. Live Photo crop `9e61629a`/`1e846351`/`a9a43705`, fix `0407e042` (cherry-picked from `codex/parity-live-photo`; TGMediaAssetsController's Live Photo modes, TGMediaAssetsPatchedLivePhotoAdjustments, MediaEditorValues cropRotation, LivePhotoButton): an edited Live Photo keeps its motion, converted at Medium with sound under the still's crop, quarter turns, mirroring and straightening (the conversion string gains `rot=`); as in Telegram, Live Photos go as stills by default, a bar button toggles all of them with Telegram's tooltip, each item's long-press menu offers Live or Live Off, and the grid badge shows the mode it will be sent with. Xcode MCP 10-17 with `-ui-probe-photo-crop live` (a generated 6 s 1280×720 motion with a tone, its first frame as a 1920×1080 still): straightened, mirrored and turned left, Done showed the still at 720×1280 above the converted motion's first frame with the same crop, turn, mirror and 8.12° tilt, the conversion string, and a 6.00 s 464×848 motion with sound; nothing was sent. Xcode MCP 10-18 with a generated Live Photo in the Simulator's library (a 720×960 still and a 3 s motion paired by content identifier, `simctl addmedia`): the grid cell read "live photo, off" with the slashed badge; picking it put the Live button left of More, which turned the badge on; holding the cell offered Edit and Live, whose submenu's Live Off and Live set the photo's own mode; sent to UI test in Live mode it arrived as "live photo" with the badge and Save Live Photo in its menu, and the gallery played the motion (`/tmp/live-open.mp4`). Not ported: Loop and Bounce (Telegram's gallery preview and GIF export), photo tools on the motion (Telegram's frame pipeline). Cover from the gallery `ce6d3df4` (TGMediaPickerGalleryInterfaceView's `_coverGalleryButton`, ChatControllerOpenAttachmentMenu's `editCover`, MediaEditorScreen's `coverEditor` and `requestCoverCompletion`): while the cover is chosen, Choose From Gallery sits above Save Cover and opens the system photo picker (no library access needed); the photo opens in the photo editor locked to the video's shape, filling it first, with Reset keeping the shape and only Mirror in the crop toolbar, plus the tools; Done writes it fitted into 1080 × 1080 as the cover without a position, shown in the Edit Cover pill, and a later Save Cover from a frame replaces it. Xcode MCP 10-17 with `-ui-probe-video-edit cover`: Choose From Gallery opened the picker, the waterfall photo opened in a 16:9 crop with Mirror only, a pinch and a straightening turn applied, Done put the cover's circle into the pill, and the editor's Done wrote "cover from the gallery", a 1280×719 189 KB cover file showing the zoomed waterfall, and converted 64.00 s at 848×464 with sound; nothing was sent. The cover is written at 1080 px, then upscaled to 1280 by LegacyMediaPickers' fitting, as Telegram does. Soften Skin `9ef3bc57` (PGSkinTool, PGPhotoSkinPass, YUGPUImageHighPassSkinSmoothingFilter, TGPhotoToolsController's `requiresFaces`, TGPaintFaceDetector): a face found as the editor opens (Core Image's accurate detector, faces from 17.5% of the photo with both eyes) puts Soften Skin at the top of the tools list; the Metal chain runs it before Enhance as the high pass of the green and blue overlay boosted into a mask, GPUImageToneCurveFilter's spline through (0.47, 0.57) dissolved in at 0.75 of the value outside the mask, then a sharpen at 0.4 of that; video has no Soften Skin, as in Telegram. Xcode MCP 10-17 with `-ui-probe-photo-tools skin` on a generated portrait: Soften Skin led the list above Enhance, a drag set +1.00 and the preview lightened the skin, Done gave edited 960×1280 with fewer pores on the cheeks (the cheeks' dark detail fell from 2.219 to 1.837 while the sharpen raised the whole photo's neighbor difference from 3.483 to 4.638); on the drawn photo without a face the list starts at Enhance. Portrait blur does not apply: TGPhotoEditorBlurToolView comments its button out. Drawing `d5f26be7`..`a7b1d7b9`, probe fix `97d944c8` (cherry-picked from `codex/parity-drawing`; DrawingUI's DrawingScreen, DrawingView, the pen, arrow, marker, neon, blur and eraser tools, ColorPickerScreen, EyedropperView, the text, simple shape, bubble and vector entities, TGPhotoDrawingController, and TGMediaVideoConverter's painting overlay): the photo editor gets a Paint tab between Crop and Tools with the six brushes, a size slider, swatches, the color picker (grid, spectrum, sliders, hex, saved colors) and the eyedropper, Undo, Redo, fill on a long press, Clear All with a confirmation, Draw and Text modes, and the Add menu with rectangle, ellipse, bubble, star and arrow; entities move, pinch, rotate, duplicate, delete and come forward, the painting is kept with the edit, reopens editable and is drawn into the result at full size. The video editor gets Video, Crop and Paint (no Blur); the painting is written as a PNG named in the conversion string (`paint=<uuid>.png`), and the transcoder draws it into every frame after the crop. Xcode MCP 10-17 with `-ui-probe-photo-draw auto` (a 1600×1200 photo with two strokes, text, a star and an arrow): the drawing reopened editable; a neon stroke drew with a glow and Undo removed it, Redo appeared; Add listed the five shapes and a bubble went in; text mode typed "Привет" in the framed style with the font and alignment buttons; a drag resized the bubble with its handles; Done gave "edited 1600×1200 with 5 entities and strokes" and the send path wrote a 1280×960 JPEG with the painting (`Documents/photo-probe-draw.png`). `-ui-probe-video-edit paint`: a purple neon stroke over the playing video stayed on the Video tab, and Done converted 6.00 s at 848×464 with sound, with the stroke in the output frame at 0.5 s (`Documents/video-probe-draw.png`). Nothing was sent. Not ported: Unistroke shape recognition (Telegram comments it out in DrawingView), sticker entities, text animations, Apple Pencil and canvas zoom, snapping and the delete bin; the Metal marker is approximated in Core Graphics and the font picker is a UIMenu; a cover picked with Edit Cover goes without the painting |
| MD-15 | P3 | Music has no lock-screen next/previous or expanded player | partly fixed `14e2e6f8`: music enables lock-screen next/previous (previous restarts after 5 s, as SharedMediaPlayer does) with title, performer, duration, rate and album art (embedded cover, TDLib album covers, thumbnail). Build only: no music message to play. Expanded player `03706589`/`0f285f8e` (OverlayAudioPlayerController): tapping the music header opens a sheet with the chat's tracks (searchChatMessages audio filter, paged both ways), album art, scrubber with fine scrubbing for tracks over ten minutes, previous/play/next, order and repeat (saved like MusicPlaybackSettings), and the rate button for long tracks only. Xcode MCP 10-16 with `-ui-probe-music-player` (`fecd92da`): the sheet shows title, performer, elapsed/remaining time, play/pause toggles, the rate button appears only with `-ui-probe-music-player-long`, close leaves the header, stop removes it. Xcode MCP 10-17 on a real group's mp3 (allowed by the user): the header opened the sheet with the chat's track list (the playing track and the ones after it), elapsed and remaining time moving; order cycled In order → Reversed → Shuffle → In order and repeat Off → Current track → All tracks → Off (left at the defaults); Next track switched to the following track with the list's playing mark following; pause and close worked. Xcode MCP 10-17 night: a track or voice message started from the profile's Music or Voice row played without a now-playing item (no header, no lock-screen title or previous/next, the playlist stopped after it); fixed `ac3b017e` (PeerInfoScreen's openChatMessage with the music or voice playlist): a track from the profile showed the header in the chat and played on to the next two tracks, and a voice message named its sender. mediaremoted shows BetterTG as the now-playing app with the track's title, performer and 768 px artwork, NextTrack and PreviousTrack enabled and the 5 s skips disabled for music (the reverse for a voice note). Blocked with the device pass: the iOS 27 Simulator's lock screen and Control Center draw no media platter, and a MediaRemote command from outside needs an entitled client, so pressing the lock screen's previous/next needs a physical iPhone (the handlers call the same playNextTrack/playPreviousTrack as the music player's buttons, verified above) |


### Probe sweep — 2026-10-12

Repeat on the merged build `e05d541` (localization merge): 86 of 91 probes report a pass; `draft-coding` passes in the app's tmp folder, and the four observation probes need live UI as above.

All 91 launch-argument probes ran on iPhone 18 Pro (iOS 27.0) against the merged build through `./build.sh run
--skip-build`, one launch per probe. Probe repairs are in `804fd8d`: probes that borrow the active client wait for the
asynchronous TDLibKit 2 account bootstrap, test entities stay within `Int32`, and probes follow the merged semantic,
localized and forward-picker APIs. After the repairs and F12/F13 every probe that reports by itself passes, including
`vod-resource-loader` (progressive playback before completion, controls, offline retry, no full download) and
`video-note-lifecycle` (about 2 minutes). Four probes only observe live UI and wrote nothing in an unattended launch:
`folder-selector-content`, `profile-header-layout`, `viewport-completion` and `message-navigation`; they are
exercised by hand:

- `viewport-completion` passed in Saved Messages after scrolling away from both edges: the real ChatView kept its
  snapshot IDs, and the held native completion restored the stable-ID pixel offset; a synthetic delegate drag rejected
  the old restoration. Physical gestures, history insertion, media resize and keyboard overlap stay unverified.
- `message-navigation`: tapping a test reply's quote in Saved Messages scrolled to the loaded target with an
  animated scroll and settled 0.2 pt from the command offset with unchanged snapshot IDs, then highlighted the target.
  The test reply was deleted afterwards.
- `profile-header-layout` passed on the Saved Messages profile (labels fill the width, 96 pt avatar). The shared
  media gallery opened from the grid, paged 1 → 3 of 6 and closed with the swipe-down dismissal back to the grid.
- `folder-selector-content`: 815 candidates, 35 empty raw titles (all deleted accounts), no empty cell text and no
  title mismatches after F14. The same check found F16.

### Context-menu gestures — 2026-10-12

Source: `/Users/lev/Developer/CustomContextMenu` (UIKitCore iOS 27.0 24A434): `App/MenuMotion.swift`,
`App/MenuTouchRecognizer.swift`, `App/CustomMenu.swift`, `App/NativeUIKit.swift`, `Tests/InteractionChecks.swift`,
`Research/Interaction/README.md`. Constants are taken from the source, none tuned by eye.

| Area | Port | BetterTG adaptation |
| --- | --- | --- |
| Motion model | `ContextMenuMotion`, `ContextMenuSpring`, `ContextMenuTouchSession` verbatim: press progress and scale, radial rubber band 15 / 0.2, preview offset clamped toward the menu, closed-form spring, release rules | `platterOffset` also clamps for a menu above the preview |
| Press before open | `ContextMenuPressGestureRecognizer` on messages, chat rows, avatars and folder tabs: progress after 0.15 s, 20 pt allowable movement, hold 0.4 s (0.325 s on iPad), growth by 8 pt on the long side and shadow 0.3 / radius 20 on a 0.6 / 0.4 s spring at up to 120 Hz; release 0.85 / 0.35 s; Reduce Motion keeps scale 1 | The effect runs on the source view instead of a pre-presented overlay; `presentTelegramContextMenu` takes the grown view over and restores its base transform. Folder tabs (`.menuOnly`) settle back when the menu opens and cast no shadow (text only). Replaces the Telegram 0.1 / 0.26 s recognizer, the 0.3 s long presses and the 0.98 shrink |
| Open menu touches | One `ContextMenuTouchRecognizer` on the menu root (cancels and delays nothing) plus the opening finger: preview pan after 10 pt with rubber band only while the finger is off the menu and spring back on release; dismissal tap 45 pt / 1.5 s; outside finger hands off to scrubbing; 0.15 s selection delay for touches that begin on the menu; release outcomes A–N | Touches in the reaction strip, in the selectable quote text and in the scrollable chat preview stay with those views. The opening finger still scrubs reactions |
| Native calls | `ContextMenuNativeAnimation`: `UIViewSpringAnimationBehavior` pan behavior (0.15 / 0.996, tracking 0.8 / 0.4 smoothed 0.08, release 0.85 / 0.5) and highlight behaviors, `_animateUsingSpringBehavior:tracking:` inside 48–120 Hz reason 0x100026, each selector-checked with the public `UIView.animate(springDuration:bounce:)` fallback | The menu glass is the system's flexible `_UIViewGlass` set with `_setBackground:` (variant 0, not adaptive, flexible, flex variant 5, no grouping; `_setEnabledWithoutSolarium:` only where iOS 27 has it), whose `_UIFlexInteraction` stretches the glass toward a finger that touches the open menu and drags; public interactive `UIGlassEffect` only without those calls. Before `0cd4967b` iOS 26 lacked `_setEnabledWithoutSolarium:`, fell back to the public glass and never bent, since the menu's rows sit beside that glass |
| Highlight | Shared highlight: frame 1 / 0.12 s, alpha 1 / 0.3 s, appears in place below 0.05 presentation opacity, inset 10 with radius min(menu radius − 10, h / 2), selection haptic on every change | Menu radius 30 keeps the existing 20 pt highlight |
| Escape | Escape key and `accessibilityPerformEscape` dismiss; the dim view is a VoiceOver Close element; focus moves into the menu | The menu root takes focus only when nothing is focused; otherwise the focused view's controller carries the Escape command, so the composer keeps its keyboard |
| Menu look | Unchanged: Telegram spring appearance, reactions strip, quote selection, submenus, keyboard-window hosting | — |

Proofs:

- Deterministic: `-ui-probe-context-menu-interaction` (`ContextMenuInteractionProbe`, DEBUG only) passed on iPhone 18 Pro
  iOS 27.0: 10,201 rubber-band vectors, native pan trace and preview centers, press samples, hold durations, 60/120 Hz
  spring independence and momentum, 12 native release cases, selection delay; private spring behavior available.
- Simulator smoke (iPhone 18 Pro, iOS 27.0, idb): chat-row preview opens on hold and stays open on release (A); outside
  tap dismisses (M); row tap after a preview menu opens the chat (F9); message menu with reactions, tap on copy runs
  copy (N, pasteboard checked); tap on the preview edge dismisses (E); a slow drag from the message onto reply opens the
  menu under the same finger and selects reply (G); Escape with the keyboard up dismisses the menu and keeps the
  keyboard; avatar menu, outside drag over 45 pt (J) and preview move 30 pt (K) keep it open; folder-tab menu, row
  touch dragged off the menu keeps it open (F); folder taps and list scrolling still work.
- Xcode MCP 10-17, one finger with `mt`: on the BetterTG test chat row, the opening finger dragged through archive and
  released outside kept the menu open with nothing chosen (B); dragged above the preview, it kept the menu open (C);
  dragged into archive and back to the preview, it kept it open (D). With the menu open, a touch below the menu dragged
  onto pin pinned the chat (H; unpinned again with a tap); on the chat preview the touch goes to the scrollable topic
  list by design (`touchOrigin` returns nil for `.chatPreview`), so I was checked on a message: a touch on the bubble
  dragged onto copy copied the message (I, pasteboard checked).
- Not proven: preview pan visuals mid-drag; VoiceOver escape (the Simulator doesn't run VoiceOver); 120 Hz and haptics on
  a physical device. iOS 26 runs the same gesture code; its morph is checked under "Liquid morph" below. Device-interaction multi-touch was
  first rejected by automatic approval review under the old AGENTS.md rule; `75872177` allows Xcode MCP, and the next
  section has the multi-touch proofs.

Glass flex, 10-24 (iPhone 17 Pro iOS 26.5 `8108A92F`, headless, agent-device in T3's Device panel, LLDB): before `0cd4967b` the menu's `_UIFlexInteraction` sat on the public fallback `UIVisualEffectView` and a touch on a row dragged out of the menu left the glass still in every frame; after it the interaction sits on the menu view itself and the same drag moves and stretches the glass toward the finger and back, as the system menu and CustomContextMenu's own menu do on iOS 27 (ContextMenuLab on iPhone 18 Pro iOS 27.0, the same drag through idb). As in the system menu (CustomContextMenu trace N1), the finger that opened the menu does not bend it.

### Context-menu gestures through Xcode device interaction — 2026-10-12

Real multi-touch sequences (`mt`) on iPhone 18 Pro iOS 27.0, build after `9d46205`, in Saved Messages:
hold 1.0 s then scrub to Copy and lift ran Copy (pasteboard changed) and closed the menu; lifting the opening finger
in place kept the menu open with nothing highlighted; scrubbing past the 10 pt hysteresis and lifting outside the menu
kept it open and ran nothing; tapping Select entered selection; a chat-row hold scrubbed to Add to Folder opened it;
the gallery More menu grew out of the button and closed back into it, with luminance rising and falling smoothly in a
60 fps recording (F26 noted). Reduce Motion at runtime (10-17, Simulator `com.apple.Accessibility ReduceMotionEnabled`
on, app relaunched, then restored): the story probe reported `reduce-motion=true`; gallery More opened without the morph,
the ••• button stayed visible and the menu grew in below it (60 fps `rm.mp4`); a 1.2 s hold on a chat row only darkened
it, its text at the same pixels until the menu opened (`rmrow.mp4`), where without Reduce Motion the same hold moved the
row's text outward by about 1.5 pt, the 8 pt growth (`row.mp4`). Recordings are in `/tmp/morph-ev`.

### Liquid morph of menu buttons — 2026-10-12

Source: Telegram iOS `telegram-upstream` 58ce7d6688, f44a25a649, 11a469d1f8, 7c2cfd6a1f (read at `7c2cfd6a1f`):
`docs/context-menu-liquid-morph.md`, `submodules/TelegramUI/Components/LensTransition` (`Bridge/Sources/LensTransitionRuntime.m`,
`Bridge/Sources/Identifiers.inc`, `Sources/LiquidMorphTransition.swift`, `Sources/LensTransitionContainer.swift`),
`prototypes/ContextMenuMorph/Tests/LiquidMorphTests.swift`.

| Area | Port |
| --- | --- |
| Runtime adapter | `BTLiquidMorphDriver` (Objective-C, bridging header): Telegram's `LTTransitionDriver` with the same XOR-encoded identifier table. It subclasses UIKit's liquid-morph presentation animation at runtime, overrides the source, pivot, accessory and background hooks, and starts it with `initWithUIController:previousAnimation:` and `performTransition`. Every method it calls or overrides is checked against its full Objective-C signature; an in-flight driver of the same source is passed as `previousAnimation` so UIKit hands the running morph over. No private name appears in plaintext in the built binary (checked with `grep`) |
| Swift wrapper | `ContextMenuLiquidMorph`: preview validation, the 10 × 10 pivot at the attachment point, completion handed back on the next main-queue turn after UIKit's cleanup, `interruptingCurrent` for a close that takes over a running opening, and a 120 Hz display-link claim that ends at completion or after 1 s |
| Menu integration | `TelegramContextMenuPresentationStyle.sourceMorph`: the menu takes the button's place (top on top in the upper half, bottom on bottom in the lower half, left or right edge by screen half, screen clamp). The button morphs into the menu glass, and an alpha-override assertion hides it for the menu's lifetime. A close morphs back into the button's current presentation transform and takes over an opening still running. A second assertion keeps the closed menu hidden through UIKit's cleanup, and the menu alpha drops to 0 before that assertion ends. Without the runtime, with Reduce Motion, or when the button has left the window, the menu opens next to the button with the Telegram spring, and a close after the button left fades at once |
| Close timing | UIKit completes a close after about 1.6 s. The menu stops taking touches when the close starts, and the chosen action runs at 0.7 s (Telegram's recorded end of the visible close motion) instead of after settling. A menu that is still closing does not block the next one: it stays alive in a closing list until its completion |

Per-control decisions:

| Control | Decision |
| --- | --- |
| Gallery More (`ChatViewAlbum.moreButton`) | System `UIMenu` replaced by the custom menu with the morph, so the gallery menu matches the rest of the app |
| Composer attach (`ChatBottomArea.attachmentButton`) | A tap opens Telegram's attachment sheet; while editing a message, the custom menu (Emoji) morphs out of the button. The send button's send options and the attachment sheet's menus also use the morph |
| Video playback rate (`rateButton`) | Not applicable: a tap cycles rates and opens no menu |
| Video quality | Not applicable: the player has no quality control |
| Media preview before sending | Not applicable: no button there opens a menu |
| Record button retry/discard (`actionButton.menu`) | Kept as a system `UIMenu`, which UIKit morphs natively. The same button owns hold-to-record touches |
| Classic navigation bar items with menus | Kept as system `UIMenu`s, morphed by UIKit. Telegram's morph targets glass header capsules, which BetterTG's classic chrome does not use |
| Folders, messages, chat rows, avatars | No morph, by scope |

Proofs:

- Deterministic: `-ui-probe-context-menu-liquid-morph` (`ContextMenuLiquidMorphProbe`, DEBUG only) passed on iPhone 18 Pro
  iOS 27.0 with Telegram's prototype checks: runtime supported, completion with UIView animations disabled and release of
  the native coordinator and context, round trip restoring hierarchy and rejecting a concurrent morph, a close at 0 and
  0.3 s taking over the opening with one completion each, and overlapping visibility assertions keeping the model alpha.
- Simulator smoke (iPhone 18 Pro, iOS 27.0, idb): composer attach menu opens in place of the hidden + button, closes on an
  outside tap without showing the open menu again, and Emoji, Stickers & GIFs opens its panel; gallery More opens in place,
  survives an open-then-close and a reopen during the closing morph, and Open in Chat navigates with no overlay left; the
  message menu is unchanged.
- Found and fixed during smoke: a reopened menu replaced the closing controller as the only strong reference, so the
  old controller deallocated before its close completed and left its overlay on screen. Closing controllers now stay in
  a list until their completion (log trace: the old close completion arrived with a nil owner).
- Morph frames (10-17, 60 fps Xcode MCP recordings of gallery More): the glass grows out of the button over about
  0.23 s and shrinks back on close; the counter stays under the opening glass and shows through the thinning closing
  glass for about 50 ms (F26). Reduce Motion runtime: plain presentation, see the gestures section above.
- Keyboard up (10-17, Xcode MCP in UI test, 60 fps `/tmp/kbmorph.mp4` frames 1464-1478): with the system keyboard
  showing, holding the send button grew Send Without Sound and Schedule Message out of it in about 0.2 s, above the
  keyboard, which stayed in place; while editing, the attach button morphed into its Emoji menu the same way.
- iOS 26 (10-17, iPhone 17 Pro iOS 26.5 Simulator, `-ui-probe-context-menu-liquid-morph`): the probe passed with
  the runtime supported, so iOS 26 morphs as iOS 27 does. An unsupported runtime takes the same
  `usesLiquidMorph == false` branch as Reduce Motion, whose plain presentation is proven above.
- Not proven: 120 Hz on a device.

## BetterTG identity (user decisions)

Telegram is the reference for behavior, gestures, layout logic and edge cases. Appearance follows BetterTG main.

- Full-width blurred navigation and tab bars with safe area; content scrolls under them. One classic Telegram navigation
  bar on every screen, with chat-list/chat sizes and Back button, no Liquid Glass islands, no glass button backgrounds
  and no glass flashes during push/pop.
- Folder picker at the bottom: Liquid Glass with liquid lens and interactive glass (`24657e8`), blur behind it, unread
  counts (`75184a2`). Forward to uses the same picker.
- Context menus: the custom Telegram menu with glass (`TelegramContextMenu`, `24d5b2f`), gestures from
  CustomContextMenu.
- Composer (`d27e495`): square and full width with the safe area when the keyboard is hidden; with the keyboard all
  corners round and 8 pt side insets appear, animated. Non-interactive Liquid Glass. Plus-to-field spacing equals the
  edge spacing, on both sides. With the keyboard, a linear gradient on the Telegram EdgeEffect curve sits behind the
  composer (the inverted list cannot use the system edge effect). The glass outline does not show at the corners or under
  the home indicator.
- Quote comes from text selection inside the open message menu; no separate item. The reaction strip does not slide in
  from the side.
- Topic search starts hidden and collapses before the list scrolls, as in the main list; the same in Forward to.
- Forward to: bottom folder picker, compact rows without last message, search in the navigation bar, no comment field or
  send panel. Tapping a chat opens it with a "Forward message / user: text" block in the composer.
- Regular icons, not glass variants with the background removed.

## Flow status — 2026-10-12

Implementation is the parity-continuation state of 2026-09-06; astra audit is the 2026-10-03 area state (details in
Appendix A). Post-merge audit is `pending` for every row until revalidated on `codex/parity`.

| Priority | Flow | Implementation (09-06) | Astra audit (10-03) | Post-merge |
| --- | --- | --- | --- | --- |
| P0 | Remove MobileVLCKit; local audio/video playback | partial | reviewed, A01–A04/A18/A19 repairs | pending; no VLC marker |
| P0 | TGS stickers, animated/custom emoji | partial | reviewed, A05–A09 repairs | pending |
| P0 | Animated WebP | partial | reviewed with animated media | pending |
| P0 | WebM/VP9 alpha and FFmpeg playback | partial | reviewed with animated media and VOD | pending |
| P0 | Voice notes | implemented breadth | reviewed, A11–A17/A26 repairs | pending; record/send/play smoke |
| P0 | Video notes | implemented multi-segment breadth | reviewed, A11–A17/A26 repairs | pending; recorder smoke only, no camera |
| P0 | VOD, range seek/refetch, PiP | partial | reviewed, A01–A04/A18/A19 repairs | pending |
| P0 | Exhaustive message content and actions | partial | reviewed, A10/A20/A31/A43–A48 repairs | pending; TDLib 1.8.68 TON cases fall back |
| P0 | Message reactions | implemented breadth | reviewed with content/actions | pending |
| P0 | Pinned messages | implemented ordinary-chat breadth | reviewed with content/actions | F19 fixed (Telegram menu flow, Saved Messages); probe + Simulator smoke |
| P0 | Forum topics | partial | reviewed, A23c/A42/A45 repairs | pending; list/topic smoke |
| P0 | Topic composer durable media identity | implemented write foundation | reviewed with composer | pending |
| P0 | Forum-aware Forward destinations | implemented breadth | reviewed with content/actions | pending; F1 fixed |
| P0 | Composer and send/delete transitions | partial | reviewed, A22/A24/A25/A49 repairs | Simulator 10-12: draft kept across back and relaunch, send, edit (F11 fixed), reply, two-message delete; transitions not frame-checked |
| P1 | Profiles, shared media, gallery | partial | reviewed, A20b/A27/A28 repairs | Simulator 10-12: Saved Messages profile header probe, grid → gallery, paging, swipe-down dismissal; other peer types pending |
| P1 | Multiple accounts | implemented | partial (A23/A30) | pending |
| P1 | Chats, folders, archive, search, edit/reorder | partial | reviewed, list/mutation repairs | F14/F16 fixed; folder-flow and folder-selector probes; mutations pending; store-based list kept |
| P1 | Timeline stability and performance | partial | reviewed, A22/A39/A49 repairs | viewport-completion and message-navigation on the real ChatView; F22 snapshot reuse by revision; prepend/media resize/keyboard pending |
| P2 | Shell/navigation polish | implemented shell/list breadth | A32/A37 unresolved | pending |
| P0 | Context-menu gestures from CustomContextMenu | ported 10-12 for all sources | — | probe + Simulator smoke; F9 fixed |
| P1 | Liquid morph of menu buttons | ported 10-12 (gallery More, composer attach) | — | probe + Simulator smoke |

## Appendix A — astra revalidation ledger

Verbatim ledger of `codex/a21e-previous-worker` at `0f0b479` (2026-10-02…03), headings demoted one level. File and line
references point into that branch. Its implementation ledger and historical slices repeat the `7b0699d`-era
ledger; Appendix B carries the newer parity-continuation copy of those flows.

This file is the checkpoint ledger for the UIKit + Combine + TDLibKit implementation. Telegram references use
`telegram-upstream/master` unless a commit is pinned. The classic pre-Liquid baseline is
`8e7e5fefb1b0aba8335d8c28b62138183d61dc3d`, the parent of Telegram's first first-parent `Glass` commit.

Implementation status and verification are separate. **done** means the recorded bounded scope has its stated proof;
**implemented breadth** means the main code paths exist, with the listed verification limits; **partial** has known gaps;
**next** identifies the next bounded slice; **queued** has not started. None implies exhaustive Telegram parity.
Gifts, Stars, collectibles, boosts, Premium, ads, livestreaming, and Telegram infrastructure
(Texture, SignalKit, Postbox, Display, ComponentFlow) are intentionally out of scope.

### Revalidation before new features — 2026-10-02

The user requested a fresh `gpt-6-astra` review of the accumulated implementation previously developed with `5.6-sol`.
The initial documentation handoff was `6b417da`; the goal subsequently started on 2026-10-02 from that clean HEAD, whose last
production commit was `7b0699d789329535786cc6170c98287c45d52ebb`. There is no `GOAL.md` in this checkout. The reusable revised
objective is [PARITY_PROMPT.md](PARITY_PROMPT.md); the previously started goal points to the user-supplied attachment.
Editing these documents does not start or resume a goal. The user explicitly resumed continuous work after the `8268947`
handoff; the goal is active. The earlier pause no longer applies. This does not mean Telegram parity is complete.
Re-read HEAD and dirty state on resume.

All existing implementation and CLEAN/build/probe/smoke claims in the old ledger remain historical evidence. Their new audit status
starts as **pending**, including flows called done or implemented; the audit results below record subsequent coverage and findings.
Preserve the original evidence and its limits; a past clean build,
zero-marker scan, catalog switch or permission-denial smoke does not prove complete behavior on the current revision.
Historical slice-level Deferred/Remaining/next notes describe those slices at the time; reconcile them with later slices and
current code before scheduling duplicate work. This section and the current checkpoint take precedence for resume ordering.

#### Audit workflow

1. Read `AGENTS.md`, `CLAUDE.md`, `project.yml`, this ledger, current code, working/index diffs and committed implementation history.
   Establish the relevant implementation base from Git history. A clean working diff is not an audit of accumulated changes.
   Inventory every flow, production entry point and shared dependency; preserve unrelated user changes and existing behavior.
2. Pin the inspected official `telegram-upstream/master` SHA and the relevant pre-Liquid reference for each flow. Use Swiftgram
   only for toggles. Verify against the pinned TDLibKit API/models, not remembered signatures or copied Telegram infrastructure.
3. Review the areas below in bounded slices, prioritizing P0 correctness and cross-flow ownership. Follow actual production
   callers, data and lifetime transitions; flag placeholders, dead paths, missing integration and overclaimed proof. Do not merely
   review the latest commit, rescan names or reread previous summaries. Fix confirmed P0/P1 findings as their area is reviewed.
4. Rewrite only for a demonstrated defect, behavioral gap, lifecycle/ownership problem, measured performance problem or avoidable
   complexity with a concrete maintenance cost. Record the evidence, replacement scope, preserved behavior/data contracts and
   regression checks before editing. A model change alone is not a rewrite reason. Keep changes bounded and avoid wholesale
   restarts or speculative abstraction.
5. For each area, record review date, reviewed SHA/files, Telegram SHA/path, TDLib version/API, findings by P0/P1/P2, fix commits,
   proof commands/device and blockers.
   Use audit states `pending`, `reviewed`, `needs-fix`, `fixed`, `runtime-blocked`; retain unresolved findings when runtime is blocked.
   Separate source review, warning-free build, deterministic probe, Simulator smoke and physical-device/server proof. Missing
   evidence is unverified, not passed; mark unavailable fixtures/permissions/hardware explicitly and continue independent work.
6. Before new feature breadth, cover every area once and close actionable P0/P1 findings; log externally blocked checks with a
   next action. Then select the highest-priority useful gap, not automatically the previous profile-management next step.
   On later resumes, continue from the recorded audit cursor and recheck changed dependencies; do not restart the entire audit.
   Proof belongs to a SHA, scenario and environment. Changed contracts, ownership or shared dependencies require a narrow
   recheck of affected flows; historical CLEAN does not automatically transfer, including to new Astra-authored repairs.
7. An explicit stop request overrides continuous gap selection. Finish only the current safe slice, stop delegated work,
   record unresolved scope and pause. A budget boundary or document edit is neither completion nor authorization to resume.

| Priority | Area to revalidate | Required checks | New audit state |
| --- | --- | --- | --- |
| P0 | MediaCore and animated media | No VLC dependency/consumer; production TGS/WebP/WebM-alpha and custom/animated emoji routes; decode ownership, alpha/timing/sync, bounded caches, offscreen pause, prefetch/cancel/fallback | reviewed with bounded A05–A09 repairs and native/transport probes; authenticated animation, device performance, broader cache identity and cross-transport arbitration remain unverified |
| P0 | Voice and video notes | Ogg Opus/waveform and H.264/AAC output; hold/cancel/lock, pause/resume, preview/seek/trim, cameras/limits; durable draft/send/retry ownership, interruptions, relaunch and terminal cleanup | reviewed with bounded A11–A17/A26 repairs, including own-draft relocation/reinstall/discard and native lifecycle/finish/handoff probes; actual OS suspension, audio delivery, hardware and server proof remain open |
| P0 | VOD, FFmpeg and PiP | Playback before full download, finite offset/limit reads, prefix/EOF checks, seek/refetch, lookahead, cancellation leases, buffering/offline/retry; same owner/playhead across inline/fullscreen/PiP, A/V sync and bounded memory | reviewed with bounded A01–A04/A18/A19 repairs; native incomplete-file playback/seek and scoped ownership probes pass. Live streaming, lookahead estimates and active system PiP/device lifecycle remain unverified |
| P0 | Message content and actions | Current generated MessageContent cases mapped to real rendering/actions and safe fallback; entities/web/captions/spoilers, albums, polls/quiz/dice/service; reply/quote/forward/edit/delete/select/reactions/pins/topics/unread/delivery | reviewed with bounded A10/A20/A31/A43–A48 repairs. A21 secret photo/video/animation and immediate/view-once playback remain incomplete and concealed; exhaustive live content/action matrix is unverified |
| P0 | Composer and timeline | Complete island states and production sends; temporary/final IDs and snapshot transitions; stable IDs, raw pagination, messageId+pixelOffset under prepend/edit/resize/keyboard; cancel/retry, prefetch, off-main work | reviewed with bounded A22/A24/A25/A39/A49a/b/c repairs and native/actual checks below. A49c2 scheduler/deletion native and ordinary actual selection/viewport checks pass; A39 intermittent native failure needs diagnosis. Physical selection race, prepend/resize/rotation/keyboard, live edit/IME and send flights remain unverified |
| P0/P1 | Cross-flow account and authority boundaries | Captured client/account/chat/topic; stale callbacks, Combine/task teardown, updates, storage/cache keys, permission revalidation; pending sends/deletes/account switches; shared player/file/audio ownership | reviewed with bounded A05/A06/A12–A14/A18/A19/A23/A29/A30/A34/A35/A38 repairs. A23 remaining subscribers and A30 active capture/full account lifecycle remain partial; no full multi-account/server proof |
| P1 | Profiles and galleries | Peer/self roles, avatar/history, member/admin/tag rights, shared-media pagination; selected item, transitions, zoom/paging/dismiss/control gestures, rotation, captions, export/forward/delete/open-in-chat | reviewed with bounded A20b/A27/A28 repairs — profile grid concealment, effective info-edit policy and pagination request identity probed; own-profile grid navigation passes at `bdd19cd`; hardware/server/gesture proof incomplete |
| P1/P2 | Accounts, chat lists/folders and classic shell | Inventory existing add/auth/switch/remove/logout paths and missing isolation; archive/search/edit/reorder/include/exclude/pin/mute/read/delete/clear/drafts; safe-area full-width blur and prohibited production UI markers | reviewed with bounded auth/list/mutation/foreground repairs below; A32 native chrome and intermittent A37 remain unresolved. Live multi-account/logout and complete secondary-surface proof remain unverified |

Read-only audit subagents return findings and need no commit or duplicate build. At most two subagents may run concurrently.
Implementation subagents use isolated worktrees, format changed Swift in one invocation, build without warnings and commit;
the primary integrates verified commits and validates the combined result. Do not spawn when the remaining budget cannot cover
integration and verification. Each implementation slice must end with proof, a focused attributed commit and an updated checkpoint.

#### Astra audit baseline and coverage

- Date/source: 2026-10-02, clean `6b417da362960e152f07ba86000b7777b636b0f5`. Pre-UIKit base is
  `67ecc4ff2287483652019b40f383d50015a35a77` (parent of `a543a0d`); VLC replacement began at `6216eee`, parent
  `0599bfdc8ff862a548b686b0f04df8b2f8ec28e5`. Audit current reachable code and the accumulated history, including integration
  merge `5d990c1`; other branches and unrelated push/build work are not authorization to merge or rewrite them.
- Official references: `telegram-upstream/master` = `6ad963e5b62d354da79040f388ae2b9132fb17b8`; classic baseline remains
  `8e7e5fefb1b0aba8335d8c28b62138183d61dc3d`. TDLibKit is pinned to `1.5.2-tdlib-1.8.66-022d6020`, TDLib `022d6020`;
  Lottie 4.6.1, libwebp 1.6.0 and checksum-pinned FFmpeg 9.0 are unchanged.
- Current marker scan over `project.yml`, `BetterTG`, `BetterTGNotificationService` and `Packages` found no VLC API/dependency,
  SwiftUI/hosting/representable or Liquid Glass production marker. This is a dependency/source check, not visual/runtime parity.

| Area | Production entry points and shared dependencies located | Initial source pass; later fixes and proofs are recorded below |
| --- | --- | --- |
| Animated media | `MessageContentView`, `MessageTextView`, reactions, composer picker and gallery → `AnimatedFileView`, TGS/WebP/FFmpeg views, `CustomEmojiStickerRepository` | Source pass through these consumers; A07 worker lifecycle/reuse probe passed, other runtime coverage and fixes outstanding |
| Voice/video notes | `ChatBottomArea`, `VideoNoteRecorderViewController`, `ChatVM` → capture/writer/codec, recording/send stores and coordinators, message playback | Voice source pass at `37c8b44`: recording/trim/PCM/codec, preview, send/retry/relaunch/outcomes and destination ownership; A11–A14. Independent video source pass at `8268947` confirms shared A12/A13 plus A15–A17; camera/interruption/server behavior remains unproved |
| VOD | `ChatView`/`ChatViewAlbum` → `GalleryVideoPlaybackOwner`, `LocalMediaPlayer` or FFmpeg sample player → range coordinator/resource loader/decoder/renderer/C AVIO | Source pass over range/loader and C/Swift decoder/render session; primary owner/PiP account/restoration pass at `909215a` finds A18/A19; other lifecycle and active-system proof pending |
| Content/actions | `MessageContentPresentation`, `MessageMetadataPresentation`, structured/text/reaction views → `ChatVM`, `MessageForwardingService`, topic/forward controllers | Source pass at `176eab9`: pinned 104-case classifier, production cell/media dispatch and spoiler/secret guards; A10/A20/A21. Structured actions at `cf885b1` find A31; exhaustive live content/action behavior remains unverified |
| Composer/timeline | `ChatBottomArea`, `ChatView`, `ChatVM`, `ChatDraftKey`, `MessageSendTransition`, date/topic header models | Timeline source pass at `3b566dd`: raw cursor, album/header identity, anchors and prefetch; A22. Composer pass at `bb01b8f`: edit dispatch/completion, semantic formatting, snapshot lifetime, ID aliases and forward isolation; A24/A25 and transition proof gaps |
| Profiles/gallery | Peer profile/control/avatar controllers → `ChatViewAlbum` gallery and owner/export/actions | Source pass at `d8ed16e`: roles, member/admin/tag controls, edit, avatar history/video, pagination, transition identity/cleanup, gesture arbitration and rotation; A27/A28. A19 isolated context/owner probes pass; active system PiP and real server actions remain unverified |
| Accounts | `TDLib`, `TelegramAccountRegistry`, root/settings/login controllers → client activation/retirement, storage, update subjects | Initial source pass at `cf885b1`: UUID databases, atomic registry, client retirement, auth routing and background ownership; A23/A30. No real add/switch/logout or notification-service handoff proof |
| Lists/shell | `MainView`, `RootVM`, `FolderView`, `ChatFolderManagementViewController`, navigation/context-menu views | Initial source pass at `cf885b1`: frozen list payloads versus dynamic action clients A29, page/tab state and full-width safe-area constraints. Secondary surfaces/search mutations and visual matrix remain partial |

#### Astra findings and repair queue

Active queue: A53b2 verified/versioned cache-only previews, then queued actual ChatView mutations. A53b1/1a deny unsafe enrichment; they do not complete cache-only parity.
A51a `38b7d06` and A51b `6b187b0` pass isolated cache/worker native probes. Post-worker sample was idle-only, so comparable
production performance remains unverified; do not infer a speedup or keep repeating unaligned captures. Keep A39's deadline.
`e70a227` repairs the separately reproduced latest-end sample invalidation: controlled baseline FAIL0.811s becomes PASS;
the ordinary native viewport/settlement regression also passes. Actual ChatView repeated-end behavior is unverified.
Passive timing at `31e497a` identifies delayed native callbacks and wait resumptions, not expensive target resolution;
the A51 sample identifies substantial synchronous main-thread cache work but does not prove sole causality. Keep the2s deadline and strict settlement predicates.
`f799d29` integrates frozen rendering/serialized applies after value prerequisite `d8512b5`; exact reviewed worker tree
`bac0ab6f`, primary build `151812-44934-6936` PASS23s/fullzero. Provider callback authority `eeb93b2`, selection touch
binding `9961aba` and A49a fallback retain bounded native proof; physical touch across same-cell reconfiguration is unverified.
`724bf32` repairs the measured UIKit deletion reset through inner presentation ownership. Native scheduler PID79368,
final delivery/action and actual A22 PID79903 pass. Same-PID Saved Select→Cancel and deselect-last remove every visible
selector. Standalone A39 PID50146 repeats the earlier unresolved native settlement failure; no timeout was relaxed.
Goal remains active; no sends/deletes/forwards or host focus activation. Latest checkpoint/build and proof limits are in A51.
A22 actual ChatView completion/control/ended-delegate-drag proof passes at `41f87a5`; physical mutation races remain open.
A46b forwarding pin ordering and A32 top search placement have bounded native/actual proof below.
A32 still has native capsule/shadow/Back limitations; A48's early-detachment callback has bounded native proof.
A47 individual topic-list reads `09db3f5` pass max-two/FIFO/reset native checks and existing forum regressions.
A30h member-tag draft retention/renewed explicit Save `c895a8c` passes bounded native checks and existing profile regressions.
A44b2a/b shared bounded reads and exact per-topic receipts `4a2a190`/`2190c4d` pass controlled reader/native MessageCell probes.
A45a/b/c echo/direct-scalar, full-read arbitration and known server-query membership have bounded native proof.
A44a ordinary and A44b1 explicit-topic bubble states have bounded native and real-history/foreground proof.
All-messages receipt aggregation now has bounded proof; live history/peer-read behavior remains unverified. No cross-topic/global fallback.
At `72d74b0`, the integrated
`982245f` navigation driver passes cold, loaded and same-PID foreground target checks with actual visible/centered cells.
A30g source review and actual same-PID basic-group smoke confirmed an open member list lost its parent profile and route during client replacement.
A40 removes concealed metadata warnings; A41 repairs the separately observed static-framework cleanup/build race.
A42 arose during active-forum-search smoke: an actual diffable reconfigure crash is now repaired with bounded native/actual
proof below. A30g is integrated through `e049da3`: native regressions and repeated Members/Admins foreground/Back smoke pass
within the stated bounds. Active forum search now renews its binding without replacing the live field or weakening global
modal guards: actual two-epoch query/clear smoke passes at `501af59`; exact-task native proof passes at `37e08e8` below.
A38 stale shared-media admission has bounded source/native/actual-profile repair proof below. A36 selector presentation and A37
post-foreground navigation overlap have fresh runtime evidence below. A21 secret-note scene-capture admission now has integrated native/UIKit
proof below; hardware capture and screenshot prevention remain unverified. A34/A35 now have integrated
ordering/ownership probes; delayed live RootVM RPC remains unverified. A32 cleanup preserves native Back
but its background remains a visual gap. A23 static-image authority and
pending-membership insertion have integrated probes; remaining live-account and non-position hydration proof stays open. A30 ForumTopics recovery has
integrated quiescent and active-search same-PID/native proof below; capture and remaining editors stay open. A33 profile-header sizing has actual-profile
geometry/screenshot proof at `b97fa9b`. A21 timed
video-note hold authority has integrated native/UIKit proof; other secret media and view-once playback remain open. A20 profile-grid concealment
has bounded integrated proof at `bdd19cd`; real spoiler gestures and transport remain unverified.
Auth A23e and bounded composer A25 semantic/marked-input/undo probes pass; live authentication/keyboard remain unverified.
A08 timing and A10 text spoilers now have integrated native/UIKit probes; A10's first runtime failure is fixed separately below.
A30b2 now enables quiescent Chat foreground recovery with bounded real-chat smoke; A15b2 voice lifecycle has native isolated proof.
A30a root lists, A30b1 composer-transfer foundation and A16/A17 video ownership retain their bounded proofs below;
Archive and ForumTopics now have bounded query/focus recovery proof below. Remaining already-open editors, active capture and full OS/server
lifecycle coverage remain separate.
A26 relocation and A29 frozen list mutations have integrated bounded proofs below; A29 cold-launch folder navigation also passes.
A12/A13/A18 delivery correlation and accepted-update transport are repaired with bounded proofs below;
callbacks rejected before publication and recovery without a registered temporary ID remain separate gaps.
A11 preserves voice recording route/reply/caption, PCM, waveform, trim and revision contracts across lifecycle teardown;
its bounded proof and remaining runtime limits are recorded below. A14 and A19 now have integrated isolated proofs;
A14's real no-send promotion exposed A26 on reinstall; the follow-up repaired relocation and recovered that same own draft.

Locations A01–A10 refer to the reviewed `6b417da` implementation unless a fix is recorded; voice A11–A14 were reviewed at
`37c8b44`. Source findings are not runtime proof. A repaired finding does not mark its entire area fixed.

| ID | Priority | Evidence / trigger | State and bounded repair |
| --- | --- | --- | --- |
| A01 | P1 | `TDLibVODRangeSource.waitForSignal/timeoutWaiter`: canceled sleep still invokes timeout; a repeated wait reuses read ID and seek generation, allowing an old callback to consume its replacement | fixed in `37c8b44`: per-registration token, cancellation return; obsolete/current-deadline probe passed |
| A02 | P1 | `ensureAvailable` can receive `updateFile` while awaiting an older zero-prefix RPC result, then register after the only wakeup; bytes wait for timeout despite being cached | fixed in `37c8b44`: compare update sequence before registering at all three wait sites; suspended-prefix production-read regression passed |
| A03 | P1 | `FFmpegSampleBufferRenderer.pause` publishes on every call; player snapshot delivery calls `updatePlaybackGate`, which pauses again in paused/buffering/EOF states | fixed in `3005369`: deduplicate complete identical snapshots while preserving every pause transport command; settled feedback, seek/rate/EOF/offline/retry probes passed |
| A04 | P1 | Decoder/controller expose maximum A/V duration, but readiness always requires video; a 5s-video/60s-audio file accepts a 20s seek with no possible video frame and reaches watchdog failure | fixed by `83103ba`, `14a01c5`, `ef8f4ba` — explicit video-main end, estimated-versus-final duration authority and verified EOF/watchdog teardown. Follow-up below repairs missing-metadata buffering and proves native playback/seek with incomplete coverage of a 13.3 MB file; live server streaming and lookahead estimate authority remain separate |
| A05 | P1 | TGS/WebP/FFmpeg animation views use global `nc.updateFile` plus numeric file ID and deferred dynamic `td`; account switch precedes root teardown. Custom-emoji fetch also resolves a dynamic client | fixed bounded source/transport — `128ada2` freezes requests and scopes delivery/decode; `6e5b287` requires originating clients through every animated consumer and custom-emoji fetch, clears reused thumbnails. Isolated transport/native/PiP regressions pass; real multi-account sticker playback unverified. A06 has its separate shared-demand repair |
| A06 | P1 | Animation view teardown/prefetch calls global file cancellation without shared demand ownership; one reused copy can cancel another visible copy's pending download | fixed bounded animated demand — `09fa140` shares account/client/file leases across TGS/WebP/WebM views and animated prefetch; last-owner cancellation/reacquisition and queued terminal updates pass isolated production-pool probes. Static `.none` prefetch and VOD-range arbitration remain separate; actual TDLib/view scheduling is unverified |
| A07 | P1 | `FFmpegAnimatedVideoView.show` constructs its decoder on MainActor; initializer opens/probes FFmpeg input and codecs synchronously, even on asset-cache hits | fixed in `3917128`: native-free init, worker-isolated prepare/read/reset/deinit and setup/reuse fences; actual native-operation thread/lifecycle probe passed before and after integration |
| A08 | P1 | FFmpeg animation indexes use capped 30 FPS and at most 600 estimated frames while decoder returns every source frame; 60 FPS and long animations never reach real EOF, variable-duration GIF timing is lost | fixed bounded timing — `863de36` uses native PTS/actual EOF, coalesced off-main bounded scan and first-frame fallback. Pinned iOS VFR/120/660-frame/metadata/cancellation probes and A07 regression pass; real media/performance remain unverified |
| A09 | P1 | Apple-container `messageAnimation` routes to static `FileMediaPreviewView`; only fullscreen owns playback | fixed bounded native loop — `e9b536b` shares existing owner/item/layer inline↔gallery, silent looping, per-animation visibility, pending-download cancellation and source/media identity fences. Actual native/probe backend and gallery/PiP regressions pass; real TDLib/live scrolling remain unverified |
| A10 | P1 | `Utils/Text.swift` spoiler formatting only adds background color; `MessageTextView.configure` retains visible text/custom emoji and exposes unredacted text through accessibility | fixed bounded text concealment — `2bf7428` shares scoped body/album/AX reveal and concealed reply/summary projection; `10b23c5` repairs surrogate validation exposed by first runtime. UIKit glyph/AX/state probes pass; actual emoji/album/live UI and separate media A20 remain unverified |
| A11 | P1 | `ChatView.viewDidDisappear` → `ChatBottomArea.cancelActiveRecordingGesture` → `ChatVM.cancelVoiceRecording` deletes the saved preview/WAV on Back because preview keeps `recordingVoiceNote == true`; permission loss uses the same teardown | fixed in `909215a` — preserve on teardown, wait for route-owned persistence and invalidate old UI intents; Simulator preview/trim Back→reopen→relaunch, active-recording Back and explicit Delete passed; live rights mutation/reply fixture remain unverified |
| A12 | P1 | Voice and video coordinators derive outcome destination from the delivered message topic, but an all-messages draft owns `destination.topic == nil` with separate `sendTopic`; store lookups require exact route equality before and after enqueue registration. Both `loadOutcome` helpers also fall back to any draft outcome when the exact temporary-ID record is absent | fixed in `847b838` (worker `2ccdb9b`) — separate delivery key, unique candidate, route+delivery enqueue gates and exact temporary-ID journal consumption. Isolated real-store early/late, all-messages, wrong-ID, ambiguity and relaunch probe passed. Pre-registration crash retains unresolved ownership; automatic recovery remains open |
| A13 | P1 | Voice and video coordinators read current active account after `NotificationCenter.publisher` defers delivery to main; an account switch between posting and delivery can attribute A's outcome/delete to B with colliding IDs | fixed in `c356513` (worker `1eb9d23`) — immutable accepted-update source through generated dispatcher; 15 outcome/delete subscribers migrated, including document cleanup; isolated production-transport probe passed. This does not fix callbacks dropped before publication, A12 correlation or A18 media streams |
| A14 | P1 | `ChatVM.startVoiceFinalization` persists an adopted draft before encoding, but sets enqueue ownership only later; a reopened ChatVM restores it as retryable while the previous owner still encodes/sends; store has no finalization/file reservation | fixed in `bb01b8f` (worker `a8d04c2`) — canonical per-draft/token ownership through encode and actual-ID registration, unique codec outputs, cancellation/join and stale UI fences. Native-codec/store probe and A12 regression pass; production no-send promotion passes. Reinstall proof fails separately at pre-existing A26 |
| A15 | P1 | Video navigation/background/interruption sets preservation intent, then `VideoNoteCaptureSession.cancel` → writer cancellation deletes the current MP4 before adoption; Record More loses the unadopted new segment | fixed bounded lifecycle — navigation joins through `d34eeb3`, video `8b42052`, voice `15871f5`/`fe5de21`; actual codec/private-store lifecycle and send-boundary probes pass. Real OS suspension/audio delivery, hardware UI and live TDLib boundaries remain unverified |
| A16 | P1 | A retained consumed-origin video preview still owns its managed send asset; retry from composer acquires enqueue ownership, but preview Cancel calls `discardVideoNoteAsset` without the retry guard and can remove that in-flight file | fixed bounded handoff in `a72d93b` (worker `44c2c35`) — consumed-retained preview detaches without reclaiming/discarding send-store media, including pending Cancel; unconsumed cancellation and tombstones unchanged. Actual offscreen recorder/native media/isolated store probe passes stale teardown→retry registration; live send/gesture/recording materialization remains unverified |
| A17 | P1 | Video automatic limit reserves `stopRequested` before async finish/UI publication; manual release in this gap still calls finish, gets `recordingUnavailable`, then failure cleanup cancels/deletes the valid near-limit clip | fixed bounded ownership in `e8a0eb1` (worker `6809716`) — one generation-scoped finish owner; competing stop returns no asset, automatic delivery retains authority, recorder operation completions are token-fenced. Actual capture-session/native H.264/AAC probe passes; real camera/limit/gesture/adoption proof remains open |
| A18 | P1 | `TDLib.activate` creates account-labelled range coordinators but passes the same lifetime-global `fileUpdates` subject; retained old-account sources accept new-account files by numeric ID. The lifetime-global delete subject similarly reaches old gallery/PiP owners without provenance | fixed in `76f9998` (worker `b2e33d2`) — immutable per-activation streams, accepted-source fence and inert bootstrap. Real range-source bytes plus retained deletion subscriptions pass A/B/replacement-client collision probe. Actual account switch/system PiP remains unverified; A19 restoration remains open |
| A19 | P1 | `GalleryPictureInPictureCoordinator.presentRestoredGallery` retains messages/owner but rebuilds gallery with mutable shared `tdlib` only, omitting original `actionClient`, `sourceLocation` and `contextIsCurrent`; restore has no account/client guard, and dismissed PiP ownership survives context teardown | fixed in `d8ed16e` (worker `1ea2594`) — frozen account/client/chat/topic/ranges/delete authority, route callbacks and same-tab pagination, every-activation revocation, bounded exactly-once restoration. Isolated context and existing owner probes pass; actual system PiP and action transport remain unverified |
| A20 | P1 | At `176eab9`, `MessageMediaView`/album tiles drop `MessagePhoto/Video/Animation.hasSpoiler`; no production display consumer checks this flag. Photos/previews and eligible videos/FFmpeg animations render before any reveal | fixed bounded concealment — `05c2b49` gates timeline/album/gallery; `d8f9b36`/`bdd19cd` gate profile-grid thumbnails, revision replacement and snapshots. Actual UIKit/native fixture probes and ordinary own-profile navigation pass. Real spoiler gestures, transport and visual polish remain unverified. Distinct from caption/text spoiler A10 |
| A21 | P1 | `MessagePhoto.isSecret` is lost by `SinglePhotoView.configure(photo:)`; animation paths likewise omit it. Video inline autoplay and export/PiP are gated, but preview/fullscreen presentation still uses the ordinary tap route; only video-note playback calls `openMessageContent` | partial — A20a denies ordinary secret photo/video/animation pixels. `0e4e1e1`/`437d7c7` repair timed video-note per-hold/client/ACK/expiry authority; actual UIKit/native probe passes through `4c3fc5e`. `13a0450b` adds the rest: Telegram's secret media bubble (blurred inline thumbnail, flame that becomes the countdown ring, "1" or seconds badge) and a SecretMediaPreviewController port for photos, videos and GIFs (title, Back, 28 pt timer, view-once mark and tooltip, timed photo closes at its deadline, short video/GIF/view-once replay, "X hasn't opened this photo yet" for sent media, zoom, swipe to dismiss). The media is read into memory or a private copy before openMessageContent on its own client, after a revision recheck; it hides while the screen is captured or the app is inactive. `-ui-probe-secret-media` passes over stubbed TDLib (read before open, deadline close, sent media not opened, view-once file deleted on open and still shown) with Xcode MCP live check of the tooltip and Back. No real secret content consumed. Not portable: Telegram's screenshot notice (TDLib has no API for it) and its screenshot-proof layer |
| A22 | P1 | `ChatView.updateSnapshot` (1329–1367 at `3b566dd`) captures latest/anchor without checking tracking/drag/deceleration, then unconditionally restores it after asynchronous diffable apply. Reconfigure/rotation completions also reuse a captured anchor without a fresh interaction/revision check | partial bounded repair — `6869382` one-shot geometry authority; `41f87a5` proves actual ChatView unchanged-snapshot completion with nonvacuous control and ended delegate-drag rejection, exact stable-ID offsets and cleanup. Actual inserted history/physical drag, rotation, keyboard and media-resize overlap remain unverified |
| A23 | P1 | At `19a6f94`, RootVM's non-outcome TD notifications still lose source before main delivery; `updateChatLastMessage`/draft/unread/user handlers mutate current folders by numeric ID. `refreshChat` awaits dynamic `td.getChat` then writes current folders without captured account/client/generation validation; an A response may overwrite B's same-ID chat after switching | partial — Root/list `e1d295e`, Chat `df9eb7a`, ForumTopics `78f0f8a`, static-image `ba0e192` and auth `097b488` have bounded authority proofs. `7426478`/`b3aa790` add static-image origin/shared demand with actual UIImageView/native/profile proof. `1cd9ecf` fences pending-list membership; suspended production-helper probe passes. Remaining subscribers/non-position ordering and real multi-account RPC races stay open; bulk rebuild/settings are A34/A35 |
| A24 | P1 | At `bb01b8f`, `ChatVM.sendMessage` dispatches by `canEditMessage`; an empty text edit falls through to preserved ordinary text/attachments. A successful edit clears by message ID only, discarding newer typing or a reopened same-ID edit session | fixed in `b18da97` (worker `8aa914f`) — explicit edit intent, immutable payload and session/revision gates on success/error; invalid text edit disabled, empty media caption allowed. Integrated suspended-callback policy probe passes; full ChatVM/UI/server edit remains unverified |
| A25 | P1 | `Utils/Text.swift` maps independent bold/italic to one font, collapses pre/preCode to code and drops quote/mention/custom-emoji identity; loading and saving a formatted message can remove entities unrelated to the edit | fixed bounded semantic round trip — `a022017` codec/scoped bridges, `fb15c25` caret refresh and `26d5f48` programmatic marked-input/UIKit undo proof pass. Live IME/keyboard shortcuts, clipboard and server round trips remain unverified. Separate from A10 display concealment |
| A26 | P1 | Real own-draft reinstall at `d8ed16e` relocates the app data container: `VoiceNoteDraftStore.loadAllDrafts` rejects persisted absolute URLs and deletes the manifest although its Ogg remains. `VideoNoteFileStore.loadAllManifests` has the same absolute-path filter for MP4/thumbnail | fixed in `8519b33` (worker `2e28fad`) — relative managed filenames, strict legacy container rebasing, retained malformed/missing manifests and migration-write fallback. Isolated voice/video relocation/outcome probes and own voice recovery→reinstall→Discard pass; DEBUG fixture correction `5a87726` keeps production validation strict |
| A27 | P1 | `peerProfileCanChangeInfo` only accepts creator/admin, so eligible group members with `Chat.permissions.canChangeInfo` cannot open or save Edit; restricted-member permissions are also ignored | fixed in `b0db39f` (worker `1a78906`) — shared effective capability, fresh appearance hydration and scoped rights updates; captured actor/account/client plus fresh `getChat`/`getChatMember` before each title/description write. Integrated 25-case policy and delayed-request probe passes; live profile permission/save behavior remains unverified |
| A28 | P2 | `PeerProfileViewController.loadMore` catches without a request-generation fence; A→B→A lets the first A's late error clear the newer A `historyTask` and display a stale error. TDLib continuation is not canceled by task cancellation | fixed in `9cdc6b0` — invalidate request identity before tab cancellation; success/error/cancellation may clear busy state or publish only after consuming their exact registration. Token regression passes A→B→A, obsolete cancellation, retry and duplicate delivery; actual suspended controller/RPC race remains unverified |
| A29 | P1 | `MainView.setAllChatsMuted` re-resolves global `td` between `getChat` and `setChatNotificationSettings`; switching A→B during the read can write A's settings/peer ID through B. FolderView/menu/editor read/write sequences likewise lack frozen action authority | fixed bounded transport in `15f146f` (worker `7513376`) — immutable action client/source, read/write/completion gates, cancellation/attachment checks. Production bulk-helper suspended-read/write probe passes with stale writes=0; cold-launch folder/editor navigation passes. Live account/dismissal mutation races and server writes remain unverified; stale same-account screens still require A30 |
| A30 | P1 | Background ownership release closes clients while suppressing Closing/Closed; foreground activates same account with `notify:false`. Root compares only loggedIn/accountID and retains a ChatVM whose immutable client/location epoch is closed; updates/sends are rejected until Back→reopen | partial — Main `0820359`/`c5d3f8b`; quiescent Chat `494bf56`/`9495f0a`; Archive `bb36bc7`; ForumTopics `958bc82`/`01a2d84` and active search through `501af59`; folder flows `850ccf8`/`b923f19`; profile editor `1e072ca`; quiescent profile `c68c1c2` plus A38 `97ccea8`; quiescent Members/Admins through `e049da3`; tag editor `c895a8c`. Bounded native and same-PID foreground proofs below; A39 has bounded repair proof. Active capture, live tag Save renewal and full account/notification lifecycle remain open |
| A30g | P1 | At `72d74b0`, Profile only retains itself while topmost; an open Members/Admins child keeps the old client and lacks restoration participation. Actual basic-group Members → Home → foreground drops both routes to Chat in the same PID | fixed bounded — `55ff037`/`f9b5dad` exact-parent/list retention including unloaded parent across epochs; `e049da3` explicit visible Retry. Native regressions pass; actual basic-group Members survives two epochs, Admins survives one and Back reaches fresh Profile. Live supergroup pagination/permission loss, tag editor and dispatched Save remain separate |
| A30h | P1 | At `2190c4d`, MembersParentBinding requires Members topmost; [Profile, Members, Tag] cannot retain Profile on client renewal and its account-change handler removes the entire suffix. Tag editor also freezes the old client and owns no renewal session | fixed bounded in `c895a8c`: exact typed triplet hold, renewed immutable edit endpoint with fresh tag authority, uncertain-write/no-replay and revision-safe ACK. Native PID83507 and existing profile regressions pass; whole live chain/foreground, interactive Back cancellation and authorized server Save remain unverified |
| A31 | P2 | Poll submission times out after 10s and allows another request, but old RPC failure calls `failSubmission(messageID:)` without an attempt token, clearing the newer submission's busy state; timeout callbacks likewise identify only message/source selection | fixed bounded scope — `b7de6ee` freezes per-attempt identity across queued RPC, failure, timeout and authoritative selection reset; production-store probe passes, delayed live RPC/UI remains unverified |
| A32 | P2 | A29 production screenshots at `15f146f` show circular Back/Add and capsule Save controls on Chat Folders/New Folder; those secondary screens use native UIBarButtonItem despite the required classic chrome | fixed — explicit buttons `941a90a`/`1b89dbd`, nil Back cleanup `3983b48`. `1ef0935` keeps owned native search below the title and out of the toolbar; native and actual forum query/foreground/clear pass. Closed by Xcode MCP Simulator check 10-16 at `a6af8476`: Chat Folders, New Folder, Settings → Notifications/Privacy/Data and Storage/Devices, and a group's Edit/Members/Administrators all show the classic chevron Back (44 pt, labelled "back") and plain text or icon right buttons with no circles or capsules; the forum's Search Topics field is the same flat capsule without shadow as the chat list search |
| A33 | P2 | Actual own-profile screenshot at `bdd19cd` shows Saved Messages wrapped and truncated inside a narrow title region although the full-width header has room | fixed bounded width — `b97fa9b` gives header labels definite available width. Actual profile at 402pt: title 362pt, full Saved Messages visible, avatar96pt; A20b regression passes. Other widths/Dynamic Type/RTL remain unverified. Separate from A20b; no introduced-regression claim |
| A34 | P1 | At `7426478`, `RootVM.updateChatFolders` builds main/custom snapshots, awaits archive hydration, then replaces all folders. Accepted same-epoch unread/draft/message/position events during that await mutate the old objects and are lost on replacement | fixed bounded observed fields — `4185849` reconciles newer accepted deltas across raw/peer/list reads and final insertion; `3290ba4` retires superseded refresh projections immediately. Actual reducer/insertion suspended probes pass. RootVM transport wiring is source-reviewed; unobserved fields/group updates and delayed live RPC remain open |
| A35 | P2 | At `7426478`, `RootVM.loadScopeNotificationSettings` collects three sequential reads and finally merges old values over settings accepted from intervening updates | fixed in `67c9470` — per-scope request revisions reserved before dispatch, accepted-update revocation and immediate response publication. Actual loader suspended-read probe passes overlapping loads, late success/failure, source/epoch/cancel and value retention; real mute-badge race is unverified |
| A36 | P2 | Folder selector passes empty raw titles through cell/sort/search and labels every `.user` Contact. Actual `1b89dbd` has 11 empty rows, all explicitly deleted/non-contact, with no cell/model mismatch. Nested candidate changes also lack a live presentation subscription | fixed bounded presentation/membership — `c9254f3` title/subtitle/search/sort and `f70cd58` child publishers; native append/remove/replacement and actual deleted-title/search proof pass. `0608d15` corrects modal fixture settlement without weakening ownership checks. Live RootVM/TDLib membership transport remains unverified |
| A37 | P2 | Actual retained profile editor at `1e072ca` after same-PID Home→foreground keeps fields at y136/y182, but the settled top blur extends to about y150 instead of y116 and covers the first field; reopening fixes it | unresolved intermittent — later focused baseline and actual delayed settled geometry are clean. Preserve the original failure; require a fresh measured reproduction before repair. Data/caret retention passes; root stack replacement/prompt updates remain unproven causes |
| A38 | P1 | A30f2 `c68c1c2` publishes prior-client Message seeds with fresh reveal/playback authority. B-epoch content/delete updates during metadata await are missed, and settled nonempty seeds are never revalidated | fixed bounded admission — `97ccea8` quarantines seeds with four-read current-client refresh, scoped revisions/tombstones, explicit Retry and synchronous permit/consumer revocation. `b630844` fixes probe settlement only. Native races and actual scrolled profile foreground pass; delayed real RPC/delete/spoiler, new-head discovery and active system PiP remain unverified |
| A39 | P1 | At `97ccea8`, explicit navigation retains old viewport intent and stale snapshot state. At `17e3fb4`, actual cold/loaded target navigation still misses. `8b8d149` actual trace proves automatic anchor capture/restore interrupts its animation | bounded target repair `6a29431`/`982245f` has actual cold/loaded/foreground proof at `72d74b0`; `e70a227` separately fixes latest-end sample invalidation with controlled baseline FAIL/fixed PASS and ordinary native regression PASS. Intermittent animated-resize deadlines remain open: `31e497a` measures delayed callback delivery/wait resumptions with sub-millisecond resolver/callback work; root scheduling cause unverified. Live quote, album remap, user interruption and rotation remain separate proof limits |
| A40 | P1 | `6a29431` integration log contains an AppIntents metadata warning for the notification extension; both wrapper output paths concealed this warning | fixed — `eff2876` removes warning filters and unused extension import, skips its inapplicable AppIntents stage. Complete signed/unsigned/final-signed logs are warning-free after A41. Compact-only historical claims are not proof of zero warnings |
| A41 | P1 | Existing static TDLib cleanup lacks dependency edges to SwiftPM's automatic package copy/sign, deleting the framework during lipo/sign in two consecutive builds | fixed bounded build DAG — `72d74b0` declares bundle and child signature inputs; copy → child sign → cleanup → app sign. Signed/unsigned/repeated signed builds and strict deep signature check pass; device/archive not exercised |
| A42 | P1 | Actual forum search at `72d74b0` crashes: queued topics snapshot reconfigures an ID missing from newer VM.topics, so provider returns a different fallback cell | fixed bounded diffable ownership — serialized snapshot-owned models, coalesced pending payload, outgoing retention through completion and exact dequeued fallback. Native real-table/cell probe and actual query changes pass; active-search foreground is separate A30d work |
| A43 | P1 | At `d8e2bb0`, list delivery UI reads `Chat.lastReadOutboxMessageId`, but `updateChatReadOutbox` has no production consumer. TDLib emits this update independently; ticks stay Delivered until unrelated hydration | fixed bounded receipt feed — scoped Root observer, direct typed update of exact chat instances across folders/archive and revision-stamped protection for in-flight reads. Native cell AX/scoped delivery/projection regressions pass; live peer-read transport and full RootVM/UI wiring remain source-reviewed |
| A44 | P1 | At `596e895`, MessageCell's shared text/media/footer status is only timestamp or Failed; bubbles never render Sending/Delivered/Read. ChatVM has no outbox feed and all-messages forum rejects scalar topic updates | fixed bounded ordinary/forum delivery — `1630ee1`, geometry `909f62b`, explicit-topic `5b9b322`, all-messages shared reads/receipts `4a2a190`/`2190c4d`. Controlled/native cells and actual ordinary/explicit-topic foreground display pass. Live all-messages/peer-read transitions and final self mapping remain separate; broadcast final checks conservatively excluded |
| A45 | P1 | `ForumTopicsVM.observeUpdates` unconditionally calls getForumTopic on updateForumTopic; pinned TDLib emits updateForumTopic after every fetched topic, even unchanged | fixed bounded echo/read ownership — `e3fb6d9`, `597d6f3`, page-membership correction `c9317e5`, known-row lifetime `0a4c6af`. Real-VM controlled reads/native cell and controller regressions pass; actual search/foreground and fuzzy before/after proof recorded. Actual TDLib request counts, delayed server conflicting updates and one bounded redundant unknown follow-up remain unverified/open |
| A46 | P2 | At `cb723ab`, topic-page merge and individual refresh sort only TD order/id, while isPinned changes only decoration; TD order excludes pin position | fixed bounded in primary list `34b7868` and Forward `e2dd664`: query-owned raw-head ranks, membership-edge revocation and unchanged raw cursor. Native multi-pin/append/query/selection and actual single-pin lists pass. Live multi-pin/reorder remains unverified; changed-pin echo can need a second stable head and pure remote reorder needs explicit refresh |
| A47 | P1 | At `69b0212`, distinct unknown same-chat topic info/scalar updates each start an individual getForumTopic; pending drain has no concurrency cap, and reset drops canceled task registrations before native completions | fixed bounded in `09db3f5`: max two individual native reads per VM across canceled query generations, exact-UUID retirement and coalesced FIFO demand. Native PID97812 and existing forum regressions pass. Page concurrency, global cross-VM limits and queue hard memory cap are outside this slice; no live lag/OOM claim |
| A48 | P1 | At `34b7868`, forwarding topic selector replaces its live topic array before un-serialized animated diffable applies; failed query retry can also merge older-query rows. Native teardown exposed a detached-parent interval before didMove(nil) | fixed bounded through `fe9424c`/`727103c`, diagnostic `1fa99a9`: transaction-owned models, serialized page/toggle applies, accepted-query and immediate containment gates. Native PID68845 passes late-callback/cursor/pending-drain checks before retirement. Natural baseline crash, live permission/TDLib races, modal dismiss and actual interactive cancellation remain unverified |
| A49 | P1 | At `41f87a5`, ChatView message provider dequeues MessageCell then looks up current VM.messages; a miss returns a new UICollectionViewCell. Main-queue snapshot dispatch and 140ms deletion delay leave outgoing IDs in the old snapshot | bounded repairs — A49a exact-cell fallback, A49b provider/touch authority, A49c1 values and A49c2 `f799d29` shared frozen transactions; `724bf32` repairs measured UIKit deletion reset. Scheduler/action native probes and actual selection/viewport checks pass. Natural Chat crash was not reproduced; actual queued mutation/delete timing/player and physical touch races remain unverified |
| A50 | P1 | Actual Saved Messages Cancel leaves circles/controls on unselected rows; endMessageSelection only invalidates previously selected IDs, and deselect-last invalidates zero rows | bounded fix `487c0de` updates all snapshot message rows on exit and surviving rows in structural last-selection removal. Actual Cancel/deselect-last screenshots pass; structural removal source-reviewed only |
| A51 | P1 | At `1c72d3a`, launch sample attributes628/1931 main-thread samples to rich-notification user/chat cache sinks doing source-file reads, image decode/JPEG, directory lookup and atomic writes. Coordinator uses raw events/global td across awaits and disk keys omit account | bounded repairs `38b7d06` account/source isolation and `6b187b0` serial off-main avatars/current-photo ordering; native isolated probes pass. Post-change sample is idle-only, not a performance comparison. Strict NSE write cutoff, photo-removal disk invalidation, registration cardinality and media IO remain open; actual notification delivery unverified |
| A52 | P1 | Source follow-up at `1c72d3a`: NSE chooses addedNotifications.last when no notification matches expected message; nested unstructured resolution tasks are not retired by canceling the outer service task | fixed bounded A52a `878e85f`, A52b1 `90d324d`, A52b2 `559a762`: exact identity/single resolver, session publication cutoff and request-owned completion/content producer; native helper cases pass. Actual NSE delivery/TDLib close, RPC termination and completion of already-started donation remain unverified |
| A53 | P1 | At `38b7d06`, app coordinator caches incoming photo/video/animation without isSecret/hasSpoiler checks; NSE MessageContent resolution excludes them, but shared-cache fallback/attachment construction can reintroduce those bytes | fixed bounded A53a `afed19b`, A53b1 `805494f` and A53b1a `cb84f9b`: full-message admission, scoped job revocation, explicit preview denial, NSE legacy-read cutoff and caption-entity concealment; native policy/pipeline cases pass. A53b2 verified cache-only restoration remains needs-fix. No real notification or concealed-media bytes exercised |

Reference contracts: pre-Liquid `MediaPlayer/Sources/ChunkMediaPlayerDirectFetchSourceImpl.swift` registers range data and cancel
observers before waiting (lines 20–38), uses bounded read/lookahead windows (lines 189–212) and selects video as the main track
(lines 545/578). `ChunkMediaPlayerV2.swift` changes synchronizer rate only when effective rate differs (lines 699–702).
Animation references: pre-Liquid `AnimatedStickerNode.swift` source creation outside main (lines 477–507), `SoftwareVideoSource.swift`
PTS/duration (213–227), `EmojiTextAttachmentView.swift` account/visibility ownership; current `VideoStickerFrameSource.swift` derives
frame count at EOF (351/409–420). No Telegram infrastructure is copied.
Voice references: current `ChatControllerMediaRecording.swift` preserves preview resource/waveform/trim/resume state
(305–329, 640–663); pre-Liquid `ChatInterfaceState.swift` persists peer/thread-scoped media drafts (726–730, 899–918),
and `ManagedAudioRecorder.swift` materializes pause/resume/trim before append (486–538). Voice findings are source-only;
the existing codec probe's all-messages outcome uses the original route and therefore does not exercise A12's coordinator mismatch.
Video source pass at `8268947`: `VideoNoteRecorderViewController`, `VideoNoteCaptureSession`, `VideoNoteAssetWriter`,
`VideoNoteFileStore`, `VideoNoteDraftCoordinator`, `ChatVM` and composer retry/discard callers. References at the pinned current /
pre-Liquid SHAs: `ChatControllerMediaRecording.swift` stop-to-preview (404–475 / 414–482), `ChatController.swift` navigation
(6856–6865 / 5963–5971), `VideoMessageCameraScreen.swift` limit handling (437–479 / 426–468), and
`Camera/Sources/VideoRecorder.swift` (354–373 at both). Positive checks: serial A/V drain, capture-generation/camera retiming,
atomic recording revisions, composition snapshot lifetime and atomic send adoption/removal tombstones. These do not close A15–A17.

Positive source checks: bounded cancellable TGS inflate, copied premultiplied WebP/FFmpeg frames, bounded frame caches, first-frame
fallback; checked C AVIO arithmetic/packet ownership, serialized close/cancel and retained Swift callback contexts. These checks do not
close runtime gaps. P2 follow-ups include TGS parsed-cache byte bounds, custom-emoji metadata eviction, repainting and glyph advance.

Owner/PiP source pass — 2026-10-02 at `909215a`: primary inspected `TDLib.swift` activation/publication (62, 194–218,
306–384), `TDLibVODRangeSource.swift` routing/acceptance (372–376, 814–823, 993–1099), gallery context/release/delete
(905, 934–950, 1348–1407, 1824–1849), owner/delete lifecycle (3946–4033, 4755–4860, 5147–5176) and PiP restoration
(5443–5628). Positive source checks: attachment-token reuse fencing, pending/active PiP retention, timeout identity checks,
exactly-once skip completion and guarded audio-session release. A18/A19 remain source findings, not reproduced system PiP.
Reference: pinned pre-Liquid `GalleryUI/Sources/Items/UniversalVideoGalleryItem.swift` retains its context (75/959), keys hidden
media by account (1060–1068), and restores via its captured expand callback (1093–1104). DirectFetch reads through its captured
resource media store (491/511/637–646). Current full-gallery action/gesture audit remains pending; no infrastructure is copied.

Message-content source pass — 2026-10-02 at `176eab9`: `MessageContentPresentation` exhaustively maps the pinned 104-case
TDLib enum; explicit unsupported/expired/service/excluded-paid paths exist. `MessageCell.configure` connects the classifier to
media, structured supplement, caption and reaction views. This is dispatch coverage, not rendering/action parity. Text still drops
web-preview data; rich/game/story/checklist and detailed service actors/targets remain declared fallbacks. No excluded paid flow is added.
New A20/A21 evidence: `MessageContentView.swift` single dispatch (39–170), photo configure (304–310), album tile dispatch;
`ChatView.showMedia` (1837–1864), inline secret-video guard (2101); gallery caption concealment (329–440), action secret gates
(2042/2714/3144), owner PiP/range restrictions (4006–4019). TDLib `MessageContent.swift` documents spoiler/hold-only contracts
at 1097–1101, 1195–1199 and 1259–1263; `openMessageContent` appears only in video-note viewing. A10 also requires sanitizing
the parent cell's `accessibilityLabel` (MessageView 530–547), not just the child text view.
Reference: pinned current/pre-Liquid `ChatMessageInteractiveMediaNode.swift` detects secret/spoiler state (925/946 vs 923/944),
disables pinch shortcuts (2500 vs 2380) and overlays/conceals media (3094 vs 2948–2988); pre-Liquid lines 923–935 track secret
countdown state. These are source findings; no secret content was opened, sent, revealed or consumed on the user's account.

Initial timeline source pass — 2026-10-02 at `3b566dd`: `ChatVM` uses a raw oldest history ID (853–901), captured client/topic
history routing (3307–3335), album-ID merging and raw child-ID deduplication (3131–3172). `ForumTopicRun.swift` projects separate
message/album/date/topic identities; `ChatView` excludes headers from prefetch/read paths and captures prefetch client+generation
(432–460). Existing pixel anchors, self-sizing mutation depth and fresh scrolling guard (1538–1626) are positive source evidence.
A22 qualifies older claims that every snapshot avoids fighting active dragging: structural apply and asynchronous completion paths
remain exposed. Reference: pinned pre-Liquid `ChatHistoryListNode.swift` stationary-item transaction (4229–4238), and
`Display/Source/ListView.swift` tracking/deceleration state (297–304), deferred transaction state (2124–2194) and tracking-aware
inset repair (3180). Only behavior is referenced; do not port Display. No live pagination/drag proof is claimed by this source pass.

Initial account/list event pass — 2026-10-02 at `19a6f94`: `RootVM+Publishers.swift` resets folders on account notification
(8–17), but non-outcome subscriptions (18–61, 94–119) retain raw payloads. Chat/draft/last-message mutations (142–177) and
`refreshChat` (195–201) need accepted-event/RPC identity. `ChatVM+Publishers.swift` still has raw reaction/permission/topic/new-message
subscriptions: checking the current route alone cannot authenticate a queued event's source. `NotificationCenter.swift` raw helpers
defer delivery without carrying `TdUpdateSource`; A13's scoped helper already supplies the required captured transport seam.
Reference: pinned account-owned `AccountStateManager` streams and `PendingMessageManager` contexts cited for A13/A18 above.
This source audit confirms missing fences, not a live account-switch reproduction; existing account databases were not changed.

Composer/action source pass — 2026-10-02 at `bb01b8f`: edit dispatch/completion (`ChatVM` 1505–1536), edit payload
(2330–2402), semantic entity conversion (`Utils/Text.swift` 34–105), formatting menu and enabled/editable input were checked.
A24 can send an unrelated preserved draft or discard newer typing; A25 loses semantic formatting. Source references at the pinned
current/pre-Liquid SHAs: `ChatControllerLoadDisplayNode.swift` empty-edit return (2267–2283 / 2155–2171),
`TextFormat/Sources/ChatTextInputAttributes.swift` independent keys (12–29), `GenerateTextEntities.swift` (149–183 / 148–182).
Positive source checks: transition temporary/final/failure aliases, canonical album lookup, bounded cleanup and forward destination/
comment capture with ambiguous-result retry gating. P2 gaps: picker sticker/GIF dismisses before a source-cell snapshot reaches the
transition; slow draft-clear RPC can outlast the five-second snapshot lifetime. Photo partial-result semantics remain a proof gap,
not a reproduced partial-send defect. No live send, edit, keyboard or flight proof is claimed.

Profile/gallery source pass — 2026-10-02 at `d8ed16e`: member/admin pagination and tag authority, self/chat edit,
avatar roles/history/video visibility, shared-media pagination, gesture arbitration, rotation, source-transition identity and canceled
transition cleanup were reviewed. A27 permission gates occur in `PeerProfileControlsViewControllers.swift` (9–19, 1110–1118)
and `PeerProfileViewController.swift` (1017–1022, 1577); A28 late-error completion at 1151–1161. Pinned references:
`PeerInfoData.swift` current/pre (2395–2427 / 2158–2191), `TelegramCore/Sources/ApiUtils/TelegramChannel.swift`
(209–226 / 207–224), `GalleryControllerNode.swift` (561–618 / 491–559). TDLib `setChatTitle`/`setChatDescription`
require effective change-info permission; its async continuation does not itself cancel the underlying completion.
A20/A21 remain separate. No new gesture P0/P1 was confirmed by this source pass; runtime parity is not established.

Account/list/shell source pass — 2026-10-02 at `cf885b1`: account registry uses UUID directories and atomic saves; retirement
waits for client closure before deleting an explicitly removed account directory. Settings/login expose add/switch/logout; no such
operation was performed here. MainView chrome constraints span leading/trailing and safe-area top/bottom. A29 evidence:
`MainView.swift` 484–508, `FolderView.swift` 433–445/527–545 and `ChatFolderManagementViewController.swift` 383–392.
Pinned `ChatListController.swift` current/pre (1187 / 1961) mutates through its immutable account context (98 / 91).
A30 evidence: `BetterTGApp` 151–159, `TDLib` 124–166/348–378, `RootView` 43–46, RootVM Ready subscription and immutable
ChatVM location/client guard. Pinned `AccountContext.swift` current/pre (117–118 / 115–116) and `ApplicationContext.swift` 106
retain account-bound ownership. A19's new client-change stream revokes PiP correctly but does not rebuild retained chat routes.

A30 bounded production smoke on `b18da97`, audit Simulator, same PID `79320`: Saved Messages → idb HOME → tap observed
BetterTG icon returns the same chat. Identical hold→lock gesture produces no recording; Back→reopen then the same gesture shows
`Voice recording locked, 36.62`. Explicit Cancel removes only that agent-created control recording; recording store is empty, and
the older A26 orphan Ogg remains backed up. Captures: `.build/ui-probe-evidence/astra-a30-lifecycle`. A bounded idb log stream
yielded no app records and an idb Python timeout-cleanup diagnostic; it is not evidence of an app crash or a client-ID log.
No actual send, logout or account switch was used. Source tracing supplies the client-replacement cause; UI proves the gesture regression.
Profiles usually auto-pop on the later account-metadata notification and can return to the same stale chat; a permanent profile freeze
is not claimed.

Structured-action source pass — 2026-10-02 at `cf885b1`: contact detail/call, location snapshot/live label/external Maps,
file/audio reuse, poll/quiz restriction/selection/result/explanation paths, dice sticker/fallback, selected-message deletion,
reaction availability and pin-property refresh were traced to ChatVM/captured-client actions. A10/A20/A21/A23 remain applicable.
New A31 is confined to poll in-flight ownership (`MessageStructuredContentView` 56–112, `ChatVM.submitPollAnswer` 1046–1066).
Pinned pre-Liquid `ChatController.swift` 3409–3440 keys in-progress poll actions and their request lifetime by message. No SignalKit
is imported. This source pass does not prove every content's real rendering/action behavior; no polls or external apps were opened.

#### Range-waiter repair proof — 2026-10-02

- Scope: A01/A02 only. Preserve range planning, source/client ownership, finite fetch limits and cancellation generations. A fresh
  UUID identifies each waiter registration; sleep cancellation exits, and a delayed old callback cannot expire a replacement.
  Update-sequence checks cover size discovery, full-file fallback and range-prefix waits without losing an already-delivered update.
- One SwiftFormat invocation covered `TDLibVODRangeSource.swift`; `./build.sh build` passed without warnings in
  `.build/logs/xcodebuild/build-Debug-20261002-141955-60817-17803.log`. Independent diff review found no blocker.
- `./build.sh run --skip-build -- -media-probe-vod-ranges`, iPhone 17 Pro / iOS 26.5,
  `8108A92F-7E93-49C8-87F4-FA53A5A40A99`, PID `74821`: idb pulled
  `.build/ui-probe-evidence/astra-vod-range-probe.txt/vod-range-probe.txt`. It reports
  `deadline-token/rearm=true`, `update-before-wait=true`, existing cache/lookahead/coalescing/disjoint-seek/offline/exact-size and
  last-lease-revival checks passed. This is a deterministic production-source probe with injected file transport, not live Telegram VOD.
- Separate runtime blocker B01: after the probe, this existing Simulator process terminated with `EXC_BAD_ACCESS` in pinned TDLib
  `td::get_page_blocks_rich_message_media` → `RichMessage::parse` → `MessagesManager::parse_dialog` while loading its database.
  Report: `/Users/lev/Library/Logs/DiagnosticReports/BetterTG-2026-10-02-142322.ips`. The screenshot shows Home, so it is not a passing
  app-flow smoke. No database reset/removal was performed. Verify probes on an isolated Simulator and separately investigate this
  dependency/data compatibility failure; the original database remains unverified.

#### Isolated range and renderer-feedback proof — 2026-10-02

- Isolated iPhone 17 Pro / iOS 26.5 Simulator `BetterTG Astra Audit`, `59EB535C-3610-41A2-AB68-53A9467DC24B`,
  avoids B01 without modifying the original database. Each run used
  `./build.sh run --skip-build --simulator-id 59EB535C-3610-41A2-AB68-53A9467DC24B -- ARGUMENT` and idb.
  Login screenshots/hierarchies and live processes accompany the probe output; no account login or server mutation occurred.
- A01/A02 recheck at `37c8b44`, argument `-media-probe-vod-ranges`, PID `78859`: all existing range checks plus
  `deadline-token/rearm=true` and `update-before-wait=true` passed. Evidence:
  `.build/ui-probe-evidence/astra-isolated-vod-range-probe/vod-range-probe.txt` and
  `astra-isolated-vod-login-visible{.png,-hierarchy.json}`. The process remained alive after 89 seconds.
- A03 preserves `pause()`'s unconditional `setRate(0, time: .invalid)`, including cancellation of pending rate changes.
  `snapshotPublisher` deduplicates the full Equatable snapshot, retaining changes to clock/rate, generation, topology, queues,
  errors and finish state. The bounded asynchronous feedback probe receives exactly one settled paused snapshot.
- One SwiftFormat invocation covered `FFmpegSampleBufferRenderer.swift`; warning-free build:
  `.build/logs/xcodebuild/build-Debug-20261002-142824-79043-26845.log`. Independent diff review found no blocker.
- `-media-probe-vod-sample-buffer`, PID `79850`: `pause-feedback-events=1`, 24 video/101 audio buffers, stable pause,
  seek generation/preroll, stale drops, finish delivery, rate 1.5 and zero renderer errors passed. Output:
  `.build/ui-probe-evidence/astra-isolated-vod-sample-buffer-probe/vod-sample-buffer-probe.txt`;
  login screenshot/hierarchy: `astra-isolated-sample-buffer-login{.png,-hierarchy.json}`.
- `-media-probe-vod-ffmpeg-controller`, PID `80246`: pause/rate/offscreen intent, last-seek-wins, persistent rolling windows
  (11 windows, one open, zero rollover seeks), EOF, offline/retry/clamp and cleanup passed; finite ranges, zero full downloads
  and zero renderer errors. Output: `.build/ui-probe-evidence/astra-isolated-vod-ffmpeg-controller-probe/vod-ffmpeg-controller-probe.txt`;
  login screenshot/hierarchy: `astra-isolated-ffmpeg-controller-login{.png,-hierarchy.json}`. Process alive after 51 seconds.
  Fixture SHA-256: `685af512ee52d20c4aa20ef182d7d208df242d45b674f8e6fc2bbef91bfeb810`.
- These are deterministic production-source probes, not live Telegram message playback or system PiP proof. The controller
  fixture's slightly unequal track ends do not cover A04's materially different durations. B01 remains unresolved.
  Both Simulators remain booted; the smoke agent disconnected its owned idb session.

#### Animated decoder worker repair proof — 2026-10-02

- Scope: A07 only. Preserve first-frame fallback, existing frame timing/cache behavior and C-handle ownership. A native-free
  initializer creates the actor; `prepare`, frame reads/resets and `isolated deinit` run on its dedicated serial executor.
  Setup cancellation/generation/path/asset checks and frame decoder identity reject stale completion, including same-path reuse.
  A05/A06 account/download ownership and A08 timing are intentionally unchanged and remain open.
- Worker commit `c5642bc5b7b75210a467519b8e314a1cbaa4c801` was reviewed and cherry-picked as `3917128`.
  Only `FFmpegAnimatedVideo.swift` and one DEBUG entry in `BetterTGApp.swift` changed. Worker SwiftFormat covered both files;
  warning-free build log is preserved in the primary checkout at
  `.build/logs/xcodebuild/worker-A07-build-Debug-20261002-143909-89115-12760.log`.
- Worker run on isolated Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iOS 26.5, PID `92196`, remained alive for 51 seconds
  on production login. Preserved evidence: `.build/ui-probe-evidence/astra-worker-a07/animation-worker-probe.txt`,
  `astra-animation-login.png` and `astra-animation-login-hierarchy.json` in that directory.
- Primary integration: one SwiftFormat call covered all four Swift files changed during the audit repairs (`0/4` changed).
  `./build.sh build` passed without warnings at `3917128`; log
  `.build/logs/xcodebuild/build-Debug-20261002-144312-3881-1967.log`. Independent delta review found no blocker.
- `./build.sh run --skip-build --simulator-id 59EB535C-3610-41A2-AB68-53A9467DC24B -- -media-probe-animation-worker`
  launched PID `4465`. Fresh container `E53CD086-9694-41C8-89CD-F27E033BC0A3` output was written at
  `2026-10-02 14:43:47 +0400`; idb pulled it into
  `.build/ui-probe-evidence/astra-integrated-animation-worker/animation-worker-probe.txt`.
  Both runs report actual create/read/reset/destroy off-main, main-release/worker-destroy, delayed-setup cancellation,
  same-path reuse fencing, replacement readiness, preserved first frame and exactly-once teardown; five native reads.
- Integrated screenshot/hierarchy `astra-integrated-animation-login{.png,-hierarchy.json}` show the live production 2FA screen,
  not a chat/sticker flow. The user subsequently reported logging into the open Simulator; no credentials were entered by the agent.
  On resume, inspect current authorization/reachable chats before selecting authenticated smoke. This user update does not close
  B01 for the original database or prove sticker playback. The later explicit continuous-work request authorizes further slices.

#### Voice lifecycle preservation proof — 2026-10-02

- A11 scope: navigation/permission teardown stops capture and preview without calling explicit discard. Main-actor registration
  retains canonical PCM/trim/adoption work and makes a reopened account/chat/topic route await it. A lifecycle generation rejects
  pre-suspension permission/resume/send/trim-audio continuations even after UI re-enablement. A forced teardown trim save never
  starts preview audio. Recording and send storage formats, route/reply/caption/waveform/revision contracts remain unchanged.
- Independent delta review identified the reopen barrier, stale intent revival and forced-trim autoplay gaps; all three were
  repaired. A12–A14, video lifecycle A15 and system interruption handling are not claimed fixed by this slice.
- One SwiftFormat invocation covered the five changed Swift files. Final warning-free `./build.sh build` log:
  `.build/logs/xcodebuild/build-Debug-20261002-150301-32416-21283.log`; no warnings/errors in the full output.
- `./build.sh run --skip-build --simulator-id 59EB535C-3610-41A2-AB68-53A9467DC24B --
  -media-probe-voice-preservation -ui-smoke-voice-gestures`, iPhone 17 Pro / iOS 26.5, PID `36834`.
  The user-authorized Simulator reaches real Saved Messages. The deterministic barrier/epoch probe reports restore-waits,
  canonical-revision, account-isolation, barrier-cleanup, suspend-invalidates-intent, reenable-keeps-old-intent-invalid and
  new-intent-allowed. Output: `.build/ui-probe-evidence/astra-voice-preservation-final-probe/voice-preservation-probe.txt`.
  This tests production coordination primitives, not an injected full ChatVM PCM-save race or live rights mutation.
- Production idb flow: hold→lock→pause, trim `0…21.0189435044s`, Back→reopen and wrapper relaunch all retain the same local
  draft `A4895271-1B10-484A-BD3D-8A7D74D60BB9`, media filename and edit revision 1. Sorted canonical manifest SHA-256 after
  Back and relaunch: `63d4ca98ab895c0f2013986a48f564e5c4b03edb45ed7f6a6e128b3c3ab9abd2`.
  Evidence: `.build/ui-probe-evidence/astra-voice-after-{back,relaunch}/`, `astra-voice-after-relaunch.png` and filtered hierarchy.
  The final build again restored trim `0:00.0…0:21.0` with Play, not active playback. Reply was nil; reply preservation is source-only.
- A second real hold→lock followed by Back during capture produced paused `27.6s` preview after reopen, not a continuing recorder.
  Manifest/WAV `5753F35D-1BE7-43F6-8713-C20DE301B67B` were present; proof is in
  `.build/ui-probe-evidence/astra-voice-active-back/` and `astra-voice-active-back.png` (visually inspected).
  Explicit Cancel/Delete removed each agent-created draft and WAV; the recording-draft directory was empty after both deletions.
  No messages were sent, no chat rights changed, no user drafts removed, no database reset and no Simulator shutdown occurred.

#### Accepted TDLib update provenance proof — 2026-10-02

- A13 worker `1eb9d23c75a335defd5a2df2274d9b6dc2504aaa` was independently reviewed and integrated as `c356513`.
  `TDLib.handle` captures account UUID/client ID into immutable notification userInfo; `td.py` generates exactly one post with
  unchanged name/raw object. Opt-in scoped subscribers extract payload/source before scheduler delivery and reject missing source.
  Voice/video durable cleanup and selected-document ownership use event account; ChatVM/forum UI additionally match frozen client.
  All 15 subscribers of send-success/send-failure/delete in these five consumers were migrated; legacy subscribers remain compatible.
- Worker warning-free build: `.build/logs/xcodebuild/worker-A13-build-Debug-20261002-152038-71499-21293.log`.
  Primary SwiftFormat covered all 11 changed Swift paths in one invocation (`0/10` changed, generated file excluded by config).
  Primary build passed without warnings in `.build/logs/xcodebuild/build-Debug-20261002-152748-427-24895.log`; generated output
  stayed unchanged after wrapper regeneration. The first primary attempt stalled before compilation while clang wrote to its
  SDK-discovery pipe; only that owned xcodebuild was interrupted, then the unchanged wrapper retry passed in 11s. Diagnostic:
  `.build/ui-probe-evidence/astra-a13-build-diagnostic/clang-81316.sample.txt`. No cache or Simulator reset was used.
- Wrapper launch on authorized Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iOS 26.5, PID `1577`, with
  `-media-probe-update-source`: `.build/ui-probe-evidence/astra-integrated-update-source/update-source-probe.txt` reports generated
  dispatch, delayed A→B delivery, colliding-ID isolation, old-client UI rejection, same-account durable ownership, unscoped rejection,
  exactly-once raw legacy payload and permanent-delete guards all passed. The real Saved Messages row remains accessible by idb.
- Probe scope: real generated dispatcher and Combine transport with an isolated NotificationCenter/in-memory consumers. It does
  not switch real accounts, touch user stores or exercise TDLib server outcomes. Production subscriber migration was source-reviewed.
  The existing active-client gate still drops callbacks arriving after a switch; safe inactive-client outcome recovery remains open.
  A12 route/temporary-ID matching, A14 finalization leases and A18/A19 VOD/PiP are unchanged.

#### VOD main-track and duration-authority proof — 2026-10-02

- A04 worker chain `23b1e49` → `61bb5e3` → `e87ef9c` was independently reviewed and integrated as
  `83103ba` → `14a01c5` → `ef8f4ba`. C selects explicit video end before audio, clips the longer audio tail and preserves persistent
  windows/final video frames. Explicit duration travels to Swift separately from container estimates. At real EOF, observed frame
  ends resolve estimates in either direction; initialized seek cursors cannot invent media duration. Verified terminal summaries
  cancel both watchdogs. An unknown end with no observed main frame or explicit metadata fails safely, not with a fabricated EOF.
- Reference: pinned current/pre-Liquid `MediaPlayer/Sources/ChunkMediaPlayerDirectFetchSourceImpl.swift` chooses `video ?? audio`
  (546/578 current, 547/579 pre-Liquid). No decoder, player-clock, queue/cache/lease architecture or dependency version was replaced.
- Native before/after evidence: `.build/ui-probe-evidence/astra-a04-native/` and `astra-a04-fallback/`, including harness, pinned
  fixtures, source snapshots and commands. Host FFmpeg 9.0.2 proves video 2s/audio 10.008s ends at 2s with all 20 video frames;
  missing-video-duration container estimates 8s/20s both resolve to 12s with all 144 frames, seek 11s begins at 11s, and seek 25s
  emits no frames but observes true EOF at 12s. Longer-video/shorter-audio, origin, standard and audio-only regressions passed.
  These host runs are not Apple media-clock proof.
- Worker final warning-free log: `.build/logs/xcodebuild/worker-A04-build-Debug-20261002-152136-73961-20174.log`.
  Primary one-call SwiftFormat covered four changed Swift files (`0/4` changed); warning-free `./build.sh build` at `ef8f4ba`:
  `.build/logs/xcodebuild/build-Debug-20261002-153032-2363-12736.log` (18s).
- Authorized iPhone 17 Pro / iOS 26.5 Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, wrapper/idb only:
  PID `2903` with `-media-probe-vod-main-track -media-probe-vod-ffmpeg-decode` passed both. Main-track output is
  `.build/ui-probe-evidence/astra-integrated-vod-main-track/vod-main-track-probe.txt`; decoder output is
  `astra-integrated-vod-decoder/vod-ffmpeg-decode-probe.txt`. Explicit 2s EOF and known/initial seek 6→2s, both estimate variants,
  seek 25→12s, persistent sessions, cleanup and bounded queues passed. Decoder retained 24 VP9 frames/101 Opus buffers,
  95,641 stereo sample frames, monotonic PTS, 3 persistent pumps/one open/zero rollover seeks, sparse unequal-track handling,
  cancellation/supersession, SWR drain and close-waits.
- PID `3401` with `-media-probe-vod-ffmpeg-controller`: `.build/ui-probe-evidence/astra-integrated-vod-controller/`
  `vod-ffmpeg-controller-probe.txt` reports stable pause, rate 1.5, offscreen cancellation/intent, last-seek-wins, 10 persistent
  windows/one open/zero rollover seeks, EOF, offline/retry/clamp and zero renderer errors, plus every new main-track assertion.
  idb still sees the real Saved Messages row afterward. No sends, account switch, data reset or Simulator shutdown occurred.
- Proof limit from independent delta audit: mixed-metadata fixture is 84,225 bytes, below the 2 MiB range fetch. Auto-fulfillment plus
  `limit != 0` proves finite request shape, not playback before the complete small file is cached. Existing lookahead still treats
  fallback duration as authoritative; no controller blocker was proven because original decodeStart and actual accepted frames
  advance playback independently after the initial scan. Follow-up: reconcile lookahead duration authority and test >2 MiB media
  with unavailable/delayed tail ranges, seek beyond an estimate and explicit incomplete-byte-coverage assertions. Live Telegram
  streaming and active system PiP remain unverified; do not promote this bounded proof to global VOD parity.

#### A04 cold partial-file playback and pre-metadata buffering — 2026-10-03

- Base `4f9b3d6`; reviewed `TDLibVODFFmpegSampleBufferPlayer`, range source/DEBUG transport and new
  `TDLibVODPartialCoverageProbe`. Existing small-file proofs remain valid within their limits. A new native AVAssetWriter
  fixture contains 24s of actual H.264 video (480×270/15fps), 13,324,774 bytes, not padding around a tiny clip. Generation and
  hashing run off main with one pixel buffer at a time. TDLib availability is injected into the real range source/FFmpeg/player.
- Confirmed P2: `updatePlaybackGate` returned before current decoder metadata existed. Initial lookahead can wait on missing
  seek bytes before that metadata arrives, so `.preparing` never became `.buffering`. PID47925 reproduces
  `preparing → failed`, no buffering, and the 12s no-video watchdog. The fixture deliberately withheld tail bytes until buffering;
  this is evidence of the missing state transition, not evidence that delayed downloads always fail in production.
- Repair is a guard split only: for a current prepared/open/error-free renderer, missing metadata schedules the existing
  generation-fenced 300ms transition when playback is requested, visible and has a decode task. No decode/range/seek-completion
  or renderer-readiness rule is relaxed. Pause/offscreen/seek/close cancellation is retained. Reference: current official
  `6ad963e5` and pre-Liquid `8e7e5fef`, `MediaPlayer/Sources/ChunkMediaPlayerV2.swift:599–613,708–722`: unavailable/new direct
  reader is buffering; display delay is 0.3s. TDLib remains pinned to `022d6020`; real transport contracts remain
  `downloadFile(offset/limit)`, `getFileDownloadedPrefixSize`, `updateFile` and `cancelDownloadFile`.
- Native PASS PID54595 at 04:40:26 +04, audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iOS26.5:
  display-ready playback reached 0.3468s with 5,852,379/13,324,774 cached bytes and the second half unavailable. Seek18s
  requested `10206788..<12303940`, stayed buffering without completing, respected 400ms pause and 400ms offscreen intervals,
  then made a new request on visibility return. Revealing the requested range plus a source update resumed display-ready playback
  at 18.237s with 8,970,365 cached bytes, still incomplete. Six nonempty finite in-file requests, no full-download call, drained
  transport/cancellation and temporary-file cleanup. Unique coverage is a union, not an overlapping-range sum.
- Preserve failed fixture evidence: PID42870 first reproduced the missing transition without detailed failure logging;
  PID47925 captured the watchdog/state sequence. After the guard fix, PID50903 passed buffering/resume but failed an incorrect
  DEBUG `limit <= 2MiB` assertion: existing fetchPlan intentionally extends overlapping ranges. The corrected assertion checks
  nonzero finite in-file bounds, with incomplete coverage checked independently. No production fetch policy was changed.
- Existing FFmpeg controller/main-track regression PASS PID55178: pause/rate/offscreen/last-seek, persistent 10-window/one-open
  session, EOF, offline/retry, explicit short-video end, under/overestimated duration and beyond-EOF clamp; zero renderer errors.
  Real root list was visible after teardown (`after-controller.png`). No sends, account switch, reset, Simulator focus activation
  or shutdown. Saved results: `.build/ui-probe-evidence/astra-a04-partial-coverage/`.
- One three-file SwiftFormat invocation, wrapper build `build-Debug-20261003-043953-54182-14840.log` PASS6s; complete log has
  zero warnings/errors. Independent read-only review accepted production guard, actual prefix-gated file reads, teardown and
  proof limits. This proves injected availability with real native decoding/display readiness; not live TDLib/server delivery,
  A/V sync for the large video-only fixture, physical hardware or active PiP. Reveal + update jointly precede recovery; this
  does not isolate updateFile as the sole wakeup rather than timeout/refetch. Lookahead estimate authority remains open.

#### Exact media-draft delivery and client streams — 2026-10-02

- A12 worker `2ccdb9b` integrated as `847b838`: `ChatDraftDeliveryKey` freezes account/chat/send topic independently of the
  owning UI route. Stores reject simultaneous enqueue by either route or delivery, require a unique outcome candidate and consume
  early evidence only after exact temporary-ID registration. Registration is persisted before cleanup; arbitrary-ID fallback is
  removed. Legacy account binding preserves the base route. Existing JSON contracts and recording-origin ownership remain intact.
- Reference: pinned current/pre-Liquid `TelegramCore/Sources/State/PendingMessageManager.swift`, account-owned manager
  (218/251 current; 213/239 pre-Liquid), immutable message request ID (192/187), pending-ID contexts (409/258), thread context
  (640/462). TDLib 1.8.66 `updateMessageSendSucceeded/Failed`, `oldMessageId`, delivered `Message.topicId`; no infrastructure port.
- Primary one-call SwiftFormat covered all eight files (`0/8` changed); warning-free wrapper build:
  `.build/logs/xcodebuild/build-Debug-20261002-153825-17942-30766.log` (9s). Worker log is preserved with `worker-A12-` prefix;
  scope/commands/limits are in `.build/ui-probe-evidence/astra-a12-worker/README.md`.
- Safe Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, wrapper PID `18527`, `-media-probe-draft-outcomes`:
  `.build/ui-probe-evidence/astra-integrated-draft-outcomes/draft-outcomes-probe.txt` passed voice+video, ordinary/explicit/all-messages
  early/late success/failure, original route, wrong account/chat/topic/ID, duplicate old manifests, both enqueue gates, exact-ID
  relaunch, unresolved pre-registration crash, legacy base-route migration and unrelated draft/file preservation.
  This uses real store methods and disk manifests in disposable UUID directories with synthetic media bytes; no server sends.
- A18 worker `b2e33d2` integrated as `76f9998`: every activation owns separate file/delete subjects with immutable account/client
  provenance. Retained publishers cannot follow later account/client replacement. Bootstrap remains inert; A13 and the active-client
  gate are unchanged. All three deletion consumers were source-checked. The sole cherry-pick conflict retained both DEBUG probe hooks.
- Reference: pinned current/pre-Liquid `AccountStateManager.swift` (322–324/308) and `ChatListSearchListPaneNode.swift` (4814/4650)
  use account-owned deletion streams. TDLib `updateFile`, `updateDeleteMessages`; range clients and numeric-ID API stay unchanged.
- Primary one-call SwiftFormat covered all three A18 files (`0/3` changed); warning-free wrapper build:
  `.build/logs/xcodebuild/build-Debug-20261002-154003-19429-13561.log` (11s); worker log preserved with `worker-A18-` prefix.
- Integrated PID `20467`, `-media-probe-client-streams -media-probe-update-source -media-probe-draft-outcomes`: all passed.
  `.build/ui-probe-evidence/astra-integrated-client-streams/client-streams-probe.txt` reads distinct real 64-byte files through retained
  A/B/replacement-client range coordinators with identical file IDs and observes isolated deletion subscriptions. Own-stream byte arrival
  is the ordering barrier; unexpected backend fetch fails. Stale/nil provenance and bootstrap events are rejected.
  `astra-integrated-client-provenance/update-source-probe.txt` repeats A13 generated-dispatch/delayed-delivery proof;
  `astra-integrated-client-drafts/draft-outcomes-probe.txt` repeats A12 on the combined product. Real Saved Messages remained visible
  before installs; no account switch, user-store reset, message send or Simulator shutdown occurred.
- Limits: isolated stream/store probes are not live multi-account server delivery or active system PiP. Legacy voice/video codec probes
  were updated and compiled but not rerun here; the new probe avoids their shared-store cleanup paths. Crash before exact ID registration
  preserves an unresolved enqueue, not automatic recoverability. A14 canonical finalization ownership, callbacks rejected by the inactive
  client gate, A15–A17 video lifecycle and A19 restoration remain open.

#### Canonical voice finalization and PiP context proof — 2026-10-02

- A14 worker `a8d04c2` integrated as `bb01b8f`. Six Swift files formatted together; warning-free primary build
  `.build/logs/xcodebuild/build-Debug-20261002-155910-46801-26110.log` (14s). Worker log is copied with `worker-A14-` prefix;
  design and proof limits: `.build/ui-probe-evidence/astra-a14-worker/README.md`.
- Voice store claims canonical runtime ownership before encoding, fences stale snapshots/tokens, uses unique attempt outputs and
  persists the accepted temporary ID before UI-generation checks. Native cancellation is joined before ownership release; preflight
  failures can retry, ambiguous post-RPC failures retain unresolved ownership. Metadata/delivery contracts and A12 gates stay intact.
  Current/pre-Liquid `ChatControllerMediaRecording.swift` (344–356, 735–760 / 354–366, 735–766) and
  `PendingMessageManager.swift` (218–251, 409–438 / 213–239, 258–282) anchor preserved ownership and captured send context.
- Audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone 17 Pro/iOS 26.5, PID `47929`:
  `-media-probe-voice-finalization -media-probe-draft-outcomes` passed. Results in `astra-a14-primary/voice-finalization-probe.txt`
  and `astra-a14-draft-regression/draft-outcomes-probe.txt` under `.build/ui-probe-evidence`. Real native Ogg encoding, suspended
  worker/RPC gates, duplicate claim/discard rejection, stale token/adoption, exact-ID outcome, pre-registration retention,
  process-local lease recovery and unrelated-file preservation run against disposable isolated stores. This does not send messages.
- Production UI on `bb01b8f`: empty recording/send stores; own hold→lock→pause yielded a 42.06s preview. The existing DEBUG
  `-ui-smoke-voice-preview-send` bypassed the send RPC after real promotion/encoding. Own draft
  `CDD62EC0-0614-4481-B007-119AD74DD113` became `isEncoded=true`, duration 42, no enqueue time/temp ID. Manifest SHA256
  `bbf6973377392f25435894ca0bf6423deb279d1600cb2261b597cca8021b6fe4`; captures and manifest/Ogg backup are in
  `astra-a14-ui`. The no-send alert intercepted Back, so navigation-during-encode is not claimed by this UI sequence.
- Reinstall to combined `d8ed16e` changed the container from `CC9310EE…` to `D630B63A…`; the loader deleted this manifest,
  left the Ogg, and restored an empty composer. `before-relaunch`/`after-relaunch` plus `restored.png` reproduce A26. This is a
  pre-existing absolute-URL persistence defect, not passing relaunch proof. Only an agent-created draft was affected; no user draft
  was deleted. Its backup remains available for recovery and the follow-up test. Recording-preview relative storage is separate.
- A19 worker `1ea2594` integrated as `d8ed16e`. Five Swift files formatted together; warning-free primary build
  `.build/logs/xcodebuild/build-Debug-20261002-160148-52841-23853.log` (20s); worker log copied with `worker-A19-` prefix.
  Freeze playback client/location/ranges/deletion stream, preserve route callbacks separately, rebind only the originating profile
  tab, revoke on every client activation, and bound each restoration completion to one terminal callback. Revoked pending/active
  PiP retains its controller through the stop barrier. References: pinned `UniversalVideoGalleryItem.swift` current context
  734–754/restoration 889/retained navigation 3150–3214; pre-Liquid 938–958/1093. No Telegram infrastructure was copied.
- Combined PID `55486`, `-media-probe-pip-context -media-probe-gallery-owner -media-probe-voice-finalization
  -media-probe-draft-outcomes`: all passed. `astra-a19-context/pip-context-probe.txt` covers frozen topic/nil-topic authority,
  same owner/view, route loss, same/changed-tab pagination, account/client replacement, pending/active stop, no stale reattach and
  exactly-once completion. `astra-a19-owner/gallery-playback-owner-probe.txt` repeats real AVFoundation/FFmpeg owner handoff,
  range/session continuity and lifecycle/adapter checks; voice/draft regressions are in `astra-a19-voice-regression` and
  `astra-a19-draft-regression`. Probe context uses injected client identity; actual TDLib action transport and real
  `activate(notify:false)` are source-reviewed, not server/lifecycle-exercised. `pip-supported=false`: active system PiP still
  requires a capable device. Marker scan over production/dependencies is empty; no Simulator shutdown or account reset occurred.

#### Edit-mode safety proof — 2026-10-02

- A24 worker `8aa914f` integrated as `b18da97`. Primary reviewed the entire policy/probe and all edit-session assignment sites.
  `ChatVM` dispatches explicitly between ordinary/invalid-edit/edit, captures the message/formatted payload, and checks session,
  text revision, task cancellation and current location after request completion. Closing Edit preserves the ordinary reply;
  newer typing or a reopened same-ID session survives an old success/error. Semantic entity conversion A25 remains unchanged.
- Six Swift files formatted in one invocation; warning-free primary wrapper build
  `.build/logs/xcodebuild/build-Debug-20261002-161023-77945-13703.log` (10s). Worker log copied with `worker-A24-` prefix;
  `.build/ui-probe-evidence/astra-a24-worker/README.md` preserves scope and reference notes.
- Same authenticated audit Simulator, PID `79320`: `-ui-probe-composer-edit -media-probe-voice-finalization
  -media-probe-draft-outcomes` all pass. Results are under `.build/ui-probe-evidence/astra-a24-primary`, `astra-a24-voice`,
  `astra-a24-drafts`. Edit probe executes the production submission/token policy with suspended callbacks: zero ordinary sends
  for invalid edit, immutable payload, A→B→A revision, same-ID reopen, caller completion-delivery fence, cancellation, unchanged
  success and empty media caption. It uses counters and fixtures, not a real ChatVM, keyboard, selected-attachment view or TDLib
  server edit. Production wiring/disabled action is source/build-proved only. No account data or messages were changed.

#### Send-draft relocation and list-action authority proof — 2026-10-02

- A26 worker `2e28fad` integrated as `8519b33`; five changed Swift files formatted together. Primary wrapper build
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
  as `5a87726`, corrects only fixture filenames and diagnostic stages; production ownership validation is not relaxed.
  One Swift file formatted; warning-free build `build-Debug-20261002-162317-68150-27789.log` (8s). PID `71109` repeats A26/A12
  successfully in `astra-a26-final-relocation`/`astra-a26-final-drafts`. Historical failure output is retained.
- Production recovery uses only own draft `CDD62EC0-0614-4481-B007-119AD74DD113`: restore its backed-up legacy JSON beside
  the still-existing Ogg, then open Saved Messages. Retry appears and canonical loading migrates the reference to a filename.
  All metadata except the intended URL change matches the backup; Ogg SHA256 remains
  `c05b255f8c03e0983da8cecef40a4777cdc9dbf08b2b29033b8b3d9d69d0ae33`. Another wrapper install (`5a87726`, PID `71109`)
  preserves identical relative JSON/Ogg and shows Retry. Long-press → **Discard Voice Message**, not Retry, removes this own
  draft through production UI. Send/recording voice stores are then empty and the mic returns. Recoverable backups, migrated
  and reinstalled files/captures: `astra-a26-ui` under `.build/ui-probe-evidence`. No message was sent or user draft removed.
  Real video reinstall remains unverified; the isolated video store probe is not camera/server proof.
- A29 worker `7513376` integrated as `15f146f`; six Swift files formatted together. Primary warning-free wrapper build
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

#### Effective group profile permission proof — 2026-10-02

- A27 worker `1a78906` integrated as `b0db39f`; primary reviewed both production controllers, shared policy/authorization and
  complete probe. Basic-group admins keep all applicable rights; ordinary members use default `canChangeInfo`; restricted
  supergroup members require membership and both effective/default rights. Supergroup admins retain allowed member rights;
  broadcast channels still require creator/admin authority. Self-profile editing is unchanged; owned-bot editing is not added.
- Fresh `getChat` + `getChatMember` on appearance closes a real entry gap: ChatVM's live permission cache does not update
  `CustomChat.chat.permissions`. Capability state owns its own source/revision, consumes only scoped permission/group updates,
  and rejects an older refresh after a rights event. Unrelated title/photo metadata no longer owns capability state. Each title
  and description write independently rereads permission and verifies source/actor/returned IDs; a revoked second write is
  blocked while existing partial-success handling is preserved. Server authorization remains authoritative; these reads are not
  an atomic permission transaction.
- References: pinned current/pre-Liquid `PeerInfoData.swift` 2395–2427/2158–2191 and
  `TelegramCore/Sources/ApiUtils/TelegramChannel.swift` 209–226/207–224. TDLib `022d6020` `Chat.permissions`,
  `ChatMemberStatus`, `ChatPermissions`, `setChatTitle` and `setChatDescription` contracts were checked directly.
- All five Swift files formatted together; warning-free primary wrapper build
  `.build/logs/xcodebuild/build-Debug-20261002-164302-10912-6908.log` (10s). Worker proof README is copied to
  `.build/ui-probe-evidence/astra-a27-worker/README.md`, build log with `worker-A27-` prefix.
- Audit Simulator, PID `11755`: `-ui-probe-profile-info-permissions` passes 25 policy cases, fresh appearance capability,
  scoped live changes/stale refresh, per-write revocation, wrong account/client/actor/chat, cancellation and delayed completion.
  Result: `.build/ui-probe-evidence/astra-a27-primary/profile-info-permissions-probe.txt`. Production helpers run against
  suspended injected reads/writes; no real profile controller permission change or server save is claimed.
  A29/A12/A26/A14/A24 regressions all pass in `astra-a27-list`, `astra-a27-drafts`, `astra-a27-relocation`, `astra-a27-voice`,
  `astra-a27-edit`. No real profile/account/message mutation. Marker scan remains empty; A32 visual chrome remains open.

#### Foreground root-list restoration proof — 2026-10-02

- A30a worker `b8d8432`/`469bad4` integrated as `0820359`/`c5d3f8b`. Accepted-source readiness clears on activation/background;
  obsolete clients cannot announce readiness. Navigation replaces only opted-in Main entries for the same account, with exact
  stack/source/generation checks and transition/modal deferral. RootVM must already match the account; its scheduled update retries
  restoration. Account switches and unrelated route objects retain their existing handling. Notification-service ownership is unchanged.
- Main carries selected folder, search query/focus and per-folder chat-ID/pixel anchors. Restore waits for current diffable completion
  and usable layout; newer query/drag invalidates it. Fresh folder object identities rebuild children without resetting their viewports.
  Chat, ForumTopics, Archive and already-open folder editors are deliberately not rebound; A30 remains open there.
- References: pinned current/pre-Liquid `ChatListUI/Sources/ChatListController.swift` 4039–4093/3969–4019 selected-filter preservation
  and 4676–4700/4620–4646 content-ready search; BetterTG adapts these contracts to UIKit/TDLib client epochs.
- All ten initial Swift files formatted together; primary build `build-Debug-20261002-164821-26680-8524.log` passed (19s).
  Model-ready follow-up formatted both files, build `build-Debug-20261002-165126-73786-13702.log` passed (9s), both without warnings.
  Earlier `build-Debug-20261002-164734-18341-15729.log` records a premature build of an unresolved App-hook cherry-pick conflict;
  both hook registrations were retained before these clean builds. Worker logs have `worker-A30a-`/`worker-A30a-model-` prefixes.
- Authenticated audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone 17 Pro/iOS 26.5, PID `74615`, `c5d3f8b`:
  `-ui-probe-client-restoration` passes readiness, A1→A2→A3/stale/account/stack/transition/model fences, retained chat identity,
  production UIKit viewport capture/restore, prepend/missing/clamp and delayed-layout/query/drag checks. Result in
  `.build/ui-probe-evidence/astra-a30a-primary`; six prior permission/action/store/edit regressions pass in `astra-a30a-regressions`.
- Production smoke: scroll groups → HOME → app icon; same PID, selected group folder and visible peer-row Y positions preserved.
  Long-press group tab → Edit Folder opens the real authority-gated editor; Back without Save. A second cycle preserves the own empty-result
  search query and focus: typing `7` without another tap appends to the restored query. Software keyboard stays hidden; no keyboard-layout
  claim. Own search was cleared with Close. Visually inspected captures under `astra-a30a-ui`: `groups-scrolled.png`,
  `groups-restored.png`, `folder-editor-restored.png`, `search-before-background.png`, `search-restored.png`;
  `search-restored-typing.png` plus AX readback records retained first-responder input. No real message/folder/account mutation.

#### Single video capture finish-owner proof — 2026-10-02

- A17 worker `6809716` integrated as `e8a0eb1`. Capture contexts carry immutable preparation generation and one manual/automatic
  finish owner through native completion and MainActor delivery. Duplicate/competing manual Stop returns nil; it cannot convert an
  automatic success into failure cleanup. Cancellation/replacement cleans only undelivered owned output; a delivered asset survives
  later capture cancellation. Missing callback cleans its own output. Recorder tasks clear only their operation token; accepted
  automatic finish fences late start/duration/stopping updates, including the preparing/Record More interval.
- Reference: pinned current/pre-Liquid `Camera/Sources/VideoRecorder.swift` 367–376 reserves stopped state before finishing and
  delivery; `LegacyInstantVideoController` guards completion/dismissal. A15 preservation and A16 consumed-preview ownership are unchanged.
- Five Swift files formatted together; primary warning-free build
  `.build/logs/xcodebuild/build-Debug-20261002-165751-81511-11272.log` (23s). Worker final log copied with `worker-A17-` prefix;
  `.build/ui-probe-evidence/astra-a17-worker/README.md` records its scope.
- Audit Simulator, PID `1196`, `e8a0eb1`: `-media-probe-video-note-finish` passes actual capture-session finish/cancel methods with
  a real H.264/AAC writer. Suspended native-finish and delivery windows cover competing/duplicate Stop, cancellation, replacement,
  missing callback, exactly-once error and retained transferred output. Actual recorder operation helpers cover stale cleanup and
  late preparing/start/duration/stopping. Result and seven A30a/A27/A29/A26/A12/A14/A24 regressions all pass under
  `.build/ui-probe-evidence/astra-a17-primary`. Fixtures are isolated; asset move simulates adoption, not the production store transfer.
  Hardware camera/microphone, full-duration limit, physical gestures, real adoption and server send remain unverified.

#### Composer-transfer foundation and video-preview handoff proof — 2026-10-02

- A30b1 worker `946dc02` integrated as `ef558ec`. An in-memory value snapshot separates ordinary compose/edit/reply/quote intent
  from mutable CustomMessage objects; images/documents retain IDs. One-shot transfer requires exact account/chat/topic (nil remains
  distinct), a new current client and unchanged quiescent owner state. Cancel/mismatch/failed retirement retains old ownership;
  commit synchronously retires it before constructing the new owner. ChatVM seeds local dirty intent before publishers/server draft
  hydration and fences retired location use/deinit file deletion/Media dismissal. No persistent schema or TDLib API change.
- Navigation does not yet call this factory. Active/pending voice/video/send/import-sensitive work must stay excluded until its
  ownership barriers are implemented; ordinary-controller picker/transition checks belong to A30b2. Before enabling replacement,
  navigation must accept the transaction before irreversible retirement and process Main plus Chat in one ready cycle.
- References: pinned current/pre-Liquid `ChatInterfaceState/Sources/ChatInterfaceState.swift` 513–523/514–524 and 612–618/565–571
  separate compose/edit/reply/media state. Four Swift files formatted together; primary build
  `.build/logs/xcodebuild/build-Debug-20261002-171549-4184-7097.log` passed without warnings (16s).
  Worker final log copied with `worker-A30b1-` prefix. Audit Simulator PID `4968`: `-ui-probe-composer-restoration` passes actual
  value/transfer/lifetime helpers, isolated selected files, account/topic/client fences, unchanged/busy/cancelled/reentrant state,
  failed-retirement retry, detached mutable message and old-deinit cleanup=0/new-owner cleanup=1. Five readiness/edit/media regressions
  pass beside the result in `.build/ui-probe-evidence/astra-a30b1-primary`. No actual ChatVM construction in this probe:
  seed order and production cleanup wiring are source/build proof only, not foreground Chat recovery.
- A16 worker `44c2c35` integrated as `a72d93b`. Recorder reuses enqueued cleanup when retained result says `originConsumed=true`:
  clear local ownership and dismiss, leaving retry/discard with composer. Cancel during submission cannot discard the transferred
  file; only its obsolete error is suppressed. Unconsumed local preview/Cancel and send-store removal tombstones are unchanged.
- References: pinned current/pre-Liquid `LegacyComponents/Sources/TGVideoMessageCaptureController.m` 1109–1115/1113–1119
  and `LegacyInstantVideoController.swift` 215–257/216–258 transfer capture into outgoing resource ownership. Three Swift files
  formatted together; primary build `.build/logs/xcodebuild/build-Debug-20261002-171743-5488-28712.log` passed without warnings (8s).
  Worker final log and README preserved with `worker-A16-` prefix and `.build/ui-probe-evidence/astra-a16-worker/README.md`.
- Audit Simulator PID `6029`, `a72d93b`: `-media-probe-video-note-submission-ownership` passes six actual offscreen-recorder
  scenarios with isolated VideoNoteFileStore and native MP4 fixtures. Consumed-retained, Cancel during submit, stale navigation result
  and enqueued paths preserve canonical media/manifest through obsolete Cancel/deinit; retry acquires ownership and exact temporary-ID
  registration succeeds. Unconsumed preview and pending Cancel still delete the local asset once. Seven A17/A30b1/A30a/A24/A14/A12/A26
  regressions pass under `.build/ui-probe-evidence/astra-a16-primary`. No real messages sent, user stores changed or capture hardware
  started. Persisted-recording materialization, ChatVM submit RPC and live gestures remain unverified. Marker scan is empty.

#### Profile shared-history request identity — 2026-10-02

- A28 `9cdc6b0` adds per-request authority independently of the selected filter. Tab change invalidates it before cancellation;
  every success/error/cancellation path consumes only its own ID before touching the task or UI. Existing account/client/tab checks,
  pagination cursor, deduplication, gallery retry and query semantics remain intact. No network cancellation guarantee is assumed.
- Reference: pinned `PeerInfoVisualMediaPaneNode.swift`, current 1726/1792 and pre-Liquid 1660/1725, scopes and replaces history
  subscriptions; TDLib `022d6020` `SearchChatMessages` topic/filter/from-message contracts checked directly. No Telegram infrastructure copied.
- Three Swift files formatted together; primary warning-free wrapper build
  `.build/logs/xcodebuild/build-Debug-20261002-172655-9917-30165.log` (10s). Audit Simulator PID `10397`:
  `-ui-probe-profile-history-request` passes production token helper checks for A→B→A late success/error/cancel, busy replacement,
  current exactly-once completion, invalidation and retry. Results plus A27/A16/A17/A30b1/A30a regressions are under
  `.build/ui-probe-evidence/astra-a28-primary`. The controller's success/catch/reset wiring is source-reviewed; the probe does not
  construct a real profile, delay a TDLib RPC or exercise tab gestures. No real account/profile/message changes.

#### Terminal navigation-plan acceptance — 2026-10-02

- A30b2 prerequisite worker `1584f4d` integrated as `1f47005`. Preparation owns no transferred files; the coordinator rechecks
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

#### Poll submission attempt ownership — 2026-10-02

- A31 `b7de6ee` gives each accepted vote attempt an immutable token. The queued RPC checks that token and current route before
  sending; failure and deadline callbacks may clear only their own attempt. A stale callback neither cancels the replacement
  deadline nor publishes a misleading idle state. Authoritative selection changes invalidate old attempts; retry keeps local choices.
- Reference: pinned pre-Liquid `submodules/TelegramUI/Sources/ChatController.swift:3422–3430` owns per-message poll requests;
  `ChatMessagePollBubbleContentNode` reflects current in-progress selections. TDLib `022d6020` `SetPollAnswer` uses message/chat
  identity and zero-based option IDs. No Telegram infrastructure copied or network cancellation guarantee assumed.
- Three Swift files formatted together; warning-free primary build
  `.build/logs/xcodebuild/build-Debug-20261002-174113-33012-16805.log` (10s). The preceding sandboxed attempt could not connect to
  CoreSimulator; the same wrapper succeeded with host access, without changing or resetting a Simulator.
- Audit Simulator PID `36667`, `-ui-probe-poll-submission`: actual store, registered deadline and already-running deadline callback
  tests pass for timeout/retry/late failure, A→B→A authoritative reset, exact replacement timer ownership, no stale notifications,
  pending-choice preservation and duplicate completion. A28/A30b1/terminal-navigation regression probes also pass in
  `.build/ui-probe-evidence/astra-a31-primary`. ChatVM wiring is source-reviewed; no real vote or delayed server RPC was performed.

#### Video-note navigation finalization and join — 2026-10-02

- A15a worker `64c47dc` integrated as `bafdde8`: navigation registers an exact account/chat/topic barrier synchronously, freezes
  capture input and joins the sole manual/automatic finish owner. A UI-independent finalizer owns native output → canonical
  recording adopt/append; ChatVM waits before reading drafts. Existing draft/reply/topic/revision survives failed append.
  Explicit Cancel remains destructive; Cancel/state callbacks from a detached preserved recorder cannot reclaim the restored draft.
- Capture state carries its original generation; old callbacks cannot revive dismissed UI. Native terminal failure settles the
  join. The fixture originally named navigation-then-background actually injected capture failure; A15b1 below corrects that name
  and separately tests background preservation. This historical slice alone did not preserve the new segment on background.
  No changes to `InputMessageVideoNote`, send/outcome manifests or TDLib delivery matching.
- References: pinned current `VideoMessageCameraScreen.swift:457–483` waits for stop result; current/pre-Liquid Legacy capture
  output handoff at 1109–1116/1113–1120 and interruption completion at 1349–1356/1353–1360. ChatController foreground handling
  at current 6857–6872/pre 5963–5978 calls `stopMediaRecorder`; `Chat/ChatControllerMediaRecording.swift` 460–480/470–487 selects
  preview for active audio/video. Legacy's separate background observer at 190–198 dismisses. Source does not establish callback
  ordering or universal deletion; on-disk/process-death recovery is a separate BetterTG durability policy.
- Primary first build `.build/logs/xcodebuild/build-Debug-20261002-174405-45697-8734.log` passed without warnings (25s).
  Initial runtime failed before its first finish gate: `recordingUnavailable`, then timeout. Diagnostics `843fde6`/`3e49c9d`
  bounded the failure and exposed ownership. Fixture correction `d34eeb3` (worker `4a224e7`) loads the real recorder view before
  installing capture, matching production `beginCapture`; its gate also reports an early terminal result instead of hanging.
  The exact prior cancellation cause is unproved. No production workaround was added to make the fixture pass.
- Final primary build `.build/logs/xcodebuild/build-Debug-20261002-180134-71658-8387.log` passes without warnings (9s).
  Audit Simulator PID `72550`, `-media-probe-video-note-preservation`: all eight actual-recorder/native-H264-AAC/store cases pass
  for manual/auto ownership before/after finish, pending append, stale-revision failure, explicit Cancel, route isolation and later
  capture failure (original output called it background termination). Evidence: `.build/ui-probe-evidence/astra-a15a-primary`;
  initial timeout/sample and the original output are retained there.
  No user store, real recording, camera permission or server send was touched. Physical capture, rapid-navigation gestures,
  suspension grace time and process death remain unverified.

#### Chat restoration history/import foundation — 2026-10-02

- A30b2 worker `760f8cc` integrated as `6aa7ce4`. Detached display values preserve raw source IDs, album members, presentation
  metadata and pagination cursor without mutable wrappers or in-flight mutation flags. Reconciliation rebuilds albums by source ID.
  A separate raw latest cursor bridges toward the seed; it does not jump directly to the old history cursor.
- At most four reads run per batch, with visible seed IDs first. Source/generation and per-message revision checks bracket metadata
  hydration and delivery; permanent deletion tombstones prevent resurrection. Partial reactions/pins do not establish that a stale
  body is current: invalidated reads stay unresolved for explicit retry. Full accepted messages satisfy superseded reads. Latest-page
  tokens reject stale/replayed/reentrant delivery. Errors never auto-poll or imply deletion.
- Exact missing result verified in pinned TDLib `022d6020`: `Requests.cpp:592–607` → `Td.cpp:1392–1407` yields 404 `Not Found`.
  Other errors retain a retryable seed. Import tokens allow one local completion into a retained same-account route before retirement;
  removed/cross-account/retired owners reject it. None authorizes a send on an obsolete client.
- Four Swift files formatted together in the worker; primary combined build
  `.build/logs/xcodebuild/build-Debug-20261002-175112-65343-2137.log` passes without warnings (11s).
  PID `66007`, `-ui-probe-chat-restoration-state` passes value/album/cursor, import and suspended read/hydration/token checks with
  zero server reads/sends. Repeated at `d34eeb3`, PID `72550`. Evidence: `.build/ui-probe-evidence/astra-a30b2-state-primary` and
  `astra-a23a-primary`; worker README/log copied separately. Existing pinned ChatInterfaceState references apply.
  Chat navigation is still disabled; live history, file-import controllers, anchor/focus and shared same-epoch update ordering need wiring.

#### Root/list account and client authority — 2026-10-02

- A23a `e1d295e` routes typed RootVM list/chat/user/unread/settings updates through accepted source checks at main delivery.
  Folder unread uses the event's client ID. List reads capture one client for every nested chat/user/group/folder RPC and check
  account/client plus root ownership epoch before publication. Full folder loads and per-chat refreshes also have request IDs;
  a detached folder cannot receive a pending append. Durable document outcome/delete handlers are unchanged.
- Legacy void auth notifications only wake a current-state read; they no longer blindly set the new account's logged-in flag.
  This does not migrate every authorization/topic subscriber or solve all same-client field-update races.
- Reference: current/pre `ChatListUI/Sources/Node/ChatListNode.swift` retains AccountContext at 1216/1213 and 1397/1391;
  current history subscription at 1934 uses that account. TDLib `getChats/getChat/getUser/getSupergroup/getBasicGroup/getChatFolder`
  and existing generated scoped update transport remain unchanged. No Telegram infrastructure copied.
- Five Swift files formatted together; primary warning-free build
  `.build/logs/xcodebuild/build-Debug-20261002-180056-69882-3475.log` (9s), after correcting a missing Foundation import.
  Integrated `d34eeb3`, PID `72550`: `-ui-probe-root-list-authority` passes actual ticket/scoped-delivery checks for delayed
  A→B, replacement client, unscoped event, A→B→A request epoch and mismatched owner. Five A30b2/A31/A29/A30a/A30b1 regression
  results pass in `.build/ui-probe-evidence/astra-a23a-primary`. Real RootVM/RPC wiring is source-reviewed; no real account switch,
  delayed server response or account/list mutation was performed.

#### Chat update delivery and integrated regression — 2026-10-02

- A23b `df9eb7a` (worker `6c43e20`) binds 20 ChatVM typed subscriptions to their accepted account/client and exact chat/topic.
  Five asynchronous new/sent/failed/message/reference hydration paths recheck that authority and the nonretired owner before
  publication. Durable send outcomes, deletion transport and local recording-store notifications retain their existing ownership.
  Same-client body/partial/delete ordering and actual Chat foreground restoration remain separate work.
- Reference: the pinned current/pre Telegram AccountContext ownership and A13 accepted-update contract above; generated TDLib
  update models, `getMessage` and captured-client metadata reads are unchanged. No server mutations or account switches exercised.
- Four changed Swift files formatted together; primary build `.build/logs/xcodebuild/build-Debug-20261002-180630-74419-20491.log`
  passes without warnings (9s). On the audit Simulator, installed `df9eb7a`, PID `75292`, actual generated dispatcher and observer
  probe passes queued A1→A2, A→B→A3, colliding IDs, missing origin, retired owner, route/topic and late callback checks.
  This is an isolated observer test, not delayed live ChatVM/TDLib network proof.
- The same launch passes Root authority, A16 video submission ownership, A13 update source, A12 draft outcomes, A30b2 history/import
  and A31 poll attempt probes. Separate `d34eeb3`, PID `73141`, passes A17 native video-finish regression.
  Evidence: `.build/ui-probe-evidence/astra-a23b-primary` and `astra-a15a-primary/video-note-finish-probe.txt`.
- Production Root/Main smoke on `df9eb7a`: selected `groups`, entered own query `232323`, Home→app icon, observed the same query
  and selected folder, then typed `7` without another focus tap; AX and screenshot show `2323237`. Closed search and verified the
  empty placeholder. Screenshot: `astra-a23b-primary/root-search-foreground.png`. Software keyboard was hidden; text focus was
  demonstrated by input, not by keyboard pixels. This does not prove restoration of an open Chat or a real account switch.

#### Animated file transport authority — 2026-10-02

- A05a `128ada2`: all three TGS/WebP/FFmpeg views use one configured request with captured account/client/file identity.
  Scoped notifications check the accepted origin at main delivery; download/cancel closures retain the original client.
  Client replacement retires the request and view. Asset/frame callbacks check request identity, current source and path;
  canceled same-file reuse cannot install an old decode. Thumbnails use the existing explicit-account/client loader.
  Complete files issue no teardown cancellation. Native worker ownership, alpha, caches and timing remain unchanged.
- This is deliberately partial: callers still capture the active client at configure. An old asynchronous consumer can pass an old
  File into a new configure; the next slice makes originating clients explicit through custom emoji, timeline, picker and gallery.
  Shared visible/prefetch download demand (A06) is not implemented by this request wrapper.
- Reference: pinned pre-Liquid `AnimatedStickerNode/Sources/AnimatedStickerNode.swift:288–291,348–424` owns its source subscription,
  disposes/replaces it and gates playback by visibility. TDLib pinned `downloadFile` documents immediate non-synchronous state plus
  `updateFile`; `cancelDownloadFile(onlyIfPending:true)` only cancels a pending request. No Telegram infrastructure imported.
- Six Swift files formatted together. Final build `.build/logs/xcodebuild/build-Debug-20261002-182359-89980-13950.log` passes without
  warnings (11s), after correcting unused-result and weak-reference diagnostics. Simulator PID `91050`, built from this exact source,
  passes `-media-probe-animation-authority`: isolated actual request/notification path, colliding/foreign/unscoped/wrong-file updates,
  queued account replacement, same-file reuse, late RPC, captured cancel and deinit cleanup. Backend closures are fixtures; no TD calls.
  A07 native worker regression and A23 Chat/Root probes also pass in `.build/ui-probe-evidence/astra-a05a-primary`.
  This does not prove real sticker playback, account switching, or all consumer origins.

#### Video lifecycle preservation and animated consumer origins — 2026-10-02

- A15b1 `8b42052` (worker `2b45d35`): background/camera/audio interruptions join the immutable capture finalizer, stop input and
  preserve the canonical recording. A per-capture background lease ends once; expiration cancels only a matching unadopted writer,
  never an accepted store save. Repeated events cannot renew the lease. Foreground restores only the retained route/generation to
  paused preview; it cannot restart capture/playback or revive a navigation-detached owner. Initial background state is respected.
- Review caught `.sending` being set before asynchronous export. The fix checks lifecycle epoch immediately before `onSubmit`,
  removes only its own export/thumbnail and retains the recording; an already invoked `onSubmit` is not canceled. Explicit Cancel
  remains destructive. References are the pinned current/pre ChatController→stopMediaRecorder→preview paths in A15a above.
- Four Swift files formatted together; integrated build `.build/logs/xcodebuild/build-Debug-20261002-182819-4794-15394.log` passes
  without warnings (10s). Exact product `8b42052`: PID `6152` lifecycle probe passes 11 recorder/native-writer/private-store scenarios,
  pending preparation, background→foreground during real export, accepted suspended submit, immediate expiry and canonical cleanup.
  Separate launches pass A15a navigation (`7592`), A17 native finish (`19855`), A16 submit ownership (`23359`). Evidence:
  `.build/ui-probe-evidence/astra-a15b1-primary`; worker source/build notes in `astra-a15b1-worker`.
  Lifecycle inputs/background backend are injected; no user stores/sends, hardware capture, real OS suspension/expiration,
  audio-notification delivery or process-death recovery were tested. Voice background/intent ownership remains A15b2.
- A05b `6e5b287` requires an explicit originating client in AnimatedFileView, custom emoji, timeline text/reactions/dice,
  composer stickers, topic icons and gallery cells. The dynamic repository overload is removed. Gallery's existing video owner
  remains usable without reconstructing a client; a new animation cannot fall back to global `td`. Reuse clears thumbnail pixels.
  Fifteen Swift files formatted together; build `.build/logs/xcodebuild/build-Debug-20261002-183343-25876-8180.log` passes without
  warnings (15s). PID `31000` passes animation-authority, native A07 and PiP-context regressions in `astra-a05b-primary`.
  Independent read-only A05a/A05b delta review found no new blocker. Actual multi-account animation/view-decode races, shared demand
  and nonanimated/static-image client plumbing remain outside this bounded proof.

#### Shared production history revisions — 2026-10-02

- A30b2 phase 1 `da59789` (worker `4c9142a`) wires the history ledger into ordinary ChatVM and the optional seeded constructor.
  Complete accepted messages install their body before metadata awaits; one four-message lane hydrates metadata. Partial updates,
  permanent deletion and source retirement invalidate older reads. Reaction/pin owners retain their wrapper until both settle.
  Normal pagination checks the same token at synchronous merge. Prepared windows carry only fetched values and an unconsumed token;
  actual installation rechecks revisions and merges current messages, preserving intervening updates instead of overwriting them.
- Restored latest history advances on raw pages, then filters exact topic for rendering. Ready/manual retry is event-driven,
  including one deferred event during batch/latest RPC; a plain failure never loops. Confirmed missing history removes display state
  only; durable recording/send outcomes and file cleanup still require their accepted TD updates. No storage schema changes.
- References: pinned ChatInterfaceState/history restoration and exact TDLib `getMessage` 404 path recorded above; captured-client
  `getMessage/getChatHistory/getMessageThreadHistory` and generated update models. Source review caught prepared-window admission
  before its actual install and sender updates missing a bare message; both were corrected before integration.
- Four Swift files formatted together; primary build `.build/logs/xcodebuild/build-Debug-20261002-183613-37316-13873.log` passes
  without warnings (33s). `da59789`, PID `41056`, `-ui-probe-chat-restoration-state` passes actual ledger/cursor cases: live body,
  partial-before-body/during-hydration, deletion, shared page token, overlapping mutation owners, deferred Ready/error/cancel and
  foreign-topic raw bridge. A23 Chat/Root, A31 poll and animation-authority regressions pass in
  `.build/ui-probe-evidence/astra-a30b2-production-primary`. Worker notes/logs are preserved separately.
- Probe read/hydration closures are isolated: actual ChatVM constructor, ordinary timeline and delayed TDLib transport still need
  production smoke. ChatView restoration is not enabled; the controller must transfer a quiescent composer/history, settle its
  one-shot pixel anchor, then start freshness. Raw unresolved reply/forward dependencies, A22 scroll interaction epochs and other
  secondary-route restoration remain open. This phase is production wiring, not a complete A30 claim.

#### A06 animated-file demand — 2026-10-02

- `09fa140` replaces per-view transport cancellation with `AnimatedFileDemand`, keyed by originating account UUID, client ID and
  file ID. TGS/WebP/WebM views and animated prefetch acquire the same whole-file demand. Releasing one view or cancelled prefetch
  cannot cancel another registered consumer. The last release cancels only the pending download through its captured client.
  A replacement starts after the previous cancellation reply; a not-yet-cancelled start can instead be shared. Completed files,
  released owners and failed prefetch waiters leave no retained pool entries after their last lease. No cache/storage schema change.
- Scoped `updateFile` revisions outrank delayed initial-state RPC replies. Review caught queued terminal updates being dropped
  while cancellation was scheduled but not yet issued. The final code distinguishes scheduled/in-flight cancellation and replays
  both completed and inactive-failure state when cancellation is abandoned. Those exact races are now explicit regressions.
- References: pinned current/pre `FetchManagerImpl/Sources/FetchManagerImpl.swift` 779–823 (episode-scoped priority/reference
  acquisition and release), adapted without Telegram infrastructure. TDLibKit `downloadFile(offset:0,limit:0,synchronous:false)`
  plus accepted `updateFile` and `cancelDownloadFile(onlyIfPending:true)`. Shared animated demand uses priority 2; static `.none`
  prefetch remains at priority 1. VOD range ownership is deliberately separate: different offset/limit would supersede a TD request.
- Five Swift files formatted together. Final build `.build/logs/xcodebuild/build-Debug-20261002-185806-60504-4167.log` passes in
  6s, zero warnings. Initial DEBUG-only actor-isolation compile failure was corrected before this build. Audit Simulator
  `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone 17 Pro / iOS 26.5, installed source `09fa140`, PID `60930`:
  `-media-probe-animation-demand`, `-media-probe-animation-authority` and `-ui-probe-chat-restoration-state` all pass. Results:
  `.build/ui-probe-evidence/astra-a06-primary`. Parent and independent delta reviews completed, including the terminal-race repair.
- Demand tests run actual production pool/request code with isolated suspended transport and notifications: duplicate visible
  owners, deinit, cancelled prefetch, pending start reuse, delayed cancel/reacquire, queued completion/failure, stale initial reply,
  client replacement, pre-start cancellation, completed cache and explicit retry. No server calls or user stores. Actual three-view
  decode callbacks/TDLib scheduler, nonanimated downloads and cross-arbitration with VOD ranges are not established by these probes.

#### A30b2 quiescent Chat controller — 2026-10-02

- `494bf56` (worker `7f98a52`) enables the existing terminal navigation replacement for ordinary Chat. Captured target-client
  metadata, account/chat/topic and retained-route checks precede synchronous composer/history ownership transfer. Imports, marked
  text, modal/context menus, gestures, capture/send operations and timeline transitions defer replacement. Paste/Photos/camera/files
  register import ownership before asynchronous work; same-account results can finish on a retained old-client route.
- Selection, focus and mic/video mode transfer separately. The retired text view resigns only its own responder; the new controller
  restores one message ID + pixel offset after snapshot, appearance, layout and keyboard settlement, then starts history freshness.
  User scroll/input invalidates this initial anchor. A22 general timeline epochs and active capture restoration are not repaired here.
- Primary follow-up `9495f0a` adds the missing explicit retry after emoji-picker Done or invalid-context dismissal. UIKit's
  interactive presentation delegate does not cover that programmatic completion. Foundation probe labels now state that those
  probes do not exercise controller navigation. A DEBUG-only, content-free log identifies actual viewport settlement.
- References: pinned current `ChatInterfaceState/Sources/ChatInterfaceState.swift` 232–270 and pre-Liquid 514–531, distinct
  compose/reply/edit/history/media state and message-index-relative offset. TDLib captured-client `getChat/getForumTopic/getMessage`,
  chat/thread history and accepted ready/update source; no new server mutation or storage schema.
- Primary builds: `.build/logs/xcodebuild/build-Debug-20261002-190318-62891-1540.log` (12s), combined voice build
  `build-Debug-20261002-190401-63298-26208.log` (11s), final picker fix `build-Debug-20261002-192208-71024-31859.log` (7s), all
  zero warnings after each slice's single SwiftFormat invocation. Sandbox-only CoreSimulator access failed; authorized wrapper retry
  succeeded without resetting data. Source review also corrected first-responder retirement before integration.
- Audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone 17 Pro / iOS 26.5: source `fe5de21`, PID `64668`, actual
  Saved Messages retained latest and settled non-latest viewport plus empty-composer caret after Home→foreground. The initial
  non-latest screenshot preceded deceleration and is not anchor proof; the repeated settled pair is visually consistent, without an
  automated pixel-error measurement. Software keyboard was hidden by the hardware-keyboard setup.
- At `9495f0a`, PID `71481`, open emoji-picker survived Home→foreground; Done returned the actual chat. At 19:26:46 the same
  process logged `Chat client restoration: viewport settled; fresh history starts`. No emoji selection, text input, attachment,
  send or account switch. Screenshots and state probe: `.build/ui-probe-evidence/astra-a30b2-controller-primary`; worker notes are
  separate. Chat state/composer foundation and A06 authority/demand probes pass; their isolated transports are not network proof.
- Pending: interrupted real provider imports, nonempty edit/reply/attachment transfer, software-keyboard transitions, active voice/video,
  ForumTopics/Archive/editors, live account switches and delayed server-history races. Full A30 remains partial.

#### A15b2 voice lifecycle checkpoint — 2026-10-02

- `15871f5` (worker `f12e3d1`) separates interaction, background and audio-interruption suspension. Clearing one reason cannot
  revive another or an older permission/trim/resume/preview/send intent. Background pauses preview and checkpoints the canonical
  PCM/trim/promotion owner. One bounded UIKit time assertion is exact-once, including immediate expiration; expiration does not
  cancel canonical persistence. Foreground does not resume capture, playback or sending automatically.
- `fe5de21` (worker `0251285`) fixes a primary-review finding: background must not wait on upload-action/reply-validation network
  preflight. The checkpoint marker ends when encoded canonical media is durable, before network awaits. A task captured while still
  encoding sees its invalidated send epoch and retains the draft. Accepted RPCs still register their actual temporary ID and retain
  their files. Fallback closed-segment promotion now keeps the route barrier through CPU/store completion. Storage formats unchanged.
- References: pinned current/pre `TelegramUI/Sources/ChatController.swift` 6857–6872 / 5963–5978;
  `Chat/ChatControllerMediaRecording.swift` 460–480 / 470–487 (stop into preview);
  `ManagedAudioRecorder.swift` 448–455 and 522–560 (session deactivation and Ogg pause/resume). Durable disk policy is BetterTG's
  adaptation; source does not establish Telegram observer ordering or identical process-death behavior. TDLib send/reply preflight
  and returned message-ID registration retain the earlier A12/A14 contracts.
- Four worker Swift files and combined nine-file primary set formatted before their builds. Primary combined build
  `.build/logs/xcodebuild/build-Debug-20261002-190401-63298-26208.log`: PASS 11s, zero warnings; follow-up build above also clean.
  On the audit Simulator, sources `fe5de21` / `9495f0a`, PIDs `64668` / `71481`, `-media-probe-voice-lifecycle` and
  `-media-probe-voice-finalization` pass. Proof: `.build/ui-probe-evidence/astra-a15b2-primary`; worker notes/logs retained separately.
- Native isolated proof uses real PCM16/48kHz trim/concatenate, Ogg codec and private recording/send stores: independent reasons,
  route barrier, duplicate/expired assertion, stale intent, failed append, explicit discard, metadata and accepted-ID ownership.
  It neither instantiates a real ChatVM nor emits OS audio notifications/server RPCs. Real microphone/interruption/process suspension,
  ChatVM's suspended network preflight and actual accepted send remain unverified; this does not close those runtime gaps.

#### A08 actual animation timeline — 2026-10-02

- `863de36` (worker `25c412d`) replaces nominal capped FPS/count with native decoded PTS and actual EOF. Binary search selects
  frames; missing/backward/duplicate timestamps fall back to the previous decoded end. The last decoded duration determines loop
  end. Native non-EOF read errors no longer count as EOF. Existing pixel-read missing-PTS zero behavior is preserved.
- Timing-only scan is coalesced by full path/inode/size/mtime through weak ownership, runs off-main, checks cancellation around
  native reads, and publishes only a complete index. Bounds: 65,536 frames / 512KiB charged to existing asset cache, 10s between
  native calls. One native call cannot be interrupted by that deadline. Last-waiter cancellation serializes native teardown and
  restart; primary review added cancellation recheck at continuation registration and a deterministic regression for that race.
  Failed/over-budget scans retain the first-frame fallback; pixel cache limits are unchanged. Device energy/latency remain unmeasured.
- References: pinned current/pre `MediaPlayer/Sources/SoftwareVideoSource.swift` 213–227 and
  `AnimatedStickerNode/Sources/VideoStickerFrameSource.swift` 343–351,409–420. This does not claim Telegram renders at uncapped
  nominal 60FPS. TDLib animated-file demand/API is unchanged. Native EOF is not universal truncated-container integrity proof.
- Primary 14-file integration SwiftFormat, build `.build/logs/xcodebuild/build-Debug-20261002-193037-75193-27184.log`: PASS16s,
  zero warnings. Audit Simulator source `2bf7428`, PID `75703`: `-media-probe-animation-timing` passes real pinned-iOS decode
  of VFR4-frame GIF, 120-frame60FPS and 660-frame22s WebM, nonzero origin, one frame and zero/under/over metadata duration;
  actual last/first pixel frames, EOF wrap, bounded-index fallback, shared cancellation/restart and pre-registration cancellation.
  A06 demand/authority pass. Separate launch source `10b23c5`, PID `78753`: A07 worker create/read/reset/destroy/reuse probe passes.
- Proof: `.build/ui-probe-evidence/astra-a08-primary`; worker host-native FFmpeg9.0.2 evidence remains separately labelled in
  `astra-a08-worker`. No real sticker feed/TDLib download/UI playback/performance claim; no user stores or server writes.

#### A10 text, caption and accessibility spoilers — 2026-10-02

- `2bf7428` (worker `f5c69bd`) adds display-only concealment. Immutable account/client/chat/source-message and exact formatted
  payload own cell-lifetime revelation; edit/reuse/source replacement invalidates callbacks. Hidden glyph/link/code/custom-emoji
  ranges stay concealed, first tap reveals, second may activate. Non-actionable bold/italic no longer swallows a later link action.
  Actual glyph hit testing excludes padding/status. Hidden custom emoji is not requested; generation checks fence old first frames.
- Body and audio/document album captions share the reveal contract, with independent member states. Parent and text-view AX use
  redacted labels; text-view value is explicitly empty. Reply/quote previews stay concealed while retaining navigation/expand.
  Chat summaries redact only the formatted segment, preserving attachment prefixes. Draft/write values and global formatter unchanged.
- The first integrated iOS probe failed on a split surrogate: `Range(NSRange,in:)` accepted an inner UTF-16 index. `10b23c5`
  validates start/end scalar boundaries explicitly, rejects overflow and split pairs, retains valid combining-scalar ranges, and
  fails malformed spoilers closed across nonempty text. Both split-start/end and valid full-emoji/combining cases now pass. The
  initial failing result is retained; a warning-free build alone did not catch it.
- References: pinned current/pre `ChatMessageTextBubbleContentNode.swift` 177–188,1202–1205 / 197–206,1119–1121;
  `InteractiveTextNodeWithEntities.swift` 350; `ChatMessageReplyInfoNode.swift` 486,503,880–891 / 458,475,801. TDLib pinned
  `FormattedText/TextEntity` uses UTF-16 ranges; source models and send contracts remain intact. A20 media concealment is separate.
- Final two-file SwiftFormat + build `.build/logs/xcodebuild/build-Debug-20261002-193330-78095-31536.log`: PASS9s, zero warnings.
  Audit Simulator source `10b23c5`, PID `78753`, `-ui-probe-text-spoilers`: PASS actual UIKit glyph layout/action dispatch,
  unchanged reveal geometry, parent/child AX, reply/quote/summary, independent state/reuse/source gates and emoji admission.
  Proof `.build/ui-probe-evidence/astra-a10-primary`; worker notes separate. Actual emoji decoding, full album layout and live
  spoiler-message touch/VoiceOver smoke remain unverified. URL/clipboard actions were captured, not executed; no server writes.

#### A23c forum-topic delivery — 2026-10-02

- `78f0f8a` routes all eight ForumTopicsVM typed subscriptions through the existing `ChatUpdateDeliveryAuthority`. Queued old
  account/client updates cannot mutate current same-ID topic info or start a current-client refresh; unscoped events are rejected.
  Captured chat/topic and current-owner gates remain. Pagination/topic read starts now recheck context before issuing the captured
  RPC; existing post-await generation/context guards remain. No UI, cursor semantics, query order or storage format changes.
- References: current/pre `ChatListUI/Sources/Node/ChatListNode.swift` immutable account context at 1216/1213 and
  `chatListViewForLocation(...account:context.account...)` at 1934/1939. TDLib pinned `ForumTopicInfo` and generated
  updateForumTopicInfo/updateForumTopic/message content/edit/delete/send models, `getForumTopics/getForumTopic`.
- Two Swift files formatted together; `.build/logs/xcodebuild/build-Debug-20261002-193919-80905-8514.log`: PASS8s, zero warnings.
  Audit Simulator source `78f0f8a`, PID `81496`: expanded `-ui-probe-chat-update-delivery` passes actual generated topic-info
  dispatcher plus production observer admission for queued A→B, colliding chat/topic IDs, replacement client, missing source,
  another chat and retired owner. Root authority, text spoilers and Chat restoration-state regressions pass in
  `.build/ui-probe-evidence/astra-a23-forum-primary`.
- Probe isolates subscribers/owners; it does not construct ForumTopicsVM, send server mutations or switch real accounts.
  Actual topic-list UI and delayed server RPC ordering are unverified. Auth/static-image subscribers, same-epoch read ordering
  and A30 ForumTopics route replacement remain separate work.

#### A09 inline Apple-container animation — 2026-10-02

- `e9b536b` (worker `fb65e3c`) routes native `messageAnimation` through the existing gallery playback owner. Inline and gallery
  transfer the same view/layer/AVPlayerItem with attachment tokens. All visible eligible animations loop silently; ordinary videos
  keep largest-visible-area selection. Offscreen loaded media pauses; pending completed-file demand cancels and retries on visibility.
- Owner construction now requires originating context; file-player configuration requires an explicit range coordinator. Thumbnail
  loading receives captured account/client. Client replacement revokes owners; animation background gates do not reauthorize them.
  Kind/fileID/editDate checks reject stale media owners. Caption-only edit may conservatively restart the same file's item.
- Pinned TDLib `Animation` has no `supportsStreaming`; this slice waits for a completed-file lease and does not claim early MP4
  animation playback. Prefetch uses thumbnails, never source MP4 as an image. Secret/spoiler animations fail closed to static
  minithumbnail pending A20/A21; ordinary-video spoiler remains open. FFmpeg GIF/WebM routes remain distinct.
- References: pinned current/pre `ChatMessageInteractiveMediaNode.swift` 1989–2029 / 1966–2006 and visible attachment
  2166–2175 / 2097–2106; `AccountContext/Sources/UniversalVideoNode.swift` 143–168;
  `TelegramUniversalVideoContent/Sources/UniversalVideoContentManager.swift` 161–235;
  `GalleryUI/Sources/Items/UniversalVideoGalleryItem.swift` 1575 / 1697. No upstream player infrastructure copied.
- Five Swift files formatted together; primary `.build/logs/xcodebuild/build-Debug-20261002-194359-83221-25084.log`: PASS15s,
  zero warnings. Audit Simulator source `e9b536b`, separate launches: inline-animation PID `83851`, gallery-owner PID `84406`,
  PiP-context PID `84924`. All three pass; files in `.build/ui-probe-evidence/astra-a09-primary`, worker notes/logs separate.
- New probe creates private native H.264 media and real production owner/MediaGalleryCell/LocalMediaPlayer: two loop boundaries,
  silent same-item/layer handoff, stale tokens, offscreen pause/resume, pending full-download cancellation/retry and context revocation.
  Range backend/current-source events are isolated. Gallery regression preserves finite ranges/FFmpeg continuity and source factory;
  PiP-context regression preserves stop/restore authority. Active system PiP remains unsupported on this Simulator and unproved.
- No server calls, camera/OS-interruption events, user stores or account switches. Real authenticated MP4-GIF scrolling, transport,
  no-flash gallery gestures and device energy remain unverified. Secret/spoiler reveal, partial-file animation playback and seamless
  caption-only edits are explicitly outside this bounded result.

#### A23d static-image update delivery — 2026-10-02

- `ba0e192` captures the active account/client before the default `TDImageLoadingView` file subscription. It consumes the
  generated scoped envelope and validates both event source and current source after main-queue delivery, before decoding.
  Existing request-generation, decode-completion, thumbnail/cache behavior and explicit-client load path remain unchanged.
- References: the pinned current/pre account-bound media reference recorded for A05/A09; pinned TDLib `File/updateFile`
  and generated `TdScopedUpdate` transport. Numeric file IDs are client-local, not cross-account authority.
- Both changed Swift files formatted together; build `.build/logs/xcodebuild/build-Debug-20261002-195308-87219-10047.log`:
  PASS10s, zero warnings. Audit Simulator, source `ba0e192`, PID `89171`, expanded `-ui-probe-chat-update-delivery`: PASS.
  Actual production observer plus generated dispatcher rejects queued old-client, foreign account with colliding file ID,
  missing source, wrong file ID and cancelled subscriptions; current-source delivery survives.
  Readback: `.build/ui-probe-evidence/astra-a23-image-primary/chat-update-delivery-probe.txt`.
- This isolated proof does not instantiate an image view, decode pixels, download files or switch real accounts. Explicit
  origin propagation to legacy callers, static-image shared-demand cancellation and auth delivery remain separate gaps.

#### A25 composer semantic entities — 2026-10-02

- `a022017` (worker `7b58988`) separates composer entity identity/payloads from visual attributes. Explicit scoped Swift/UIKit
  bridges and semantic fallbacks retain code/pre/language, quotes, links, mentions, custom emoji and dates across unrelated edits.
  UTF-16 scalar bounds reject overflow/split surrogates; decorative crossing ranges split into nested TDLib output. Independent
  bold/italic toggles preserve both traits. Adjacent emoji identities remain separate. Eight ChatVM import sites cover edits/captions/drafts.
- Only manual input entity types are exported; detected URLs/email/phone/mentions remain plain text for TDLib parsing. External
  RTF accepts visual traits and supported explicit links, not arbitrary background colors or private identity attributes. Paste
  commits marked text and blocks route replacement until synchronous mutation settles. Link alerts reject changed source values.
  Display formatting/A10, send-attempt authority and persistence formats remain unchanged.
- First integrated runtime failed: a UIKit caret move restored underline into typing attributes. `fb15c25` refreshes sanitized
  typing attributes on selection/text callbacks, matching pre-Liquid input-panel timing. Start/interior/end insertion, deletion
  and neighboring semantic spans now pass; the initial failure is preserved, not relabeled as success.
- References: pinned current/pre `TextFormat/Sources/ChatTextInputAttributes.swift` 12–25,100–139,1048–1095 / 13–25,1040–1055;
  `StringWithAppliedEntities.swift` 30–56 / 30–54; `GenerateTextEntities.swift` 149–183 / 148–179;
  `ChatPresentationInterfaceState/Sources/ChatTextFormat.swift` 6–98. Pre `TelegramUI/Sources/ChatTextInputPanelNode.swift`
  3041–3047,4085–4097 refreshes typing attributes after text/selection changes. Pinned TDLib `TextEntity`, `FormattedText`
  and `InputMessageContent` define UTF-16 offsets, nesting and the manual-entity whitelist.
- Eight-file integration format/build `build-Debug-20261002-195938-90068-6531.log`: PASS11s, zero warnings. Final two-file
  format/build `build-Debug-20261002-200325-91739-906.log`: PASS7s, zero warnings. Audit Simulator source `fb15c25`, PID `92214`:
  `-ui-probe-composer-entities`, composer-edit/restoration, text-spoiler and scoped-update regressions all pass. Evidence under
  `.build/ui-probe-evidence/astra-a25-primary`; worker notes under `.build/composer-entities-proof` in its protected worktree.
- Probe uses real UITextView insertion/deletion/callbacks, edit-attempt preparation, DraftMessage Codable and immutable restoration
  transfer. No user clipboard, URL, server calls or account-store writes. Live IME/undo, network edit/send, persisted draft relaunch,
  private semantic clipboard interchange and animated custom-emoji composer presentation remain unverified. No new quote/language picker.
- Follow-up `26d5f48` expands the same production-field probe: model echo preserves two marked candidates and their commit,
  restoration stays blocked while composing, and UIKit's actual undo manager restores/reapplies formatting and pasted text with
  unchanged entities. One-file format/build `build-Debug-20261002-200757-94069-19293.log`: PASS6s, zero warnings. Audit Simulator
  source `26d5f48`, PID `94652`: `marked-model-feedback=true; UIKit-undo-redo=true`; restoration/text-spoiler regressions pass.
  This is programmatic UITextInput/undo proof, not a live software-keyboard, dictation, CJK suggestion or keyboard-shortcut test.

#### A22 delayed viewport authority — 2026-10-02

- `6869382` binds automatic latest/anchor compensation to a one-shot geometry ticket. Structural snapshot, single/bulk reconfigure,
  rotation, deferred self-sizing and reply-quote expansion consume only the newest current ticket. Capture and completion both
  reject active tracking/drag/deceleration; gesture invalidation remains effective after scrolling ends. Explicit message/latest
  navigation retires old automatic tickets. Revoked Chat ownership cannot restore an old viewport.
- Quote expansion resolves the stable item ID after apply, not its captured index path. Independent inset/highlight changes retire
  pending compensation; inset work caused by a completion's own synchronous layout stays in that compensation. Initial inset pinning
  no longer overrides active scrolling. Existing message IDs, history/cursors, send transitions and A30 restored-viewport contract remain.
- Reference: pinned pre-Liquid `TelegramUI/Sources/ChatHistoryListNode.swift` 4229–4238 stationary-item transactions;
  `Display/Source/ListView.swift` 297–304 tracking state,2124–2194 deferred geometry,3180 tracking-aware inset repair.
  No upstream UI infrastructure copied; no TDLib schema/API changes. Independent four-file source review found no introduced blocker.
- All four changed Swift files formatted together; final `build-Debug-20261002-201821-1578-13580.log`: PASS8s, zero warnings.
  Audit Simulator source `6869382`, PID `2570`: `-ui-probe-viewport-authority`, Chat state, composer restoration/entities pass.
  Policy probe verifies stale/repeated ticket rejection, current scroll/context gates, 1,000 superseding revisions and fresh work after
  invalidation. It does not exercise UICollectionView diffable completion timing or emulate a real drag.
- Actual own Saved Messages opens, scrolls to earlier history, stays at that settled position across later observation and returns to
  latest using its visible button; composer remains available. Screenshots and probe outputs: `.build/ui-probe-evidence/astra-a22-primary`.
  The first chat screenshot caught the push transition; use the settled/after-scroll/after-idle/returned-latest captures for UI evidence.
  No messages, drafts, account settings or links were changed. Controlled prepend/resize/rotation/keyboard races, programmatic-scroll
  animation overlap and exact pixel-offset instrumentation remain unverified; this is not complete timeline parity.
- Additional actual keyboard smoke, 2026-10-03 03:41–03:47: installed code `596e895` (documentation HEAD `123cf31`),
  audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone 17 Pro/iOS 26.5, same PID `59144`.
  Saved Messages was scrolled away from latest and allowed to settle; tapping the empty composer showed the Russian software
  keyboard, and tapping blank history dismissed it. Two pre-keyboard AX samples and the shown/hidden samples retain the same
  fully visible row rectangles: privacy-safe label hashes `946a11dcc510` at `(8,139.3333,386,46)` and `5169c6a01ad7` at
  `(8,229.3333,386,191)`. Composer y moved `796.6667→487.6667→796.6667`, with text length zero throughout.
  Screenshots inspected: `.build/ui-probe-evidence/astra-a22-keyboard/{scrolled-first,keyboard-shown,keyboard-hidden}.png`.
  These are AX label hashes, not TD message IDs; this proves only the settled nonlatest empty-composer show/hide sequence.
  No typing, sends, links or message actions. Interactive dismissal, simultaneous prepend/resize, rotation, send flights and
  nonempty composer remain unverified. No Swift change was needed for this bounded check.
  Documentation build `build-Debug-20261003-034905-77575-16672.log`: PASS5s, complete log zero warnings/errors.
- `41f87a5` (worker `2aba07b`, reviewed tree `44a14cfc`) adds opt-in `-ui-probe-viewport-completion` to an actual already-open
  Saved Messages controller. No mock rows/VM or history writes: unchanged production snapshot, held exact native completion,
  stable original item ID and geometry, matched control and ended delegate-drag cases. Probe motion suppresses its own willDisplay
  read-receipt/history demand; real entry/scroll remains normal UI. Interference is SKIP, invariant failure is FAIL.
  Review rejected an initial diagnostic global-invalidate cleanup; final cleanup consumes only its captured ticket before releasing
  held completion and cannot retire a newer real capture/quote ticket. No production authority algorithm was changed.
- Single SwiftFormat0/2; integrated build `build-Debug-20261003-123000-86500-18926.log`: PASS13s, full log zero warnings/errors.
  Audit59EB535C/iOS26.5 PID88609: first run expired before the manual scroll (12:32:54 SKIP, no assertion failure). Reopened actual
  Saved Messages and scrolled once: fresh run96B73C04 report12:34:25+04 PASS. Control offset475.6667→539.6667→475.6667,
  stable-ID pixel354.3333→290.3333→354.3333. Ended delegate drag retains539.6667/pixel290.3333 after the old completion.
  Native/release counts2/2, restoration counts1 total, each layout depth1→0, cleanup returns initial viewport and holds no closure.
  `astra-a22-completion/after-pass.png` inspected. Actual inserted older rows, physical drag during apply, resize/keyboard/rotation
  overlap and interrupted cleanup transport are not established by this bounded unchanged-snapshot test.
- Supplementary PID93318 reports12:36:16/19: Chat restoration state and composer pass; viewport helper FAILS A39 animated
  target/quote settlement after resize. Standalone rerun PID316, fresh report12:40:56 PASS, with unchanged build/source. Preserve
  the first failure: its cause is unresolved; concurrent fixtures are not a proven cause. This is not a full clean runtime-suite claim.

#### A49 ChatView snapshot fallback — 2026-10-03

- Source `41f87a5`: `ChatView.swift`1553–1559 dequeues before resolving `message(for:)` from current `chatVM.messages`.
  `messagesDidChange` defers structural apply to the main queue; visible delete adds a140ms delay after the VM removes rows.
  Thus an outgoing snapshot ID can lack a live model. The current miss returns a fresh cell; weak-owner/cast exits also need
  exact registered dequeue behavior. `ChatMessageRenderOwners` detects wrapper changes only and is not a snapshot model store.
- Reference: local UIKit26.5 `UICollectionView.h`471–473 requires reconfiguration to keep existing cells. Telegram pre-Liquid
  `8e7e5fe`, `ChatHistoryListNode.swift`4226–4241 carries the transition's history view/opaque state into its transaction/completion.
  Adapt ownership to UIKit/TDLib; no Texture/Postbox/Display import and no TDLib schema change.
- Bounded A49a plan: shared production dequeue/configure path, exact same cell on model miss, inert media/callback/selection/AX
  cleanup, normal same-ID reconfiguration recovery. Native production MessageCell/diffable probe removes only its fixture model
  while retaining its snapshot ID. No real message delete/send. A49b must separately retain outgoing models through exact apply
  completion and gate stale callbacks; A49a alone must not be reported as complete transaction ownership or a reproduced Chat crash.
- A49a `ca71e33` (worker `c30c94a`, reviewed tree `a51fc2e3`) implements one shared dequeue path for message/date/topic cells.
  Missing model/owner or cast mismatch returns the exact registered object. Unavailable MessageCell resets existing media/resource
  owners, text, closures, AX, selection/swipe and owned animation presentation; date/topic headers clear text/AX/action/icon state.
  An extracted bubble is concealed without reparenting or altering its external owner's transform/alpha. Normal configure restores
  visibility, actions and accessibility. Context-menu captured actions and entire menu lifetime are outside this slice.
- Worker build `125718-22308-10102`: PASS9s; integrated `130225-28206-10571`: PASS15s, complete logs zero warnings/errors.
  Audit59EB535C/iOS26.5 PID29347 report13:03:16 FAILS the combined extraction assertion. Diagnostic-only `9e76f8f` (worker
  `15ecc478`, tree `33ba48c3`) preserves predicates; build `130540-31515-29596` PASS12s/fullzero. PID32074 report13:06:20
  establishes parent=true, hidden=true, expected transform preserved and own container identity/alpha1; only UIKit alpha getter
  `0.80000001192092896` differs from literal `0.80000000000000004`. These failures are retained, not relabeled as passes.
- Oracle-only `0404996` (worker `8f3d33a`, tree `c37e9732`) captures actual getter baselines immediately after assignment, checks
  nontrivial arming, then compares exact post-fallback equality; no epsilon/production change. Joint SwiftFormat0/7; build
  `131011-36936-10906` PASS17s, full log zero warnings/errors. PID37648 report13:10:52 PASS: native MessageCell same-object
  reconfigure without prepareForReuse, missing model cleanup, recovered same-ID text/selection/actions, released weak owner,
  extracted ownership/presentation preservation, header unavailable/recovery and cast mismatch. Existing delivery/A44 receipt,
  stable wrapper replacement/album promotion and offset checks pass. Fresh install container/report receipts are in
  `.build/ui-probe-evidence/astra-a49a-fallback/README.md`.
- Same0404996/PID37648 actual Saved Messages renders text/forward/date headers and empty composer; existing forwarded text's
  context menu opens and dismisses to the same bubble. Screenshots `saved-settled`, `menu-open`, `menu-dismissed` inspected.
  No option chosen, text typed, link opened, send or delete. This ordinary UI check does not reproduce unavailable-row timing.
  Loaded-media cancellation, suspended history pan and captured menu actions are not armed by this fixture; A49b remains open.
- A49b source contract: five producers (structural, single/bulk reconfigure, highlight, quote) must share any new scheduler.
  Preserve A22 intent/tickets/depth, A44 wrapper invalidation, delete140ms barrier, send-flight target settlement and client retirement.
  `ChatVM+Publishers`305–322 mutates an album wrapper in place; ChatVM1332–1353 can replace the same album ID's wrapper.
  Retention of mutable references alone is not a coherent rendering transaction. Keep provider rendering separate from live
  action/navigation/prefetch lookup; exclude deleting IDs from reconfigure so configure cannot revive a fading bubble.
  The provider-callback prerequisite is repaired below; rendering ownership stays separate.

#### A49b rendered message action authority — 2026-10-03

- `eeb93b2` (worker `64299df`, reviewed tree `d755c225`) freezes each provider configuration's source/location, exact wrapper,
  value payload and derived metadata, cell binding and selected/chosen state. Seven callbacks resolve current live row, attached
  top route, account/client and intent permissions before acting. Old AX/media bridges cannot invoke newly installed callbacks;
  swipe completion requires its begin binding. Poll actions carry the exact token returned before synchronous publication reentry;
  rejection clears only that token in the original captured store, preserving newer retries.
- References: pre-Liquid `8e7e5fe`, `ChatController.swift`3191–3227 and
  `Chat/ChatControllerLoadDisplayNode.swift`1578–1619 resolve current reply permissions/history. Pinned TDLibKit
  `1.5.2-tdlib-1.8.66-022d6020` provides value-typed Equatable Message/MessageProperties; `setPollAnswer` API/schema is unchanged.
- Worker full log `133819-82229-23159` PASS9s; integration joint SwiftFormat0/7, build `134359-88074-14542` PASS17s,
  full log zero warnings/errors. Audit59EB535C/iOS26.5 PID90027, fresh container `B00A258F-A101-49FD-8BD7-12DBBF0E6436`,
  report13:44:48 PASS: real MessageCell/diffable reconfigure and retained AX/media callbacks, changed wrapper/source/payload,
  selected/chosen state and permissions; actual poll option UIControl accepts fresh submission and rejects closed poll;
  stale/reentrant rejection preserves the newer exact retry. Existing delivery/A44/A49a probes also pass; RPC/sends=0.
- Proof limits: source/route inputs are controlled; actual controller detach/index-path races, physical swipe/selection timing,
  asynchronous action execution, direct child controls and captured menu actions are not covered. No renderer/scheduler rewrite.
- Same `eeb93b2`/PID90027 actual Saved Messages: existing context Select enters1; provider taps select a second row (2), then
  deselect it after reconfigure (1); Cancel restores empty composer with selection toolbar absent. Screenshots inspected under
  `.build/ui-probe-evidence/astra-a49b-actions/`; no send/vote/reaction/forward/delete/link action. This proves ordinary current
  selection admission in the real controller, not touch-down/update/touch-up or detached-route races.
  Subsequent screenshot review confirms unselected rows retain blue selection circles after Cancel in this same evidence;
  toolbar/composer recovery must not be read as full selection teardown proof. See A50 below.
- Confirmed next bounded defect at `eeb93b2`: MessageView's persistent selectionControl retains its touch while configure replaces
  actionBindingID/onSelectionToggle. Late touchUpInside calls the new callback, whose fresh authority can admit the wrong intent.
  Plan: capture binding on touchDown, consume only matching token on touchUpInside, clear on cancel/outside/reset/configure;
  preserve independent AX activation and ordinary selection. Prove current, stale/rebound, duplicate/cancel/outside/reset sequences
  through the real UIControl event targets; synthetic event ordering is not physical UITouch proof. Reaction buttons are separately
  reset/replaced on each configure, so the same source defect is absent there. No actual unwanted selection has been reproduced.
- Follow-up `9961aba` (worker `9e1b0a0`, reviewed tree `bf7833e7`) implements that touch token; configure/reset/detach/cancel/outside
  clear it, up consumes before invoking the callback, AX stays independent. Worker joint2-file format/build `135311-1388-8311`
  PASS9s/fullzero; integration joint SwiftFormat0/7/build `135546-3924-17979` PASS15s/fullzero. Audit59EB535C/iOS26.5 PID5348,
  fresh container `1086DC4E-361C-4EAC-8255-C0041B6E0D3D`, report13:56:42 PASS: old armed token, exact same native cell/control
  and unchanged reuse count across reconfigure; late/duplicate/canceled/outside/reset touch-up rejected; fresh touch and independent
  AX admitted. All prior delivery/action probes pass. Synthetic UIControl event ordering is not physical UITouch race proof.
- Same `9961aba`/PID5348 ordinary Saved selection again passes1→2→1; Cancel restores composer/toolbar state but leaves circles
  on unselected rows, reproducing A50. Evidence `touch-selected`, `touch-selected-two`, `touch-selected-one-again`, `touch-canceled`.

#### A50 selection-mode exit invalidation — 2026-10-03

- P1, bounded fix `487c0de`; actual Saved Messages at `eeb93b2`/PID90027 and `9961aba`/PID5348 shows stale unselected-row circles after Cancel.
  `ChatView.endMessageSelection` saves only selected IDs and reconfigures those after setting isSelectingMessages=false.
  Other cells retain selectionActive/control/indicator and the old callbacks. A49 guards suppress stale actions but do not repair UI.
  The structural `endMessageSelection(reconfigure:false)` branch likewise needs all surviving rows reconfigured in that apply.
- Bounded plan: invalidate every message row already in the displayed snapshot on explicit mode exit, and every surviving
  message row in the structural snapshot when selected-message removal exits the mode. Keep stable IDs, ordinary per-selection
  targeted updates, permission checks and viewport restoration; no send/delete/poll mutation.
- `487c0de`, reviewed tree `62c1bc70`, invalidates all displayed message rows on explicit exit, including deselect-last with an
  already-empty selected set. Structural selected-row removal invalidates all incoming surviving message rows in its own apply.
  Telegram pre-Liquid `8e7e5fe`, `ChatController.swift`7372–7384 updates selection state for every history item. No TDLib API change.
- Joint SwiftFormat0/7; full build `140935-21229-15672` PASS14s/zero warnings/errors. Audit59EB535C/iOS26.5 PID22663,
  fresh container `4844B0B0-0143-4DE3-A183-22684E32AD5E`, report14:10:24 passes existing delivery/A44/A49 action/touch probes.
  Same source/PID actual Saved Select→Cancel and Select→tap sole selected row both remove all visible selectors and restore
  empty composer; screenshots `a50-selection`, `a50-cancel-clean`, `a50-deselect-before`, `a50-deselect-clean` inspected.
  Structural model removal is source-reviewed, not exercised by this smoke or existing native probe; deletion race remains unverified.

#### A49c snapshot transaction design gate — 2026-10-03

- Source `9961aba`: all five producers must move together: structural snapshot, single/bulk reconfigure, highlight (including
  DEBUG branch) and quote. Highlight currently has no depth/completion lifecycle. Delete's140ms deadline protects only structural
  applies; no deleting-ID filter prevents a reconfigure from restoring alpha/interaction. This is a confirmed ownership gap,
  not grounds to change TDLib pagination or live action/navigation lookup.
- Planned bounded replacement: provider-only frozen render values, exact canonical wrapper identity separate from render clone,
  full sender/reply/forward/album/formatted/properties/reactions/unread/sendFailed/pin/quote/delivery/mutation state and exact client.
  Do not reuse client-restoration seed semantics, which intentionally drop delivery/mutation state. Freeze header info and cell
  selection/highlight/layout inputs as well. Actions compare current canonical state against rendered values, never against the clone.
- One active UUID batch, committed/outgoing render rows and one coalesced pending demand buffer; pending stores intent/IDs,
  not stale NSDiffable snapshots. Build membership/frozen values at dispatch, retain outgoing rows through exact completion,
  reject duplicate callbacks and balance each depth owner even after source retirement. Exclude fading deletion IDs from
  reconfigure, respect the existing deadline, and preserve A44 owner invalidation and temporary→final aliases.
- Preserve A22: stamp a pending buffer with a separate interaction-invalidation revision, never refresh that stamp during
  coalescing. Stale demand may update content but cannot mint a new automatic restoration ticket after an ended drag.
  Keep an explicit finishing/busy phase through completion/depth release/drain; navigation, restored viewport, send flights and
  client replacement must see pending work and cannot settle in the gap between applies. Initial unloaded/no-window hydration
  remains allowed; obsolete sources cannot dispatch. This design is reviewed, not implemented or runtime-proven.
- First standalone prerequisite A49c1: immutable render value used as the existing action-authority baseline, with canonical
  identity kept separate; exact/lazy render-only materialization and mutation-isolation probes. Existing predicate semantics,
  client-restoration seeds, provider and all five apply paths remain unchanged in this prerequisite. The following integration
  must switch provider/scheduler together, including old bound-cell fade preservation, deleting-ID tombstones through exact
  removal completion, and committed raw-member checks before send/navigation settlement (an added album member reuses its ID).
- A49c1 `d8512b5` (worker `5ce940d`, reviewed tree `6ab765ce`) captures all14 message-render fields as values and lazily creates
  detached renderer adapters with exact private delivery state, mutation flags, explicit nil reactions and empty unread state.
  Existing action authority now stores this value baseline separately from canonical wrapper identity; current production callers
  keep existing capture timing and admission semantics. Client-restoration seeds and provider/snapshot paths are unchanged.
- Worker build `140810-18467-16598` PASS13s/fullzero; primary joint SwiftFormat0/9/build `141710-32677-17015` PASS14s/fullzero.
  Audit59EB535C/iOS26.5 PID35594, fresh container `2A3C5EC4-9438-40E6-B6CB-4528C450FF1D`, report14:18:11 PASS. Extended
  `ChatMessageActionAuthorityProbe.verifyRenderValues` runs before the existing report's success: same-wrapper album promotion,
  sender/metadata/formatted/properties/reaction/read/mutation changes leave captured values and exact materialization unchanged;
  clone mutations stay isolated; old baseline fails, fresh baseline+canonical passes, clone cannot acquire canonical authority.
  All prior delivery/A49/A44 native cases pass. Source+native prerequisite proof does not establish frozen production rendering.
- Fresh pre-integration baseline at clean `f15d2b9` (production `d8512b5`, product from `141942-39748-21216`): standalone
  viewport-authority PID67824/container `86434DC1-9554-4BA7-8BBD-768A533512E0`, report14:34:47+04 PASS. Native A39
  animation/estimated-height resize/convergence passes; the earlier combined-run failure remains unexplained, not superseded.
- Actual Saved Messages baseline, wrapper `-ui-probe-viewport-completion`, Audit59EB535C/iOS26.5 PID77750/container
  `07C30E00-16D2-410F-9DCB-326F7756FCA7`, report14:43:58+04 PASS. Control offset498.6667→562.6667→498.6667 and
  stable-ID pixel331.3333→267.3333→331.3333; ended synthetic delegate drag retains562.6667/pixel267.3333. Native/releases2/2,
  depth1→0, original anchor restored in cleanup. `c2-baseline-viewport.png` inspected. One physical scroll entered the fixture;
  concurrent physical drag/history insertion/resize/keyboard remain unverified. No send/delete/forward or host focus activation.
  These are checks of the committed prerequisite, not proof of the in-progress scheduler.

#### A49c2 frozen timeline transactions — 2026-10-03

- P1, `f799d29` (worker `ec68744`, reviewed tree `bac0ab6f`): all five production snapshot producers share one active
  transaction and a coalesced intent buffer. Provider rows retain exact canonical identity, immutable render values, client/source,
  header and selection inputs through exact native completion. Materialization and new inline players remain lazy; live action,
  navigation and prefetch lookup stay separate. Raw album membership must be committed before navigation/send settlement.
- Preserve A22 interaction epochs, A44 owner invalidation, A50 all-row selection exit, temporary/final aliases and the140ms
  deletion deadline. Tombstone-owned bindings survive intermediate commits. Same-album reappearance first commits removal,
  then queues fresh membership without turning stale recovery into post-drag restoration. Duplicate/ownerless receipts release
  only the matching batch; pending/finishing states block premature navigation/send/client settlement.
- Committed visible-row acknowledgement deduplicates current visible raw IDs and checks the attached active scene/route.
  Context previews may load history but cannot acknowledge reads. Background/read-retry/player ownership changes have source
  review, not live transport proof. No TDLib API change; pinned TDLibKit remains `1.5.2-tdlib-1.8.66-022d6020`.
- Telegram references: official master `6ad963e5`, pre-Liquid `8e7e5fe`,
  `submodules/TelegramUI/Sources/ChatHistoryListNode.swift`4197–4241 (raw-member correlation and transaction-owned history);
  pre-Liquid `submodules/TelegramUI/Sources/ChatController.swift`7372–7384 (all history selection updates). No infrastructure imported.
- Worker compile failures `145001`/`145414` (actor isolation/explicit captures/type inference) and weak-mutation warnings
  `145605` were corrected, not suppressed. Review withdrew earlier approvals for deletion-lease carryover, same-album liveness
  and mixed-epoch recovery; final worker `151204-36307-16904` PASS9s/fullzero. Primary joint SwiftFormat0/9 and
  `151812-44934-6936` PASS23s/fullzero; exact reviewed tree integrated without other Swift changes.
- First native scheduler probe, Audit59EB535C/iOS26.5 PID48152/container `3F87B0C4-06F0-4748-A8BF-6D9C6F987646`,
  report15:19:13+04 FAIL: deleting-cell presentation changed. Diagnostic-only `1727d77` (worker `f06ea40`, reviewed tree
  `d638b735`), format0/9/build `152429-60083-15376` PASS12s/fullzero, preserves the assertion. PID62822/container
  `0539F196-6964-4174-B1C0-9C134447DEB6`, report15:25:35 FAIL confirms exact same cell/binding/lease, reuse0,
  interaction disabled; alpha0.375/translation(8,-3) survive provider return, but UIKit resets cell alpha1/identity by native
  receipt. Production also animates these cell attributes: an inner presentation-layer repair is required, not a weaker oracle.
- Same `f799d29`: delivery/action regression PID49199/container `D31762BA-315B-4FC8-8946-C4DA59FB09CF`, report15:20:15 PASS.
  Standalone viewport-authority PID50146/container `E157EB3B-DCCB-45ED-91FE-D5E081F2B63D`, report15:21:10 FAIL:
  A39 animated target/quote did not settle after resize. Driver/probe are byte-unchanged from `d8512b5` and do not instantiate
  ChatView. Historical failure remains unresolved; this repeat disproves any claim that only combined runs can fail.
- Actual Saved Messages A22 PID51820/container `7E07B2CE-3C0E-483C-9110-AD462FC19784`, report15:23:35 PASS:
  exact native/releases2/2, depth1→0; control offset483.3333→547.3333→483.3333, anchor pixel346.6667→282.6667→346.6667;
  ended synthetic delegate drag retains547.3333/pixel282.6667. One physical scroll entered the exercise; IDs were unchanged.
  Real prepend/media resize/keyboard/physical overlap remain unverified. No sends/deletes/forwards or host focus activation.
- `724bf32` (worker `0b08091`, reviewed tree `d0a54bb4`) moves deletion opacity/slide/scale into MessageCell.contentView,
  composing its permanent timeline flip. Cell/descendant AX and interaction are disabled during deletion; configure/unavailable/
  reuse reset only the owned inner layer, preserving rowStack swipe/selection and externally extracted menu content.
  Worker joint9-file format/build `153256-73686-3111` PASS10s/fullzero; primary format0/9/build `153501-78488-29638`
  PASS12s/fullzero. Assertions now measure the actual owned presentation, including same-cell normal configure and animation reset.
- Audit59EB535C/iOS26.5 PID79368/container `B9291225-072C-42EF-883E-0A471DF8472C`, report15:35:36 PASS: production
  scheduler/native MessageCell, all five coalesced demands, exact/duplicate/ownerless receipts and depth, frozen values/actions,
  committed raw album members, stale restoration rejection, both same-album deletion/reappearance schedules and AX/reset.
  Late provider/native receipt preserve inner opacity/transform and exact binding without reuse. Actual ChatView producer races,
  physical gestures, live client switch,140ms delete timing and actual timeline media-player ownership remain unverified; RPC/sends0.
- Same final production `724bf32`, PID79903/container `585489CE-C989-4009-8687-A6065E83554B`, report15:36:23 PASS:
  existing delivery/render/action/poll/touch/source/receipt native regressions. Earlier media-reveal regression at `1727d77`,
  PID69532/container `78A0D689-DDC4-4EB4-9F6A-E7C481D2B0A3`, report15:29:29 PASS with isolated native media/backend;
  it does not prove real timeline gestures, TDLib transport or active system PiP.
- Same final PID79903 actual Saved A22 report15:38:06 PASS: native/releases2/2, depth1→0, stable IDs unchanged.
  Control offset488.6667→552.6667→488.6667, anchor pixel341.3333→277.3333→341.3333; ended synthetic delegate drag
  retains552.6667/pixel277.3333. Ordinary Select→Cancel and Select→tap sole selected row both remove all visible selectors
  and restore the empty composer. Screenshots `c2-final-viewport`, `c2-final-selected`, `c2-final-cancel`,
  `c2-final-deselect-before`, `c2-final-deselect-clean` inspected under `.build/ui-probe-evidence/astra-a49b-actions/`.
  Root screenshots contain private previews and must stay local. No sends/deletes/forwards/reactions/votes/profile/account edits;
  ordinary navigation may acknowledge history through the app's normal read path. The injected probes themselves issue no RPCs.
- Next bounded slice: add passive A39 completion/failure-reason receipts (outcome, post-result visibility, offset error,
  commands/native ends and deadline versus correction budget). Confirm or reject the source candidate where a late layout
  offset change clears `receivedEnd` and leaves no future end to resume checks. Keep current deadline/centering assertions;
  then add an exact event-order regression and repair only a measured defect. Driver/probe do not use the ChatView scheduler.
  Further A49 coverage: actual queued producer overlap, prepend/keyboard/media resize, committed-read lifecycle and current
  inline-player ownership. Native fixture success is not proof of these whole-controller/server paths.
- Final checkpoint build `154717-90533-2969` PASS9s, full1385-line log has no warnings/errors; AGENTS/CLAUDE agree,
  production/dependency VLC and forbidden UI/infrastructure marker scan is empty. Source checkpoint `724bf32`; only this
  parity record changed after that build. Simulator remains booted in Saved Messages, selection exited; no host focus activation.

#### A23e login authorization authority — 2026-10-02

- `097b488` (worker `b5e001b`) publishes replayable accepted authorization state keyed to the account/client epoch.
  Handoff clears readiness before replacement; Login clears credentials/hint and cancels queued work. A fixed-account session
  accepts its replacement client, but a foreign-account transition permanently revokes it. Duplicate states retain current input.
- Submit captures client, stage and request identity before dispatch. Every dispatch/completion validates that identity; old
  completions cannot clear newer busy/input state. Country lookup and country/account callbacks use the same authority.
  Root replaces a revoked Login even after a coalesced A→B→A. Unsupported authorization stages remain non-submittable.
  Cancellation cannot retract an already dispatched RPC; credentials are not logged, and Swift String zeroization is not promised.
- Generator and emitted auth notification use the normal scoped transport. Accepted-state replay replaces informational
  `getAuthorizationState` reads. Regeneration leaves `Td+Generated.swift` unchanged (SHA256
  `1d4722587534754ed628995aa1dbcb6bb6628aa1e8f2d56d9b86b056e669fa41`).
- Reference: pinned current/pre `AuthorizationUI/Sources/AuthorizationSequenceController.swift` 39–124,340–342,519,942 /
  39–124,190–195,477,900. Pinned TDLib `GetAuthorizationState.swift` documents informational use only; production follows
  accepted `updateAuthorizationState` and captured phone/code/password authentication APIs. No upstream infrastructure copied.
- Nine Swift integration paths formatted together (generated path excluded by repository formatter); integration build
  `build-Debug-20261002-202608-8127-22497.log`: PASS11s, zero warnings. First actual Login probe failed because UIKit normalized
  the cleared placeholder to nil. Diagnostic proved text empty, hint nil, input disabled and old action invalid. `d7e9974` accepts
  nil or empty without changing production; initial failure and Boolean-only diagnostic are retained.
- One-file final format/build `build-Debug-20261002-203027-28086-32623.log`: PASS7s, zero warnings. Audit Simulator PID `31259`,
  source `097b488` plus the later-committed `d7e9974` probe: auth, Root list, Chat updates, viewport and composer entity probes pass.
  Actual Login view covers queued/suspended/reentrant/deinit cancellation, duplicate submit, same-account replacement, foreign
  terminal revocation and scoped generated dispatch using private injected state/requests. Auth/account-store/clipboard writes: zero.
- Authenticated root opens and returns from Home in the same launch after accepted-state bootstrap changes. Evidence:
  `.build/ui-probe-evidence/astra-a23-auth-primary`; root screenshot contains private chat data and is not a shareable artifact.
  Real code/password/country actions, actual account switching and server authentication remain unverified.

#### A20a route-owned media concealment — 2026-10-02

- `05c2b49` (worker `113e443`) introduces route-owned account/client/chat authority and per-member media-revision permits.
  Keys include content kind, source file IDs, edit revision and spoiler/secret flags; download progress does not erase a reveal.
  Timeline first tap reveals only the selected spoiler; second tap opens gallery. Gallery grants only its central item and retains
  the issuing session through PiP restoration. Secret photo/video/animation remain concealed and cannot enter ordinary playback.
- Admission happens before image/player/thumbnail creation or prefetch. Concealed UIKit covers contain no raw media beneath them.
  Single/album AX is sanitized; captions retain independent A10 semantics. Photo/video loads use the captured client.
  Transition capture and later snapshot access check the exact revision and rendered generation.
- Accepted Chat model changes synchronously revoke old permits before queued UI work, cancel pending prefetch and invalidate
  owners. Gallery receives the accepted replacement payload; same-ID updates reconfigure visible cells and require a new reveal.
  Reconciliation is guarded against recursive notifications. Covered timeline cells refresh revealed members on gallery return.
- Reference: pinned current/pre `ChatMessageInteractiveMediaNode.swift` spoiler/secret admission 925/946 / 923/944 and
  concealment 3094 / 2948–2988; pinned TDLib `MessagePhoto/MessageVideo/MessageAnimation.hasSpoiler/isSecret` contracts.
  This bounded implementation uses an opaque cover; upstream blur/particle polish and full visual parity are not claimed.
- Eight Swift files formatted together; integration build `build-Debug-20261002-203725-34161-16930.log`: PASS18s, zero warnings.
  Audit Simulator source `05c2b49`, PID `39784`: media-reveal, text-spoiler and viewport probes pass. Native AVAssetWriter fixture,
  actual gallery cell/controller/owner and isolated range backend prove selected-only admission, no pre-reveal downloads,
  revision cancellation, stale snapshots and issuing-session retention. PID `40544`: native inline-animation and gallery-transition
  regressions pass. PID `40966`: gallery-owner native/FFmpeg continuity, finite ranges and teardown pass. PID `42082`:
  isolated PiP context/restoration regression passes; active system PiP remains unsupported. Readbacks:
  `.build/ui-probe-evidence/astra-a20a-primary`.
- Same PID `42082` opens actual Saved Messages with its ordinary text history and composer intact; no hidden media was selected.
  Private `saved-chat.png` records this limited UI smoke. Documentation checkpoint build
  `build-Debug-20261002-204324-42880-29193.log`: PASS5s, zero warnings.
- Policy-level first/second tap proof is not a real timeline gesture. Actual TDLib transport, spoiler UI gestures, real PiP,
  profile grid, full accessibility and animation appearance remain unverified. Profile concealment is the next bounded repair.
  Same-epoch stale RPC ordering is not solved by revision permits. No real hidden/secret message was opened or consumed.

#### A30c Archive client recovery — 2026-10-02

- `bb36bc7` opts Archive into the existing prepared navigation replacement. It captures query, search focus and stable
  row/pixel viewport; commit constructs a new frozen action client without rebuilding adjacent Chat routes. The shared coordinator
  retains its account/ready-source/modal/stack checks. Archive also replaces its child when RootVM publishes a new archive folder
  object, so later hydration does not strand the old list. Old child subscriptions/prefetch ownership are released normally.
- Preserve full-width UIKit chrome and current safe-area/search height. Defer replacement/hydration during dragging/deceleration
  or marked input; matching scroll callbacks, query changes, appearance and Root state schedule retries. Independent review caught
  a tracking-only wait with no terminal scroll callback; the final gate excludes tracking-only touches. IME unmark without a query
  event remains a runtime proof gap, not claimed solved.
- Reference: pinned current/pre `ChatListUI/Sources/ChatListController.swift` 98 / 91 retains immutable account context and
  list location. BetterTG adapts this ownership to its existing TDLib `readyClientChanges`, accepted folder hydration and
  `ChatListArchive` model; no new TDLib API, storage format or copied navigation infrastructure.
- Three modified Swift files formatted together; final `build-Debug-20261002-205425-50452-17562.log`: PASS9s, zero warnings.
  Audit Simulator PID `52323`, source `458365c` plus the committed delta: client-restoration, Root list and auth probes pass.
  Actual Archive search retains a nonempty local query and active focus through two Home→foreground cycles. Existing Russian
  hardware-keyboard layout transformed the requested ASCII fixture; the exact resulting query survived unchanged.
- Bounded idb log confirms `Archive client restoration: replacement accepted; search-focus=true` in PID `52323` at21:00:18.
  Screenshots/proofs/command limits: `.build/ui-probe-evidence/astra-a30c-primary`. The temporary agent-created filter was closed.
  No archived chat, message, account, server setting or draft was modified. idb's timeout cleanup emitted an asyncio diagnostic;
  it is not an app/build warning. Populated anchor accuracy, live hydration during dragging, late first-layout and cross-account
  navigation remain unverified; the existing generic coordinator probe is not an actual Archive-controller test.

#### A20b profile-grid media concealment — 2026-10-02

- `d8f9b36` (worker `3f1f359`) gives shared-media cells the profile's frozen playback context and issuing reveal session.
  Thumbnail/minithumbnail loading, visible badges, accessibility and transitions require the current member revision. Concealed
  cells contain an opaque cover without raw media below it. Source/revision/reuse invalidation cancels loading and clears pixels.
  Accepted profile snapshots reconcile permits before diffable delivery and refresh retained same-ID cells and the active gallery.
- Selecting a profile-grid item opens the existing gallery and grants only its selected member. Return refreshes visible grants;
  timeline's separate first-tap/second-tap contract is unchanged. Secret media remains denied; file/link/audio rows and avatar
  handling are unchanged. Revision permits do not solve same-epoch stale RPC ordering or profile client replacement.
- References: pinned current/pre `TelegramUI/Components/PeerInfo/PeerInfoVisualMediaPaneNode/Sources/PeerInfoVisualMediaPaneNode.swift`
  895–933,1322–1337,1898–1907 / 875–913,1273–1288,1816–1825; pinned TDLib media `hasSpoiler/isSecret` and file contracts.
- Primary review corrected a probe assumption about rasterized transition views. `bdd19cd` (worker `e5fffa7`) checks actual
  UIImageView snapshot pixels: the private red fixture is absent while covered and present after reveal. No production policy change.
  Three Swift files formatted together; `build-Debug-20261002-210753-97781-13866.log`: PASS10s, zero warnings.
- Audit Simulator source `bdd19cd`, PID `473`: profile-media-reveal, media-reveal, text-spoiler and client-restoration probes pass.
  Actual cell/gallery plus private fixture cover zero pre-reveal thumbnail calls, revision/source revocation, reuse, stale snapshots
  and sanitized AX. This is not a full profile-controller, real TDLib transport or actual spoiler-touch test.
- Same launch: Saved Messages → own Profile displays the avatar, Media/Files/Links/Audio controls and populated media grid.
  No media item, hidden content, editor or server action was opened. Private screenshots/proofs:
  `.build/ui-probe-evidence/astra-a20b-primary`. Circular Back remains an A32 gap; the visibly truncated title is recorded as A33.
  Hardware/VoiceOver, populated-grid updates, actual spoiler gestures and full visual parity remain unverified.

#### A21c timed secret video-note hold authority — 2026-10-02

- `0e4e1e1` (worker `46772f7`) replaces global open/file authority and persistent reveal with frozen account/client/message,
  one configuration token and one token per hold. Scoped content/edit/delete/file updates and client/lifecycle changes revoke
  playback. Release, move-out, cancellation, reuse and offscreen teardown remove the player and concealed pixels synchronously.
- A supported incoming timed note validates fresh metadata, obtains its complete file, revalidates, awaits captured-client
  `openMessageContent`, then requires fresh positive finite `selfDestructIn` before player admission. Monotonic expiry includes
  metadata latency conservatively and cannot extend across holds. Late ACK/error/seek/display callbacks cannot authorize another
  hold or configuration. Cancellation does not retract an RPC already dispatched to TDLib.
- Immediate/view-once, missing/invalid timer and outgoing secret forms remain unavailable before this view's I/O. This is not
  a global TDLib/prefetch no-download policy. No temporary copied-file lease, screenshot prevention, secret gallery/export/PiP
  or photo/video/animation hold is added. Ordinary video-note play/pause remains supported.
- Primary review found ordinary thumbnails admitted before a rejected backend. `437d7c7` (worker `1a3c9d4`) gates thumbnail
  and minithumbnail admission and revokes off-window playback even when a detached view remains retained.
- References: pinned TDLib `MessagesManager.cpp` 9303–9324,10199–10223,10329–10352,16968–16994,20641–20642; generated
  `MessageVideoNote`, `Message.selfDestructIn` and `openMessageContent`. Zero remaining duration may mean not started. Immediate
  expiry can remove files during open. Pinned current/pre `GalleryData.swift` 317–319 / 267–269 and
  `GalleryUI/Sources/SecretMediaPreviewController.swift` 519–551,590–597 / 517–549,588–595 use a separate protected viewer
  and pre-consumption file lease; this bounded repair does not claim that view-once architecture.
- Five Swift files formatted together; integration build `build-Debug-20261002-211637-8286-29034.log`: PASS10s, zero warnings.
  First actual-view probe failed its immediate deinit assumption after window removal. `4c3fc5e` waits for bounded queued UIKit
  teardown while ACK remains suspended, with a weak condition; the view is gone before the reply. Exact transient retention cause
  is unproven. Production is unchanged. One-file build `build-Debug-20261002-211911-11904-22812.log`: PASS8s, zero warnings.
- Audit Simulator source `437d7c7` plus the committed probe fix, PID `12358`: actual UIKit/native-player/private-MP4/JPEG probe
  passes nil/stale backend pixels, unsupported forms, ACK admission, late callbacks, positive TTL/elapsed metadata, repeated hold,
  source collision, edit/delete/reuse/window/offscreen/background revocation, canceled download, deinit and ordinary play/pause.
  Injected requests/clock produce no real opens, user-media operations or account writes. Real touch/server TTL ordering remains unverified.
- Source `4c3fc5e`, PID `13038`: profile/media reveal, text-spoiler and navigation regressions pass with fresh file timestamps.
  Separate native inline-animation PID `15898` and gallery-owner PID `16179` pass; same owner/item/layer, finite FFmpeg ranges,
  cancellation and offscreen continuity retained. Active system PiP unsupported. Proofs and initial failure:
  `.build/ui-probe-evidence/astra-a21c-primary`. Worker build/ref notes remain in its `.build/video-note-hold-proof`.

#### A21d secret video-note scene-capture admission — 2026-10-02

- `fd98d02` (worker `5d141f6`) requires an attached window and inherited UIKit `sceneCaptureState == .inactive` at hold,
  metadata, download, ACK and player/pixel admission. Active/unspecified capture and detachment deny the secret hold.
  A trait callback synchronously conceals pixels, stops the player and retires owned download/hold authority. Ending capture
  does not revive a hold or extend its monotonic deadline; a new hold is required. Ordinary notes remain unaffected.
- Reference: the current/pre secret viewer and `ChatImageGalleryItem.swift` capture-protected path cited above. UIKit 26.5
  `UITraitSceneCaptureState`/`registerForTraitChanges` supply scene recording/mirroring state. TDLib APIs are unchanged.
  This is a conservative display gate, not screenshot prevention or a guarantee that hardware cannot capture the first frame.
- `f45869b` (worker `9ac9219`) verifies real container-to-view trait inheritance without overriding the leaf, then explicit
  active/inactive/unspecified boundaries. Existing fixtures inherit actual scene traits. Both changed Swift files formatted
  together; primary `build-Debug-20261002-225546-56715-10303.log`: PASS11s, zero warnings.
- Audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iOS26.5, source `f45869b`, PID `58077`: full actual-UIKit/native-player/
  private-MP4 hold probe passes, including pending I/O, ACK, visible pixels, rehold and ordinary-note regressions.
  Output mtime `2026-10-02 22:56:55`; private proof `.build/ui-probe-evidence/astra-a21-capture-primary`.
  No real secret content opened or account write performed. Hardware recording/touch/server behavior remains unverified;
  photo/video/animation and immediate/view-once playback remain separate concealed gaps.

#### A30e retained folder-flow authority — 2026-10-02

- `850ccf8` (worker `4a5dc84`) keeps the existing folder list/editor/selector/order controllers and their local name, rules,
  selected IDs, raw search query and ordering. `FolderFlowSession` renews only future immutable action scopes after matching
  account, current client, Ready source and Root model. Account departure permanently revokes the flow, including A→B→A.
- Predispatch rollover sends nothing. Readiness/client loss after create/edit/delete/reorder dispatch leaves an explicit
  uncertain result with retained inputs and no automatic replay. Late ACK/error cannot pop, present or enable another save.
  Main → Add Chats is owned by the retained selector, not a retiring Main. Full-definition updates retain existing semantics;
  remote conflict merging, process-death drafts and uncertain-result server reconciliation are not added.
- Initial actual-UIKit probe at `850ccf8`, PID `65721`, failed detached-owner delivery: UIKit retained a popped view in its
  window. `b923f19` (worker `af67ce0`) replaces that insufficient window check with actual containment/navigation/presentation
  membership up to the exact window root. The original assertion stays unchanged; covered entries, nested/page children,
  modal navigation, animated pop, residual pixels and detached navigation subtrees have explicit regressions.
- References: pinned current/pre `ChatListUI/Sources/ChatListFilterPresetController.swift` 550–576,1399–1429 / 546–572,1394–1424
  preserve local editor state with account context. Pinned TDLib `td_api.tl` 13154–13172 defines the existing get/create/edit/
  delete/reorder APIs. No Telegram infrastructure or new account storage is copied.
- All six Swift files formatted together. Primary integration builds `build-Debug-20261002-230359-64579-5399.log`: PASS26s and
  `build-Debug-20261002-231025-79060-7092.log`: PASS55s, zero warnings. The first sandbox-only attempt could not reach
  CoreSimulator; the wrapper succeeded with normal host access, without resetting any Simulator.
- Audit Simulator, iOS26.5, source `b923f19`, PID `80658`: actual folder-session/list/editor/selector/order probe passes;
  immutable scopes, repeated/stale Ready, predispatch denial, all four uncertain mutations, partial UI attachment and account
  revocation are covered with injected endpoints and zero server writes. List-action, navigation-restoration, Root authority
  and accepted-update projection regressions also pass. Fresh output mtimes `23:12:16–23:12:22`.
- Real UI source `850ccf8`, PID `65721`: local New Folder name `Astraflow`, Groups rule and caret survive Home→app-icon
  foreground; Always Include remains usable. Lifecycle log records ownership release `23:08:33` and restoration `23:09:07`.
  Source `b923f19`, PID `80658`: active selector query `Saved` and Saved Messages checkmark survive another Home→foreground.
  Close Search → Done returns to the same unsaved editor with `Always Include, 1 chats`; the local callback remains usable.
  No folder was saved and no conversation opened. Private proof, including initial failure:
  `.build/ui-probe-evidence/astra-a30e-primary`. Server mutations, live account switch, IME and interactive reorder remain unverified.
- Cold and post-foreground selector screenshots also show pre-existing blank title rows, a white Done checkmark and native
  bottom search. `CustomChat.displayTitle`, subtitle and sorting are unchanged by this slice: empty raw titles sort first;
  all `.user` rows are labeled Contact. Deleted/unknown row classification needs content-free counters before attributing it.
  System Done/prominent foreground with hidden background is an A32 contrast gap; do not claim visual parity from probe flags.
  Documentation checkpoint build `build-Debug-20261002-232053-99468-14280.log`: PASS11s, zero warnings; prohibited production/
  dependency marker scan empty, AGENTS/CLAUDE synchronized.

#### A30f1 retained profile editor and fresh save authority — 2026-10-02

- `1e072ca` (worker `ae69e9e`) keeps the exact editor, raw fields, selection and local errors through same-account client
  replacement. A fresh immutable account/actor/client scope is reserved for each explicit Save; stale Ready cannot renew it.
  Account/actor departure permanently revokes the editor, including A→B→A. The actual parent retains only its attached,
  immediate, non-revoked editor; other profile children and full profile restoration remain separate.
- A27 permission reads remain fresh before each title/description write. Predispatch loss sends nothing; after first dispatch,
  client/readiness loss leaves an explicit uncertain result without replay. Accepted partial ACK advances only that field's
  baseline. Late ACK/error cannot update fields or navigation; newer typing prevents an old success from closing the editor.
  No server-conflict reconciliation or process-death profile draft storage is added.
- References: current/pre `PeerInfoHeaderEditingContentNode.swift`111–160/97–142 reuse existing editing fields;
  `PeerInfoScreen.swift`1663–1755,1920–1956 / 4296–4377,4507–4543 captures explicit edit/save state. Pinned TDLib `td_api.tl`
  13225–13230,13329–13334,13415–13423,14617–14627 supplies the existing name/bio/chat-info and authorization contracts.
  No Telegram infrastructure copied. Primary reviewed the session, parent gate, editor and injected endpoint proof.
- Five Swift files formatted together; `build-Debug-20261002-232350-7050-2496.log`: PASS14s, zero warnings. Native editor
  probe at `1e072ca`, PID `9957`, passes production session/retention helper, actual UIKit fields/selection, stale Ready,
  immutable payload/client, partial writes, typing revision and detached/account/actor rejection. A27 permission, generic
  navigation and folder-flow regressions pass. Fresh results `23:24:47–23:24:52`; no server mutation.
- Real Saved → own Profile → Edit: enter agent-only `AstraDraft`, Home → app icon. Same PID `9957`; lifecycle log records
  ownership release `23:32:55`, recreation/Ready `23:33:18`. Same field/caret survives; typing `2` yields `AstraDraft2`.
  Back retires the stale parent to restored Saved. Reopen Profile/Edit: original empty Last name is intact. Save was never
  pressed; agent-only draft discarded. Private proof `.build/ui-probe-evidence/astra-a30f1-primary`.
- Settled foreground screenshots also expose A37 first-field overlap. This is bounded state/authority proof, not clean layout
  parity. Hardware keyboard/IME, live account switch, authorized server saves and full profile/gallery recovery remain unverified.
- A37 diagnostic follow-up adds opt-in `-ui-diagnose-profile-editor-layout`: at most 32 public bar/safe-area/field-frame samples
  on editor state/layout events, no text/IDs and no forced layout or production behavior change. Two-file format and
  `build-Debug-20261002-234312-52588-868.log`: PASS14s, zero warnings. Runtime geometry classification pending.
- At `9c0816b`, PID `56662`, both unfocused and focused same-PID foreground runs have clean settled screenshots. Instant
  ready-state samples report bar maxY150/safe minY116, but these are transition samples, not proof of persistent geometry.
  The original `1e072ca` overlap remains a valid observation; its trigger/root cause is unconfirmed. Add a delayed 0.5s
  `settled-state` sample without forcing layout; one-file format and `build-Debug-20261002-235130-62705-6888.log`: PASS8s,
  zero warnings. Agent-only `AstraLayout` was discarded via Back without Save. Private proof `.build/ui-probe-evidence/astra-a37-primary`.

#### A30f2 profile restoration prerequisites — 2026-10-02

- `9c0816b` (worker `1a39db2`) adds route-validated accepted tab/page/cursor/metadata seeds, stable message/pixel viewport,
  fitted-header timing and fresh preceding-Chat callback factory. No client-restoration activation yet.
- Five-file format; `build-Debug-20261002-234417-55831-13224.log`: PASS11s, zero warnings. Native prerequisite probe at
  PID `56662`, fresh `23:45:01`, passes seed/identity/history and actual UICollectionView prepend/header/empty/drag/layout
  checks. A30f1 editor regression also passes. Private proof `.build/ui-probe-evidence/astra-a30f2-primary`.
- Activation, production metadata RPC/callback rebinding and actual same-PID profile foreground remain pending. References:
  pinned current/pre `PeerInfoPaneContainerNode.swift`923–950/1209–1236, current `PeerInfoScreen.swift`5598–5620 and
  `PeerInfoScreenOpenChat.swift`1–58; pinned TDLib `td_api.tl`11710–11728 topic/filter/raw cursor. No infrastructure copied.

#### A30f2 activation and A38 admission review — 2026-10-02–03

- `c68c1c2` (worker `35adb4d`) restores only the topmost quiescent profile with unchanged account/actor and the exact
  preceding restored Chat. Captured-client metadata reads, source/Ready/owner gates and terminal cleanup fence replacement;
  callbacks bind to the fresh Chat. Existing editor retention remains separate. Five-file format;
  `build-Debug-20261002-235658-67695-30825.log`: PASS11s, zero warnings.
- Native probe at `c68c1c2`, PID `68772`, passes actual seed/UICollectionView/history helpers and production coordinator
  with value-only navigation entries. Suspended metadata, repeated rollover, child/detached-owner and predispatch rejection
  pass; actual PeerProfile/ChatVM/TDLib are not injected by this fixture. Existing editor and folder probes also pass.
- Actual Saved → Profile → Files → Home → app icon retains PID `68772`, Files selection, accepted visible rows and header
  geometry. Lifecycle log: ownership released `00:05:16`, restored `00:05:41`, profile replacement accepted `00:05:42`.
  Search then opens the fresh Saved Chat's focused search field. No file/gallery was opened and no message/profile/folder
  was sent or saved. Scrolled anchor, Open in Chat, repeated actual rollover and live account switch remain unverified.
  Private proof `.build/ui-probe-evidence/astra-a30f2-activation-primary`. idb timeout cleanup prints an asyncio warning;
  this is tool cleanup, not an app crash.
- Independent delta review found A38: old seed values receive new media authority without message revalidation. The route
  smoke above proves navigation/state only. Repair boundary: reuse a profile-owned bounded revision/read scheduler, close
  all unverified pixel/AX/action paths, preserve raw pagination and viewport; permanent deletion and newer partial updates
  must defeat delayed getMessage/search pages. Errors remain retryable, not fabricated deletion. No ChatVM/Root rewrite.

#### A38 shared-message revalidation — 2026-10-03

- `97ccea8` (worker `4116257`) reuses the profile-owned four-read history ledger. Every seed retains only ID/order/viewport;
  content, AX, file demand, transitions and actions await current-client admission. Scoped content/edit/delete updates revoke
  permits and visible consumers before async reads. Page admission shares revisions/tombstones and preserves unresolved IDs
  as actual loading/Retry rows; raw cursor remains server-page-derived. Exact404 `Not Found` removes; other errors and unknown
  RichMessage membership remain retryable. Attachment/Ready/anchor settlement resumes initial work; predispatch rejection
  consumes its exact request registration. No ChatVM/Root rewrite or new secret viewer.
- Gallery/PiP consumers are invalidated without revoking the profile's shared playback context. Default context teardown for
  other callers is unchanged. Independent immutable delta review found no further confirmed blocker. Active AVKit stop/layer
  latency is not proven by a Simulator helper. Six-file format; integration
  `build-Debug-20261003-002923-30429-24207.log`: PASS31s, zero warnings.
- Source `97ccea8`, PID `31005`: standalone shared-refresh probe passes actual ledger/adapter, four-read/visible priority,
  suspended delete/spoiler/page races, exact404/offline/permission/unknown-filter Retry, source/actor/topic/tab/root attachment,
  actual cell geometry/diffable anchor, permit and non-vacuous late transition rejection. Seed raw loads0; accepted loads1;
  new spoiler adds0. Full controller RPC/bootstrap and gallery/PiP teardown are source-reviewed, not injected by this fixture.
- The next standalone profile-restoration run, PID `31305`, failed `error disappeared or auto-spun`: its new error check
  resumed a read then assumed delivery after40ms. `b630844` (worker `054caab`) replaces all such delays with bounded semantic
  state and actual driver completion; one-RPC/state assertions remain. DEBUG-only handle, defer cleanup, independent review.
  Initial failure is preserved in `.build/ui-probe-evidence/astra-a38-primary/profile-restoration-probe.txt`.
  `build-Debug-20261003-003813-36345-3545.log`: PASS11s, zero warnings. A prior attempt stopped in clang metadata output
  (`003415-34099-21928`); a sample showed blocked pipe write. Only that owned build was interrupted; retry needed no cache
  removal, toolchain or Simulator reset. Source `b630844`, PID `39878`: complete profile-restoration plus explicit A38 checks pass.
  Fresh result: `.build/ui-probe-evidence/astra-a38-settled-primary/profile-restoration-probe.txt`.
- Regressions at `97ccea8`: profile-grid concealment, general media reveal and PiP context pass PID `31707`;
  native/FFmpeg gallery-owner, continuity, stop/cancel and sample-buffer PiP factory pass PID `32182` (system PiP unsupported).
- Actual source `97ccea8`, PID `32182`: Saved → Profile initially populates Media/Files. Scroll Files, Home→app icon;
  ownership released00:35:34, restored00:35:56, profile replacement accepted00:35:56.658. Settled first full row remains
  y151/height52.667 with the same following rows, confirming this scrolled anchor and nondefault tab survive revalidation.
  No file/gallery opened and no message/profile/folder saved. Selecting an older row returns to the fresh Chat but does not
  reach the target after settlement; tracked separately as A39, not counted as successful Open in Chat. Private screenshots
  and reports stay under `.build/ui-probe-evidence/astra-a38-primary`; peer names/IDs/file names are not copied into this ledger.
- References: pinned current/pre `PeerInfoVisualMediaPaneNode.swift`1769,1795–1847/1703,1720–1766 uses account-owned reactive
  message/placeholder state; `PeerInfoPaneContainerNode.swift`923–950/1209–1236 retains selection. Pinned TDLib `td_api.tl`
  10318–10326,10583–10587,11397–11400,11710–11724; `Requests.cpp`592–606 and `Td.cpp`1400–1401 define exact absent-message
  error; `MessageContent.cpp`6479+,6537–6538 and `WebPageBlock.cpp`2613–2617,2727–2731 define rich media filter uncertainty.
  No Telegram infrastructure copied. Repeated live races, newly arrived head messages, rich UI, rotation/Dynamic Type and
  system PiP remain separate limits.

#### A30g member/admin route recovery — 2026-10-03

- Baseline `72d74b0` (documentation HEAD `59ca5a9`): profile topmost gate233–239 and removal954–982 discard the
  profile suffix while its Members/Admins child is visible. The child retains an immutable old client and does not participate
  in navigation restoration. This is distinct from the already-supported ordinary profile editor.
- Actual audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone17Pro/iOS26.5, PID `30616`: existing basic group →
  Profile → Members shows three rows at y116/189.333/262.667, each73.333pt. Home02:19:29 releases TDLib ownership02:19:30.327;
  foreground02:23:52.455 restores it. Settled hierarchy and screenshot show Chat, with Members and Profile removed; PID stays30616.
  Private pixels are under `.build/ui-probe-evidence/astra-a30g-baseline`. No tag/editor/save/send/delete/export action occurred;
  normal chat-read side effects remain possible. idb supplies input/hierarchy; `simctl io screenshot` supplies pixels because the
  idb screenshot backend is unavailable. The Simulator window was not activated or shut down.
- Bounded repair contract: retain only a quiescent exact adjacent Profile/Members stack through same-account Ready; transfer
  accepted member IDs, raw cursor and row geometry/anchor, never old TDLib member objects or action authority. Re-read current
  availability and membership with bounded page demand; fence account/actor/client/attempt and late callbacks. Preserve raw
  server order/pagination and fresh tag preflight. Active tag editor, Save uncertainty, modal and active gestures stay separate.
- References: pinned current/pre `TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoMembers.swift`
  136–190/136–188 and305–307/292–294 retains account-owned accepted state/loading/pages. TDLibKit `1.5.2-tdlib-1.8.66-022d6020`,
  TDLib `022d6020`: `getBasicGroupFullInfo`, `getChatAdministrators`, `getSupergroupMembers`. No Telegram infrastructure copied.
  The implementation and bounded after-fix proof follow; these references do not establish complete member-management parity.
- Baseline documentation validation `build-Debug-20261003-022901-39675-31468.log`: PASS5s; complete log has zero warnings/errors.
  No Swift change in this checkpoint.
- `55ff037` (worker `0c2e1a2`) implements exact adjacent Profile/Members retention, same-account/actor restoration,
  stable member-ID/pixel geometry and neutral quarantined rows. Current `getBasicGroupFullInfo`, `getChatAdministrators`,
  or one 100-row `getSupergroupMembers` page per demand revalidates rows. Raw offset remains separate from deduplicated IDs
  and the retained extent. Source/generation/attached-owner checks precede dispatch and follow every response; scoped
  member/group/permissions changes invalidate immediately, with semantic full-info dedup preventing self-triggered replay.
- Independent review found that a replaced Profile can stay unloaded beneath Members across another ownership epoch.
  `f9b5dad` (worker `50a299a`) installs ownership/Ready observation at init, keeps UI/media work view-bound and transfers
  accepted seed state without materializing the covered Profile. `e049da3` (worker `6b5a29d`) adds plain visible Retry for
  deep retained-page failures, synchronous neutral error cells, and per-failure UUID/generation/source/top-owner checks.
  Errors do not automatically retry; old buttons cannot consume a newer failure. Both followups passed independent review.
- Primary integration builds `build-Debug-20261003-025548-60862-15401.log` (10s) and
  `build-Debug-20261003-030933-90779-22519.log` (15s): PASS, full logs contain zero warnings/errors; changed Swift files
  formatted together. Initial PID `62735` Members probe failed an immediate combined UIKit pop/retirement assertion.
  The corrected fixture retains synchronous authority rejection, then boundedly waits for actual lifecycle cancellation;
  it does not relax production guards. Source `e049da3`, PID `99916`: Members and existing Profile probes both pass.
  Members proof covers production replay/revision/ABA and coordinator helpers, actual unloaded-Profile callbacks, native
  Members table/quarantine/anchor/fresh partial page/pop cancellation, visible Retry, no auto-retry, covered/unready/stale
  generation/old-button rejection and predispatch cancellation. Generic parent navigation entries remain value adapters;
  no TDLib RPC, server permission change or global client swap is injected by the probe.
- Actual source `f9b5dad`, PID `62735`, same audit Simulator: Members retains all three baseline row frames through
  release03:01:08.920 → restore03:02:00.705 and release03:07:27.277 → restore03:08:13.888. The second cycle leaves the newly
  replaced Profile unloaded beneath Members. Profile replacement acceptance logs occur03:02:00.929 and03:08:15.915.
  Back reaches Profile; Admins shows one Owner row at y116/height73.333, then retains it through release03:10:49.847 →
  restore03:11:36.553, acceptance03:11:36.718. Back again reaches current Profile controls. Settled rows contain no Updating
  placeholders. Names/IDs are omitted here; ignored pixels are under `.build/ui-probe-evidence/astra-a30g-primary`.
- Runtime bounds: small basic group only; no member/tag/editor/save/send/delete action, real network-error injection,
  live permission loss, large supergroup pagination or active-editor recovery. Normal chat-read effects remain possible.
  Native error fixtures prove the local path, not live offline recovery. Existing A32 native circular Back remains open.
- Documentation validation `build-Debug-20261003-031613-8760-19481.log`: PASS5s, full log zero warnings/errors. Forbidden
  production/dependency marker scan is empty; AGENTS/CLAUDE agree. No new Swift change in this documentation checkpoint.

#### A30h member-tag editor renewal: repair contract — 2026-10-03

- Source `2190c4d`, primary and independent review: `PeerProfileControlsViewControllers.swift`314–326 pushes the tag editor
  above Members. `PeerProfileMembersRestoration.swift`145–151 requires Members itself topmost, so Profile's retention gate
  (`PeerProfileViewController.swift`234–242) fails; synchronous client-change handling1017–1021 reaches1095–1123 and drops
  Profile/Members/Tag together. The tag editor1170–1188 captures one immutable old client and has no renewed edit session.
  This is a concrete source-proved P1, not a claim that the live account's authorized editor was exercised.
- Bounded change: hold only the exact attached adjacent Profile→Members→Tag chain for the same account and actor, preserving
  the existing editor, text/selection/marked input and visible errors. Keep stale parents quarantined and defer their replacement
  until editor closes; do not widen generic Members.canRetain or Profile replacement eligibility. Existing parent restoration
  resumes afterward. Reuse/extend the existing PeerProfileEditSession rather than replacing the navigation architecture.
- One explicit tag Save gets a current Ready endpoint and repeats getChat plus actor/target getChatMember, permissions and
  captured-baseline conflict checks before setChatMemberTag. Preserve empty-tag removal and validation. Source/actor/detached
  changes must prevent dispatch; a possibly dispatched write becomes uncertain with no automatic retry. A delayed ACK must not
  pop over newer typing. No live tag/rights mutation is authorized by this smoke; use controlled endpoints for those boundaries.
- References: current `6ad963e` `TelegramUI/Components/ChatParticipantRightsScreen/Sources/ChatParticipantRightsScreen.swift`
  63–64,250–274,502–516 and `TelegramCore/Sources/TelegramEngine/Peers/Ranks.swift`15–42 preserve rank edit intent and
  account-owned explicit commit; pre-Liquid `8e7e5f` `PeerInfoUI/Sources/ChannelAdminController.swift`
  922–933,1150–1155,1304–1311 owns updated rank/focus. These do not prove Telegram behavior under TDLib client recreation.
  TDLib `022d6020`: getChat/getChatMember/setChatMemberTag and canEditTag/canManageTags; preserve the existing authority matrix.
- Planned proof: actual UIKit editor with exact-chain retention and controlled edit endpoints; repeated same-account epochs,
  raw text/selection, predispatch cancellation, postdispatch uncertainty/no replay, new typing versus delayed result and Back
  release. Existing profile/member probes must pass. Live authorized editing remains unavailable unless naturally permitted;
  no synthetic production route or server changes to create the fixture.

#### A30h member-tag editor renewal: integrated proof — 2026-10-03

- `c895a8c` (worker `68b6fae`, reviewed tree `736de4e`) keeps the existing editor/UITextField behind a separate exact
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

#### A39 explicit target navigation — 2026-10-03

- `1b1429f` (worker `4fc6d02`) retires retained viewport intent when accepting explicit navigation, consults the current
  snapshot marker, and holds target/quote until snapshot, layout, window and source are valid. Pending navigation fences
  initial/latest compensation; gestures, supersession, source revocation and failed admission retain their cancellation rules.
  Initial positioning is synchronous; navigation in an initialized Chat remains animated. Existing ChatVM history logic is
  unchanged apart from opt-in content-free phase diagnostics. Three-file format; integration
  `build-Debug-20261003-005409-91096-31077.log`: PASS31s, zero warnings.
- Independent review found a final-release wakeup missing from rotation and a loaded fast-path bypass. `17e3fb4` (worker
  `f6899a0`) pairs all nine layout owners through one release helper and retries pending navigation after the last external
  release. Explicit scroll's own release does not recurse into unavailable layout. Delta review is clean; three-file format,
  `build-Debug-20261003-005819-95305-8829.log`: PASS9s, zero warnings.
- Source `17e3fb4`, audit Simulator PID `95662`: viewport-authority and complete profile-restoration/A38 probes pass.
  Navigation fixtures use the actual ticket/viewport/release helpers and real UICollectionView/diffable layout, but a
  value-only consumer, not full ChatView/ChatVM or system rotation. They do not test the production animated-scroll/highlight
  sequence. Reports: `.build/ui-probe-evidence/astra-a39-primary`.
- Cold control at `b630844`, PID `39878`, without Home/client rollover already failed to reach the same old Files target
  after about70s (`astra-a38-settled-primary/cold-target-settled.png`). The observed failure is not specific to restoration.
  At `17e3fb4`, PID `95662`, fresh Saved → Profile → Files → older June document at01:03:16 also returns to latest September/
  October messages. Phase reads `applied`, target AX is absent, and settled screenshot confirms the miss. Repeating the same
  already-loaded target at01:05:51 moves only to early September, still without the target. No file opened/downloaded and no
  message/profile/folder saved. Private screenshots and phase remain under the A39 evidence directory.
- `8b8d149` (worker `805a07b`) adds opt-in numeric geometry to actual ChatView and renames the misleading pre-command phase
  to `offset-command`. At most64 samples, reserved settled checks, lazy metric capture, weak exact-request delayed callbacks,
  serial background JSON writes; no IDs/content exported and no scrolling policy changed. Both-file format and independent
  immutable review pass. Integration `build-Debug-20261003-011303-7581-26376.log`: PASS10s, zero warnings.
- Actual source `8b8d149`, PID `8251`, only `-ui-probe-message-navigation`, cold Files target tap01:14:45: window is ready67ms,
  explicit animated command70ms requests5627.833 from-94.333. Two highlight snapshots finish before motion continues through
  -51,78.333,289. Automatic capture at115ms sees pending0; automatic restore153ms calls anchor writer154ms, synchronously emits
  animation-end and rewrites offset to78.333. At10.571s, current target5743.833 remains offscreen, correct mapping/source/window
  flags all hold. This proves mid-flight automatic compensation interrupts explicit navigation; immediate highlight cancellation
  is rejected for this run. Which automatic capture caller (self-size versus reconfigure) is not distinguished, and animation-end
  alone is not successful arrival. Native helper did not exercise this production sequence.
  Trace, failed settled screenshot and AX check: `.build/ui-probe-evidence/astra-a39-geometry`; no send/edit/delete/export or
  file open was invoked. Normal read-state side effects of chat navigation are not excluded.
  Last persisted settled sample is10s; the scheduled25s sample is absent, so do not claim25s diagnostic coverage.
- Diagnostic-proof documentation build `build-Debug-20261003-011704-11526-27558.log`: PASS6s, zero warnings.
- Repair boundary: hold explicit navigation authority until measured target settlement; gate automatic and inset/anchor
  compensation during flight, remeasure estimated cell geometry, and retire authority on drag/new target/latest/source change.
  Preserve animations, quotes, current source and the existing history/revision contracts. No wholesale timeline or loader rewrite.
- `6a29431` (worker `1af25c6`) adds the production native-scroll settlement driver and gates compensation until fresh raw
  membership, current source, mounted visible cell and two stable geometry observations agree. Drag/latest/cover/source/new-target
  cancellation retires it; quotes/highlight start only on success. Independent immutable review passes. Four-file format0/4.
  Integration `build-Debug-20261003-014324-25949-6943.log` succeeds13s but has one metadata warning; it is not warning-free (A40).
- Audit Simulator after user app restart: same audit UDID/runtime, authentication preserved, source `6a29431`, PID `26494`.
  Native viewport-authority probe passes actual production driver/native animation/estimated UICollectionView plus cancellation,
  remap, supersession, deferred layout and failure deadline. Full ChatView wiring is checked by the separate real flow below.
  idb hierarchy/input works; screenshot backend fails, so `simctl io screenshot` supplies pixels without activation or data reset.
- Actual cold Saved → Profile → Files → old June target at01:46:27 now reaches the message, but phase is `scroll-failed`.
  Native command50ms→5627.833; native end360ms; corrections404ms→7031.5 and504ms→6854.5. Subsequent UIKit geometry leaves
  offset6900.333 versus target6854.167 (46.167pt error); target AX/cell are visible through25.152s. No automatic anchor writer
  interrupts flight. The two-correction limit fails before highlight; cold settlement remains open, not counted as complete.
- Repeating the already-loaded target at01:49:10 passes `scroll-settled`333ms; target mounted/visible, offset6953 versus
  desired6953.167, stable10.501s. AX target y387.667/height118 and settled screenshot agree. Evidence:
  `.build/ui-probe-evidence/astra-a39-settlement/{cold,loaded}`. No send/edit/delete/export/file open; ordinary read-state effects
  are possible. Next repair is progress-bounded convergence under the existing deadline, not a relaxed visibility-only success test.
- `982245f` (worker `9eee50d`) permits at most8 final corrections, requires measured residual improvement with only one stalled
  pass, and retains the2s failure-only deadline. Nonanimated UIKit offset changes keep geometry checking alive. Exact0.75pt,
  mounted/visible cell and two-frame stability remain mandatory; there is no visibility-only success. Independent review passes.
  Native probe adds successive real estimated neighboring cells plus explicitly injected residuals; stall/oscillation limits pass.
- Final audit Simulator source `72d74b0` (includes `982245f`), PID `30616`: expanded viewport-authority probe passes. Actual cold
  target tap02:02:22 settles572ms after three corrections, offset6808 versus target6808.167. Target AX y387.667/height118 and
  settled screenshot agree; error-0.167pt remains stable25.297s.
- Same PID: scrolled Files target y188.667/height52.667 before Home02:05:03. Lifecycle logs confirm ownership released02:05:05.027,
  restored02:06:01.959, profile replacement accepted02:06:02.647. Files keeps the same row geometry. Open in Chat02:06:57 settles
  224ms on the fresh client, offset5450.667 versus5450.5, mounted target AX y388/height118, stable25.152s. Repeating the loaded
  target02:11:15 settles38ms with the same0.167pt error and geometry, stable25.151s.
  Proof: `.build/ui-probe-evidence/astra-a39-convergence/{cold,foreground,loaded}` plus fresh native report. No sends, file opens,
  deletes, exports or account resets; ordinary read-state effects remain possible. This closes the measured target defect, not
  exhaustive quote/album/rotation/gesture parity. A40/A41 below provide final warning-free integration builds.
- Documentation checkpoint `build-Debug-20261003-021404-33516-4379.log`: PASS5s, complete log zero warnings/errors; prohibited
  production/dependency marker scan empty, AGENTS/CLAUDE identical. Simulator remains booted and was never activated separately.
- References: pinned current/pre `ChatControllerNavigateToMessage.swift`342–422,474–507/333–360 distinguishes loaded target
  navigation from cancellable 50-message initial search and target/missing completion. Pinned TDLibKit `getChatHistory`,
  `getMessage`, captured ChatLocation and current history revision admission remain unchanged. No Telegram infrastructure copied.
- Follow-up diagnostic `f8bcab3` (worker `fd1ae68`, reviewed tree `265e323d`) adds an opt-in192-event DEBUG value trace,
  terminal deadline/budget reasons, geometry before consumer target clear and separate post-result outcome/visibility/quote.
  No extra driver resolve/layout calls;2s watchdog,3s probe wait,0.75pt threshold, correction budget and predicates unchanged.
  Worker format/build `155938-6424-25004` PASS14s/fullzero; primary joint format0/2/build `160215-12692-11186`
  PASS11s/full1486-line log zero warnings/errors. Current reference `6ad963e5` and pre `8e7e5fe`,
  `submodules/TelegramUI/Sources/Chat/ChatControllerNavigateToMessage.swift`342–380/333–365 rechecked read-only.
- Audit59EB535C/iOS26.5 standalone run1 PID15417/container `BABBC350-720B-4207-8832-1DDA59F3166D`, report16:03:20 PASS;
  run2 PID18301/container `D3CFE2EE-CACA-4105-B7D5-13427693DC49`, report16:04:15 PASS. Run3 PID22802/container
  `BB7C17B1-AF0D-43A6-B547-E42A60414EE4`, report16:06:29 FAIL on unchanged source/product. Full content-free receipts are
  preserved under `.build/ui-probe-evidence/astra-a39-diagnostics/{first,second,third-failure}.txt`; no UI gesture or server mutation.
- Run3 identifies a deadline failure, not correction-budget rejection or a post-result-only oracle failure: commands `[true]`,
  no corrections, target not intersecting/mounted/visible both before clear and after completion, residual304.5pt. Native ends
  arrive0.342s and1.299s. First verifier observation0.591s sees offset4626.6667/target4258.5; second2.151s sees4563/4258.5,
  stops checking and clears receivedEnd. Deadline fires2.156s. The second accepted end retained the old first observation.
  End-reset is observed, but that frame was already after the2s budget: this does not prove it caused the timeout.
- Timing follow-up `31e497a` (worker `b3c1d2c`, exact peer-reviewed tree `b1abbf3a`) adds callback entry/display-link timestamps,
  timing around existing resolve calls and bounded aggregates from existing10ms wait resumptions. No extra timer, task,
  resolver/layout call, deadline extension or predicate change. Joint format0/2; primary build `161829-36511-3066` PASS11s,
  full1482-line log zero warnings/errors; worker `161246-31131-24056` PASS9s/fullzero.
- Same Audit Simulator timing run1 PID37004/container `7CAE36F2-8631-458B-A80C-59907020F3CE`, report16:19:13 PASS;
  run2 PID38384/container `261CC0A4-26C1-45F0-B685-AC69CF6AE3DF`, report16:20:15 FAIL. Native end0.343s; callback entries
  1.2465/2.2683s with display timestamps0.5304/1.3458s: delivery delays0.716/0.922s. Callback durations0.118/0.295ms,
  resolver spans0.054/0.027ms. Completion wait has20 resumptions/maxGap0.670s, including378/430/670/347ms gaps.
  This establishes main-actor/run-loop scheduling delay in this run, not continuous thread blocking or its source.
- Run2 reaches a mounted/visible target with0.167pt residual after correction at2.268s, but deadline2.316s precedes the next
  two-frame recheck. Commands `[true,false]`; no end-reset or correction rejection. Thus earlier end-reset is not necessary
  for this intermittent deadline. Full content-free reports: `.build/ui-probe-evidence/astra-a39-diagnostics/timing-{first,second}.txt`.
  No actual ChatView navigation or server mutation is exercised by this isolated native fixture; no production timeout fix claimed.
- Next bounded counterexample: hold only verifier delivery, accept genuine native end1 and one sample, inject a separately
  labeled native offset animation, then accept genuine end2 before the next sample. Establish whether retained pre-end2
  geometry loses the current checker. Keep natural animation/cancellation checks; a repair must retain stale-end protection,
  exact visible/centered settlement, correction budget and deadline. This is separate from scheduling-delay diagnosis above.
- Timing checkpoint build `162308-41757-22286` PASS8s; complete1385-line log zero warnings/errors. Production/dependency
  prohibited-marker scan empty; AGENTS/CLAUDE identical; only this checkpoint document remained uncommitted before recording.
- Controlled latest-end baseline `f564580` (worker `d22ea3e`, exact reviewed tree `ea732dcf`) adds a dedicated
  `-ui-probe-navigation-end-order` fixture. DEBUG manual verifier delivery retains the actual display link and admits calls
  only while the production checker/current command exists. Native delegates are forwarded; no receivedEnd/sample setters.
  Its accurate48pt estimates isolate ordering; the existing natural fixture retains80pt estimates and automatic frames.
  Joint format0/3; primary build `163140-63493-4382` PASS19s/full1486-line log zero warnings/errors; worker
  `162945-60442-7840` PASS8s/full1450-line log zero warnings/errors. Separate setup/deadline INCONCLUSIVE and contract FAIL.
- Audit baseline PID64657/container `321FBD05-6B75-4D61-AF06-D916B2846B1D`, report16:32:27: definite FAIL at0.8111s,
  before2s. Genuine end1 arrives0.4351s; first manual sample0.4444s records1696pt. A deliberately injected second native
  animation reaches1760pt; genuine end2 arrives0.7736s. Next manual observation resets receivedEnd and stops the checker,
  while ownership/target remain, commands `[true]`, no result or quote, residual64pt. The hook refuses a further frame after
  checker retirement. Six automatic callbacks were held. Full report: `astra-a39-diagnostics/end-order-baseline.txt` under
  `.build/ui-probe-evidence`. This is a controlled driver liveness counterexample, not actual ChatView relocation proof.
- Bounded repair plan: every accepted end invalidates both previous geometry samples while preserving the existing display
  link. Require two post-latest-end stable observations before correction/settlement; retain motion/stale-end rejection,
  visibility/centering, request/command identity, cancellation, correction cap and2s deadline. No loader/timeline rewrite.
  The independently measured scheduling-delay timeout remains open and is not explained or repaired by this change.
- `e70a227` (worker `442e33e`, reviewed tree `548cf025`) implements exactly those two sample resets plus a comment.
  Accepted-end guard, current link/command, resolver calls and all failure/success predicates are unchanged. Reentrant end
  during resolve invalidates samples before the verifier reads them; movement between new samples still drops stale-end
  authority. Joint format0/3; primary build `163554-69774-7770` PASS8s/full1450-line log zero warnings/errors; worker
  `163342-66161-9874` PASS32s/full1450-line log zero warnings/errors. Exact-tree independent review PASS.
- Same Audit Simulator fixed controlled run PID70456/container `789ECA0E-CC76-4F42-86A2-C043AA4C26C2`, report16:36:36 PASS.
  The contract now requires two post-latest-end observations before one nonanimated correction; this dedicated scenario
  does not claim complete settlement, real ChatView relocation or the cause of earlier spontaneous timeouts.
- Ordinary automatic-frame viewport regression on the same source/product PID70970/container
  `1016F44C-2C52-4952-B2A4-7D1C9E79362C`, report16:37:19 PASS: native animated resize/quote, album remap, new-target/stale end,
  drag/latest/source/cover/missing-member cancellation, tracking-only retirement, deferred layout, failure deadline and
  successive self-size correction bounds. Consumer remains value-only; actual ChatView/TDLib/hardware gestures are not proved.
  Full reports: `.build/ui-probe-evidence/astra-a39-diagnostics/end-order-{fixed,natural}.txt`. No fixture RPCs or account-store
  mutations; Simulator remains booted and host focus was not activated.
- Final latest-end checkpoint build `163857-71725-11058` PASS5s, full1385-line log zero warnings/errors. AGENTS/CLAUDE
  identical; prohibited production/dependency markers absent; implementation commits and this focused proof record preserve
  unrelated files. Next: one bounded native startup profile to attribute scheduling delay, then queued ChatView mutations.
  Goal remains active; repeated-end actual ChatView behavior and spontaneous timeout root cause remain unverified.
- Documentation checkpoint `build-Debug-20261003-010725-3164-28383.log`: PASS5s, zero warnings. AGENTS/CLAUDE remain identical;
  prohibited production/dependency marker scan is empty. The reusable prompt also records background-only Simulator activation.

#### A51 rich-notification cache work and account boundary — 2026-10-03

- Baseline `1c72d3a`/production `e70a227`; unchanged product from final build `163857-71725-11058`. ETTrace runner/framework
  are absent, so one bounded native `sample` capture uses the existing binary with no temporary dependency or project patch.
  Audit Simulator59EB535C/iOS26.5, PID74960, launch16:41:43.101; sample starts16:41:43.211 for4s at requested1ms interval.
  Installed/product `BetterTG.debug.dylib` UUID both `C0AB6393-0C4C-3302-822B-E0934568680C`; installed bundle UUID-directory
  `037BB6D0-97E9-4552-A392-244CC9CD9041` matches the sampled executable path. First-party hot stacks have source symbols.
  Sample omits its binary-images table; retain that limit. Artifact: `.build/ui-probe-evidence/astra-a39-diagnostics/startup-sample.txt`.
- Independent full first-thread tree audit:1931 main-thread observations,8243 parsed nodes at sample lines24–8266;
  disjoint notification sinks628/1931=32.5% (chat418,user210). Inside those628: normalize/decode/JPEG266; atomicwrite197;
  cache URL/AppGroup/directory lookup139; source Data read19; other7. Do not add nested inclusive counts. UIKit accessibility
  startup381/1931=19.7% and earlier dyld bootstrap182/1931=9.4% are separate branches. Sample weights include waits and are
  not CPU milliseconds; instrumentation, startup/cache/network state and AX activity limit timing claims.
- Same-PID report16:41:47/container `72E59F99-2256-47EA-A19B-AC074DA6EA0F` fails A39 deadline. Motion wait0.520s;
  completion maxGap0.532s. Last verifier arrives2.271s for display timestamp1.645s; deadline2.293s. Target is mounted/visible
  at0.167pt residual after two corrections, without the final pair of observations. This correlates cache work and delayed
  delivery in one launch; it does not prove a sole cause or quantitative speedup. Full report: `startup-profile-probe.txt` nearby.
- Source: `RichNotificationCacheCoordinator.swift`30–41 receives raw TD updates on main;74–93 performs placeholder/full-avatar
  normalization/write and loads completed files before checking registered references. Each unrelated completed file may
  therefore be read. Refresh/media closures reuse global `td` across awaits. `RichNotificationCache.swift`48–62 uses shared
  peer/message keys; `NotificationService.swift`53–54 falls back to active account for an unmatched notification account.
- Bounded A51a prerequisite: require positive Telegram account-user ID for cache reads/writes, new account namespace,
  nil/mismatch fail closed, no legacy lookup/deletion. Preserve logical peer/message keys, JPEG format/dimensions and intent
  identifiers. Scoped current-source event admission and captured immutable client/account around awaits; clear file mappings
  on client replacement. NSE session/account selection must not put another account's bytes in metadata's namespace.
- Then A51b: move complete avatar jobs (source read, directory lookup, normalization and write) to a bounded serial utility
  worker, coalescing latest pending work per scoped destination. Preserve fallback/update ordering and invalidate old demand.
  Do not dispatch an unbounded block per event or move only JPEG conversion. Media work and full notification lifecycle
  remain explicit until separately covered. Preserve no-server mutation probes and before/after source/build/UUID proof.
- Adjacent baseline findings: avatar file mappings retain superseded same-account photos; source namespace alone does not
  provide photo-version ordering (A51b below repairs this map). NSE's unmatched-message fallback and unstructured resolution task/expiry
  ownership are A52, outside the cache-namespace prerequisite. Do not label this flow fully account/lifecycle-verified.
- Telegram references: official `6ad963e5`, `Telegram/NotificationService/Sources/NotificationService.swift`467–491 uses
  the selected account's MediaBox cache,855–880 selects notification account by payload key,902–934 keeps state on its queue.
  Pre-Liquid `8e7e5fe` same path459–483/785/849–872 retains account cache/queue behavior. Adapt contracts only; no MediaBox,
  Postbox or SignalKit copied. TDLibKit `1.5.2-tdlib-1.8.66-022d6020` models/APIs remain unchanged.
- A51a fix `38b7d06` (worker `47ec08e`, exact reviewed tree `e07df0d`): all avatar/media cache callers now require a positive
  Telegram user ID; disk paths use `RichNotifications/accounts/<userID>`, without changing logical peer/message/Intents keys.
  NSE selects only an exact metadata-account match. Five coordinator TD update sinks use scoped publication, capture the
  original client and recheck source/account/client after awaits; completed files are read only when references exist.
  Reference maps reset on client generation change. Invalid scope exits before lazy container resolution. JPEG contracts remain.
- Worker joint six-file SwiftFormat and build `170232-12469-13006` pass. Primary integration build `170800-18896-18037`
  passes10s; complete log has zero warnings/errors (success at line1560). Independent peer reviews the exact tree; no unrelated files included.
- Native isolated probe at `38b7d06`: Audit Simulator59EB535C/iOS26.5, PID19449, fresh container
  `2466B327-A10B-4455-814E-5AB9A0A10601`, report17:08:34+04. `-ui-probe-notification-cache-scope` passes actual JPEG/cache IO
  in a UUID temporary root, exact red/blue avatar/media bytes for colliding IDs across accounts, nil/0/negative zero resolver
  calls, no legacy fallback or mutation of130 legacy media entries, queued scoped publication, independent wrong-client/user
  negatives and reused file IDs after account/client replacement. Fixture RPC/account-store writes=0; owned fixtures are removed.
  Report: `.build/ui-probe-evidence/astra-a51/cache-scope.txt`. Actual coordinator delayed RPCs, NSE delivery/expiry, media task
  bounds and main-thread relief are unverified. No performance claim belongs to this prerequisite.
- Planned bounded slice (implemented below): A51b serial utility avatar worker with bounded/coalesced pending jobs, current-photo reference replacement,
  and same-photo candidate quality ordering. Entire read/normalize/path/write must leave main; no unbounded dispatch block per
  event or main-contended lock held during disk IO. Keep account/client invalidation and fail-closed cache scope. Then one
  comparable startup capture, with cache/startup variance retained; A52 and actual queued ChatView proof stay open.
- A51b design boundary before implementation: one active job and at most128 pending scoped destinations; revoke on synchronous
  authorization invalidation as well as source replacement. Success-only bounded dedupe must allow failed writes to retry.
  Generation checks can reject work before publication, but an already-entered atomic write may finish in its captured account
  namespace. Serial order prevents an older app job overwriting a newer app commit; strict no-write-after-NSE-handoff needs
  a separate drain/versioned-publication contract. Media IO, task/RPC lifetime and full NSE correctness are outside this slice.
- A51a checkpoint build `171052-22021-9011` passes4s, full1385-line log zero warnings/errors. AGENTS/CLAUDE remain identical;
  prohibited production/dependency marker scan is empty. Goal remains active; next implementation is the bounded A51b slice.
- Pre-A51b paired baseline after the namespace change: source `9d8003d`/production `38b7d06`, same final build above,
  same Audit Simulator and only `-ui-probe-viewport-authority`; PID24933. Launch17:12:53.045+04, sample17:12:53.148 for4s/1ms.
  Installed bundle `B0BB3B10-B68A-4673-B618-4B2A7AB72BED` matches the sample path; installed/product debug-dylib UUID both
  `067931AE-7CD7-3FA2-8EC6-92061BAFD04F`. Main-thread observations2288; symbolicated cache stacks remain. Binary-images
  table is again unavailable. Same-PID viewport report17:13:01 passes, which further limits any sole-cause claim about the
  earlier deadline failure. Container `2DCEB9EF-3155-42B7-8A65-D5A1538AF1A9`; saved `avatar-baseline-sample.txt` and
  `avatar-baseline-context.txt` under `.build/ui-probe-evidence/astra-a51`. This run exists to separate the upcoming worker
  change from account-namespace/cache warm-up; it is not a statistically controlled latency benchmark.
- Independent baseline tree audit:8340 nodes at lines24–8363, exclusive sum2288 with no negative nodes. Disjoint user/chat
  cache subtrees994/2288=43.44% (user412,chat582). Within994: atomic Data.write352; normalization/ImageIO/JPEG334;
  URL/AppGroup/directory277; source reads21; protection attributes1; other9. Avatar descendants993 and sink totals999 overlap
  this count and must not be added. Whole-main top leaves include mach_msg2_trap448 and __ulock_wait2 387; waiting is included.
- A51b fix `6b187b0` (worker `ffec9ac`, exact independently reviewed tree `8e4a1f17`): one serial utility drain, at most128
  pending peer batches with up to3 ranked candidates each, and256 success receipts. Main submits immutable metadata/paths;
  source reads, cache-directory lookup, image decode/JPEG, atomic writes and protection attributes run on utility. Pending
  overflow drops oldest best-effort prewarming. Locks cover metadata only, never IO. Failed high-rank candidates fall back
  to small/placeholder; successful quality survives receipt eviction, and failed writes remain retryable.
- Current photo revisions replace old reverse file references and reject held stale work. Authorization nil synchronously
  invalidates pending jobs, including TDLib handoff without activeClientChanges. Same-account client replacement gets a new
  generation. Refresh request UUID plus per-peer photo-change sequence rejects superseded same-source getChat results, also
  when a newer user-photo admission replaced that destination; unrelated peers do not invalidate it.
- Worker joint five-file SwiftFormat/build `172444-41649-30775`: PASS8s, full1458-line log zero warnings/errors. The earlier
  `172139-37803-1252` Gate Sendable warning was repaired by auditing all mutable gate state under lock/semaphore; it was
  not suppressed. Primary integration build `172737-45171-21885`: PASS13s, complete log zero warnings/errors, success1572.
- Native combined cache-scope/worker probe at `6b187b0`: PID46367, Audit Simulator59EB535C/iOS26.5, fresh container
  `8E662CBF-C9BE-4180-9EE7-08995B18DB99`, both reports17:28:19+04 PASS. Actual isolated JPEG/filesystem work covers100-offer
  coalescing, one held active job, bounded pending/receipt eviction, quality after receipt eviction, old-photo and source-ABA/
  client-replacement rejection before write, exact fresh bytes, missing-big→small and corrupt-big/missing-small→placeholder,
  all-candidate write failure and retry. Container resolution rejects main-thread access in the worker fixture; synchronous
  worker IO remains on its utility queue. Cleanup revokes/drains owned workers before removing only their UUID fixture root.
  This does not exercise real delayed coordinator TDLib RPCs or NSE delivery. Saved `avatar-worker-native.txt` nearby.
- One post-worker startup capture uses the same wrapper/probe flag and4s/1ms request: PID49173, launch17:29:11.408+04,
  sample header17:29:11.710. Bundle `11D7EF11-4A25-4D73-83FC-7EF5F6A80FBE`; installed/product/sample binary-table UUID
  `BE0DFC28-05EE-374C-B849-264D354E5831` agrees. Main3174 observations are all idle mach_msg2_trap; no avatar-worker/cache
  stack appears on any thread. This capture lacks equivalent active work and cannot prove994→0 improvement, source-level
  startup speedup or actual production avatar-job execution. Attach/setup timing and warm state remain uncontrolled.
  Same-PID viewport report17:29:17 PASS in container `4E37FF80-13B4-4E3E-B298-072A084EAC18`; no deadline was relaxed.
  Artifacts: `avatar-worker-sample.txt` and `avatar-worker-profile-context.txt` nearby. Align a future measurement with actual
  production job start/end receipts before claiming a before/after performance result; do not repeat blind launches.
- Remaining A51: current-source per-peer registration metadata is uncapped; photo removal revokes jobs but leaves the previous
  JPEG on disk; already-entered atomic write may finish after handoff. Media IO/task bounds and A52/A53 are unchanged.
  Source/native-worker evidence supports this bounded avatar repair, not complete notification correctness or A39 causality.
- Independent post-profile audit confirms114 call-graph nodes/10 threads, no negative exclusive weights, main entirely
  idle; launch-to-header delay302ms versus baseline103ms does not establish active-window alignment. No further capture or
  user-cache deletion was attempted. Future profiling needs content-free production job receipts before a matched capture.
- Final A51b checkpoint build `173407-60281-18514`: PASS5s, full1385-line log zero warnings/errors. AGENTS/CLAUDE match;
  prohibited production/dependency marker scan is empty. Worker checkout is clean, all implementation changes are committed;
  only this ledger awaits its focused commit. Goal remains active; A53 is the next bounded implementation.

#### A52a exact notification correlation — 2026-10-03

- `878e85f` replaces unrelated-last and shifted-only matching with `RichNotificationTarget`: positive exact account,
  peer kind/ID, ordinary cloud server ID in1...Int32.max, exact TDLib raw ID with zero local/scheduled bits. Invalid metadata
  is rejected before creating a TDLib client. The actual getChat response must match requested chatID and metadata peer;
  newMessage also requires its embedded message.chatId. Every getMessage/history candidate rechecks chat and raw ID.
- Telegram official `6ad963e5`, `Telegram/NotificationService/Sources/NotificationService.swift`2006 and pre `8e7e5fe`
  same path1770 resolve media through exact message identity. Pinned TDLibFramework `1.8.66-022d6020`,
  `td/td/telegram/MessageId.h`27–75 defines ordinary serverID<<20 and distinct low-bit local/scheduled variants;
  TDLibKit `1.5.2-tdlib-1.8.66-022d6020` notificationTypeNewMessage/NewPushMessage, getChat/getMessage/getChatHistory.
- Independent immutable review passes tree `b6f2bce3` on `be7dbdf`; four-file format2/4. Wrapper
  `175532-86891-9719` PASS9s, full1573-line log zero warnings/errors. Integration with A53a: joint eight-file format0/8,
  `175914-89505-20180` PASS8s, full1573-line log zero warnings/errors.
- Native at source `afed19b`, Audit Simulator59EB535C/iOS26.5, PID90125, fresh container
  `372A479D-FC6A-4F8B-BFF8-CB41CBC52013`, target report18:00:04+04 PASS. Actual production helper and TDLib model fixtures
  cover nil/wrong account, invalid/maximum cloud ID, low-bit aliases, peer kind/ID, wrong chat response/message group,
  matching-before-unrelated-last and unrelated-only selection. showPreview=false remains identifiable for the next denial
  stage; identity is not preview permission. No RPC/account-store/notification/INInteraction donation in the probe.
- At the A52a checkpoint, A52b remained open: nested session tasks, timeout/expiry and cache-publication lifetime. This helper/model
  proof does not exercise actual NSE delivery or TDLib RPC. Evidence: `.build/ui-probe-evidence/astra-a52-a53/`.
- A52b1 repair boundary reviewed before implementation: one lifetime authority owns continuation, client bootstrap and
  configure/process/resolver task tickets. Exact raw group-chat prefilter precedes the sole resolver; getChat's type/peer
  validation remains. Cancellation/timeout revokes tickets and synchronous cache-publication authority, then closes on a
  separate utility task without joining pending RPC tasks. No locks across await, continuation resume, task cancellation
  or close. Retirement may wait for already-entered synchronous cache IO; no hard real-time expiry guarantee.
- Pinned TDLibKit `TDLibApi.swift`31051–31069 uses a checked continuation without Swift cancellation propagation;
  manager `closeClients`133–138 waits for clients removal, and queryQueue177–178 removes before the queued client update
  handler necessarily runs. Canceling a Swift Task or completing close is not a callback-drain proof. A52b2 service request
  generation, builder/INInteraction donation and callback ownership remain separate from the session-only repair.

#### A52b1 session publication and teardown authority — 2026-10-03

- `90d324d` (worker `8c11665`, reviewed tree `c87a5863`) introduces one locked session lifetime for continuation,
  client bootstrap and at most one configure/process/resolve role. Tickets are reserved before spawning and reject a
  task handle arriving after completion or retirement. The target's raw chat prefilter prevents a same-messageID event
  from another chat consuming the sole resolver. Overflow is rejected before client creation; getChat type/peer checks remain.
- Outer cancellation, timeout and authorization failure retire authority once, cancel registered task handles and resume
  the result outside the lock. Late callback admission, post-await results and cache publication require live exact tickets.
  Synchronous cache writes and retirement share the lock: writes already inside it may delay retirement, but later writes
  cannot enter. Utility close is claimed once after retirement without joining pending TDLib tasks; the process lock stays
  held until close returns. Basic service cancellation checks stop already-cancelled work before lock/session/content paths.
- Telegram official `6ad963e5`, `Telegram/NotificationService/Sources/NotificationService.swift`2524–2527,2571–2606,
  and pre `8e7e5fe`2267–2270,2314–2349 separate handler disposal from once-only content completion. BetterTG adapts
  ownership to Swift tasks/TDLibKit; no SignalKit/Postbox/Display infrastructure copied. Pinned TDLib `DialogId.cpp`66–88
  and `DialogId.h`26–27 define private/basic/supergroup raw chat IDs; monoforum arithmetic remains accepted.
- Worker joint seven-file format3/7; wrapper `181538-16903-22292` PASS10s, complete1585-line log zero warnings/errors.
  Independent immutable peer review passes. Primary joint eleven-file format0/11; integration `182000-23494-22239`
  PASS17s, complete1585-line log zero warnings/errors. Worker is clean; all seven implementation files committed.
- Native at `90d324d`, same Audit Simulator59EB535C/iOS26.5, PID25440, fresh container
  `90A3B266-C8A0-4C49-BC66-191D96C1C1C1`: lifetime report18:21:15+04 PASS. Production authority fixtures cover cancel
  before begin/create, creation concurrent with retirement/early callback, wrong/duplicate tickets, completion before handle
  registration, three held uncooperative role tasks, result before their release, close claim without joining, positive and
  denied effects, and synchronous publication ordering. Exact admitted tasks are awaited; positive event receipts are checked.
  No actual TDLib client/cache/account/notification/donation effects in this lifetime probe.
- Same run: target, media-admission and cache-scope reports18:21:14 PASS; avatar worker18:21:15 PASS. Target adds exact
  group-chat, monoforum and overflow checks. Cache/worker tests retain real isolated JPEG IO. idb hierarchy available before
  install; wrapper kept Simulator in background. Evidence: `.build/ui-probe-evidence/astra-a52-a53/lifetime/`.
- Limits: pinned SDK RPC continuations can outlive cancellation; close is not a callback-drain proof. Check-before-await
  cannot guarantee zero new RPC submissions after a concurrent retirement, while publication itself is strictly gated.
  Actual NSE/APNs/SDK shutdown remain unverified. An entered synchronous write can delay expiry; no hard-deadline guarantee.
- Next A52b2: bind service processing task, content handler, temporary attachment/INInteraction construction and completion
  to one request authority. A Task.isCancelled check before builder alone has a check→side-effect gap. Preserve original
  fallback and once-only delivery; test replacement, expiry before task-handle registration, late producer and positive delivery
  through a production seam without donating synthetic interactions. Do not conflate this with the session-only repair.
- Then A53b: explicit hidden/showPreview denial must revoke even a previously accepted in-flight resolver for that same
  message; the new single resolver does not make its first notification permanently authoritative. Full-message eligibility,
  known content/delete revisions and versioned persisted evidence must govern cache/builder/wait paths together.
- A52b2 plan reviewed at `3d680cb`: a request coordinator owns one UUID, original fallback, handler and task handle.
  Replacement retires the exact old record; cancel and handler delivery run outside the lock and may reenter begin.
  Every later install/check/finish must therefore validate its ticket, including the ticket returned by an outer begin.
  Finish invokes its synchronous content producer under the same lock as expiry, then retires and delivers its captured
  handler once. Preserve ordinary content generation, original fallback and account/session selection. Test actual
  coordinator paths with injected effects; do not donate synthetic interactions. Entered builder IO may delay expiry;
  only donation invocation is fenced, not completion of an already-started system donation.
- Final checkpoint build `182318-27788-15437`: PASS5s, complete1385-line log zero warnings/errors. Production/dependency
  prohibited-marker scan empty; AGENTS/CLAUDE match. Primary implementation and worker are committed and clean; this
  proof ledger is the final focused documentation commit. Goal stays active; next implementation is A52b2 above.

#### A52b2 request-owned content completion — 2026-10-03

- `559a762` adds a shared production request coordinator: UUID owns original content, handler and optional task. Replacement
  and expiry retire that record; cancellation and exact-handler delivery run outside the lock. Reentrant handlers/cancellation
  can replace an outer begin before it returns, so every install/check/finish validates its ticket. Late task installation
  cancels the exact orphan; an old delayed result cannot construct content or complete a newer request.
- Actual NSE content builder, attachment creation and donation invocation run inside the coordinator's synchronous finish
  producer. Expiry and producer ownership serialize; once retired, the captured handler is delivered once. Original fallback,
  positive enrichment, account/session selection and quick-reply behavior remain. No lock crosses await/cancel/handler delivery.
- Official current `6ad963e5` NotificationService.swift2524–2527/2553–2606 and pre-Liquid `8e7e5fe`2267–2270/2296–2349
  separate old-work disposal from once-only completion. This adapts that ownership without Telegram infrastructure imports.
- Exact independent review passes tree `d3f44f92`. Joint four-file SwiftFormat0/4; final build `183542-38148-13783` PASS4s,
  full1476-line log zero warnings/errors. Two earlier logger/capture warnings were corrected with explicit `self.logger`.
- Native source `559a762`, Audit Simulator59EB535C/iOS26.5, PID40035, fresh container
  `68E5B756-8A9D-44EF-9CFC-298DDACF7B30`: request probe18:39:27+04 PASS. Actual coordinator covers original/positive
  once-only completion, expiry/finish before task registration, held uncooperative old response, handler/cancellation reentry,
  rejected superseded outer ticket and entered synchronous producer versus expiry. Fixture tasks are awaited; effects injected.
- Same launch: session lifetime, target, media admission, cache scope and avatar worker reports18:39:26–27 PASS. idb hierarchy
  available before install; wrapper launch preserved focus. Evidence: `.build/ui-probe-evidence/astra-a52-a53/request/`.
  Actual NSE/APNs/builder donation remains unverified; an entered synchronous builder may delay expiry, and a system donation
  already started cannot be revoked. The coordinator probe performs no RPC/account/cache/donation effects.

#### A53 notification media concealment — source finding 2026-10-03

- At `38b7d06`, `RichNotificationCacheCoordinator.cacheMedia` accepts incoming photo/video/animation through its local
  `mediaCandidate`, which lacks both `isSecret` and `hasSpoiler` guards. Positive server message IDs in cloud private/group/
  supergroup chats can therefore acquire persisted preview bytes. Secret-chat peer mapping returns nil; do not generalize
  this finding to a demonstrated secret-chat delivery.
- NSE `NotificationTDLibSession.swift`450–460 already excludes secret/spoiler MessageContent, but
  `RichNotificationContentBuilder.content`21 and `fallback`88 read the shared cache without eligibility evidence.
  `NotificationService.waitForCachedMedia` has the same read path. Source review demonstrates the bypass path, not
  real push exposure. No actual private/secret content was opened or sent for this finding.
- Telegram official `6ad963e5`, `Telegram/NotificationService/Sources/NotificationService.swift`2006, and pre-Liquid
  `8e7e5fe` same path1770 explicitly exclude `containsSecretMedia` and `MediaSpoilerMessageAttribute` before extracting
  notification media. Preserve that contract with TDLib `MessageContent` flags; no Telegram infrastructure import.
- Next after A51b: bounded app-side eligibility gate before download/cache, deterministic positive/negative cases. Then
  examine persisted eligibility, content edits and NSE fallback authority; a new admission guard alone does not sanitize
  existing entries or prove delayed/cache-only notification delivery. Keep this separate from avatar-worker proof.
- Repair plan reviewed at `be7dbdf` before implementation: A53a shared full-message eligibility plus source/chat/raw-message
  work leases. Reject secret/spoiler/self-destruct media before any getChat/download/write; preserve ordinary supported
  positives. Matching content/delete updates and auth/source revocation retire old jobs immediately; every await must
  recheck the captured lease, and older cleanup must not remove a replacement job. This stage does not close the disk/NSE bypass.
- Prerequisites for the remaining end-to-end repair: A52 exact account/chat/peer/raw-message correlation and live-session
  authority. The current unrelated addedNotifications.last fallback and shifted-only ID match cannot certify media under a
  metadata key. Then explicit unresolved/denied/allowed state must govern builder, cache wait and cache publication.
  Under-specified PushMessageContent thumbnails are not positive evidence; fetch exact full MessageContent even when a
  push thumbnail exists. Explicit denial must never become an ordinary nil cache fallback.
- Durable cache target: atomic versioned evidence and bytes bound to account/peer/chat/raw-message/content revision;
  old scoped/unscoped JPEGs stay untouched and unread. Observed edits/deletes revoke evidence and outstanding jobs before
  awaits; only current verified content can republish. Preserve ordinary eligible preview/fallback behavior. Unseen server
  edits and actual remote notification delivery remain separate proof limits, not reasons to disable every preview.
- Planned probes use isolated roots and the actual production policy/lease/attachment-selection seams, with held async
  work and exact receipts. Do not donate synthetic INInteractions or send real notifications for these tests.
- A53a `afed19b` (worker `739c9e3`, reviewed tree `55d6883a`) adds shared full-Message policy: photo/video/animation
  require !isSecret&&!hasSpoiler; videoNote !isSecret; selfDestructType/selfDestructIn reject the envelope. Ordinary
  autoDeleteIn does not deny previews. The app preserves photo/video/animation/sticker candidates and placeholder→file.
- `RichNotificationMediaPrewarmer` owns source/chat/raw-message UUID leases. New-message admission and content/delete
  revocation use the same synchronous accepted-TDLib publisher order; an old queued admission cannot revive an edited job.
  Matching edits/deletes, auth nil and source/client replacement revoke before awaits resume. Each await rechecks current
  authority; old cleanup cannot remove a replacement. The actual getChat response also validates requested chatID.
- Worker joint four-file format/final build `175435-85477-13178` PASS10s/full1450-line log zero warnings/errors.
  Initial compile missing a nested @MainActor annotation was repaired, not suppressed. Exact peer review caught and fixed
  a vacuous burst-test oracle: the test now requires and awaits the precise newly admitted task. Integration build above.
- Native same source/PID/container as A52a: media-admission report18:00:05+04 PASS; ordinary families and placeholder
  positives, concealed/self-destruct negatives before injected IO, same-turn new→edit, held getChat/download revocation,
  source ABA/client replacement and own-token cleanup all pass. The production publisher/pipeline uses injected RPC/read/
  cache operations; real TDLib/NSE/durable disk revocation is not demonstrated. No private media or messages sent.
  Cache-scope and avatar-worker regression probes also PASS18:00:05 using real isolated JPEG/filesystem IO.
- Remaining A53b: raw existing media cache, NSE nil fallback and push-thumbnail authority still bypass explicit denial.
  notificationTypeNewMessage.showPreview=false is also not yet enforced by the resolver. Versioned evidence plus bytes,
  known-edit/delete invalidation and explicit unresolved/denied/allowed selection depend on A52b session authority.
  App media work remains uncapped and reads/writes on main; this slice revokes leases, not the underlying TDLib download.
- Follow-up `a2be588` rejects zero/negative, low-bit local/scheduled and out-of-range raw IDs before app prewarmer getChat/
  download/read/cache. It derives the persisted server-message key once from the admitted ordinary cloud ID. Pinned
  MessageId.h27–75 supplies the encoding; maximum Int32 server ID remains valid. Independent exact review passes tree
  `c6bf1b7c`; joint two-file format0/2, build `180821-97791-18988` PASS10s/full1454-line log zero warnings/errors.
- Native follow-up at `a2be588`, same Audit Simulator/runtime, PID2426, fresh container
  `1EF3238E-91C2-4DD2-94CF-5B75DD6ECD24`, media-admission report18:10:29+04 PASS. Negative IDs cause no injected IO;
  maximum valid ID round-trips the cache key. Saved `media-cloud-id-native.txt` with the other A52/A53 evidence.
- A53b must also treat pinned `pushMessageContentHidden` (td_api.tl8537–8538) as explicit denial before fetchMessage:
  the current nil-candidate path can fetch full media/body despite a hidden push. Backend
  `apns-payload-mapper.service.ts` forwards loc_key as metadata.event without independent preview permission. This is
  source evidence, not demonstrated push exposure. Content eligibility and notification preview permission are distinct.
- A53b1 repair boundary reviewed before implementation at `559a762`: represent unresolved/denied/allowed media explicitly;
  hidden/showPreview=false must withhold body overrides as well as attachments. Scan every exact notification in the batch
  before admitting the sole resolver. Later denial/edit/delete and publication/finish must use one lifetime authority so a
  previously accepted resolver cannot publish after known denial. Require exact full Message admission even with push thumbnails.
- A53b1 removes raw-JPEG reads from builder/fallback/cache-wait, preserves fresh eligible media and normal text/title/avatar/
  quick reply, and adds injected production decision/race proofs without real notifications or donations. It leaves old cache
  files untouched. Transitional limitation: unverified cache-only media is withheld. This is not complete A53 parity.
- Mandatory next A53b2 restores ordinary verified cache-only previews: atomic versioned evidence+bytes, exact account/chat/
  ordinary raw-message identity, separate preview permission, cross-process revision arbitration and observed edit/delete
  invalidation even without an active job. Missing/evicted evidence must reject late commits. Existing raw JPEGs remain unread;
  full Message media eligibility alone must not be treated as showPreview permission. Unseen server edits/settings stay unverified.

#### A53b1 explicit preview evidence — 2026-10-03

- `805494f` (worker `ee6482e`, exact reviewed tree `33dcf2fa`) separates denied/unresolved/allowed media. Every media push
  requires the exact full Message, even if it carries a thumbnail. Full envelope self-destruct and media secret/spoiler flags
  are checked; missing evidence stays unresolved. Ordinary full-message families, no-thumbnail caption and chat auto-delete
  remain permitted. Original body is preserved for denied/unresolved decisions; no generated caption can bypass the decision.
- Every matching entry in an addedNotifications batch is scanned before resolver admission. Hidden/showPreview=false,
  content/edited/delete and exact previously bound updateNotification replacements retire the same session authority that
  owns publication/finish. A held old result cannot overwrite the denied result or publish. Wrong client/chat/raw-message/group
  identities cannot deny it. This linearizes at the lifetime lock, not callback/decode entry; post-retirement updates are unobserved.
- NSE builder/fallback/cache-wait no longer read raw media JPEGs; NSE no longer writes them. Builder accepts only explicit
  allowed bytes and clears pre-existing attachments. Existing disk files are untouched; avatar caches and Intents identifiers
  are unchanged. Concealment retains the existing metadata quick-reply fallback; it does not imply chat send permission denial.
- Pinned TDLib td_api.tl8537–8538/8716/8730 supplies Hidden, showPreview and the weaker push model. updateNotification omits
  chatID and therefore requires a group already bound by an exact target event. Telegram media concealment references above
  still apply. Caption entity spoilers are a separate remaining body issue, not covered by media.hasSpoiler.
- Joint worker nine-file format; final build `190516-81039-5600` PASS7s/full1458 lines zero warnings/errors. Explicit Gate
  MainActor isolation fixes the first probe build warning without suppression. Primary joint eleven-file format0/11;
  integration `190831-85528-20489` PASS17s/full1601 lines zero warnings/errors. Exact independent and primary reviews pass.
- Native source `805494f`, Audit59EB535C/iOS26.5, PID87313, fresh container `96D8ED57-42F8-4151-8B55-E846C09499F0`:
  preview report19:09:41+04 PASS. Production policy/lifetime fixtures cover all ordinary full media, push thumbnail requiring
  fetch, hidden/showPreview/media flags, both batch orders, bound replacement, missing/wrong identity, held fetch/download
  revocation and exact late-task publication/finish rejection. Fixture RPC/donation effects0; actual NSE/builder/APNs unverified.
- Same run all six request/lifetime/target/admission/cache/worker regressions PASS19:09:40–41. idb preinstall count22; wrapper
  preserved host focus and borrowed Simulator. Evidence: `.build/ui-probe-evidence/astra-a52-a53/preview/`.
  Transitional limitation: unverified cache-only media remains withheld. A53b2 restoration is mandatory, not optional polish.
- A53b1a plan at `805494f`: media.hasSpoiler does not cover FormattedText caption entities. The current body formatter reads
  caption.text directly for photo/video/animation/document, potentially replacing a safe APNs body with concealed text.
  Preserve original body whenever its caption contains textEntityTypeSpoiler, without denying an otherwise eligible attachment.
  Keep plain/non-spoiler caption enrichment; test the shared production caption gate with actual TDLib entities. No range
  rewriting, new notifications or donation fixtures. Pre-Liquid `ChatMessageNotificationItem.swift`219–223/448 retains spoiler
  entities and hides their text for in-app notifications; this is concealment reference, not proof of remote APNs formatting.

#### A53b1a caption entity concealment — 2026-10-03

- `cb84f9b` routes photo/video/animation/document body generation through the shared FormattedText caption gate. A spoiler
  entity returns no replacement body; eligible attachments keep their independent authority. Plain/bold captions and empty
  Photo/Video/GIF/filename labels remain identical. No UTF-16 slicing or new rendering infrastructure is introduced.
- Exact independent review passes tree `f830e1aa`; joint eleven-file SwiftFormat2/11. Build `191222-90485-18135` PASS8s,
  complete1545-line log zero warnings/errors. No regression scope was relaxed.
- Native same frozen tree, now committed `cb84f9b`, Audit59EB535C/iOS26.5, PID91301, fresh container
  `F9078410-8C14-4A4D-8A93-8CB552BB440A`: preview report19:13:48+04 PASS. Actual shared helper preserves ordinary/bold/
  empty output and original body with valid or malformed-range spoiler entities, including emoji text; allowed media remains.
  Fixture Int.max is never serialized or used to slice text. It tests entity presence, not TDLib transport validation.
- All six notification regression reports PASS19:13:47–48. idb preinstall count22; background wrapper preserves focus.
  Evidence: `.build/ui-probe-evidence/astra-a52-a53/captions/`. This suppresses an unsafe generated override; it does not
  sanitize an already-unsafe original APNs payload or prove actual NSE attachment/donation behavior. Cache-v2 remains next.

#### A53b2 cache-v2 design gate — reviewed 2026-10-03, not implemented

- At `559a762`, prewarmer active leases do not cover completed entries; `RichNotificationCache` persists only JPEG bytes.
  Replace the media path with one atomic envelope per exact account/raw-chat/ordinary raw-message identity in `media-v2`.
  It must bind schema/policy version, random content revision, resource fingerprint, full-message eligibility, state and
  normalized bytes/digest. Normalize outside the lock. Prepare a revision before download; completion compares against the
  present matching revision and never recreates an evicted/missing record. A source/client token is job ownership, not permission.
- App and NSE transactions need a stable per-account file lock. Invalidation must cover matching content/edited/delete events
  even without a running job. Accepted invalidations survive source retirement; do not silently drop them when bounding queues.
  MainActor receipt can revoke local work and enqueue immutable keys, but durable cross-process visibility begins only after
  the utility transaction succeeds. A reader that acquires the lock first may still consume the previous revision. Failed writes
  cannot emit a successful acknowledgement. Atomic replacement/readback alone is not proof of power-loss durability.
- `TDLib.releaseForNotificationService`152–166 currently closes clients and unlocks without a media transaction drain.
  Flush already-accepted invalidations off-main before orderly DB handoff. The DB lock does not protect cache readers:
  `NotificationService` reads cache after its six-second owner-lock timeout. Abrupt termination and pre-ack reads remain limits.
  To prevent an already-copied stale record from later becoming an attachment, final publication must revalidate its exact
  revision under the same authority; an earlier locked read alone cannot prove no post-ack attachment.
- Backend `apns-payload-mapper.service.ts`57 forwards the raw `loc_key` as metadata.event, with no independent preview flag.
  Pinned TDLib `NotificationManager.cpp`2818–2919/3332–3354 maps raw GIF/DOC/ROUND and strips CHAT_/CHANNEL_ prefixes;
  `NotificationType.cpp`160–161 maps MESSAGE to Hidden. Any cache-only presentation allowlist must use exact supported raw
  message-family keys and peer kinds, not substring matching or normalized TD names. Hidden/secret/notext/unknown/aggregate
  and pinned events remain fail-closed. Such a policy is source-derived presentation evidence, not fresh server-settings proof.
- Required isolated tests: fresh/cache-only positives; concealment/preview denial; held download versus revoke; same-batch deny;
  edit/delete with no active job; two store instances; eviction versus late commit; invalid identity/schema/digest; failed revoke
  without acknowledgement; and declared pre-ack versus rejected post-ack read/commit order. Legacy JPEGs stay untouched/unread.

#### A40 complete build-warning visibility — 2026-10-03

- Fix commit: `eff2876`.
- Full integration log `014324-25949-6943` line264 reports `Metadata extraction skipped. No AppIntents.framework dependency found`
  for BetterTGNotificationService. `script/build.sh` and its compact formatter hid this category; the formatter also aggregated
  SwiftFormat warning details. Remove these filters so each warning remains visible, and require complete-log checks in both
  synchronized instruction files.
- The notification extension declares no AppIntent/AppShortcut; it uses legacy `Intents`/`UNNotificationServiceExtension`.
  Remove its unused AppIntents import and set target-only `LM_SKIP_METADATA_EXTRACTION: YES`. Local Xcode26.6 task-producer
  inspection confirms the native Boolean omits the inapplicable stage, rather than quieting emitted diagnostics. Main-app
  extraction configuration is unchanged. Restore extraction if extension AppIntent declarations are introduced.
- Independent six-file review, shell syntax and parser fixtures pass; skipped/disabled metadata, SwiftFormat per-rule and
  uppercase warning examples remain visible. One-file SwiftFormat0/1; `build-Debug-20261003-015029-27777-31071.log`: PASS5s,
  full log zero warnings/errors, extension recompiles with no extraction task. The next build `015206-28264-17404` exposes an
  existing race between `Remove Static TDLib Artifact` and automatic framework copy/sign; A41 repairs it below.
- Historical full logs explicitly rechecked: A38 `002923`, `003813`, `004329`; A39 `005409`, `005819`; worker `013700` all have
  zero warnings/errors and successful builds. A39 `010725`, `011303`, `011704` also pass full-log checks. Their claims stand.
  Other compact-only historical claims remain unverified;
  no broad retroactive assertion is made. Telegram/TDLib behavior unchanged; no runtime notification delivery proof claimed.

#### A41 static artifact cleanup dependency order — 2026-10-03

- Two consecutive builds `015206-28264-17404` and `015425-28980-13074` fail when cleanup deletes TDLibFramework.framework during
  Xcode's automatic lipo/copy/sign. Failed manifest `5bf934207b9f9cd20ed3f407db54958a` shows the cleanup waits only for the
  explicit copy-files phase, while SwiftPM's package copy and child signing are independent producers. No dependency or cache
  reset is warranted.
- `72d74b0` adds only two XcodeGen `inputFiles`: the embedded static bundle and its `_CodeSignature`. The generated graph
  now orders copy → child signing → cleanup → unsigned-product-ready → app signing without a cycle. Cleanup still removes only
  the redundant generated static artifact, recoverable by the next build; package sources/cache and TDLibKitDynamic remain intact.
- Integrated source includes A39 follow-up `982245f` (worker `9eee50d`); all four outstanding Swift files formatted together0/4.
  `build-Debug-20261003-015646-29545-22064.log`: PASS7s; `--no-code-signing` log `015734-29820-5419`: PASS4s;
  final signed `015810-30055-29778`: PASS5s. Complete logs have zero warnings/errors; main-app metadata extraction still runs,
  extension extraction does not. Final redundant bundle is absent and `codesign --verify --deep --strict` passes.
  Independent graph/source review and shell warning fixtures pass. Device/archive signing remains unverified.

#### A42 forum-search snapshot cell ownership — 2026-10-03

- Actual source `72d74b0`/docs`cef6bdc`, audit Simulator PID `42180`: existing real forum → active search → three-character
  Cyrillic query. At02:31:53.810, UIKit throws `NSInternalInconsistencyException`: reconfigure expected the existing `ForumTopicCell`
  but received a new plain `UITableViewCell`. Crash report `BetterTG-2026-10-03-023158.ips`, incident
  `E8889D35-E206-4228-9339-F3C0A2617229`; stack reaches `applySnapshot`341 from queued topics sink307. No Home was sent.
- Cause: the provider resolves a captured snapshot ID against newer `viewModel.topics`; a miss returns another cell instance.
  `ForumTopicsSnapshotState` now owns the outgoing/incoming models for one apply, coalesces the next payload, prunes removed models
  only on matching completion, and rejects retired callbacks. The provider always returns its registered dequeued cell; unexpected
  missing models clear pixels, icon work and accessibility/actions. Stable displayed ID plus current accepted/raw-query membership
  gates selection. Pagination uses settled displayed rows; viewport restoration waits for the last pending apply.
- Contracts retained: native UITableView/diffable animation, topic IDs/order, TDLib pagination, search semantics, immutable client,
  target navigation and account fences. No search-owner/foreground rewrite or infrastructure import. References: pinned current/pre
  `ChatListUI/Sources/ChatListSearchContainerNode.swift`712–720/660–668 keeps the ongoing query stream; UIKit's runtime assertion
  supplies the exact same-cell reconfigure contract. TDLib `022d6020` `getForumTopics` and typed topic updates are unchanged.
- Independent source review found no further blocker. Four changed Swift files formatted together. Initial `023925-49399-14038`
  build exposed probe actor/immutable-model errors and one explicit-self error; repaired without suppression. Complete logs
  `build-Debug-20261003-024008-49732-21018.log` and `024232-51718-5650` both PASS7s with zero warnings/errors.
- Initial native probe PID `50825` timed out with an unattached animated table. The DEBUG fixture now attaches its real table to
  a temporary UIKit window and tears it down; no production timing gate was weakened. PID `54675` passes production-state
  serialization/coalescing/outgoing lifetime, real diffable reconfigure of the same production cell, missing-model cleanup and
  retired completion rejection. Existing forum-restoration regression also passes. This native consumer does not inject the full
  controller/VM transport or verify navigation actions.
- Actual fixed production code PID `50825`: matching query shows one row; clear/new unmatched query settles to No topics found;
  further quick query changes keep the same PID. PID `54675` repeats the exact original Cyrillic query and settles to No topics
  found without crash; three-minute exception-log read is empty. No topic selected or message/topic mutation occurred. Private
  before/after pixels and failed-fixture notes: `.build/ui-probe-evidence/astra-a30d-search-baseline`. Background-search restoration,
  result selection and multi-page search remain separate proof limits. The native bottom search island is still an A32 UI gap.
- Final `build-Debug-20261003-025014-56598-7723.log`: PASS4s, complete log zero warnings/errors; prohibited production/dependency
  markers absent. No whole-repository formatting or account/data reset.

#### A32 folder Done contrast and A36 title classification — 2026-10-02

- `1b89dbd` (worker `7a46acb`) changes only selector/order Done factories to titled `.plain` items, retaining actions,
  target, readiness gates and AX label. Native folder-flow probe now verifies all of them, including disabled action denial.
  Two-file format; `build-Debug-20261002-232705-14634-13985.log`: PASS8s, zero warnings.
- Audit Simulator, source `1b89dbd`, PID `29718`: folder-flow and profile-editor regressions pass, fresh results
  `23:36:07–23:36:09`. Actual New Folder → Always Include shows readable plain Done after transition settles. Done returns
  to the same unsaved editor with zero selected chats; Back discards that local draft. No folder saved, reordered or deleted.
  Order's visual appearance and VoiceOver remain unverified; native Back and bottom Search islands are still open A32 gaps.
- Aggregate-only actual-selector diagnostic at `23:37:48`: 467 candidates, 11 empty raw titles, all 11 explicitly deleted and
  non-contact, zero unknown; 14 visible cells, 11 empty text labels, zero model/display mismatches. No peer names/IDs/query
  logged. This confirms A36 presentation loss rather than missing hydration or stale cell rendering.
- Source: `CustomChat.displayTitle` returns raw `Chat.title`; selector uses it for cell/sort/search and all user subtitles say
  Contact. Pinned TD `UserManager.cpp`5574–5585 permits empty unnamed titles; `td_api.tl`797–819 distinguishes deleted/unknown.
  Current/pre `LocalizedPeerData/Sources/PeerTitle.swift`31–54/29–52 supplies name/deleted fallback; its phone TODO is not copied.
  Private proof `.build/ui-probe-evidence/astra-a32-done-primary`. Candidate title/contact update freshness remains part of A36.
  Documentation checkpoint `build-Debug-20261002-234112-48169-3610.log`: PASS6s, zero warnings; prohibited source/dependency
  scan empty, AGENTS/CLAUDE synchronized. No Simulator was activated or shut down.
- `c9254f3` (worker `cef12a6`) adds truthful selector-only title/subtitle fallbacks, deterministic title/ID ordering and
  source/generation-fenced existing-candidate observation. Presentation dedup ignores unread/position/message-only changes;
  same-ID fresh objects are rebound without unnecessary sort/reload. Selection and valid Saved titles are preserved.
  Two-file format; `build-Debug-20261002-234911-61254-22275.log`: PASS8s, zero warnings. Primary runtime pending.
  Independent source review found no introduced blocker, but `CustomFolder.chats` append/remove is not forwarded by Root.
  The existing probe manually publishes `modelChanges`; it does not prove that live child-membership link. Separate repair queued.
- Actual `c68c1c2`, PID `68772`: all 11 explicitly deleted rows now have visible `Deleted Account` labels, no Contact subtitle,
  and are found by local search. Real self `Saved Messages` title is retained; its current non-contact classification is shown.
  Aggregate diagnostic: 467 candidates, 11 empty raw titles, zero empty visible cell texts and zero model/display mismatches.
  Extended native selector probe passes. Back discards the blank local folder; no selections or server saves were made.
  Private proof `.build/ui-probe-evidence/astra-a36-primary`.
- `f70cd58` (worker `1b259865`) adds source/generation-fenced child `CustomFolder` publishers, retaining existing presentation
  dedup and replacing obsolete folder/chat subscriptions. Root/session are unchanged. Two-file format;
  `build-Debug-20261003-000123-71229-20485.log`: PASS9s, zero warnings. Native child-publisher probe at `d34d012`,
  PID `88865`, passes append/remove/same-ID replacement, obsolete subscriptions, query/selection and source/detach fences,
  using real child publishers without manual wakeups. RootVM/TDLib transport is not injected. Private proof
  `.build/ui-probe-evidence/astra-folder-membership-primary`. An earlier combined launch, PID `84460`, reached the old
  modal test and failed `dismissing modal kept authority`; the isolated unchanged probe passes. Presentation-settlement
  timing in that fixture was then corrected: wait for public presentation completion, not merely window attachment, before
  initiating dismissal. The immediate dismiss-authority and detached-pixels assertions are unchanged. One-file format;
  `build-Debug-20261003-001241-93570-24717.log`: PASS16s, zero warnings. Combined folder/profile probes pass at PID `97142`
  with this DEBUG-only correction; profile navigation entries remain value-only and do not cover A38 admission.
  References: current/pre `ChatListFilterPresetController.swift`791–798/787–794 and
  `ContactMultiselectionControllerNode.swift`191–215/192–216 keep explicit selection separate from live rows;
  pinned TDLib `td_api.tl`10406,11471–11476 supplies position removal/live loading semantics.

#### A37 focused prompt baseline — 2026-10-03

- `d34d012` (worker `fc815ea`) adds only a DEBUG `-ui-probe-navigation-prompt` fixture: actual classic navigation and editor,
  temporary isolated key window restored on exit, real first responder/selection, delayed public geometry and retained-stack
  replacement. No production layout changes. One-file format; `build-Debug-20261003-000305-73770-24276.log`: PASS16s,
  zero warnings.
- PID `79838`: baseline three samples bar/safe/field116/116/136. Waiting sample116/150/170 fails the fixture's strict bar=safe
  assertion, but does not show field overlap. Public prompt/safe-area APIs do not guarantee that equality. This failed probe
  is not proof of the original clipping cause. Correct the fixture to collect all phases and separately test harmful overlap,
  baseline return and focus/selection without forced layout. Private report `.build/ui-probe-evidence/astra-a37-primary`.
- `04c904a` (worker `4e704d5`) corrects only that measurement contract: public bar/safe difference is diagnostic;
  harmful field/bar overlap, exact selection, focus/text and final ready-baseline remain failures. All 24 samples/8 phases
  are collected before verdict. One-file format; `build-Debug-20261003-001518-2098-7636.log`: PASS9s, zero warnings.
  PID `4253` passes all phases including fresh client and exact retained-stack replacement: no harmful overlap, focus/text/
  selection loss or final-baseline failure; nine waiting samples have bar116/safe150/field170. No forced layout or production
  invalidation added. Private proof `.build/ui-probe-evidence/astra-a37-complete-primary`. Original actual clipping remains
  open/intermittent; this isolated baseline does not establish its cause or prove real foreground/painted-pixel behavior.
- Actual delayed diagnostic at `97ccea8`, PID `32182`, with `-ui-diagnose-profile-editor-layout`: focus first own-profile
  field without editing, Home00:39:11→foreground00:39:45. Immediate samples show bar150/safe116/field136, but all three
  delayed settled samples return116/116/136 with first responder retained. Settled screenshot is clean; Back exits without
  Save or an agent-authored draft. `.build/ui-probe-evidence/astra-a37-delayed-primary` contains the bounded geometry JSON
  and pixels. This confirms transient geometry in this run, not the cause or repair of the earlier persistent clipping.

#### A33 definite profile-header text width — 2026-10-02

- `b97fa9b` changes the four centered header labels from `width <= stack.width` to definite available width. Multiline fitting
  no longer resolves the own title to a narrow 90pt region. Text alignment, fonts, line limits, self-role wording and the 96pt
  avatar remain unchanged. No full header rewrite. Independent source review found no blocker.
- Reference: pinned current/pre `TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift`
  1361–1372 / 1390–1398 measures text against explicit header width; 1206–1218 / 1245–1257 preserves Saved Messages for this role.
  No TDLib API or storage changes.
- Two Swift files formatted together; `build-Debug-20261002-212624-17872-14020.log`: PASS9s, zero warnings. Audit Simulator
  PID `20471`, source `3218502` plus the committed delta: actual Saved Messages → Profile displays the full one-line title.
  Read-only DEBUG geometry records header402pt/title362pt, all three visible labels centered at available width, avatar96pt,
  content size category L. It does not replace content or log title/bio/phone. Profile media concealment regression also passes.
- Private before/after screenshots and readback: `.build/ui-probe-evidence/astra-a20b-primary/own-profile.png` and
  `.build/ui-probe-evidence/astra-a33-primary`. No editor/media item/server action opened. Other widths, dynamic category changes,
  long/RTL titles and scrolled-offset resizing remain unverified. Circular Back remains separate A32 work.

#### A43 chat-list read-receipt delivery — 2026-10-03

- Baseline `d8e2bb0`: `ChatListCell.deliveryState` reads the immutable Chat's outgoing read watermark, but generated
  `updateChatReadOutbox` has no subscriber. Folder rows already observe `CustomChat.objectWillChange`; missing TDLib feed,
  not missing cell rendering, is the narrow defect. No broad unread-badge or timeline rewrite is included.
- Add the receipt to Root's existing account/client-scoped observation and active-read projection. Patch only the matching
  Chat watermark in main/custom/archive instances; deduplicate shared object identities and unchanged values. No getChat
  round trip. Revision stamps preserve a newer accepted receipt across earlier getChat/hydration/rebuild results while
  respecting later read and complete-snapshot boundaries. Existing source/epoch retirement remains unchanged.
- References: Telegram current `6ad963e5b62d354da79040f388ae2b9132fb17b8`,
  `ChatListUI/Sources/Node/ChatListItem.swift`3393–3411 and1590–1591; pre-Liquid
  `8e7e5fefb1b0aba8335d8c28b62138183d61dc3d`, same path3093–3111 and1510–1511: account read counters drive
  Delivered/Read and accessibility independently of unread badges. TDLib `022d6020`, `td_api.tl`10417–10418;
  `MessagesManager.cpp`9938–9950,27270–27284 sends the dedicated update;25560–25565 only schedules database persistence.
  Last-message/position updates are not guaranteed companions. No upstream infrastructure imported.
- Three Swift files formatted together; `build-Debug-20261003-032256-23469-20517.log`: PASS9s, complete warning/error scan
  empty. Independent source review found no introduced P1/P2. Audit Simulator59EB535C-3610-41A2-AB68-53A9467DC24B/iOS26.5,
  PID `24065`, source `d8e2bb0` plus this delta: root projection, list authority and insertion probes all pass.
- Expanded probe exercises production scoped NotificationCenter delivery, authority and field patch; multiple distinct
  folders/archive instances, shared-instance single publication, duplicate/current/wrong-chat/foreign-source handling,
  old-client queued delivery rejection, stale hydration and newer read/snapshot precedence. Actual `ChatListCell.configure`
  changes AX from Delivered to Read without a new last message. Its private center/fixture makes no server calls and does not
  inject updates into the user's Root. RootVM subscriber/table wiring is source-reviewed, not runtime-injected. The fixture
  retains a lease while switching its fake source to test field ordering; production source changes still invalidate leases,
  covered by the existing retirement regression. No live peer-read, full list receipt smoke or server mutation claim.

#### A44 timeline delivery-state audit — 2026-10-03

- Source baseline `596e895`, independently confirmed: `MessageView.swift`514–551 builds text, standalone and media-overlay
  timestamps with only `sendFailed`; AX576 reuses that value. `CustomMessage` has no derived read state. A43 updates list
  rows only: bubbles do not consume that watermark. `ChatVM+Publishers.swift`13–16 observes inbox but no outbox;122–129
  refreshes only the explicit route topic and discards direct scalar topic receipt updates in all-messages mode.
- Narrow repair must preserve raw sending-state precedence before comparing a temporary message ID to read watermarks;
  accepted final/failure replacement cannot keep a stale temporary state. Use current-client chat watermark for ordinary
  messages and exact per-message forum-topic watermark in both explicit-topic and all-messages routes. Missing topic state
  cannot fall back to another topic or the global chat. Late getChat/getForumTopic must not overwrite intervening accepted
  receipt updates. Do not carry old-client receipt authority through restoration seeds.
- Existing `ChatView.messagesDidChange` updates structural snapshots but reconfigures only headers (1769–1781), and its
  VM object observer updates chrome/composer. A watermark field alone will not refresh settled bubbles. Use targeted stable
  `DisplayedMessageID` reconfiguration through the existing anchor-preserving path, with no new scroll intent. BetterTG's
  album representative is newest-first (`ChatVM.swift`3578–3605), whereas Telegram's message/read status comes from its
  canonical first item; select that status source explicitly and recompute after replacement/deletion/promotion.
- References: current `6ad963e5b62d354da79040f388ae2b9132fb17b8` / pre-Liquid
  `8e7e5fefb1b0aba8335d8c28b62138183d61dc3d`, `TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/`
  `ChatMessageTextBubbleContentNode.swift`337–346 /360–369 uses Failed → Sending → Sent(read).
  Current `ChatMessageDateAndStatusNode/Sources/ChatMessageDateAndStatusNode.swift`32–44,607–683 supplies outgoing clock/
  single/double check variants; `ChatMessageItemImpl/Sources/ChatMessageItemImpl.swift`255–269 /235–249 selects grouped status.
  `TelegramCore/Sources/Utils/MessageUtils.swift`348–378 /351–380 defines effective direction, including self and broadcast.
- TDLib `022d6020`, `MessagesManager.cpp`32931–32934 gives broadcast channels a maximal outbox watermark, not a personal
  read receipt.11567–11576 marks ordinary self messages non-outgoing. Do not mechanically show Read on broadcast posts or
  hide pending/failure in Saved Messages. Final self-check styling requires an explicit reference mapping; do not invent it.
  `updateForumTopic` carries its own watermark. Optional `updateMessageSendAcknowledged` (`td_api.tl`10300–10304) only means
  quick acknowledgement, may precede failure and is not final success/read. Fullscreen gallery controls are outside this
  status repair; bubble media overlays are in scope. Source audit only; no new production code or live message send/read proof.

#### A44a ordinary-chat bubble delivery states — 2026-10-03

- Worker `52d7e33` integrated as `1630ee1`; DEBUG-only geometry correction `909f62b`. Add derived Equatable status with
  raw Failed/Pending precedence before any temporary-ID comparison; final outgoing ordinary messages show single/double checks
  from the current source/route watermark. Unknown receipt never claims Read. Canonical first chronological album member supplies
  status, independent of newest-first display representative; promotion/replacement recomputes it. Incoming/broadcast/forum
  final states and final Saved Messages mapping stay excluded; Saved pending/failed remains visible despite TD's outgoing flag.
- `ChatVM` subscribes to scoped outbox updates before a fresh current-client getChat baseline. UUID/revision fences reject late
  reads after accepted updates, including duplicates; source departure terminally retires/cancels receipts. History seeds omit
  derived state. Text/footer/media overlays share the status; accessibility speaks Sending/Failed to send/Delivered/Read rather
  than glyphs. References and pinned TDLib semantics are in the preceding A44 audit; no foreign Telegram infrastructure copied.
- Independent review closed same-ID wrapper publication, stale legacy-failure and queued old-owner risks. Structural snapshots
  reconfigure retained IDs whose wrapper changed. Per-message queued invalidations validate exact current model/wrapper and batch
  a receipt burst into one existing anchor-preserving reconfiguration, avoiding one whole snapshot apply per row.
- Native `-ui-probe-message-delivery`, audit Simulator59EB535C-3610-41A2-AB68-53A9467DC24B/iOS26.5: PID62893 PASS includes
  revision/source/route retirement, canonical album promotion, pending/final replacement, history seed reset, actual MessageCell
  text/footer/media/VoiceOver, same-cell stable-ID replacement, stale owner rejection and 23 changed wrappers in one native apply.
  Fixed-row adapter offset remains unchanged. It is not whole-ChatVM or self-sizing production-history proof.
- Preserve fixture failures: PID58294 compound assertion failed; diagnostic PID59352 isolated retained-cell=true, Read=true,
  stale callbacks=0, but offset `(0,0)→(0,-62)`. UIWindow had not yet applied its initial automatic safe-area inset. `909f62b`
  waits for actual window/host/collection layout and settled initial inset before capturing the baseline; no assertion was removed
  and no production anchor code was changed. Native PASS followed on PID62893.
- Same PID62893 actual production navigation through bot and ordinary personal histories: incoming bot messages had no outgoing
  checks; four pre-existing outgoing personal-chat messages displayed double checks and spoken Read. No typing, sending,
  reactions, links or message actions. Only already-read rows were opened. Actual outgoing frames were x8/w386 at y469.6667,
  555.0,654.3333,739.6667 with heights80.3333,94.3333,80.3333,32. They remained identical after Home/foreground:
  ownership released04:57:36.747, restored04:58:39.482, Chat viewport settled/fresh-history starts04:58:39.772 (+04).
  Screenshots inspected before/after; same PID, empty composer and keyboard hidden. This proves existing Read display and
  quiescent source renewal, not a live peer read transition or sending/failure lifecycle. Dynamic media resizing, albums under
  live sends and multi-account operation remain unverified. Local artifacts: `.build/ui-probe-evidence/astra-a44-delivery/`.
- Worker and primary full build logs zero warnings/errors; integration `044543-57615-13161` PASS9s, geometry correction
  `045008-60058-31007` PASS6s, each after one all-changed-Swift formatting invocation. A04 range regression PID58294 also passes
  with the unique-byte-coverage backend. A04 production/probe repair is committed as `8be1c9a`.

#### A44b1 explicit forum-topic receipts and ChatVM echo repair — 2026-10-03

- Worker `caf406d` integrated as `5b9b322`, independently reviewed. Exact positive `.messageTopicForum` route/account/client
  consumes its own updateForumTopic outbox watermark. Canonical raw message topic and chat must match; other topics, numeric
  collisions with saved/direct/thread kinds and missing topic identity cannot borrow it. Pending/Failed precedence stays intact.
  All-messages aggregation remains unimplemented; neither chat-global nor nil-to-General fallback was added.
- Subscribe before the reused fresh getForumTopic baseline, even with restored metadata. Receipt UUID/revision, exact returned
  info.chatId/forumTopicId, current source and request-owner UUID fence completion/cleanup. Initial readonly loading cannot start
  a duplicate request. Restored ForumTopic/history is not receipt authority; source departure cancels and terminally retires it.
- Review found the existing scalar observer refetched after every update, including TDLib's own getForumTopic response echo.
  ChatVM now consumes direct scalar/draft payload, preserving omitted info/lastMessage/order/unreadCount; only a changed inbox
  edge requests the omitted unread count once. Identical/outbox/draft echoes do not fetch. Later accepted scalar/draft (including
  nil clearing) overlays a late full response; separate info revision preserves newer info. Composer dirty/revision policy remains.
  This does not repair the independent ForumTopicsVM list cycle, tracked as A45.
- References: TDLib022d6020 `td_api.tl:2980–2992,10539–10552`, `ForumTopic.cpp:48–54,137–160`,
  `ForumTopicManager.cpp:617–636,831–880,1180–1190`. Official current6ad963e5/pre8e7e5f:
  `TelegramCore/Sources/State/AccountViewTracker.swift:1931–1959/1873–1901` and
  `Postbox/Sources/MessageHistoryView.swift:1155–1210,1364–1376/1128–1183,1333–1345` use exact-thread read state,
  with no global fallback for absent thread data. No upstream infrastructure imported.
- Native PID86336 `-ui-probe-message-delivery` PASS, including all A44a cases plus exact-topic/global/kind exclusion,
  duplicate-update read fence, wrong returned identity, canonical promotion, source/UUID retirement, late draft overlay/clear,
  identical echo before/after full response and changed-inbox decisions. Three actual MessageCells reconfigure only the matching
  topic status, retaining foreign/unknown rows and offset. The request-count assertions model production reducer decisions;
  they do not count whole-ChatVM or live TDLib requests. Saved result `.build/ui-probe-evidence/astra-a44-forum/`.
- Actual PID90037 on source5b9b322: existing DEBUG `-ui-smoke-forum-topic-write` only navigated to an existing writable General
  topic1; despite the flag's historical name, no text or messages were written. A pre-existing text and photo show single checks;
  three AX rows report Delivered (one is the service row whose visible status is intentionally hidden). After Home/foreground,
  ownership released05:06:29.414, restored05:07:55.499, Chat viewport settled/fresh history05:07:57.745 (+04); same PID,
  empty topic composer, same status/geometry: x8/w386, y93.3333/128.6667/563.6667, heights30.3333/391/208.
  Screenshots before/after inspected. This is route/display/source-renewal smoke, not proof of receipt freshness, peer Read
  transition, actual RPC counts, remote draft edits or forum send/retry. Native fixture covers exact watermark decisions separately.
- Six changed Swift files formatted together; primary `050253-84583-2008.log` PASS12s, worker `045916-78400-10799.log`
  PASS13s, complete logs zero warnings/errors. No data reset, focus activation or Simulator shutdown.

#### A45 forum fetch-response echo audit — 2026-10-03

- Source `909f62b`: `ForumTopicsVM.swift:281–286` invokes refresh for every scalar topic update;341–365 cancels/replaces its
  task then calls getForumTopic, without an in-flight skip or semantic dedup. The pinned TDLib022d6020
  `telegram/ForumTopicManager.cpp:831–880` executes the user query, and1165–1190 replaces its topic and unconditionally calls
  `send_update_forum_topic` (including the literal `topic_ == nullptr || true` branch). Thus an unchanged response can provoke
  another request. Independent reviewer and primary confirmed this; request-count/runtime impact has not been measured.
- A44b1's ChatVM loader has the analogous edge and must break it before receipt baseline integration. The list owner is a
  separate slice: consume scalar fields directly, preserve fields absent from update (lastMessage/order/unreadCount/info),
  reconcile only true semantic changes requiring a read, and revision-fence stale full responses. Preserve query, pagination,
  current-client authority and stable topic rows. Prior A30d restoration proof does not cover or repair this cycle.
- Additional pinned-source evidence: `ForumTopicManager.cpp:930–961` emits the same update for every page row before
  getForumTopics resolves; `ForumTopic.cpp:117–133` derives order from both lastMessage and draft date. A45a must suppress/coalesce
  page-created unknown demands, refresh omitted count/order only for relevant semantic changes, and overlay exact-topic scalar
  events accepted after either page or individual dispatch. Full page-vs-individual ordering of omitted fields and later
  hidden/renamed-info resurrection are separate A45b. Reset must preserve raw TD pagination cursor semantics and exact owners.
- A45a `e3fb6d9` (worker `af3a8bb`) consumes known scalar payloads directly and deduplicates unchanged echoes. Unknown
  lookups coalesce behind page/individual work; a returned page satisfies only unknown-echo demand, never later semantic
  demand for omitted count/order/lastMessage. Independent review caught and repaired that demand-loss race before integration.
  Inbox/draft changes refresh once; post-dispatch exact-topic scalar updates overlay either response. Individual requests
  validate UUID/generation/query/raw returned chat+topic and use weak VM ownership across await. Synchronous source departure
  permanently retires tasks/subscriptions/leases; late cleanup cannot remove a successor. Shared applying(update:) preserves b1.
- Native PID31180 on source e3fb6d9, `-ui-probe-forum-updates`, PASS: actual ForumTopicsVM with controlled async read closures
  and local scoped notifications proves page/individual echo counts, unknown/failed/filtered demand, direct scalar delivery,
  post-dispatch scalar overlay/raw cursor, semantic demand across page and individual completion, wrong result identity,
  late query/error cleanup and terminal source ABA. A mounted production ForumTopicCell updates from its topics publisher.
  This is not a full diffable-controller/viewport proof or live TDLib RPC counting; no global account mutation or server writes.
- Native PID32832 on the same source: active-search and restoration probes both PASS, covering the production search controller,
  field/table/snapshot lifetime, renewed bindings, late metadata, source/account guards, saved page/query/cursors and viewport
  helpers. These fixtures do not prove current live-server filtering or a real foreground cycle. Results are saved under
  `.build/ui-probe-evidence/astra-a45-topic-updates/` with the A45a probe output.
- Native PID34729 message-delivery regression PASS, including explicit-topic scalar extraction, echo decisions, late drafts,
  real MessageCells and stable owner/offset behavior. Whole-ChatVM and live peer-read transitions remain outside that fixture.
- Actual PID36808 on e3fb6d9: six real topic rows loaded, search reduced to topic1, same-process Home/foreground preserved the
  raw query and focused keyboard. Ownership released05:32:58.246, restored05:33:47.182, search binding accepted05:33:47.532 (+04).
  idb physical-keyboard input produced a Cyrillic-layout query despite visible English keys; this was observed, not labelled
  literal-General proof. Screen-keyboard input and its visible correction then produced General. Cancel restored all six IDs
  `[153,196,1,134,94,37]` at their original x0/w402, y116+61.3333n geometry. Screenshots before/search/foreground/after inspected.
  No topic selected, message sent or pin changed. This verifies bounded live read/filter/renewal/navigation, not RPC counts,
  delayed server response ordering, large-page pagination or remote topic edits. Existing native Back/Search styling gap remains A32.
- Five changed Swift files formatted together; primary `build-Debug-20261003-052515-30443-1717.log` PASS11s and worker
  `052305-27973-17007.log` PASS8s, complete logs zero warnings/errors. Source review passed on immutable af3a8bb.
  A45b now addresses older full responses overwriting a newer accepted row and page responses resurrecting hidden/renamed rows;
  it must preserve raw cursors, accepted-update overlays, semantic demand and the no-echo contract.

#### A45b full-result arbitration and server-search correction — 2026-10-03

- `597d6f3` (worker `9ec934a`) stamps each actual page/individual dispatch. A full exact-topic row is rejected only after a
  higher ordinal has committed; a newer pending/failed request does not discard usable older data. Shared admission preserves
  post-dispatch scalar/info changes and records accepted removal ordinals. Raw TD cursors remain independent of filtered rows.
  Full-response comparison baselines use captured read revision, not global completion revision: an unrelated topic update
  cannot turn an older full response into a newer live event. Independent review caught that draft seam before integration.
- Native PID45056 on 597d6f3 PASS: all A45a cases plus both completion orders, older-data visibility while newer read waits,
  newer failure, unrelated-topic events, later hide/rename removal, raw cursor, and a fresh later response replacing an old
  tombstone. This is a local full-response precedence policy, not proof of server causal ordering or originating RPC IDs in updates.
- Primary found a missed regression after initial review: new page filtering reused the legacy individual `contains` matcher.
  Actual PID50531 on 597d6f3, literal Geberal query, showed No topics found; prior e3fb6d9 PID36808 returned General for that
  typo. The pinned getForumTopics API supplies server-filtered results and does not promise substring matching. Screenshot
  `b1-search-geberal.png` confirms failure; `b1-search-failure.png` is an earlier literal-General success despite its filename.
- `c9317e5` (worker `c84cb18`) preserves raw server-page membership. Only a genuinely newer different name may invalidate
  that result locally; unchanged/same-name info echoes do not. Hidden topics remain excluded. Controlled cases cover fuzzy
  results, pending-page same-name echoes, later rename/hide and raw cursor.
- Correction native PID61547 PASS all A45a/b cases and server-query membership cases. Actual PID64127 on c9317e5: same
  literal Geberal query returns General/topic1 at x0/y62/w402/h61.3333. Before/after screenshots b1-search-geberal and
  b2-search-geberal were inspected; Cancel restores all six topic IDs. This closes the introduced page-filter regression
  for this real query, not every server search behavior or later info/individual-refresh lifetime. No topics opened or writes sent.
- Builds: primary053808-44178-22355 PASS23s, correction054358-59116-5045 PASS8s; worker053416-40099-30375 PASS11s,
  correction054200-53359-6587 PASS10s. Each two-file Swift delta formatted together; full logs zero warnings/errors and
  immutable review passed. The original review missed server-versus-local search semantics; the runtime failure is preserved.
- Follow-up identified as A45c: legacy info observer and individual refresh still apply contains to a known server-matched row, so same-name
  notifications can remove fuzzy results. Preserve only exact query/topic/name membership already granted by a current page;
  unknown lookups must not gain invented fuzzy authority. A bounded extra unknown refresh after page omission is also recorded;
  it is not the former unbounded echo loop. A46 pin ordering remains separate.

#### A44b2 read foundation and safe runtime availability — 2026-10-03

- Source at `835d4bd`: all-messages `refreshForumTopic` starts one task per topic without a concurrency bound, retains its VM
  across await and publishes returned metadata without checking raw chat/topic identity. Adding an independent receipt queue
  would duplicate those reads. First share and bound this metadata path; retain exact timeline/composer demands, protect live
  scalar/info changes, retire on source departure and count canceled-but-unfinished TD calls until their actual completion.
  Per-topic receipt rendering follows separately. General remains only an explicit composer demand, never a receipt fallback.
- Exact Telegram reference: `6ad963e` `Postbox/Sources/MessageHistoryView.swift`1155–1217,1364–1374 and pre-Liquid
  `8e7e5f`1127–1188,1333–1343 collect loaded messages' exact thread IDs, prune departed IDs and default missing per-thread
  watermark to unread. Adapt the contract only; no Postbox dependency. TDLib `022d6020`: `getForumTopic`, `updateForumTopic`,
  `updateForumTopicInfo`, exact `Message.topicId`; cached display metadata is not fresh receipt authority.
- DEBUG-only `-ui-smoke-forum-all-messages` selects only a naturally base-mode forum from loaded folders with zero unread
  messages/mentions/reactions/poll votes and no marked-unread flag. It rechecks raw getChat/getSupergroup identity, current
  account/client, attached top controller and the exact current row object before navigation. At most eight candidates are
  read serially. A source-departure token and 15s watchdog revoke late navigation; the watchdog does not cancel TD transport.
  No forced viewAsTopics override, synthetic chat, mode toggle, send or scheme change. Independent source review passed.
- Native availability result on the logged-in audit Simulator59EB535C-3610-41A2-AB68-53A9467DC24B/iOS26.5, PID5126,
  source `835d4bd` plus this DEBUG delta: fresh06:12:31 (+04) result has `loaded-forums=9, eligible=0`; no route opened.
  This is a blocker for live all-messages smoke in the loaded safe candidates, not proof of account-wide absence. Before/after
  bounded idb type counts remain22 elements; no personal message text was dumped. Evidence:
  `.build/ui-probe-evidence/astra-a44-all-messages/forum-all-messages-route-probe.txt`. Do not claim reader/receipt success
  from this availability check; their controlled production-component proofs and integration remain the next implementation.
- MainView.swift formatted in one invocation; primary061118-3495-7982 PASS26s, full log zero warnings/errors.

#### A44b2a bounded all-messages metadata reader — 2026-10-03

- Worker `0942d9c` integrated as `4a2a190`. `ChatForumTopicReads` owns at most two outstanding reads, including canceled
  TD continuations until they actually return. Exact entry/request UUID and raw returned chat/topic guard same-ID re-demand;
  weak captures let the owner deallocate during an uncancelable read. Source/composer-transfer retirement is terminal and
  clears metadata synchronously. Existing controller-pop draft save can retain permission metadata until VM teardown.
- Demand includes all canonical raw album members, General as an explicit composer reason, reply/edit, frozen voice/video
  recording and pending/outgoing drafts. A one-main-turn reconciliation handles callers that request before assigning context;
  expired reasons and unused cache entries are pruned. Typed forum admission checks matching supergroup identity and excludes
  channel/direct/saved routes. One controller hook forwards its existing frozen video topic; b1 explicit-topic path is unchanged.
- Existing scalar reducer rebases post-dispatch updates; per-entry info revision protects newer name/closed/hidden metadata.
  Predispatch cache cannot overrule a subsequent full read. Scalar/info echoes do not fetch. Failed/malformed reads remain held
  under unchanged demand; existing user refresh/Ready, explicit composer request or drop/re-add can retry. Failure does not
  starve the queue. No timer retry; scalar payload does not refresh omitted unreadCount/order/lastMessage. Existing consumers
  use topic info for headers/permissions; exact-topic receipt authority is the next b2b slice, not inferred from this cache.
- Native PID22721 on `4a2a190`, audit Simulator59EB535C-3610-41A2-AB68-53A9467DC24B/iOS26.5: fresh06:28:59 (+04)
  `forum-topic-reads-probe.txt` PASS production reader/demand builder under cancellation-insensitive controlled continuations:
  max-two outstanding calls, coalescing, pruning/re-demand, canonical album/exact raw identities, late scalar/info overlay,
  malformed replies, failure hold/progress/explicit retry, retired source ABA and weak owner release. Terminal replies are
  matched by topic ID rather than assuming Task start order. The fixture explicitly invokes retire; actual source subscription,
  whole ChatVM, pop draft persistence, header/viewport and live TD RPC behavior remain source-reviewed or unverified.
- Same PID's fresh `message-delivery-probe.txt` PASS ordinary/explicit-topic reducer and actual MessageCell regression,
  canonical promotion, stale wrapper rejection, batched stable-ID update and unchanged native fixed-row offset. It does not
  prove b2b all-messages ticks or live peer-read transitions. Evidence files preserved in
  `.build/ui-probe-evidence/astra-a44-all-messages/`; earlier safe live availability remains blocked (nine loaded forums, zero candidates).
- Immutable independent review PASS. Six Swift files formatted together; primary062812-22030-25473 PASS19s, worker062426-17963-24832
  PASS7s, full logs zero warnings/errors. Earlier worker062209 emitted one DEBUG WeakMutability warning, fixed without suppression.

#### A44b2b exact per-topic receipts in all-messages history — 2026-10-03

- Worker `76f6f73` integrated as `2190c4d`. Each existing reader entry owns `ChatDeliveryReceiptState` for its exact positive
  forum topic. Its receipt ticket starts with the same metadata request and consumes the raw response before metadata admission;
  no second RPC or queue is added. Direct scoped scalar updates change receipts even when metadata is absent or failed.
  Identical receipts advance the revision fence without publishing an unchanged state. Prune/retire revokes both owners before
  notifying current wrappers; re-demand starts with no inherited watermark. Cached/restored display metadata grants no receipt.
- ChatVM uses the canonical raw album member's chat/topic, not the newest display representative. Unknown current exact-topic
  watermark shows Delivered; nil/thread/saved/direct/foreign-chat and broadcast final states are excluded. Raw Pending/Failed
  precedence remains unchanged. A separate receipt callback derives only matching current wrappers, independent of metadata
  equality; existing Equatable publication and stable-ID batching repaint cells without scroll intent or per-row reads.
- Review found two additional initialization gaps: restored history assignment bypasses didSet, and new supergroup eligibility
  originally derived status before demand sync. Both now synchronize first, as does messages.didSet. A small b2a follow-up moves
  restored video metadata demand after the async reply lookup and current-source guard, immediately before installing its draft;
  the queued reconciliation can no longer prune that still-unassigned context. These ChatVM ordering paths are source-reviewed.
- Native PID34441 on `2190c4d`, same audit Simulator59EB535C-3610-41A2-AB68-53A9467DC24B/iOS26.5: both reports fresh06:41:21
  (+04) PASS. Reader probe covers distinct topic watermarks, direct update before/after failed metadata, duplicate update versus
  late baseline, wrong raw scopes while valid control topics remain Read, nil-cache pruning/re-demand and source retirement.
  Existing b2a queue/concurrency/lifetime cases also pass. No live TDLib RPCs or global source mutation were injected.
- MessageCell native adapter uses the production reader/projection and current raw wrappers: topic11 changes only its canonical
  album row to Read while topic12 stays Delivered, preserving the actual cell and fixed-row collection offset. Same stable-ID
  album promotion switches to topic12/Delivered; callbacks from the removed wrapper cannot repaint its replacement. Pending,
  failure, final-ID replacement, seed reset and retirement pass. Ordinary/explicit-topic/native batching regressions remain PASS.
  The adapter does not execute the entire ChatVM, live source subscription, self-sizing history or peer-read transport.
- Five changed Swift files formatted together. Primary064029-33247-16763 PASS14s; exact final worker063739-30512-24107 PASS11s,
  full logs zero warnings/errors. Independent immutable review PASS. Proof files:
  `.build/ui-probe-evidence/astra-a44-all-messages/forum-topic-receipts-probe.txt` and `message-delivery-b2b-probe.txt`.
  Safe live all-messages availability remains blocked as above; no server preference was changed to manufacture a fixture.

#### A45c known server-query row lifetime — 2026-10-03

- `0a4c6af` (worker `656e32c`) retains a known row only when accepted query, topic ID and name still match. Same-name info
  changes and inbox/draft refreshes no longer discard a server fuzzy match. Individual dispatch captures that name and verifies
  it against both current and admitted response after existing source/generation/UUID/ordinal checks. No fuzzy algorithm or
  transferable membership cache is added; unknown IDs keep the conservative matcher. Rename/hide/name ABA revoke the exception.
  Restored accepted-query rows retain display membership only, not fresh server metadata or permissions.
- Native PID76193 on 0a4c6af PASS all A45a/b/c cases: same-name changed closed state, inbox/draft reads and echoes, unknown
  same-name ID exclusion, rename/hide/query/source ABA, late replies and a rebuilt VM from the accepted display seed. The seed
  fixture uses the same captured client, not a real client epoch. Actual source-renewal/search smoke at earlier e3fb6d9 and
  fuzzy before/after c9317e5 remain separately scoped; no live remote edit/counting claim is inferred from these controlled reads.
- Native PID76765 active-search/restoration regressions PASS on 0a4c6af. Fresh result files timestamp05:56:14/05:56:07 (+04)
  were checked, then preserved as final probe outputs. All A45 evidence is under `.build/ui-probe-evidence/astra-a45-topic-updates/`.
- Two changed Swift files formatted together; primary055412-75499-10026 PASS10s, worker055207-73770-18802 PASS22s,
  complete logs zero warnings/errors. Independent immutable review passed. Next P1 is A44b2; A46 remains the separate visible
  pinned-order gap. Unknown-topic page omission may still cause one redundant refresh, not recursive identical-echo fetching.

#### A47 topic-list individual read fan-out — 2026-10-03

- Primary and independent source review at `69b0212`: `ForumTopicsVM.swift`339–344/421–429 registers distinct unknown
  same-chat topic updates; 460–501 drains every pending ID and starts individual reads without a shared outstanding limit.
  Reset229–234 cancels then drops task registrations, although a TDLib await need not finish on Swift cancellation. Rapid query
  generations can therefore overlap old and new native work. This is separate from A45's fixed per-ID echo loop.
- Natural trigger: pinned TDLib `022d6020` `td/telegram/MessagesInfo.cpp`28–79 consumes topic infos from message/history/search
  responses; `ForumTopicManager.cpp`1139–1148/1358–1375 publishes changed infos. A covered topic-list controller retains its
  same-source subscription until removal (`ForumTopicsViewController.swift`145–150). An empty-query list accepts these new IDs;
  `ForumTopicManager.cpp`831–847 dispatches a network getForumTopic for ordinary user clients even when info is cached.
  Normal getForumTopics page echoes are usually satisfied by the accepted page303–305; do not attribute fan-out to every page.
- Repair boundary: bound actual outstanding individual reads, including canceled-but-unfinished predecessors; coalesce demand,
  preserve exact request/source/query ownership, raw page cursors, A45 ordinal/scalar/info overlays and known fuzzy membership.
  Any cache pruning must retain row/pending/inflight/tombstone authority. Current maps grow within a query and clear on reset or
  retirement; this is not evidence of a cross-account or permanent leak. No new backend, navigation policy or pin-order change.
- Reference: Telegram current `6ad963e` and pre-Liquid `8e7e5f`, `submodules/TelegramCore/Sources/ForumChannels.swift`,
  finite getForumTopics limit/cursor response ownership; A44b2a's loaded-topic reader supplies an existing BetterTG cancellation
  ownership pattern. A specific concurrency limit is a BetterTG adaptation, not a claimed upstream value.
- Planned proof: controlled real ForumTopicsVM burst outside a partial/failed page, maximum outstanding count, fair coalesced
  draining, repeated query reset with uncancellable old completions, source retirement and all A45 regressions. No live lag,
  OOM, request-count or server mutation proof yet. Queue after A30h and before P2 A46.

#### A47 bounded individual reads: integrated proof — 2026-10-03

- `09db3f5` (worker `0f5bcd3`, reviewed tree `af57d4c`) separates the UUID-keyed outstanding transport registry from
  current-query topicID ownership. Canceled predecessors keep their slots until their exact tasks return. Each terminal
  removes only its UUID; a same-ID successor retains its authority. Current demand is a unique FIFO, duplicate reasons only
  upgrade semantic invalidation, and pages can satisfy only nonsemantic demand. Dispatch rechecks latest hidden/query
  membership and captures its read stamp/name then. A45 ordinal/scalar/info overlays and raw page cursor remain unchanged.
- Native PID97812 on audit59EB535C/iOS26.5, fresh report07:19:33+04: `-ui-probe-forum-updates` PASS. Real ForumTopicsVM
  with cancellation-insensitive injected continuations proves maximum two outstanding individual reads, 11 dispatched IDs
  after partial and failed pages, FIFO/coalescing, hidden queued veto, error/foreign-result slot release, two query resets with
  old slots still occupied, same-ID old cleanup versus successor, and source ABA retirement. Exact Task.value joins verify
  callback completion; all previous A45 checks pass too. Before-change baseline PID95173 also passed at07:15:58.
- Integrated supplementary regressions PASS: PID99039 restoration/snapshot at07:20:36/39, PID99673 actual active-search
  controller at07:21:30. The first supplementary launch used an unrecognized search argument; no search proof is attributed
  to it. The separate active-search launch used the verified flag. Evidence: `.build/ui-probe-evidence/astra-a47-forum-reads/`.
  These remain controlled native proofs, not real TDLib request counts, live foreground, server filtering or measured lag/OOM.
- One two-file SwiftFormat invocation after integration made no changes. Worker build `build-Debug-20261003-071551-95012-24969.log`
  PASS11s; primary `build-Debug-20261003-071859-97295-17064.log` PASS10s; full logs zero warnings/errors. Independent review
  passed. Queue has one record per distinct current-query demand and clears on reset/retire; no hard memory bound is claimed.
  Page requests and distinct VM instances do not share this limit. A46 remains a separate ordering repair.

#### A48 forwarding-topic snapshot ownership — 2026-10-03

- Source `34b7868`, `ForwardForumTopicsViewController.swift:205–212,288–331`: cell provider reads latest `topics`,
  falling back to a newly created cell on a miss. A page replaces that array and clears `loading` before an animated apply;
  a subsequent accepted query/page may replace it again while UIKit still reconfigures the previous snapshot.
  Reachable sequence: settled [1,2] → accepted [1,3] reconfigures1 → accepted [4] before completion → older provider asks1.
  RPC generation/query checks cannot retire already accepted UIKit work. This matches A42's independently observed failure
  mechanism, but no live forwarding crash is claimed.
  Unlike A42's queued Combine publications, Forward assigns topics and starts apply synchronously on MainActor; the precise
  deferred UIKit callback schedule remains unverified. Separately, a failed query reset retains the previous query's topics;
  a cursor-zero `load(reset:false)` retry then merges old and new query results. The accepted-query boundary is part of this repair.
- Repair boundary: forwarding topic selector only. Reuse `ForumTopicsSnapshotState` for transaction-owned models/clients,
  keep outgoing models through exact completion, and coalesce only the next payload. Preserve raw TDLib cursor, rights checks,
  selected topic identities and final forwarding service revalidation. Selection must wait for a settled/current displayed row;
  fallback must return the exact dequeued cell. Do not combine A46b pin ranking or unrelated forwarding UX in this slice.
- Proof plan: native production-controller/table probe with held apply completion, rapid accepted page/query changes, retained
  reconfigure IDs, stale completion, selection gates and teardown; existing forum snapshot/active-search regressions.
  Use injected read-only endpoints, no real forwarding/server writes. Telegram's separate UI infrastructure is not imported;
  this is UIKit transaction correctness under the established A42 contract, not a new server ordering claim.
- Initial integration `fe9424c` (worker `7710a9`, reviewed tree `eb2c373e`) serializes page/toggle snapshots, keeps outgoing
  models/clients, gates query selection and replaces previous-query rows on cursor-zero retry. Primary build
  `build-Debug-20261003-112447-8466-30715.log`: PASS9s, complete log zero warnings/errors. Native PID14762 at11:27:30+04
  FAILED its teardown assertion; this was not a runtime-complete handoff.
- Diagnostic-only `1fa99a9` (worker `2c82e6c`, reviewed tree `12cea598`) adds exact pop/containment receipts without changing
  production guards. Build `build-Debug-20261003-113410-35144-20625.log`: PASS9s, complete log zero warnings/errors.
  Native PID35915 at11:34:59 passes transaction/query/fallback/selection cases and post-retirement cleanup. Immediate pop receipt
  is parent=nil, absent from stack, retired=false, with models1/2 retained and apply busy; the later receipt is retired=true and empty.
  Thus waiting for `didMove(nil)` fixes the probe's timing assumption but does not establish immediate detached-owner admission.
  Next bounded correction must reject late reads/actions/new applies during this actual detached interval, while retaining models
  through the exact native completion and avoiding permanent retirement in a cancellable `willMove(nil)` transition.
- Follow-up `727103c` (worker `5a4ac6`, reviewed tree `e29ea3c`) remembers first non-nil containment. After that receipt,
  actual parent/children detachment rejects page/action/enqueue/drain admission before the terminal lifecycle callback; bootstrap
  reads stay compatible and exact completion remains unconditional. No window/nav-stack/`isMovingFromParent` gate or irreversible
  `willMove(nil)` retirement is introduced. A retained parent can continue its current read.
  Single SwiftFormat0/2; build `build-Debug-20261003-114744-67424-30857.log`: PASS9s, full log zero warnings/errors.
- Native PID68845 on audit59EB535C/iOS26.5, report11:48:19+04: PASS actual production controller/table, held native completion,
  coalesced queries, same-cell/fallback, closed/selected rows, failed head→retry/raw append cursor, stale source/query and teardown.
  Immediate pop receipt is retired=false/owner=false/parent=nil. The native read returns distinct cursor(91,44,900) and its exact
  Task.value plus held completion are consumed **before** retirement wait; original cursor and starts2/2 remain unchanged, queued
  and late models are not admitted. The intermediate receipt is still retired=false; final lifecycle cleanup empties models.
  First attachment is separately awaited; synthetic retained-parent `willMove(nil)` keeps loading/selection alive. This does not
  prove an actual canceled swipe, whole modal dismissal, live rights resolution or real forwarding. No server delivery is exercised.
- Existing supplementary regressions pass on the integrated follow-up: PID75259 restoration/snapshot11:50:49/52+04,
  PID75908 active-search11:51:32. Reports are fresh from newly resolved containers. Evidence under
  `.build/ui-probe-evidence/astra-a48-forward-snapshot/`; natural UIKit overlap and actual Forward delivery remain unverified.

#### A46 forum pinned ordering audit — 2026-10-03

- Source `cb723ab`: `ForumTopicPageState.merging` and `ForumTopicsVM.sortTopics` compare only order and topic ID;
  `ForumTopicCell` renders pin decoration/background without moving the row. A pinned topic with an older chronological
  order can therefore remain below an ordinary topic. This predates A45a's direct scalar path.
- Pinned TDLib022d6020 `ForumTopic.cpp:117–133` derives order only from last message and draft date. `td_api.tl:3917`
  exposes isPinned separately; getForumTopics is a temporary server-list API with an explicit raw pagination cursor.
  Telegram `6ad963e`/pre-Liquid `8e7e5f` `ChatListNodeLocation.swift:365–388`/`264–288` uses a separate pinnedIndex.
  `ForumChannels.swift:1265–1313`/`1075–1122` stores pinned thread IDs separately when applying loaded results.
- Preserve configured pin order, exact source/query ownership and raw cursor; do not infer pin positions from timestamps
  or topic IDs. Pinned `ForumTopicManager.cpp:748–774` consumes the server's ordered pinned IDs only as membership and
  emits an update only when isPinned changes; a pure remote reorder has no exposed position update. Preserve server-head
  response order where available and state the refresh limitation rather than inventing a local order. No server pin writes or
  runtime reordering were exercised; this is a gap queued after A45, not a completed parity claim.
- Actual PID36808 on e3fb6d9 confirms the visible defect: pinned General/topic1 is third, below two ordinary topics, both before
  and after search/foreground/Cancel. Screenshot `astra-a45-topic-updates/list-before.png` and list-after were inspected;
  no pin mutation was issued. Multiple configured pin ordering still has no runtime proof.
- A46a repair boundary: primary topic list only. Keep a query-owned display rank from the accepted raw zero-cursor server
  page, separate from chronological order; append and individual reads cannot assign configured rank. Preserve it while a
  same-query head refresh is pending or fails; clear on query change and transfer only matching-query restoration seeds.
  Newer pin-membership transitions must fence an older head's rank, including accepted individual full reads; equal echoes
  must not invalidate rank. Keep raw cursor, A45 full-read/fuzzy arbitration and A47 transport bounds unchanged.
  Unknown/re-pinned rank waits for explicit head refresh rather than fabricating pin position; remote position-only changes
  have the TDLib limitation above. Shared merge defaults and the forwarding topic selector remain a separate A46b follow-up.
  Plan: four files plus real-VM head/append/unpin/re-pin/query/restore/late-head regressions; source-confirmed ordering does not
  establish actual multi-pin/viewport behavior. A46 remains partial until remaining consumers and update behavior are addressed.

- Integrated A46a `34b7868` (worker `7573412`), independently reviewed tree
  `3613000505747ce3eee4dc0b979739dca64965da`. Query-owned `ForumTopicPinnedOrder` uses eligible exact-chat raw head IDs;
  non-head reads cannot assign rank, membership edges invalidate older tickets, and display restoration carries matching ranks.
  Shared chronological merge and forwarding selector remain unchanged. An initially unknown pin echo is admitted, but a known
  unpinned→pinned echo during a head read is indistinguishable from a concurrent change: it conservatively requires a second
  explicit stable head. No automatic pin-fetch loop or invented position is introduced.
- Integrated SwiftFormat0/4; primary `build-Debug-20261003-110934-87641-16429.log`: PASS15s, full log zero warnings/errors.
  Native PID88745 on `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone17Pro/iOS26.5, fresh forum-updates report11:10:15+04:
  PASS raw head order against chronology/ID, duplicate pin, append/individual preservation, unpin/re-pin, failed head, query and
  display seed, initial/equal/changed echo, scalar/individual membership races and source ABA. Existing A45/A47 cases also pass;
  exact injected native-task terminals are awaited, not evidence of real RPC timing or global transport bounds.
- Existing native restoration/snapshot regressions PID92263 (11:12:37/39) and active-search PID92585 (11:13:32) pass.
  Actual read-only forum list baseline on be6052b/PID84938 reproduced IDs153,196,1,134,94,37 with pinned General third.
  After `34b7868`, PID92862 shows1,153,196,134,94,37: General first at y116, row61.33pt, width402pt.
  `astra-a46-pinned-order/after.png` was inspected. No pin changes, topic selection or forwarding; native Back/search islands
  remain A32. Controlled multi-pin ordering is proven; live configured multi-pin changes and scrolled prepend/resize are not.
  Same PID92862 Home→foreground keeps the exact order/frames, with `ForumTopics client restoration: replacement accepted`
  at11:16:16.793+04. This proves one quiescent display-rank renewal on that loaded list, not active remote pin mutation.
- A46b before proof: actual PID92862, still `34b7868`, opened an existing photo's Forward action → searched the existing forum
  → entered its production topic selector. IDs153,196,1,134,94,37 put pinned General third at y290.67pt (first rowy168).
  `astra-a46-pinned-order/forward-topics-before.png` was inspected; no topic/destination selected and no Send.
  Reference: Telegram current/pre `submodules/TelegramUI/Components/PeerSelectionController/Sources/PeerSelectionControllerNode.swift`
  223–249/196–222 uses the shared forum ChatList and its separate pinnedIndex. After A48, reuse the query-owned pin projection
  in this consumer: accepted raw head assigns rank, append preserves it, accepted membership edges invalidate obsolete positions,
  and changed query clears it. Keep raw cursor, server query membership, A48 snapshot/selection gates and existing rights semantics.
  Native consumer checks must cover ordered pins, append/unpin/re-pin, query changes, failed head retry and unchanged selected IDs.
- A46b integration `e2dd664` (worker `8559c51`, independently reviewed tree `7f78bf8a`) reuses `ForumTopicPinnedOrder` in
  the production Forward controller. Exact-chat/positive incoming rows are merged before projection; raw response cursor/hasMore
  remain untouched. Only accepted raw head assigns ranks. Append observes known membership edges, including duplicate-ID edges
  within its page, without inventing rank; query change clears rank. A48 model/apply/selection/source/containment gates remain.
  Single SwiftFormat0/2; integrated build `build-Debug-20261003-120434-2571-25802.log`: PASS22s, full log zero warnings/errors.
- Native PID14782 on audit59EB535C/iOS26.5, fresh report12:07:44+04: PASS ordered two-pin head, invalid/foreign/hidden rows,
  reversed append order/raw cursor, across-page unpin→re-pin revocation, selected-ID persistence, failed head retry/new query
  and existing A48 transaction/teardown cases. Same-page duplicate ABA is source-inspected, not separately native-tested.
  This run's post-completion teardown receipt was already retired; the earlier PID68845 proof remains the explicit pre-retirement case.
- Actual PID15841 at `e2dd664`: existing photo → Forward → existing forum → production topic selector now shows
  IDs1,153,196,134,94,37. General1 is pinned and first at y168pt instead of third at y290.67pt; rows remain402×61.33pt.
  `astra-a46-pinned-order/forward-topics-after.png` inspected. No topic/destination chosen, pin mutation or Send. This is actual
  single-pin loaded-list proof; live multi-pin editing/reordering, permissions and delivery remain unverified.

#### A30d ForumTopics client recovery — 2026-10-02

- `958bc82` (worker `45c93ef`) adds prepared same-account replacement of only the stale topic-list navigation slot. Metadata
  is fetched with the captured ready client. Source/stack/account/chat/route-kind checks reject obsolete results; synchronous
  commit retires old page/topic tasks, subscriptions and open-chat lease. Adjacent restored Chat identity is preserved.
- Transfer accepted rows/query, raw search text, exact date/topic/message cursor, completed cursors, has-more, pending or failed
  reset/append, target-consumed state and stable topic-ID/pixel-offset viewport. In-flight cursors are not completed cursors.
  Raw input ahead of the stale VM restarts its own query at zero, without unrelated rows. A second epoch before view loading
  retains pending request intent. Cached rows are a display seed, not proof of fresh server-head reconciliation.
- Target lookup uses per-attempt identity through both captured-client awaits. Canceled/failed lookups can retry; an opened target
  is not replayed beneath an existing child. `01a2d84` (worker `610c9ff`) keeps metadata/target continuations weak across awaits
  and adds a content-free actual-commit DEBUG log. Active UISearchController/IME/modal/drag defers replacement; dismissal and
  terminal interaction callbacks retry. Automatic active-search restoration remains unimplemented.
- Viewport applies only after the latest snapshot and usable layout; a new query or user drag cancels it. References: pinned
  current/pre `ChatListNodeLocation.swift` 9–12,240–297 / 9–12,158–205; immutable account-bound `ChatListNode.swift`
  1216,1934 / 1213,1939; `ChatListController.swift` 4665–4672 / 4609–4616. Pinned TDLib `GetForumTopics/ForumTopics`
  carries explicit query and cursor triple. Client recreation is BetterTG's adaptation, not upstream architecture copied.
- Five Swift files formatted together; `build-Debug-20261002-213659-45775-2887.log`: PASS9s, zero warnings. Audit Simulator
  source `01a2d84`, PID `49689`: forum seed/target, actual generic coordinator and fixed-row UIKit viewport probe pass, together
  with client-restoration, Chat update delivery and Root authority regressions. Full suspended VM RPC/controller wiring is source-reviewed,
  not covered by that probe. Output explicitly retains these limits.
- A DEBUG-only `-ui-smoke-forum-list` opens one existing real topics route per process, without selecting a topic or presenting
  fixture UI. One-file build `build-Debug-20261002-213904-53667-8267.log`: PASS9s, zero warnings. PID `54903`, source `01a2d84`
  plus that committed route helper: real populated list retains its rows through two Home→foreground cycles. The second bounded
  idb stream records `ForumTopics client restoration: replacement accepted` at21:44:41 in that same PID. No messages/topics were
  selected, no draft/send/settings mutation performed. idb's timeout cleanup emits an asyncio diagnostic, not an app/build warning.
- Private UI/probes: `.build/ui-probe-evidence/astra-a30d-primary`; worker refs/logs under `.build/a30d-proof`. The first log window
  ended before foreground; only the second proves acceptance. Search/IME, target navigation, dynamic-height/populated-anchor accuracy,
  live pagination and changed route-kind recovery remain unverified. The native bottom Search Topics island is additional A32 evidence.
- Active-search regression confirmed2026-10-03 after the separate A42 crash repair: production `59f187b`, PID `54675`,
  audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iOS26.5. Focused Cyrillic query `фке` has no results. Home releases
  ownership02:53:57.505; foreground restores02:54:43.789 in the same PID, preserving the field/keyboard. Clearing the query
  still leaves zero rows after settlement; Cancel02:56:55 triggers replacement acceptance02:56:55.227 and six topics return.
  Private `foreground-cleared-settled.png` and `cancel-recovered.png` under `.build/ui-probe-evidence/astra-a30d-search-baseline`
  were inspected. No topic opened or edited. This is a stale active-search binding, not another A42 diffable crash.
- Next repair contract: retain exact topmost controller/search field and current raw text/selection/focus; renew only its
  client/VM binding after same-account/actor Ready and fresh route metadata. Keep global modal guards and the existing
  quiescent replacement path. Fence queued publishers, target/error actions and awaits to their captured binding; close an
  old diffable batch's own lifetime while rejecting stale viewport/load side effects. Swap only after snapshot drain; defer
  marked input, foreign presentation and active interaction through explicit lifecycle events. Native wiring and actual
  continued typing/clearing after foreground must be checked before marking active search fixed.

#### A30d active-search binding renewal — 2026-10-03

- `f551b40` (worker `5c65406`) retains the exact ForumTopics controller/search controller/field/table/data source and swaps
  only its immutable-client VM after current account/actor/Ready and fresh route metadata. It captures raw query at commit,
  preserving field text, UTF16 selection and focus. IME, foreign modal, native transition and table interaction defer via events.
  Global navigation modal guards remain unchanged. Every queued VM sink/target/error/metadata result has model+binding authority.
- A42 snapshot batches now retain their supplying clients as well as models. Old native completion always closes its own
  transaction lifetime; stale viewport/load effects are denied. Renewal waits for all pending/native batches to drain. Metadata
  failure clears stale rows and shows explicit Retry with exact failure/source/binding checks; typing does not auto-retry.
- Independent review repaired three introduced seams before acceptance: `1f959bb` (`465cf12`) keeps account/actor notifications
  synchronous so departure/return cannot disappear in queued sampling; `cc6ad7e` (`a75f667`) permits original-source rendering
  before getMe supplies an actor, latches first known actor only under exact original-source Ready and rejects unknown-identity
  epoch departure; `501af59` (`8a08600`) exposes a failure latched before view loading when Back first reveals that controller.
  Cross-epoch renewal still requires known identity. Metadata and target waits keep controller ownership weak.
- References: pinned current/pre `ChatListController.swift`4665–4672/4609–4616 and
  `ChatListSearchContainerNode.swift`115,143–144,712–720 /97,120–121,660–668 preserve account-bound query ownership.
  Pinned TDLib022d6020 `getChat/getForumTopics`, query+cursor and account-client update transport remain unchanged.
  BetterTG client-epoch restoration is its own adaptation; no upstream infrastructure is copied.
- Six Swift files formatted together. Primary builds `035458-85956-3726` PASS8s and `035939-97796-21734` PASS7s;
  DEBUG fixture builds `040658-11205-23255` PASS12s and `041539-25602-17621` PASS8s. Full logs have zero warnings/errors.
- Actual source `501af59`, PID1590, audit Simulator/iOS26.5: Cyrillic `фке` has zero results with focused software keyboard.
  Home releases ownership04:03:50.098; foreground restores04:04:41.091 and accepts search binding04:04:41.269 in the same PID.
  Clearing without Cancel returns all six topics. New Cyrillic `г` filters to one row after settlement. Keyboard Search hides
  keyboard but leaves search active. Second release04:06:54.014→restore04:07:55.359→binding acceptance04:07:55.524 preserves
  query/result and does not open keyboard. Clearing again without Cancel returns six rows. No topic opened or edited.
  Private screenshots/README: `.build/ui-probe-evidence/astra-a30d-active-search`; idb input/AX with simctl screenshot fallback.
- First native probe at `501af59`, PID99423 failed `foreign modal`: its presenter assumption was wrong. DEBUG-only `e5979fd`
  (`f8e40b1`) verifies actual reciprocal modal ownership and attachment. Rerun PID19367 confirms UIKit forwards presentation
  to UINavigationController while search stays active; modal guard/retry pass, but immediate search-dismissal+pop times out.
  `c9e2169` (`655698c`) waits for native didDismiss, verifies real pop result/stack exclusion and bounded parent=nil/retirement.
  Its actual-controller probe passes PID25951 at04:16:19, including Unicode selection, stale sinks, native batch drainage,
  metadata supersession, Ready gap, IME, explicit/stale Retry, nil→known actor, unloaded failure and account/actor ABA.
  `37e08e8` (`7097a76`) further waits for the exact held metadata task before checking post-pop rejection; final rerun passes
  PID27782 at04:18:38, fresh container `D5F001F3-D5D3-4E2D-8D86-1211F90B0398`.
  Its build `build-Debug-20261003-041749-27326-24775.log`: PASS8s, complete log zero warnings/errors.
- Separate `e5979fd` native forum snapshot/restoration regressions pass PID24685 at04:13:52/04:13:50. These cover production
  snapshot/cell helpers and coordinator/viewport/seed contracts, not live RPCs. Fixtures use isolated VMs and controlled
  metadata without global account mutation, TDLib leases or server RPC. Real pagination/metadata failures/route-kind change,
  interactive pop and simultaneous search-dismissal+pop remain unverified. A32 native Back/Search visual gaps remain open.
  Documentation build `build-Debug-20261003-042015-29687-457.log`: PASS4s, full log zero warnings/errors. Production/dependency
  forbidden-marker scan is empty; AGENTS/CLAUDE remain identical.

#### A23f static-image origin and shared demand — 2026-10-02

- `7426478` (worker `73bcb04`) requires an explicit originating client or frozen `TDImageOrigin` at every static-image entry.
  Admission precedes minithumbnail/cache/local decode/download. Placeholder/cache-only loads also revoke on source changes.
  Avatars and GIF tiles retain their source instead of rebinding an old File to a new client; folder, sender, reply, pin,
  forwarding, composer and profile consumers pass their existing captured client. Empty photos retire the prior request.
- Static images and `.none` prefetch use the existing account/client/file demand pool. Cancel releases one lease; last-owner
  cancellation and reacquisition remain serialized. Voice/video-note full-file prefetch stays fire-and-forget/unpooled, without
  file-global cancel; it is outside these shared-cancel guarantees. VOD offset/limit transport is unchanged. Decode remains off-main
  and request/source fenced. Detached native decode is not interrupted mid-operation; cache resolution policy is unchanged.
- References: pinned current/pre `ChatMessageInteractiveMediaNode.swift` 1370 / 1364 binds image work to its account;
  `FetchManagerImpl.swift` 797/823 registers/removes consumers. Pinned TDLib `downloadFile/cancelDownloadFile/updateFile`
  (`td_api.tl` 13778–13790): file identity is client-local, and cancellation is file-wide. No upstream infrastructure copied.
- All 22 Swift files formatted together; integration `build-Debug-20261002-214759-61736-17727.log`: PASS18s, zero warnings.
  Main and independent delta reviews found no introduced production blocker. Audit Simulator source `7426478`, PID `63466`:
  static-image/shared-demand/scoped-delivery probes pass with actual UIImageViews and private PNGs. Nil/stale/cache/source
  collision, multiple views plus prefetch, last release/reacquire, late RPC/decode, reuse and deinit are covered without server writes.
- PID `69030`: media-reveal and text-spoiler pass, but profile-grid fixture fails `ordinary media regressed`. Its thumbnail
  injector retained the initial fixture's origin after creating a replacement-client fixture. `b3aa790` changes only that
  DEBUG fixture wiring, preserving the earlier stale-origin assertions. One-file format/build
  `build-Debug-20261002-215620-70529-12978.log`: PASS9s, zero warnings. PID `70966`: profile-grid, static-image, shared-demand
  and scoped-delivery all pass. Initial failure is retained under `initial-7426478`, not erased or counted as a pass.
- Actual Saved Messages → Profile at `7426478`, PID `69030`: avatar and populated shared-media grid load; full header title,
  402pt header/362pt labels/96pt avatar remain correct. No media/editor/message mutation selected. Separate PID `53678` at
  `b3aa790`: timed video-note hold/native-player regression passes. Native inline-animation PID `9931` and gallery-owner PID `24400`
  pass separately; active system PiP remains unsupported. Private evidence: `.build/ui-probe-evidence/astra-a23-static-primary`.
  Live multi-account switching, real canceled TDLib downloads, unpooled prefetch and every thumbnail consumer remain unverified.
- Further bounded source audit at `7426478`: pending nonzero position → suspended metadata → order0 removal → late append
  can resurrect a row. Existing `chatRefreshIDs` guards overlapping refreshes, not this insertion. A23g will guard semantic-list
  membership through hydration. Pinned TDLib `td_api.tl`10403–10406 requires order0 removal and allows positions through last-message/draft;
  11473–11476 says `getChats` is informational, not an atomic list-state source. Bulk rebuild/settings races remain A34/A35.

#### A23g pending chat-list membership — 2026-10-02

- `1cd9ecf` (worker `551707e`) serializes pending hydration by account/client/chat/semantic list and exact destination folder.
  All four membership entry points share the production helper. Zero order and omitted lists in complete last-message/draft
  vectors remove rows and revoke pending insertion. A positive update during hydration coalesces into one follow-up read;
  only the latest intent may append, with its accepted order/pin. Remove→re-add can proceed before the canceled old RPC returns.
  Old success/nil/error cleanup cannot clear replacement ownership. Source/folder/root-ticket changes fence terminal application.
- References: pinned TDLib `td_api.tl`10398–10406,10430–10433; `MessagesManager.cpp`33622–33658,27091–27094,27128–27131
  confirms complete current membership vectors and omitted zero-order lists. Pinned current/pre `ChatListNode.swift`
  3327–3365 / 3477–3515 serializes accepted list transitions. No Postbox/SignalKit infrastructure copied.
- Five Swift files formatted together; `build-Debug-20261002-221330-92632-19395.log`: PASS16s, zero warnings. Audit Simulator
  source `1cd9ecf`, PID `94658`: actual helper/CustomFolder/RootListAuthority probe passes sixteen suspended hydrations:
  pre-dispatch removal, late success/nil, coalesced order/pin, omission, re-add before old reply, distinct lists/accounts/clients,
  replaced folder/root ticket, rejection and retry. Root/scoped-update/forum-restoration/classic-navigation regressions also pass.
- Evidence: `.build/ui-probe-evidence/astra-a23g-primary`; worker `.build/root-chat-insertion-proof/README.md` records its
  initial DEBUG fixture compile corrections and final clean build. No real account changes or server calls. RootVM notification/RPC
  wiring is source-reviewed, not exercised by the helper. Pending unread/user/non-position hydration, bulk rebuild A34 and scope
  notification ordering A35 remain open. This proof establishes membership, not complete latest message/draft payload parity.

#### A32 explicit navigation buttons and native Back limitation — 2026-10-02

- `941a90a` (worker `71289be`) uses an app-owned UINavigationBar with ordinary UINavigationControllers at all seven production
  constructors. Per-instance `hidesSharedBackground` is reapplied to initial/late/replaced buttons and the previous item's native
  back item. Targets/actions/menu/customView/enabled/delegate remain unchanged. Native Back is not replaced with a custom left action.
  Existing full-width material appearance gains compact-scroll-edge coverage; no search/safe-area/gesture layout changes.
- References: pinned pre-Liquid `Display/Source/NavigationBar.swift`1153–1167,1194–1227,1286–1310 and
  `NavigationButtonNode.swift`299–313; public UIKit26.5 `UIBarButtonItem.h`147–166, `UINavigationItem.h`31–38,154–165.
  The background flag is not an appearance-proxy property. No Telegram infrastructure/private subview traversal copied.
- Nine Swift files formatted together; `build-Debug-20261002-220321-68144-21386.log`: PASS16s, zero warnings. PID `76056`:
  actual offscreen navigation/bar probe, generic client and forum restoration regressions pass. Probe verifies item identity,
  initial/late/replaced actions, generated/explicit back, native stack methods and all four appearance states, not visible chrome.
- Production Saved → Profile → Edit, same PID: Save is plain text without its capsule; Back remains circular on Profile and a
  capsule on Edit. Back returns to Profile and Saved without saving. idb exposes editor navigation as one Group, not separate
  Back/Save children; coordinates came from screenshots. Long-press returned to Profile; native history-menu behavior is unverified.
- Diagnostic-only `3a7ac85` (worker `80ad6e8`) records bounded public item flags without titles/IDs/content. Two-file build
  `build-Debug-20261002-221009-76792-23655.log`: PASS19s, zero warnings. PID `88393`: real attached owned bar, exact previous
  stack item, `hidesSharedBackground=true`, group0/plain/no custom action before and after layout, but the native Back background remains.
  This excludes an unconfigured bar/wrong-item explanation; it does not establish a UIKit implementation cause.
- One-line timing trial `839c26e` (worker `eda9c64`) sets the generated back flag before assignment. One-file format/build
  `build-Debug-20261002-221603-96136-10079.log`: PASS8s, zero warnings. PID `96492`: headless probe passes; actual Profile/Edit
  still show the same Back background. The ineffective trial is removed; no private workaround or custom pop action is introduced.
- Cleanup `3983b48` (worker `7d361e1`) removes synthetic back items and title tracking. UIKit retains nil Back and adaptive
  title policy; only explicit back/left/right buttons receive the background flag. Two-file format and integration build
  `build-Debug-20261002-223232-18887-16383.log`: PASS43s, zero warnings. PID `20378`, source `3983b48`, same audit Simulator:
  actual navigation probe passes nil preservation through title/display-mode/stack changes and explicit→nil reset.
  Saved → Profile → Edit → Back → Saved succeeds without edits. Save remains plain; native Back remains circular on both
  Profile and Edit. Public diagnostics confirm attached owned bars, nil back items and exact previous stack ownership.
  Editor navigation remains one AX Group; Back coordinates came from settled pixels. This cleanup is not a visual Back fix.
- Private captures/diagnostics: `.build/ui-probe-evidence/astra-a32-primary`. No profile fields edited/Save tapped/server mutation.
  Native Back/background/history, interactive cancel, first-frame polish, RTL/dynamic widths/dark mode and native search remain open.
  Continue independent P1 list ordering while preserving this reproducible public-API limitation.

#### A32 native search placement — 2026-10-03

- `1ef0935` sets `.stacked` and disables toolbar integration only for non-nil search controllers on app-owned bars.
  Setters are idempotent; search/delegate/field identity, text/selection, active state, scrolling policy and native Back are retained.
  No global appearance mutation, private subview traversal or controller/delegate replacement. The Forward picker owns a separate
  UISearchBar header and is unchanged by this policy.
- References: pre-Liquid `8e7e5fe`, `ChatListHeaderComponent/Sources/ChatListNavigationBar.swift`272–326 retains search in
  the top navigation region. Local UIKit26.5 `UINavigationItem.h`39–53,232–254 defines stacked placement and the public toolbar
  opt-out. These APIs establish preferred placement, not full classic visual styling; no Telegram UI infrastructure is copied.
- Independent review passed final tree `7dd516d8`. Both changed Swift files formatted in one invocation; final build
  `build-Debug-20261003-120206-97759-31692.log`: PASS18s, full log zero warnings/errors. Native PID99807, report12:03:03+04,
  passes initial/late/replaced/removed search, repeated layout, non-nil selection[2,5], delegate/text/scroll preservation and unowned
  bar isolation, plus existing Back/action/appearance checks. Integrated PID14782 repeats PASS at12:07:37.
- Actual PID99807, source `1ef0935` on audit59EB535C/iOS26.5: top Search Topics replaces the bottom toolbar island; first topic
  moves from y116 to y176pt, below search. Active field is(16,70,315,44); query `articles` returns topic37 at y122pt.
  Home→foreground in the same PID preserves query, keyboard and these frames; clear/close restores all six rows with General first.
  The narrow replacement log has no receipt, so this proves foreground UI continuity, not a newly established TDLib client epoch.
  Inspected `astra-a32-search-placement/after-final.png`, `active.png`, `foreground-search.png`.
- Search capsule/shadow, circular Back/Close, other search screens, rotation, RTL/Dynamic Type and accessibility remain open.
  Production/dependency forbidden-marker scan is empty at `e2dd664`; this is not proof that all runtime chrome is classic.
- Supplementary integrated forum regressions at documentation HEAD `8a26464`: PID64049, fresh restoration/snapshot reports
  12:20:20/22+04, PASS; PID65325 active-search12:22:15 PASS. These preserve their controlled-coordinator/table proof limits;
  no additional live epoch claim.

#### Background Simulator launch — 2026-10-02

- User requested no focus stealing during repeated smoke. `a264c4e` changes the wrapper to `open -g -a Simulator` and syncs
  AGENTS/CLAUDE. macOS `open --help` defines `-g` as no foreground activation. Boot readiness, install, app launch and idb remain
  unchanged; no Simulator shutdown or extra activation. Shell syntax and `build-Debug-20261002-215832-37840-40.log` pass (5s,
  zero warnings); subsequent video-note/animation/gallery smoke launches succeed through this path. On the inline-animation run,
  read-only `lsappinfo front` reports the same opaque front-application ID before and after launch; no application was activated separately.

#### A34 accepted list projection and refresh ownership — 2026-10-02

- `4185849` (worker `85cbcec`) retains typed latest-per-field deltas only for active rebuild/hydration/refresh reads. Raw Chat,
  peer and list RPCs have separate dispatch revisions: older accepted values cannot replace a fresher response. Explicit nil
  photo/draft/last values clear old fields; complete positions revoke omitted lists, newer partial positions override their list.
  A final synchronous reconciliation precedes folder installation; positive missing-row intents use the new exact folder owner.
- Pending insertion keeps its lease through actual helper admission, not only until hydration returns. A23 membership ownership
  remains authoritative. Requested peer IDs alone receive user deltas. Terminal/canceled/replaced leases clear retained values;
  repeated updates coalesce instead of appending a journal. Native RPC cancellation is not claimed.
- Main review found superseded refreshes retained projections until RPC return. `3290ba4` (worker `29b7ce0`) adds synchronous
  per-chat refresh retirement and exact-identity cleanup. Rejected startup also closes its captured owner. Independent source
  review found no further introduced blocker; it did not exercise full RootVM/TDLib transport.
- References: pinned current/pre `ChatListUI/Sources/Node/ChatListNode.swift`3327–3365 / 3477–3515 serializes accepted list
  transitions. Pinned TD `td_api.tl`10398–10406,10430–10433,11473–11476 defines full positions/removal and warns `getChats`
  is informational. Existing 200-item reads/new group subscriptions are unchanged; this is not exhaustive chat-list hydration.
- Nine integrated Swift files formatted together; `build-Debug-20261002-224502-40819-31807.log`: PASS29s, zero warnings.
  Source `3290ba4`, audit Simulator PID `44216`: actual reducer/insertion probe passes raw/peer/list boundaries, nil clearing,
  suspended rebuild/new-folder replay, late admission, remove→re-add/coalescing and suspended refresh retirement. Root membership,
  scope settings, source authority, scoped Chat updates, Forum restoration and native navigation regressions all pass.
  Fresh A34/A35 files timestamp `22:46:03`; evidence `.build/ui-probe-evidence/astra-a34-primary`. Authenticated root is populated;
  All→people→All selection was exercised without opening other chats or editing folders. This does not reproduce a live delayed
  rebuild. A dedicated full-new-Chat snapshot runtime case and unobserved Chat/group fields remain outside proof.

#### A35 scope notification read authority — 2026-10-02

- `67c9470` (worker `d7f2462`) reserves three typed scope revisions synchronously before dispatch. A new load replaces old
  reservations; an accepted scoped update revokes only its scope. Each current response publishes immediately, with immutable
  client/Root ticket validation before and after await. Failure leaves accepted values unchanged; stale cleanup cannot revoke
  a newer request. Root account/client invalidation clears ownership. No notification settings are written to TDLib.
- References: current/pre `TelegramCore/Sources/State/ManagedGlobalNotificationSettings.swift`80–98 preserves current preference
  state at asynchronous commit; pinned TD `td_api.tl`10554–10555,13460–13461 supplies update/get scope semantics. No upstream
  infrastructure copied. `FolderView` consumes the existing published dictionary for mute presentation.
- Five-file integration format/build `build-Debug-20261002-223928-27434-8714.log`: PASS50s, zero warnings. Source `67c9470`,
  PID `31611`: actual loader with held continuations passes update-before-dispatch, in-flight update, immediate publish,
  newer overlapping batches, late success/failure, new load after update, account/client/epoch and cancellation. Root/insertion
  regressions pass; all three files freshly written `22:41:07`. Evidence `.build/ui-probe-evidence/astra-a35-primary`.
  Combined A34 PID `44216` repeats the loader proof. No server mutations; visible mute-badge race remains source-only.

### Implementation ledger

| Priority | Flow | Telegram reference | TDLib API / model | Status and proof before revalidation |
| --- | --- | --- | --- | --- |
| P0 | Remove MobileVLCKit; local audio/video playback seam | `submodules/TelegramUniversalVideoContent/Sources/PlatformVideoContent.swift` at the pre-Liquid baseline | `downloadFile`, `updateFile`, `cancelDownloadFile` | **partial** — `LocalMediaPlayer` uses AVFoundation, gallery playback pauses offscreen and has thumbnail fallback, and downloaded Ogg/Opus audio is cancellably decoded by FFmpeg before AVPlayer use. A range-backed FFmpeg controller now emits owned BGRA video and interleaved float audio for generic VP9/Opus WebM without a full download, renders both tracks on one Apple media clock, and is production-routed through the persistent inline/fullscreen gallery owner. `./build.sh build` passes without warnings and `rg` finds no VLC dependency/import/API marker in `project.yml` or `BetterTG`. Persistent FFmpeg sessions span rolling windows and sample-buffer PiP uses the exact display layer; only active system PiP/device proof remains. |
| P0 | TGS stickers and animated/custom emoji | `AnimatedStickerFrameSource.swift` gzip/rlottie path, `AnimatedStickerNode.swift` lifecycle, and pre-Liquid `MultiAnimationRenderer.swift` / `EmojiTextAttachmentView.swift` | `MessageSticker`, `TextEntityType.customEmoji`, `getCustomEmojiStickers`, `downloadFile`, `updateFile` | **partial** — timeline/gallery TGS uses bounded zlib decode, pinned Lottie 4.6.1, synchronized loops, visibility pause, parsed cache, prefetch/cancel, and thumbnail fallback. Custom-emoji entities are batch-resolved by ID, mapped from arbitrary TDLib order, overlaid on exact TextKit glyph rects, keep the native glyph until first frame, and share TGS/WebP/WebM clocks/lifecycle. `./test.sh` passes; Telegram `tiny.tgs` decodes to valid 100×100@30 JSON; current idb smoke confirms ordinary/wrapped text and timestamps remain stable. No custom emoji exists in the reachable viewport, so visual rendering and `needsRepainting` substitution remain unproved/pending. |
| P0 | Animated WebP | `submodules/WebPBinding/Sources/UIImage+WebP.m`; Telegram only uses its static frame fallback | `StickerFormat.webp`, `File`, `downloadFile`, `updateFile` | **partial** — direct pinned libwebp 1.6.0 demux preserves frame timing, blend/disposal canvas and premultiplied alpha; timeline/gallery share a synchronized display clock, off-main decoder, 64 MiB frame/asset caches, full-file prefetch/cancel, visibility pause, and thumbnail fallback. `./test.sh` passes; the exact metadata path decodes upstream's 4,764-byte animated fixture as 990×1050, 8 frames/0.8 s, and the first BGRA frame proves alpha 0…255. Current `./run.sh` + idb launch/chat smoke is stable; visual playback awaits a reachable WebP sticker in simulator data. |
| P0 | WebM/VP9 alpha stickers and generic FFmpeg playback | `AnimatedStickerNode/VideoStickerFrameSource.swift`, `FFMpegMediaVideoFrameDecoder.swift`, `FFMpegAVFrame.m` | `StickerFormat.webm`, `File`, `downloadFile`, `updateFile` | **partial** — checksum-pinned FFmpeg 9.0 decodes the main VP9 stream plus Matroska `BlockAdditional` alpha stream, scales to BGRA, premultiplies alpha, and feeds synchronized timeline/gallery loops with off-main decode, 64 MiB caches, prefetch/cancel, visibility pause, and thumbnail fallback. GIF/non-Apple animation containers now route through the same renderer while MP4/MOV retain AVFoundation. The non-looping range decoder retains probe packets, decodes VP9+Opus on a named worker, copies borrowed C frames before callback return, trims seek preroll/sample tails to the exact requested interval, and supports supersession/cancel. Its renderer uses pooled IOSurface-backed BGRA buffers, packed Float32 PCM and one `AVSampleBufferRenderSynchronizer`, with bounded generation-aware queues and no `DisplayImmediately`. The rolling controller is production-routed for public, secret, streaming, non-streaming and already-cached WebM/Matroska videos while Apple containers stay on AVFoundation. `./build.sh build` and the gallery-owner idb probe pass; persistent cross-window decoder and sample-buffer PiP adapter probes pass; real-message visual proof and active PiP on a capable device remain. |
| P0 | Voice notes: Ogg Opus, waveform, record/lock/edit/send | `ManagedAudioRecorder.swift`, `OpusBinding/Sources/opusenc/opusenc.m`, `AudioWaveform.swift`, `TGModernConversationInputMicButton.m`, and pre-Liquid `ChatRecordingPreviewInputPanelNode.swift` | `VoiceNote`, `InputMessageVoiceNote`, `resendMessages`, `updateMessageSendSucceeded/Failed`, `downloadFile` | **implemented breadth** — capture is 48 kHz mono signed-16 PCM, rejects recordings below 0.5 s, produces an exact 100×5-bit/63-byte waveform, and sends only validated Ogg/Opus. Transactional send manifests survive registration/crash races, failed sends honor TDLib resend state, multiple drafts promote, and unsupported paid/alternate-reply states cannot silently resend. Telegram's 0.19 s hold/release, slide-cancel/lock distance+velocity ordering, pre-arm/system-cancel preservation, VoiceOver lock, and scoped bottom-edge deferral are implemented. Locked Stop-and-preview closes WAV segments, validates/merges exact PCM frames off-main, derives Telegram-normalized waveform samples, and atomically owns a revisioned editable draft. The UIKit island exposes Delete, Record More, Play/Pause, hollow seekable waveform, two continuously draggable/VoiceOver-adjustable trim handles, selected duration and Send. Trim metadata is revisioned and restored; selection is at least 1s/56pt, playback and seek clamp to it, releasing either edge previews the changed edge, and Resume presents destructive-trim confirmation. Any non-full trim is materialized to a new PCM revision before Record More or Ogg promotion, recomputing exact duration/waveform. Dedicated playback has reciprocal arbitration and scoped session release. Reply/interruption ownership, cancel/send/trim generations, manifest relocation, relaunch restoration and cleanup are covered. `./test.sh` passes; idb proves exact `142→202`/`304→254.14` handle travel, hollow seek, edge preview, confirmation Cancel/Continue, revisioned append, relaunch playback, and trimmed safe-Send ordering (`1.33104s` materialized before `encoded=true`) with unchanged timeline and empty stores after Discard. Remaining voice work is encoder-quality parity/polish, not a missing requested flow. |
| P0 | Video notes | `submodules/Camera/Sources/VideoRecorder.swift`, `CameraRoundVideoFilter.swift`, `VideoMessageCameraScreen`, `ResultPreviewView.swift` | `InputMessageVideoNote`, `InputVideoNote`, `sendMessage`, `resendMessages` | **implemented multi-segment breadth** — the writer serializes capture queues, gates pre-video audio, waits video+audio EOF, center-crops/orients and round-masks actual pixels, and validates network-optimized 400×400 H.264 High/CABAC ~1 Mbps + mono 48 kHz AAC MP4. Generation-scoped AVCapture requests microphone then camera, defaults front, rejects stale PTS, freezes device orientation per recording, cleans interruptions/background/audio ownership, soft-stops at `>59.5s`, and hard-clamps at 60s. UIKit composer tap toggles mic/video; the unchanged Telegram 0.19s arm, live/release distance+velocity ordering, pre-arm lock, system-cancel preservation and bottom-edge deferral route both modes. A child recorder keeps the composer gesture alive and shows the classic max-369pt round camera, 4pt progress, 44pt flip/flash, pinch zoom, front-screen/back-torch flash, holding/lock/cancel, locked Stop-to-preview and release-to-send. Live 1s-throttled front/back switching rejects queued old A/V, removes the capture timestamp gap from both tracks and encodes a six-frame/0.2s dissolve instead of only smoothing the preview. Single-result preview loops muted and can play/pause/delete/send; TDLib promotion uses `InputVideoNote` and preserves the snapshotted reply. Atomic manifests own adopted MP4s across crash/chat close, reconcile outcome-before-registration, expose safe no-paid retries while keeping unsupported failures discardable, and clean success/discard/permanent delete. The ordered-segment foundation owns stable-ID MP4 segments, atomically persists revisioned global trim, composes video/audio on identical boundaries, samples exactly 13 full-composition thumbnails, materializes a zero-start 1…60s export, and preserves a 0.5…1s first result for Record More. `LocalMediaPlayer` retains the full `VideoNoteCompositionResult` snapshot lease, applies `forwardPlaybackEndTime`, exact last-target-wins seeks and loops from the global trim lower bound without rebuilding the item. UIKit Record More is visible only below 59s, starts hands-free, ignores sub-0.5s Stop, appends in order while clearing prior trim, uses aggregate 59.5s soft/60s hard limits and non-destructively restores preview on capture failure. The UIKit strip decodes exactly 13 indexed JPEGs off-main with cancellation, keeps them stable across trim revisions, and overlays adjustable global handles with an epsilon-safe exact 1s minimum. Live drag keeps handles active, pauses and exact-seeks only the changed edge; terminal save blocks other actions, persists once from the captured revision and resumes from the lower bound using current playback intent. Composition playback appears before thumbnails, then advances monotonically from empty to repeated frame 0 to all 13 exact frames without disturbing trim state. Circle tap and VoiceOver activation toggle mute separately from Play/Pause; a visible mute badge and scoped playback audio session track every-loop re-mute and reciprocal Media takeover. Navigation/relaunch restores the originating chat’s draft and stored reply; final send rejects aggregate selections below 1s, materializes the selected range and transfers the durable origin explicitly. A transformed time-0 frame from that materialized MP4 becomes a quality-0.4, ≤320px, <200KB JPEG `InputThumbnail`; real-image/dimension validation falls back to nil, while valid JPEG ownership persists beside the MP4 through retry/relaunch and terminal cleanup. Recording→send adoption is idempotent by durable origin ID and adopt+begin holds one actor lease. Runtime reservations cover draft/origin/file aliases; terminal cleanup first persists a relaunch-safe tombstone, confirms recording-manifest deletion, then removes send authority. Any failure leaves both durable authorities for retry, including missing-media and registered-success recovery. Timeline video-note bubbles are circular, cancellably downloaded, thumbnail-backed, offscreen-paused and locally playable with reciprocal audio arbitration; secret notes call `openMessageContent` before hold-to-reveal. `./test.sh`/`./run.sh` pass. Probes prove 1.0s A/V, round/orientation pixels, concurrent drain, pre-video audio, crossfade/audio-retime, limits/cancel, decoded segment/PCM order, exact thumbnail times, global trim, legacy manifests, same-origin dedupe/barrier, atomic enqueue, durable/corrupt-thumbnail handling, removal-tombstone relaunch and send success/failure races. idb proves voice↔video toggles, real permission/camera-unavailable routing and exact cleanup; Simulator has no camera, so hardware capture/flip/flash remains unproved. |
| P0 | VOD before full download, range seek/refetch, PiP | pre-Liquid `ChunkMediaPlayerV2.swift`, `ChunkMediaPlayerDirectFetchSourceImpl.swift`, and `UniversalVideoGalleryItem.swift` native PiP lifecycle | `downloadFile(offset:limit:)`, `getFileDownloadedPrefixSize`, `getFile`, `updateFile`, `cancelDownloadFile`, `updateDeleteMessages` | **partial — inline/fullscreen native VOD + owner-scoped PiP + production FFmpeg range playback**: each injected TDLib client owns its file coordinator and private update streams. Reads cap at 256 KiB, probe 512 KiB, fetch 2 MiB, reuse overlap, cancel disjoint/stale generations, distinguish cached/buffering/offline/retryable/terminal state, and never treat `expectedSize` as EOF. Refcounted leases share a source and only the last current lease cancels. FFmpeg 9 custom AVIO uses a 64 KiB buffer, exact checked seek/size callbacks, named blocking threads, shared raw-PTS A/V timeline and ≥10s packet lookahead. One persistent demux/codec/SWR session now spans soft rolling horizons within each seek generation; crossing frames are emitted whole, sparse per-track packets use a globally ordered bounded FIFO, pause retains the session, and seek/offscreen/cancel replace it terminally. Decoder reads share the source's cancellable serialization gate, retry transient displacement, retain stream-probe packets, cap allocation/read/packet work, decode bounded windows to owned BGRA and 48 kHz interleaved float frames, drain codecs/SWR at EOF, clip output to `[seek,target)`, and terminate deterministically on supersession/cancel. Apple-decodable non-secret MP4/M4V/MOV uses strict custom-scheme `AVAssetResourceLoader` metadata and serialized ≤256 KiB reads; `LocalMediaPlayer` retains the asset/delegate/lease, explicitly manages a 1s playable threshold and 10s forward buffer, preserves 0.5×–2× rate, and adopts raw AVKit pause/play/rate/EOF intent without rebuffer restart races. WebM/Matroska routes through the rolling sample-buffer controller for range-capable public media and through full-download-then-FFmpeg for secret/non-streaming media; completed files re-enter the same FFmpeg backend instead of AVPlayer. Fullscreen gallery preserves start time and exact thumbnail until first frame, exposes generation-safe fallback/Retry plus a full-width UIKit blur footer with play/pause, ±15s, duration, disjoint loaded ranges, terminal scrub, mute, rate, auto-hide and VoiceOver seeking. Serialized loader and typed FFmpeg failures distinguish buffering/offline/retrying/terminal failures; generation-guarded publisher bindings prevent canceled or replaced backends from publishing stale state. Offline/timed-out VOD preserves the playhead and retries through a fresh range session without forcing a full download, while terminal decode failures retain generation-safe full-download fallback. A message-scoped owner now retains the exact view/layer/player/resource-loader/TDLib lease across standalone timeline, grouped album tiles, fullscreen and PiP. Inline videos are muted aspect-fill with controls hidden; only the greatest-visible-area owner is active, using the real standalone or mosaic-tile frame, and inactive owners defer all local/VOD/full playback loading. Every album video owner is transferred into gallery as one account-scoped set, preventing a second neighbor player/lease when paging, and every borrowed owner returns to its exact tile. Generation-scoped attachment tokens reject stale cell callbacks after reparent, diffable pruning uses current visible child message IDs, borrowed dismissal/PiP stop returns the same item and playhead, and offscreen owners pause then release. Standalone and grouped media open and close through UIKit-only exact source transitions: the exact bubble/tile is captured synchronously before owner reparent, clipped through every ancestor into explicit window coordinates, rasterized without play/status overlays, and animated into the aspect-fit gallery rect with its corner mask. Dismiss resolves the current selected stable ID afresh; stale/reused/offscreen/deleted/PiP targets fade, generation-safe cleanup cannot mutate a reused cell, and owner return happens only after successful transition completion under the hidden source. Rotation re-centers the same selected message. Timeline, album and prefetch thumbnail paths never use the whole video as fallback. Gallery neighbors remain bounded to central ±1. Native `AVPictureInPictureController(playerLayer:)` is manual, hidden for secret/looping/noncentral/unready/unsupported media, and owned outside cells. A token-scoped movie-playback audio session restores partial failures without deactivating another owner, hands raw controls to external transport, and relinquishes on Media takeover. The singleton transfer coordinator retains active PiP across gallery dismissal, re-presents the exact account/chat/message with the same owner/session, waits for presentation teardown, and restores the exact item without flash. Pending start and stop have bounded generation/timeouts; coordinator authority is retained while AVKit remains active. Permanent deletes arrive on the injected client's private stream, revoke matching chat/message PiP and restoration, while deleted noncurrent neighbors update in place. `./build.sh build` passes without warnings. The SHA-pinned simulator decode probe emits 24 VP9 frames and 96,000 stereo-Opus sample frames with monotonic timestamps, exact post-seek output, codec/SWR tail drain, finite `downloadFile` ranges, zero full downloads, supersession and cancellation. The gallery-owner idb probe additionally proves `ffmpeg-route=true`, exact controller/playhead continuity, preserved offscreen intent, finite ranges, cleanup and the unchanged native MP4 owner path. Existing simulator proofs also cover partial cold playback, local/external controls, range cancellation, loaded ranges, offline retry, exact inline→fullscreen→inline view/item/playhead continuity, zero transfer-cancel delta, terminal lease cancellation, exact clipped/fresh standalone and album-tile geometry, single active tile arbitration, dismissal retention, delete revocation and readiness gating. This simulator reports `pip-supported=false`, so active PiP/background/system-control/restore behavior still requires a PiP-capable device proof. Persistent FFmpeg sessions and sample-buffer PiP transport/lifecycle are simulator-proved; actual system PiP/background/restore remains a physical-device proof gap. Livestreaming is excluded. |
| P0 | Exhaustive message content and actions | pre-Liquid `ChatMessageReplyInfoNode`, `ChatMessageForwardInfoNode`, `ChatMessageSelectionNode`, `ChatMessageSelectionInputPanelNode`, `PeerSelectionController`, contact/map/poll/action nodes, and `ServiceMessageStrings` | all 104 TDLib 1.8.66 `MessageContent` cases; `MessageReplyTo`, `TextQuote`, `MessageForwardInfo`, `ForwardSource`, `getMessageProperties`, `forwardMessages`, `searchChats`, `searchChatsOnServer`, file/poll/edit/copy/reply/delete APIs | **partial — exhaustive catalog + core cards + reply provenance + real Forward/select**: the 104-case no-default catalog drives timeline/chat-list summaries, captions and accessibility. UIKit covers attachments/albums, contact, MapKit location/live expiry, poll/quiz, emoji/dice fallback, service and unsupported rows. Reply/forward metadata preserves chat-scoped IDs, source/origin, inline and ID-zero fallback, thumbnails, PSA, manual quote text/UTF-16 position and unavailable/story state. Manual quote authoring emits a bounded entity-safe `InputTextQuote`; external/story overrides survive text/photo/voice/video/draft paths. Classic reply expands 5→50 lines before navigation, exact destination text highlights after `willDisplay`, and forward taps prefer source message/chat with account-safe cross-chat routing. Context Forward expands the complete album; Select owns stable outer IDs while every action expands, de-duplicates and strictly sorts real child IDs with a 100-message cap. The classic UIKit mode uses full-row taps, a 28pt check at x=6, 42pt incoming-only shift, message-count navigation state, full-width safe-area blur actions and exact per-child TDLib capability refresh. Multi-delete revalidates revoke scope. The full-screen UIKit Forward picker supports Saved/main/archive/server discovery, multiple ordinary chats and multiple explicit topics in the same forum, sender/caption modes, secret-copy rules, per-content/topic permissions, account generations and partial outcome safety. Builds are warning-free; deterministic device proof is recorded below. Remaining P0: recipient comment/forward-draft transition, drag-select/autoscroll, positional null-result support in pinned TDLibKit, link previews/spoilers, resolved service actors/pinned targets, poll voters/media, insertion-aware/slot dice and rich/game/story/checklist UI. |
| P0 | Message reactions | pre-Liquid/current `ReactionButtonListComponent`, `ChatMessageReactionsFooterContentNode`, `ChatMessageBubbleItemNode` and `ChatController` reaction flow | `MessageInteractionInfo`, `MessageReactions`, `getMessageAvailableReactions`, `addMessageReaction`, `removeMessageReaction`, `updateMessageInteractionInfo`, `updateMessageUnreadReactions`, `readAllChatReactions`, `readAllForumTopicReactions` | **implemented ordinary/explicit-topic breadth** — UIKit renders TDLib emoji/custom-emoji reactions as sorted 30pt chips with 20pt icons, exact 6pt wrapping, selected/unread state, compact counts, incoming/outgoing/center alignment, VoiceOver labels/actions and offscreen-paused TGS/WebP/WebM custom emoji. Existing album reactions stay on the representative bubble. Context React can originate the first reaction through a non-Premium standard-emoji picker. Every add re-fetches authoritative message availability, excludes per-item Premium and paid/Stars types, honors unavailability and chat maximum count, while a chosen non-paid reaction remains removable under new restrictions. Generation-safe optimistic state rolls back failures; normal-user interaction/unread plus chat permission/availability updates reconcile under captured account/client guards. Explicit-topic rendering/picker/mutation validates the current `ChatLocation`, and acknowledgement uses `readAllForumTopicReactions`. Deferred polish: custom-emoji add grid, reactor list/recent avatars, disappearing-chip animation and live server mutation smoke. |
| P0 | Pinned messages | pre-Liquid/current `ChatInterfaceStateContextMenus`, `ChatControllerLoadDisplayNode`, `ChatPinnedMessageTitlePanelNode` and message-window navigation | `Message.isPinned`, `MessageProperties.canBePinned`, `getChatPinnedMessage`, `pinChatMessage`, `unpinChatMessage`, `updateMessageIsPinned`, `updateDeleteMessages` | **implemented ordinary-chat newest-pin breadth** — initial and refreshed state comes only from account/client/generation-fenced `getChatPinnedMessage`; only confirmed 404 clears while transient failures retain the last authoritative banner. Permanent non-cache deletes and authoritative unpins clear before refetch, edits/content refresh the preview, and stale mutation/fetch/animation completions are revision-gated. Context Pin/Unpin uses freshly fetched `canBePinned`, one chat-serialized optimistic transaction and exact Saved/private/group/channel notification/scope modes. A classic full-width 50pt UIKit chrome-material banner sits below navigation, shares spoiler-safe reply thumbnail extraction, locally hides by newest message ID, resurfaces for a newer ID, preserves the inverted timeline offset, and taps through existing history-window navigation. Dynamic Type is capped to the fixed panel geometry and VoiceOver exposes separate Open/Hide controls. Forum/view-as-topics/direct-message groups, albums and sending/service messages are explicitly gated. Proof is recorded below. Deferred parity: nearest-visible pin rotation, pinned-only list/pagination, admin undo and older-pin warning detail. |
| P0 | Forum topics: list, explicit writes and all-messages timeline | pre-Liquid/current `ChatListNodeLocation.swift`, `ChatMessageItemImpl.swift`, `ChatMessageDateHeader.swift`, `ChatInterfaceStateInputPanels.swift`, `ChatControllerMediaRecording.swift` and `ChatControllerLoadDisplayNode.swift` | `MessageTopic`, `ForumTopic`, `getForumTopics`, `getForumTopic`, `getChatHistory`, `getForumTopicHistory`, `updateForumTopicInfo`, `sendMessage`, `sendMessageAlbum`, `setChatDraftMessage`, `sendChatAction` | **partial — explicit-topic breadth + production all-messages composer routing** — runtime identity is `(accountID,clientID,chatID,MessageTopic?)`; exact topic list/history/search/update and immutable explicit-topic write context remain. `Chat.viewAsTopics` authoritatively selects topic list (`true`) versus base history (`false`). Base history renders stable adjacent-topic headers, preserves raw pagination/album identity and visible message+pixel anchors, and excludes headers from message-only behavior. Text/photo/edit use discovered General without reply or the replied message's exact topic, reject closed-topic replies, and always store/clear the route draft with `topic:nil`. Voice/video now snapshot that same destination+reply at recording start, persist it separately from the base draft key through preview/relaunch/retry, revalidate live metadata/permissions before enqueue, and route record/upload/cancel actions through the frozen topic. Warning-free build proof is recorded below. |
| P0 | Topic composer durable media identity | pre-Liquid/current `ChatInterfaceState.swift`, `ChatControllerMediaRecording.swift` and thread-scoped interface-state ownership | `MessageTopic`, `InputMessageVoiceNote`, `InputMessageVideoNote`, `updateMessageSendSucceeded/Failed` | **implemented write foundation** — `ChatDraftKey(accountID,chatID,MessageTopic?)` remains the on-disk route/draft owner across voice/video recording, preview, send, retry and outcome reconciliation, while the four version-tolerant manifests persist a separate immutable `sendTopic` for all-messages General/reply routing. Runtime-only TDLib client IDs remain excluded. Stores restore/deduplicate/enqueue/discard by route destination; enqueue and chat actions use the frozen send topic and reply, with live closed/permission checks and account/client fences. Outcome files use draft UUID rather than colliding chat/message IDs. A one-time account-registry migration snapshot may claim unambiguous legacy base drafts; legacy records without `sendTopic` remain valid but cannot be guessed into an all-messages destination. Runtime proof is below. |
| P0 | Forum-aware Forward destinations | pre-Liquid/current `ChatControllerForwardMessages.swift` and `PeerSelectionController.swift` | `getForumTopics`, `getForumTopic`, `forwardMessages(topicId:)` | **implemented breadth** — destination identity is `(chatID, MessageTopic?)`, so ordinary chats and multiple topics in one forum coexist in one selection. Forum rows drill into an exact-cursor UIKit topic picker; closed/hidden topics require creator/manage-topics authority and every content permission is rechecked at delivery. Source account/topic membership is fetched both at preparation and immediately before mutation. TDLib results must have exact count/chat/topic; transient forum metadata failures disable rather than fall through to General. Classic full-width material headers, plain Back and table-header search avoid iOS 26 floating glass. Live idb proof selected a real forum topic locally without pressing Forward. |
| P0 | Composer and send/delete transitions | pre-Liquid chat input panel and message transition paths | `FormattedText`, `InputMessageContent`, `sendMessage`, edit/reply/delete APIs | **partial** — one UIKit floating blur island owns formatted text, emoji insertion, non-Premium installed stickers, saved GIFs, photos/camera, security-scoped multi-file documents, reply/edit and voice/video states in ordinary, explicit-topic and all-messages chats. Sends serialize to prevent duplicate rapid-tap delivery and clear UI only after TDLib acceptance. Real UIKit snapshots of visible reply/text/photo/album/document/voice/video-preview-or-retry sources follow temporary→final IDs and fly into canonical insertion; viewport anchoring remains independent. Sticker/GIF sends use exact permission/topic/reply contexts, captured draft cleanup, account-fenced search, offscreen-paused/cancelled media and no Premium/Stars results. Voice/video retry authority and document upload leases survive UI teardown. Full-bubble deletes fade+slide then collapse under a surviving anchor; no dust/particles. Remaining: public inline-GIF search, custom-emoji authoring and forward comment/draft. |
| P1 | Profiles, shared media, fullscreen gallery | pre-Liquid/current `PeerInfoScreen.swift`, `PeerInfoAvatarListNode.swift`, `PeerInfoPaneContainerNode.swift`, `PeerInfoScreenOpenMessage.swift` and gallery controllers | peer/full-info/status/title/photo updates; `getUserProfilePhotos`, `getBasicGroupFullInfo`, `getSupergroupMembers`, `getChatAdministrators`, `getChatMember`, `getMessageProperties`, topic/history APIs, `downloadFile`, `forwardMessages`, `deleteMessages`, `setName`, `setBio`, `setChatTitle`, `setChatDescription`, `setChatMemberTag`; message/file APIs | **partial — live UIKit profile + shared/avatar galleries + management/actions** — account-fenced user/bot/self/group/channel profile exposes live title/status/bio/usernames/phone/member/photo state and Media/Files/Links/Audio. Separate Members/Admins lists retain server order and roles, paginate raw supergroup offsets, react to membership/full-info changes and preserve a visible-row anchor; permission-gated self/chat Edit uses changed-only sequential writes, live cached visibility and exact pre-write member-rights revalidation. User rows open a standalone tag editor whose fresh self/other-member authority matrix, stale-baseline conflict check and awaited write follow current Telegram behavior without coupling tags to administrator rights. Shared media retains the profile under exact-source append-paged gallery with cancel-safe pan, unified video chrome, scrollable formatted/spoiler-safe captions and authoritative totals. Gallery Open in Chat captures the selected identity, re-fetches it through the captured client, revalidates account/client/topic through fade-dismiss completion, then routes into the source timeline without competing reverse transitions. Save and system Share now share one original-resource export boundary with fresh copy-protection checks, full TDLib download, account/generation fences and managed temp ownership; Photos receives signature-validated still images/GIF/MP4 and WEBP sticker frame PNG without moving TDLib cache files. Forward reuses the production topic/destination/comment picker and offers selected-item versus authoritatively bounded whole-album semantics. Delete intersects fresh per-ID modes, repeats pre-write authority, commits one batch and coalesces all-media permanent updates into one terminal fade without returning deleted playback/PiP owners. Header avatar opens a real-`ChatPhoto` gallery with user/bot/self role-aware raw-offset history, group/channel current full-info photo, exact item+file transition, zoom and no-flash central muted video loop. Generic Saved Messages self now preserves upstream title/blank-status/action semantics while rendering the captured account's real avatar and gallery instead of the Saved glyph. Typed peer/full-info bursts coalesce into one render; generation fences prevent stale `getChat`/full-info resurrection; role signatures reconcile populated avatar galleries without dismissing them. Warning-free proofs are below. Remaining: promote/demote/remove management tools and exhaustive profile actions. |
| P1 | Multiple accounts | Telegram account manager behavior without copying Postbox | separate TDLib clients and databases, authorization state, `logOut` | **partial — existing account breadth, isolation unverified** — add/auth/switch/remove/logout and client/storage paths already exist. Revalidate their production lifecycle and event/subscription ownership; animation A05/A06 and voice A13 expose cross-flow isolation gaps. Do not implement a second account shell from the old queued label. |
| P1 | Chats, folders, archive, search, edit/reorder | pre-Liquid `ChatListItem.swift`, chat list/filter controllers | chat lists/positions/folders, pin/mute/read/delete/clear/draft APIs | **partial** — main/archive/custom-folder lists and paging already exist; folder tabs are classic full-width material, and chat cells now use contiguous Telegram geometry with date, delivery, unread/mute/pin state and account-backed actions. Remaining: edit/reorder/include/exclude completeness, clear history/draft parity, archive reveal gestures, richer delivery/typing states and mutation account fencing. |
| P1 | Timeline stability and performance | pre-Liquid/current `ChatMessageItemImpl.swift` and `ChatMessageDateHeader.swift` history/header behavior | `getChatHistory`, `updateNewMessage`, `updateDeleteMessages`, file updates | **partial** — stable message/album/topic/date IDs, raw-history pagination cursor, cross-page album merging, message-only prefetch/read/selection and visible `messageId + pixelOffset` restoration cover structural snapshots. Composer/keyboard insets, object-driven and autonomous cell self-sizing, bulk reconfigure, Dynamic Type and rotation now capture the same anchor or latest edge; mutation depth discards stale deferred anchors and never fights active dragging. Every chat emits one stable localized date row per day with exact date→topic ordering. Remaining proof/gaps: a live pagination/album seam, software-keyboard-attached runtime proof and eliminating residual metadata work from the main actor. |
| P2 | Classic shell/navigation polish | pre-Liquid navigation/tab bars, `ChatListFilterTabContainerNode.swift` and `ChatListItem.swift` | n/a | **implemented classic shell/list breadth** — the bottom folder bar is one edge-to-edge `systemChromeMaterial` surface through the safe area; its scrollable tabs use the pre-Liquid three-point selected line instead of an inset lens/capsule. Context menus use ordinary `systemMaterial` blur and classic corners. Chat-list cards are replaced by contiguous 76pt full-width rows with 60pt avatars at x=10 and separators from x=80. Source search finds no `UIGlassEffect`, `glassEffect` or `cornerConfiguration`. Warning-free build and real-state idb proofs are below. Remaining P2: systematic audit of secondary navigation/search/action surfaces. |

### Checkpoint

- Latest code `cb84f9b` closes bounded caption-entity enrichment after request owner `559a762` and explicit preview `805494f`.
  Exact reviews, warning-free builds and all seven fresh native probes pass at PID91301. Primary/worker code is committed;
  no new account/server/notification mutation or Simulator shutdown. Goal remains active.
  Next: A53b2 per-account versioned media evidence/CAS store, ordered off-main invalidation and verified cache-only restore,
  using the reviewed design gate above. Never reenable raw JPEG fallback; retain the declared pre-ack/post-session limits.
- Final checkpoint build `191636-93639-26315`: PASS4s, complete1385-line log zero warnings/errors. Prohibited production/
  dependency markers and NSE raw media cache-call scans are empty; AGENTS/CLAUDE match. Worker is clean; this ledger is the
  only final agent-authored change and is committed separately. Goal remains active with the A53b2 cursor above.
- A53b1 `805494f` has exact independent review, warning-free integration and all seven native reports PASS at PID87313.
  Next bounded A53b1a protects caption-entity spoilers; then required A53b2 restores verified cache-only media. Neither actual
  APNs delivery nor future/durable edits are proved by the policy fixtures. Previous checkpoint bullets below are historical.
- Latest notification request slice `559a762`: independent exact review, warning-free build `183542-38148-13783` and all six
  native probes at PID40035 pass with the limits recorded above. A52a/b1/b2 are bounded fixes, not real APNs delivery proof.
  Next is A53b1 denial/legacy-read cutoff, followed immediately by required A53b2 verified cache-only preview restoration.
  Goal remains active; Simulator/account state is preserved. Prior checkpoint bullets below are historical.
- Latest A51a `38b7d06` plus A51b `6b187b0` pass combined cache/worker native probes PID46367 and warning-free integration
  build `172737-45171-21885`. Viewport regression passes PID49173, but its idle-only sample is not a performance comparison.
  Next: A53 notification media concealment, then A52 and actual queued ChatView proof. The A51 section records remaining
  strict-handoff/photo-removal/registration/media limits; do not reimplement these completed bounded slices.
  Final checkpoint build `173407-60281-18514` passes without warnings; account stores and Simulator lifetime are preserved.
- Active continuous work resumed explicitly after `8268947`; no further resume is required. A01/A02/A03/A07 have bounded
  warning-free build/probe proof; `909215a` repairs A11 with production navigation/relaunch/Delete proof. A13 `c356513` has
  accepted-event transport proof; A04 through `ef8f4ba` has native and Simulator decoder/controller proof. A12 `847b838` and
  A18 `76f9998` have combined isolated store/stream proofs. A14 `bb01b8f` and A19 `d8ed16e` have integrated bounded probes.
  A24 `b18da97` has integrated edit-policy proof; A26 `8519b33`/`5a87726` has store and own voice reinstall/discard proof.
  A29 `15f146f` has isolated mutation-authority proof and read-only cold-launch folder/editor navigation smoke.
  A27 `b0db39f` has integrated effective-permission/authorization proof.
  A30a `0820359`/`c5d3f8b` has production same-PID root-list/search restoration proof; A17 `e8a0eb1` has native finish-owner proof.
  A30b1 `ef558ec` has isolated one-shot transfer proof; A16 `a72d93b` has actual recorder/store handoff proof.
  A28 `9cdc6b0` has pagination registration proof; real delayed profile RPC remains unverified.
  A31 `b7de6ee` has poll-attempt/deadline ownership proof; no server votes or delayed live RPC proof.
  A15a navigation joins pass through `d34eeb3`; A30b2 history/import helpers `6aa7ce4` and Root A23a `e1d295e` pass bounded probes.
  A05a/b and A15b1 have bounded source/transport/native proofs; shared production history revisions pass at `da59789`.
  A06 shared animated demand has bounded transport proof at `09fa140`; static-image origin/demand passes at `7426478`/`b3aa790`.
  A15b2 voice lifecycle passes at `fe5de21`.
  Quiescent Chat A30b2 is active at `494bf56`/`9495f0a` with bounded actual-chat smoke. Secondary routes, remaining A23,
  A25 bounded semantic repair passes through `fb15c25`; live-input coverage and other queued findings remain open.
  A08/A10 native/UIKit probes now pass through `10b23c5`.
  Broad parity is not complete.
  B01 still blocks the original Simulator database; the separate audit Simulator is now logged in and usable without data reset.
- Latest verified implementation includes A04 partial-file buffering `8be1c9a`, A44a ordinary receipts `1630ee1` and native
  geometry proof `909f62b`; actual four Read bubbles retain exact frames through a client foreground epoch (PID62893).
  Explicit forum A44b1 `5b9b322` has native PID86336 and actual topic display/foreground PID90037 proof above.
  A45a/b/c through `0a4c6af` have bounded native and actual search proofs above; documentation checkpoint `835d4bd` is clean.
  A44b2a/b `4a2a190`/`2190c4d` pass production-reader/MessageCell regressions PID22721/PID34441. Runtime availability PID5126
  found nine loaded forums and zero safe base-mode candidates; no route or account preference was changed.
  Latest implementation build `build-Debug-20261003-064029-33247-16763.log` PASS14s; complete log zero warnings/errors.
  AGENTS/CLAUDE match; production/dependency scan still has zero VLC, forbidden UI and imported Telegram-infrastructure markers.
  A30d active-search renewal through `501af59`, native proof through `37e08e8`
  (PID27782 PASS) and actual two-epoch search/clear smoke (PID1590). A43 receipt feed has three native root regressions PASS,
  PID `24065`.
  Its baseline `d8e2bb0` includes A30g `55ff037`/`f9b5dad`, visible Retry `e049da3` and A42 `59f187b`.
  Native Members/Profile regressions pass (PID `99916`); actual `f9b5dad` Members survives two ownership epochs and Admins one,
  with stable small-list geometry and Back→Profile. Actual active search now continues after foreground without Cancel;
  first focused and second keyboard-hidden epochs pass. A30g large-list/permission/editor limits remain.
  Earlier `72d74b0` includes A39 `6a29431`/`982245f`, A40 `eff2876` warning visibility and A41 static-cleanup dependency order.
  Actual PID `30616` passes cold/loaded/foreground target settlement with stable visible cells and retained scrolled Files anchor;
  expanded native viewport probe passes. A39's measured defect is repaired; live quote/album/rotation interruption remains unverified.
  Earlier actual PID `8251` identifies automatic anchor compensation interrupting explicit animation.
  Viewport/profile-restoration native probes at `17e3fb4` pass (PID `95662`) but did not cover this sequence.
  `b630844` completes A38/profile-restoration native checks (PID `39878`); production
  `97ccea8` also passes media/PiP/gallery regressions and actual scrolled profile foreground (PID `32182`).
  `04c904a` corrected focused prompt baseline passes24 samples (PID `4253`), without a production fix.
  `0608d15` modal presentation fixture correction passes combined probes (PID `97142`).
  `f70cd58` child membership has native proof (PID `88865`); combined-probe modal timing is separately tracked. `c68c1c2` profile route/tab/Search smoke passes
  (PID `68772`); introduced A38 stale-media admission is repaired by `97ccea8`. A36 presentation native/actual proof passes.
  `c9254f3` A36 presentation has a warning-free integration build. `9c0816b` A30f2
  prerequisites have native proof (PID `56662`), not activation proof. A37 repeat settled screenshots are clean; cause remains open.
  `1b89dbd` Done native/actual-selector proof passes (PID `29718`); A30f1 `1e072ca` actual editor
  foreground/typing/discard/reopen and four native regressions pass (PID `9957`), with separate layout finding A37.
  `b923f19` includes A30e `850ccf8`; folder-flow and four regression probes pass (PID `80658`).
  `f45869b` includes A21d `fd98d02`; native secret-hold/capture-trait regression passes (PID `58077`).
  `3290ba4` includes A34 `4185849` and A35 `67c9470`; combined seven-probe regression passes (PID `44216`).
  `3983b48`: native nil-Back policy probe and actual Profile/Edit/Back smoke pass (PID `20378`);
  explicit Save remains plain, Back remains circular. `1cd9ecf`: pending membership and Root/scoped/Forum/navigation helper regressions pass (PID `94658`).
  `941a90a` fixes explicit Save chrome but leaves native Back open; `3a7ac85` gives actual public-state diagnostics. The ineffective
  timing trial `839c26e` is removed after PID `96492` repeats the same visible Back background.
  `b3aa790`: static-image/shared-demand/profile-grid/scoped-delivery probes pass (PID `70966`), native
  timed video-note regression passes (PID `53678`). Actual own-profile/avatar/grid/header smoke passes at `7426478` (PID `69030`).
  `a264c4e` preserves desktop focus during wrapper runs. `01a2d84` plus the committed forum smoke helper: actual quiescent topic-list foreground replacement passes
  (PID `54903`); forum/navigation/Root/scoped-update probes pass at `01a2d84` (PID `49689`).
  `b97fa9b`: actual own-profile header widths/full title/avatar and media concealment regression pass (PID `20471`).
  `4c3fc5e`: timed video-note native hold probe passes (PID `12358`, production `437d7c7` plus that probe fix);
  profile/media/text/navigation regressions pass (PID `13038`), native animation and gallery-owner pass separately (`15898`/`16179`).
  `bdd19cd`: profile/media concealment, text-spoiler and navigation probes pass (PID `473`);
  own-profile navigation and populated grid load pass without opening media. `bb36bc7`: Archive same-PID search/foreground
  replacement smoke and navigation/Root/auth regressions pass (PID `52323`).
  `05c2b49`: media-reveal/text-spoiler/viewport probes pass (PID `39784`); native animation/transition,
  gallery-owner and PiP-context regressions pass in separate launches (PIDs `40544`/`40966`/`42082`).
  `097b488` with assertion-only `d7e9974`: auth, Root/Chat source, viewport and composer probes pass (PID `31259`);
  authenticated cold-launch root and Home→foreground smoke pass.
  `6869382`: viewport policy, Chat state and composer regressions pass (PID `2570`); ordinary Saved scroll/latest smoke passes.
  `26d5f48`: marked-input model feedback and actual UIKit undo/redo pass (PID `94652`), with restoration/spoiler regressions.
  `fb15c25`: semantic composer, edit/restoration, text-spoiler and scoped-update regressions pass (PID `92214`).
  Static-image observer/source regression passes at `ba0e192` (PID `89171`).
  `e9b536b`: native inline animation, gallery-owner and PiP-context regressions pass (PIDs `83851`/`84406`/`84924`).
  A23 forum-topic scoped delivery plus Root/Chat-state/spoiler regressions pass at `78f0f8a` (PID `81496`).
  A08 native timing, A10 UIKit spoilers and A07 worker regression pass at `10b23c5` (PIDs `75703`/`78753`).
  A06 demand/source and voice-preservation regression pass on combined `2bf7428`. Earlier Chat/composer and voice lifecycle/finalization
  proofs remain at `9495f0a` (PID `71481`), including actual Chat modal/background/Done; Root/poll at `da59789`, Main at `df9eb7a`.
  Latest full-log-verified warning-free signed integration builds: `.build/logs/xcodebuild/build-Debug-20261003-030933-90779-22519.log`
  and `025548-60862-15401`; A42 final `025014-56598-7723` also passes. Earlier signed `015810-30055-29778`/`015646-29545-22064`
  and unsigned `015734-29820-5419` pass. A40 records the rejected nonclean `014324` claim.
  Earlier integration builds: `.build/logs/xcodebuild/build-Debug-20261003-011303-7581-26376.log`,
  `build-Debug-20261003-005819-95305-8829.log`,
  `build-Debug-20261003-005409-91096-31077.log`, `build-Debug-20261003-003813-36345-3545.log`,
  `build-Debug-20261003-002923-30429-24207.log`, `build-Debug-20261002-232705-14634-13985.log`,
  `build-Debug-20261002-232350-7050-2496.log`, `build-Debug-20261002-231025-79060-7092.log`,
  `build-Debug-20261002-230359-64579-5399.log`, `build-Debug-20261002-225546-56715-10303.log`,
  `build-Debug-20261002-224502-40819-31807.log` and
  `build-Debug-20261002-223928-27434-8714.log`.
  Production/dependency scan over `project.yml`, `BetterTG`,
  `BetterTGNotificationService` and `Packages` has no VLC, SwiftUI/hosting/representable or Liquid Glass markers.
  The prompt/document delta received an independent read-only review. Neither clean build nor this marker scan closes the audit.
- The protected auxiliary `astra-animation-worker/BetterTG` worktree produced integrated A04/A18/A19/A26/A30a/A30b1/terminal plans;
  A30b2 controller/history, A23b Chat fences, A10/A25, A23e auth and A21c timed video-note authority are integrated.
  Static-image origin/shared-demand `73bcb04` is integrated as `7426478`, with reviewed fixture correction `b3aa790` and runtime proof.
  A23g pending membership is integrated as `1cd9ecf` with actual-helper proof. A34 accepted-update projection/refresh retirement
  is integrated as `4185849`/`3290ba4`; A30e folder-flow authority is integrated as `850ccf8`/`b923f19` with native/runtime proof.
  A36 presentation is integrated as `c9254f3`; focused prompt baseline as `d34d012`. A38 `4116257`/`054caab` is integrated
  as `97ccea8`/`b630844`, with bounded native/actual proof above. A39 `4fc6d02`/`f6899a0` is integrated as `1b1429f`/`17e3fb4`;
  diagnostics `805a07b` is integrated as `8b8d149`, settlement `1af25c6` as `6a29431`, convergence `9eee50d` as `982245f`.
  Their bounded native/actual proof is above. A30g `0c2e1a2`/`50a299a`/`6b5a29d` is integrated as
  `55ff037`/`f9b5dad`/`e049da3`, with native/actual proof above. A30d `5c65406`/`465cf12`/`a75f667`/`8a08600`
  are integrated as `f551b40`/`1f959bb`/`cc6ad7e`/`501af59`; probe corrections `f8e40b1`/`655698c`/`7097a76` as
  `e5979fd`/`c9e2169`/`37e08e8`. Bounded native/actual proof passes. A44a `52d7e33` is integrated as `1630ee1`;
  primary DEBUG correction `909f62b` is imported in worker as `2f5b9fe` (do not duplicate-pick).
  A44b1 `caf406d` is integrated as `5b9b322`; A45a `af3a8bb` is integrated as `e3fb6d9` with bounded native proof.
  A45b `9ec934a`/`c84cb18` are integrated as `597d6f3`/`c9317e5`; A45c `656e32c` as `0a4c6af`, native regressions pass.
  A44b2a `0942d9c` as `4a2a190`, b2b `76f6f73` as `2190c4d`: native reader/MessageCell regressions pass.
  Reviewer is checking remaining concrete P1 renewal work before P2 pin ordering; implementation worker is clean.
  A46 pinned ordering is separate.
  Native before/after fixtures and logs were preserved in `.build/ui-probe-evidence/astra-a04-*`.
  `astra-outcome-source/BetterTG` produced integrated A13/A12/A14/A24/A29/A27/A17/A16/A15a/A15b1/A15b2/A08/A09/A20a;
  A20b profile-grid concealment and A30d ForumTopics recovery are integrated. A32 explicit-button policy is integrated; native Back
  still ignores the configured flag in runtime proof. Ineffective generated Back is removed by `3983b48` after independent
  source review; A23g/A34 independent review found no further introduced blocker. A35 is integrated as `67c9470`.
  A21d secret-note recording/mirroring admission is integrated as `fd98d02`/`f45869b`; photo and immediate/view-once remain denied.
  Profile-editor repair is integrated as `1e072ca`. A30f2 prerequisite is integrated as `9c0816b`; activation `35adb4d`
  is integrated as `c68c1c2` with bounded route proof and introduced A38 finding. Child membership is integrated as `f70cd58`.
  Focused-prompt measurement correction is integrated as `04c904a` with native proof. This worker independently reviewed A38
  and its DEBUG settlement correction, then source-confirmed A39; it has no uncommitted implementation delta.
  Parent owns idb; Simulators remain booted.
  Do not force-delete protected worktrees. Historical A07 worker proofs remain in the primary checkout.
- Initial documentation-only validation at `6b417da`: `./build.sh build` passed without warnings on Xcode 26.6; log
  `.build/logs/xcodebuild/build-Debug-20261002-141016-42207-16861.log`. The missing ignored `Secret.swift` was restored from the
  main checkout for the build and is excluded from the commit. Documentation-only peer review passed; no Swift source edits or
  new runtime smoke were performed. This build does not close any implementation-audit row.
- Exact next slice: P1 A49c2 coherent provider/serialized applies across all five producers; A49c1 `d8512b5` immutable value
  prerequisite has native proof. Preserve A50 `487c0de` all-row mode exit and A49b `eeb93b2`/`9961aba` action/touch authority.
  A49a `ca71e33` with oracle `0404996` has bounded native/ordinary UI proof; earlier test failures and their measured cause remain above.
  A22 `41f87a5` has real unchanged-snapshot control/ended-delegate-drag proof; actual prepend/keyboard/media-resize remains open.
  Keep the initial A39 helper failure and passing standalone retry as separate observations; cause remains unresolved.
  A46b `e2dd664` and A32 placement `1ef0935` have bounded native/actual proof above; native chrome remains partial.
  A48 `fe9424c`/`727103c` has bounded native/regression proof above.
  A46a `34b7868` has bounded native/actual-list/foreground proof above. Preserve raw pagination, exact query/source ownership,
  A45 arbitration and A47's native read bound; never infer configured pin positions from timestamps or topic IDs.
  A47 `09db3f5` and A30h `c895a8c` have bounded native/regression proofs above; their live/runtime limitations remain.
  A44b2b now derives exact raw-topic receipts with the existing shared reads. Preserve A44a/b1/b2 states and A45 no-echo behavior,
  source/UUID/revision lifetime, wrapper identity and timeline anchors. A46 live multi-pin/reorder behavior remains unverified.
  A45a/b/c have bounded real-VM/native-cell proof above. A44a/A44b1 have bounded native/actual proofs above;
  A44b2 has controlled/native proof, live all-messages data remains unavailable; final self/broadcast checks conservatively absent.
  A30d active-search renewal now passes exact-task native and actual two-epoch focused/keyboard-hidden query/clear checks;
  live pagination/metadata failure and overlapping dismissal+pop remain separate limits.
  A30g bounded recovery is verified; larger member lists, server permission changes and live tag-editor/Save renewal stay open.
  A43 list receipt feed is fixed in `596e895`; A44a repairs ordinary bubbles separately. Keep topic/self/broadcast contracts above.
  A39 mid-flight takeover and estimated-height convergence now pass bounded cold/loaded/foreground target checks at `72d74b0`;
  live quote/album/rotation/user-interruption coverage and sequential metadata waits remain separate limits.
  A38 admission/native/actual scrolled restoration proof passes; no live delayed delete/spoiler or active PiP claim.
  A30f1 editor state/authority proof passes; full gallery/member-editor restoration remains separate.
  A36 child-publisher and actual deleted-title proofs pass; modal fixture correction passes combined probes. A37 complete
  focused baseline and actual delayed settled geometry are clean; retain the original intermittent failure and avoid speculative rewrite.
  Retain A32 native Back/search capsule styling and extended runtime matrix;
  retain A22's controlled layout/interaction runtime gaps after the bounded authority repair.
  Retain static-image live transport/account-switch proof limits and Chat's untested nonempty composer/import/keyboard cases.
  Telegram's chat-level background path stops into preview; Legacy also has a separate dismiss observer. Their ordering and durable
  process-death preservation are not established by static source. Preserve the bounded A15a proof and its failed initial fixture evidence.
  The full A30 transaction
  spans too many ownership boundaries for one bounded slice. Continue A05–A10/A15 and A20–A23/A25/A32.
  Own A26 draft recovery/reinstall/discard is complete; keep its backups, do not restore it again.
  A12 crash before registration retains unresolved ownership; do not guess an outcome. A04 cold partial-file native playback/seek
  now passes with explicit incomplete coverage; retain live-server, large-file A/V and lookahead-estimate limits above.
  B01 needs a data-preserving TDLib investigation. Continue owner/PiP, complete MessageContent/actions, composer/timeline,
  profile/gallery and account/list/shell audit
  coverage. Retain completed range/renderer checks; do not restart source review unless code/dependencies change.
  New feature breadth remains behind the audit gate.
- Last pre-audit feature slice: `7b0699d` member/admin user rows open a standalone UIKit member-tag flow with fresh
  actor/target authority, exact baseline conflict detection, awaited `setChatMemberTag`, account fences and post-success list reload.
- Timeline invariants to revalidate: raw TDLib pagination owns the cursor; `mediaAlbumId` owns grouped identity across pages; heterogeneous
  message/date/topic items rebuild from canonical state; only messages participate in behavior; every structural apply restores a visible
  message + exact pixel offset. Date→topic ordering and significant-time/locale reconfiguration follow Telegram's header spaces.
- Historical verification: warning-free Xcode 26.6 build `.build/logs/xcodebuild/build-Debug-20260831-153759-82885-28094.log`; focused
  Telegram/API and post-reload-fix delta reviews reported CLEAN. PID `83599` completed the non-mutating member-tag smoke; Simulator
  was left booted. These results are not a fresh whole-implementation audit.
- Historical proof blockers to reassess: the reachable account lacked member-tag authority; the denial path was runtime-proved,
  authorized editing/writes were source-reviewed/build-proved only. No safe reachable forum had `viewAsTopics == false`, the software
  keyboard stayed hidden after first-responder taps, and idb omitted context-menu actions. Active PiP and camera capture need capable
  hardware. Record current availability and continue independent checks without upgrading blocked proof to passed.
- Deferred feature candidate after the audit: promote/demote/remove member-management tools. Keep rights mutations independent of
  member tags; confirmed higher-priority audit findings take precedence.

### Historical implementation slices

#### UIKit peer profile and shared-media slice

- **P1 flow:** pre-Liquid/current peer-info header, pane and open-message behavior from `PeerInfoScreen.swift`,
  `PeerInfoHeaderNode.swift`, `PeerInfoPaneContainerNode.swift` and `PeerInfoScreenOpenMessage.swift`, adapted to UIKit + Combine +
  TDLibKit without Telegram infrastructure.
- Implemented: chat title/avatar entry; user/bot/self/basic-group/supergroup/channel identity; full-info bio/description,
  username/phone/member details; Message/Search actions; one scrollable Dynamic Type header; Media/Files/Links/Audio tabs; exact current
  `MessageTopic` query scope and open-in-chat route; stable deduplicated pagination; empty and later-page retry without losing the cursor;
  account/client fencing; cancellable grid thumbnail download with redisplay restart; accessibility labels and intrinsic action height.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-105649-495-22414.log`; focused source/delta review clean. Runtime PID
  `840` exposes Profile/Back, exactly one `4 members`, 56.67pt intrinsic Message/Search actions, the four-tab group, 12 visible Media
  tiles, `No shared files`, real Link rows and a real `.m4a` Audio row. The exact Media→Files→Links→Audio path remains alive after fixing
  UIKit diffable snapshot reentrancy, and Back returns to the group chat. Evidence is under
  `.build/ui-probe-evidence/profile-shared-media-*`; no media or server mutation was selected.
- Deferred at this slice (see subsequent profile/gallery slices): avatar/video header history and fullscreen entry; edit/member/admin
  controls; shared-media selection/actions; live metadata reconciliation; gallery caption, gesture, rotation and complete
  save/forward/delete/open-in-chat/video-control parity.

#### Profile shared-media gallery slice

- **P1 flow:** peer-info media pane → production gallery from current/pre-Liquid `PeerInfoPaneContainerNode.swift` and
  `PeerInfoScreenOpenMessage.swift`, retaining the `ChatLocation` history source and a fresh visible transition provider.
- Implemented: Media-only gallery routing while Files/Links/Audio keep open-in-chat; exact thumbnail snapshot without the video badge;
  represented-ID + visible-cell + account validation; profile retained beneath the modal; newest→oldest selected-ID-stable append-only
  pages; one in-flight mutation queue; boundary retry; no reload jump; active-account fencing before cell/VOD/PiP creation; release and
  fade on account switch; active-client permanent photo/video delete reconciliation; selected-delete forced fade. The footer is one
  full-width `systemChromeMaterialDark` surface through the bottom safe area with plain 52×50 Close/Share and a nontruncating index.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-111604-5080-25531.log`; final source/delta review CLEAN. PID `5495`
  opened the first profile tile as `1 of 30`, paged to the exact full `2 of 30`, then Close returned to Profile with the original
  131×131 source tile still present. AX proves `gallery-close`, `gallery-counter`, `gallery-share` on the full-width footer; screenshot
  `.build/ui-probe-evidence/profile-gallery-authoritative-classic-footer.png`. No Share or server mutation was performed.
- Deferred: avatar/photo-video header history, interactive pan-dismiss, captions, save/forward/delete/open-in-chat,
  rotation/current-item runtime proof, and deliberate near-page-boundary/error/account-switch/delete smoke.

#### Unified fullscreen gallery chrome slice

- **P1/P2 flow:** current/pre-Liquid gallery single-tap chrome and video-control coordination, adapted to UIKit recognizers without
  importing Telegram transition/gesture infrastructure.
- Implemented: controller-owned `chromeIsVisible`; edge-to-edge pager behind a full-width safe-area blur overlay; photo single tap
  dynamically waits for nested double-tap zoom; controls/retry/seek touches are excluded; selected video disables its private tap and
  reports controls visibility/auto-hide through its playback owner to the same footer/status state; page/reuse/dismiss/PiP bindings are
  explicit. VoiceOver can never leave Close/Share hidden, hidden footer leaves AX, Reduce Motion is honored, and accessibility Escape
  closes. Video controls stay exactly above the 50pt footer plus bottom safe area instead of being obscured by the overlay.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-113041-8640-9218.log`; final delta review CLEAN. PID `8944` proved
  photo chrome `visible→hidden→visible` (`402×874` media when hidden), video single-tap exposing seek/back/play/forward/mute/rate plus
  `gallery-close`/`2 of 30`/`gallery-share`, playing auto-hide removing both control groups from AX, and Close returning to Profile.
  Screenshot: `.build/ui-probe-evidence/profile-gallery-unified-video-controls.png`; no Share or server mutation occurred.
- Deferred: deliberate double-tap/pinch and VoiceOver-status runtime toggles.

#### Guarded interactive gallery dismissal slice

- **P1 flow:** Telegram current/pre-Liquid down-swipe gallery dismissal, adapted to the existing exact-source UIKit animator through
  `UIPercentDrivenInteractiveTransition` without importing Telegram gesture/transition infrastructure.
- Implemented: one-finger, positive-y, 1.2× direction lock; exact centered-page requirement; minimum photo zoom with no zoom bounce or
  deceleration; horizontal pager cooperation; temporary pan/pinch suspension only after begin; touch exclusion for footer, every
  `UIControl`, visible video controls and Retry; active seek/PiP/start/stop/retention rejection. Progress is translation-driven; 28% or
  900pt/s finishes, otherwise cancel restores chrome, modal AX isolation, pager/zoom gestures and pending page/delete updates. Playback
  owners release only from the animator's completed commit. Account switch force-finishes the interaction and pops the profile from the
  transition completion; an unexpected cancel uses a terminal nonanimated fallback instead of leaving an invalid gallery visible.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-114920-12706-5954.log`; final delta review CLEAN. PID `12991` proved a
  slow 70pt/1s down-pan cancels with only gallery AX and restored `gallery-close`/`1 of 30`/`gallery-share`; a 450pt/0.4s down-pan finishes
  at Profile with the exact 131×131 source tile; horizontal swipe still reaches `2 of 30`; up-swipe remains in gallery. No Share or
  server mutation occurred; Simulator remains booted.
- Deferred: deliberate zoomed-photo, live seek, active PiP and external account-switch gesture rejection on capable/runtime states.

#### Fullscreen gallery caption and total-count slice

- **P1 flow:** current/pre-Liquid gallery caption footer, spoiler/entity interaction and absolute position index, adapted to UIKit TextKit
  and the existing TDLib message stream.
- Implemented: formatted photo/video/animation captions; validated UTF-16 entities; scaled bold/italic/code runs refreshed on content-size
  changes; 44…220pt scroll container (96pt compact cap) rather than truncation; scroll position per selected message; caption-scroll hold
  that keeps unified chrome/video controls visible until return to top. Dynamic caption height raises the 136pt video controls above
  `50 + captionHeight`. Spoilers are opaque before reveal, redacted from AX, reveal by hit-test or AX action, then publish non-hidden
  URL/email/phone/mention AX actions. Concealed `textUrl` destinations compare normalized scheme/host/default-port/path/query/fragment
  and require an explicit URL confirmation when they differ. Profile listens to active-account content/edit updates, generation-serializes
  `getMessage`, preserves topic scope, and reconfigures same-ID captions. Profile search passes TDLib `totalCount`; loaded-page appends and
  deletes update messages before re-clamping that total.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-121611-18495-8647.log`; final source/delta review CLEAN. PID `18804`
  exposes a real `Caption, …` label at 378×28 and `1 of 88`; captioned video proof shows scrub/transport entirely above
  its caption, with footer below. Screenshots: `.build/ui-probe-evidence/profile-gallery-caption-entities-final.png` and
  `.build/ui-probe-evidence/profile-gallery-caption-video-controls.png`. No entity URL, Share or server mutation was activated.
- Runtime blockers: reachable sampled captions contain no spoiler or concealed `textUrl`, and no long caption was safely selected, so
  reveal/confirmation/scroll-hold are source-reviewed and build-proved but not deliberately exercised on account data.

#### Real profile avatar gallery slice

- **P1 flow:** current/pre-Liquid `PeerInfoAvatarListNode` → `AvatarGalleryController`, adapted to UIKit and native TDLibKit models rather
  than synthetic timeline messages.
- Implemented: header 96pt image/button AX only when a real effective/full photo exists; a true placeholder remains image-only. User/bot
  payload preserves effective/personal/normal/history/trailing-public roles with stable `ChatPhoto.id` dedupe, keeps raw history offset
  independent of extra role entries, inserts later 100-photo pages before public fallback and exposes footer Retry. Group/channel use the
  only available TDLib source, `BasicGroupFullInfo.photo` / `SupergroupFullInfo.photo`; `ChatPhotoInfo.big` is a static fallback only and
  never fabricates an animation. A separate UIKit pager keeps stable photo IDs/current page through rotation, exact-animates the whole
  circular header only for the current item and fades historical items. Captured-client synchronous JPEG/MP4 requests have per-file
  generations and no global update bus; 96MB/cost-limited decoded cache; static image remains until `AVPlayerLayer` ready; animation seeks
  to `mainFrameTimestamp`, loops muted only central, pauses/resets offscreen; nested pan activates only above 1× while pinch/double-tap
  remains available. Late network completions require current account, visible/top profile and no competing presentation.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-124706-24968-7861.log`; final source/delta review CLEAN. Runtime PID
  `24630` exposes `<group> profile photo` as 96×96 button, opens real `Profile photo, Mar 19, 2026` in the modal pager with plain
  `avatar-gallery-close`, then restores the exact 96×96 source. Screenshot:
  `.build/ui-probe-evidence/profile-avatar-gallery-final.png`; no mutation occurred.
- Blockers/deferred: current safe group has one static photo, so user >100 pagination, animated avatar loop and zoom gestures are not
  runtime-proved. TDLib cancellation is global per client/file; without a cross-consumer lease coordinator, offscreen deliberately
  cancels only local await/decode/playback work and lets active transport finish into TDLib cache rather than cancel another consumer.

#### Generic self avatar source slice

- **P1 flow:** Telegram current/pre-Liquid generic self info opened from Saved Messages, explicitly distinct from Settings/My Profile.
- Implemented: self is captured once only when a non-nil account user ID equals the peer. Generic self title remains `Saved Messages`,
  presence is blank, redundant Message is hidden, and Search/Edit remain. `ProfileAvatarView` can render the real self peer file over the
  Saved glyph only for this captured profile context. The explicit image path owns account/client/user identity, waits for the full file
  through that client, uses no global `updateFile` bus, never cancels shared TDLib transport, and suppresses every callback after switch.
- Header source follows effective `User.profilePhoto` then main `UserFullInfo.photo`; self `personalPhoto` is ignored and `publicPhoto`
  never becomes current. Gallery ordering is effective current → distinct normal/history → distinct public last. Raw history offsets stay
  server-owned, extra-role count is separate, and pages insert before public without moving the selected item. Transition to/from the
  header requires both exact photo ID and rendered file ID; otherwise it fades. Main/personal/public role signatures trigger a full-page
  reconcile that preserves a historical selection; reconciliation, pagination and initial open have independent UUID-owned task slots.
  An authoritative empty set closes/resets the pager instead of preserving stale media.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-152230-76740-9666.log`; final upstream/API/task-race review CLEAN.
  PID `74705` exposed the real cat avatar as a 96×96 `Saved Messages profile photo` button, exact `Saved Messages` title, no status and no
  Message action; Search/Edit and shared tabs remained. It opened real `Profile photo, May 10, 2023` with `avatar-gallery-close` and no
  mutation. Final build PID `77080` launched on the still-booted Simulator. Evidence:
  `.build/ui-probe-evidence/profile-self-avatar-source.png` and
  `.build/ui-probe-evidence/profile-self-avatar-gallery.png`.
- Runtime blocker/deferred: this account exposes one current profile-photo item, so >100 pagination, distinct public fallback, live role
  replacement, authoritative empty close and concurrent request invalidation are source-reviewed/build-proved rather than live-mutated.

#### Live profile metadata slice

- **P1 flow:** Telegram current/pre-Liquid signal-driven peer info data, adapted to BetterTG's active-client typed update bus and UIKit
  state rather than one-shot controller snapshots.
- Implemented: exact account/client and peer-ID guards for chat title/photo, user/status, basic group, supergroup and all three full-info
  updates. User/group payloads replace `CustomChat.type` immediately; title/status/usernames/phone/member noun/count update before any
  network round trip. Full-info payloads directly update bio/description/details/full `ChatPhoto`. Title/photo refetches use one monotonic
  `metadataGeneration`; full-info requests and pushed payloads share `fullInfoGeneration`; cancelled/older responses cannot overwrite a
  newer revision. First full-info hydration does not cancel a legitimate simultaneous avatar open, while later `ChatPhoto.id` changes
  increment avatar identity, cancel initial/history tasks, clear raw offset/dedupe/total, close stale avatar gallery and remove old
  animation authority. One run-loop-coalesced render updates title/status color/bio/details/avatar/placeholder/AX traits+hint/tap
  availability and Dynamic Type header height together.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-130032-28652-16080.log`; final source/delta review CLEAN. PID `29034`
  exposes the stable 96×96 `<group> profile photo`, title, `4 members`, actions, tabs and media after live subscriptions attach.
- Runtime blocker: no deliberate server title/photo/status/full-info mutation was performed on the safe account; update transitions are
  source-reviewed and build-proved, while the runtime smoke is a no-regression readback.

#### Profile member, administrator and edit controls slice

- **P1 flow:** current/pre-Liquid peer-info member/admin panes and creator/administrator edit gates, adapted to UIKit diffable tables and
  TDLibKit without Telegram account or list infrastructure.
- Implemented: a separate intrinsic management row with Members, Admins and permission-gated Edit. Basic groups use the complete
  `BasicGroupFullInfo.members`; supergroups/channels expose Members only under `canGetMembers` and advance pagination by raw
  `ChatMembers.members.count`; Administrators use `getChatAdministrators` independently of hidden-member access. Stable local
  user/chat IDs preserve server order and unresolved fallbacks; one queued resolver batches same-ID reconfiguration through a serialized
  diffable apply; Dynamic Type and VoiceOver include title, role and presence. Live `updateChatMember`/full-info changes debounce a fresh
  authoritative load while retaining the first visible ID and pixel offset. Later-page failures remain visible in a table footer with
  explicit Retry. Account changes cancel child work and atomically remove the complete navigation suffix at the owning Profile.
- Edit captures account/user/client/chat identity. Cached creator or administrator `canChangeInfo` controls visibility, while every chat
  submit calls `getChatMember` for that captured user immediately before `setChatTitle`/`setChatDescription`. Self edit uses
  `setName`/`setBio`. Only changed fields are sent in sequence; successful first operations update the retry baseline, and a second-operation
  failure reports partial success without optimistic canonical state.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-132517-34076-25539.log`; final focused audit has no remaining API/model,
  pagination, diffable or account-lifetime finding after the atomic suffix fix. PID `33583` exposes a separate 176×56.67 Members/Admins
  row on the real three-member basic group; Members resolves exact `<member>, Owner`, `<member>, Member · online`, `лева, Member`, while
  Administrators independently resolves `<member>, Owner`. Screenshots:
  `.build/ui-probe-evidence/profile-management-controls.png` and
  `.build/ui-probe-evidence/profile-administrators-controls.png`. Edit was correctly absent for this non-admin account; no Save or other
  server mutation was performed.
- Runtime blocker/deferred: a safely reachable self/owned test profile was not mutated, so Edit form writes and live permission revocation
  are source-reviewed/build-proved rather than server-proved. Member promotion/removal/admin-right editors remain a later management gap.

#### Member and administrator tag editor slice

- **P1 flow:** current `PeerInfoData.swift`, `PeerInfoScreenOpenMember.swift`, `ChatParticipantRightsScreen.swift` and TelegramCore
  `Ranks.swift` rank editing, compared with pre-Liquid `ChannelAdminController.swift`, adapted as an independent UIKit + TDLibKit tag
  operation rather than an administrator-rights mutation.
- TDLib boundary: captured-client `getChat` plus parallel actor/target `getChatMember` reads before presentation and again immediately
  before one awaited `setChatMemberTag`. Basic groups and non-channel supergroups are accepted; inactive targets and channels fail closed.
  Self editing requires fresh `ChatPermissions.canEditTag`. Editing another user requires creator status or fresh
  `AdministratorRights.canManageTags`; another creator is protected, and a non-creator may edit an administrator only when
  `canBeEdited`. The target tag must still equal the captured baseline before the write, preventing a stale editor from overwriting a
  concurrent change.
- UIKit editor preserves the current tag verbatim, counts at most 16 Swift characters, rejects controls and graphic emoji, accepts empty
  to remove the tag, and keeps transport errors visible without optimistic canonical state. Successful writes explicitly schedule an
  authoritative member-list reload instead of relying on the bot-only `updateChatMember` delivery contract. Account/client changes cancel
  preparation or saving and disable stale controls.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-153759-82885-28094.log`; final focused delta review CLEAN. Runtime PID
  `83599` exposed all three real member rows as enabled buttons with disclosure chevrons and the `Shows member tag controls` hint. Tapping
  self `лева` performed the fresh authority reads and produced `Can't Edit Tag` / `You no longer have permission to edit this member's
  tag.`, then OK returned to Members. Screenshots:
  `.build/ui-probe-evidence/member-tag-smoke-members.png` and
  `.build/ui-probe-evidence/member-tag-smoke-permission-denied.png`. No text was edited, Save was never pressed and no Telegram mutation
  occurred; Simulator remains booted.
- Runtime blocker/deferred: this live account cannot edit a tag, so an authorized Save/remove and post-success refetch are not exercised
  against the server. Promotion, demotion, removal and administrator-right editors are queued after the revalidation gate.

#### Fullscreen gallery Open in Chat slice

- **P1 flow:** Telegram current/pre-Liquid gallery context action `Open in Chat`, adapted to the existing UIKit footer and BetterTG
  timeline-window loader without Telegram gallery/navigation infrastructure.
- Implemented: a plain 52×50 ellipsis control alongside unchanged Close/Share on the full-width classic blur footer. The action exists
  only when the presenting route supplies a captured account/client/source location and completion. Tap freezes a Sendable
  chat/message/topic identity, disables the control with progress and calls `getMessage` through the captured client. Completion checks
  action generation, selected ID, account/client, returned identity and exact topic for scoped profiles; base-chat routes intentionally
  accept any forum topic. A permanent delete, page change or account invalidation cancels quietly. Success forces a fade instead of the
  reverse tile transition and retains a separate navigation generation through dismissal; the completion rechecks account/client/context
  before invoking Profile or Chat. Profile pops only after modal dismissal; Chat uses its existing `prepareMessageWindow` path when the
  target is outside the loaded timeline. Secret-chat navigation needs no send/delete/save permission and remains allowed.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-134050-43746-25199.log`; final focused delta review CLEAN. PID `44134`
  exposed exact footer frames `Close 4×790 52×50`, `More actions 294×790 52×50`, `Share 346×790 52×50` and the sole UIKit menu action
  `Open in Chat`. Selecting the first profile item (`1 of 1688`) completed gallery fade and profile removal, returning to
  the source group chat with the exact `Photo, 13:31` bubble visible. Evidence:
  `.build/ui-probe-evidence/gallery-open-in-chat-menu.png` and
  `.build/ui-probe-evidence/gallery-open-in-chat-result.png`; no Telegram mutation occurred.
- Runtime blocker/deferred: the safe smoke did not switch accounts or delete the selected message during the subsecond dismissal window;
  both races are generation-fenced and source-reviewed. Forward and Delete were subsequently recorded in their own slices below.

#### Gallery Save and secured Share slice

- **P1/P0 flow:** Telegram current/pre-Liquid gallery media export and camera-roll save, adapted to UIKit, TDLibKit and Photos without
  Telegram media-box/resource infrastructure.
- Implemented: Save and Share serialize with Open in Chat and freeze the exact selected identity. Both perform parallel captured-client
  `getMessage`/`getMessageProperties`, require `canBeSaved`, reject both protected-content flags, paid media, self-destruct state and
  secret one-time photo/video/animation, then resolve the original largest photo or primary video/animation/sticker `File`. A user action
  requests full `downloadFile(limit:0,offset:0,synchronous:true)` and validates exact completion/path; cancellation only drops local
  authority and never calls global `cancelDownloadFile`. Selection/content/delete/account changes cancel before external commit.
- Photos uses `.addOnly`, re-fetches message/properties immediately before `performChanges`, sets `shouldMoveFile = false`, preserves
  creation date and a separator/control-stripped filename, validates images by ImageIO signature and Apple video by MIME plus playable
  AVAsset video track. GIF uses `.photo`, MP4 animation `.video`; WEBP sticker Save exports deterministic decoder frame 0 as PNG.
  TGS/WEBM sticker Save remains honestly hidden. Live Photo is labeled `Save Still Photo`, and Share requires an explicit
  `Share Still Photo` confirmation rather than silently implying paired motion. Photos commit is correctly treated as non-cancellable
  once submitted.
- Share now uses the same fresh protection gates instead of leaking an already-local protected path. It derives a canonical extension
  from fixed sticker format, TDLib MIME, ImageIO signature or MIME UTType; server filename contributes only a sanitized stem. A UUID temp
  hardlink (copy fallback) survives TDLib eviction/message deletion and is retained through `UIActivityViewController` completion before
  idempotent cleanup.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-140818-50364-12175.log`; final focused Telegram/TDLib/Photos delta
  review CLEAN. PID `50749` opened the real first profile photo through the secured Share preflight and displayed the system sheet with
  managed `bettertg-photo-<message-id>` / `JPEG Image · 6 KB`; the sheet was dismissed without choosing an external destination.
  PID `49849` exposed `Save Photo` and `Open in Chat` as the two More actions. Evidence:
  `.build/ui-probe-evidence/gallery-save-export-menu.png` and
  `.build/ui-probe-evidence/gallery-secured-share-sheet.png`.
- Runtime blocker/deferred: Save was deliberately not selected because it writes to the user's Photos library and no separate destructive
  smoke authorization was given. No reachable GIF/MP4 animation, WEBP sticker or Live Photo was exercised; those format branches are
  source-reviewed/build-proved. Delete is implemented below.

#### Gallery Forward slice

- **P1 flow:** Telegram current/pre-Liquid gallery `MessageGroup` sharing, adapted to BetterTG's existing UIKit
  `ForwardMessagesViewController`, forum topic picker, comment state and `MessageForwardingService` rather than a parallel delivery path.
- Implemented: Forward is serialized with Open/Save/Share and captures account/client/chat/topic/selected ID before any await. A fresh
  `getMessage` validates the source. Non-album media proceeds as one message. For an album, no loaded gallery row is trusted: exact
  base/forum/direct-messages/Saved/thread history APIs request expanding 20/40/100 windows around the selected ID. A group is accepted
  only when both adjacent nonmatching boundaries are present or Telegram's 10-item cap is reached. History transport failures advance to
  the next window and finally degrade to selected-only; cancellation propagates immediately. Fresh IDs retain exact topic and server
  order semantics through `MessageForwardRequest`.
- Complete groups show an explicit `This Item` versus `All N Items` action sheet, so a protected/unavailable sibling never prevents the
  user from trying the selected item. The chosen request enters the production destination search, secret-chat forced-copy rules, forum
  topic drill-down, formatted comment, sender/caption options, partial-delivery handling and exact account fences. Gallery playback pauses
  only while the full-screen picker is visible and resumes on Cancel; successful delivery reports recipient count in the existing footer.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-142756-56092-20725.log`; final Telegram/TDLib delta review CLEAN.
  PID `54892` exposed the real `Forward to` picker with search, destination eligibility, Add a comment, `1 message` and disabled Forward
  before selection; Cancel returned to the exact `1 of 1688` gallery with Close/More/Share intact. Final build PID `57324` launched on the
  still-booted Simulator. Evidence: `.build/ui-probe-evidence/gallery-forward-picker.png`; no destination was selected and no
  `forwardMessages` mutation occurred.
- Runtime blocker/deferred: the reachable selected photo has no album, so the item/all choice and every topic-history variant are
  source-reviewed/build-proved rather than live-data-proved. Deliberate delivery remains a test-account mutation gap.

#### Gallery Delete slice

- **P1/P0 flow:** Telegram current/pre-Liquid gallery item/group deletion and revoke-mode confirmation, adapted to one captured TDLibKit
  client and the same authoritative album resolver as Forward.
- Implemented: Delete is absent for secret/self-destruct media and serialized with Open/Save/Share/Forward. Single media proceeds to
  authority checks; a proven album first offers destructive `This Item` / `All N Items`, while unresolved history safely degrades to the
  selected item. Every chosen ID receives fresh exact-chat/topic `getMessage` plus `getMessageProperties`; permissions intersect across
  the complete set. Confirmation exposes `Delete for Me` only when every ID supports local deletion and `Delete for Everyone` only when
  every ID supports revoke. Immediately before commit, the same messages/properties/mode are fetched and checked again. One captured
  `deleteMessages` call is issued; no optimistic removal, multi-call partial state or automatic retry exists. An unconfirmed post-enqueue
  failure tells the user to inspect whether media remains.
- The controller now observes permanent deletes for photo/animation/sticker as well as video. Per-chat ID unions coalesce rapid events
  across diffable batches and interactive dismissal, merge owner callbacks, filter the newest pending canonical message list once and
  adjust the authoritative total once. Video owners are marked terminal and removed before release, revoking PiP/restore and preventing
  deleted playback from returning inline. Selected deletion uses a pre-enqueue snapshot and exactly-once forced fade; no dust/particles.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-144807-65887-7317.log`; final Telegram/TDLib lifecycle review CLEAN.
  PID `63543` exposed destructive `Delete` above Save/Forward/Open in the real gallery menu; it was not activated. Final unified build PID
  `66267` launched with Simulator still booted. Evidence: `.build/ui-probe-evidence/gallery-delete-action-visible.png`.
- Runtime blocker: destructive confirmation and `deleteMessages` were deliberately not exercised without separate approval; item/all,
  for-me/everyone, rapid-update union and video/PiP terminal branches are source-reviewed/build-proved.

#### Forum notification quick-reply slice

- **P0 flow:** topic-aware notification reply using TDLib `getMessage`, `getForumTopic`, `sendMessage(topicId:)` and `viewMessages`.
- Implemented: exact account requirement; captured-client guards; authoritative message/topic fetch; closed/manage-topic and existing
  chat/payment checks; verified same-topic reply target; exact returned chat/topic assertion; fail-closed lookup behavior.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-080453-55869-29388.log` plus focused source delta-review.
- Deferred: deliberate test-account notification action proof and all-messages history/composer parity.

#### Forum-aware Forward destination slice

- **P0 flow:** pre-Liquid/current forum drill-down behavior from `ChatControllerForwardMessages` and `PeerSelectionController`, adapted
  to UIKit + TDLibKit rather than Telegram controllers/state stores.
- Implemented: source route proof at prepare+delivery; destination chat/topic identity; multi-chat/multi-topic selection; exact cursor
  topic picker/search; closed/manage-topic and per-content eligibility; fail-closed forum discovery; exact forward result validation;
  partial retention; account fences; classic full-width material navigation/search and local selection summaries.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-075614-53821-9609.log`; local selection flow and classic header evidence
  `.build/ui-probe-evidence/forum-forward-topic-plain-final-*`; no Forward/send mutation, PID 54141 alive, Simulator booted.
- Deferred: comment/forward-draft transition, deliberate test-account delivery and all-messages headers.

#### All-messages forum timeline foundation slice

- **P0/P1 flow:** base forum adjacent-topic runs and jump-free history extension from pre-Liquid/current
  `ChatMessageItemImpl.swift` and `ChatMessageDateHeader.swift`, adapted to one inverted UIKit collection without Telegram
  Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: stable `message(id)` / `album(mediaAlbumId)` / `topicHeader(topicID,runStartMessageID)` identities; complete
  projection rebuild for `A,A,B,B,A`; official 34pt centered 22pt topic control with 16pt General/custom/generated icon, one-line title
  and chevron; lazy account/client-fenced `getForumTopic` cache plus `updateForumTopicInfo`; authoritative topic tap; message-only
  read/prefetch/playback/context/selection paths; raw TDLib pagination cursor; cross-page album coalescing; permanent member-delete
  survival; message-window reuse; and visible message + pixel-offset restoration across boundary-header insert/remove/merge.
- Production routing follows live `Chat.viewAsTopics`. Base text/photo/edit/draft and chat-action contexts resolve to discovered General
  or the replied message's exact topic; closed-topic replies fail closed, reply transitions cancel the prior topic action, and the base
  draft key remains `topic:nil`. Voice/video manifests now carry a separate immutable send topic through record/pause/resume/preview,
  relaunch, enqueue, resend and exact record/upload/cancel actions; a newer composer reply is never cleared by an older media draft.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-085723-71772-1312.log`; wrapper/idb launch PID `67526` stayed
  alive and ordinary chats retained full composer controls. `.build/ui-probe-evidence/forum-all-messages-*` records the hierarchy scan;
  no safe `viewAsTopics == false` forum exists in current simulator data, so live header tap remains a data-state blocker. Fresh PID
  `71701` passed `.build/ui-probe-evidence/forum-all-messages-media-destination-*`: voice Ogg/Opus + base-draft/frozen-topic relaunch,
  video send outcome/legacy/thumbnail/tombstone cleanup, and ordered multi-segment video recording trim/thumbnails/frozen-topic handoff.
- Deferred: live all-messages topic-header/pagination/album seam proof on an account with a reachable forum in this mode.

#### Keyboard and self-sizing timeline anchor slice

- **P1 flow:** Telegram-style `messageId + pixelOffset` retention across viewport/intrinsic-size changes in the inverted UIKit history.
- Implemented: message-cell pre-fit height notification; one coalesced visible-message anchor for autonomous self-sizing; exact anchor/latest
  restoration around single/bulk diffable reconfigure, composer/search/selection/keyboard insets, Dynamic Type and rotation; mutation-depth
  ownership so stale deferred size callbacks cannot overwrite a newer snapshot/inset/rotation anchor; active pan/deceleration remains untouched.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-091301-75604-22504.log`; focused delta-review clean. PID `75942`
  retained `Video message, 0:13` at `{{53,381},{260,260}}` and `chat-date-1787342400` at `{{172,348},{58,22}}` across two
  hierarchy-derived focus attempts (`Δx/y/w/h=0`). Simulator did not present `AXKeyboard`—likely hardware-keyboard state—so the
  non-no-op keyboard-attached transition remains a runtime proof blocker. Evidence: `.build/ui-probe-evidence/timeline-anchor-fresh-*`.

#### Delete collapse/fade/slide slice

- **P0 flow:** Telegram-style restrained delete transition without dust/particles, integrated with authoritative TDLib
  `updateDeleteMessages` and the inverted diffable timeline.
- Implemented: ChatVM announces only bubbles whose complete source-message set disappears; visible sources become noninteractive and
  animate 140ms opacity + directional 24pt slide + 0.98 scale; the delayed heterogeneous snapshot then performs layout collapse. Rapid
  deletes coalesce to one deadline, cell reuse resets all presentation state, nonvisible deletes apply immediately, album-member survivors
  stay in place, video teardown still follows `didEndDisplaying`, and the collapse anchor is restricted to IDs surviving in canonical state.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-092113-77487-3754.log`; focused source/delta review clean. No deliberate
  server delete was performed, so visual runtime mutation proof remains deferred.

#### Composer send-flight slice

- **P0 flow:** pre-Liquid Telegram composer source-to-message insertion transition, adapted to real UIKit snapshots and TDLib temporary
  IDs without Telegram transition infrastructure.
- Implemented: synchronous capture of visible reply, formatted text, selected-photo strip, caption, active voice/video preview and
  retry-button sources; one serialized composer text/media send; temporary→success/failure ID aliases before or after acceptance;
  canonical album/message target lookup; 320ms staggered frame/corner/opacity flight into the real visible bubble; bounded offscreen
  fallback; five-second/deinit/account cleanup. Voice direct/trim-preview/promotion/retry and video recorder/retry paths bind runtime-only
  transition tokens to their durable draft IDs, accept exact returned message IDs, and cancel retained/interrupted/discarded failures.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-093342-80738-1901.log`; focused source/delta review clean. No deliberate
  test-account send was performed, so the visible flight remains a mutation-gated runtime proof gap.

#### UIKit file/document attachment slice

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

#### UIKit emoji/sticker/GIF composer slice

- **P0 flow:** pre-Liquid/current emoji/sticker/GIF input panel behavior, adapted to a UIKit page sheet and TDLib-native
  `getStickers`, `getSavedAnimations`, `InputMessageSticker` and `InputMessageAnimation`.
- Implemented: Emoji/Stickers/GIF segmented grid; debounced search and mode-generation cancellation; account/client/chat fencing before
  loads and selection; installed regular sticker query with every Premium sticker excluded; saved-GIF filtering; exact picker-cell AX;
  TGS/WebP/WebM reuse with offscreen pause and GIF thumbnail cancel/restart; repeated emoji insertion with debounced route draft; exact
  other-message permission, General/reply topic and returned-destination assertion. Sticker sends preserve typed text while clearing the
  accepted reply through the captured draft topic with generation-fenced retry; GIF caption clears safely; both use serialized sends and
  the insertion-flight protocol. No Premium/Stars/custom-emoji results are offered.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-102014-91617-3187.log`; focused source/delta review clean. Runtime
  PID `90585` proved the UIKit sheet, exact three segments, 64 enabled emoji buttons, 16 non-Premium sticker buttons, 16 saved-GIF
  buttons, offscreen-safe navigation and Done return. Evidence: `.build/ui-probe-evidence/composer-media-picker-final-*`; no
  emoji/sticker/GIF was selected or sent.

#### Forward comment/draft slice

- **P0 flow:** pre-Liquid/current forward destination comment state, adapted to the existing UIKit multi-recipient/topic picker and
  TDLib `sendMessage(InputMessageText)` followed by `forwardMessages`.
- Implemented: expanding formatted Add a comment field retained across topic drill-down/search/retry; keyboard-layout-guide attachment
  with interactive dismissal and safe-area toolbar switching; Dynamic Type height refresh; comment snapshot at delivery start; exact
  basic-message/private/paid/forum/closed/admin eligibility; account/client checks immediately before mutation; exact returned topic.
  Each destination records the delivered `FormattedText`, so a failed forward retries without duplicating an unchanged successful
  comment, while an edited comment is a new intent. Comment failure blocks that destination's forward; ambiguous/partial forwarding keeps
  the existing nonretry policy, and controls re-enable with the comment intact.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-102642-93175-2531.log`; focused source/delta review clean. PID `93577`
  reached the real message context menu, but idb omitted its Forward overlay action, so safe navigation to the comment field was blocked.
  Evidence: `.build/ui-probe-evidence/forward-comment-final-*`; no comment or forward mutation occurred.

#### Date and topic boundary slice

- **P1 flow:** pre-Liquid/current `ChatMessageItemImpl.swift` date/topic merge break and `ChatMessageDateHeader.swift` 34pt service
  header ordering, adapted to stable heterogeneous UIKit diffable items.
- Implemented: calendar-start stable IDs; 34pt inverted rows with centered 22pt localized pills; Today/Yesterday/year-aware labels and
  header accessibility; one separator per day in ordinary and forum histories; exact visual date→topic→message ordering on simultaneous
  boundaries; no duplicate topic header at midnight; message-only read/prefetch/selection/playback; structural pixel-anchor reuse; and
  significant-time/locale snapshot reconfiguration so cached Today labels and timezone-derived identities cannot go stale.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-090344-73347-22038.log`; runtime hierarchy/screenshot evidence is
  `.build/ui-probe-evidence/date-headers-*`. Fresh PID `73694` exposes `chat-date-1787860800` (`Aug 28`, 58.67×22) and
  `chat-date-1788033600` (`Yesterday`, 76.67×22); 6pt row insets plus existing 5pt message gaps prove the exact 34pt row with zero
  overlap, while the enabled composer remains at y=796.67.

#### Writable explicit forum topic slice

- **P0 flow:** pre-Liquid/current closed-topic input panel, topic placeholder, text/attachment/media recording, activity and draft
  semantics from `ChatInterfaceStateInputPanels`, `ChatTextInputPanelNode`, `ChatController`, `ChatControllerOpenAttachmentMenu` and
  `ChatControllerMediaRecording`, adapted to UIKit + Combine + TDLibKit without Telegram infrastructure.
- Implemented: immutable send context; exact topic for text/photo/album/voice/video/action/draft; returned-topic assertions; same-topic
  replies; content-specific and live closed-topic authority; dirty/stale draft fences; generation-safe clear retries; edit preservation;
  partial-album retention; exact-location reactions/polls/delete/forward source; writable/restricted UIKit composer states and topic
  placeholder. Base forum history is now handled by the separate all-messages resolver above.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-073123-48367-634.log`; non-mutating real-topic route and production
  composer evidence `.build/ui-probe-evidence/forum-topic-write-final-*`; PID 48686 alive, Simulator booted.
- Deferred: forward comment, all-messages General-or-reply resolver/run
  headers, deliberate test-account send/draft mutation, topic-scoped pinned banner and remaining attachment types.

#### Topic media draft identity slice

- **P0 flow:** thread-scoped composer media ownership from pre-Liquid/current `ChatInterfaceState` and
  `ChatControllerMediaRecording`, adapted to Codable actors + TDLibKit rather than Postbox/SignalKit.
- Implemented: stable account/chat/full-topic key; four version-tolerant manifests; durable one-time legacy policy; exact restore,
  deduplication, enqueue, discard, recording handoff and resolution routing; draft-UUID outcome names; voice registration barrier;
  account/topic coordinator snapshots; stale account restore/promote guards; recorder receives the immutable destination.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-065904-41355-13754.log`; terminal probe files and run metadata
  `.build/ui-probe-evidence/topic-draft-key-*`; PID 41675 alive after proof, Simulator booted.
- Deferred: resolved network send context, topic text drafts/dirty generations, closed-topic write permission, exact returned-topic
  assertions, then attachments/voice/video UI enablement and topic-aware Forward/all-messages headers.

#### Classic chat list row slice

- **P2/P1 flow:** pre-Liquid `ChatListItem` presentation applied to existing UIKit chat/folder data and actions.
- Implemented: full-width 76pt rows; 60pt avatar at x=10; content/separator x=80; pinned/normal/highlight backgrounds; title/preview/date;
  pending/failed/delivered/read state; unread/muted/marked-unread/pin accessories; capped Dynamic Type; full-state VoiceOver; full-row context
  extraction and tap target. Existing diffable stable IDs, prefetch, search, gestures and TDLib actions remain unchanged.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-063859-35683-18833.log`; exact frame/tap evidence
  `.build/ui-probe-evidence/classic-chat-rows-*`; first tap opens Saved Messages; PID 35152 alive; Simulator booted.
- Deferred: typing/action preview, verified/scam/status/story adornments, archive reveal gestures and full account fencing for list mutations.

#### Classic shell blur slice

- **P2 flow:** full-width folder/tab chrome and context-menu material, based on pre-Liquid `ChatListFilterTabContainerNode` selection
  geometry and classic UIKit material rather than Liquid Glass.
- Implemented: edge-to-edge bottom blur including safe area; rectangular scroll viewport; exact three-point segment line; selected accent
  text; ordinary system-material context menu; classic 16/10pt menu/highlight corners; all Glass-only APIs and marker strings removed.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-062914-33482-14249.log`; real account hierarchy/screenshot and long-press
  menu evidence `.build/ui-probe-evidence/classic-shell-*`; PID 33820 alive; Simulator booted.
- Deferred: remaining navigation/search/action surfaces still need a complete full-width/no-floating audit.

#### Forum topic browsing slice

- **P0 flow:** pre-Liquid/current `ChatListNodeLocation`, `ChatListNodeEntries`, `ChatListItem`, `ChatControllerContentData` and
  `ChatControllerLoadDisplayNode`, adapted to UIKit + Combine + TDLibKit without Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: account/client/chat/topic route identity; captured-client ref-counted open lease; exact topic cursors/order/hidden/search;
  update refetch and transient retention; explicit topic history/search/read acknowledgement; target-message topic resolution; classic
  UIKit rows with General/custom-emoji icons, pin/closed/draft/unread variants, Dynamic Type, VoiceOver and offscreen animation pause;
  stable-ID reconfiguration; fail-closed push/forward; VM-level read-only barriers with non-mutating content access preserved.
- Proof: warning-free build log `.build/logs/xcodebuild/build-Debug-20260831-062650-32938-29366.log`; device hierarchy/screenshot files
  `.build/ui-probe-evidence/forum-topics-*`; `[1,42,77]`, hidden 99 absent, AX tap `(201,262)`, status
  `Opened topic 42 · Read-only`, PID 31980 alive.
- Deferred: all-messages topic-run headers, topic composer/writes/durable drafts, topic forwarding selection, topic actions/mutations,
  General hidden toggle/admin controls, unread navigation and live server pagination/mutation smoke.

#### Pinned message slice

- **P0 flow:** pre-Liquid/current `ChatInterfaceStateContextMenus`, `ChatControllerLoadDisplayNode`,
  `ChatPinnedMessageTitlePanelNode` and `ChatControllerNavigateToMessage`, adapted to UIKit + Combine + TDLibKit without
  Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: exact Saved/private/group/channel pin modes; fresh `canBePinned` preflight; one serialized chat mutation; optimistic
  newest-pin state with authoritative revision rollback fences; account/client/generation guards before and after TDLib; initial and
  refreshed `getChatPinnedMessage`; 404-only clearing; cache/permanent-delete/edit/content/isPinned reconciliation; direct-message/forum/
  topic/album/service/sending gates; shared spoiler-safe thumbnail extraction; 50pt full-width blur banner; separate Open/Hide AX controls;
  local hidden-ID token; newer-pin resurfacing; selection/search suppression; stale-animation rejection; inverted-history inset stability.
- Proof: `Pinned message probe: modes=true, visibility=true, 404-only-clear=true, newest-only=true, banner-height=50, local-hide=true, navigation=true, uikit=true, swiftui=false`.
- Deferred: nearest-visible pin rotation, pinned-only list/pagination, admin unpin undo, older-pin warning details, topic-scoped pins and
  deliberate live server mutation proof.

#### Message reactions slice

- **P0 flow:** pre-Liquid/current `ReactionButtonListComponent`, `ChatMessageReactionsFooterContentNode`,
  `ChatMessageBubbleItemNode` and `ChatController` toggle/restriction behavior, adapted without
  Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: representative-bubble standard/custom reaction rendering; Telegram count-minus-own-selection sorting; exact 30/20pt
  geometry and 6pt wrapping; chosen/unread styling; reusable accessibility; account-keyed custom-emoji sticker cache; offscreen
  animation pause; zero-state context picker; authoritative per-message availability; Premium/paid exclusion; maximum-count-safe
  optimistic add/remove with rollback; chosen removal under restrictions; normal-client interaction/unread reconciliation; live
  chat permission/max updates; account-switch fences; chat/topic reaction-read acknowledgement; read-only topic and ephemeral mutation gating.
- Proof: `Message reaction probe: reducer=true, remove=true, add=true, max-count=true, unread=true, paid-excluded=true, wrapping-chips=true, uikit=true, swiftui=false`.
  Device hierarchy proves the exact two-row frames/gaps and paid omission. Fresh center taps produce
  `👍: 2, Not selected` and `❤️: 1201, Selected` while PID 11956 remains running.
- Deferred: custom-emoji origination grid, reactor list/avatars, removal animation, forum-topic identity and live server mutation proof.

#### Forward and message-selection slice

- **P0 flow:** pre-Liquid/current `ChatMessageSelectionNode`, `ChatMessageSelectionInputPanelNode`,
  `ChatControllerForwardMessages` and `PeerSelectionController` behavior, adapted to UIKit + Combine + TDLibKit without
  Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: context Select/Forward gates; whole-album direct forwarding; stable selection/reuse/accessibility; classic geometry and
  transition timing; 100-child limit; exact per-child property/content preflight; multi-delete; Saved/main/archive/offline/server
  destination discovery; raw-chat secret/private/group/channel eligibility; multi-recipient progress; sender/caption modes; safe
  nonretryable treatment for unknown partial subsets; account-switch fences before every mutation.
- Proof: `Message forwarding probe: normalized=true, limit=true, options=true, album-atomic=true, multi-recipient=true, account-scoped=true, uikit=true, swiftui=false`.
  Device hierarchy proves `forward-probe-saved-messages` and `forward-probe-design-group` are full-width 402×62 AX controls;
  center taps select both, enable the 66×56 Forward control and produce `Ready: 3 sorted IDs · 2 chats` without a Telegram send.

#### Reply, quote and forward provenance slice

- **P0 flow:** pre-Liquid/current `ChatMessageReplyInfoNode`, `ChatMessageForwardInfoNode` and bubble tap semantics, adapted without
  AsyncDisplayKit/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: cross-chat/ID-zero/story/unavailable fallbacks; forwarded target author override; `ForwardSource` chat-first display and
  message→chat→sender navigation; hidden-author static state; thumbnails including round video notes; 1-line ordinary and 5/50-line manual
  quote layout; source/context accessibility and bubble custom actions; exact quote range search/highlight; external reply input and every
  media draft restoration path; account/client guards; cache/permanent-delete and stale-generation fences.
- Proof: `Message metadata probe: inline=true, unknown-chat=true, source-priority=true, expand-then-navigate=true, forward-navigate=true, external-input=true, utf16-quote=true, highlight=true, uikit=true, swiftui=false`.
  Screenshots are `.build/message-metadata-final-*.png`; Simulator remains booted.

#### Exhaustive MessageContent breadth slice

- **P0 flow:** classic content routing based on the pre-Liquid contact/map/poll/action/animated-sticker nodes and
  `ServiceMessageStrings`, adapted to UIKit + Combine + TDLibKit rather than Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: 104-case catalog; shared summary/caption extraction; audio and document rows plus attachment albums; explicit primary-file
  download/cancel/reconcile and thumbnail-only prefetch; details-first contact card with five vCard lines; actual MapKit snapshots and
  absolute live-location timer; single/multi poll submission, persisted pending state, authoritative result/quiz colors and VoiceOver;
  visibility-gated animated emoji/rolling regular dice with safe resolved fallback; centered service pills; italic unsupported placeholder;
  explicit excluded-product fallbacks; account-captured, generation-safe prefetch.
- Proof: the DEBUG probe instantiates production views with real TDLib model values rather than parallel mock views. Its Documents proof is
  `MessageContent probe: tdlib=1.8.66-022d6020, exhaustive-cases=104, views=file,file,attachmentAlbum,contact,location,location,poll,poll,stickerGlyph,stickerGlyph,service,service, sized=true, poll-actions=poll:0,poll:0,1, action-proof=true, uikit=true, swiftui=false`.
  Device screenshots are under `.build/message-content-final-postbuild-*.png`; Simulator remains booted.

#### FFmpeg range controller slice

- **P0 flow:** non-Apple WebM VOD controller, following pre-Liquid/current `ChunkMediaPlayerV2.swift` buffering/seek/EOF and
  `ChunkMediaPlayerDirectFetchSourceImpl.swift` packet-lookahead behavior through TDLib `downloadFile(offset:limit:)`,
  `getFileDownloadedPrefixSize`, `updateFile` and `cancelDownloadFile`.
- Implemented: MainActor Combine controller; serialized 2s normalized packet horizon followed by a bounded 60s
  decoder job; exact 1s source gate plus Apple raw sufficiency; play/pause/rate/seek/EOF; non-zero-origin and per-track intervals;
  typed offline/retry failures; last-target-wins generations; offscreen renderer/range suspension; sparse audio degrades to silence;
  source demand cancellation is operation-token/last-demand scoped.
- Verification: `./build.sh` and `./test.sh` pass with Xcode 26.6. The 11.208s DEBUG fixture launched through
  `RUN_ARGUMENTS="-media-probe-vod-ffmpeg-controller" ./run.sh` and reported deferred load, ≥1s initial gate, ≤60s window,
  autoplay, visible buffering, stable pause, 1.5× rate, offscreen suspension/cancellation, preserved intent, last-seek-wins,
  seek-first PTS, EOF/no-loop, offline/retry, seek clamp, zero renderer errors, finite range downloads, zero full downloads and cleanup.
  `git diff --check` is clean.
- Subsequent slices below record persistent session rollover and the sample-buffer PiP implementation. Active system PiP/background
  restore remains a physical-device proof gap, subject to the new revalidation gate.

#### Production FFmpeg gallery routing slice

- **P0 flow:** WebM/VP9 VOD in the existing UIKit inline/fullscreen owner, following pre-Liquid `UniversalVideoGalleryItem.swift`
  central visibility and `ChunkMediaPlayerV2.swift` backend continuity without importing Telegram infrastructure.
- Implemented: MIME+extension routing; public range streaming; secret/non-streaming full-download handoff; cached-file FFmpeg re-entry;
  one controller/view/lease across inline and fullscreen; mute/rate/seek/control routing; offscreen demand suspension with preserved intent;
  first-frame/thumbnail transition fallback; typed failures; generation guards for every native and FFmpeg Combine stream; stale lease
  invalidation; native MP4/MOV/M4V and AVPlayer PiP isolation.
- Verification: `./build.sh build` succeeds without warnings. The combined native+FFmpeg owner probe launched through
  `./build.sh run -- -media-probe-gallery-owner`; idb readback proves `ffmpeg-route=true`, `same-controller=true`,
  `offscreen-intent=true`, `finite-ranges=true`, `ffmpeg-invalidate=true`, native `same-item=true`, zero full downloads for streamable
  fixtures, exact return-to-inline continuity, terminal lease cancellation and no stale attachment callbacks.

#### Persistent FFmpeg session slice

- **P0 flow:** retain demux/decoder/SWR state across VOD high-water expansions, matching pre-Liquid `ChunkMediaPlayerV2.swift`,
  `FFMpegMediaDataReaderV2` and `FFMpegFileReader` session-per-seek behavior through TDLib finite range reads.
- Implemented: separate exact one-shot and soft streaming APIs; one open per seek-generation; authoritative Continue horizon; full crossing
  frames; per-track emitted cursors; end-aware track completion; globally sequenced interleaved compressed-packet FIFO with hard count and
  payload/side-data/overhead footprint bounds; cumulative session metrics and per-pump safety budgets; persistent callbacks/context;
  terminal cancellation and close barrier; no repeated lookahead after session start.
- Verification: SHA-pinned two-second boundary fixture proves three uneven pumps, one open, no rollover seek, monotonic A/V, no added
  previous-end→next-start discontinuity, exact seek, persistent supersession/cancel and EOF/SWR tail. SHA-pinned sparse unequal-track
  fixture proves video 12s plus audio packets at 0…2 and 8…10s, non-EOF first horizon, full terminal audio/video, and ordered FIFO use
  (`25` packets / `24,113` bytes). The production controller proves eleven 1s DEBUG pumps on one session plus all prior playback states.

#### Sample-buffer Picture in Picture slice

- **P0 flow:** FFmpeg WebM VOD PiP using the pre-Liquid/current `NativePictureInPictureContentImpl` AVKit contract while retaining
  BetterTG's existing UIKit owner, Combine state, TDLib range session and restore coordinator.
- Implemented: exact layer-keyed `ContentSource`; strongly retained lock-backed playback adapter; finite current-containing range;
  playing/buffering/paused mapping; explicit setPlaying; signed skip with past-end reset; render-size forwarding; background audio allowed;
  pause/duration invalidation; native/sample source reconciliation; start/stop timeouts; pending-start strong retention; deletion/restore/audio
  lifecycle; deferred failed-player teardown; forced-timeout controller retirement and exact stale-controller rejection.
- Verification: the production gallery-owner fixture exercises the real content-source factory despite system PiP being unsupported and
  proves sample layer/delegate identity, transport/range behavior, exact-once completion, source continuity, zero extra TDLib cancellation,
  deferred stop-before-close, native fallback route, pending-start barrier and stale timeout callback rejection. Actual system-window PiP
  and background restore still require a capable physical device.

## Appendix B — parity-continuation ledger

Verbatim ledger of `codex/parity-continuation` at `eb4e199` (through 2026-09-06), headings demoted one level.

This file is the checkpoint ledger for the UIKit + Combine + TDLibKit implementation. Telegram references use
`telegram-upstream/master` unless a commit is pinned. The classic pre-Liquid baseline is
`8e7e5fefb1b0aba8335d8c28b62138183d61dc3d`, the parent of Telegram's first first-parent `Glass` commit.

User-approved visual exception (2026-09-05): preserve BetterTG's existing Liquid Glass folder picker and shared context
menus, as restored from `64625ed^`. Keep the inset scrolling glass capsule, moving glass selection and full-width background
blur, plus the glass menu surface and rounded highlights. Future parity work must retain this presentation while extending
actions and state handling; the classic baseline does not require replacing these two surfaces.

Status values: **done** has local implementation proof, **partial** is usable with listed gaps, **next** is the next
bounded slice, and **queued** has not started. Gifts, Stars, collectibles, boosts, Premium, ads, livestreaming, and
Telegram infrastructure (Texture, SignalKit, Postbox, Display, ComponentFlow) are intentionally out of scope.

| Priority | Flow | Telegram reference | TDLib API / model | Status and proof |
| --- | --- | --- | --- | --- |
| P0 | Remove MobileVLCKit; local audio/video playback seam | `submodules/TelegramUniversalVideoContent/Sources/PlatformVideoContent.swift` at the pre-Liquid baseline | `downloadFile`, `updateFile`, `cancelDownloadFile` | **partial** — `LocalMediaPlayer` uses AVFoundation, gallery playback pauses offscreen and has thumbnail fallback, and downloaded Ogg/Opus audio is cancellably decoded by FFmpeg before AVPlayer use. A range-backed FFmpeg controller now emits owned BGRA video and interleaved float audio for generic VP9/Opus WebM without a full download, renders both tracks on one Apple media clock, and is production-routed through the persistent inline/fullscreen gallery owner. `./build.sh build` passes without warnings and `rg` finds no VLC dependency/import/API marker in `project.yml` or `BetterTG`. Persistent FFmpeg sessions span rolling windows and sample-buffer PiP uses the exact display layer; only active system PiP/device proof remains. |
| P0 | TGS stickers and animated/custom emoji | `AnimatedStickerFrameSource.swift` gzip/rlottie path, `AnimatedStickerNode.swift` lifecycle, and pre-Liquid `MultiAnimationRenderer.swift` / `EmojiTextAttachmentView.swift` | `MessageSticker`, `TextEntityType.customEmoji`, `getCustomEmojiStickers`, `downloadFile`, `updateFile` | **partial** — timeline/gallery TGS uses bounded zlib decode, pinned Lottie 4.6.1, synchronized loops, visibility pause, parsed cache, prefetch/cancel, and thumbnail fallback. Custom-emoji entities are batch-resolved by ID, mapped from arbitrary TDLib order, overlaid on exact TextKit glyph rects, keep the native glyph until first frame, and share TGS/WebP/WebM clocks/lifecycle. `./test.sh` passes; Telegram `tiny.tgs` decodes to valid 100×100@30 JSON; current idb smoke confirms ordinary/wrapped text and timestamps remain stable. The September 5 Saved Messages test verifies two identical custom emoji in the composer and a successful send. `needsRepainting` substitution remains a separate unproved/pending detail. |
| P0 | Animated WebP | `submodules/WebPBinding/Sources/UIImage+WebP.m`; Telegram only uses its static frame fallback | `StickerFormat.webp`, `File`, `downloadFile`, `updateFile` | **partial** — direct pinned libwebp 1.6.0 demux preserves frame timing, blend/disposal canvas and premultiplied alpha; timeline/gallery share a synchronized display clock, off-main decoder, 64 MiB frame/asset caches, full-file prefetch/cancel, visibility pause, and thumbnail fallback. `./test.sh` passes; the exact metadata path decodes upstream's 4,764-byte animated fixture as 990×1050, 8 frames/0.8 s, and the first BGRA frame proves alpha 0…255. Current `./run.sh` + idb launch/chat smoke is stable; visual playback awaits a reachable WebP sticker in simulator data. |
| P0 | WebM/VP9 alpha stickers and generic FFmpeg playback | `AnimatedStickerNode/VideoStickerFrameSource.swift`, `FFMpegMediaVideoFrameDecoder.swift`, `FFMpegAVFrame.m` | `StickerFormat.webm`, `File`, `downloadFile`, `updateFile` | **partial** — checksum-pinned FFmpeg 9.0 decodes the main VP9 stream plus Matroska `BlockAdditional` alpha stream, scales to BGRA, premultiplies alpha, and feeds synchronized timeline/gallery loops with off-main decode, 64 MiB caches, prefetch/cancel, visibility pause, and thumbnail fallback. GIF/non-Apple animation containers now route through the same renderer while MP4/MOV retain AVFoundation. The non-looping range decoder retains probe packets, decodes VP9+Opus on a named worker, copies borrowed C frames before callback return, trims seek preroll/sample tails to the exact requested interval, and supports supersession/cancel. Its renderer uses pooled IOSurface-backed BGRA buffers, packed Float32 PCM and one `AVSampleBufferRenderSynchronizer`, with bounded generation-aware queues and no `DisplayImmediately`. The rolling controller is production-routed for public, secret, streaming, non-streaming and already-cached WebM/Matroska videos while Apple containers stay on AVFoundation. `./build.sh build` and the gallery-owner idb probe pass; persistent cross-window decoder and sample-buffer PiP adapter probes pass; real-message visual proof and active PiP on a capable device remain. |
| P0 | Voice notes: Ogg Opus, waveform, record/lock/edit/send | `ManagedAudioRecorder.swift`, `OpusBinding/Sources/opusenc/opusenc.m`, `AudioWaveform.swift`, `TGModernConversationInputMicButton.m`, and pre-Liquid `ChatRecordingPreviewInputPanelNode.swift` | `VoiceNote`, `InputMessageVoiceNote`, `resendMessages`, `updateMessageSendSucceeded/Failed`, `downloadFile` | **implemented breadth** — capture is 48 kHz mono signed-16 PCM, rejects recordings below 0.5 s, produces an exact 100×5-bit/63-byte waveform, and sends only validated Ogg/Opus. Transactional send manifests survive registration/crash races, failed sends honor TDLib resend state, multiple drafts promote, and unsupported paid/alternate-reply states cannot silently resend. Telegram's 0.19 s hold/release, slide-cancel/lock distance+velocity ordering, pre-arm/system-cancel preservation, VoiceOver lock, and scoped bottom-edge deferral are implemented. Locked Stop-and-preview closes WAV segments, validates/merges exact PCM frames off-main, derives Telegram-normalized waveform samples, and atomically owns a revisioned editable draft. The UIKit island exposes Delete, Record More, Play/Pause, hollow seekable waveform, two continuously draggable/VoiceOver-adjustable trim handles, selected duration and Send. Trim metadata is revisioned and restored; selection is at least 1s/56pt, playback and seek clamp to it, releasing either edge previews the changed edge, and Resume presents destructive-trim confirmation. Any non-full trim is materialized to a new PCM revision before Record More or Ogg promotion, recomputing exact duration/waveform. Dedicated playback has reciprocal arbitration and scoped session release. Reply/interruption ownership, cancel/send/trim generations, manifest relocation, relaunch restoration and cleanup are covered. `./test.sh` passes; idb proves exact `142→202`/`304→254.14` handle travel, hollow seek, edge preview, confirmation Cancel/Continue, revisioned append, relaunch playback, and trimmed safe-Send ordering (`1.33104s` materialized before `encoded=true`) with unchanged timeline and empty stores after Discard. Remaining voice work is encoder-quality parity/polish, not a missing requested flow. |
| P0 | Video notes | `submodules/Camera/Sources/VideoRecorder.swift`, `CameraRoundVideoFilter.swift`, `VideoMessageCameraScreen`, `ResultPreviewView.swift` | `InputMessageVideoNote`, `InputVideoNote`, `sendMessage`, `resendMessages` | **implemented multi-segment breadth** — the writer serializes capture queues, gates pre-video audio, waits video+audio EOF, center-crops/orients and round-masks actual pixels, and validates network-optimized 400×400 H.264 High/CABAC ~1 Mbps + mono 48 kHz AAC MP4. Generation-scoped AVCapture requests microphone then camera, defaults front, rejects stale PTS, freezes device orientation per recording, cleans interruptions/background/audio ownership, soft-stops at `>59.5s`, and hard-clamps at 60s. UIKit composer tap toggles mic/video; the unchanged Telegram 0.19s arm, live/release distance+velocity ordering, pre-arm lock, system-cancel preservation and bottom-edge deferral route both modes. A child recorder keeps the composer gesture alive and shows the classic max-369pt round camera, 4pt progress, 44pt flip/flash, pinch zoom, front-screen/back-torch flash, holding/lock/cancel, locked Stop-to-preview and release-to-send. Live 1s-throttled front/back switching rejects queued old A/V, removes the capture timestamp gap from both tracks and encodes a six-frame/0.2s dissolve instead of only smoothing the preview. Single-result preview loops muted and can play/pause/delete/send; TDLib promotion uses `InputVideoNote` and preserves the snapshotted reply. Atomic manifests own adopted MP4s across crash/chat close, reconcile outcome-before-registration, expose safe no-paid retries while keeping unsupported failures discardable, and clean success/discard/permanent delete. The ordered-segment foundation owns stable-ID MP4 segments, atomically persists revisioned global trim, composes video/audio on identical boundaries, samples exactly 13 full-composition thumbnails, materializes a zero-start 1…60s export, and preserves a 0.5…1s first result for Record More. `LocalMediaPlayer` retains the full `VideoNoteCompositionResult` snapshot lease, applies `forwardPlaybackEndTime`, exact last-target-wins seeks and loops from the global trim lower bound without rebuilding the item. UIKit Record More is visible only below 59s, starts hands-free, ignores sub-0.5s Stop, appends in order while clearing prior trim, uses aggregate 59.5s soft/60s hard limits and non-destructively restores preview on capture failure. The UIKit strip decodes exactly 13 indexed JPEGs off-main with cancellation, keeps them stable across trim revisions, and overlays adjustable global handles with an epsilon-safe exact 1s minimum. Live drag keeps handles active, pauses and exact-seeks only the changed edge; terminal save blocks other actions, persists once from the captured revision and resumes from the lower bound using current playback intent. Composition playback appears before thumbnails, then advances monotonically from empty to repeated frame 0 to all 13 exact frames without disturbing trim state. Circle tap and VoiceOver activation toggle mute separately from Play/Pause; a visible mute badge and scoped playback audio session track every-loop re-mute and reciprocal Media takeover. Navigation/relaunch restores the originating chat’s draft and stored reply; final send rejects aggregate selections below 1s, materializes the selected range and transfers the durable origin explicitly. A transformed time-0 frame from that materialized MP4 becomes a quality-0.4, ≤320px, <200KB JPEG `InputThumbnail`; real-image/dimension validation falls back to nil, while valid JPEG ownership persists beside the MP4 through retry/relaunch and terminal cleanup. Recording→send adoption is idempotent by durable origin ID and adopt+begin holds one actor lease. Runtime reservations cover draft/origin/file aliases; terminal cleanup first persists a relaunch-safe tombstone, confirms recording-manifest deletion, then removes send authority. Any failure leaves both durable authorities for retry, including missing-media and registered-success recovery. Timeline video-note bubbles are circular, cancellably downloaded, thumbnail-backed, offscreen-paused and locally playable with reciprocal audio arbitration; secret notes call `openMessageContent` before hold-to-reveal. `./test.sh`/`./run.sh` pass. Probes prove 1.0s A/V, round/orientation pixels, concurrent drain, pre-video audio, crossfade/audio-retime, limits/cancel, decoded segment/PCM order, exact thumbnail times, global trim, legacy manifests, same-origin dedupe/barrier, atomic enqueue, durable/corrupt-thumbnail handling, removal-tombstone relaunch and send success/failure races. idb proves voice↔video toggles, real permission/camera-unavailable routing and exact cleanup; Simulator has no camera, so hardware capture/flip/flash remains unproved. |
| P0 | VOD before full download, range seek/refetch, PiP | pre-Liquid `ChunkMediaPlayerV2.swift`, `ChunkMediaPlayerDirectFetchSourceImpl.swift`, and `UniversalVideoGalleryItem.swift` native PiP lifecycle | `downloadFile(offset:limit:)`, `getFileDownloadedPrefixSize`, `getFile`, `updateFile`, `cancelDownloadFile`, `updateDeleteMessages` | **partial — inline/fullscreen native VOD + owner-scoped PiP + production FFmpeg range playback**: each injected TDLib client owns its file coordinator and private update streams. Reads cap at 256 KiB, probe 512 KiB, fetch 2 MiB, reuse overlap, cancel disjoint/stale generations, distinguish cached/buffering/offline/retryable/terminal state, and never treat `expectedSize` as EOF. Refcounted leases share a source and only the last current lease cancels. FFmpeg 9 custom AVIO uses a 64 KiB buffer, exact checked seek/size callbacks, named blocking threads, shared raw-PTS A/V timeline and ≥10s packet lookahead. One persistent demux/codec/SWR session now spans soft rolling horizons within each seek generation; crossing frames are emitted whole, sparse per-track packets use a globally ordered bounded FIFO, pause retains the session, and seek/offscreen/cancel replace it terminally. Decoder reads share the source's cancellable serialization gate, retry transient displacement, retain stream-probe packets, cap allocation/read/packet work, decode bounded windows to owned BGRA and 48 kHz interleaved float frames, drain codecs/SWR at EOF, clip output to `[seek,target)`, and terminate deterministically on supersession/cancel. Apple-decodable non-secret MP4/M4V/MOV uses strict custom-scheme `AVAssetResourceLoader` metadata and serialized ≤256 KiB reads; `LocalMediaPlayer` retains the asset/delegate/lease, explicitly manages a 1s playable threshold and 10s forward buffer, preserves 0.5×–2× rate, and adopts raw AVKit pause/play/rate/EOF intent without rebuffer restart races. WebM/Matroska routes through the rolling sample-buffer controller for range-capable public media and through full-download-then-FFmpeg for secret/non-streaming media; completed files re-enter the same FFmpeg backend instead of AVPlayer. Fullscreen gallery preserves start time and exact thumbnail until first frame, exposes generation-safe fallback/Retry plus a full-width UIKit blur footer with play/pause, ±15s, duration, disjoint loaded ranges, terminal scrub, mute, rate, auto-hide and VoiceOver seeking. Serialized loader and typed FFmpeg failures distinguish buffering/offline/retrying/terminal failures; generation-guarded publisher bindings prevent canceled or replaced backends from publishing stale state. Offline/timed-out VOD preserves the playhead and retries through a fresh range session without forcing a full download, while terminal decode failures retain generation-safe full-download fallback. A message-scoped owner now retains the exact view/layer/player/resource-loader/TDLib lease across standalone timeline, grouped album tiles, fullscreen and PiP. Inline videos are muted aspect-fill with controls hidden; only the greatest-visible-area owner is active, using the real standalone or mosaic-tile frame, and inactive owners defer all local/VOD/full playback loading. Every album video owner is transferred into gallery as one account-scoped set, preventing a second neighbor player/lease when paging, and every borrowed owner returns to its exact tile. Generation-scoped attachment tokens reject stale cell callbacks after reparent, diffable pruning uses current visible child message IDs, borrowed dismissal/PiP stop returns the same item and playhead, and offscreen owners pause then release. Standalone and grouped media open and close through UIKit-only exact source transitions: the exact bubble/tile is captured synchronously before owner reparent, clipped through every ancestor into explicit window coordinates, rasterized without play/status overlays, and animated into the aspect-fit gallery rect with its corner mask. Dismiss resolves the current selected stable ID afresh; stale/reused/offscreen/deleted/PiP targets fade, generation-safe cleanup cannot mutate a reused cell, and owner return happens only after successful transition completion under the hidden source. Rotation re-centers the same selected message. Timeline, album and prefetch thumbnail paths never use the whole video as fallback. Gallery neighbors remain bounded to central ±1. Native `AVPictureInPictureController(playerLayer:)` is manual, hidden for secret/looping/noncentral/unready/unsupported media, and owned outside cells. A token-scoped movie-playback audio session restores partial failures without deactivating another owner, hands raw controls to external transport, and relinquishes on Media takeover. The singleton transfer coordinator retains active PiP across gallery dismissal, re-presents the exact account/chat/message with the same owner/session, waits for presentation teardown, and restores the exact item without flash. Pending start and stop have bounded generation/timeouts; coordinator authority is retained while AVKit remains active. Permanent deletes arrive on the injected client's private stream, revoke matching chat/message PiP and restoration, while deleted noncurrent neighbors update in place. `./build.sh build` passes without warnings. The SHA-pinned simulator decode probe emits 24 VP9 frames and 96,000 stereo-Opus sample frames with monotonic timestamps, exact post-seek output, codec/SWR tail drain, finite `downloadFile` ranges, zero full downloads, supersession and cancellation. The gallery-owner idb probe additionally proves `ffmpeg-route=true`, exact controller/playhead continuity, preserved offscreen intent, finite ranges, cleanup and the unchanged native MP4 owner path. Existing simulator proofs also cover partial cold playback, local/external controls, range cancellation, loaded ranges, offline retry, exact inline→fullscreen→inline view/item/playhead continuity, zero transfer-cancel delta, terminal lease cancellation, exact clipped/fresh standalone and album-tile geometry, single active tile arbitration, dismissal retention, delete revocation and readiness gating. This simulator reports `pip-supported=false`, so active PiP/background/system-control/restore behavior still requires a PiP-capable device proof. Persistent FFmpeg sessions and sample-buffer PiP transport/lifecycle are simulator-proved; actual system PiP/background/restore remains a physical-device proof gap. Livestreaming is excluded. |
| P0 | Exhaustive message content and actions | pre-Liquid `ChatMessageReplyInfoNode`, `ChatMessageForwardInfoNode`, `ChatMessageSelectionNode`, `ChatMessageSelectionInputPanelNode`, `PeerSelectionController`, contact/map/poll/action nodes, and `ServiceMessageStrings` | all 104 TDLib 1.8.66 `MessageContent` cases; `MessageReplyTo`, `TextQuote`, `MessageForwardInfo`, `ForwardSource`, `getMessageProperties`, `forwardMessages`, `searchChats`, `searchChatsOnServer`, file/poll/edit/copy/reply/delete APIs | **partial — exhaustive catalog + core cards + reply provenance + real Forward/select**: the 104-case no-default catalog drives timeline/chat-list summaries, captions and accessibility. UIKit covers attachments/albums, contact, MapKit location/live expiry, poll/quiz, emoji/dice fallback, service and unsupported rows. Reply/forward metadata preserves chat-scoped IDs, source/origin, inline and ID-zero fallback, thumbnails, PSA, manual quote text/UTF-16 position and unavailable/story state. Manual quote authoring emits a bounded entity-safe `InputTextQuote`; external/story overrides survive text/photo/voice/video/draft paths. Classic reply expands 5→50 lines before navigation, exact destination text highlights after `willDisplay`, and forward taps prefer source message/chat with account-safe cross-chat routing. Context Forward expands the complete album; Select owns stable outer IDs while every action expands, de-duplicates and strictly sorts real child IDs with a 100-message cap. The classic UIKit mode uses full-row taps, a 28pt check at x=6, 42pt incoming-only shift, message-count navigation state, full-width safe-area blur actions and exact per-child TDLib capability refresh. Multi-delete revalidates revoke scope. The full-screen UIKit Forward picker supports Saved/main/archive/server discovery, multiple ordinary chats and multiple explicit topics in the same forum, sender/caption modes, secret-copy rules, per-content/topic permissions, account generations and partial outcome safety. Builds are warning-free; deterministic device proof is recorded below. Forward comments, native two-finger range selection/autoscroll, timeline spoilers, link previews and rich-message rendering are now implemented; see the September 5 follow-up below. Remaining P0: positional null-result support in pinned TDLibKit, resolved service actors/pinned targets, poll voters/media, insertion-aware/slot dice and game/story/checklist UI. |
| P0 | Message reactions | pre-Liquid/current `ReactionButtonListComponent`, `ChatMessageReactionsFooterContentNode`, `ChatMessageBubbleItemNode` and `ChatController` reaction flow | `MessageInteractionInfo`, `MessageReactions`, `getMessageAvailableReactions`, `addMessageReaction`, `removeMessageReaction`, `updateMessageInteractionInfo`, `updateMessageUnreadReactions`, `readAllChatReactions`, `readAllForumTopicReactions` | **implemented ordinary/explicit-topic breadth** — UIKit renders TDLib emoji/custom-emoji reactions as sorted 30pt chips with 20pt icons, exact 6pt wrapping, selected/unread state, compact counts, incoming/outgoing/center alignment, VoiceOver labels/actions and offscreen-paused TGS/WebP/WebM custom emoji. Existing album reactions stay on the representative bubble. A 46pt reaction strip sits above the extracted message, prioritizes recent reactions, displays emoji/custom emoji, and supports tap or drag selection. Every add re-fetches authoritative availability, allows Premium items only for Premium accounts, excludes paid/Stars types, honors unavailability and chat maximum count; chosen non-paid reactions remain removable under new restrictions. Generation-safe optimistic state rolls back failures; normal-user interaction/unread plus chat permission/availability updates reconcile under captured account/client guards. Explicit-topic rendering/picker/mutation validates the current `ChatLocation`, and acknowledgement uses `readAllForumTopicReactions`. Deferred polish: expanded reaction grid/search, reactor list/recent avatars, disappearing-chip animation and live server mutation smoke. |
| P0 | Pinned messages | pre-Liquid/current `ChatInterfaceStateContextMenus`, `ChatControllerLoadDisplayNode`, `ChatPinnedMessageTitlePanelNode` and message-window navigation | `Message.isPinned`, `MessageProperties.canBePinned`, `getChatPinnedMessage`, `pinChatMessage`, `unpinChatMessage`, `updateMessageIsPinned`, `updateDeleteMessages` | **implemented ordinary-chat newest-pin breadth** — initial and refreshed state comes only from account/client/generation-fenced `getChatPinnedMessage`; only confirmed 404 clears while transient failures retain the last authoritative banner. Permanent non-cache deletes and authoritative unpins clear before refetch, edits/content refresh the preview, and stale mutation/fetch/animation completions are revision-gated. Context Pin/Unpin uses freshly fetched `canBePinned`, one chat-serialized optimistic transaction and exact Saved/private/group/channel notification/scope modes. A classic full-width 50pt UIKit banner shares one background with the navigation bar, shares spoiler-safe reply thumbnail extraction, locally hides by newest message ID, resurfaces for a newer ID, preserves the inverted timeline offset, and taps through existing history-window navigation. Dynamic Type is capped to the fixed panel geometry and VoiceOver exposes separate Open/Hide controls. Forum/view-as-topics/direct-message groups, albums and sending/service messages are explicitly gated. Proof is recorded below. Deferred parity: nearest-visible pin rotation, pinned-only list/pagination, admin undo and older-pin warning detail. |
| P0 | Forum topics: list, explicit writes and all-messages timeline | pre-Liquid/current `ChatListNodeLocation.swift`, `ChatMessageItemImpl.swift`, `ChatMessageDateHeader.swift`, `ChatInterfaceStateInputPanels.swift`, `ChatControllerMediaRecording.swift` and `ChatControllerLoadDisplayNode.swift` | `MessageTopic`, `ForumTopic`, `getForumTopics`, `getForumTopic`, `getChatHistory`, `getForumTopicHistory`, `updateForumTopicInfo`, `sendMessage`, `sendMessageAlbum`, `setChatDraftMessage`, `sendChatAction` | **partial — explicit-topic breadth + production all-messages composer routing** — runtime identity is `(accountID,clientID,chatID,MessageTopic?)`; exact topic list/history/search/update and immutable explicit-topic write context remain. `Chat.viewAsTopics` authoritatively selects topic list (`true`) versus base history (`false`). Base history renders stable adjacent-topic headers, preserves raw pagination/album identity and visible message+pixel anchors, and excludes headers from message-only behavior. Text/photo/edit use discovered General without reply or the replied message's exact topic, reject closed-topic replies, and always store/clear the route draft with `topic:nil`. Voice/video now snapshot that same destination+reply at recording start, persist it separately from the base draft key through preview/relaunch/retry, revalidate live metadata/permissions before enqueue, and route record/upload/cancel actions through the frozen topic. Warning-free build proof is recorded below. |
| P0 | Topic composer durable media identity | pre-Liquid/current `ChatInterfaceState.swift`, `ChatControllerMediaRecording.swift` and thread-scoped interface-state ownership | `MessageTopic`, `InputMessageVoiceNote`, `InputMessageVideoNote`, `updateMessageSendSucceeded/Failed` | **implemented write foundation** — `ChatDraftKey(accountID,chatID,MessageTopic?)` remains the on-disk route/draft owner across voice/video recording, preview, send, retry and outcome reconciliation, while the four version-tolerant manifests persist a separate immutable `sendTopic` for all-messages General/reply routing. Runtime-only TDLib client IDs remain excluded. Stores restore/deduplicate/enqueue/discard by route destination; enqueue and chat actions use the frozen send topic and reply, with live closed/permission checks and account/client fences. Outcome files use draft UUID rather than colliding chat/message IDs. A one-time account-registry migration snapshot may claim unambiguous legacy base drafts; legacy records without `sendTopic` remain valid but cannot be guessed into an all-messages destination. Runtime proof is below. |
| P0 | Forum-aware Forward destinations | pre-Liquid/current `ChatControllerForwardMessages.swift` and `PeerSelectionController.swift` | `getForumTopics`, `getForumTopic`, `forwardMessages(topicId:)` | **implemented breadth** — destination identity is `(chatID, MessageTopic?)`, so ordinary chats and multiple topics in one forum coexist in one selection. Forum rows drill into an exact-cursor UIKit topic picker; closed/hidden topics require creator/manage-topics authority and every content permission is rechecked at delivery. Source account/topic membership is fetched both at preparation and immediately before mutation. TDLib results must have exact count/chat/topic; transient forum metadata failures disable rather than fall through to General. Classic full-width material headers, plain Back and table-header search avoid iOS 26 floating glass. Live idb proof selected a real forum topic locally without pressing Forward. |
| P0 | Composer and send/delete transitions | pre-Liquid chat input panel and message transition paths | `FormattedText`, `InputMessageContent`, `sendMessage`, edit/reply/delete APIs | **partial** — one UIKit floating blur island owns formatted text, emoji insertion, non-Premium installed stickers, saved GIFs, photos/camera, security-scoped multi-file documents, reply/edit and voice/video states in ordinary, explicit-topic and all-messages chats. Sends serialize to prevent duplicate rapid-tap delivery and clear UI only after TDLib acceptance. Real UIKit snapshots of visible reply/text/photo/album/document/voice/video-preview-or-retry sources follow temporary→final IDs and fly into canonical insertion; viewport anchoring remains independent. Sticker/GIF sends use exact permission/topic/reply contexts, captured draft cleanup, account-fenced search, offscreen-paused/cancelled media and no Premium/Stars results. Voice/video retry authority and document upload leases survive UI teardown. Full-bubble deletes fade+slide then collapse under a surviving anchor; no dust/particles. Custom-emoji authoring now includes a TDLib search picker, animated inline input, UTF-16 entities, adjacent-emoji separation, copy/paste and draft restoration. Remaining: public inline-GIF search. Formatted forwarding comments are implemented, retained across destination search/topic selection and sent before forwarding with retry deduplication; actual delivery still needs an end-to-end run. |
| P1 | Profiles, shared media, fullscreen gallery | pre-Liquid/current `PeerInfoScreen.swift`, `PeerInfoAvatarListNode.swift`, `PeerInfoPaneContainerNode.swift`, `PeerInfoScreenOpenMessage.swift` and gallery controllers | peer/full-info/status/title/photo updates; `getUserProfilePhotos`, `getBasicGroupFullInfo`, `getSupergroupMembers`, `getChatAdministrators`, `getChatMember`, `getMessageProperties`, topic/history APIs, `downloadFile`, `forwardMessages`, `deleteMessages`, `setName`, `setBio`, `setChatTitle`, `setChatDescription`, `setChatMemberTag`; message/file APIs | **partial — live UIKit profile + shared/avatar galleries + management/actions** — account-fenced user/bot/self/group/channel profile exposes live title/status/bio/usernames/phone/member/photo state and Media/Files/Links/Audio. Separate Members/Admins lists retain server order and roles, paginate raw supergroup offsets, react to membership/full-info changes and preserve a visible-row anchor; permission-gated self/chat Edit uses changed-only sequential writes, live cached visibility and exact pre-write member-rights revalidation. User rows open a standalone tag editor whose fresh self/other-member authority matrix, stale-baseline conflict check and awaited write follow current Telegram behavior without coupling tags to administrator rights. Shared media retains the profile under exact-source append-paged gallery with cancel-safe pan, unified video chrome, scrollable formatted/spoiler-safe captions and authoritative totals. Gallery Open in Chat captures the selected identity, re-fetches it through the captured client, revalidates account/client/topic through fade-dismiss completion, then routes into the source timeline without competing reverse transitions. Save and system Share now share one original-resource export boundary with fresh copy-protection checks, full TDLib download, account/generation fences and managed temp ownership; Photos receives signature-validated still images/GIF/MP4 and WEBP sticker frame PNG without moving TDLib cache files. Forward reuses the production topic/destination/comment picker and offers selected-item versus authoritatively bounded whole-album semantics. Delete intersects fresh per-ID modes, repeats pre-write authority, commits one batch and coalesces all-media permanent updates into one terminal fade without returning deleted playback/PiP owners. Header avatar opens a real-`ChatPhoto` gallery with user/bot/self role-aware raw-offset history, group/channel current full-info photo, exact item+file transition, zoom and no-flash central muted video loop. Generic Saved Messages self now preserves upstream title/blank-status/action semantics while rendering the captured account's real avatar and gallery instead of the Saved glyph. Typed peer/full-info bursts coalesce into one render; generation fences prevent stale `getChat`/full-info resurrection; role signatures reconcile populated avatar galleries without dismissing them. Warning-free proofs are below. Remaining: promote/demote/remove management tools and exhaustive profile actions. |
| P1 | Multiple accounts | Telegram account manager behavior without copying Postbox | separate TDLib clients and databases, authorization state, `logOut` | **implemented** — isolated TDLib clients/databases/subscriptions and persisted account registry with add/auth/switch/remove/logout. A fresh comprehensive multi-account runtime pass remains pending. |
| P1 | Chats, folders, archive, search, edit/reorder | pre-Liquid `ChatListItem.swift`, chat list/filter controllers | chat lists/positions/folders, pin/mute/read/delete/clear/draft APIs | **partial** — main/archive/custom-folder lists now consume ordered TDLib updates and page through loadChats to explicit 404 exhaustion; folder tabs retain the approved Liquid Glass capsule over full-width background blur, and chat cells use contiguous Telegram geometry with date, delivery, unread/mute/pin state and account-backed actions. Remaining: edit/reorder/include/exclude completeness, clear history/draft parity, archive reveal gestures, richer delivery/typing states and mutation account fencing. |
| P1 | Timeline stability and performance | pre-Liquid/current `ChatMessageItemImpl.swift` and `ChatMessageDateHeader.swift` history/header behavior | `getChatHistory`, `updateNewMessage`, `updateDeleteMessages`, file updates | **partial** — stable message/album/topic/date IDs, raw-history pagination cursor, cross-page album merging, message-only prefetch/read/selection and visible `messageId + pixelOffset` restoration cover structural snapshots. Composer/keyboard insets, object-driven and autonomous cell self-sizing, bulk reconfigure, Dynamic Type and rotation now capture the same anchor or latest edge; mutation depth discards stale deferred anchors and never fights active dragging. Every chat emits one stable localized date row per day with exact date→topic ordering. Remaining proof/gaps: a live pagination/album seam, software-keyboard-attached runtime proof and eliminating residual metadata work from the main actor. |
| P2 | Shell/navigation polish | pre-Liquid navigation and `ChatListItem.swift`; approved BetterTG glass folder/menu baseline `64625ed^` | n/a | **implemented shell/list breadth** — the folder bar keeps edge-to-edge `systemChromeMaterial` through the safe area behind an inset 42pt Liquid Glass capsule and continuously moving glass selection. Shared context menus use `UIGlassEffect` with 30pt menu and 20pt highlight corners. Later folder/menu actions, unread state, localization and gestures remain. Chat-list rows retain contiguous 76pt full-width geometry with 60pt avatars at x=10 and separators from x=80. Warning-free build and real-state idb proofs are recorded below. Remaining P2: audit secondary navigation/search/action surfaces while preserving the explicit glass exception. |

### Checkpoint

- Active continuation: `codex/parity-continuation` in worktree `31df/BetterTG`. The complete first media/parity
  history through `5d990c1` and all 44 continuation commits through `7b0699d` are retained, including member tags.
  The integration merges `1d9d80a`, which contains local `main` at `6dd705c` and TDLibKit 2.0.0.
- Native compatibility preserves account/topic-scoped composer and media drafts, profile permissions, gallery actions and
  persistent FFmpeg sessions. Legacy archive adapters preserve formatted text, quotes, replies and all MessageTopic variants;
  native value equality preserves reaction/avatar change detection. Generated aliases exclude application-owned types such as
  `ChatLocation`. Chat open/close transitions are serialized per account/client/chat.
- Timeline invariants: raw TDLib pagination owns the cursor; complete pages are hydrated without skipping an unconsumed item;
  canonical album/date/topic identity and visible message + pixel-offset restoration remain in the continuation.
- Verification: Xcode 26.6 / iOS 26.5 build `.build/logs/xcodebuild/build-Debug-20260905-162801-7759-9727.log` has no warnings.
  PID `5795` passed fresh legacy draft coding, Ogg/Opus, account/topic-isolated voice drafts, frozen-topic video send/recording
  drafts and persistent VP9/Opus range playback probes. Results are app Documents probe files; UI evidence is under
  `.build/ui-probe-evidence/parity-merge-20260905/`.
- UI navigation passed chats → chat → profile → Members → profile → shared photo gallery → profile → chat → chats.
  Member rows enter the tag editor; the available account's permission-denial path is expected. Authorized tag Save/remove
  and other server mutations remain unverified. The later feature checkpoint remains promote/demote/remove and admin-rights
  editing, independent of the existing tag flow.
- Fixed the inherited profile header-width defect: centered labels now use the full header content width, consistent with
  Telegram upstream `PeerInfoHeaderNode`'s screen-width-based text layout. On iPhone 17 Pro / iOS 26.5, a long group title
  changed from x=154 / 94×54.67 pt (split and truncated) to x=20 / 362×26.67 pt (complete on one line); avatar remains 96×96 pt.
  Evidence: `03-profile` versus `14-fixed-profile` PNG/JSON in the UI evidence directory above. At that checkpoint, PID `8105`
  was running on the corrected profile; action buttons and media grid were unobscured.
- Generator cleanup: `td.py` moved to `script/td.py`; the wrapper, repository-root calculation, generated header and both
  agent documents use the new path. The final warning-free build exercised the relocated generator with the existing package cache.

#### Liquid Glass folder picker and context-menu restoration — 2026-09-05

- User request: restore the existing folder picker and context-menu UI from before the parity classic-shell conversion;
  retain any later behavior and action work. The exact visual regression is `64625ed`.
- Reversed only that commit's styling hunks in `MainView.swift` and `TelegramContextMenu.swift`. The folder picker again has
  a 42pt glass capsule inset 16pt, a clipped scrolling viewport and a moving glass selection over the full-width background blur.
  Menus again use regular Liquid Glass, 30pt outer corners and 20pt selection corners. The shared menu source matches `64625ed^`.
- Retained later localization, TDLibKit 2 migration, forum routes and folder reselect scroll repair. Folder actions, unread
  badges, page transitions, extracted previews, keyboard hosting and context action handlers are unchanged by the restoration.
- Build: SwiftFormat checked both changed Swift files; `./build.sh build --simulator-id 8108A92F-7E93-49C8-87F4-FA53A5A40A99`
  succeeded on Xcode 26.6 / iOS 26.5 with zero warnings or errors. Log: `.build/logs/xcodebuild/build-Debug-20260905-163828-11292-31865.log`.
- Runtime: launched through `./build.sh run --skip-build` on the same iPhone 17 Pro / iOS 26.5 (PID `12092`).
  CLI idb/simctl captures show the restored glass picker, folder tap loading channels, content swipe returning to All, strip
  scrolling that fully reveals the groups badge and later tabs, and groups selection centering its glass capsule. Before/after
  PNG/JSON evidence is under `.build/ui-probe-evidence/glass-restore-20260905/` (01/02/04 before, 05–14 after).
  Reselecting groups returns the scrolled list to the first pinned row; the shared folder menu shows all six actions in the
  restored glass surface, and Edit Folder opens the correct configuration and returns via Back without saving. No new control
  clipping or overlap was found in this bounded smoke. App remains on the groups list with the picker visible.
  `SMOKE.md` records the exact checks and limits: separate chat/message menus were not repeated after restoration and no
  server mutation action was submitted.

#### UIKit peer profile and shared-media slice

- **P1 flow:** pre-Liquid/current peer-info header, pane and open-message behavior from `PeerInfoScreen.swift`,
  `PeerInfoHeaderNode.swift`, `PeerInfoPaneContainerNode.swift` and `PeerInfoScreenOpenMessage.swift`, adapted to UIKit + Combine +
  TDLibKit without Telegram infrastructure.
- Implemented: chat title/avatar entry; user/bot/self/basic-group/supergroup/channel identity; full-info bio/description,
  username/phone/member details; Message/Search actions; one scrollable Dynamic Type header; Media/Files/Links/Audio tabs; exact current
  `MessageTopic` query scope and open-in-chat route; stable deduplicated pagination; empty and later-page retry without losing the cursor;
  account/client fencing; cancellable grid thumbnail download with redisplay restart; accessibility labels and intrinsic action height.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-105649-495-22414.log`; focused source/delta review clean. Runtime PID
  `840` exposes Profile/Back, exactly one `4 members`, 56.67pt intrinsic Message/Search actions, the four-tab group, 12 visible Media
  tiles, `No shared files`, real Link rows and a real `.m4a` Audio row. The exact Media→Files→Links→Audio path remains alive after fixing
  UIKit diffable snapshot reentrancy, and Back returns to the group chat. Evidence is under
  `.build/ui-probe-evidence/profile-shared-media-*`; no media or server mutation was selected.
- Deferred: avatar/video header history and fullscreen entry; edit/member/admin controls; shared-media selection/actions; live metadata
  reconciliation; gallery caption, gesture, rotation and complete save/forward/delete/open-in-chat/video-control parity.

#### Profile shared-media gallery slice

- **P1 flow:** peer-info media pane → production gallery from current/pre-Liquid `PeerInfoPaneContainerNode.swift` and
  `PeerInfoScreenOpenMessage.swift`, retaining the `ChatLocation` history source and a fresh visible transition provider.
- Implemented: Media-only gallery routing while Files/Links/Audio keep open-in-chat; exact thumbnail snapshot without the video badge;
  represented-ID + visible-cell + account validation; profile retained beneath the modal; newest→oldest selected-ID-stable append-only
  pages; one in-flight mutation queue; boundary retry; no reload jump; active-account fencing before cell/VOD/PiP creation; release and
  fade on account switch; active-client permanent photo/video delete reconciliation; selected-delete forced fade. The footer is one
  full-width `systemChromeMaterialDark` surface through the bottom safe area with plain 52×50 Close/Share and a nontruncating index.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-111604-5080-25531.log`; final source/delta review CLEAN. PID `5495`
  opened the first profile tile as `1 of 30`, paged to the exact full `2 of 30`, then Close returned to Profile with the original
  131×131 source tile still present. AX proves `gallery-close`, `gallery-counter`, `gallery-share` on the full-width footer; screenshot
  `.build/ui-probe-evidence/profile-gallery-authoritative-classic-footer.png`. No Share or server mutation was performed.
- Deferred: avatar/photo-video header history, interactive pan-dismiss, captions, save/forward/delete/open-in-chat,
  rotation/current-item runtime proof, and deliberate near-page-boundary/error/account-switch/delete smoke.

#### Unified fullscreen gallery chrome slice

- **P1/P2 flow:** current/pre-Liquid gallery single-tap chrome and video-control coordination, adapted to UIKit recognizers without
  importing Telegram transition/gesture infrastructure.
- Implemented: controller-owned `chromeIsVisible`; edge-to-edge pager behind a full-width safe-area blur overlay; photo single tap
  dynamically waits for nested double-tap zoom; controls/retry/seek touches are excluded; selected video disables its private tap and
  reports controls visibility/auto-hide through its playback owner to the same footer/status state; page/reuse/dismiss/PiP bindings are
  explicit. VoiceOver can never leave Close/Share hidden, hidden footer leaves AX, Reduce Motion is honored, and accessibility Escape
  closes. Video controls stay exactly above the 50pt footer plus bottom safe area instead of being obscured by the overlay.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-113041-8640-9218.log`; final delta review CLEAN. PID `8944` proved
  photo chrome `visible→hidden→visible` (`402×874` media when hidden), video single-tap exposing seek/back/play/forward/mute/rate plus
  `gallery-close`/`2 of 30`/`gallery-share`, playing auto-hide removing both control groups from AX, and Close returning to Profile.
  Screenshot: `.build/ui-probe-evidence/profile-gallery-unified-video-controls.png`; no Share or server mutation occurred.
- Deferred: deliberate double-tap/pinch and VoiceOver-status runtime toggles.

#### Guarded interactive gallery dismissal slice

- **P1 flow:** Telegram current/pre-Liquid down-swipe gallery dismissal, adapted to the existing exact-source UIKit animator through
  `UIPercentDrivenInteractiveTransition` without importing Telegram gesture/transition infrastructure.
- Implemented: one-finger, positive-y, 1.2× direction lock; exact centered-page requirement; minimum photo zoom with no zoom bounce or
  deceleration; horizontal pager cooperation; temporary pan/pinch suspension only after begin; touch exclusion for footer, every
  `UIControl`, visible video controls and Retry; active seek/PiP/start/stop/retention rejection. Progress is translation-driven; 28% or
  900pt/s finishes, otherwise cancel restores chrome, modal AX isolation, pager/zoom gestures and pending page/delete updates. Playback
  owners release only from the animator's completed commit. Account switch force-finishes the interaction and pops the profile from the
  transition completion; an unexpected cancel uses a terminal nonanimated fallback instead of leaving an invalid gallery visible.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-114920-12706-5954.log`; final delta review CLEAN. PID `12991` proved a
  slow 70pt/1s down-pan cancels with only gallery AX and restored `gallery-close`/`1 of 30`/`gallery-share`; a 450pt/0.4s down-pan finishes
  at Profile with the exact 131×131 source tile; horizontal swipe still reaches `2 of 30`; up-swipe remains in gallery. No Share or
  server mutation occurred; Simulator remains booted.
- Deferred: deliberate zoomed-photo, live seek, active PiP and external account-switch gesture rejection on capable/runtime states.

#### Fullscreen gallery caption and total-count slice

- **P1 flow:** current/pre-Liquid gallery caption footer, spoiler/entity interaction and absolute position index, adapted to UIKit TextKit
  and the existing TDLib message stream.
- Implemented: formatted photo/video/animation captions; validated UTF-16 entities; scaled bold/italic/code runs refreshed on content-size
  changes; 44…220pt scroll container (96pt compact cap) rather than truncation; scroll position per selected message; caption-scroll hold
  that keeps unified chrome/video controls visible until return to top. Dynamic caption height raises the 136pt video controls above
  `50 + captionHeight`. Spoilers are opaque before reveal, redacted from AX, reveal by hit-test or AX action, then publish non-hidden
  URL/email/phone/mention AX actions. Concealed `textUrl` destinations compare normalized scheme/host/default-port/path/query/fragment
  and require an explicit URL confirmation when they differ. Profile listens to active-account content/edit updates, generation-serializes
  `getMessage`, preserves topic scope, and reconfigures same-ID captions. Profile search passes TDLib `totalCount`; loaded-page appends and
  deletes update messages before re-clamping that total.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-121611-18495-8647.log`; final source/delta review CLEAN. PID `18804`
  exposes a real `Caption, …` label at 378×28 and `1 of 88`; captioned video proof shows scrub/transport entirely above
  its caption, with footer below. Screenshots: `.build/ui-probe-evidence/profile-gallery-caption-entities-final.png` and
  `.build/ui-probe-evidence/profile-gallery-caption-video-controls.png`. No entity URL, Share or server mutation was activated.
- Runtime blockers: reachable sampled captions contain no spoiler or concealed `textUrl`, and no long caption was safely selected, so
  reveal/confirmation/scroll-hold are source-reviewed and build-proved but not deliberately exercised on account data.

#### Real profile avatar gallery slice

- **P1 flow:** current/pre-Liquid `PeerInfoAvatarListNode` → `AvatarGalleryController`, adapted to UIKit and native TDLibKit models rather
  than synthetic timeline messages.
- Implemented: header 96pt image/button AX only when a real effective/full photo exists; a true placeholder remains image-only. User/bot
  payload preserves effective/personal/normal/history/trailing-public roles with stable `ChatPhoto.id` dedupe, keeps raw history offset
  independent of extra role entries, inserts later 100-photo pages before public fallback and exposes footer Retry. Group/channel use the
  only available TDLib source, `BasicGroupFullInfo.photo` / `SupergroupFullInfo.photo`; `ChatPhotoInfo.big` is a static fallback only and
  never fabricates an animation. A separate UIKit pager keeps stable photo IDs/current page through rotation, exact-animates the whole
  circular header only for the current item and fades historical items. Captured-client synchronous JPEG/MP4 requests have per-file
  generations and no global update bus; 96MB/cost-limited decoded cache; static image remains until `AVPlayerLayer` ready; animation seeks
  to `mainFrameTimestamp`, loops muted only central, pauses/resets offscreen; nested pan activates only above 1× while pinch/double-tap
  remains available. Late network completions require current account, visible/top profile and no competing presentation.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-124706-24968-7861.log`; final source/delta review CLEAN. Runtime PID
  `24630` exposes `<group> profile photo` as 96×96 button, opens real `Profile photo, Mar 19, 2026` in the modal pager with plain
  `avatar-gallery-close`, then restores the exact 96×96 source. Screenshot:
  `.build/ui-probe-evidence/profile-avatar-gallery-final.png`; no mutation occurred.
- Blockers/deferred: current safe group has one static photo, so user >100 pagination, animated avatar loop and zoom gestures are not
  runtime-proved. TDLib cancellation is global per client/file; without a cross-consumer lease coordinator, offscreen deliberately
  cancels only local await/decode/playback work and lets active transport finish into TDLib cache rather than cancel another consumer.

#### Generic self avatar source slice

- **P1 flow:** Telegram current/pre-Liquid generic self info opened from Saved Messages, explicitly distinct from Settings/My Profile.
- Implemented: self is captured once only when a non-nil account user ID equals the peer. Generic self title remains `Saved Messages`,
  presence is blank, redundant Message is hidden, and Search/Edit remain. `ProfileAvatarView` can render the real self peer file over the
  Saved glyph only for this captured profile context. The explicit image path owns account/client/user identity, waits for the full file
  through that client, uses no global `updateFile` bus, never cancels shared TDLib transport, and suppresses every callback after switch.
- Header source follows effective `User.profilePhoto` then main `UserFullInfo.photo`; self `personalPhoto` is ignored and `publicPhoto`
  never becomes current. Gallery ordering is effective current → distinct normal/history → distinct public last. Raw history offsets stay
  server-owned, extra-role count is separate, and pages insert before public without moving the selected item. Transition to/from the
  header requires both exact photo ID and rendered file ID; otherwise it fades. Main/personal/public role signatures trigger a full-page
  reconcile that preserves a historical selection; reconciliation, pagination and initial open have independent UUID-owned task slots.
  An authoritative empty set closes/resets the pager instead of preserving stale media.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-152230-76740-9666.log`; final upstream/API/task-race review CLEAN.
  PID `74705` exposed the real cat avatar as a 96×96 `Saved Messages profile photo` button, exact `Saved Messages` title, no status and no
  Message action; Search/Edit and shared tabs remained. It opened real `Profile photo, May 10, 2023` with `avatar-gallery-close` and no
  mutation. Final build PID `77080` launched on the still-booted Simulator. Evidence:
  `.build/ui-probe-evidence/profile-self-avatar-source.png` and
  `.build/ui-probe-evidence/profile-self-avatar-gallery.png`.
- Runtime blocker/deferred: this account exposes one current profile-photo item, so >100 pagination, distinct public fallback, live role
  replacement, authoritative empty close and concurrent request invalidation are source-reviewed/build-proved rather than live-mutated.

#### Live profile metadata slice

- **P1 flow:** Telegram current/pre-Liquid signal-driven peer info data, adapted to BetterTG's active-client typed update bus and UIKit
  state rather than one-shot controller snapshots.
- Implemented: exact account/client and peer-ID guards for chat title/photo, user/status, basic group, supergroup and all three full-info
  updates. User/group payloads replace `CustomChat.type` immediately; title/status/usernames/phone/member noun/count update before any
  network round trip. Full-info payloads directly update bio/description/details/full `ChatPhoto`. Title/photo refetches use one monotonic
  `metadataGeneration`; full-info requests and pushed payloads share `fullInfoGeneration`; cancelled/older responses cannot overwrite a
  newer revision. First full-info hydration does not cancel a legitimate simultaneous avatar open, while later `ChatPhoto.id` changes
  increment avatar identity, cancel initial/history tasks, clear raw offset/dedupe/total, close stale avatar gallery and remove old
  animation authority. One run-loop-coalesced render updates title/status color/bio/details/avatar/placeholder/AX traits+hint/tap
  availability and Dynamic Type header height together.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-130032-28652-16080.log`; final source/delta review CLEAN. PID `29034`
  exposes the stable 96×96 `<group> profile photo`, title, `4 members`, actions, tabs and media after live subscriptions attach.
- Runtime blocker: no deliberate server title/photo/status/full-info mutation was performed on the safe account; update transitions are
  source-reviewed and build-proved, while the runtime smoke is a no-regression readback.

#### Profile member, administrator and edit controls slice

- **P1 flow:** current/pre-Liquid peer-info member/admin panes and creator/administrator edit gates, adapted to UIKit diffable tables and
  TDLibKit without Telegram account or list infrastructure.
- Implemented: a separate intrinsic management row with Members, Admins and permission-gated Edit. Basic groups use the complete
  `BasicGroupFullInfo.members`; supergroups/channels expose Members only under `canGetMembers` and advance pagination by raw
  `ChatMembers.members.count`; Administrators use `getChatAdministrators` independently of hidden-member access. Stable local
  user/chat IDs preserve server order and unresolved fallbacks; one queued resolver batches same-ID reconfiguration through a serialized
  diffable apply; Dynamic Type and VoiceOver include title, role and presence. Live `updateChatMember`/full-info changes debounce a fresh
  authoritative load while retaining the first visible ID and pixel offset. Later-page failures remain visible in a table footer with
  explicit Retry. Account changes cancel child work and atomically remove the complete navigation suffix at the owning Profile.
- Edit captures account/user/client/chat identity. Cached creator or administrator `canChangeInfo` controls visibility, while every chat
  submit calls `getChatMember` for that captured user immediately before `setChatTitle`/`setChatDescription`. Self edit uses
  `setName`/`setBio`. Only changed fields are sent in sequence; successful first operations update the retry baseline, and a second-operation
  failure reports partial success without optimistic canonical state.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-132517-34076-25539.log`; final focused audit has no remaining API/model,
  pagination, diffable or account-lifetime finding after the atomic suffix fix. PID `33583` exposes a separate 176×56.67 Members/Admins
  row on the real three-member basic group; Members resolves exact `<member>, Owner`, `<member>, Member · online`, `лева, Member`, while
  Administrators independently resolves `<member>, Owner`. Screenshots:
  `.build/ui-probe-evidence/profile-management-controls.png` and
  `.build/ui-probe-evidence/profile-administrators-controls.png`. Edit was correctly absent for this non-admin account; no Save or other
  server mutation was performed.
- Runtime blocker/deferred: a safely reachable self/owned test profile was not mutated, so Edit form writes and live permission revocation
  are source-reviewed/build-proved rather than server-proved. Member promotion/removal/admin-right editors remain a later management gap.

#### Member and administrator tag editor slice

- **P1 flow:** current `PeerInfoData.swift`, `PeerInfoScreenOpenMember.swift`, `ChatParticipantRightsScreen.swift` and TelegramCore
  `Ranks.swift` rank editing, compared with pre-Liquid `ChannelAdminController.swift`, adapted as an independent UIKit + TDLibKit tag
  operation rather than an administrator-rights mutation.
- TDLib boundary: captured-client `getChat` plus parallel actor/target `getChatMember` reads before presentation and again immediately
  before one awaited `setChatMemberTag`. Basic groups and non-channel supergroups are accepted; inactive targets and channels fail closed.
  Self editing requires fresh `ChatPermissions.canEditTag`. Editing another user requires creator status or fresh
  `AdministratorRights.canManageTags`; another creator is protected, and a non-creator may edit an administrator only when
  `canBeEdited`. The target tag must still equal the captured baseline before the write, preventing a stale editor from overwriting a
  concurrent change.
- UIKit editor preserves the current tag verbatim, counts at most 16 Swift characters, rejects controls and graphic emoji, accepts empty
  to remove the tag, and keeps transport errors visible without optimistic canonical state. Successful writes explicitly schedule an
  authoritative member-list reload instead of relying on the bot-only `updateChatMember` delivery contract. Account/client changes cancel
  preparation or saving and disable stale controls.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-153759-82885-28094.log`; final focused delta review CLEAN. Runtime PID
  `83599` exposed all three real member rows as enabled buttons with disclosure chevrons and the `Shows member tag controls` hint. Tapping
  self `лева` performed the fresh authority reads and produced `Can't Edit Tag` / `You no longer have permission to edit this member's
  tag.`, then OK returned to Members. Screenshots:
  `.build/ui-probe-evidence/member-tag-smoke-members.png` and
  `.build/ui-probe-evidence/member-tag-smoke-permission-denied.png`. No text was edited, Save was never pressed and no Telegram mutation
  occurred; Simulator remains booted.
- Runtime blocker/deferred: this live account cannot edit a tag, so an authorized Save/remove and post-success refetch are not exercised
  against the server. Promotion, demotion, removal and administrator-right editors remain the next bounded profile-management gap.

#### Fullscreen gallery Open in Chat slice

- **P1 flow:** Telegram current/pre-Liquid gallery context action `Open in Chat`, adapted to the existing UIKit footer and BetterTG
  timeline-window loader without Telegram gallery/navigation infrastructure.
- Implemented: a plain 52×50 ellipsis control alongside unchanged Close/Share on the full-width classic blur footer. The action exists
  only when the presenting route supplies a captured account/client/source location and completion. Tap freezes a Sendable
  chat/message/topic identity, disables the control with progress and calls `getMessage` through the captured client. Completion checks
  action generation, selected ID, account/client, returned identity and exact topic for scoped profiles; base-chat routes intentionally
  accept any forum topic. A permanent delete, page change or account invalidation cancels quietly. Success forces a fade instead of the
  reverse tile transition and retains a separate navigation generation through dismissal; the completion rechecks account/client/context
  before invoking Profile or Chat. Profile pops only after modal dismissal; Chat uses its existing `prepareMessageWindow` path when the
  target is outside the loaded timeline. Secret-chat navigation needs no send/delete/save permission and remains allowed.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-134050-43746-25199.log`; final focused delta review CLEAN. PID `44134`
  exposed exact footer frames `Close 4×790 52×50`, `More actions 294×790 52×50`, `Share 346×790 52×50` and the sole UIKit menu action
  `Open in Chat`. Selecting the first profile item (`1 of 1688`) completed gallery fade and profile removal, returning to
  the source group chat with the exact `Photo, 13:31` bubble visible. Evidence:
  `.build/ui-probe-evidence/gallery-open-in-chat-menu.png` and
  `.build/ui-probe-evidence/gallery-open-in-chat-result.png`; no Telegram mutation occurred.
- Runtime blocker/deferred: the safe smoke did not switch accounts or delete the selected message during the subsecond dismissal window;
  both races are generation-fenced and source-reviewed. Forward and Delete remain separate action slices.

#### Gallery Save and secured Share slice

- **P1/P0 flow:** Telegram current/pre-Liquid gallery media export and camera-roll save, adapted to UIKit, TDLibKit and Photos without
  Telegram media-box/resource infrastructure.
- Implemented: Save and Share serialize with Open in Chat and freeze the exact selected identity. Both perform parallel captured-client
  `getMessage`/`getMessageProperties`, require `canBeSaved`, reject both protected-content flags, paid media, self-destruct state and
  secret one-time photo/video/animation, then resolve the original largest photo or primary video/animation/sticker `File`. A user action
  requests full `downloadFile(limit:0,offset:0,synchronous:true)` and validates exact completion/path; cancellation only drops local
  authority and never calls global `cancelDownloadFile`. Selection/content/delete/account changes cancel before external commit.
- Photos uses `.addOnly`, re-fetches message/properties immediately before `performChanges`, sets `shouldMoveFile = false`, preserves
  creation date and a separator/control-stripped filename, validates images by ImageIO signature and Apple video by MIME plus playable
  AVAsset video track. GIF uses `.photo`, MP4 animation `.video`; WEBP sticker Save exports deterministic decoder frame 0 as PNG.
  TGS/WEBM sticker Save remains honestly hidden. In this initial export slice (superseded by the September 5 Live Photo implementation), Live Photo was labeled `Save Still Photo`, and Share required an explicit
  `Share Still Photo` confirmation rather than silently implying paired motion. Photos commit is correctly treated as non-cancellable
  once submitted.
- Share now uses the same fresh protection gates instead of leaking an already-local protected path. It derives a canonical extension
  from fixed sticker format, TDLib MIME, ImageIO signature or MIME UTType; server filename contributes only a sanitized stem. A UUID temp
  hardlink (copy fallback) survives TDLib eviction/message deletion and is retained through `UIActivityViewController` completion before
  idempotent cleanup.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-140818-50364-12175.log`; final focused Telegram/TDLib/Photos delta
  review CLEAN. PID `50749` opened the real first profile photo through the secured Share preflight and displayed the system sheet with
  managed `bettertg-photo-<message-id>` / `JPEG Image · 6 KB`; the sheet was dismissed without choosing an external destination.
  PID `49849` exposed `Save Photo` and `Open in Chat` as the two More actions. Evidence:
  `.build/ui-probe-evidence/gallery-save-export-menu.png` and
  `.build/ui-probe-evidence/gallery-secured-share-sheet.png`.
- Runtime blocker/deferred: Save was deliberately not selected because it writes to the user's Photos library and no separate destructive
  smoke authorization was given. No reachable GIF/MP4 animation, WEBP sticker or Live Photo was exercised; those format branches are
  source-reviewed/build-proved. Delete is implemented below.

#### Gallery Forward slice

- **P1 flow:** Telegram current/pre-Liquid gallery `MessageGroup` sharing, adapted to BetterTG's existing UIKit
  `ForwardMessagesViewController`, forum topic picker, comment state and `MessageForwardingService` rather than a parallel delivery path.
- Implemented: Forward is serialized with Open/Save/Share and captures account/client/chat/topic/selected ID before any await. A fresh
  `getMessage` validates the source. Non-album media proceeds as one message. For an album, no loaded gallery row is trusted: exact
  base/forum/direct-messages/Saved/thread history APIs request expanding 20/40/100 windows around the selected ID. A group is accepted
  only when both adjacent nonmatching boundaries are present or Telegram's 10-item cap is reached. History transport failures advance to
  the next window and finally degrade to selected-only; cancellation propagates immediately. Fresh IDs retain exact topic and server
  order semantics through `MessageForwardRequest`.
- Complete groups show an explicit `This Item` versus `All N Items` action sheet, so a protected/unavailable sibling never prevents the
  user from trying the selected item. The chosen request enters the production destination search, secret-chat forced-copy rules, forum
  topic drill-down, formatted comment, sender/caption options, partial-delivery handling and exact account fences. Gallery playback pauses
  only while the full-screen picker is visible and resumes on Cancel; successful delivery reports recipient count in the existing footer.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-142756-56092-20725.log`; final Telegram/TDLib delta review CLEAN.
  PID `54892` exposed the real `Forward to` picker with search, destination eligibility, Add a comment, `1 message` and disabled Forward
  before selection; Cancel returned to the exact `1 of 1688` gallery with Close/More/Share intact. Final build PID `57324` launched on the
  still-booted Simulator. Evidence: `.build/ui-probe-evidence/gallery-forward-picker.png`; no destination was selected and no
  `forwardMessages` mutation occurred.
- Runtime blocker/deferred: the reachable selected photo has no album, so the item/all choice and every topic-history variant are
  source-reviewed/build-proved rather than live-data-proved. Deliberate delivery remains a test-account mutation gap.

#### Gallery Delete slice

- **P1/P0 flow:** Telegram current/pre-Liquid gallery item/group deletion and revoke-mode confirmation, adapted to one captured TDLibKit
  client and the same authoritative album resolver as Forward.
- Implemented: Delete is absent for secret/self-destruct media and serialized with Open/Save/Share/Forward. Single media proceeds to
  authority checks; a proven album first offers destructive `This Item` / `All N Items`, while unresolved history safely degrades to the
  selected item. Every chosen ID receives fresh exact-chat/topic `getMessage` plus `getMessageProperties`; permissions intersect across
  the complete set. Confirmation exposes `Delete for Me` only when every ID supports local deletion and `Delete for Everyone` only when
  every ID supports revoke. Immediately before commit, the same messages/properties/mode are fetched and checked again. One captured
  `deleteMessages` call is issued; no optimistic removal, multi-call partial state or automatic retry exists. An unconfirmed post-enqueue
  failure tells the user to inspect whether media remains.
- The controller now observes permanent deletes for photo/animation/sticker as well as video. Per-chat ID unions coalesce rapid events
  across diffable batches and interactive dismissal, merge owner callbacks, filter the newest pending canonical message list once and
  adjust the authoritative total once. Video owners are marked terminal and removed before release, revoking PiP/restore and preventing
  deleted playback from returning inline. Selected deletion uses a pre-enqueue snapshot and exactly-once forced fade; no dust/particles.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-144807-65887-7317.log`; final Telegram/TDLib lifecycle review CLEAN.
  PID `63543` exposed destructive `Delete` above Save/Forward/Open in the real gallery menu; it was not activated. Final unified build PID
  `66267` launched with Simulator still booted. Evidence: `.build/ui-probe-evidence/gallery-delete-action-visible.png`.
- Runtime blocker: destructive confirmation and `deleteMessages` were deliberately not exercised without separate approval; item/all,
  for-me/everyone, rapid-update union and video/PiP terminal branches are source-reviewed/build-proved.

#### Forum notification quick-reply slice

- **P0 flow:** topic-aware notification reply using TDLib `getMessage`, `getForumTopic`, `sendMessage(topicId:)` and `viewMessages`.
- Implemented: exact account requirement; captured-client guards; authoritative message/topic fetch; closed/manage-topic and existing
  chat/payment checks; verified same-topic reply target; exact returned chat/topic assertion; fail-closed lookup behavior.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-080453-55869-29388.log` plus focused source delta-review.
- Deferred: deliberate test-account notification action proof and all-messages history/composer parity.

#### Forum-aware Forward destination slice

- **P0 flow:** pre-Liquid/current forum drill-down behavior from `ChatControllerForwardMessages` and `PeerSelectionController`, adapted
  to UIKit + TDLibKit rather than Telegram controllers/state stores.
- Implemented: source route proof at prepare+delivery; destination chat/topic identity; multi-chat/multi-topic selection; exact cursor
  topic picker/search; closed/manage-topic and per-content eligibility; fail-closed forum discovery; exact forward result validation;
  partial retention; account fences; classic full-width material navigation/search and local selection summaries.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-075614-53821-9609.log`; local selection flow and classic header evidence
  `.build/ui-probe-evidence/forum-forward-topic-plain-final-*`; no Forward/send mutation, PID 54141 alive, Simulator booted.
- Deferred: comment/forward-draft transition, deliberate test-account delivery and all-messages headers.

#### All-messages forum timeline foundation slice

- **P0/P1 flow:** base forum adjacent-topic runs and jump-free history extension from pre-Liquid/current
  `ChatMessageItemImpl.swift` and `ChatMessageDateHeader.swift`, adapted to one inverted UIKit collection without Telegram
  Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: stable `message(id)` / `album(mediaAlbumId)` / `topicHeader(topicID,runStartMessageID)` identities; complete
  projection rebuild for `A,A,B,B,A`; official 34pt centered 22pt topic control with 16pt General/custom/generated icon, one-line title
  and chevron; lazy account/client-fenced `getForumTopic` cache plus `updateForumTopicInfo`; authoritative topic tap; message-only
  read/prefetch/playback/context/selection paths; raw TDLib pagination cursor; cross-page album coalescing; permanent member-delete
  survival; message-window reuse; and visible message + pixel-offset restoration across boundary-header insert/remove/merge.
- Production routing follows live `Chat.viewAsTopics`. Base text/photo/edit/draft and chat-action contexts resolve to discovered General
  or the replied message's exact topic; closed-topic replies fail closed, reply transitions cancel the prior topic action, and the base
  draft key remains `topic:nil`. Voice/video manifests now carry a separate immutable send topic through record/pause/resume/preview,
  relaunch, enqueue, resend and exact record/upload/cancel actions; a newer composer reply is never cleared by an older media draft.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-085723-71772-1312.log`; wrapper/idb launch PID `67526` stayed
  alive and ordinary chats retained full composer controls. `.build/ui-probe-evidence/forum-all-messages-*` records the hierarchy scan;
  no safe `viewAsTopics == false` forum exists in current simulator data, so live header tap remains a data-state blocker. Fresh PID
  `71701` passed `.build/ui-probe-evidence/forum-all-messages-media-destination-*`: voice Ogg/Opus + base-draft/frozen-topic relaunch,
  video send outcome/legacy/thumbnail/tombstone cleanup, and ordered multi-segment video recording trim/thumbnails/frozen-topic handoff.
- Deferred: live all-messages topic-header/pagination/album seam proof on an account with a reachable forum in this mode.

#### Keyboard and self-sizing timeline anchor slice

- **P1 flow:** Telegram-style `messageId + pixelOffset` retention across viewport/intrinsic-size changes in the inverted UIKit history.
- Implemented: message-cell pre-fit height notification; one coalesced visible-message anchor for autonomous self-sizing; exact anchor/latest
  restoration around single/bulk diffable reconfigure, composer/search/selection/keyboard insets, Dynamic Type and rotation; mutation-depth
  ownership so stale deferred size callbacks cannot overwrite a newer snapshot/inset/rotation anchor; active pan/deceleration remains untouched.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-091301-75604-22504.log`; focused delta-review clean. PID `75942`
  retained `Video message, 0:13` at `{{53,381},{260,260}}` and `chat-date-1787342400` at `{{172,348},{58,22}}` across two
  hierarchy-derived focus attempts (`Δx/y/w/h=0`). Simulator did not present `AXKeyboard`—likely hardware-keyboard state—so the
  non-no-op keyboard-attached transition remains a runtime proof blocker. Evidence: `.build/ui-probe-evidence/timeline-anchor-fresh-*`.

#### Delete collapse/fade/slide slice

- **P0 flow:** Telegram-style restrained delete transition without dust/particles, integrated with authoritative TDLib
  `updateDeleteMessages` and the inverted diffable timeline.
- Implemented: ChatVM announces only bubbles whose complete source-message set disappears; visible sources become noninteractive and
  animate 140ms opacity + directional 24pt slide + 0.98 scale; the delayed heterogeneous snapshot then performs layout collapse. Rapid
  deletes coalesce to one deadline, cell reuse resets all presentation state, nonvisible deletes apply immediately, album-member survivors
  stay in place, video teardown still follows `didEndDisplaying`, and the collapse anchor is restricted to IDs surviving in canonical state.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-092113-77487-3754.log`; focused source/delta review clean. No deliberate
  server delete was performed, so visual runtime mutation proof remains deferred.

#### Composer send-flight slice

- **P0 flow:** pre-Liquid Telegram composer source-to-message insertion transition, adapted to real UIKit snapshots and TDLib temporary
  IDs without Telegram transition infrastructure.
- Implemented: synchronous capture of visible reply, formatted text, selected-photo strip, caption, active voice/video preview and
  retry-button sources; one serialized composer text/media send; temporary→success/failure ID aliases before or after acceptance;
  canonical album/message target lookup; 320ms staggered frame/corner/opacity flight into the real visible bubble; bounded offscreen
  fallback; five-second/deinit/account cleanup. Voice direct/trim-preview/promotion/retry and video recorder/retry paths bind runtime-only
  transition tokens to their durable draft IDs, accept exact returned message IDs, and cancel retained/interrupted/discarded failures.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-093342-80738-1901.log`; focused source/delta review clean. No deliberate
  test-account send was performed, so the visible flight remains a mutation-gated runtime proof gap.

#### UIKit file/document attachment slice

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

#### UIKit emoji/sticker/GIF composer slice

- **P0 flow:** pre-Liquid/current emoji/sticker/GIF input panel behavior, adapted to a UIKit page sheet and TDLib-native
  `getStickers`, `getSavedAnimations`, `InputMessageSticker` and `InputMessageAnimation`.
- Implemented: Emoji/Stickers/GIF segmented grid; debounced search and mode-generation cancellation; account/client/chat fencing before
  loads and selection; installed regular sticker query with every Premium sticker excluded; saved-GIF filtering; exact picker-cell AX;
  TGS/WebP/WebM reuse with offscreen pause and GIF thumbnail cancel/restart; repeated emoji insertion with debounced route draft; exact
  other-message permission, General/reply topic and returned-destination assertion. Sticker sends preserve typed text while clearing the
  accepted reply through the captured draft topic with generation-fenced retry; GIF caption clears safely; both use serialized sends and
  the insertion-flight protocol. No Premium/Stars/custom-emoji results are offered.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-102014-91617-3187.log`; focused source/delta review clean. Runtime
  PID `90585` proved the UIKit sheet, exact three segments, 64 enabled emoji buttons, 16 non-Premium sticker buttons, 16 saved-GIF
  buttons, offscreen-safe navigation and Done return. Evidence: `.build/ui-probe-evidence/composer-media-picker-final-*`; no
  emoji/sticker/GIF was selected or sent.

#### Forward comment/draft slice

- **P0 flow:** pre-Liquid/current forward destination comment state, adapted to the existing UIKit multi-recipient/topic picker and
  TDLib `sendMessage(InputMessageText)` followed by `forwardMessages`.
- Implemented: expanding formatted Add a comment field retained across topic drill-down/search/retry; keyboard-layout-guide attachment
  with interactive dismissal and safe-area toolbar switching; Dynamic Type height refresh; comment snapshot at delivery start; exact
  basic-message/private/paid/forum/closed/admin eligibility; account/client checks immediately before mutation; exact returned topic.
  Each destination records the delivered `FormattedText`, so a failed forward retries without duplicating an unchanged successful
  comment, while an edited comment is a new intent. Comment failure blocks that destination's forward; ambiguous/partial forwarding keeps
  the existing nonretry policy, and controls re-enable with the comment intact.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-102642-93175-2531.log`; focused source/delta review clean. PID `93577`
  reached the real message context menu, but idb omitted its Forward overlay action, so safe navigation to the comment field was blocked.
  Evidence: `.build/ui-probe-evidence/forward-comment-final-*`; no comment or forward mutation occurred.

#### Date and topic boundary slice

- **P1 flow:** pre-Liquid/current `ChatMessageItemImpl.swift` date/topic merge break and `ChatMessageDateHeader.swift` 34pt service
  header ordering, adapted to stable heterogeneous UIKit diffable items.
- Implemented: calendar-start stable IDs; 34pt inverted rows with centered 22pt localized pills; Today/Yesterday/year-aware labels and
  header accessibility; one separator per day in ordinary and forum histories; exact visual date→topic→message ordering on simultaneous
  boundaries; no duplicate topic header at midnight; message-only read/prefetch/selection/playback; structural pixel-anchor reuse; and
  significant-time/locale snapshot reconfiguration so cached Today labels and timezone-derived identities cannot go stale.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-090344-73347-22038.log`; runtime hierarchy/screenshot evidence is
  `.build/ui-probe-evidence/date-headers-*`. Fresh PID `73694` exposes `chat-date-1787860800` (`Aug 28`, 58.67×22) and
  `chat-date-1788033600` (`Yesterday`, 76.67×22); 6pt row insets plus existing 5pt message gaps prove the exact 34pt row with zero
  overlap, while the enabled composer remains at y=796.67.

#### Writable explicit forum topic slice

- **P0 flow:** pre-Liquid/current closed-topic input panel, topic placeholder, text/attachment/media recording, activity and draft
  semantics from `ChatInterfaceStateInputPanels`, `ChatTextInputPanelNode`, `ChatController`, `ChatControllerOpenAttachmentMenu` and
  `ChatControllerMediaRecording`, adapted to UIKit + Combine + TDLibKit without Telegram infrastructure.
- Implemented: immutable send context; exact topic for text/photo/album/voice/video/action/draft; returned-topic assertions; same-topic
  replies; content-specific and live closed-topic authority; dirty/stale draft fences; generation-safe clear retries; edit preservation;
  partial-album retention; exact-location reactions/polls/delete/forward source; writable/restricted UIKit composer states and topic
  placeholder. Base forum history is now handled by the separate all-messages resolver above.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-073123-48367-634.log`; non-mutating real-topic route and production
  composer evidence `.build/ui-probe-evidence/forum-topic-write-final-*`; PID 48686 alive, Simulator booted.
- Deferred: forward comment, all-messages General-or-reply resolver/run
  headers, deliberate test-account send/draft mutation, topic-scoped pinned banner and remaining attachment types.

#### Topic media draft identity slice

- **P0 flow:** thread-scoped composer media ownership from pre-Liquid/current `ChatInterfaceState` and
  `ChatControllerMediaRecording`, adapted to Codable actors + TDLibKit rather than Postbox/SignalKit.
- Implemented: stable account/chat/full-topic key; four version-tolerant manifests; durable one-time legacy policy; exact restore,
  deduplication, enqueue, discard, recording handoff and resolution routing; draft-UUID outcome names; voice registration barrier;
  account/topic coordinator snapshots; stale account restore/promote guards; recorder receives the immutable destination.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-065904-41355-13754.log`; terminal probe files and run metadata
  `.build/ui-probe-evidence/topic-draft-key-*`; PID 41675 alive after proof, Simulator booted.
- Deferred: resolved network send context, topic text drafts/dirty generations, closed-topic write permission, exact returned-topic
  assertions, then attachments/voice/video UI enablement and topic-aware Forward/all-messages headers.

#### Classic chat list row slice

- **P2/P1 flow:** pre-Liquid `ChatListItem` presentation applied to existing UIKit chat/folder data and actions.
- Implemented: full-width 76pt rows; 60pt avatar at x=10; content/separator x=80; pinned/normal/highlight backgrounds; title/preview/date;
  pending/failed/delivered/read state; unread/muted/marked-unread/pin accessories; capped Dynamic Type; full-state VoiceOver; full-row context
  extraction and tap target. Existing diffable stable IDs, prefetch, search, gestures and TDLib actions remain unchanged.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-063859-35683-18833.log`; exact frame/tap evidence
  `.build/ui-probe-evidence/classic-chat-rows-*`; first tap opens Saved Messages; PID 35152 alive; Simulator booted.
- Deferred: typing/action preview, verified/scam/status/story adornments, archive reveal gestures and full account fencing for list mutations.

#### Classic shell blur slice (historical; folder/menu styling superseded 2026-09-05)

The Liquid Glass restoration above supersedes this slice for the folder picker and shared context menus only.

- **P2 flow:** full-width folder/tab chrome and context-menu material, based on pre-Liquid `ChatListFilterTabContainerNode` selection
  geometry and classic UIKit material rather than Liquid Glass.
- Implemented: edge-to-edge bottom blur including safe area; rectangular scroll viewport; exact three-point segment line; selected accent
  text; ordinary system-material context menu; classic 16/10pt menu/highlight corners; all Glass-only APIs and marker strings removed.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-062914-33482-14249.log`; real account hierarchy/screenshot and long-press
  menu evidence `.build/ui-probe-evidence/classic-shell-*`; PID 33820 alive; Simulator booted.
- Deferred at that checkpoint: remaining navigation/search/action surfaces needed an audit. The approved folder/menu glass
  surfaces are excluded from any subsequent full-width/no-floating conversion.

#### Forum topic browsing slice

- **P0 flow:** pre-Liquid/current `ChatListNodeLocation`, `ChatListNodeEntries`, `ChatListItem`, `ChatControllerContentData` and
  `ChatControllerLoadDisplayNode`, adapted to UIKit + Combine + TDLibKit without Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: account/client/chat/topic route identity; captured-client ref-counted open lease; exact topic cursors/order/hidden/search;
  update refetch and transient retention; explicit topic history/search/read acknowledgement; target-message topic resolution; classic
  UIKit rows with General/custom-emoji icons, pin/closed/draft/unread variants, Dynamic Type, VoiceOver and offscreen animation pause;
  stable-ID reconfiguration; fail-closed push/forward; VM-level read-only barriers with non-mutating content access preserved.
- Proof: warning-free build log `.build/logs/xcodebuild/build-Debug-20260831-062650-32938-29366.log`; device hierarchy/screenshot files
  `.build/ui-probe-evidence/forum-topics-*`; `[1,42,77]`, hidden 99 absent, AX tap `(201,262)`, status
  `Opened topic 42 · Read-only`, PID 31980 alive.
- Deferred: all-messages topic-run headers, topic composer/writes/durable drafts, topic forwarding selection, topic actions/mutations,
  General hidden toggle/admin controls, unread navigation and live server pagination/mutation smoke.

#### Pinned message slice

- **P0 flow:** pre-Liquid/current `ChatInterfaceStateContextMenus`, `ChatControllerLoadDisplayNode`,
  `ChatPinnedMessageTitlePanelNode` and `ChatControllerNavigateToMessage`, adapted to UIKit + Combine + TDLibKit without
  Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: exact Saved/private/group/channel pin modes; fresh `canBePinned` preflight; one serialized chat mutation; optimistic
  newest-pin state with authoritative revision rollback fences; account/client/generation guards before and after TDLib; initial and
  refreshed `getChatPinnedMessage`; 404-only clearing; cache/permanent-delete/edit/content/isPinned reconciliation; direct-message/forum/
  topic/album/service/sending gates; shared spoiler-safe thumbnail extraction; 50pt full-width blur banner; separate Open/Hide AX controls;
  local hidden-ID token; newer-pin resurfacing; selection/search suppression; stale-animation rejection; inverted-history inset stability.
- Proof: `Pinned message probe: modes=true, visibility=true, 404-only-clear=true, newest-only=true, banner-height=50, local-hide=true, navigation=true, uikit=true, swiftui=false`.
- Deferred: nearest-visible pin rotation, pinned-only list/pagination, admin unpin undo, older-pin warning details, topic-scoped pins and
  deliberate live server mutation proof.

#### Message reactions slice

- **P0 flow:** pre-Liquid/current `ReactionButtonListComponent`, `ChatMessageReactionsFooterContentNode`,
  `ChatMessageBubbleItemNode` and `ChatController` toggle/restriction behavior, adapted without
  Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: representative-bubble standard/custom reaction rendering; Telegram count-minus-own-selection sorting; exact 30/20pt
  geometry and 6pt wrapping; chosen/unread styling; reusable accessibility; account-keyed custom-emoji sticker cache; offscreen
  animation pause; zero-state context picker; authoritative per-message availability; Premium/paid exclusion; maximum-count-safe
  optimistic add/remove with rollback; chosen removal under restrictions; normal-client interaction/unread reconciliation; live
  chat permission/max updates; account-switch fences; chat/topic reaction-read acknowledgement; read-only topic and ephemeral mutation gating.
- Proof: `Message reaction probe: reducer=true, remove=true, add=true, max-count=true, unread=true, paid-excluded=true, wrapping-chips=true, uikit=true, swiftui=false`.
  Device hierarchy proves the exact two-row frames/gaps and paid omission. Fresh center taps produce
  `👍: 2, Not selected` and `❤️: 1201, Selected` while PID 11956 remains running.
- Deferred: custom-emoji origination grid, reactor list/avatars, removal animation, forum-topic identity and live server mutation proof.

#### Forward and message-selection slice

- **P0 flow:** pre-Liquid/current `ChatMessageSelectionNode`, `ChatMessageSelectionInputPanelNode`,
  `ChatControllerForwardMessages` and `PeerSelectionController` behavior, adapted to UIKit + Combine + TDLibKit without
  Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: context Select/Forward gates; whole-album direct forwarding; stable selection/reuse/accessibility; classic geometry and
  transition timing; 100-child limit; exact per-child property/content preflight; multi-delete; Saved/main/archive/offline/server
  destination discovery; raw-chat secret/private/group/channel eligibility; multi-recipient progress; sender/caption modes; safe
  nonretryable treatment for unknown partial subsets; account-switch fences before every mutation.
- Proof: `Message forwarding probe: normalized=true, limit=true, options=true, album-atomic=true, multi-recipient=true, account-scoped=true, uikit=true, swiftui=false`.
  Device hierarchy proves `forward-probe-saved-messages` and `forward-probe-design-group` are full-width 402×62 AX controls;
  center taps select both, enable the 66×56 Forward control and produce `Ready: 3 sorted IDs · 2 chats` without a Telegram send.

#### Reply, quote and forward provenance slice

- **P0 flow:** pre-Liquid/current `ChatMessageReplyInfoNode`, `ChatMessageForwardInfoNode` and bubble tap semantics, adapted without
  AsyncDisplayKit/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: cross-chat/ID-zero/story/unavailable fallbacks; forwarded target author override; `ForwardSource` chat-first display and
  message→chat→sender navigation; hidden-author static state; thumbnails including round video notes; 1-line ordinary and 5/50-line manual
  quote layout; source/context accessibility and bubble custom actions; exact quote range search/highlight; external reply input and every
  media draft restoration path; account/client guards; cache/permanent-delete and stale-generation fences.
- Proof: `Message metadata probe: inline=true, unknown-chat=true, source-priority=true, expand-then-navigate=true, forward-navigate=true, external-input=true, utf16-quote=true, highlight=true, uikit=true, swiftui=false`.
  Screenshots are `.build/message-metadata-final-*.png`; Simulator remains booted.

#### Exhaustive MessageContent breadth slice

- **P0 flow:** classic content routing based on the pre-Liquid contact/map/poll/action/animated-sticker nodes and
  `ServiceMessageStrings`, adapted to UIKit + Combine + TDLibKit rather than Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: 104-case catalog; shared summary/caption extraction; audio and document rows plus attachment albums; explicit primary-file
  download/cancel/reconcile and thumbnail-only prefetch; details-first contact card with five vCard lines; actual MapKit snapshots and
  absolute live-location timer; single/multi poll submission, persisted pending state, authoritative result/quiz colors and VoiceOver;
  visibility-gated animated emoji/rolling regular dice with safe resolved fallback; centered service pills; italic unsupported placeholder;
  explicit excluded-product fallbacks; account-captured, generation-safe prefetch.
- Proof: the DEBUG probe instantiates production views with real TDLib model values rather than parallel mock views. Its Documents proof is
  `MessageContent probe: tdlib=1.8.66-022d6020, exhaustive-cases=104, views=file,file,attachmentAlbum,contact,location,location,poll,poll,stickerGlyph,stickerGlyph,service,service, sized=true, poll-actions=poll:0,poll:0,1, action-proof=true, uikit=true, swiftui=false`.
  Device screenshots are under `.build/message-content-final-postbuild-*.png`; Simulator remains booted.

#### FFmpeg range controller slice

- **P0 flow:** non-Apple WebM VOD controller, following pre-Liquid/current `ChunkMediaPlayerV2.swift` buffering/seek/EOF and
  `ChunkMediaPlayerDirectFetchSourceImpl.swift` packet-lookahead behavior through TDLib `downloadFile(offset:limit:)`,
  `getFileDownloadedPrefixSize`, `updateFile` and `cancelDownloadFile`.
- Implemented: MainActor Combine controller; serialized 2s normalized packet horizon followed by a bounded 60s
  decoder job; exact 1s source gate plus Apple raw sufficiency; play/pause/rate/seek/EOF; non-zero-origin and per-track intervals;
  typed offline/retry failures; last-target-wins generations; offscreen renderer/range suspension; sparse audio degrades to silence;
  source demand cancellation is operation-token/last-demand scoped.
- Verification: `./build.sh` and `./test.sh` pass with Xcode 26.6. The 11.208s DEBUG fixture launched through
  `RUN_ARGUMENTS="-media-probe-vod-ffmpeg-controller" ./run.sh` and reported deferred load, ≥1s initial gate, ≤60s window,
  autoplay, visible buffering, stable pause, 1.5× rate, offscreen suspension/cancellation, preserved intent, last-seek-wins,
  seek-first PTS, EOF/no-loop, offline/retry, seek clamp, zero renderer errors, finite range downloads, zero full downloads and cleanup.
  `git diff --check` is clean.
- Persistent session rollover is complete; sample-buffer PiP remains the independent VOD architecture gap.

#### Production FFmpeg gallery routing slice

- **P0 flow:** WebM/VP9 VOD in the existing UIKit inline/fullscreen owner, following pre-Liquid `UniversalVideoGalleryItem.swift`
  central visibility and `ChunkMediaPlayerV2.swift` backend continuity without importing Telegram infrastructure.
- Implemented: MIME+extension routing; public range streaming; secret/non-streaming full-download handoff; cached-file FFmpeg re-entry;
  one controller/view/lease across inline and fullscreen; mute/rate/seek/control routing; offscreen demand suspension with preserved intent;
  first-frame/thumbnail transition fallback; typed failures; generation guards for every native and FFmpeg Combine stream; stale lease
  invalidation; native MP4/MOV/M4V and AVPlayer PiP isolation.
- Verification: `./build.sh build` succeeds without warnings. The combined native+FFmpeg owner probe launched through
  `./build.sh run -- -media-probe-gallery-owner`; idb readback proves `ffmpeg-route=true`, `same-controller=true`,
  `offscreen-intent=true`, `finite-ranges=true`, `ffmpeg-invalidate=true`, native `same-item=true`, zero full downloads for streamable
  fixtures, exact return-to-inline continuity, terminal lease cancellation and no stale attachment callbacks.

#### Persistent FFmpeg session slice

- **P0 flow:** retain demux/decoder/SWR state across VOD high-water expansions, matching pre-Liquid `ChunkMediaPlayerV2.swift`,
  `FFMpegMediaDataReaderV2` and `FFMpegFileReader` session-per-seek behavior through TDLib finite range reads.
- Implemented: separate exact one-shot and soft streaming APIs; one open per seek-generation; authoritative Continue horizon; full crossing
  frames; per-track emitted cursors; end-aware track completion; globally sequenced interleaved compressed-packet FIFO with hard count and
  payload/side-data/overhead footprint bounds; cumulative session metrics and per-pump safety budgets; persistent callbacks/context;
  terminal cancellation and close barrier; no repeated lookahead after session start.
- Verification: SHA-pinned two-second boundary fixture proves three uneven pumps, one open, no rollover seek, monotonic A/V, no added
  previous-end→next-start discontinuity, exact seek, persistent supersession/cancel and EOF/SWR tail. SHA-pinned sparse unequal-track
  fixture proves video 12s plus audio packets at 0…2 and 8…10s, non-EOF first horizon, full terminal audio/video, and ordered FIFO use
  (`25` packets / `24,113` bytes). The production controller proves eleven 1s DEBUG pumps on one session plus all prior playback states.

#### Sample-buffer Picture in Picture slice

- **P0 flow:** FFmpeg WebM VOD PiP using the pre-Liquid/current `NativePictureInPictureContentImpl` AVKit contract while retaining
  BetterTG's existing UIKit owner, Combine state, TDLib range session and restore coordinator.
- Implemented: exact layer-keyed `ContentSource`; strongly retained lock-backed playback adapter; finite current-containing range;
  playing/buffering/paused mapping; explicit setPlaying; signed skip with past-end reset; render-size forwarding; background audio allowed;
  pause/duration invalidation; native/sample source reconciliation; start/stop timeouts; pending-start strong retention; deletion/restore/audio
  lifecycle; deferred failed-player teardown; forced-timeout controller retirement and exact stale-controller rejection.
- Verification: the production gallery-owner fixture exercises the real content-source factory despite system PiP being unsupported and
  proves sample layer/delegate identity, transport/range behavior, exact-once completion, source continuity, zero extra TDLib cancellation,
  deferred stop-before-close, native fallback route, pending-start barrier and stale timeout callback rejection. Actual system-window PiP
  and background restore still require a capable physical device.


### User-reported list, menu and profile fixes — 2026-09-05

- Single/double delivery checks use Telegram's `PresentationResourcesChatList.generateStatusCheckImage`
  stroke geometry. A fixed trailing status container isolates unread/pin/mute from summary compression
  and removes hidden arranged-view width conflicts; pin is hidden whenever unread owns the slot.
- Expanded and active list/chat searches use a 36pt field with 8pt vertical padding. Pinned content and
  chat navigation share one background material, with no overlapping independent blur surfaces.
- Message menus retain the approved glass style, align with the actual bubble edge, keep Forward in
  the main action section and expose one Delete entry with a Back/available deletion-modes submenu.
- Avatar previews request account-scoped large photos during presentation, preserve the existing
  image and dissolve to the decoded result. Profile/Search actions resolve the represented peer.
- Profile actions occupy one row; Edit remains in navigation. Shared media uses the actual folder
  picker component (plain items without folder actions) with its glass selection and scrolling logic.
- Leaving selection via Cancel, last deselection or removal of selected messages resets all cells,
  including unselected indicators. The count title has symmetric navigation bounds around Cancel.
- Validation: SwiftFormat on all 12 changed Swift files, warning-free `./build.sh build` on Xcode 26.6
  / iOS 26.5 (`build-Debug-20260905-174328-31642-5978.log`); wrapper launch on the existing simulator.
  Simulator screenshots/hierarchy confirm list/chat search 8pt bottom gaps, trailing unread badges, one-row profile actions and glass tabs, avatar Profile/Search, root Delete/Back, exact bubble-edge menu alignment, centered selection title and complete cleanup on Cancel/last deselection. See `.build/ui-probe-evidence/parity-fixes-20260905/stage1/SMOKE.md`. Physical-device layout proof remains pending.


### TDLib chat-list ownership and paging — 2026-09-05

- `TelegramChatListStore` consumes the active client's ordered updates before dispatching UI
  notifications. It retains chat/peer snapshots and all chat fields across partial updates;
  folder membership comes from positions, with `(order, chatId)` descending order and zero-order
  removal. Last-message and draft updates replace the full position set, including removals.
- RootVM projects this cache into stable CustomChat objects. Folder metadata hydration cannot lose
  chat updates arriving before the corresponding folder UI exists. Account/client changes discard
  old caches and fence async folder/page work. Read-inbox/outbox updates feed the actual row state.
- Main, archive and custom folders use `loadChats` with repeated short pages and 404 as exhaustion.
  Near-bottom scrolling loads more; failures expose Retry. The chat-list UI no longer uses `getChats`
  or per-row `getChat`/peer requests to discover list contents. Informational picker/action snapshots
  remain separate. `ChatListStoreDebugProbe` exercises order ties, movement/removal, partial read
  updates, retained native values and account/client isolation without making server requests.
- Validation: SwiftFormat on all task-modified Swift files; warning-free `./build.sh build` on
  Xcode 26.6 / iOS 26.5 (`build-Debug-20260905-175331-35225-7160.log`). The opt-in native-cache probe passed all nine checks on a real TDLib model, without server mutations. Main, custom-folder and Archive lists populated correctly after the snapshot fix below. A visible scroll sample does not establish a measured row-200 crossing.


### Selection pan and deletion submenu separator — 2026-09-05

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


### Chat-list snapshot race found during launch verification — 2026-09-05

- Real startup exposed a UITableView dequeue assertion: membership reached the diffable snapshot
  before the separately queued provider cache, causing a fallback cell with the wrong reuse type.
- Each snapshot now populates its cache first; applies serialize and coalesce pending identifiers.
  Old row objects survive removal animations and are pruned only after completion. This also
  prevents scope/account metadata bursts from racing structural list updates.
- Validation: warning-free wrapper build `build-Debug-20260905-180601-39253-15148.log`;
  fixed launch PID 39691 remained running, main/custom/archive populated with expected visible
  order, and the repeated native-cache probe passed nine checks. Evidence is under
  `.build/ui-probe-evidence/parity-fixes-20260905/stage2/`.


### Custom language links — 2026-09-05

- Timeline links and gallery captions recognize Telegram `t.me/setlanguage/<id>` and
  `tg://setlanguage?lang=<id>`; the requested `addlanguage` spelling is accepted as an alias.
  `bettertg://setlanguage?lang=<id>` is registered for external app routing. Scene URL/user-activity
  entry points defer a language link through authorization when needed.
- A UIKit preview follows Telegram's LanguageLinkPreviewController flow: fetch actual language
  metadata, show name/completion, then download and apply only after the Change action. Already
  selected and missing packs have explicit states. Settings retains installed custom-pack metadata
  across catalog refreshes, and the selected pack/base strings persist for relaunch.
- Application is fenced by client/account and selection generation; stale requests cannot replace
  a newer choice. Numeric formatting uses the pack's plural language. Selection title/Cancel also
  use Telegram's localized keys.
- Validation: property-list/string lint, SwiftFormat on all task-modified Swift, warning-free
  wrapper build `build-Debug-20260905-180601-39253-15148.log`. The exact Saved Messages link was
  subsequently applied; Settings and persisted `appLanguagePackID` both read `lowercased-en`.


#### September 5 parity follow-up

- **Chat chrome and lists:** Telegram vector single/double checks; a fixed trailing status region prevents unread counters from following message width and prevents pin/unread overlap. Expanded and active searches use a 36pt field with an 8pt bottom inset inside 44pt chrome. TDLib updates own list membership/order; `loadChats` only requests more data, repeats short pages and stops on 404. Diffable snapshots publish their cell cache first and serialize/coalesce pending snapshots. The isolated store probe passes nine checks; main/custom/archive pagination and stable scrolling passed on the simulator.
- **Navigation, menus and selection:** all owned navigation controllers use classic plain UIKit buttons. Profile actions stay in one row, and shared-media tabs reuse the approved glass folder selector. Avatar menus request the high-resolution photo and wire Search/Profile. Message menus follow the actual bubble edge, keep one root Delete with Back-separated children, and remove the Reply/Forward divider. Selection clears every circle on Cancel/last deselection, centers the count title and supports UIKit two-finger range selection. The installed simulator HID tool cannot synthesize two simultaneous fingers, so that gesture still needs manual verification.
- **Localization:** `t.me/setlanguage`/`addlanguage` and app/internal links open the Telegram-style preview. Installed custom packs survive refresh and use the pack's plural code. The exact Saved Messages link `https://t.me/setlanguage/lowercased-en` was applied; Settings and persisted `appLanguagePackID` both read `lowercased-en`. The final compact sheet and its visible actions passed UI readback.
- **Messages:** timeline spoilers hide glyphs, attachments, custom emoji and accessibility text until revealed. Link previews render TDLib text/media ordering and open the destination. Rich messages render native headings, formatted text, lists, quotes, tables with spans, media, buttons, details and full-content expansion. Inline/block formulas use pinned SwiftMath 1.7.3, following Telegram's `InstantPageMath`; summaries/replies show spoiler-safe content and Copy retains plain block text. Rich-message authoring/editing is outside this rendering slice. The real read-only chat samples verify paragraphs, links and inline code; synthetic table/details/formula fixtures live in the agent-created private `BetterTG test` forum.
- **Reactions/custom emoji:** the new strip is above the message and supports recent standard/custom reactions without expansion/search. Thirteen local checks cover 64-bit IDs, UTF-16 ranges, adjacent emoji, formatting, draft/copy round trips, selected quote positions, rebased entities and complete Unicode grapheme boundaries. A real Saved Messages send with two identical custom emoji passed; adding and removing a reaction on that own test message also passed. Debug C/C++ builds use `-O1` because TDLibKit's large generated clone switch overflowed a Swift worker stack at `-O0`; Swift remains `-Onone`.
- **Recording:** unscoped Saved Messages sends accept TDLib's assigned Saved Messages topic after acceptance. Video-note playback preserves its player and accepts taps through the video surface; duration sits at bottom-left. Video/voice recording share animated lock/cancel hints; starting the camera no longer cancels the tracking gesture. The camera preview uses `AVCaptureDevice.RotationCoordinator`, and trim drags are excluded from the navigation back gesture. Voice paths are passed without percent encoding and UUID-named pending clips survive app-container relocation. The pre-existing Saved video now plays/pauses; the retained own voice clip restored after reinstall and its single Retry sent successfully to Saved Messages at 19:41 without a failure alert.
- **Gallery/Live Photo:** the full image and crop window animate separately, while the destination/source media is hidden for the transition to prevent a duplicate. Classic top Back/counter/actions and bottom Share/author/date/Delete panels accompany a 23pt/42pt thumbnail strip. Live Photo import preserves its motion resource, allows an explicit still-photo toggle, sends TDLib `InputPhoto.video`, renders a Live badge and plays the motion track with `LocalMediaPlayer`, following Telegram's `UniversalVideoGalleryItem`. Camera-roll export pairs JPEG/MOV identifiers using Telegram's `SaveToCameraRoll` approach. Share exports both resources. Secret chats use a still photo as required by TDLib. The synthetic JPEG/MOV identifier check and PHLivePhoto recognition passed. One synthetic Live Photo was selected, sent to Saved Messages, accepted with its native video component, and saved back to Photos as a second Live Photo asset. The received gallery passed muted autoplay, looping playback, Stop and press-and-hold/release checks. No second send or save was performed.
- **Physical limits:** the connected iPhone is passcode-locked and the installed CLI tooling cannot supply its accessibility/touch interface. Its screenshot is black. Camera orientation, physical unread-badge layout and real two-finger selection have not been claimed as verified on hardware.

Evidence is stored under `.build/ui-probe-evidence/parity-fixes-20260905/`. Tests only send to Saved Messages or the agent-created private `BetterTG test` forum; no other participant's messages are modified or deleted.


#### September 6 navigation and text-selection refinements

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

#### September 6 forum idle-scroll regression

The user reproduced continuous jumping with search hidden. A 12-second recording and six snapshots
confirmed about 80pt of visible movement despite unchanged accessibility row frames. LLDB caught
repeated 44pt additive table-bounds spring animations during diffable updates. Two mechanisms fed
the regression: the table's overridden content size conflicted with UIKit's update geometry, and
`updateForumTopic` requested `getForumTopic`, whose response emits another `updateForumTopic`.

Forum positioning now follows the chat list: set the initial offset once and snap only at drag end.
A native footer reserves search travel for short lists without overriding content size. Incoming
topic fields are applied directly; pin, inbox-read or draft-date changes fetch the missing full-topic
order/unread count only after those fields have been updated, so the echoed event cannot refetch.
Full responses merge and sort in a single publication.

`build-Debug-20260906-021227-74509-29734.log` passed with zero warnings. The fix was installed on the
same simulator as PID 74854, and the user confirmed the jumping was gone. Baseline video, pixel
measurements and debugger stacks are in `forum-jump` under the simulator evidence directory above.

#### September 6 media interaction corrections

Gallery dismissal now drags full-size media vertically in either direction. Chrome and background
fade with distance (Telegram's 50pt/80pt ranges); releasing animates from the current position into
the validated source. Source views use alpha instead of `isHidden`, preserving arranged-view
geometry. Open in Chat prepares the destination first and starts the highlight only after landing.
The shared-media viewer is presented by the navigation controller so removing the profile beneath
it does not short-circuit dismissal. Highlights fade in/out as an overlay without rebuilding cells.

The photo/video pager spans the chat, with account/topic-bound history loading in both directions.
Thumbnails contain only the current message album, disappear for standalone media, interpolate
width during paging, and select the centered item while scrubbing. Photos and albums reach their
bubble edges, with separate caption/metadata padding and continuous photo-caption joins. GIFs loop
inline without opening the viewer. Live Photo uses Telegram's two original gallery icons, aligned
with Back; message/reply summaries distinguish Live Photo from Photo.

Keyboard attachment now updates the visible composer blur's bottom corners. Voice/video recording
retains the input row height. Video-note recording overlays the chat navigation bar; inline playback
hides central controls while playing and removes the progress ring when playback ends.

A physical iPhone reproduced the double-camera-switch failure: the final video was 6.0367s while
audio ended at 5.9725s. Capture now freezes video and drains delayed microphone buffers through its
last frame before closing audio. Strict media validation remains enabled. The same front/back/front
probe passed with a 6.07s square recording; it only creates and deletes a local clip, never sends it.
Reports are in `.build/ui-probe-evidence/video-note-double-switch/`.

Simulator recordings under `.build/ui-probe-evidence/gallery-composer-20260906/` and
`.build/ui-probe-evidence/media-navigation-20260906/` cover source-return geometry, keyboard corners,
recording height and cancellation, captions/replies, Live Photo controls, both Open in Chat routes,
post-transition highlight fading, album scrubbing, and paging beyond an album with older-history
loading. The final shared-media return/highlight proof is `profile-final/06-profile-return.mp4`.
An existing suitable GIF was not available for this UI pass; inline GIF playback is build-verified.
No message was sent by these checks. Final simulator and device builds
`build-Debug-20260906-170646-15353-6396.log` and `build-Debug-20260906-170755-16779-25227.log`
passed without warnings; the device was relaunched normally after the capture probe.

#### Gallery controls, keyboard navigation, and forwarding follow-up (2026-09-06)

Gallery transitions keep the media snapshot separate from the surrounding controls, including the
Live Photo button. Controls fade with drag distance and animate back during cancellation; presentation
also fades them in. Native sharing expands from the Share button. Navigation highlights the exact
media item within an album, while text messages retain a bubble highlight.

Reply controls receive their first tap while the composer is focused. Programmatic scrolling resolves
the destination again after self-sizing rows settle, then highlights it. History moves with the
composer even when reading older messages: a simulator check measured the same two messages moving
up by 301 pt and returning to their exact initial positions when the keyboard closed. Editing ends
before opening a gallery so cancelling its dismissal cannot restore the keyboard above the photo.
The gallery retains hardware shortcuts with an empty software input view, preventing the More menu
from restoring an unwanted keyboard.

The Forward picker uses the account's folders, loads each TDLib chat list before enumerating it,
keeps custom-folder searches scoped, and excludes recipients and forum topics the user cannot post to.
Selections persist across folders. Its UIKit layout has fixed search, measured folder tabs with an
underline, message previews, compact selection controls, an inset comment field, and a filled action.

Recordings and screenshots are under `.build/ui-probe-evidence/gallery-polish-20260906/` and
`.build/ui-probe-evidence/keyboard-forward-20260906/`. The latter's `18-focused-cancel.mp4` verifies
that the keyboard does not return over the gallery. The More-menu check is
`.build/ui-probe-evidence/gallery-menu-20260906/04-menu.png`; the final picker screenshots are in
`keyboard-forward-20260906/forward-final/`. Checks did not send messages. The final simulator
build `build-Debug-20260906-180319-54637-12556.log` passed without warnings. The paired iPhone became
unavailable before delivery of the final keyboard and picker changes.

#### Forward recipient navigation and composer preview (2026-09-06)

The production Forward picker now reuses the main screen's bottom `FolderPickerView`,
`UIPageViewController` paging and `TelegramListNavigationBar` search. Recipient rows contain
only a 40-point avatar and title, with a 56-point minimum height. Existing account, content,
private-recipient and forum-topic eligibility filtering remains in place. The picker has no
comment field, recipient counter or send toolbar.

Selecting a chat/topic opens that destination with a cancellable `PendingMessageForward`
preview above the composer: a Forward title and sender/content summary. The composer Send
action sends any comment first, then invokes the existing forwarding service with fresh
permission checks; ambiguous partial results are not offered for automatic retry. Choosing
another reply replaces the pending forward. The old offline selection fixture's toolbar is
now private to its legacy debug probe.

Simulator evidence: `.build/ui-probe-evidence/forward-redesign-20260906/` contains the compact
picker (`05-forward.png`), horizontal paging (`06-folder-swipe.mp4`), folder tap and search,
recipient-to-composer transition (`11-recipient-to-draft.mp4`, `11-draft.png`) and cancellation
(`12-canceled.png`). These checks did not send messages. All changed Swift files were formatted;
`build-Debug-20260906-221323-59280-9033.log` records a successful build with no warnings or errors.
