# Custom language links — 2026-09-05

- Timeline links and gallery captions recognize Telegram `t.me/setlanguage/<id>` and
  `tg://setlanguage?lang=<id>`; the requested `addlanguage` spelling is accepted as an alias.
  `bettertg://setlanguage?lang=<id>` is registered for external app routing. Scene URL/user-activity
  entry points defer a language link through authorization when needed.
- A UIKit preview follows Telegram's LanguageLinkPreviewController flow: fetch actual language
  metadata, show name/completion, then download and apply only after the Change action. Already
  selected and missing packs have explicit states. Settings retains installed custom-pack metadata
  across catalog refreshes, and the selected pack/base strings persist for relaunch.
- Application is fenced by client/account and selection generation; stale requests cannot replace
  a newer choice. Numeric formatting uses the pack's plural language. Selection title/Cancel also
  use Telegram's localized keys.
- Validation: property-list/string lint, SwiftFormat on all task-modified Swift, warning-free
  wrapper build `build-Debug-20260905-180601-39253-15148.log`. The exact Saved Messages link was
  subsequently applied; Settings and persisted `appLanguagePackID` both read `lowercased-en`.
