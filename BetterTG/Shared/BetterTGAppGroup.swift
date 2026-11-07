// BetterTGAppGroup.swift

import Foundation

enum BetterTGAppGroup {
    /// `BETTERTG_APP_GROUP` from the build settings, so a fork signed with its own bundle ID gets its own group.
    static let identifier = Bundle.main.object(forInfoDictionaryKey: "BetterTGAppGroup") as? String ?? ""

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    /// InAppNotificationSettings.displayNameOnLockscreen, shared with the notification service: on, notifications name
    /// their sender while the device is locked; on by default.
    static var displaysNamesOnLockScreen: Bool {
        get { defaults?.object(forKey: "displaysNamesOnLockScreen") as? Bool ?? true }
        set { defaults?.set(newValue, forKey: "displaysNamesOnLockScreen") }
    }

    static func containerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
