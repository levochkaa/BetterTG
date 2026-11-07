// SendInviteLinkViewController.swift

import TDLibKit
import UIKit

// MARK: - SendInviteLinkViewController

/// Telegram's SendInviteLinkScreen for a chat: the people TDLib could not add (failedToAddMembers) because their
/// privacy settings refuse invitations. With the chat's invite link the sheet offers to send it to the checked ones as
/// a message (Skip until one is checked, then Send Invite Link with their count); without one it says the admins keep
/// the link from you and only closes. A person who takes messages from Premium users only can't be checked. Telegram's
/// Premium section above the list is left out with the rest of Premium.
@MainActor final class SendInviteLinkViewController: UIViewController {
    struct Person {
        let peer: SettingsPeer
        let status: (text: String, isOnline: Bool)
        let requiresPremium: Bool
    }

    private static let avatarSize: CGFloat = 64
    /// AnimatedAvatarSetNode's customSpacing: each avatar overlaps the one before it by 30 points.
    private static let avatarOverlap: CGFloat = 30
    private static let rowHeight: CGFloat = 60

    private let people: [Person]
    private let link: String?
    private let accountID: UUID?
    private let client: TDLibClient
    /// `-ui-probe-send-invite-link`: nothing is sent.
    private let isProbe: Bool
    private weak var toastHost: UIView?
    private var selected = Set<Int64>()
    private var checks = [Int64: UIImageView]()
    private var isSending = false

    private let scrollView = UIScrollView()
    private let content = UIStackView()
    private let closeButton = UIButton(configuration: .glass())
    private let actionButton = UIButton(configuration: .prominentGlass())
    private var fittingHeight: CGFloat = 540

    /// SendInviteLinkContentComponent's text: the link offered, or the admins keeping it.
    private var descriptionText: String {
        let single = people.count == 1 ? people[0].peer.title : nil
        if link != nil {
            if let single { return L10n.telegram("SendInviteLink.TextAvailableSingleUser", single) }
            return L10n.telegramPlural("SendInviteLink.TextAvailableMultipleUsers", count: people.count)
        }
        if let single { return L10n.telegram("SendInviteLink.TextUnavailableSingleUser", single) }
        return L10n.telegramPlural("SendInviteLink.TextUnavailableMultipleUsers", count: people.count)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private init(
        people: [Person],
        link: String?,
        accountID: UUID?,
        client: TDLibClient,
        toastHost: UIView?,
        isProbe: Bool,
    ) {
        self.people = people
        self.link = link
        self.accountID = accountID
        self.client = client
        self.toastHost = toastHost
        self.isProbe = isProbe
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    // MARK: Layout

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        if let sheet = sheetPresentationController {
            sheet.detents = [.custom(identifier: .init("fitting")) { [weak self] context in
                min(self?.fittingHeight ?? 540, context.maximumDetentValue)
            }]
            sheet.prefersGrabberVisible = false
        }

        scrollView.alwaysBounceVertical = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        content.axis = .vertical
        content.alignment = .fill
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        let avatars = makeAvatars()
        let titleLabel = UILabel()
        titleLabel.text = L10n.telegram(link == nil
            ? "SendInviteLink.LinkUnavailableTitle"
            : "SendInviteLink.InviteTitle")
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header
        let textLabel = UILabel()
        textLabel.numberOfLines = 0
        textLabel.textAlignment = .center
        textLabel.attributedText = Self.markdown(descriptionText, font: .systemFont(ofSize: 15))
        let textContainer = UIView()
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textContainer.addSubview(textLabel)
        NSLayoutConstraint.activate([
            textLabel.topAnchor.constraint(equalTo: textContainer.topAnchor),
            textLabel.bottomAnchor.constraint(equalTo: textContainer.bottomAnchor),
            textLabel.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor, constant: 16),
            textLabel.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor, constant: -16),
        ])

        for view in [avatars, titleLabel, textContainer, makeList()] {
            content.addArrangedSubview(view)
        }
        content.setCustomSpacing(120 - 48 - Self.avatarSize, after: avatars)
        content.setCustomSpacing(8, after: titleLabel)
        content.setCustomSpacing(22, after: textContainer)

