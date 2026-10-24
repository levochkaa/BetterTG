// ChannelLinkSetupViewController.swift

import TDLibKit
import UIKit

// MARK: - ChannelLinkSetupViewController

/// Telegram's channelVisibilityController in `.initialSetup`, right after a channel is created: Public with a t.me
/// link checked while typing (checkChatUsername), or Private with the channel's invite link to copy. Next (on its tap
/// only) saves a public link (setSupergroupUsername) after Telegram's warning, then goes on to adding subscribers.
final class ChannelLinkSetupViewController: SettingsListViewController, ComposeFlowScreen {
    private enum Status: Equatable {
        case idle
        case checking
        case available
        case invalid(String)
    }

    private static let checkDelay = Duration.milliseconds(300)

    private let chatID: Int64
    private let supergroupID: Int64
    private var isPublic = false
    private var username = ""
    private var status = Status.idle
    private var inviteLink: String?
    private var isLoadingLink = true
    private var isSaving = false
    private var checkTask: Task<Void, Never>?

    init(chatID: Int64, supergroupID: Int64) {
        self.chatID = chatID
        self.supergroupID = supergroupID
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        checkTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Channel.TypeSetup.Title")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Next"), style: .prominent, target: self, action: #selector(nextPressed),
        )
        updateNextButton()
        loadInviteLink()
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [SettingsSection(
            header: L10n.telegram("Channel.Edit.LinkItem"),
            footer: L10n.telegram(isPublic ? "Channel.Setup.TypePublicHelp" : "Channel.Setup.TypePrivateHelp"),
            rows: [
                SettingsRow(
                    title: L10n.telegram("Channel.Setup.LinkTypePublic"),
                    accessory: isPublic ? .checkmark : .none,
                ) { [weak self] in self?.setPublic(true) },
                SettingsRow(
                    title: L10n.telegram("Channel.Setup.LinkTypePrivate"),
                    accessory: isPublic ? .none : .checkmark,
                ) { [weak self] in self?.setPublic(false) },
            ],
        )]
        if isPublic {
            sections.append(SettingsSection(rows: [SettingsRow(title: "", style: .input(SettingsTextInput(
                text: username,
                placeholder: L10n.telegram("Group.PublicLink.Placeholder"),
                prefix: "t.me/",
                autocapitalization: .none,
                autocorrection: false,
            ) { [weak self] text in self?.usernameChanged(text) }))]))
            sections.append(SettingsSection(
                footer: L10n.telegram("Channel.Username.CreatePublicLinkHelp"),
                rows: statusRows(),
            ))
        } else {
            let linkRow =
                if let inviteLink {
                    SettingsRow(title: inviteLink, style: .action(destructive: false)) { [weak self] in
                        self?.copyInviteLink()
                    }
                } else {
                    SettingsRow(
                        title: L10n.telegram("Channel.NotificationLoading"),
                        style: .status(.secondaryLabel),
                        accessory: isLoadingLink ? .activity : .none,
                    )
                }
            sections.append(SettingsSection(
                header: L10n.telegram("InviteLink.InviteLink"),
                footer: L10n.telegram("Channel.Username.CreatePrivateLinkHelp"),
                rows: [linkRow],
            ))
        }
        return sections
    }

    /// Telegram's checkAddressNameFormat, with the group or channel wording.
    static func formatError(_ value: String, isGroup: Bool = false) -> String? {
        let prefix = isGroup ? "Group.Username." : "Channel.Username."
        let characters = Array(value)
        for (index, character) in characters.enumerated() {
            if character == "_" {
                if index == 0 { return L10n.telegram(prefix + "InvalidStartsWithUnderscore") }
                if index == characters.count - 1 {
                    return characters.count < 4
                        ? L10n.telegram(prefix + "InvalidTooShort")
                        : L10n.telegram(prefix + "InvalidEndsWithUnderscore")
                }
            }
            if index == 0, character.isASCII, character.isNumber {
                return L10n.telegram(prefix + "InvalidStartsWithNumber")
            }
            let isAllowed = character == "_" || (character.isASCII && (character.isLetter || character.isNumber))
            if !isAllowed { return L10n.telegram("Channel.Username.InvalidCharacters") }
        }
        return characters.count < 4 ? L10n.telegram(prefix + "InvalidTooShort") : nil
    }

    /// checkChatUsername's answer as Telegram words it; nil when the link is free.
    static func availabilityError(_ result: TDNativeCheckChatUsernameResult?) -> String? {
        switch result {
        case .checkChatUsernameResultOk:
            nil
        case .checkChatUsernameResultUsernameOccupied,
             .checkChatUsernameResultUsernamePurchasable:
            L10n.telegram("Channel.Username.InvalidTaken")
        case .checkChatUsernameResultPublicChatsTooMany:
            L10n.telegram("Username.TooManyPublicUsernamesError")
        case .checkChatUsernameResultPublicGroupsUnavailable,
             .checkChatUsernameResultUsernameInvalid,
             nil:
            L10n.telegram("Channel.Username.InvalidCharacters")
        }
    }

    private func statusRows() -> [SettingsRow] {
        switch status {
        case .idle:
            []
        case .checking:
            [SettingsRow(
                title: L10n.telegram("Channel.Username.CheckingUsername"),
                style: .status(.secondaryLabel),
                accessory: .activity,
            )]
        case .available:
            [SettingsRow(
                title: L10n.telegram("Channel.Username.UsernameIsAvailable", username),
                style: .status(.systemGreen),
            )]
        case .invalid(let text):
            [SettingsRow(title: text, style: .status(.systemRed))]
        }
    }

    /// The private link Telegram shows under Invite Link: the channel's primary invite link.
    private func loadInviteLink() {
        let client = client
        let supergroupID = supergroupID
        Task { [weak self] in
            let info = try? await client.getSupergroupFullInfo(supergroupId: supergroupID)
            guard let self, contextIsCurrent else { return }
            inviteLink = info?.inviteLink?.inviteLink
            isLoadingLink = false
            if !isPublic { reload() }
        }
    }

    private func setPublic(_ value: Bool) {
        guard value != isPublic, !isSaving else { return }
        view.endEditing(true)
        isPublic = value
        reload()
        updateNextButton()
    }

    private func usernameChanged(_ text: String) {
        username = text
        checkTask?.cancel()
        checkTask = nil
        if text.isEmpty {
            status = .idle
        } else if let formatError = Self.formatError(text) {
            status = .invalid(formatError)
        } else {
            status = .checking
            scheduleCheck(text)
        }
        updateStatus()
    }

    private func scheduleCheck(_ text: String) {
        guard contextIsCurrent else { return }
        let client = client
        let chatID = chatID
        checkTask = Task { [weak self] in
            try? await Task.sleep(for: Self.checkDelay)
            guard !Task.isCancelled else { return }
            let result = try? await client.send(TDNativeRequests.checkChatUsername(chatId: chatID, username: text))
            guard let self, !Task.isCancelled, username == text else { return }
            status = Self.availabilityError(result).map { .invalid($0) } ?? .available
            updateStatus()
        }
    }

    private func updateStatus() {
        if isPublic { reload(sections: IndexSet(integer: 2)) }
        updateNextButton()
    }

    private func updateNextButton() {
        navigationItem.rightBarButtonItem?.isEnabled = !isSaving && (!isPublic || status == .available)
    }

    private func copyInviteLink() {
        guard let inviteLink else { return }
        UIPasteboard.general.string = inviteLink
        showToast(L10n.telegram("InviteLink.InviteLinkCopiedText"))
    }

    /// ChannelVisibilityController's Next: a public link after Telegram's warning, then the subscribers.
    @objc private func nextPressed() {
        guard !isSaving, contextIsCurrent else { return }
        view.endEditing(true)
        guard isPublic else {
            addSubscribers()
            return
        }
        guard status == .available else { return }
        let alert = UIAlertController(
            title: nil,
            message: L10n.telegram("Channel.Edit.PrivatePublicLinkAlert"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default) { [weak self] _ in
            self?.saveUsername()
        })
        present(alert, animated: true)
    }

    private func saveUsername() {
        guard !isSaving, contextIsCurrent else { return }
        isSaving = true
        updateNextButton()
        let client = client
        let supergroupID = supergroupID
        let value = username
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.setSupergroupUsername(
                    supergroupId: supergroupID, username: value,
                ))
                guard let self, contextIsCurrent else { return }
                isSaving = false
                addSubscribers()
            } catch {
                guard let self else { return }
                isSaving = false
                if ((error as? TDLibError)?.message ?? "").contains("OCCUPIED") {
                    status = .invalid(L10n.telegram("Channel.Username.InvalidTaken"))
                }
                updateStatus()
                if contextIsCurrent { presentAlert(title: nil, message: L10n.telegram("Login.UnknownError")) }
            }
        }
    }

    /// The next step of the initial setup: ContactMultiselectionController in `.channelCreation`.
    private func addSubscribers() {
        guard contextIsCurrent, navigationController?.topViewController === self else { return }
        NavigationStorage.shared.replaceComposeFlow(
            with: ComposeContactPickerViewController(mode: .channelSubscribers(chatID: chatID)),
        )
    }
}
