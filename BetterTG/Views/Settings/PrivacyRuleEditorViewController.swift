// PrivacyRuleEditorViewController.swift

import TDLibKit
import UIKit

// MARK: - PrivacyRuleEditorViewController

/// Telegram's SelectivePrivacySettingsController for one rule: Everybody, My Contacts or Nobody, the rule's help, the
/// exceptions that apply to the chosen option, for the phone number who can find the account by it, and for calls
/// who they go peer-to-peer with. Each choice saves at once with setUserPrivacySettingRules.
final class PrivacyRuleEditorViewController: SettingsListViewController {
    var onChange: ((PrivacyRuleState) -> Void)?

    private let kind: PrivacyKind
    private let phoneNumber: String
    private var state: PrivacyRuleState
    /// Who can find the account by its number (userPrivacySettingAllowFindingByPhoneNumber).
    private var discovery: PrivacyRuleState?
    /// Who calls go peer-to-peer with (userPrivacySettingAllowPeerToPeerCalls).
    private var peerToPeer: PrivacyRuleState?

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
        var sections = [SettingsSection(
            header: kind.header,
            footer: info,
            rows: options.map { base, title in
                SettingsRow(title: title, accessory: state.base == base ? .checkmark : .none) { [weak self] in
                    self?.select(base)
                }
            },
        )]
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
        return sections
    }

    private static func countText(_ count: Int) -> String {
        if count == 0 {
            L10n.telegram("PrivacyLastSeenSettings.EmpryUsersPlaceholder")
        } else {
            L10n.telegramPlural("UserCount", count: count)
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
