# Flow status — 2026-10-12

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
