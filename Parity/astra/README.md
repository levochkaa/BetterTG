# Appendix A — astra revalidation ledger

Verbatim ledger of `codex/a21e-previous-worker` at `77c8386` (2026-10-02…03), one file per section. File and line
references point into that branch. Its implementation ledger and historical slices repeat the `5e6f5a0`-era
ledger; [Appendix B](../continuation/README.md) carries the newer parity-continuation copy of those flows.

This file is the checkpoint ledger for the UIKit + Combine + TDLibKit implementation. Telegram references use
`telegram-upstream/master` unless a commit is pinned. The classic pre-Liquid baseline is
`8e7e5fefb1b0aba8335d8c28b62138183d61dc3d`, the parent of Telegram's first first-parent `Glass` commit.

Implementation status and verification are separate. **done** means the recorded bounded scope has its stated proof;
**implemented breadth** means the main code paths exist, with the listed verification limits; **partial** has known gaps;
**next** identifies the next bounded slice; **queued** has not started. None implies exhaustive Telegram parity.
Gifts, Stars, collectibles, boosts, Premium, ads, livestreaming, and Telegram infrastructure
(Texture, SignalKit, Postbox, Display, ComponentFlow) are intentionally out of scope.

## Contents

- [Revalidation before new features — 2026-10-02](revalidation/README.md)
- [Implementation ledger](implementation-ledger.md)
- [Checkpoint](checkpoint.md)
- [Historical implementation slices](slices/README.md)
