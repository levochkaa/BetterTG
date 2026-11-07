// SettingsSearch.swift

import Foundation
import UIKit

// MARK: - SettingsSearchItem

/// SettingsSearchableItem: a setting the Settings search finds by its title, its synonyms and the screens above it,
/// shown with its section's icon and those screens as breadcrumbs.
struct SettingsSearchItem {
    /// Where a found item leads.
    enum Target {
        /// What the Settings row does.
        case row(SettingsViewController.Row)
        /// A screen pushed over Settings.
        case screen(@MainActor () -> UIViewController)
        case twoStepVerification
        case deleteAccount
    }

    let id: String
    let title: String
    let alternate: [String]
    /// The Settings row whose icon the item shows.
    let icon: SettingsViewController.Row
    let breadcrumbs: [String]
    let target: Target
}

// MARK: - SettingsSearch

/// settingsSearchableItems and searchSettingsItems for the settings BetterTG has. Telegram's Premium, Business, Stars,
/// gifts, calls, Passport, themes and backgrounds are left out, as are its hidden items that only settings links
/// reach.
@MainActor enum SettingsSearch {
    private static let recentsKey = "BetterTG.settingsSearchRecents"
    /// addRecentSettingsSearchItem keeps the last 100.
    private static let recentsLimit = 100

    /// The item ids found before, latest first.
    static var recentIDs: [String] {
        UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
    }

    static func items() -> [SettingsSearchItem] {
        profileItems() + devicesItems() + stickerItems() + notificationItems() + privacyItems() + dataItems()
            + appItems()
    }

    /// searchSettingsItems: every word of the query starts a word of the item's title, synonyms or breadcrumbs
    /// below the first; one word may match any of them.
    static func search(_ items: [SettingsSearchItem], query: String) -> [SettingsSearchItem] {
        let queryTokens = tokens(query.lowercased())
        guard !queryTokens.isEmpty else { return [] }
        return items.filter { item in
            var string = item.title
            for alternate in item.alternate {
                let trimmed = alternate.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { string += " \(trimmed)" }
            }
            if item.breadcrumbs.count > 1 {
                string += " " + item.breadcrumbs.dropFirst().joined(separator: " ")
            }
            let itemTokens = tokens(string)
            return queryTokens.allSatisfy { query in itemTokens.contains { $0.hasPrefix(query) } }
        }
    }

    static func addRecent(_ id: String) {
        var ids = recentIDs.filter { $0 != id }
        ids.insert(id, at: 0)
        UserDefaults.standard.set(Array(ids.prefix(recentsLimit)), forKey: recentsKey)
    }

    static func removeRecent(_ id: String) {
        UserDefaults.standard.set(recentIDs.filter { $0 != id }, forKey: recentsKey)
    }

    static func clearRecents() {
        UserDefaults.standard.removeObject(forKey: recentsKey)
    }