        closeButton.configuration?.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
        )
        closeButton.configuration?.baseForegroundColor = .label
        closeButton.configuration?.cornerStyle = .capsule
        closeButton.accessibilityLabel = L10n.telegram("Common.Close")
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        actionButton.configuration?.cornerStyle = .capsule
        actionButton.configuration?.imagePlacement = .trailing
        actionButton.configuration?.imagePadding = 6
        actionButton.addAction(UIAction { [weak self] _ in self?.performMainAction() }, for: .touchUpInside)

        for subview in [closeButton, actionButton] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -8),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 48),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            content.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            actionButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            actionButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            actionButton.heightAnchor.constraint(equalToConstant: 52),
            actionButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -8),
        ])
        view.bringSubviewToFront(closeButton)
        updateSelection()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // ResizableSheetComponent fits the sheet to its content; a longer list scrolls.
        let height = 48 + content.systemLayoutSizeFitting(
            CGSize(width: view.bounds.width - 32, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        )
        .height + 16 + 8 + 52 + 8 + view.safeAreaInsets.bottom
        guard abs(height - fittingHeight) > 0.5 else { return }
        fittingHeight = height
        sheetPresentationController?.animateChanges {
            sheetPresentationController?.invalidateDetents()
        }
    }

    // MARK: Presenting

    /// PresentAddMembers and CreateGroupController: the refused people and the chat's primary invite link, which
    /// TDLib gives only to admins who may invite. `requiresLink` is CreateGroupController's case, which shows the
    /// sheet only with a link.
    static func present(
        failed: [FailedToAddMember],
        chatID: Int64,
        requiresLink: Bool = false,
        from presenter: UIViewController,
        toastHost: UIView?,
    ) async {
        guard !failed.isEmpty else { return }
        let accountID = TDLib.shared.activeAccountID
        let client = TDLib.shared.activeClient
        let link = await inviteLink(chatID: chatID, client: client)
        if requiresLink, link == nil { return }
        var people = [Person]()
        for member in failed {
            guard let person = await person(
                member.userId,
                requiresPremium: member.premiumRequiredToSendMessages,
                client: client,
            )
            else { continue }
            people.append(person)
        }
        guard !people.isEmpty, TDLib.shared.activeAccountID == accountID else { return }
        let sheet = SendInviteLinkViewController(
            people: people, link: link, accountID: accountID, client: client, toastHost: toastHost, isProbe: false,
        )
        presenter.present(sheet, animated: true)
    }

    #if DEBUG
    /// `-ui-probe-send-invite-link`: the sheet for up to three of the given people with a made-up link; nothing is
    /// sent.
    static func presentProbe(userIDs: [Int64], from presenter: UIViewController) async {
        let client = TDLib.shared.activeClient
        var people = [Person]()
        for (index, userID) in userIDs.prefix(3).enumerated() {
            if let person = await person(userID, requiresPremium: index == 2, client: client) {
                people.append(person)
            }
        }
        guard !people.isEmpty else { return }
        let sheet = SendInviteLinkViewController(
            people: people,
            link: "https://t.me/+BetterTGProbe",
            accountID: TDLib.shared.activeAccountID,
            client: client,
            toastHost: presenter.navigationController?.view ?? presenter.view,
            isProbe: true,
        )
        presenter.present(sheet, animated: true)
    }
    #endif

    private static func inviteLink(chatID: Int64, client: TDLibClient) async -> String? {
        guard let chat = try? await client.getChat(chatId: chatID) else { return nil }
        switch chat.type {
        case .chatTypeSupergroup(let group):
            return try? await client.getSupergroupFullInfo(supergroupId: group.supergroupId).inviteLink?.inviteLink
        case .chatTypeBasicGroup(let group):
            return try? await client.getBasicGroupFullInfo(basicGroupId: group.basicGroupId).inviteLink?.inviteLink
        default:
            return nil
        }
    }

    private static func person(_ userID: Int64, requiresPremium: Bool, client: TDLibClient) async -> Person? {
        guard let user = try? await client.getUser(userId: userID) else { return nil }
        let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return Person(
            peer: SettingsPeer(
                id: user.id,
                title: name.isEmpty ? L10n.telegram("User.DeletedAccount") : name,
                file: user.profilePhoto?.small,
                minithumbnail: user.profilePhoto?.minithumbnail,
                placeholder: user.telegramAvatarPlaceholder,
            ),
            status: UserPresenceText.text(for: user.status),
            requiresPremium: requiresPremium,
        )
    }

    /// ButtonTextContentComponent's badge: the count in the accent colour on a white capsule.
    private static func badge(_ count: Int) -> UIImage {
        let text = NSAttributedString(string: "\(count)", attributes: [
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: UIColor.tintColor,
        ])
        let textSize = text.size()
        let size = CGSize(width: max(20, ceil(textSize.width) + 12), height: 20)
        return UIGraphicsImageRenderer(size: size)
            .image { _ in
                UIColor.white.setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2).fill()
                text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2))
            }
            .withRenderingMode(.alwaysOriginal)
    }

    private static func sharedText(_ names: [String]) -> String {
        switch names.count {
        case 1: L10n.telegram("Conversation.ShareLinkTooltip.Chat.One", names[0])
        case 2: L10n.telegram("Conversation.ShareLinkTooltip.TwoChats.One", names[0], names[1])
        default: L10n.telegram("Conversation.ShareLinkTooltip.ManyChats.One", names[0], "\(names.count - 1)")
        }
    }

    /// Telegram's **bold** markers.
    private static func markdown(_ text: String, font: UIFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 0.2
        for (index, part) in text.components(separatedBy: "**").enumerated() {
            result.append(NSAttributedString(string: part, attributes: [
                .font: index.isMultiple(of: 2) ? font : UIFont.systemFont(ofSize: font.pointSize, weight: .semibold),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph,
            ]))
        }
        return result
    }

    /// AnimatedAvatarSetNode: the first three people at 64 points, the first on top, each later one cut around the one
    /// before it.
    private func makeAvatars() -> UIView {
        let container = UIView()
        let shown = Array(people.prefix(3))
        let step = Self.avatarSize - Self.avatarOverlap
        let width = Self.avatarSize + CGFloat(max(0, shown.count - 1)) * step
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            row.widthAnchor.constraint(equalToConstant: width),
            row.heightAnchor.constraint(equalToConstant: Self.avatarSize),
        ])
        for (index, person) in shown.enumerated().reversed() {
            let avatar = ProfileAvatarView()
            avatar.isUserInteractionEnabled = false
            avatar.frame = CGRect(x: CGFloat(index) * step, y: 0, width: Self.avatarSize, height: Self.avatarSize)
            avatar.configure(
                file: person.peer.file,
                minithumbnail: person.peer.minithumbnail,
                placeholder: person.peer.placeholder,
                accountID: accountID,
                client: client,
            )
            if index > 0 {
                let bounds = CGRect(origin: .zero, size: avatar.frame.size)
                let path = UIBezierPath(rect: bounds)
                path.append(UIBezierPath(ovalIn: bounds.offsetBy(dx: -step, dy: 0).insetBy(dx: -2, dy: -2)))
                let mask = CAShapeLayer()
                mask.fillRule = .evenOdd
                mask.frame = bounds
                mask.path = path.cgPath
                avatar.layer.mask = mask
            }
            row.addSubview(avatar)
        }
        container.isAccessibilityElement = false
        return container
    }

    /// PeerListItemComponent rows on one card: a 40-point avatar, the name over the presence (or the Premium note
    /// with a lock) and, for a person who can get the link, a check at the trailing edge.
    private func makeList() -> UIView {
        let card = UIStackView()
        card.axis = .vertical
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 26
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        for (index, person) in people.enumerated() {
            card.addArrangedSubview(makeRow(person, hasNext: index < people.count - 1))
        }
        return card
    }

    private func makeRow(_ person: Person, hasNext: Bool) -> UIView {
        let canSelect = link != nil && !person.requiresPremium
        let row = UIControl()
        row.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
        let avatar = ProfileAvatarView()
        avatar.isUserInteractionEnabled = false
        avatar.configure(
            file: person.peer.file,
            minithumbnail: person.peer.minithumbnail,
            placeholder: person.peer.placeholder,
            accountID: accountID,
            client: client,
        )
        let name = UILabel()
        name.text = person.peer.title
        name.font = .systemFont(ofSize: 17, weight: .semibold)
        let status = UILabel()
        status.font = .systemFont(ofSize: 15)
        if person.requiresPremium {
            let text = NSMutableAttributedString(attachment: NSTextAttachment(
                image: UIImage(
                    systemName: "lock.fill",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold),
                )?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal) ?? UIImage(),
            ))
            text.append(NSAttributedString(string: " " + L10n.telegram("SendInviteLink.StatusAvailableToPremiumOnly")))
            status.attributedText = text
            status.textColor = .secondaryLabel
        } else {
            status.text = person.status.text
            status.textColor = person.status.isOnline ? .tintColor : .secondaryLabel
        }
        let labels = UIStackView(arrangedSubviews: [name, status])
        labels.axis = .vertical
        labels.spacing = 1
        labels.isUserInteractionEnabled = false
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.isHidden = !hasNext
        for subview in [avatar, labels, separator] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(subview)
        }
        var constraints = [
            avatar.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            avatar.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 40),
            avatar.heightAnchor.constraint(equalToConstant: 40),
            labels.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 62),
            labels.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 62),
            separator.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / max(1, traitCollection.displayScale)),
        ]
        if canSelect {
            let check = UIImageView()
            check.contentMode = .scaleAspectFit
            check.isUserInteractionEnabled = false
            check.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(check)
            checks[person.peer.id] = check
            constraints += [
                check.centerXAnchor.constraint(equalTo: row.trailingAnchor, constant: -8 - 24),
                check.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                check.widthAnchor.constraint(equalToConstant: 22),
                check.heightAnchor.constraint(equalToConstant: 22),
                labels.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -8 - 48),
            ]
            let id = person.peer.id
            row.addAction(UIAction { [weak self] _ in self?.toggle(id) }, for: .touchUpInside)
        } else {
            constraints.append(labels.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -8))
            row.isUserInteractionEnabled = false
        }
        NSLayoutConstraint.activate(constraints)
        row.isAccessibilityElement = true
        row.accessibilityLabel = [name.text, status.attributedText?.string ?? status.text]
            .compactMap(\.self)
            .joined(separator: ", ")
        return row
    }

    // MARK: Selection

    private func toggle(_ id: Int64) {
        guard !isSending else { return }
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
        UIView.transition(with: view, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.updateSelection()
        }
    }

    /// The checks, and the button: Close without a link, Skip with nobody checked, else Send Invite Link with the
    /// checked count as its badge.
    private func updateSelection() {
        for (id, check) in checks {
            let isOn = selected.contains(id)
            check.image = UIImage(systemName: isOn ? "checkmark.circle.fill" : "circle")
            check.tintColor = isOn ? .tintColor : .tertiaryLabel
            check.superview?.accessibilityTraits = isOn ? [.button, .selected] : .button
        }
        let title =
            if link == nil {
                L10n.telegram("SendInviteLink.ActionClose")
            } else if selected.isEmpty {
                L10n.telegram("SendInviteLink.ActionSkip")
            } else {
                L10n.telegram("SendInviteLink.ActionInvite")
            }
        actionButton.configuration?.attributedTitle = AttributedString(
            title,
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]),
        )
        actionButton.configuration?.image = link == nil || selected.isEmpty ? nil : Self.badge(selected.count)
        actionButton.configuration?.showsActivityIndicator = isSending
        actionButton.isEnabled = !isSending
    }

    // MARK: Sending

    /// performMainAction: without a link or a checked person the sheet closes; else the link goes as a message to each
    /// checked person, and the sheet closes with Telegram's "Link shared with" toast.
    private func performMainAction() {
        guard !isSending else { return }
        guard let link, !selected.isEmpty else {
            dismiss(animated: true)
            return
        }
        let recipients = people.filter { selected.contains($0.peer.id) }.map(\.peer)
        if !isProbe {
            guard TDLib.shared.activeAccountID == accountID else {
                dismiss(animated: true)
                return
            }
            let client = client
            Task {
                for recipient in recipients {
                    guard let chat = try? await client.createPrivateChat(force: false, userId: recipient.id) else {
                        continue
                    }
                    _ = try? await client.sendMessage(
                        chatId: chat.id,
                        inputMessageContent: .inputMessageText(InputMessageText(
                            clearDraft: false,
                            linkPreviewOptions: nil,
                            text: FormattedText(entities: [], text: link),
                        )),
                        options: nil,
                        replyMarkup: nil,
                        replyTo: nil,
                        topicId: nil,
                    )
                }
            }
        }
        let text = Self.sharedText(recipients.map { $0.title.replacing("*", with: "") })
        let host = toastHost
        dismiss(animated: true) {
            if let host { TelegramUndoToast.show(text: text, in: host, bottomInset: 12, undo: nil) }
        }
    }
}
