# A23d static-image update delivery — 2026-10-02

- `bf44ad0` captures the active account/client before the default `TDImageLoadingView` file subscription. It consumes the
  generated scoped envelope and validates both event source and current source after main-queue delivery, before decoding.
  Existing request-generation, decode-completion, thumbnail/cache behavior and explicit-client load path remain unchanged.
- References: the pinned current/pre account-bound media reference recorded for A05/A09; pinned TDLib `File/updateFile`
  and generated `TdScopedUpdate` transport. Numeric file IDs are client-local, not cross-account authority.
- Both changed Swift files formatted together; build `.build/logs/xcodebuild/build-Debug-20261002-195308-87219-10047.log`:
  PASS10s, zero warnings. Audit Simulator, source `bf44ad0`, PID `89171`, expanded `-ui-probe-chat-update-delivery`: PASS.
  Actual production observer plus generated dispatcher rejects queued old-client, foreign account with colliding file ID,
  missing source, wrong file ID and cancelled subscriptions; current-source delivery survives.
  Readback: `.build/ui-probe-evidence/astra-a23-image-primary/chat-update-delivery-probe.txt`.
- This isolated proof does not instantiate an image view, decode pixels, download files or switch real accounts. Explicit
  origin propagation to legacy callers, static-image shared-demand cancellation and auth delivery remain separate gaps.
