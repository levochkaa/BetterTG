// BetterTGSettings.swift

import Combine
import Foundation

/// BetterTG's own options, as Swiftgram's SGSimpleSettings: on this device for every account, each with Swiftgram's
/// default. `changes` fires after any of them changes.
@MainActor final class BetterTGSettings {
    static let shared = BetterTGSettings()

    let changes = PassthroughSubject<Void, Never>()

    /// Swiftgram's Hide Tab Bar: Chats alone, with the archive and Settings as buttons in its bar.
    var hidesTabBar: Bool {
        get { bool("hideTabBar", default: false) }
        set { set(newValue, "hideTabBar") }
    }

    /// Swiftgram's Show Contacts Tab and Calls Tab for BetterTG's tabs: a hidden one opens from Chats' bar.
    var showsArchiveTab: Bool {
        get { bool("showArchiveTab", default: true) }
        set { set(newValue, "showArchiveTab") }
    }

    var showsSettingsTab: Bool {
        get { bool("showSettingsTab", default: true) }
        set { set(newValue, "showSettingsTab") }
    }

    /// Swiftgram's Show Tab Names.
    var showsTabNames: Bool {
        get { bool("showTabNames", default: true) }
        set { set(newValue, "showTabNames") }
    }

    /// Swiftgram's Wide Tab Bar: the bar keeps Telegram's full width.
    var wideTabBar: Bool {
        get { bool("wideTabBar", default: false) }
        set { set(newValue, "wideTabBar") }
    }

    var animatedMedia: Bool {
        get { UserDefaults.standard.object(forKey: "animatedMediaEnabled") as? Bool ?? true }
        set {
            guard newValue != animatedMedia else { return }
            UserDefaults.standard.set(newValue, forKey: "animatedMediaEnabled")
            changes.send()
        }
    }

    private init() {}

    private func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: "BetterTG.settings." + key) as? Bool ?? value
    }

    private func set(_ value: Bool, _ key: String) {
        UserDefaults.standard.set(value, forKey: "BetterTG.settings." + key)
        changes.send()
    }
}
