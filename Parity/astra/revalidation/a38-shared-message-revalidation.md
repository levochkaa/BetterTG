# A38 shared-message revalidation — 2026-10-03

- `aad1ac9` (worker `4116257`) reuses the profile-owned four-read history ledger. Every seed retains only ID/order/viewport;
  content, AX, file demand, transitions and actions await current-client admission. Scoped content/edit/delete updates revoke
  permits and visible consumers before async reads. Page admission shares revisions/tombstones and preserves unresolved IDs
  as actual loading/Retry rows; raw cursor remains server-page-derived. Exact404 `Not Found` removes; other errors and unknown
  RichMessage membership remain retryable. Attachment/Ready/anchor settlement resumes initial work; predispatch rejection
  consumes its exact request registration. No ChatVM/Root rewrite or new secret viewer.
- Gallery/PiP consumers are invalidated without revoking the profile's shared playback context. Default context teardown for
  other callers is unchanged. Independent immutable delta review found no further confirmed blocker. Active AVKit stop/layer
  latency is not proven by a Simulator helper. Six-file format; integration
  `build-Debug-20261003-002923-30429-24207.log`: PASS31s, zero warnings.
- Source `aad1ac9`, PID `31005`: standalone shared-refresh probe passes actual ledger/adapter, four-read/visible priority,
  suspended delete/spoiler/page races, exact404/offline/permission/unknown-filter Retry, source/actor/topic/tab/root attachment,
  actual cell geometry/diffable anchor, permit and non-vacuous late transition rejection. Seed raw loads0; accepted loads1;
  new spoiler adds0. Full controller RPC/bootstrap and gallery/PiP teardown are source-reviewed, not injected by this fixture.
- The next standalone profile-restoration run, PID `31305`, failed `error disappeared or auto-spun`: its new error check
  resumed a read then assumed delivery after40ms. `6723b65` (worker `054caab`) replaces all such delays with bounded semantic
  state and actual driver completion; one-RPC/state assertions remain. DEBUG-only handle, defer cleanup, independent review.
  Initial failure is preserved in `.build/ui-probe-evidence/astra-a38-primary/profile-restoration-probe.txt`.
  `build-Debug-20261003-003813-36345-3545.log`: PASS11s, zero warnings. A prior attempt stopped in clang metadata output
  (`003415-34099-21928`); a sample showed blocked pipe write. Only that owned build was interrupted; retry needed no cache
  removal, toolchain or Simulator reset. Source `6723b65`, PID `39878`: complete profile-restoration plus explicit A38 checks pass.
  Fresh result: `.build/ui-probe-evidence/astra-a38-settled-primary/profile-restoration-probe.txt`.
- Regressions at `aad1ac9`: profile-grid concealment, general media reveal and PiP context pass PID `31707`;
  native/FFmpeg gallery-owner, continuity, stop/cancel and sample-buffer PiP factory pass PID `32182` (system PiP unsupported).
- Actual source `aad1ac9`, PID `32182`: Saved → Profile initially populates Media/Files. Scroll Files, Home→app icon;
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
