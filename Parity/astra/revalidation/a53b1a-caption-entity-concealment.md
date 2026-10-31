# A53b1a caption entity concealment — 2026-10-03

- `0428569` routes photo/video/animation/document body generation through the shared FormattedText caption gate. A spoiler
  entity returns no replacement body; eligible attachments keep their independent authority. Plain/bold captions and empty
  Photo/Video/GIF/filename labels remain identical. No UTF-16 slicing or new rendering infrastructure is introduced.
- Exact independent review passes tree `f830e1aa`; joint eleven-file SwiftFormat2/11. Build `191222-90485-18135` PASS8s,
  complete1545-line log zero warnings/errors. No regression scope was relaxed.
- Native same frozen tree, now committed `0428569`, Audit59EB535C/iOS26.5, PID91301, fresh container
  `F9078410-8C14-4A4D-8A93-8CB552BB440A`: preview report19:13:48+04 PASS. Actual shared helper preserves ordinary/bold/
  empty output and original body with valid or malformed-range spoiler entities, including emoji text; allowed media remains.
  Fixture Int.max is never serialized or used to slice text. It tests entity presence, not TDLib transport validation.
- All six notification regression reports PASS19:13:47–48. idb preinstall count22; background wrapper preserves focus.
  Evidence: `.build/ui-probe-evidence/astra-a52-a53/captions/`. This suppresses an unsafe generated override; it does not
  sanitize an already-unsafe original APNs payload or prove actual NSE attachment/donation behavior. Cache-v2 remains next.
