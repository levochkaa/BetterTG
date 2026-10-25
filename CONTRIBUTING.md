# Contributing to BetterTG

Thanks for helping. Bug reports, fixes, features, docs and forks are all welcome.

## Before you start

- Search the issues first. For a larger change, open an issue describing it so we can agree on the approach before you write it.
- Report security problems privately through [GitHub security advisories](https://github.com/levochkaa/BetterTG/security/advisories/new), not in a public issue.
- Keep other people's data out of issues, commits, notes and screenshots: names, usernames, chat titles, messages and phone numbers from your Telegram account. Describe them in general terms instead.

## Setup

Follow [Building](README.md#building) in the README. `./setup.sh` keeps your `api_id`, `api_hash` and signing settings in files git ignores, and `./script/prepare_worktree.sh` copies them into new worktrees.

### Telegram's test server

Debug builds sign in to [Telegram's test server](https://core.telegram.org/api/auth#test-accounts) as well: Settings → Accounts → Add Test Server Account, or ten quick taps on the background of the sign-in screen, which switch that sign-in between the production and test servers. A test server account shows "Test Server" on the sign-in screen and in the account list. Its numbers are `+99966 X YYYY`, X being the data center (1 to 3), and its code is X repeated five times. Test accounts are fake and shared, so they suit screenshots.

## Making a change

- Write all UI in UIKit, with Auto Layout and Combine. Don't add SwiftUI.
- Telegram for iOS is the reference for behaviour, gestures and layout logic. Port the relevant logic from [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) instead of approximating it, and adapt it to BetterTG's UIKit and TDLibKit code. BetterTG keeps its own look.
- Format every Swift file you change with SwiftFormat and the repository's `.swiftformat`.
- `./build.sh build` must finish without warnings. There is no test target yet, so check your change in the Simulator or on a device.
- Keep debug probes behind launch arguments and out of release code paths.
- When you add an open-source dependency, add its license text to `BetterTG/Resources/Licenses` and list it in `LicensesViewController` in the same change.
- [Parity](Parity/README.md) tracks parity with Telegram for iOS. Add a row to [Parity/checkpoint.md](Parity/checkpoint.md) when your change closes a gap.
- The push relay in `Backend` has its own checks; see [Backend/README.md](Backend/README.md#verification).
- [AGENTS.md](AGENTS.md) holds the same rules for coding agents, and `CLAUDE.md` links to it.

## Commits and pull requests

- Name commits `<type>(<scope>): <message>` in lowercase. The type is `feature` for something users notice, `fix` for a bug, or `tech` for internal work, as in `fix(chat): keep the draft after a failed send`.
- Keep each pull request to one topic. Describe what changed, why, and how you checked it. Include screenshots for UI changes.

## License

BetterTG is released under the [GNU General Public License v3.0](LICENSE). Your contributions are released under it too, and you keep the copyright to them.
