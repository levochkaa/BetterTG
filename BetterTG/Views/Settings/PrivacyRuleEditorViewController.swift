// PrivacyRuleEditorViewController.swift

import TDLibKit
import UIKit

// MARK: - PrivacyRuleEditorViewController

/// Telegram's SelectivePrivacySettingsController for one rule: Everybody, My Contacts or Nobody, the rule's help, the
/// exceptions that apply to the chosen option, for the phone number who can find the account by it, and for calls
/// who they go peer-to-peer with. Each choice saves at once with setUserPrivacySettingRules.
final class PrivacyRuleEditorViewController: SettingsListViewController {
    /// The gift settings as plain values to change one of them.
    private struct GiftDraft {
        var showGiftButton: Bool
        var unlimitedGifts: Bool
        var limitedGifts: Bool
        var upgradedGifts: Bool
        var giftsFromChannels: Bool
        var premiumSubscription: Bool

        var settings: TDNativeGiftSettings {
            TDNativeGiftSettings(showGiftButton: showGiftButton, acceptedGiftTypes: TDNativeAcceptedGiftTypes(
                unlimitedGifts: unlimitedGifts,
                limitedGifts: limitedGifts,
                upgradedGifts: upgradedGifts,
                giftsFromChannels: giftsFromChannels,
                premiumSubscription: premiumSubscription,
            ))
        }

        init(_ settings: TDNativeGiftSettings) {
            let types = settings.acceptedGiftTypes
            self.showGiftButton = settings.showGiftButton
            self.unlimitedGifts = types.unlimitedGifts
            self.limitedGifts = types.limitedGifts
            self.upgradedGifts = types.upgradedGifts
            self.giftsFromChannels = types.giftsFromChannels
            self.premiumSubscription = types.premiumSubscription
        }
    }

    var onChange: ((PrivacyRuleState) -> Void)?

    private let kind: PrivacyKind
    private let phoneNumber: String
    private var state: PrivacyRuleState
    /// Who can find the account by its number (userPrivacySettingAllowFindingByPhoneNumber).
    private var discovery: PrivacyRuleState?
    /// Who calls go peer-to-peer with (userPrivacySettingAllowPeerToPeerCalls).
    private var peerToPeer: PrivacyRuleState?
    /// The gifts rule's Show Gift Icon and accepted gift types (the account's giftSettings), which need Premium.
    private var giftSettings: TDNativeGiftSettings?
    private var isPremium = false

    private var exceptionsInfo: String {
        guard kind == .profilePhoto else { return L10n.telegram("PrivacyLastSeenSettings.CustomShareSettingsHelp") }
        return switch state.base {
        case .nobody: L10n.telegram("Privacy.ProfilePhoto.CustomOverrideAddInfo")
        case .contacts: L10n.telegram("Privacy.ProfilePhoto.CustomOverrideBothInfo")
        case .everybody: L10n.telegram("Privacy.ProfilePhoto.CustomOverrideInfo")
        }
    }

    init(kind: PrivacyKind, state: PrivacyRuleState, phoneNumber: String) {
        self.kind = kind
        self.state = state
        self.phoneNumber = phoneNumber
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = kind.screenTitle
        if kind == .phoneNumber { loadDiscovery() }
        if kind == .calls { loadPeerToPeer() }
        if kind == .gifts { loadGiftSettings() }
    }

