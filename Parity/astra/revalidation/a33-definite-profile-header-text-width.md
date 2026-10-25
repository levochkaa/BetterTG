# A33 definite profile-header text width — 2026-10-02

- `9f19e5b` changes the four centered header labels from `width <= stack.width` to definite available width. Multiline fitting
  no longer resolves the own title to a narrow 90pt region. Text alignment, fonts, line limits, self-role wording and the 96pt
  avatar remain unchanged. No full header rewrite. Independent source review found no blocker.
- Reference: pinned current/pre `TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift`
  1361–1372 / 1390–1398 measures text against explicit header width; 1206–1218 / 1245–1257 preserves Saved Messages for this role.
  No TDLib API or storage changes.
- Two Swift files formatted together; `build-Debug-20261002-212624-17872-14020.log`: PASS9s, zero warnings. Audit Simulator
  PID `20471`, source `4332cd5` plus the committed delta: actual Saved Messages → Profile displays the full one-line title.
  Read-only DEBUG geometry records header402pt/title362pt, all three visible labels centered at available width, avatar96pt,
  content size category L. It does not replace content or log title/bio/phone. Profile media concealment regression also passes.
- Private before/after screenshots and readback: `.build/ui-probe-evidence/astra-a20b-primary/own-profile.png` and
  `.build/ui-probe-evidence/astra-a33-primary`. No editor/media item/server action opened. Other widths, dynamic category changes,
  long/RTL titles and scrolled-offset resizing remain unverified. Circular Back remains separate A32 work.
