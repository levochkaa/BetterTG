# TDLibKit and the notification extension

BetterTG uses TDLib through [TDLibKit](https://github.com/levochkaa/TDLibKit), pinned to an exact release in `project.yml`. Both targets consume the dynamic `TDLibKitShared` product while importing the `TDLibKit` module. The app embeds the framework once; the notification service extension links it through `@executable_path/../../Frameworks` without embedding a second copy.

## Capabilities

Rich notifications need these on the Apple developer account, which Xcode's automatic signing sets up from the entitlements:

- The App Group `group.<bundle ID>` on both the app's and the extension's (`<bundle ID>.NotificationService`) App IDs. `Configuration/BetterTG.xcconfig` derives it from `BETTERTG_BUNDLE_ID`.
- Push Notifications, App Attest and Communication Notifications on the app's App ID.
