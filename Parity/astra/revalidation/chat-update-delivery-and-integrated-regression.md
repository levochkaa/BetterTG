# Chat update delivery and integrated regression — 2026-10-02

- A23b `d9c7be5` (worker `6c43e20`) binds 20 ChatVM typed subscriptions to their accepted account/client and exact chat/topic.
  Five asynchronous new/sent/failed/message/reference hydration paths recheck that authority and the nonretired owner before
  publication. Durable send outcomes, deletion transport and local recording-store notifications retain their existing ownership.
  Same-client body/partial/delete ordering and actual Chat foreground restoration remain separate work.
- Reference: the pinned current/pre Telegram AccountContext ownership and A13 accepted-update contract above; generated TDLib
  update models, `getMessage` and captured-client metadata reads are unchanged. No server mutations or account switches exercised.
- Four changed Swift files formatted together; primary build `.build/logs/xcodebuild/build-Debug-20261002-180630-74419-20491.log`
  passes without warnings (9s). On the audit Simulator, installed `d9c7be5`, PID `75292`, actual generated dispatcher and observer
  probe passes queued A1→A2, A→B→A3, colliding IDs, missing origin, retired owner, route/topic and late callback checks.
  This is an isolated observer test, not delayed live ChatVM/TDLib network proof.
- The same launch passes Root authority, A16 video submission ownership, A13 update source, A12 draft outcomes, A30b2 history/import
  and A31 poll attempt probes. Separate `901af79`, PID `73141`, passes A17 native video-finish regression.
  Evidence: `.build/ui-probe-evidence/astra-a23b-primary` and `astra-a15a-primary/video-note-finish-probe.txt`.
- Production Root/Main smoke on `d9c7be5`: selected `groups`, entered own query `232323`, Home→app icon, observed the same query
  and selected folder, then typed `7` without another focus tap; AX and screenshot show `2323237`. Closed search and verified the
  empty placeholder. Screenshot: `astra-a23b-primary/root-search-foreground.png`. Software keyboard was hidden; text focus was
  demonstrated by input, not by keyboard pixels. This does not prove restoration of an open Chat or a real account switch.
