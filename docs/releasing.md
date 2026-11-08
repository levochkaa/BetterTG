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
- Test Information in App Store Connect → TestFlight, which external testing needs: the beta description (say that the app uses the Telegram API), feedback email, privacy policy and the Beta App Review contact and notes. Sign-in needs a Telegram account. Telegram's test server lets App Review sign in without one (it refuses our own test-number sign-ins), so the notes, here and in App Review Information, walk the reviewer through it: ten quick taps on an empty area of the phone screen, Test Server, the number +99966 2 and four digits, the code 22222.
- The app's name is "BetterTG: Telegram Client", in Russian "BetterTG: клиент Telegram", as Swiftgram, Nicegram and iMe name theirs. Section 2.3 of the [Telegram API terms](https://core.telegram.org/api/terms) allows "Telegram" in the title only as "Unofficial Telegram", and section 4.2 lets Telegram revoke the API ID over it; Telegram hasn't enforced it on those clients. The description says in its first line that the app is unofficial and uses the Telegram API, as section 2.2 asks.

Xcode creates the distribution certificate and profiles itself through the API key. The lanes use `/Applications/Xcode-27.2.0.app` unless `BETTERTG_XCODE` names another Xcode.

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

The product page has the 39 App Store localizations. Each has seven 6.9" screenshots, five iPhone Duo screenshots of the unfolded landscape (2853x2007), a product page header (3840x1646) and a search results asset (3600x2400), made by `script/app_store_screenshots.py` from the readme demo's screens (see `CLAUDE.md`) and the locale's texts; its docstring lists the screens it takes. The screens show the app in the language Telegram has a language pack for, else in English. Take them on a new iPhone 17 Pro Max simulator and a new iPhone Duo simulator, neither signed in, with the status bar at 9:41. For each language, launch once without `-readme-demo` and with `-AppleLanguages (<language>)`, so the app downloads Telegram's strings for it, then with both. In Arabic and Hebrew the chat mirrors but the tab bar and the Duo's split view don't. The iPhone Duo screenshots, the header and the search results asset go through the App Store Connect API's Asset Library: an `appAssetLibraryImages` upload, then an `appAssetLibraryPlacements` on the version localization, in the `IPHONE_DUO_PROFILE` group for the Duo's screenshots and `DEFAULT_PROFILE` for the other two. The header and search asset show on iOS 27 and later. On the Duo, the settings list's BetterTG row can sit under the floating tab bar, so a script taps it beside the bar. Search results show the search results asset, or else the first three screenshots, so they carry the pitch. The keywords leave out the words of the name and subtitle, which App Store search already counts, and fit in 100 bytes; a Cyrillic or Greek letter takes two, a CJK, Thai or Devanagari one three.

The app and its notification extension ship a `PrivacyInfo.xcprivacy` with the reasons for the required-reason APIs they and TDLib call, and the data the push relay handles. Update it when the code calls another such API or the relay starts storing something new, and keep App Privacy in App Store Connect in line with it and with the [Privacy Policy](../Website/privacy.html). App Privacy, which only the website edits, declares Emails or Text Messages (the notification previews) and Device ID (the push token), both for App Functionality, linked to the user and not used for tracking. The age rating is 17+ because of the in-app browser's unrestricted web access.

The app declares `ITSAppUsesNonExemptEncryption` as `NO`, as Telegram for iOS does, so App Store Connect doesn't ask about export compliance for each build.