    override func makeSections() -> [SettingsSection] {
        let options: [(PrivacyRuleState.Base, String)] = [
            (.everybody, L10n.telegram("PrivacySettings.LastSeenEverybody")),
            (.contacts, L10n.telegram("PrivacySettings.LastSeenContacts")),
            (.nobody, L10n.telegram("PrivacySettings.LastSeenNobody")),
        ]
        let publicLink = L10n.telegram("PrivacyPhoneNumberSettings.CustomPublicLink", "+\(phoneNumber)")
            .withoutTelegramLinks
            .replacing("[", with: "")
            .replacing("]", with: "")
        let info = kind == .phoneNumber ? (state.base == .nobody ? nil : publicLink) : kind.info
        // Gifts nobody may send leave nothing to display, so the choice is off (permisisonsEnabled).
        let optionsEnabled = giftSettings.map { settings in
            let types = settings.acceptedGiftTypes
            return types.unlimitedGifts || types.limitedGifts || types.upgradedGifts
        } ?? true
        var sections = [SettingsSection(
            header: kind.header,
            footer: info,
            rows: options.map { base, title in
                SettingsRow(
                    title: title,
                    accessory: state.base == base ? .checkmark : .none,
                    isEnabled: optionsEnabled,
                ) { [weak self] in
                    self?.select(base)
                }
            },
        )]
        if let giftSettings {
            // The gift icon's switch leads the screen, its # drawn as the gift.
            sections.insert(SettingsSection(
                footer: L10n.telegram("Privacy.Gifts.ShowGiftButtonInfo").replacing("#", with: "🎁 "),
                rows: [giftToggle(
                    "Privacy.Gifts.ShowGiftButton",
                    isOn: giftSettings.showGiftButton,
                ) { $0.showGiftButton = $1 }],
            ), at: 0)
        }
        if kind == .phoneNumber, let discovery {
            let everybody = discovery.base == .everybody
            sections.append(SettingsSection(
                header: L10n.telegram("PrivacyPhoneNumberSettings.DiscoveryHeader"),
                footer: everybody ? publicLink : L10n.telegram("PrivacyPhoneNumberSettings.CustomDisabledHelp"),
                rows: [
                    SettingsRow(
                        title: L10n.telegram("PrivacySettings.LastSeenEverybody"),
                        accessory: everybody ? .checkmark : .none,
                    ) { [weak self] in self?.selectDiscovery(everybody: true) },
                    SettingsRow(
                        title: L10n.telegram("PrivacySettings.LastSeenContacts"),
                        accessory: everybody ? .none : .checkmark,
                    ) { [weak self] in self?.selectDiscovery(everybody: false) },
                ],
            ))
        }
        var exceptionRows = [SettingsRow]()
        if state.showsNever {
            exceptionRows.append(SettingsRow(
                title: kind.neverTitle,
                detail: Self.countText(state.neverCount),
                accessory: .disclosure,
            ) { [weak self] in self?.openExceptions(always: false) })
        }
        if state.showsAlways {
            exceptionRows.append(SettingsRow(
                title: kind.alwaysTitle,
                detail: Self.countText(state.alwaysCount),
                accessory: .disclosure,
            ) { [weak self] in self?.openExceptions(always: true) })
        }
        sections.append(SettingsSection(
            header: L10n.telegram("GroupInfo.Permissions.Exceptions"),
            footer: exceptionsInfo,
            rows: exceptionRows,
        ))
        if let peerToPeer { sections += peerToPeerSections(peerToPeer) }
        if let giftSettings {
            let types = giftSettings.acceptedGiftTypes
            sections.append(SettingsSection(
                header: L10n.telegram("Privacy.Gifts.AcceptedTypes"),
                footer: L10n.telegram("Privacy.Gifts.AcceptedTypes.Info"),
                rows: [
                    giftToggle("Privacy.Gifts.AcceptedTypes.Unlimited", isOn: types.unlimitedGifts) {
                        $0.unlimitedGifts = $1
                    },
                    giftToggle("Privacy.Gifts.AcceptedTypes.Limited", isOn: types.limitedGifts) {
                        $0.limitedGifts = $1
                    },
                    giftToggle("Privacy.Gifts.AcceptedTypes.Unique", isOn: types.upgradedGifts) {
                        $0.upgradedGifts = $1
                    },
                    giftToggle("Privacy.Gifts.AcceptedTypes.Channel", isOn: types.giftsFromChannels) {
                        $0.giftsFromChannels = $1
                    },
                    giftToggle("Privacy.Gifts.AcceptedTypes.Premium", isOn: types.premiumSubscription) {
                        $0.premiumSubscription = $1
                    },
                ],
            ))
        }
        return sections
    }

