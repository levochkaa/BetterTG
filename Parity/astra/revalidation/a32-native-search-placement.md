# A32 native search placement — 2026-10-03

- `70f37c3` sets `.stacked` and disables toolbar integration only for non-nil search controllers on app-owned bars.
  Setters are idempotent; search/delegate/field identity, text/selection, active state, scrolling policy and native Back are retained.
  No global appearance mutation, private subview traversal or controller/delegate replacement. The Forward picker owns a separate
  UISearchBar header and is unchanged by this policy.
- References: pre-Liquid `8e7e5fe`, `ChatListHeaderComponent/Sources/ChatListNavigationBar.swift`272–326 retains search in
  the top navigation region. Local UIKit26.5 `UINavigationItem.h`39–53,232–254 defines stacked placement and the public toolbar
  opt-out. These APIs establish preferred placement, not full classic visual styling; no Telegram UI infrastructure is copied.
- Independent review passed final tree `7dd516d8`. Both changed Swift files formatted in one invocation; final build
  `build-Debug-20261003-120206-97759-31692.log`: PASS18s, full log zero warnings/errors. Native PID99807, report12:03:03+04,
  passes initial/late/replaced/removed search, repeated layout, non-nil selection[2,5], delegate/text/scroll preservation and unowned
  bar isolation, plus existing Back/action/appearance checks. Integrated PID14782 repeats PASS at12:07:37.
- Actual PID99807, source `70f37c3` on audit59EB535C/iOS26.5: top Search Topics replaces the bottom toolbar island; first topic
  moves from y116 to y176pt, below search. Active field is(16,70,315,44); query `articles` returns topic37 at y122pt.
  Home→foreground in the same PID preserves query, keyboard and these frames; clear/close restores all six rows with General first.
  The narrow replacement log has no receipt, so this proves foreground UI continuity, not a newly established TDLib client epoch.
  Inspected `astra-a32-search-placement/after-final.png`, `active.png`, `foreground-search.png`.
- Search capsule/shadow, circular Back/Close, other search screens, rotation, RTL/Dynamic Type and accessibility remain open.
  Production/dependency forbidden-marker scan is empty at `ecd1d64`; this is not proof that all runtime chrome is classic.
- Supplementary integrated forum regressions at documentation HEAD `04bb5f1`: PID64049, fresh restoration/snapshot reports
  12:20:20/22+04, PASS; PID65325 active-search12:22:15 PASS. These preserve their controlled-coordinator/table proof limits;
  no additional live epoch claim.
