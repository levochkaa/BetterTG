# A52b2 request-owned content completion — 2026-10-03

- `51d7174` adds a shared production request coordinator: UUID owns original content, handler and optional task. Replacement
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
- Native source `51d7174`, Audit Simulator59EB535C/iOS26.5, PID40035, fresh container
  `68E5B756-8A9D-44EF-9CFC-298DDACF7B30`: request probe18:39:27+04 PASS. Actual coordinator covers original/positive
  once-only completion, expiry/finish before task registration, held uncooperative old response, handler/cancellation reentry,
  rejected superseded outer ticket and entered synchronous producer versus expiry. Fixture tasks are awaited; effects injected.
- Same launch: session lifetime, target, media admission, cache scope and avatar worker reports18:39:26–27 PASS. idb hierarchy
  available before install; wrapper launch preserved focus. Evidence: `.build/ui-probe-evidence/astra-a52-a53/request/`.
  Actual NSE/APNs/builder donation remains unverified; an entered synchronous builder may delay expiry, and a system donation
  already started cannot be revoked. The coordinator probe performs no RPC/account/cache/donation effects.
