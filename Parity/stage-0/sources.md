# Sources

| Source | SHA | Role in the merge |
| --- | --- | --- |
| `main` (local, not pushed) | `bca8057` (prompt written at `24d5b2f`) | Toolchain, dependencies and current UI: Xcode 27, TDLibKit 1.8.68, liquid-lens folder picker, folder unread badges, Telegram context menu |
| `codex/parity-continuation` | `aec5611` (2026-09-05…06) | Parity code already on TDLibKit 2; user UI decisions |
| `codex/a21e-previous-worker` (astra) | `0b35e21` (2026-10-02…03) | Independent revalidation: ownership/lifecycle fixes, account/client epochs, MediaCore, probes; TDLibKit 1.5.2 |

The parity lines share `e88036e`. `0b8fc67` is the parity-continuation merge of `e88036e` with main's TDLibKit 2
(`6dd705c`), before any of its UI decisions.
