# BetterTG / Telegram iOS Parity

This folder is the checkpoint ledger for the UIKit + Combine + TDLibKit implementation, one file per section. The goal
prompt is [goal.md](goal.md); editing the ledger or the prompt does not start or resume a goal.

Implementation status and audit status are separate. Implementation: **done** (the recorded scope has its stated proof),
**implemented breadth** (main paths exist, listed limits), **partial** (known gaps), **next**, **queued**. Audit:
`pending`, `reviewed`, `needs-fix`, `fixed`, `runtime-blocked`. Proof kinds are source review, warning-free build,
deterministic probe, Simulator smoke and physical device or server. A proof belongs to its SHA, scenario and environment;
historical CLEAN, build or smoke results do not transfer to merged or changed code. Gifts, Stars, collectibles, boosts,
Premium, ads, livestreaming and Telegram infrastructure (Texture, SignalKit, Postbox, Display, ComponentFlow) are out of
scope. None of these states claims complete Telegram parity.

## Contents

- [checkpoint.md](checkpoint.md): start here. The branch, references and toolchain, the latest checkpoints with a row
  for each closed gap, the runtime smoke after the merge (D1–D8) and the audit cursor.
- [goal.md](goal.md): the goal prompt, in Russian.
- [identity.md](identity.md): BetterTG's look, as the user decided it.
- [flow-status.md](flow-status.md): the state of each flow on 2026-10-12.
- [stage-0](stage-0/README.md): merging `main`, `codex/parity-continuation` and astra into one branch, with the merge
  decisions and findings F1–F56.
- [audits](audits/README.md): audits of the merged code from 2026-10-12 to 10-16, one file per area. Each file defines
  its own IDs: M and T (post-merge), C and L (second pass), V and R (voice and video notes, message content), T (forum
  topics, timeline, Forward, folders), S and ST (search, chat actions, stickers, stories), B and M (compose), G (groups
  and channels), MD (media sending and gallery).
- [context-menu](context-menu/README.md): the context menu's touch model from CustomContextMenu and the liquid morph of
  menu buttons.
- [astra](astra/README.md): Appendix A, the revalidation ledger of `codex/a21e-previous-worker` (2026-10-02…03):
  findings A01–A53 in its repair queue, then a file for each repair or proof.
- [continuation](continuation/README.md): Appendix B, the ledger of `codex/parity-continuation` through 2026-09-06.

Search by ID or by the Telegram name of a component: `rg -n 'ST-1' Parity`, `rg -l ChatListTitleView Parity`.

## Recording

- When a change closes a gap, add a row to the newest checkpoint in [checkpoint.md](checkpoint.md), after the last
  dated row and before the "TDLibKit is on TDLib 1.8.69" row: the area and date, what changed, the Telegram code it
  follows, the commit, and how it was checked.
- A new audit gets a file in `audits` named after its date and area, and a line in its README.
- Stage 0, the audits and both appendices are history. Fix links in them; don't rewrite them.
- `git log -- PARITY.md PARITY_PROMPT.md` shows the ledger's history before it moved here.
