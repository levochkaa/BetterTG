# Releasing

BetterTG ships through TestFlight and the App Store with the [fastlane](https://fastlane.tools) lanes in `fastlane/Fastfile`. A lane archives with `./build.sh archive`, exports an App Store IPA with Xcode's automatic signing and uploads it with an App Store Connect API key.

## One-time setup

- Ruby 4.0.7 from `.ruby-version` (`rbenv install 4.0.7`), then `bundle install`.
- An App Store Connect API key with the App Manager role. Put it in `fastlane/api_key.json`, which git ignores and `./script/prepare_worktree.sh` copies into new worktrees:

  ```json
  {
    "key_id": "KEY_ID",
    "issuer_id": "ISSUER_ID",
    "key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----",
    "duration": 1200,
    "in_house": false
  }
  ```

  CI can set `BETTERTG_ASC_API_KEY_ID`, `BETTERTG_ASC_API_KEY_ISSUER_ID` and `BETTERTG_ASC_API_KEY_PATH` (a `.p8` file) or `BETTERTG_ASC_API_KEY_CONTENT` instead.
- The app record in App Store Connect for the bundle ID in `Configuration/BetterTG.xcconfig`, or in `Configuration/Local.xcconfig` for a fork.
- TestFlight groups: the `Internal` group gets every processed build; external lanes send to `External`, which has a public link, unless told otherwise.
- Test Information in App Store Connect → TestFlight, which external testing needs: the beta description (say that the app uses the Telegram API), feedback email, privacy policy and the Beta App Review contact and notes. Sign-in needs a Telegram number, so the notes ask the reviewer to sign in with their own.
- The app's name must not contain "Telegram" except as "Unofficial Telegram", under section 2.3 of the [Telegram API terms](https://core.telegram.org/api/terms).

Xcode creates the distribution certificate and profiles itself through the API key. The lanes use `/Applications/Xcode-27.1.0.app` unless `BETTERTG_XCODE` names another Xcode.

## Lanes

```bash
bundle exec fastlane ios internal                     # TestFlight for internal testers
bundle exec fastlane ios external                     # TestFlight for the External group, after Beta App Review
bundle exec fastlane ios external groups:"Friends"    # other external groups, comma-separated
bundle exec fastlane ios release                      # upload a build for the App Store version
bundle exec fastlane ios release submit:true          # and submit it for review
bundle exec fastlane ios next_build_number
```

Every lane takes `build_number:` (default: the latest TestFlight build plus one) and `ipa:` to upload an IPA built before instead of building. The TestFlight lanes take `changelog:`, which becomes What to Test; it defaults to the version, the build number and the last commit. `BETTERTG_TESTFLIGHT_INTERNAL_GROUPS` and `BETTERTG_TESTFLIGHT_EXTERNAL_GROUPS` set default groups.

The marketing version is `MARKETING_VERSION` in `project.yml`. Raise it before a new App Store version. Archives and IPAs stay in `.build/distribution/<version>-<build>`.

`release` uploads the binary only: write the App Store description, screenshots and What's New in App Store Connect, then submit there or pass `submit:true`. Releases go out manually after approval.

The app and its notification extension ship a `PrivacyInfo.xcprivacy` with the reasons for the required-reason APIs they and TDLib call, and the data the push relay handles. Update it when the code calls another such API or the relay starts storing something new, and keep App Privacy in App Store Connect in line with it and with the [Privacy Policy](../Website/privacy.html).

The app declares `ITSAppUsesNonExemptEncryption` as `NO`, as Telegram for iOS does, so App Store Connect doesn't ask about export compliance for each build.