    private static func countText(_ count: Int) -> String {
        if count == 0 {
            L10n.telegram("PrivacyLastSeenSettings.EmpryUsersPlaceholder")
        } else {
            L10n.telegramPlural("UserCount", count: count)
        }
    }

    /// A gift switch. Without Premium it stays as it is and displayLockedGiftsInfo's toast says why; with it the
    /// change saves with setGiftSettings.
    private func giftToggle(
        _ key: String,
        isOn: Bool,
        update: @escaping (inout GiftDraft, Bool) -> Void,
    ) -> SettingsRow {
        SettingsRow(title: L10n.telegram(key), accessory: .toggle(isOn: isOn, onChange: { [weak self] value in
            self?.changeGiftSetting(value, update: update)
        }))
    }

    private func changeGiftSetting(_ value: Bool, update: (inout GiftDraft, Bool) -> Void) {
        guard let giftSettings else { return }
        guard isPremium else {
            refreshRowsInPlace()
            TelegramUndoToast.show(
                text: L10n.telegram("Privacy.Gifts.PremiumToast.Text").withoutTelegramMarkup,
                in: view,
                bottomInset: 12,
                undo: nil,
            )
            return
        }
        var draft = GiftDraft(giftSettings)
        update(&draft, value)
        let settings = draft.settings
        // The switch shows the change while it saves; a failure puts it back under the alert.
        perform { [weak self] client in
            do {
                _ = try await client.send(TDNativeRequests.setGiftSettings(settings: settings))
            } catch {
                self?.refreshRowsInPlace()
                throw error
            }
        } completion: { [weak self] in
            self?.giftSettings = settings
            self?.reload()
        }
    }

    /// The account's own giftSettings and Premium, from its full info.
    private func loadGiftSettings() {
        let client = client
        Task { [weak self] in
            guard let me = try? await client.getMe(),
                  let info = try? await client.getUserFullInfo(userId: me.id),
                  let self, contextIsCurrent else { return }
            isPremium = me.isPremium
            giftSettings = info.giftSettings
            reload()
        }
    }

    /// The calls' Peer-to-Peer sections: Always, My Contacts or Never, then the exceptions that apply. iOS Call
    /// Integration is left out with calls.
    private func peerToPeerSections(_ state: PrivacyRuleState) -> [SettingsSection] {
        let options: [(PrivacyRuleState.Base, String)] = [
            (.everybody, L10n.telegram("Privacy.Calls.P2PAlways")),
            (.contacts, L10n.telegram("Privacy.Calls.P2PContacts")),
            (.nobody, L10n.telegram("Privacy.Calls.P2PNever")),
        ]
        var exceptionRows = [SettingsRow]()
        if state.showsNever {
            exceptionRows.append(SettingsRow(
                title: kind.neverTitle,
                detail: Self.countText(state.neverCount),
                accessory: .disclosure,
            ) { [weak self] in self?.openExceptions(always: false, peerToPeer: true) })
        }
        if state.showsAlways {
            exceptionRows.append(SettingsRow(
                title: kind.alwaysTitle,
                detail: Self.countText(state.alwaysCount),
                accessory: .disclosure,
            ) { [weak self] in self?.openExceptions(always: true, peerToPeer: true) })
        }
        return [
            SettingsSection(
                header: L10n.telegram("Privacy.Calls.P2P"),
                footer: L10n.telegram("Privacy.Calls.P2PHelp"),
                rows: options.map { base, title in
                    SettingsRow(title: title, accessory: state.base == base ? .checkmark : .none) { [weak self] in
                        self?.selectPeerToPeer(base)
                    }
                },
            ),
            SettingsSection(
                footer: L10n.telegram("PrivacyLastSeenSettings.CustomShareSettingsHelp"),
                rows: exceptionRows,
            ),
        ]
    }

    private func select(_ base: PrivacyRuleState.Base) {
        guard base != state.base else { return }
        var updated = state
        updated.base = base
        save(updated)
    }

