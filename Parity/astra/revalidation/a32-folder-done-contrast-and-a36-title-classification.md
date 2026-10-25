# A32 folder Done contrast and A36 title classification — 2026-10-02

- `1fd4ae4` (worker `7a46acb`) changes only selector/order Done factories to titled `.plain` items, retaining actions,
  target, readiness gates and AX label. Native folder-flow probe now verifies all of them, including disabled action denial.
  Two-file format; `build-Debug-20261002-232705-14634-13985.log`: PASS8s, zero warnings.
- Audit Simulator, source `1fd4ae4`, PID `29718`: folder-flow and profile-editor regressions pass, fresh results
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
- `4477718` (worker `cef12a6`) adds truthful selector-only title/subtitle fallbacks, deterministic title/ID ordering and
  source/generation-fenced existing-candidate observation. Presentation dedup ignores unread/position/message-only changes;
  same-ID fresh objects are rebound without unnecessary sort/reload. Selection and valid Saved titles are preserved.
  Two-file format; `build-Debug-20261002-234911-61254-22275.log`: PASS8s, zero warnings. Primary runtime pending.
  Independent source review found no introduced blocker, but `CustomFolder.chats` append/remove is not forwarded by Root.
  The existing probe manually publishes `modelChanges`; it does not prove that live child-membership link. Separate repair queued.
- Actual `649ffac`, PID `68772`: all 11 explicitly deleted rows now have visible `Deleted Account` labels, no Contact subtitle,
  and are found by local search. Real self `Saved Messages` title is retained; its current non-contact classification is shown.
  Aggregate diagnostic: 467 candidates, 11 empty raw titles, zero empty visible cell texts and zero model/display mismatches.
  Extended native selector probe passes. Back discards the blank local folder; no selections or server saves were made.
  Private proof `.build/ui-probe-evidence/astra-a36-primary`.
- `b419253` (worker `1b259865`) adds source/generation-fenced child `CustomFolder` publishers, retaining existing presentation
  dedup and replacing obsolete folder/chat subscriptions. Root/session are unchanged. Two-file format;
  `build-Debug-20261003-000123-71229-20485.log`: PASS9s, zero warnings. Native child-publisher probe at `c37e10c`,
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
