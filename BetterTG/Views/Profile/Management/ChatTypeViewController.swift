// ChatTypeViewController.swift

import TDLibKit
import UIKit

// MARK: - ChatTypeViewController

/// Telegram's ChannelVisibilityController in its `.generic` mode for the owner: Public with an editable t.me link
/// checked while typing (checkChatUsername), or Private with the invite link; Manage Invite Links; who can send
/// messages in a group with a linked channel; Approve New Members (not for a public channel); and Restrict Saving
/// Content. Done applies the changes. A basic group becomes a supergroup first to take a public link, as Telegram
/// converts it, and the app returns to the chat list since the chat is replaced.
final class ChatTypeViewController: SettingsListViewController {
    private enum Status: Equatable {
        case idle
        case checking
        case available
        case invalid(String)
    }

    private static let checkDelay = Duration.milliseconds(300)

    private let target: ChatManagementTarget
    private let savedUsername: String
    private var isPublic: Bool
    private var username: String
    private var status = Status.idle
    private var inviteLink: String?
    private var joinToSend: Bool
    private var joinByRequest: Bool
    /// Whether a changed Approve New Members also applies to the existing invite links.
    private var appliesApprovalToInviteLinks = false
    /// The user's active invite links, which Telegram offers to update along with Approve New Members.
    private var activeInviteLinkCount = 0
    private var protectsContent: Bool
    private var isSaving = false
    private var checkTask: Task<Void, Never>?

    private var isGroup: Bool {
        !target.isChannel
    }

    /// A group linked to a channel chooses who may write (Group.Setup.WhoCanSendMessages).
    private var isDiscussion: Bool {
        isGroup && (target.supergroupInfo?.linkedChatId ?? 0) != 0
    }

    /// Approval is a supergroup setting, and a public channel has no one to approve.
    private var offersApproval: Bool {
        target.supergroupID != nil && !(target.isChannel && isPublic)
    }

    private var linkIsReady: Bool {
        switch status {
        case .available: true
        case .idle: !username.isEmpty && username == savedUsername
        case .checking, .invalid: false
        }
    }

