// ChatJoinRequestsBannerView.swift

import TDLibKit
import UIKit

// MARK: - ChatJoinRequestsBannerView

/// Telegram's ChatInviteRequestsTitlePanelNode: a 40 pt panel under the chat's title for an administrator with pending
/// join requests, the latest requesters' 32 pt avatars overlapping from the left, "N Requests to Join" in 15 pt
/// medium accent centred but clear of them, and a 12 pt close cross. The panel opens the requests; the cross hides it
/// until someone else asks.
final class ChatJoinRequestsBannerView: UIView {
    static let contentHeight: CGFloat = 40

    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?

    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let openControl = UIControl()
    private var avatarViews = [ProfileAvatarView]()
    private var titleCenterConstraint: NSLayoutConstraint!
    private var renderedUserIDs = [Int64]()
    private var loadTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        addSubview(separator)

        openControl.translatesAutoresizingMaskIntoConstraints = false
        openControl.addTarget(self, action: #selector(openPressed), for: .touchUpInside)
        openControl.isAccessibilityElement = true
        openControl.accessibilityTraits = .button
        addSubview(openControl)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = tintColor
        titleLabel.isUserInteractionEnabled = false
        titleLabel.isAccessibilityElement = false
        addSubview(titleLabel)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(Self.closeImage(), for: .normal)
        closeButton.tintColor = tintColor
        closeButton.accessibilityLabel = L10n.telegram("Common.Close")
        closeButton.addTarget(self, action: #selector(closePressed), for: .touchUpInside)
        addSubview(closeButton)

        self.titleCenterConstraint = titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor)
        titleCenterConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / max(1, traitCollection.displayScale)),
            openControl.topAnchor.constraint(equalTo: topAnchor),
            openControl.leadingAnchor.constraint(equalTo: leadingAnchor),
            openControl.trailingAnchor.constraint(equalTo: trailingAnchor),
            openControl.heightAnchor.constraint(equalToConstant: Self.contentHeight),
            // The title sits a point below the middle, no nearer the left than 90 pt.
            titleLabel.centerYAnchor.constraint(equalTo: topAnchor, constant: Self.contentHeight / 2 + 1),
            titleCenterConstraint,
            titleLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor,
                constant: 90,
            ),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: topAnchor, constant: Self.contentHeight / 2),
            closeButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -5),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        titleLabel.textColor = tintColor
        closeButton.tintColor = tintColor
    }

    /// The cross of 1.33 pt rounded lines in a 12 pt square.
    private static func closeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12))
            .image { context in
                let cg = context.cgContext
                cg.setStrokeColor(UIColor.black.cgColor)
                cg.setLineWidth(1.33)
                cg.setLineCap(.round)
                cg.move(to: CGPoint(x: 1, y: 1))
                cg.addLine(to: CGPoint(x: 11, y: 11))
                cg.move(to: CGPoint(x: 11, y: 1))
                cg.addLine(to: CGPoint(x: 1, y: 11))
                cg.strokePath()
            }
            .withRenderingMode(.alwaysTemplate)
    }

    /// The count and the latest requesters TDLib names (`chatJoinRequestsInfo`), three at most.
    func configure(requests: ChatJoinRequestsInfo, client: TDLibClient) {
        let title = L10n.telegramPlural(
            "Conversation.RequestsToJoin",
            count: requests.totalCount,
            formattedCount: requests.totalCount.formatted(.number),
        )
        titleLabel.text = title
        openControl.accessibilityLabel = title
        let userIDs = Array(requests.userIds.prefix(3))
        guard userIDs != renderedUserIDs else { return }
        renderedUserIDs = userIDs
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            var peers = [SettingsPeer]()
            for id in userIDs {
                if let peer = await SettingsPeer.user(id, client: client) { peers.append(peer) }
            }
            guard !Task.isCancelled, let self else { return }
            showAvatars(peers, client: client)
        }
    }

    /// AnimatedAvatarSetNode: 32 pt avatars 22 pt apart, each on top of the next with a 1.5 pt gap ring.
    private func showAvatars(_ peers: [SettingsPeer], client: TDLibClient) {
        avatarViews.forEach { $0.removeFromSuperview() }
        avatarViews = peers.enumerated().reversed().map { index, peer in
            let avatar = ProfileAvatarView()
            avatar.translatesAutoresizingMaskIntoConstraints = false
            avatar.isUserInteractionEnabled = false
            avatar.layer.cornerRadius = 17.5
            avatar.layer.borderWidth = 1.5
            avatar.layer.borderColor = (backgroundColor ?? .systemBackground)
                .resolvedColor(with: traitCollection)
                .cgColor
            avatar.clipsToBounds = true
            avatar.configure(
                file: peer.file,
                minithumbnail: peer.minithumbnail,
                placeholder: peer.placeholder,
                client: client,
            )
            addSubview(avatar)
            NSLayoutConstraint.activate([
                avatar.leadingAnchor.constraint(
                    equalTo: safeAreaLayoutGuide.leadingAnchor,
                    constant: 4 - 1.5 + CGFloat(index) * 22,
                ),
                avatar.centerYAnchor.constraint(equalTo: topAnchor, constant: Self.contentHeight / 2),
                avatar.widthAnchor.constraint(equalToConstant: 35),
                avatar.heightAnchor.constraint(equalToConstant: 35),
            ])
            return avatar
        }
        bringSubviewToFront(closeButton)
    }

    @objc private func openPressed() {
        onOpen?()
    }

    @objc private func closePressed() {
        onClose?()
    }
}

// MARK: - ChatJoinRequestsDismissal

/// ApplicationSpecificNotice's dismissed invitation requests: the requesters shown when the panel was closed, per
/// account and chat; the panel returns once the latest requesters differ.
enum ChatJoinRequestsDismissal {
    static func isDismissed(_ requests: ChatJoinRequestsInfo, accountID: UUID?, chatID: Int64) -> Bool {
        guard let stored = UserDefaults.standard.array(forKey: key(accountID: accountID, chatID: chatID))
            as? [Int64] else { return false }
        return Set(stored) == Set(requests.userIds.prefix(3))
    }

    static func dismiss(_ requests: ChatJoinRequestsInfo, accountID: UUID?, chatID: Int64) {
        UserDefaults.standard.set(Array(requests.userIds.prefix(3)), forKey: key(accountID: accountID, chatID: chatID))
    }

    private static func key(accountID: UUID?, chatID: Int64) -> String {
        "BetterTG.dismissedJoinRequests.\(accountID?.uuidString ?? "none").\(chatID)"
    }
}
