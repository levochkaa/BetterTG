# Sources

| Source | SHA | Role in the merge |
| --- | --- | --- |
| `main` (local, not pushed) | `bb0df3e` (prompt written at `3656153`) | Toolchain, dependencies and current UI: Xcode 27, TDLibKit 1.8.68, liquid-lens folder picker, folder unread badges, Telegram context menu |
| `codex/parity-continuation` | `7893aea` (2026-09-05…06) | Parity code already on TDLibKit 2; user UI decisions |
| `codex/a21e-previous-worker` (astra) | `77c8386` (2026-10-02…03) | Independent revalidation: ownership/lifecycle fixes, account/client epochs, MediaCore, probes; TDLibKit 1.5.2 |

The parity lines share `5e6f5a0`. `ee8cf99` is the parity-continuation merge of `5e6f5a0` with main's TDLibKit 2
(`1476556`), before any of its UI decisions.
