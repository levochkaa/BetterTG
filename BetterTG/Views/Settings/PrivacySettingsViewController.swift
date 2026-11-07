// PrivacySettingsViewController.swift

import TDLibKit
import UIKit

// MARK: - PrivacySettingsViewController

/// Telegram's Privacy and Security (PrivacyAndSecurityController): Blocked Users, Active Websites while there are
/// any, Two-Step Verification,
/// Auto-Delete Messages, the privacy rules with their summaries, and the inactivity period before account deletion,
/// whose menu also deletes the account now. Premium-only rules are not offered.
final class PrivacySettingsViewController: SettingsListViewController {
    private var rules = [PrivacyKind: PrivacyRuleState]()
    private var blockedCount: Int?
    private var websitesCount = 0
    private var hasPassword: Bool?
    /// The login email's pattern from getPasswordState, nil until it is read; empty without one.
    private var loginEmailPattern: String?
    private var autoDeleteTime: Int?
    private var accountTtlDays: Int?
    private var phoneNumber = ""
    /// can_archive_and_mute_new_chats_from_unknown_users, Telegram's autoarchive_setting_available.
    private var canAutoArchive = false
    private var archiveSettings: TDNativeArchiveChatListSettings?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("PrivacySettings.Title")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        load()
    }

    override func makeSections() -> [SettingsSection] {
        let loading = L10n.telegram("Channel.NotificationLoading")
        let blockedText = blockedCount.map { $0 == 0 ? L10n.telegram("PrivacySettings.BlockedPeersEmpty") : "\($0)" }
        let passwordText = hasPassword.map {
            L10n.telegram($0 ? "PrivacySettings.PasscodeOn" : "PrivacySettings.PasscodeOff")
        }
        let autoDeleteText = autoDeleteTime.map {
            $0 == 0 ? L10n.telegram("Autoremove.OptionOff") : SettingsFormatting.timeInterval(seconds: $0)
        }
        var securityRows = [SettingsRow(
            title: L10n.telegram("Settings.BlockedUsers"),
            detail: blockedText ?? loading,
            symbol: "hand.raised.fill",
            symbolTint: .systemRed,
            accessory: .disclosure,
        ) { [weak self] in
            self?.navigationController?.pushViewController(BlockedUsersViewController(), animated: true)
        }]
        if websitesCount > 0 {
            securityRows.append(SettingsRow(
                title: L10n.telegram("PrivacySettings.WebSessions"),
                detail: "\(websitesCount)",
                symbol: "globe",
                symbolTint: .systemBlue,
                accessory: .disclosure,
            ) { [weak self] in self?.openWebsites() })
        }
        let biometry = AppPasscode.shared.biometryType
        securityRows.append(SettingsRow(
            title: L10n.telegram(biometry == .faceID
                ? "PrivacySettings.PasscodeAndFaceId"
                : biometry == .touchID ? "PrivacySettings.PasscodeAndTouchId" : "PrivacySettings.Passcode"),
            detail: L10n.telegram(AppPasscode.shared.isSet
                ? "PrivacySettings.PasscodeOn"
                : "PrivacySettings.PasscodeOff"),
            symbol: "lock.fill",
            symbolTint: .systemGreen,
            accessory: .disclosure,
        ) { [weak self] in self?.openPasscode() })
        let security = SettingsSection(footer: L10n.telegram("Settings.AutoDeleteInfo"), rows: securityRows + [
            SettingsRow(
                title: L10n.telegram("PrivacySettings.TwoStepAuth"),
                detail: passwordText ?? loading,
                symbol: "key.fill",
                symbolTint: .systemOrange,
                accessory: .disclosure,
            ) { [weak self] in self?.openTwoStepVerification() },
            SettingsRow(
                title: L10n.telegram("Settings.AutoDeleteTitle"),
                detail: autoDeleteText ?? loading,
                symbol: "timer",
                symbolTint: .systemPurple,
                accessory: .disclosure,
                isEnabled: autoDeleteTime != nil,
            ) { [weak self] in self?.openAutoDelete() },
        ])
        // groupPrivacyFooter under the rules, Invites last among them.
        let privacy = SettingsSection(
            header: L10n.telegram("PrivacySettings.PrivacyTitle"),
            footer: L10n.telegram("PrivacySettings.InviteSectionFooter"),
            rows: PrivacyKind.allCases.map { kind in
                SettingsRow(
                    title: kind.rowTitle,
                    detail: rules[kind]?.summary ?? loading,
                    accessory: .disclosure,
                    isEnabled: rules[kind] != nil,
                ) { [weak self] in self?.openEditor(kind) }
            },
        )
        let leading = [security] + loginEmailSections() + [privacy] + autoArchiveSections()
        let accountSectionIndex = leading.count
        let account = SettingsSection(
            header: L10n.telegram("PrivacySettings.DeleteAccountTitle"),
            footer: L10n.telegram("PrivacySettings.DeleteAccountHelp"),
            rows: [SettingsRow(
                title: L10n.telegram("PrivacySettings.DeleteAccountIfAwayFor"),
                detail: accountTtlDays.map(Self.monthsText) ?? loading,
                isEnabled: accountTtlDays != nil,
            ) { [weak self] in self?.presentAccountTtlMenu(at: IndexPath(row: 0, section: accountSectionIndex)) }],
        )
        let dataSettings = SettingsSection(
            footer: L10n.telegram("PrivacySettings.DataSettingsHelp"),
            rows: [SettingsRow(title: L10n.telegram("PrivacySettings.DataSettings"), accessory: .disclosure) {
                [weak self] in
                self?.navigationController?.pushViewController(DataPrivacySettingsViewController(), animated: true)
            }],
        )
        let openLinksIn = SettingsSection(rows: [SettingsRow(
            title: L10n.telegram("ChatSettings.OpenLinksIn"),
            detail: WebBrowser.current.title,
            accessory: .disclosure,
        ) { [weak self] in
            self?.navigationController?.pushViewController(WebBrowserSettingsViewController(), animated: true)
        }])
        return leading + [account, dataSettings, openLinksIn]
    }

    private static func monthsText(_ days: Int) -> String {
        L10n.telegramPlural("MessageTimer.Months", count: max(1, days / 30))
    }

    /// New Chats From Unknown Users with Archive and Mute, where the server offers it to an account without Premium.
    private func autoArchiveSections() -> [SettingsSection] {
        guard canAutoArchive else { return [] }
        return [SettingsSection(
            header: L10n.telegram("PrivacySettings.AutoArchiveTitle"),
            footer: L10n.telegram("PrivacySettings.AutoArchiveInfo"),
            rows: [SettingsRow(
                title: L10n.telegram("PrivacySettings.AutoArchive"),
                accessory: .toggle(isOn: archiveSettings?.archiveAndMuteNewChatsFromUnknownUsers ?? false) {
                    [weak self] isOn in self?.setAutoArchive(isOn)
                },
                isEnabled: archiveSettings != nil,
            )],
        )]
    }

    /// updateAccountAutoArchiveChats, shown at once and taken back if TDLib refuses it.
    private func setAutoArchive(_ isOn: Bool) {
        guard let current = archiveSettings, contextIsCurrent else { return }
        let updated = TDNativeArchiveChatListSettings(
            archiveAndMuteNewChatsFromUnknownUsers: isOn,
            keepUnmutedChatsArchived: current.keepUnmutedChatsArchived,
            keepChatsFromFoldersArchived: current.keepChatsFromFoldersArchived,
        )
        archiveSettings = updated
        let client = client
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.setArchiveChatListSettings(settings: updated))
            } catch {
                guard let self, contextIsCurrent else { return }
                archiveSettings = current
                reload()
            }
        }
    }

    /// PrivacyAndSecurityController's Login Email: shown with a login email, for a +7 number or in Russian, as Telegram
    /// shows it; the footer offers to set one up or to change it.
    private func loginEmailSections() -> [SettingsSection] {
        guard let pattern = loginEmailPattern else { return [] }
        let shows = !pattern.isEmpty || phoneNumber.hasPrefix("7")
            || AppLocalization.shared.selectedLanguagePackID.hasPrefix("ru")
        guard shows else { return [] }
        let hasEmail = !pattern.isEmpty && !pattern.contains(" ")
        return [SettingsSection(
            footer: L10n.telegram(hasEmail ? "PrivacySettings.LoginEmailInfo" : "PrivacySettings.LoginEmailSetupInfo"),
            rows: [SettingsRow(
                title: L10n.telegram("PrivacySettings.LoginEmail"),
                symbol: "envelope.fill",
                symbolTint: .systemBlue,
                accessory: .disclosure,
            ) { [weak self] in self?.openLoginEmail(pattern: hasEmail ? pattern : nil) }],
        )]
    }

    /// openEmailSettings: with an email, its pattern over LoginEmailAlertText and Change Email; otherwise the setup.
    private func openLoginEmail(pattern: String?) {
        guard let pattern else {
            pushLoginEmailSetup(isChange: false)
            return
        }
        let alert = UIAlertController(
            title: pattern, message: L10n.telegram("PrivacySettings.LoginEmailAlertText"), preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("PrivacySettings.LoginEmailAlertChange"), style: .default) {
            [weak self] _ in self?.pushLoginEmailSetup(isChange: true)
        })
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func pushLoginEmailSetup(isChange: Bool) {
        let setup = LoginEmailViewController(client: client, isChange: isChange)
        setup.onCompleted = { [weak self] in self?.load() }
        navigationController?.pushViewController(setup, animated: true)
    }

    private func load() {
        guard contextIsCurrent else { return }
        let client = client
        Task { [weak self] in
            var loadedRules = [PrivacyKind: PrivacyRuleState]()
            for kind in PrivacyKind.allCases {
                if let value = try? await client
                    .send(TDNativeRequests.getUserPrivacySettingRules(setting: kind.setting))
                {
                    loadedRules[kind] = PrivacyRuleState(rules: value)
                }
            }
            let blocked = try? await client.send(TDNativeRequests.getBlockedMessageSenders(
                blockList: .blockListMain, offset: 0, limit: 1,
            ))
            let password = try? await client.send(TDNativeRequests.getPasswordState())
            let autoDelete = try? await client.send(TDNativeRequests.getDefaultMessageAutoDeleteTime())
            let ttl = try? await client.send(TDNativeRequests.getAccountTtl())
            let me = try? await client.getMe()
            let websites = try? await client.send(TDNativeRequests.getConnectedWebsites())
            var canAutoArchive = false
            if case .optionValueBoolean(let value) = try? await client.getOption(
                name: "can_archive_and_mute_new_chats_from_unknown_users",
            ) {
                canAutoArchive = value.value
            }
            #if DEBUG
                // `-ui-probe-privacy-autoarchive` shows the section the server offers only to some accounts.
                if ProcessInfo.processInfo.arguments.contains("-ui-probe-privacy-autoarchive") { canAutoArchive = true }
            #endif
            let archive = canAutoArchive
                ? try? await client.send(TDNativeRequests.getArchiveChatListSettings())
                : nil
            guard let self, contextIsCurrent else { return }
            self.canAutoArchive = canAutoArchive
            archiveSettings = archive
            websitesCount = websites?.websites.count ?? 0
            rules = loadedRules
            blockedCount = blocked?.totalCount
            hasPassword = password?.hasPassword
            loginEmailPattern = password?.loginEmailAddressPattern
            autoDeleteTime = autoDelete?.time
            accountTtlDays = ttl?.days
            phoneNumber = me?.phoneNumber ?? ""
            reload()
        }
    }

    /// openTwoStepVerification: TwoStepVerificationUnlockSettingsController, which reads the password's state.
    private func openTwoStepVerification() {
        guard contextIsCurrent else { return }
        let service = TDLibTwoStepVerificationService(client: client)
        Task { [weak self] in
            let configuration = try? await service.configuration()
            guard let self, contextIsCurrent else { return }
            navigationController?.pushViewController(
                TwoStepVerificationViewController.entry(for: configuration, service: service),
                animated: true,
            )
        }
    }

    private func openPasscode() {
        guard let navigationController else { return }
        PasscodeOptionsViewController.open(in: navigationController)
    }

    private func openWebsites() {
        let controller = ActiveWebsitesViewController()
        controller.onChange = { [weak self] count in
            self?.websitesCount = count
            self?.reload()
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func openEditor(_ kind: PrivacyKind) {
        guard let state = rules[kind] else { return }
        let editor = PrivacyRuleEditorViewController(kind: kind, state: state, phoneNumber: phoneNumber)
        editor.onChange = { [weak self] state in
            self?.rules[kind] = state
            self?.reload()
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    private func openAutoDelete() {
        guard let autoDeleteTime else { return }
        let controller = GlobalAutoDeleteViewController(currentTime: autoDeleteTime)
        controller.onChange = { [weak self] time in
            self?.autoDeleteTime = time
            self?.reload()
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    /// Telegram's If Away For menu: 1, 3, 6, 12, 18 or 24 months (setAccountTtl), then Delete Account Now, which
    /// opens DeleteAccountOptionsController.
    private func presentAccountTtlMenu(at indexPath: IndexPath) {
        guard let accountTtlDays, let cell = tableView.cellForRow(at: indexPath) else { return }
        var actions = [30, 90, 180, 365, 548, 730].map { days in
            TelegramContextMenuAction(
                title: Self.monthsText(days),
                image: accountTtlDays == days ? UIImage(systemName: "checkmark") : nil,
            ) { [weak self] in
                self?.perform { client in
                    _ = try await client.send(TDNativeRequests.setAccountTtl(ttl: TDNativeAccountTtl(days: days)))
                } completion: { [weak self] in
                    self?.accountTtlDays = days
                    self?.reload()
                }
            }
        }
        actions.append(TelegramContextMenuAction(
            title: L10n.telegram("PrivacySettings.DeleteAccountNow"),
            image: nil,
            isDestructive: true,
            startsNewSection: true,
        ) { [weak self] in
            guard let self else { return }
            DeleteAccountOptionsViewController.present(hasPassword: hasPassword ?? false, from: self)
        })
        presentTelegramContextMenu(sourceView: cell, actions: actions, presentationStyle: .menuOnly)
    }
}

// MARK: - PrivacyKind

/// The privacy rules Telegram lists under Privacy, with the texts of their SelectivePrivacySettingsController.
enum PrivacyKind: CaseIterable {
    case phoneNumber
    case lastSeen
    case profilePhoto
    case bio
    case birthday
    case forwards
    case calls
    case invites

    var setting: TDNativeUserPrivacySetting {
        switch self {
        case .phoneNumber: .userPrivacySettingShowPhoneNumber
        case .lastSeen: .userPrivacySettingShowStatus
        case .profilePhoto: .userPrivacySettingShowProfilePhoto
        case .bio: .userPrivacySettingShowBio
        case .birthday: .userPrivacySettingShowBirthdate
        case .forwards: .userPrivacySettingShowLinkInForwardedMessages
        case .calls: .userPrivacySettingAllowCalls
        case .invites: .userPrivacySettingAllowChatInvites
        }
    }

    var rowTitle: String {
        switch self {
        case .phoneNumber: L10n.telegram("PrivacySettings.PhoneNumber")
        case .lastSeen: L10n.telegram("PrivacySettings.LastSeen")
        case .profilePhoto: L10n.telegram("Privacy.ProfilePhoto")
        case .bio: L10n.telegram("Privacy.Bio")
        case .birthday: L10n.telegram("Privacy.Birthday")
        case .forwards: L10n.telegram("Privacy.Forwards")
        case .calls: L10n.telegram("Privacy.Calls")
        case .invites: L10n.telegram("PrivacySettings.InviteItem")
        }
    }

    var screenTitle: String {
        switch self {
        case .phoneNumber: L10n.telegram("Privacy.PhoneNumber")
        case .lastSeen: L10n.telegram("PrivacySettings.LastSeenTitle")
        case .calls: L10n.telegram("Settings.CallSettings")
        case .invites: L10n.telegram("Privacy.GroupsAndChannels")
        case .bio,
             .birthday,
             .forwards,
             .profilePhoto: rowTitle
        }
    }

    var header: String {
        switch self {
        case .phoneNumber: L10n.telegram("PrivacyPhoneNumberSettings.WhoCanSeeMyPhoneNumber")
        case .lastSeen: L10n.telegram("PrivacyLastSeenSettings.WhoCanSeeMyTimestamp")
        case .profilePhoto: L10n.telegram("Privacy.ProfilePhoto.WhoCanSeeMyPhoto")
        case .bio: L10n.telegram("Privacy.Bio.WhoCanSeeMyBio")
        case .birthday: L10n.telegram("Privacy.Birthday.WhoCanSeeMyBio")
        case .forwards: L10n.telegram("Privacy.Forwards.WhoCanForward")
        case .calls: L10n.telegram("Privacy.Calls.WhoCanCallMe")
        case .invites: L10n.telegram("Privacy.GroupsAndChannels.WhoCanAddMe")
        }
    }

    /// The help under the options; the phone number's names the public link instead.
    var info: String? {
        switch self {
        case .phoneNumber: nil
        case .lastSeen: L10n.telegram("PrivacyLastSeenSettings.CustomHelp")
        case .profilePhoto: L10n.telegram("Privacy.ProfilePhoto.CustomHelp")
        case .bio: L10n.telegram("Privacy.Bio.CustomHelp")
        case .birthday: L10n.telegram("Privacy.Birthday.CustomHelp")
        case .forwards: L10n.telegram("Privacy.Forwards.CustomHelp")
        case .calls: L10n.telegram("Privacy.Calls.CustomHelp")
        case .invites: L10n.telegram("Privacy.GroupsAndChannels.CustomHelp")
        }
    }

    var neverTitle: String {
        switch self {
        case .calls,
             .forwards,
             .invites: L10n.telegram("Privacy.GroupsAndChannels.NeverAllow")
        case .bio,
             .birthday,
             .lastSeen,
             .phoneNumber,
             .profilePhoto: L10n.telegram("PrivacyLastSeenSettings.NeverShareWith")
        }
    }

    var alwaysTitle: String {
        switch self {
        case .calls,
             .forwards,
             .invites: L10n.telegram("Privacy.GroupsAndChannels.AlwaysAllow")
        case .bio,
             .birthday,
             .lastSeen,
             .phoneNumber,
             .profilePhoto: L10n.telegram("PrivacyLastSeenSettings.AlwaysShareWith")
        }
    }
}

// MARK: - PrivacyRuleState

/// Telegram's SelectivePrivacySettings over TDLib's ordered rules: Everybody, My Contacts or Nobody, with users and
/// groups that are always or never allowed. Rules for bots and Premium users are kept as they were.
struct PrivacyRuleState: Equatable {
    enum Base: Equatable {
        case everybody
        case contacts
        case nobody
    }

    var base: Base
    var allowUserIDs = [Int64]()
    var allowChatIDs = [Int64]()
    var restrictUserIDs = [Int64]()
    var restrictChatIDs = [Int64]()
    var allowsBots = false
    var allowsPremiumUsers = false

    /// Exceptions that apply under the current base: Everybody keeps only Never, Nobody only Always.
    var showsNever: Bool { base != .nobody }
    var showsAlways: Bool { base != .everybody }

    var alwaysCount: Int { allowUserIDs.count + allowChatIDs.count }
    var neverCount: Int { restrictUserIDs.count + restrictChatIDs.count }

    /// Telegram's stringForSelectiveSettings.
    var summary: String {
        let never = showsNever ? neverCount : 0
        let always = showsAlways ? alwaysCount : 0
        switch base {
        case .everybody:
            return never == 0
                ? L10n.telegram("PrivacySettings.LastSeenEverybody")
                : L10n.telegram("PrivacySettings.LastSeenEverybodyMinus", String(never))
        case .contacts:
            if never > 0, always > 0 {
                return L10n.telegram("PrivacySettings.LastSeenContactsMinusPlus", String(never), String(always))
            } else if always > 0 {
                return L10n.telegram("PrivacySettings.LastSeenContactsPlus", String(always))
            } else if never > 0 {
                return L10n.telegram("PrivacySettings.LastSeenContactsMinus", String(never))
            }
            return L10n.telegram("PrivacySettings.LastSeenContacts")
        case .nobody:
            return always == 0
                ? L10n.telegram("PrivacySettings.LastSeenNobody")
                : L10n.telegram("PrivacySettings.LastSeenNobodyPlus", String(always))
        }
    }

    /// The rules for setUserPrivacySettingRules, exceptions first as Telegram sends them.
    var tdRules: TDNativeUserPrivacySettingRules {
        var rules = [TDNativeUserPrivacySettingRule]()
        if showsAlways {
            if !allowUserIDs.isEmpty {
                rules.append(.userPrivacySettingRuleAllowUsers(TDNativeUserPrivacySettingRuleAllowUsers(
                    userIds: allowUserIDs,
                )))
            }
            if !allowChatIDs.isEmpty {
                rules.append(.userPrivacySettingRuleAllowChatMembers(TDNativeUserPrivacySettingRuleAllowChatMembers(
                    chatIds: allowChatIDs,
                )))
            }
        }
        if showsNever {
            if !restrictUserIDs.isEmpty {
                rules.append(.userPrivacySettingRuleRestrictUsers(TDNativeUserPrivacySettingRuleRestrictUsers(
                    userIds: restrictUserIDs,
                )))
            }
            if !restrictChatIDs.isEmpty {
                rules.append(.userPrivacySettingRuleRestrictChatMembers(
                    TDNativeUserPrivacySettingRuleRestrictChatMembers(chatIds: restrictChatIDs),
                ))
            }
        }
        if base != .everybody {
            if allowsPremiumUsers { rules.append(.userPrivacySettingRuleAllowPremiumUsers) }
            if allowsBots { rules.append(.userPrivacySettingRuleAllowBots) }
        }
        switch base {
        case .everybody: rules.append(.userPrivacySettingRuleAllowAll)
        case .contacts: rules.append(.userPrivacySettingRuleAllowContacts)
        case .nobody: rules.append(.userPrivacySettingRuleRestrictAll)
        }
        return TDNativeUserPrivacySettingRules(rules: rules)
    }

    init(rules: TDNativeUserPrivacySettingRules) {
        var allowsAll = false
        var allowsContacts = false
        var allowsBots = false
        var allowsPremiumUsers = false
        var allowUserIDs = [Int64]()
        var allowChatIDs = [Int64]()
        var restrictUserIDs = [Int64]()
        var restrictChatIDs = [Int64]()
        for rule in rules.rules {
            switch rule {
            case .userPrivacySettingRuleAllowAll: allowsAll = true
            case .userPrivacySettingRuleAllowContacts: allowsContacts = true
            case .userPrivacySettingRuleAllowBots: allowsBots = true
            case .userPrivacySettingRuleAllowPremiumUsers: allowsPremiumUsers = true
            case .userPrivacySettingRuleAllowUsers(let value): allowUserIDs += value.userIds
            case .userPrivacySettingRuleAllowChatMembers(let value): allowChatIDs += value.chatIds
            case .userPrivacySettingRuleRestrictUsers(let value): restrictUserIDs += value.userIds
            case .userPrivacySettingRuleRestrictChatMembers(let value): restrictChatIDs += value.chatIds
            case .userPrivacySettingRuleRestrictAll,
                 .userPrivacySettingRuleRestrictBots,
                 .userPrivacySettingRuleRestrictContacts:
                break
            }
        }
        self.base = allowsAll ? .everybody : allowsContacts ? .contacts : .nobody
        self.allowUserIDs = allowUserIDs
        self.allowChatIDs = allowChatIDs
        self.restrictUserIDs = restrictUserIDs
        self.restrictChatIDs = restrictChatIDs
        self.allowsBots = allowsBots
        self.allowsPremiumUsers = allowsPremiumUsers
    }
}
