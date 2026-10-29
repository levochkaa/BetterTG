// InAppNotifications.swift

import AudioToolbox
import Combine
import UIKit
import UserNotifications

// MARK: - InAppNotificationSettings

/// Telegram's InAppNotificationSettings kept on the device for every account: In-App Sounds (on), In-App Vibrate
/// (off), In-App Preview (on), and the badge's Count Unread Messages (on; off counts chats).
enum InAppNotificationSettings {
    private enum Keys {
        static let playSounds = "BetterTG.inApp.playSounds"
        static let vibrate = "BetterTG.inApp.vibrate"
        static let displayPreviews = "BetterTG.inApp.displayPreviews"
        static let badgeCountsMessages = "BetterTG.badge.countsMessages"
    }

    static var playSounds: Bool {
        get { UserDefaults.standard.object(forKey: Keys.playSounds) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.playSounds) }
    }

    static var vibrate: Bool {
        get { UserDefaults.standard.object(forKey: Keys.vibrate) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: Keys.vibrate) }
    }

    static var displayPreviews: Bool {
        get { UserDefaults.standard.object(forKey: Keys.displayPreviews) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.displayPreviews) }
    }

    /// totalUnreadCountDisplayCategory: the badge counts unread messages, or unread chats when off.
    @MainActor static var badgeCountsMessages: Bool {
        get { UserDefaults.standard.object(forKey: Keys.badgeCountsMessages) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.badgeCountsMessages)
            AppBadge.shared.refresh()
        }
    }
}

// MARK: - ServiceSoundManager

/// Telegram's ServiceSoundManager: MessageSent once a sent message is delivered, the notification sound for a new
/// message while the app is open, and the vibration. System sounds follow the ring/silent switch.
@MainActor final class ServiceSoundManager {
    static let shared = ServiceSoundManager()

    private lazy var messageDeliverySound = Self.loadSound("MessageSent")
    private lazy var incomingMessageSound = Self.loadSound("notification")
    private var lastDeliverySound = Date.distantPast

    private static func loadSound(_ name: String) -> SystemSoundID? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { return nil }
        var sound: SystemSoundID = 0
        return AudioServicesCreateSystemSoundID(url as CFURL, &sound) == noErr ? sound : nil
    }

    /// An album's messages are delivered one by one; Telegram plays once for the group.
    func playMessageDeliveredSound() {
        guard Date().timeIntervalSince(lastDeliverySound) > 0.3, let messageDeliverySound else { return }
        lastDeliverySound = Date()
        AudioServicesPlaySystemSound(messageDeliverySound)
    }

    func playIncomingMessageSound() {
        guard let incomingMessageSound else { return }
        AudioServicesPlaySystemSound(incomingMessageSound)
    }

    func playVibrationSound() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
}

// MARK: - AppBadge

/// The app badge: the active account's unread messages, or unread chats, outside muted chats, as Telegram's Badge
/// Counter shows them by default.
@MainActor final class AppBadge {
    static let shared = AppBadge()

    private var unreadMessages = 0
    private var unreadChats = 0

    func update(unreadMessages: Int) {
        self.unreadMessages = unreadMessages
        refresh()
    }

    func update(unreadChats: Int) {
        self.unreadChats = unreadChats
        refresh()
    }

    func refresh() {
        let count = InAppNotificationSettings.badgeCountsMessages ? unreadMessages : unreadChats
        UNUserNotificationCenter.current().setBadgeCount(max(0, count)) { error in
            if let error { log("App badge update failed: \(error.localizedDescription)") }
        }
    }
}

// MARK: - InAppNotificationPresentation

/// ApplicationContext's handling of a new message while the app is open, for a push that arrives in the foreground:
/// nothing while the passcode lock is up; otherwise a message that isn't silent plays Telegram's notification sound
/// with In-App Sounds and vibrates with In-App Vibrate, and In-App Preview shows the banner unless the message's chat
/// is open. The system banner stands in for ChatMessageNotificationItem.
@MainActor enum InAppNotificationPresentation {
    static func options(for route: PushNotificationRoute?, isSilent: Bool) -> UNNotificationPresentationOptions {
        guard let route else { return [.banner, .list, .sound] }
        guard !AppPasscode.shared.isLocked else { return [.list] }
        if !isSilent {
            if InAppNotificationSettings.playSounds { ServiceSoundManager.shared.playIncomingMessageSound() }
            if InAppNotificationSettings.vibrate { ServiceSoundManager.shared.playVibrationSound() }
        }
        guard InAppNotificationSettings.displayPreviews, !isChatVisible(route) else { return [.list] }
        return [.banner, .list]
    }

    /// A chat screen for the message's chat anywhere in the stack, in its thread when the message has one.
    private static func isChatVisible(_ route: PushNotificationRoute) -> Bool {
        if let accountID = route.accountID,
           TDLib.shared.accounts.first(where: { $0.id == TDLib.shared.activeAccountID })?.userID != accountID
        {
            return false
        }
        let chatID =
            switch route.peerType {
            case .privateChat: route.peerID
            case .basicGroup: -route.peerID
            case .supergroup: -1_000_000_000_000 - route.peerID
            }
        return NavigationStorage.shared.viewControllers.contains { controller in
            guard let location = (controller as? ChatViewController)?.location, location.chatID == chatID else {
                return false
            }
            guard let topServerMessageID = route.topServerMessageID else { return true }
            return location.forumTopicID == Int(topServerMessageID)
                || location.messageThreadID == route.tdlibTopMessageID
        }
    }
}
