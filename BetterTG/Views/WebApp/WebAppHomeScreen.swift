// WebAppHomeScreen.swift

import UIKit

// MARK: - WebAppHomeScreen

/// WebAppController's home screen events. iOS can't tell whether the Web App's shortcut exists, so
/// `web_app_check_home_screen` answers "unknown"; `web_app_add_to_home_screen` (addToHomeScreen) opens the bot's
/// t.me link in Safari, whose Add to Home Screen makes the shortcut.
@MainActor enum WebAppHomeScreen {
    static func check(_ bridge: WebAppBridge) {
        bridge.send("home_screen_checked", ["status": "unknown"])
    }

    /// x-safari-https makes Safari open the link instead of the app it belongs to.
    static func add(_ bridge: WebAppBridge) {
        guard let username = bridge.botUsername, !username.isEmpty,
              let url = URL(string: "x-safari-https://t.me/\(username)?startapp&addToHomeScreen")
        else { return }
        UIApplication.shared.open(url)
    }
}
