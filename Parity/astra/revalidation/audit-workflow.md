# Audit workflow

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
| P1 | Profiles and galleries | Peer/self roles, avatar/history, member/admin/tag rights, shared-media pagination; selected item, transitions, zoom/paging/dismiss/control gestures, rotation, captions, export/forward/delete/open-in-chat | reviewed with bounded A20b/A27/A28 repairs — profile grid concealment, effective info-edit policy and pagination request identity probed; own-profile grid navigation passes at `0278eca`; hardware/server/gesture proof incomplete |
| P1/P2 | Accounts, chat lists/folders and classic shell | Inventory existing add/auth/switch/remove/logout paths and missing isolation; archive/search/edit/reorder/include/exclude/pin/mute/read/delete/clear/drafts; safe-area full-width blur and prohibited production UI markers | reviewed with bounded auth/list/mutation/foreground repairs below; A32 native chrome and intermittent A37 remain unresolved. Live multi-account/logout and complete secondary-surface proof remain unverified |

Read-only audit subagents return findings and need no commit or duplicate build. At most two subagents may run concurrently.
Implementation subagents use isolated worktrees, format changed Swift in one invocation, build without warnings and commit;
the primary integrates verified commits and validates the combined result. Do not spawn when the remaining budget cannot cover
integration and verification. Each implementation slice must end with proof, a focused attributed commit and an updated checkpoint.
