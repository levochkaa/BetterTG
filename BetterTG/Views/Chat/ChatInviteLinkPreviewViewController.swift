// ChatInviteLinkPreviewViewController.swift

import TDLibKit
import UIKit

// MARK: - ChatInviteLinkPreviewViewController

/// Telegram's JoinLinkPreviewController for a `t.me/+hash` or `joinchat` link the user can't open yet: the chat's
/// photo, title, member count, a few members and its description, with Join or Request to Join. Nothing is joined
/// until the user taps the button. Requests run on the client that checked the link and stop once it isn't current.
final class ChatInviteLinkPreviewViewController: UIViewController {
    /// Called after the dismissal with the joined chat, as Telegram's navigateToPeer.
    var onJoined: ((Int64) -> Void)?

    // MARK: Private

    private let inviteLink: String
    private let info: TDNativeChatInviteLinkInfo
    private let authority = ChatListActionAuthority()
    private let dimmer = UIControl()
    private let sheetStack = UIStackView()
    private let contentStack = UIStackView()
    private let avatarView = ProfileAvatarView()
    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let membersScroll = UIScrollView()
    private let membersStack = UIStackView()
    private let aboutLabel = UILabel()
    private let requestLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let joinButton = TelegramSheetActionButton()
    private let cancelButton = TelegramSheetActionButton()
    private var contentHeight: NSLayoutConstraint!
    private var sheetWidth: NSLayoutConstraint!
    private var didAnimateIn = false
    private var isJoining = false

    private var isChannel: Bool {
        if case .inviteLinkChatTypeChannel = info.type { return true }
        return false
    }