    init(target: ChatManagementTarget) {
        self.target = target
        self.savedUsername = target.supergroup?.usernames?.editableUsername ?? ""
        self.isPublic = target.isPublic
        self.username = savedUsername
        self.inviteLink = target.inviteLink
        self.joinToSend = target.supergroup?.joinToSendMessages ?? false
        self.joinByRequest = target.supergroup?.joinByRequest ?? false
        self.protectsContent = target.chat.hasProtectedContent
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
        title = L10n.telegram(isGroup ? "GroupInfo.GroupType" : "Channel.TypeSetup.Title")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Done"), style: .prominent, target: self, action: #selector(donePressed),
        )
        updateDoneButton()
        loadInviteLinkCount()
    }

    override func makeSections() -> [SettingsSection] {
        let helpKey =
            switch (isGroup, isPublic) {
            case (true, true): "Group.Setup.TypePublicHelp"
            case (true, false): "Group.Setup.TypePrivateHelp"
            case (false, true): "Channel.Setup.TypePublicHelp"
            case (false, false): "Channel.Setup.TypePrivateHelp"
            }
        var sections = [SettingsSection(
            header: L10n.telegram(isGroup ? "Group.Setup.TypeHeader" : "Channel.Edit.LinkItem"),
            footer: L10n.telegram(helpKey),
            rows: [
                SettingsRow(
                    title: L10n.telegram(isGroup ? "Group.Setup.TypePublic" : "Channel.Setup.LinkTypePublic"),
                    accessory: isPublic ? .checkmark : .none,
                ) { [weak self] in self?.setPublic(true) },
                SettingsRow(
                    title: L10n.telegram(isGroup ? "Group.Setup.TypePrivate" : "Channel.Setup.LinkTypePrivate"),
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
                footer: L10n.telegram(
                    isGroup ? "Group.Username.CreatePublicLinkHelp" : "Channel.Username.CreatePublicLinkHelp",
                ),
                rows: statusRows(),
            ))
        } else if let inviteLink {
            sections.append(SettingsSection(
                header: L10n.telegram("InviteLink.InviteLink"),
                footer: L10n.telegram(
                    isGroup ? "Group.Username.CreatePrivateLinkHelp" : "Channel.Username.CreatePrivateLinkHelp",
                ),
                rows: [SettingsRow(
                    title: ChatInviteLinkText.address(inviteLink),
                    style: .action(destructive: false),
                    symbol: "link",
                ) { [weak self] in self?.presentLinkMenu(inviteLink) }],
            ))
        }
        sections.append(SettingsSection(
            footer: L10n.telegram("InviteLink.CreateInfo"),
            rows: [SettingsRow(
                title: L10n.telegram("InviteLink.Manage"),
                accessory: .disclosure,
            ) { [weak self] in self?.manageLinks() }],
        ))
        if isDiscussion {
            sections.append(SettingsSection(
                header: L10n.telegram("Group.Setup.WhoCanSendMessages.Title"),
                rows: [false, true].map { membersOnly in
                    SettingsRow(
                        title: L10n.telegram(membersOnly
                            ? "Group.Setup.WhoCanSendMessages.OnlyMembers"
                            : "Group.Setup.WhoCanSendMessages.Everyone"),
                        accessory: joinToSend == membersOnly ? .checkmark : .none,
                    ) { [weak self] in
                        self?.joinToSend = membersOnly
                        self?.reload()
                    }
                },
            ))
        }
        if offersApproval {
            sections.append(SettingsSection(
                footer: L10n.telegram(
                    isGroup ? "Group.Setup.ApproveNewMembersInfo" : "Channel.Setup.ApproveNewSubscribersInfo",
                ),
                rows: [SettingsRow(
                    title: L10n.telegram(isGroup
                        ? "Group.Setup.ApproveNewMembers"
                        : "Channel.Setup.ApproveNewSubscribers"),
                    accessory: .toggle(
                        isOn: joinByRequest,
                        onChange: { [weak self] isOn in self?.approvalChanged(isOn) },
                    ),
                    isEnabled: !isSaving,
                )],
            ))
        }
        let forwardingInfo =
            switch (isGroup, protectsContent) {
            case (true, false): "Group.Setup.ForwardingGroupInfo"
            case (true, true): "Group.Setup.ForwardingGroupInfoDisabled"
            case (false, false): "Group.Setup.ForwardingChannelInfo"
            case (false, true): "Group.Setup.ForwardingChannelInfoDisabled"
            }
        sections.append(SettingsSection(
            header: L10n.telegram(isGroup ? "Group.Setup.ForwardingGroupTitle" : "Group.Setup.ForwardingChannelTitle"),
            footer: L10n.telegram(forwardingInfo),
            rows: [SettingsRow(
                title: L10n.telegram("Group.Setup.ForwardingDisabled"),
                accessory: .toggle(isOn: protectsContent, onChange: { [weak self] isOn in
                    self?.protectsContent = isOn
                    self?.reload()
                }),
                isEnabled: !isSaving,
            )],
        ))
        return sections
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

    private func setPublic(_ value: Bool) {
        guard value != isPublic, !isSaving else { return }
        view.endEditing(true)
        isPublic = value
        reload()
        updateDoneButton()
    }

    private func usernameChanged(_ text: String) {
        username = text
        checkTask?.cancel()
        checkTask = nil
        if text.isEmpty || text == savedUsername {
            status = .idle
        } else if let error = ChannelLinkSetupViewController.formatError(text, isGroup: isGroup) {
            status = .invalid(error)
        } else {
            status = .checking
            scheduleCheck(text)
        }
        updateStatus()
    }

    private func scheduleCheck(_ text: String) {
        guard contextIsCurrent else { return }
        let client = client
        let chatID = target.chatID
        checkTask = Task { [weak self] in
            try? await Task.sleep(for: Self.checkDelay)
            guard !Task.isCancelled else { return }
            let result = try? await client.send(TDNativeRequests.checkChatUsername(chatId: chatID, username: text))
            guard let self, !Task.isCancelled, username == text else { return }
            status = ChannelLinkSetupViewController.availabilityError(result).map { .invalid($0) } ?? .available
            updateStatus()
        }
    }

    private func updateStatus() {
        if isPublic { reload(sections: IndexSet(integer: 2)) }
        updateDoneButton()
    }

    private func updateDoneButton() {
        navigationItem.rightBarButtonItem?.isEnabled = !isSaving && (!isPublic || linkIsReady)
    }

    // MARK: Invite link

    private func presentLinkMenu(_ link: String) {
        guard contextIsCurrent, let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 1)) else { return }
        presentTelegramContextMenu(sourceView: cell, actions: [
            TelegramContextMenuAction(
                title: L10n.telegram("InviteLink.ContextCopy"),
                image: UIImage(systemName: "doc.on.doc"),
            ) { [weak self] in
                guard let self else { return }
                ChatFolderInviteLinkActions.copy(link, in: self)
            },
            TelegramContextMenuAction(
                title: L10n.telegram("InviteLink.ContextShare"),
                image: UIImage(systemName: "square.and.arrow.up"),
            ) { [weak self, weak cell] in
                guard let self else { return }
                ChatFolderInviteLinkActions.share(link, from: self, sourceView: cell)
            },
            TelegramContextMenuAction(
                title: L10n.telegram("InviteLink.ContextRevoke"),
                image: UIImage(systemName: "trash"),
                isDestructive: true,
            ) { [weak self] in self?.revoke(link) },
        ], presentationStyle: .menuOnly)
    }

    /// Revoking the primary link replaces it with a new one.
    private func revoke(_ link: String) {
        ChatInviteLinkText.confirmRevoke(isChannel: target.isChannel, in: self) { [weak self] in
            guard let self else { return }
            let chatID = target.chatID
            perform(failureText: { ChatManagementRows.failureText($0) }) { [weak self] client in
                let links = try await client.send(TDNativeRequests.revokeChatInviteLink(
                    chatId: chatID,
                    inviteLink: link,
                ))
                self?.inviteLink = links.inviteLinks.first { $0.isPrimary && !$0.isRevoked }?.inviteLink
            } completion: { [weak self] in
                self?.showToast(L10n.telegram("InviteLink.InviteLinkRevoked"))
                self?.reload()
            }
        }
    }

    private func manageLinks() {
        guard contextIsCurrent, !isSaving else { return }
        navigationController?.pushViewController(ChatInviteLinksViewController(target: target), animated: true)
    }

    // MARK: Approval

    /// ChannelVisibilityController counts the user's active links (peerExportedInvitations) to offer them the change.
    private func loadInviteLinkCount() {
        guard target.supergroupID != nil, contextIsCurrent else { return }
        let client = client
        let chatID = target.chatID
        Task { [weak self] in
            guard let userID = try? await client.getMe().id,
                  let links = try? await client.send(TDNativeRequests.getChatInviteLinks(
                      chatId: chatID,
                      creatorUserId: userID,
                      isRevoked: false,
                      offsetDate: 0,
                      offsetInviteLink: "",
                      limit: 1,
                  ))
            else { return }
            self?.activeInviteLinkCount = Int(links.totalCount)
        }
    }

    /// Telegram's toggleApproveMembers: with active links it asks whether they follow the new setting.
    private func approvalChanged(_ isOn: Bool) {
        joinByRequest = isOn
        appliesApprovalToInviteLinks = false
        guard activeInviteLinkCount > 0 else { return }
        let links = L10n.telegramPlural(
            "Group.Setup.ApproveNewMembersApplyToExistingInviteLinksText.Links",
            count: activeInviteLinkCount,
            formattedCount: activeInviteLinkCount.formatted(.number),
        )
        let key =
            switch (isGroup, isOn) {
            case (true, true): "EnableGroup"
            case (true, false): "DisableGroup"
            case (false, true): "EnableChannel"
            case (false, false): "DisableChannel"
            }
        let alert = UIAlertController(
            title: L10n.telegram("Group.Setup.ApproveNewMembersApplyToExistingInviteLinksTitle"),
            message: L10n.telegram("Group.Setup.ApproveNewMembersApplyToExistingInviteLinksText.\(key)", links)
                .withoutTelegramMarkup,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.No"), style: .default))
        let yes = UIAlertAction(title: L10n.telegram("Common.Yes"), style: .default) { [weak self] _ in
            self?.appliesApprovalToInviteLinks = true
        }
        alert.addAction(yes)
        alert.preferredAction = yes
        chatListTopPresenter.present(alert, animated: true)
    }

    // MARK: Done

    /// ChannelVisibilityController's Done: Telegram warns once before a private chat gets a public link.
    @objc private func donePressed() {
        guard !isSaving, contextIsCurrent else { return }
        view.endEditing(true)
        let newUsername: String? =
            if isPublic {
                username != savedUsername || !target.isPublic ? username : nil
            } else {
                target.isPublic ? "" : nil
            }
        guard let newUsername, !newUsername.isEmpty, !target.isPublic else {
            apply(username: newUsername)
            return
        }
        confirm(
            message: L10n
                .telegram(isGroup ? "Group.Edit.PrivatePublicLinkAlert" : "Channel.Edit.PrivatePublicLinkAlert"),
            actionTitle: L10n.telegram("Common.OK"),
            isDestructive: false,
        ) { [weak self] in self?.apply(username: newUsername) }
    }

    private func apply(username newUsername: String?) {
        guard !isSaving, contextIsCurrent else { return }
        setSaving(true)
        let client = client
        let chatID = target.chatID
        let supergroup = target.supergroup
        let protects = protectsContent != target.chat.hasProtectedContent ? protectsContent : nil
        let membersOnly = isDiscussion && joinToSend != supergroup?.joinToSendMessages ? joinToSend : nil
        let approval = offersApproval && joinByRequest != supergroup?.joinByRequest ? joinByRequest : nil
        let appliesToInviteLinks = appliesApprovalToInviteLinks
        let hasOtherUsernames = (supergroup?.usernames?.activeUsernames ?? []).contains { $0 != savedUsername }
        let savedUsername = savedUsername
        Task { [weak self] in
            do {
                if let protects {
                    _ = try await client.send(TDNativeRequests.toggleChatHasProtectedContent(
                        chatId: chatID, hasProtectedContent: protects,
                    ))
                }
                var supergroupID = supergroup?.id
                var upgraded = false
                if supergroupID == nil, let newUsername, !newUsername.isEmpty {
                    let chat = try await client.send(TDNativeRequests.upgradeBasicGroupChatToSupergroupChat(
                        chatId: chatID,
                    ))
                    if case .chatTypeSupergroup(let value) = chat.type { supergroupID = value.supergroupId }
                    upgraded = true
                }
                if let supergroupID {
                    if let membersOnly {
                        _ = try await client.send(TDNativeRequests.toggleSupergroupJoinToSendMessages(
                            supergroupId: supergroupID, joinToSendMessages: membersOnly,
                        ))
                    }
                    if let approval {
                        _ = try await client.send(TDNativeRequests.toggleSupergroupJoinByRequest(
                            supergroupId: supergroupID,
                            joinByRequest: approval,
                            guardBotUserId: 0,
                            applyToInviteLinks: appliesToInviteLinks,
                        ))
                    }
                    if let newUsername {
                        if newUsername != savedUsername {
                            _ = try await client.send(TDNativeRequests.setSupergroupUsername(
                                supergroupId: supergroupID, username: newUsername,
                            ))
                        }
                        // Going private also turns off the chat's other public links (deactivateAllAddressNames).
                        if newUsername.isEmpty, hasOtherUsernames {
                            _ = try await client.send(TDNativeRequests.disableAllSupergroupUsernames(
                                supergroupId: supergroupID,
                            ))
                        }
                    }
                }
                guard let self, contextIsCurrent else { return }
                if upgraded {
                    NavigationStorage.shared.popToRoot()
                } else {
                    navigationController?.popViewController(animated: true)
                }
            } catch {
                guard let self else { return }
                setSaving(false)
                guard contextIsCurrent else { return }
                if ((error as? TDLibError)?.message ?? "").contains("USERNAME_OCCUPIED") {
                    status = .invalid(L10n.telegram("Channel.Username.InvalidTaken"))
                    updateStatus()
                }
                presentAlert(title: nil, message: ChatManagementRows.failureText(error))
            }
        }
    }

    private func setSaving(_ value: Bool) {
        isSaving = value
        tableView.isUserInteractionEnabled = !value
        updateDoneButton()
    }
}