    private func save(_ updated: PrivacyRuleState) {
        let setting = kind.setting
        let rules = updated.tdRules
        perform { client in
            _ = try await client.send(TDNativeRequests.setUserPrivacySettingRules(setting: setting, rules: rules))
        } completion: { [weak self] in
            guard let self else { return }
            state = updated
            onChange?(updated)
            reload()
        }
    }

    private func loadPeerToPeer() {
        let client = client
        Task { [weak self] in
            let rules = try? await client.send(TDNativeRequests.getUserPrivacySettingRules(
                setting: .userPrivacySettingAllowPeerToPeerCalls,
            ))
            guard let self, contextIsCurrent, let rules else { return }
            peerToPeer = PrivacyRuleState(rules: rules)
            reload()
        }
    }

    private func selectPeerToPeer(_ base: PrivacyRuleState.Base) {
        guard var updated = peerToPeer, base != updated.base else { return }
        updated.base = base
        savePeerToPeer(updated)
    }

    private func savePeerToPeer(_ updated: PrivacyRuleState) {
        let rules = updated.tdRules
        perform { client in
            _ = try await client.send(TDNativeRequests.setUserPrivacySettingRules(
                setting: .userPrivacySettingAllowPeerToPeerCalls,
                rules: rules,
            ))
        } completion: { [weak self] in
            self?.peerToPeer = updated
            self?.reload()
        }
    }

    private func loadDiscovery() {
        let client = client
        Task { [weak self] in
            let rules = try? await client.send(TDNativeRequests.getUserPrivacySettingRules(
                setting: .userPrivacySettingAllowFindingByPhoneNumber,
            ))
            guard let self, contextIsCurrent, let rules else { return }
            discovery = PrivacyRuleState(rules: rules)
            reload()
        }
    }

    /// Telegram offers Everybody or My Contacts for finding the account by its number.
    private func selectDiscovery(everybody: Bool) {
        guard let discovery, (discovery.base == .everybody) != everybody else { return }
        let rule: TDNativeUserPrivacySettingRule =
            everybody ? .userPrivacySettingRuleAllowAll : .userPrivacySettingRuleAllowContacts
        perform { client in
            _ = try await client.send(TDNativeRequests.setUserPrivacySettingRules(
                setting: .userPrivacySettingAllowFindingByPhoneNumber,
                rules: TDNativeUserPrivacySettingRules(rules: [rule]),
            ))
        } completion: { [weak self] in
            self?.discovery?.base = everybody ? .everybody : .contacts
            self?.reload()
        }
    }

    /// Telegram's SelectivePrivacySettingsPeersController. A person or group added to one list leaves the other.
    private func openExceptions(always: Bool, peerToPeer: Bool = false) {
        guard let state = peerToPeer ? self.peerToPeer : state else { return }
        let controller = PrivacyExceptionsViewController(
            title: always ? kind.alwaysTitle : kind.neverTitle,
            userIDs: always ? state.allowUserIDs : state.restrictUserIDs,
            chatIDs: always ? state.allowChatIDs : state.restrictChatIDs,
        )
        controller.onChange = { [weak self] userIDs, chatIDs in
            guard let self, let state = peerToPeer ? self.peerToPeer : self.state else { return }
            var updated = state
            if always {
                updated.allowUserIDs = userIDs
                updated.allowChatIDs = chatIDs
                updated.restrictUserIDs.removeAll(where: userIDs.contains)
                updated.restrictChatIDs.removeAll(where: chatIDs.contains)
            } else {
                updated.restrictUserIDs = userIDs
                updated.restrictChatIDs = chatIDs
                updated.allowUserIDs.removeAll(where: userIDs.contains)
                updated.allowChatIDs.removeAll(where: chatIDs.contains)
            }
            if peerToPeer { savePeerToPeer(updated) } else { save(updated) }
        }
        navigationController?.pushViewController(controller, animated: true)
    }
}