    init(inviteLink: String, info: TDNativeChatInviteLinkInfo) {
        self.inviteLink = inviteLink
        self.info = info
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        dimmer.translatesAutoresizingMaskIntoConstraints = false
        dimmer.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        view.addSubview(dimmer)
        sheetStack.translatesAutoresizingMaskIntoConstraints = false
        sheetStack.axis = .vertical
        sheetStack.spacing = 8
        view.addSubview(sheetStack)
        sheetWidth = sheetStack.widthAnchor.constraint(equalToConstant: 382)
        NSLayoutConstraint.activate([
            dimmer.topAnchor.constraint(equalTo: view.topAnchor),
            dimmer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sheetStack.centerXAnchor.constraint(equalTo: view.centerXAnchor), sheetWidth,
            sheetStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
        ])

        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 16
        card.clipsToBounds = true
        sheetStack.addArrangedSubview(card)
        sheetStack.addArrangedSubview(cancelButton)
        cancelButton.layer.cornerRadius = 16
        cancelButton.clipsToBounds = true
        cancelButton.setTitle(L10n.telegram("Common.Cancel"), for: .normal)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        joinButton.setTitle(joinTitle(), for: .normal)
        joinButton.accessibilityIdentifier = "chat-invite-join"
        joinButton.addTarget(self, action: #selector(join), for: .touchUpInside)
        for button in [joinButton, cancelButton] {
            button.heightAnchor.constraint(equalToConstant: 57).isActive = true
        }

        configureContent()
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = false
        card.addSubview(scroll)
        scroll.addSubview(contentStack)
        joinButton.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(joinButton)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        joinButton.addSubview(spinner)
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(separator)
        contentHeight = scroll.heightAnchor.constraint(equalToConstant: 280)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: card.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor), contentHeight,
            contentStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            contentStack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -18),
            contentStack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
            joinButton.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            joinButton.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            joinButton.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            joinButton.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            spinner.centerYAnchor.constraint(equalTo: joinButton.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: joinButton.trailingAnchor, constant: -20),
            separator.topAnchor.constraint(equalTo: joinButton.topAnchor),
            separator.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),
        ])
        loadMembers()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = min(view.bounds.width, view.bounds.height) - 20
        if abs(sheetWidth.constant - width) > 0.5 { sheetWidth.constant = width }
        let fitting = contentStack.systemLayoutSizeFitting(
            CGSize(width: max(1, width - 32), height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        )
        let available = max(120, view.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom - 142)
        let height = min(available, ceil(fitting.height + 42))
        if abs(contentHeight.constant - height) > 0.5 { contentHeight.constant = height }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAnimateIn else { return }
        didAnimateIn = true
        sheetStack.transform = CGAffineTransform(translationX: 0, y: sheetStack.bounds.height + 40)
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction],
        ) { self.sheetStack.transform = .identity }
    }

    // MARK: Content

    /// JoinLinkPreviewPeerContentNode: the photo, title and count, then the known members for a plain invite, or
    /// Telegram's approval note for a link that creates a join request.
    private func configureContent() {
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 4

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.showsContextMenu = false
        avatarView.isAccessibilityElement = false
        let title = info.title.trimmingCharacters(in: .whitespacesAndNewlines)
        avatarView.configure(
            file: info.photo?.small,
            largeFile: info.photo?.big,
            minithumbnail: info.photo?.minithumbnail,
            placeholder: TelegramAvatarPlaceholder(
                peerID: info.chatId,
                accentColorID: info.accentColorId,
                upgradedGiftColors: nil,
                letters: title.telegramAvatarFirstLetter.map { [$0] } ?? [],
                isDeleted: false,
            ),
            accountUserID: 0,
            client: authority.client,
        )
        let avatarContainer = UIView()
        avatarContainer.addSubview(avatarView)
        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: avatarContainer.topAnchor),
            avatarView.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor),
            avatarView.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 100),
            avatarView.heightAnchor.constraint(equalToConstant: 100),
        ])
        contentStack.addArrangedSubview(avatarContainer)
        contentStack.setCustomSpacing(15, after: avatarContainer)

        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header
        contentStack.addArrangedSubview(titleLabel)

        let hasMembers = !info.createsJoinRequest && !info.memberUserIds.isEmpty
        countLabel.text =
            if isChannel {
                L10n.telegramPlural("Conversation.StatusSubscribers", count: info.memberCount)
            } else if hasMembers {
                L10n.telegramPlural("Invitation.Members", count: info.memberCount)
            } else {
                L10n.telegramPlural("Conversation.StatusMembers", count: info.memberCount)
            }
        countLabel.font = .systemFont(ofSize: 15)
        countLabel.textColor = .secondaryLabel
        countLabel.textAlignment = .center
        countLabel.numberOfLines = 0
        contentStack.addArrangedSubview(countLabel)

        membersScroll.showsHorizontalScrollIndicator = false
        membersScroll.alwaysBounceHorizontal = false
        membersScroll.isHidden = true
        membersStack.translatesAutoresizingMaskIntoConstraints = false
        membersStack.axis = .horizontal
        membersStack.alignment = .top
        // Telegram's peersScrollNode centres the members when they fit and scrolls them when they don't.
        let membersContent = UIView()
        membersContent.translatesAutoresizingMaskIntoConstraints = false
        membersScroll.addSubview(membersContent)
        membersContent.addSubview(membersStack)
        let fitsWidth = membersContent.widthAnchor.constraint(equalTo: membersScroll.frameLayoutGuide.widthAnchor)
        fitsWidth.priority = .defaultLow
        NSLayoutConstraint.activate([
            membersScroll.heightAnchor.constraint(equalToConstant: 95),
            membersContent.topAnchor.constraint(equalTo: membersScroll.contentLayoutGuide.topAnchor),
            membersContent.bottomAnchor.constraint(equalTo: membersScroll.contentLayoutGuide.bottomAnchor),
            membersContent.leadingAnchor.constraint(equalTo: membersScroll.contentLayoutGuide.leadingAnchor),
            membersContent.trailingAnchor.constraint(equalTo: membersScroll.contentLayoutGuide.trailingAnchor),
            membersContent.heightAnchor.constraint(equalTo: membersScroll.frameLayoutGuide.heightAnchor),
            membersContent.widthAnchor.constraint(greaterThanOrEqualTo: membersScroll.frameLayoutGuide.widthAnchor),
            fitsWidth,
            membersStack.topAnchor.constraint(equalTo: membersContent.topAnchor),
            membersStack.bottomAnchor.constraint(equalTo: membersContent.bottomAnchor),
            membersStack.centerXAnchor.constraint(equalTo: membersContent.centerXAnchor),
            membersStack.leadingAnchor.constraint(greaterThanOrEqualTo: membersContent.leadingAnchor),
        ])
        contentStack.addArrangedSubview(membersScroll)
        contentStack.setCustomSpacing(12, after: countLabel)

        let about = info.description.trimmingCharacters(in: .whitespacesAndNewlines)
        aboutLabel.text = about
        aboutLabel.font = .systemFont(ofSize: 17)
        aboutLabel.textAlignment = .center
        aboutLabel.numberOfLines = 0
        aboutLabel.isHidden = about.isEmpty
        contentStack.addArrangedSubview(aboutLabel)
        contentStack.setCustomSpacing(12, after: membersScroll)

        requestLabel.text = L10n.telegram(isChannel
            ? "MemberRequests.RequestToJoinDescriptionChannel"
            : "MemberRequests.RequestToJoinDescriptionGroup")
        requestLabel.font = .systemFont(ofSize: 15)
        requestLabel.textColor = .secondaryLabel
        requestLabel.textAlignment = .center
        requestLabel.numberOfLines = 0
        requestLabel.isHidden = !info.createsJoinRequest
        contentStack.addArrangedSubview(requestLabel)
        contentStack.setCustomSpacing(12, after: aboutLabel)
    }

    private func joinTitle() -> String {
        if info.createsJoinRequest {
            return L10n.telegram(isChannel
                ? "MemberRequests.RequestToJoinChannel"
                : "MemberRequests.RequestToJoinGroup")
        }
        return L10n.telegram(isChannel ? "Channel.JoinChannel" : "Invitation.JoinGroup")
    }

    /// The members TDLib knows for this link, without the user, and Telegram's "+N" for the rest.
    private func loadMembers() {
        guard !info.createsJoinRequest, !info.memberUserIds.isEmpty else { return }
        let client = authority.client
        let accountID = authority.source?.accountID
        let ownUserID = TDLib.shared.activeAccount?.userID
        let ids = info.memberUserIds.filter { $0 != ownUserID }
        let memberCount = info.memberCount
        Task { [weak self] in
            var users = [User]()
            for id in ids {
                guard !Task.isCancelled else { return }
                if let user = try? await client.getUser(userId: id) { users.append(user) }
            }
            guard let self, authority.isCurrent, !users.isEmpty else { return }
            for user in users {
                membersStack.addArrangedSubview(memberView(user, client: client, accountID: accountID))
            }
            let remaining = memberCount - users.count
            if remaining > 0 { membersStack.addArrangedSubview(moreView(remaining)) }
            membersScroll.isHidden = false
            view.setNeedsLayout()
        }
    }

    private func memberView(_ user: User, client: TDLibClient, accountID: UUID?) -> UIView {
        let avatar = ProfileAvatarView()
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.showsContextMenu = false
        avatar.configure(
            file: user.profilePhoto?.small,
            minithumbnail: user.profilePhoto?.minithumbnail,
            placeholder: user.telegramAvatarPlaceholder,
            accountID: accountID,
            accountUserID: 0,
            client: client,
        )
        let name = user.firstName.isEmpty ? user.lastName : user.firstName
        return peerItem(avatar, name: name.isEmpty ? L10n.telegram("User.DeletedAccount") : name)
    }

    private func moreView(_ count: Int) -> UIView {
        let circle = UILabel()
        circle.translatesAutoresizingMaskIntoConstraints = false
        circle.text = "+\(count)"
        circle.font = .systemFont(ofSize: 16, weight: .medium)
        circle.textColor = .white
        circle.textAlignment = .center
        circle.adjustsFontSizeToFitWidth = true
        circle.minimumScaleFactor = 0.6
        circle.backgroundColor = .systemGray
        circle.layer.cornerRadius = 30
        circle.clipsToBounds = true
        return peerItem(circle, name: nil)
    }

    /// SelectablePeerNode's 85 × 95 cell: a 60 pt avatar over the compact name.
    private func peerItem(_ avatar: UIView, name: String?) -> UIView {
        let item = UIView()
        item.translatesAutoresizingMaskIntoConstraints = false
        item.addSubview(avatar)
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = name
        label.font = .systemFont(ofSize: 11)
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        item.addSubview(label)
        item.isAccessibilityElement = name != nil
        item.accessibilityLabel = name
        NSLayoutConstraint.activate([
            item.widthAnchor.constraint(equalToConstant: 85),
            item.heightAnchor.constraint(equalToConstant: 95),
            avatar.topAnchor.constraint(equalTo: item.topAnchor, constant: 4),
            avatar.centerXAnchor.constraint(equalTo: item.centerXAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 60),
            avatar.heightAnchor.constraint(equalToConstant: 60),
            label.topAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 6),
            label.leadingAnchor.constraint(equalTo: item.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: item.trailingAnchor, constant: -4),
        ])
        return item
    }

    @objc private func cancel() {
        guard !isJoining else { return }
        dismiss(animated: true)
    }

    /// JoinLinkPreviewController.join: `joinChatByInviteLink`, then the chat, or Telegram's "request sent" toast.
    @objc private func join() {
        guard !isJoining else { return }
        let scope = authority.scope(owner: self)
        let client = authority.client
        let link = inviteLink
        setJoining(true)
        Task { [weak self] in
            do {
                let result = try await scope.perform {
                    try await client.send(TDNativeRequests.joinChatByInviteLink(inviteLink: link))
                }
                guard let self else { return }
                switch result {
                case .chatJoinResultSuccess(let success):
                    let onJoined = onJoined
                    dismiss(animated: true) { onJoined?(success.chatId) }
                case .chatJoinResultRequestSent:
                    finishWithRequestSent()
                case .chatJoinResultDeclined, .chatJoinResultGuardBotApprovalRequired:
                    // Telegram continues a guard bot's approval in a web app BetterTG doesn't have.
                    dismiss(animated: true)
                }
            } catch {
                guard let self, scope.isCurrent else { return }
                handleJoinError(error)
            }
        }
    }

    private func setJoining(_ joining: Bool) {
        isJoining = joining
        joinButton.isEnabled = !joining
        cancelButton.isEnabled = !joining
        if joining { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    private func finishWithRequestSent() {
        let text = L10n.telegram("MemberRequests.RequestToJoinSent") + "\n" + L10n.telegram(isChannel
            ? "MemberRequests.RequestToJoinSentDescriptionChannel"
            : "MemberRequests.RequestToJoinSentDescriptionGroup")
        let host = presentingViewController?.view
        dismiss(animated: true) {
            if let host { TelegramUndoToast.show(text: text, in: host, bottomInset: 8, undo: nil) }
        }
    }

    /// The errors JoinLinkPreviewController reports; anything else closes the sheet, as Telegram's `.generic`.
    private func handleJoinError(_ error: Swift.Error) {
        let message = (error as? TDLibError)?.message ?? ""
        let text: String? =
            if message.contains("CHANNELS_TOO_MUCH") {
                L10n.telegram("Join.ChannelsTooMuch")
            } else if message.contains("USERS_TOO_MUCH") {
                L10n.telegram("Conversation.UsersTooMuchError")
            } else if message.contains("FLOOD") || (error as? TDLibError)?.code == 429 {
                L10n.telegram("TwoStepAuth.FloodError")
            } else {
                nil
            }
        if message.contains("INVITE_REQUEST_SENT") {
            finishWithRequestSent()
            return
        }
        guard let text else {
            dismiss(animated: true)
            return
        }
        let presenter = presentingViewController
        dismiss(animated: true) {
            let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
            presenter?.chatListTopPresenter.present(alert, animated: true)
        }
    }
}