    /// stringTokens: the string's words, folded and lowercased, each once.
    private static func tokens(_ string: String) -> [String] {
        let folded = string.folding(options: .diacriticInsensitive, locale: .current).lowercased() as NSString
        let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault, folded, CFRangeMake(0, folded.length), kCFStringTokenizerUnitWord,
            CFLocaleCopyCurrent(),
        )
        var result = [String]()
        var seen = Set<String>()
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard range.location >= 0, range.length > 0 else { continue }
            let token = folded.substring(with: NSRange(location: range.location, length: range.length))
            if seen.insert(token).inserted { result.append(token) }
        }
        return result
    }

    /// synonyms: a SettingsSearch.Synonyms string's lines.
    private static func synonyms(_ key: String) -> [String] {
        let value = L10n.telegram(key)
        guard value != key, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return value.components(separatedBy: "\n")
    }

    private static func item(
        _ id: String,
        _ titleKey: String,
        synonyms synonymsKey: String? = nil,
        icon: SettingsViewController.Row,
        breadcrumbs: [String] = [],
        target: SettingsSearchItem.Target,
    ) -> SettingsSearchItem {
        SettingsSearchItem(
            id: id,
            title: L10n.telegram(titleKey),
            alternate: synonymsKey.map(synonyms) ?? [],
            icon: icon,
            breadcrumbs: breadcrumbs.map { L10n.telegram($0) },
            target: target,
        )
    }

    private static func profileItems() -> [SettingsSearchItem] {
        let crumbs = ["EditProfile.Title"]
        return [
            item(
                "edit/username", "Settings.Username", synonyms: "SettingsSearch.Synonyms.EditProfile.Username",
                icon: .profile, breadcrumbs: crumbs, target: .screen { UsernameSetupViewController() },
            ),
            item(
                "edit/birthday", "Settings.Birthday", icon: .profile, breadcrumbs: crumbs,
                target: .screen { EditProfileViewController() },
            ),
            item(
                "edit/add-account", "Settings.AddAccount", synonyms: "SettingsSearch.Synonyms.EditProfile.AddAccount",
                icon: .profile, breadcrumbs: crumbs, target: .row(.addAccount),
            ),
            item(
                "edit/log-out", "Settings.Logout", synonyms: "SettingsSearch.Synonyms.EditProfile.Logout",
                icon: .profile, breadcrumbs: crumbs, target: .row(.logOut),
            ),
            item("my-profile", "Settings.MyProfile", icon: .myProfile, target: .row(.myProfile)),
            item(
                "saved-messages", "Settings.SavedMessages", synonyms: "SettingsSearch.Synonyms.SavedMessages",
                icon: .savedMessages, target: .row(.savedMessages),
            ),
        ]
    }

    private static func devicesItems() -> [SettingsSearchItem] {
        var devices = item(
            "devices", "Settings.Devices", synonyms: "SettingsSearch.Synonyms.Privacy.AuthSessions",
            icon: .devices, target: .row(.devices),
        )
        devices = SettingsSearchItem(
            id: devices.id, title: devices.title,
            alternate: devices.alternate + [L10n.telegram("PrivacySettings.AuthSessions")],
            icon: devices.icon, breadcrumbs: devices.breadcrumbs, target: devices.target,
        )
        return [
            devices,
            item(
                "devices/terminate-sessions", "AuthSessions.TerminateOtherSessions",
                synonyms: "SettingsSearch.Synonyms.Devices.TerminateOtherSessions", icon: .devices,
                breadcrumbs: ["Settings.Devices"], target: .row(.devices),
            ),
            item(
                "folders", "Settings.ChatFolders", synonyms: "SettingsSearch.Synonyms.ChatFolders",
                icon: .chatFolders, target: .row(.chatFolders),
            ),
        ]
    }

    /// Telegram's Stickers and Emoji; BetterTG keeps them under Appearance.
    private static func stickerItems() -> [SettingsSearchItem] {
        let crumbs = ["ChatSettings.Stickers"]
        let stickers = SettingsSearchItem.Target.screen { InstalledStickerSetsViewController(mode: .stickers) }
        return [
            item(
                "appearance/stickers-and-emoji", "ChatSettings.Stickers",
                synonyms: "SettingsSearch.Synonyms.Stickers.Title", icon: .appearance, target: stickers,
            ),
            item(
                "appearance/stickers-and-emoji/suggest-by-emoji", "Stickers.SuggestStickers",
                synonyms: "SettingsSearch.Synonyms.Stickers.SuggestStickers", icon: .appearance,
                breadcrumbs: crumbs, target: stickers,
            ),
            item(
                "appearance/stickers-and-emoji/trending", "StickerPacksSettings.FeaturedPacks",
                synonyms: "SettingsSearch.Synonyms.Stickers.FeaturedPacks", icon: .appearance,
                breadcrumbs: crumbs, target: .screen { FeaturedStickersViewController() },
            ),
            item(
                "appearance/stickers-and-emoji/archived", "StickerPacksSettings.ArchivedPacks",
                synonyms: "SettingsSearch.Synonyms.Stickers.ArchivedPacks", icon: .appearance,
                breadcrumbs: crumbs, target: .screen { ArchivedStickerSetsViewController(mode: .stickers) },
            ),
            item(
                "appearance/stickers-and-emoji/large-emoji", "Appearance.LargeEmoji",
                synonyms: "SettingsSearch.Synonyms.Appearance.LargeEmoji", icon: .appearance,
                breadcrumbs: crumbs, target: stickers,
            ),
            item(
                "appearance/stickers-and-emoji/dynamic-order", "StickerPacksSettings.DynamicOrder",
                icon: .appearance, breadcrumbs: crumbs, target: stickers,
            ),
            item(
                "appearance/stickers-and-emoji/emoji", "StickerPacksSettings.Emoji", icon: .appearance,
                breadcrumbs: crumbs, target: .screen { InstalledStickerSetsViewController(mode: .emoji) },
            ),
            item(
                "appearance/stickers-and-emoji/emoji/quick-reaction", "Settings.QuickReactionSetup.Title",
                icon: .appearance, breadcrumbs: crumbs, target: .screen { QuickReactionSetupViewController() },
            ),
        ]
    }

    private static func notificationItems() -> [SettingsSearchItem] {
        let crumbs = ["Settings.NotificationsAndSounds"]
        let notifications = SettingsSearchItem.Target.row(.notifications)
        func child(_ id: String, _ title: String, _ synonyms: String? = nil) -> SettingsSearchItem {
            item(
                "notifications/" + id, title, synonyms: synonyms.map { "SettingsSearch.Synonyms.Notifications." + $0 },
                icon: .notifications, breadcrumbs: crumbs, target: notifications,
            )
        }
        return [
            item(
                "notifications", "Settings.NotificationsAndSounds",
                synonyms: "SettingsSearch.Synonyms.Notifications.Title", icon: .notifications, target: notifications,
            ),
            child("private-chats", "Notifications.PrivateChats", "MessageNotificationsSound"),
            child("groups", "Notifications.GroupChats"),
            child("channels", "Notifications.Channels"),
            child("stories", "Notifications.Stories", "MessageNotificationsSound"),
            item(
                "notifications/reactions", "Notifications.Reactions", icon: .notifications, breadcrumbs: crumbs,
                target: .screen { ReactionNotificationSettingsViewController() },
            ),
            child("in-app-sounds", "Notifications.InAppNotificationsSounds", "InAppNotificationsSound"),
            child("in-app-vibrate", "Notifications.InAppNotificationsVibrate", "InAppNotificationsVibrate"),
            child("in-app-preview", "Notifications.InAppNotificationsPreview", "InAppNotificationsPreview"),
            child("count-unread-messages", "Notifications.Badge.CountUnreadMessages", "BadgeCountUnreadMessages"),
            child("new-contacts", "NotificationSettings.ContactJoined", "ContactJoined"),
            child("reset", "Notifications.ResetAllNotifications", "ResetAllNotifications"),
        ]
    }

    private static func privacyItems() -> [SettingsSearchItem] {
        let crumbs = ["Settings.PrivacySettings"]
        let privacy = SettingsSearchItem.Target.row(.privacy)
        func child(
            _ id: String,
            _ title: String,
            _ synonyms: String? = nil,
            target: SettingsSearchItem.Target = .row(.privacy),
        ) -> SettingsSearchItem {
            item(
                "privacy/" + id, title, synonyms: synonyms.map { "SettingsSearch.Synonyms.Privacy." + $0 },
                icon: .privacy, breadcrumbs: crumbs, target: target,
            )
        }
        let dataCrumbs = ["Settings.PrivacySettings", "PrivacySettings.DataSettings"]
        let data = SettingsSearchItem.Target.screen { DataPrivacySettingsViewController() }
        func dataChild(_ id: String, _ title: String, _ synonyms: String) -> SettingsSearchItem {
            item(
                "privacy/data-settings/" + id, title, synonyms: "SettingsSearch.Synonyms.Privacy.Data." + synonyms,
                icon: .privacy, breadcrumbs: dataCrumbs, target: data,
            )
        }
        var selfDestruct = child("self-destruct", "PrivacySettings.DeleteAccountTitle", "DeleteAccountIfAwayFor")
        selfDestruct = SettingsSearchItem(
            id: selfDestruct.id, title: selfDestruct.title.capitalized, alternate: selfDestruct.alternate,
            icon: selfDestruct.icon, breadcrumbs: selfDestruct.breadcrumbs, target: selfDestruct.target,
        )
        return [
            item(
                "privacy", "Settings.PrivacySettings", synonyms: "SettingsSearch.Synonyms.Privacy.Title",
                icon: .privacy, target: privacy,
            ),
            child("blocked", "Settings.BlockedUsers", "BlockedUsers", target: .screen { BlockedUsersViewController() }),
            child("last-seen", "PrivacySettings.LastSeen", "LastSeen"),
            child("profile-photos", "Privacy.ProfilePhoto", "ProfilePhoto"),
            child("forwards", "Privacy.Forwards", "Forwards"),
            child("calls", "Privacy.Calls", "Calls"),
            child("invites", "Privacy.GroupsAndChannels", "GroupsAndChannels"),
            child("bio", "Privacy.Bio"),
            child("birthday", "Privacy.Birthday"),
            child("phone-number", "Privacy.PhoneNumber"),
            child("2sv", "PrivacySettings.TwoStepAuth", "TwoStepAuth", target: .twoStepVerification),
            child("auto-delete", "Settings.AutoDeleteTitle"),
            child("login-email", "PrivacySettings.LoginEmail"),
            child(
                "active-websites", "PrivacySettings.WebSessions", "AuthSessions",
                target: .screen { ActiveWebsitesViewController() },
            ),
            selfDestruct,
            child("data-settings", "PrivacySettings.DataSettings", "Data.Title", target: data),
            item(
                "privacy/open-links", "ChatSettings.OpenLinksIn",
                synonyms: "SettingsSearch.Synonyms.ChatSettings.OpenLinksIn", icon: .privacy, breadcrumbs: crumbs,
                target: .screen { WebBrowserSettingsViewController() },
            ),
            dataChild("delete-synced", "Privacy.ContactsReset", "ContactsReset"),
            dataChild("suggest-contacts", "Privacy.TopPeers", "TopPeers"),
            dataChild("delete-cloud-drafts", "Privacy.DeleteDrafts", "DeleteDrafts"),
            item(
                "delete-account", "DeleteAccount.DeleteMyAccount",
                synonyms: "SettingsSearch.DeleteAccount.DeleteMyAccount", icon: .privacy, target: .deleteAccount,
            ),
        ]
    }

    private static func dataItems() -> [SettingsSearchItem] {
        let crumbs = ["Settings.ChatSettings"]
        let data = SettingsSearchItem.Target.row(.dataAndStorage)
        let storage = SettingsSearchItem.Target.screen { StorageUsageViewController() }
        func child(
            _ id: String,
            _ title: String,
            _ synonyms: String? = nil,
            target: SettingsSearchItem.Target = .row(.dataAndStorage),
        ) -> SettingsSearchItem {
            item(
                "data/" + id, title, synonyms: synonyms.map { "SettingsSearch.Synonyms.Data." + $0 },
                icon: .dataAndStorage, breadcrumbs: crumbs, target: target,
            )
        }
        return [
            item(
                "data", "Settings.ChatSettings", synonyms: "SettingsSearch.Synonyms.Data.Title",
                icon: .dataAndStorage, target: data,
            ),
            child("storage", "ChatSettings.Cache", "Storage.Title", target: storage),
            item(
                "data/storage/clear-cache", "Cache.ClearCache",
                synonyms: "SettingsSearch.Synonyms.Data.Storage.ClearCache", icon: .dataAndStorage,
                breadcrumbs: ["Settings.ChatSettings", "ChatSettings.Cache"], target: storage,
            ),
            child("usage", "NetworkUsageSettings.Title", "NetworkUsage", target: .screen {
                NetworkUsageViewController()
            }),
            child(
                "auto-download/mobile", "ChatSettings.AutoDownloadUsingCellular", "AutoDownloadUsingCellular",
                target: .screen { AutoDownloadConnectionViewController(networkType: .cellular) },
            ),
            child(
                "auto-download/wifi", "ChatSettings.AutoDownloadUsingWiFi", "AutoDownloadUsingWifi",
                target: .screen { AutoDownloadConnectionViewController(networkType: .wifi) },
            ),
            child("auto-download/reset", "ChatSettings.AutoDownloadReset", "AutoDownloadReset"),
            child("save-edited-photos", "Settings.SaveEditedPhotos", "SaveEditedPhotos"),
            child("pause-music", "Settings.PauseMusicOnRecording"),
            child("raise-to-listen", "Settings.RaiseToListen"),
            item(
                "data/proxy", "Settings.Proxy", synonyms: "SettingsSearch.Synonyms.Proxy.Title", icon: .proxy,
                target: .row(.proxy),
            ),
            item(
                "data/proxy/add-proxy", "SocksProxySetup.AddProxy",
                synonyms: "SettingsSearch.Synonyms.Proxy.AddProxy", icon: .proxy, breadcrumbs: ["Settings.Proxy"],
                target: .screen { ProxyServerSettingsViewController(editedProxy: nil) },
            ),
        ]
    }

    private static func appItems() -> [SettingsSearchItem] {
        let languageCrumbs = ["Settings.AppLanguage"]
        return [
            item("power-saving", "Settings.PowerSaving", icon: .powerSaving, target: .row(.powerSaving)),
            item(
                "appearance", "Settings.Appearance", synonyms: "SettingsSearch.Synonyms.Appearance.Title",
                icon: .appearance, target: .row(.appearance),
            ),
            item(
                "language", "Settings.AppLanguage", synonyms: "SettingsSearch.Synonyms.AppLanguage",
                icon: .language, target: .row(.language),
            ),
            item(
                "language/show-button", "Localization.ShowTranslate",
                synonyms: "SettingsSearch.Synonyms.Language.ShowTranslateButton", icon: .language,
                breadcrumbs: languageCrumbs, target: .row(.language),
            ),
            item(
                "language/do-not-translate", "Localization.DoNotTranslate",
                synonyms: "SettingsSearch.Synonyms.Language.DoNotTranslate", icon: .language,
                breadcrumbs: languageCrumbs, target: .screen {
                    TranslationLanguagesViewController(mode: .doNotTranslate)
                },
            ),
            item(
                "ask-question", "Settings.Support", synonyms: "SettingsSearch.Synonyms.Support", icon: .support,
                target: .row(.support),
            ),
            item("faq", "Settings.FAQ", synonyms: "SettingsSearch.Synonyms.FAQ", icon: .faq, target: .row(.faq)),
            item("features", "Settings.Tips", icon: .tips, target: .row(.tips)),
            item("privacy-policy", "Permissions.PrivacyPolicy", icon: .privacyPolicy, target: .row(.privacyPolicy)),
        ]
    }
}

// MARK: - SettingsSearchRecentHeaderView

/// ChatListSearchItemHeader's recentPeers over the recent items: Recent, and Clear on the right.
final class SettingsSearchRecentHeaderView: UIView {
    static let height: CGFloat = 38

    var onClear: (() -> Void)?

    private let titleLabel = UILabel()
    private let clearButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.text = L10n.telegram("DialogList.SearchSectionRecent").uppercased()
        titleLabel.font = .preferredFont(forTextStyle: .footnote)
        titleLabel.textColor = .secondaryLabel
        clearButton.setTitle(L10n.telegram("WebSearch.RecentSectionClear"), for: .normal)
        clearButton.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        clearButton.addAction(UIAction { [weak self] _ in self?.onClear?() }, for: .touchUpInside)
        for subview in [titleLabel, clearButton] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            clearButton.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            clearButton.lastBaselineAnchor.constraint(equalTo: titleLabel.lastBaselineAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
