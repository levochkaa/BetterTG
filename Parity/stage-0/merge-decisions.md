# Merge decision ledger

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
