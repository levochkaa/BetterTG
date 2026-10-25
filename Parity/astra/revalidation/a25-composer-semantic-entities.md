# A25 composer semantic entities — 2026-10-02

- `0a8011e` (worker `7b58988`) separates composer entity identity/payloads from visual attributes. Explicit scoped Swift/UIKit
  bridges and semantic fallbacks retain code/pre/language, quotes, links, mentions, custom emoji and dates across unrelated edits.
  UTF-16 scalar bounds reject overflow/split surrogates; decorative crossing ranges split into nested TDLib output. Independent
  bold/italic toggles preserve both traits. Adjacent emoji identities remain separate. Eight ChatVM import sites cover edits/captions/drafts.
- Only manual input entity types are exported; detected URLs/email/phone/mentions remain plain text for TDLib parsing. External
  RTF accepts visual traits and supported explicit links, not arbitrary background colors or private identity attributes. Paste
  commits marked text and blocks route replacement until synchronous mutation settles. Link alerts reject changed source values.
  Display formatting/A10, send-attempt authority and persistence formats remain unchanged.
- First integrated runtime failed: a UIKit caret move restored underline into typing attributes. `ac8b1e8` refreshes sanitized
  typing attributes on selection/text callbacks, matching pre-Liquid input-panel timing. Start/interior/end insertion, deletion
  and neighboring semantic spans now pass; the initial failure is preserved, not relabeled as success.
- References: pinned current/pre `TextFormat/Sources/ChatTextInputAttributes.swift` 12–25,100–139,1048–1095 / 13–25,1040–1055;
  `StringWithAppliedEntities.swift` 30–56 / 30–54; `GenerateTextEntities.swift` 149–183 / 148–179;
  `ChatPresentationInterfaceState/Sources/ChatTextFormat.swift` 6–98. Pre `TelegramUI/Sources/ChatTextInputPanelNode.swift`
  3041–3047,4085–4097 refreshes typing attributes after text/selection changes. Pinned TDLib `TextEntity`, `FormattedText`
  and `InputMessageContent` define UTF-16 offsets, nesting and the manual-entity whitelist.
- Eight-file integration format/build `build-Debug-20261002-195938-90068-6531.log`: PASS11s, zero warnings. Final two-file
  format/build `build-Debug-20261002-200325-91739-906.log`: PASS7s, zero warnings. Audit Simulator source `ac8b1e8`, PID `92214`:
  `-ui-probe-composer-entities`, composer-edit/restoration, text-spoiler and scoped-update regressions all pass. Evidence under
  `.build/ui-probe-evidence/astra-a25-primary`; worker notes under `.build/composer-entities-proof` in its protected worktree.
- Probe uses real UITextView insertion/deletion/callbacks, edit-attempt preparation, DraftMessage Codable and immutable restoration
  transfer. No user clipboard, URL, server calls or account-store writes. Live IME/undo, network edit/send, persisted draft relaunch,
  private semantic clipboard interchange and animated custom-emoji composer presentation remain unverified. No new quote/language picker.
- Follow-up `3cfa419` expands the same production-field probe: model echo preserves two marked candidates and their commit,
  restoration stays blocked while composing, and UIKit's actual undo manager restores/reapplies formatting and pasted text with
  unchanged entities. One-file format/build `build-Debug-20261002-200757-94069-19293.log`: PASS6s, zero warnings. Audit Simulator
  source `3cfa419`, PID `94652`: `marked-model-feedback=true; UIKit-undo-redo=true`; restoration/text-spoiler regressions pass.
  This is programmatic UITextInput/undo proof, not a live software-keyboard, dictation, CJK suggestion or keyboard-shortcut test.
