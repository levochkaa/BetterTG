# A49b rendered message action authority — 2026-10-03

- `3325251` (worker `2c511e2`, reviewed tree `d755c225`) freezes each provider configuration's source/location, exact wrapper,
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
- Same `3325251`/PID90027 actual Saved Messages: existing context Select enters1; provider taps select a second row (2), then
  deselect it after reconfigure (1); Cancel restores empty composer with selection toolbar absent. Screenshots inspected under
  `.build/ui-probe-evidence/astra-a49b-actions/`; no send/vote/reaction/forward/delete/link action. This proves ordinary current
  selection admission in the real controller, not touch-down/update/touch-up or detached-route races.
  Subsequent screenshot review confirms unselected rows retain blue selection circles after Cancel in this same evidence;
  toolbar/composer recovery must not be read as full selection teardown proof. See A50 below.
- Confirmed next bounded defect at `3325251`: MessageView's persistent selectionControl retains its touch while configure replaces
  actionBindingID/onSelectionToggle. Late touchUpInside calls the new callback, whose fresh authority can admit the wrong intent.
  Plan: capture binding on touchDown, consume only matching token on touchUpInside, clear on cancel/outside/reset/configure;
  preserve independent AX activation and ordinary selection. Prove current, stale/rebound, duplicate/cancel/outside/reset sequences
  through the real UIControl event targets; synthetic event ordering is not physical UITouch proof. Reaction buttons are separately
  reset/replaced on each configure, so the same source defect is absent there. No actual unwanted selection has been reproduced.
- Follow-up `1d67d4d` (worker `221a377`, reviewed tree `bf7833e7`) implements that touch token; configure/reset/detach/cancel/outside
  clear it, up consumes before invoking the callback, AX stays independent. Worker joint2-file format/build `135311-1388-8311`
  PASS9s/fullzero; integration joint SwiftFormat0/7/build `135546-3924-17979` PASS15s/fullzero. Audit59EB535C/iOS26.5 PID5348,
  fresh container `1086DC4E-361C-4EAC-8255-C0041B6E0D3D`, report13:56:42 PASS: old armed token, exact same native cell/control
  and unchanged reuse count across reconfigure; late/duplicate/canceled/outside/reset touch-up rejected; fresh touch and independent
  AX admitted. All prior delivery/action probes pass. Synthetic UIControl event ordering is not physical UITouch race proof.
- Same `1d67d4d`/PID5348 ordinary Saved selection again passes1→2→1; Cancel restores composer/toolbar state but leaves circles
  on unselected rows, reproducing A50. Evidence `touch-selected`, `touch-selected-two`, `touch-selected-one-again`, `touch-canceled`.
