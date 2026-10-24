// StoryViewerFooterPanel.swift

import TDLibKit
import UIKit

// MARK: - StoryFooterPanel

/// StoryFooterPanelComponent under the account's own story, where someone else's story has the reply panel: the
/// latest viewers' avatars, the view count or No Views, the reactions in red and the reposts in green, and the delete
/// button on the right. Telegram's viewers list behind the counts, the upload status of a story being posted (BetterTG
/// doesn't post stories) and the channel footer with its like and share buttons are left out.
enum StoryFooterPanel {
    struct Configuration: Equatable {
        let viewCount: Int
        let reactionCount: Int
        let forwardCount: Int
        /// AnimatedAvatarSetContext's peers: the latest three viewers.
        let recentViewerIDs: [Int64]
        let canDelete: Bool
    }

    /// The footer for the story, or nil where Telegram shows none: someone else's story and a live stream.
    static func configuration(story: Story, isOwn: Bool) -> Configuration? {
        guard isOwn else { return nil }
        if case .storyContentLive = story.content { return nil }
        // Telegram reads the reactions and reposts only once the story has views.
        let info = story.interactionInfo.flatMap { $0.viewCount != 0 ? $0 : nil }
        return Configuration(
            viewCount: info?.viewCount ?? 0,
            reactionCount: info?.reactionCount ?? 0,
            forwardCount: info?.forwardCount ?? 0,
            recentViewerIDs: Array((info?.recentViewerUserIds ?? []).prefix(3)),
            canDelete: story.canBeDeleted,
        )
    }

    /// Story.Footer.ViewCount without the count Telegram draws on its own: "|3| Views" leaves " Views".
    static func viewsLabel(count: Int) -> String {
        guard count != 0 else { return L10n.telegram("Story.Footer.NoViews") }
        var string = L10n.telegramPlural("Story.Footer.ViewCount", count: count)
        if let first = string.range(of: "|"),
           let second = string.range(of: "|", range: first.upperBound..<string.endIndex)
        {
            string.removeSubrange(string.startIndex..<second.upperBound)
        }
        return string
    }

    /// countString: thousands, millions and billions with one decimal rounded down, 1.2K or 3M.
    static func countText(_ count: Int) -> String {
        let count = Int64(count)
        let billion = Int64(1_000_000_000)
        let million = Int64(1_000_000)
        if count >= billion {
            let remainder = Int64((Double(count % billion) / 100_000_000).rounded(.down))
            return remainder != 0 ? "\(count / billion).\(remainder)T" : "\(count / billion)T"
        }
        if count >= million {
            let remainder = Int64((Double(count % million) / 100_000).rounded(.down))
            return remainder != 0 ? "\(count / million).\(remainder)M" : "\(count / million)M"
        }
        if count >= 1000 {
            let remainder = (count % 1000) / 102
            return remainder != 0 ? "\(count / 1000).\(remainder)K" : "\(count / 1000)K"
        }
        return String(count)
    }
}

// MARK: - StoryFooterPanelView

final class StoryFooterPanelView: UIView {
    static let height = CGFloat(44)
    /// The footer's top below the story (footerPanelY at rest).
    static let topSpacing = CGFloat(10)

    private static let avatarSize = CGFloat(30)
    /// AnimatedAvatarSetView's overlap between neighbouring avatars.
    private static let avatarOverlap = CGFloat(10)
    private static let avatarViewsSpacing = CGFloat(18)
    private static let groupSpacing = CGFloat(6)
    private static let iconSpacing = CGFloat(2)
    private static let iconSize = CGSize(width: 23, height: 23)

    var onDelete: (() -> Void)?

    private(set) var configuration: StoryFooterPanel.Configuration?

    private var avatarViews = [ProfileAvatarView]()
    private let countLabel = UILabel()
    private let viewsLabel = UILabel()
    private let reactionIcon = UIImageView()
    private let reactionLabel = UILabel()
    private let forwardIcon = UIImageView()
    private let forwardLabel = UILabel()
    private let deleteButton = UIButton(type: .system)
    private var avatarTask: Task<Void, Never>?

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        let numbers = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        for label in [countLabel, reactionLabel, forwardLabel] {
            label.font = numbers
            label.textColor = .white
            addSubview(label)
        }
        viewsLabel.font = .systemFont(ofSize: 15)
        viewsLabel.textColor = .white
        addSubview(viewsLabel)
        reactionIcon.image = UIImage(systemName: "heart.fill")
        reactionIcon.tintColor = UIColor(red: 1, green: 0x3B / 255, blue: 0x30 / 255, alpha: 1)
        forwardIcon.image = UIImage(systemName: "arrow.2.squarepath")
        forwardIcon.tintColor = UIColor(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255, alpha: 1)
        for icon in [reactionIcon, forwardIcon] {
            icon.contentMode = .center
            icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
            addSubview(icon)
        }
        deleteButton.tintColor = .white
        deleteButton.setImage(
            UIImage(systemName: "trash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)),
            for: .normal,
        )
        deleteButton.accessibilityLabel = L10n.telegram("Story.ContextDeleteStory")
        deleteButton.accessibilityIdentifier = "story-footer-delete"
        deleteButton.addTarget(self, action: #selector(deletePressed), for: .touchUpInside)
        addSubview(deleteButton)
    }

    deinit {
        avatarTask?.cancel()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let configuration else { return }
        let height = bounds.height
        var x = CGFloat(16)
        for (index, avatar) in avatarViews.enumerated() {
            avatar.frame = CGRect(
                x: x + CGFloat(index) * (Self.avatarSize - Self.avatarOverlap),
                y: ((height - Self.avatarSize) / 2).rounded(.down),
                width: Self.avatarSize,
                height: Self.avatarSize,
            )
            if index > 0 { applyCutout(to: avatar) }
        }
        if let last = avatarViews.last {
            x = last.frame.maxX + Self.avatarViewsSpacing
        }
        if configuration.viewCount != 0 {
            x = place(countLabel, at: x)
        }
        x = place(viewsLabel, at: x)
        if configuration.reactionCount != 0 {
            x = place(reactionIcon, at: x + Self.groupSpacing, size: Self.iconSize)
            x = place(reactionLabel, at: x + Self.iconSpacing)
        }
        if configuration.forwardCount != 0 {
            x = place(forwardIcon, at: x + Self.groupSpacing, size: Self.iconSize)
            _ = place(forwardLabel, at: x + Self.iconSpacing)
        }
        deleteButton.frame = CGRect(x: bounds.width - 12 - 44, y: (height - 44) / 2, width: 44, height: 44)
    }

    func configure(
        _ configuration: StoryFooterPanel.Configuration?,
        avatar: @escaping @MainActor (Int64) async -> SettingsPeer?,
        client: TDLibClient,
    ) {
        let viewersChanged = configuration?.recentViewerIDs != self.configuration?.recentViewerIDs
        self.configuration = configuration
        guard let configuration else {
            avatarTask?.cancel()
            avatarViews.forEach { $0.removeFromSuperview() }
            avatarViews = []
            return
        }
        countLabel.text = StoryFooterPanel.countText(configuration.viewCount)
        countLabel.isHidden = configuration.viewCount == 0
        viewsLabel.text = StoryFooterPanel.viewsLabel(count: configuration.viewCount)
        reactionLabel.text = String(configuration.reactionCount)
        reactionIcon.isHidden = configuration.reactionCount == 0
        reactionLabel.isHidden = configuration.reactionCount == 0
        forwardLabel.text = String(configuration.forwardCount)
        forwardIcon.isHidden = configuration.forwardCount == 0
        forwardLabel.isHidden = configuration.forwardCount == 0
        deleteButton.isHidden = !configuration.canDelete
        if viewersChanged { loadAvatars(configuration.recentViewerIDs, avatar: avatar, client: client) }
        // VoiceOver reads the views with their count and the reactions and reposts beside them.
        viewsLabel.accessibilityLabel = [
            configuration.viewCount != 0 ? countLabel.text : nil,
            viewsLabel.text,
            configuration.reactionCount != 0 ? "❤ \(configuration.reactionCount)" : nil,
            configuration.forwardCount != 0 ? "🔁 \(configuration.forwardCount)" : nil,
        ]
            .compactMap(\.self)
            .joined(separator: " ")
        accessibilityElements = configuration.canDelete ? [viewsLabel, deleteButton] : [viewsLabel]
        setNeedsLayout()
    }

    // MARK: Private

    private func loadAvatars(
        _ ids: [Int64],
        avatar: @escaping @MainActor (Int64) async -> SettingsPeer?,
        client: TDLibClient,
    ) {
        avatarTask?.cancel()
        avatarViews.forEach { $0.removeFromSuperview() }
        avatarViews = ids.map { id in
            let view = ProfileAvatarView()
            view.showsContextMenu = false
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            view.configure(
                file: nil,
                minithumbnail: nil,
                placeholder: TelegramAvatarPlaceholder(
                    peerID: id,
                    accentColorID: 0,
                    upgradedGiftColors: nil,
                    letters: [],
                    isDeleted: false,
                ),
                client: client,
            )
            return view
        }
        for (index, view) in avatarViews.enumerated() {
            // AnimatedAvatarSetView keeps the latest viewer on top.
            view.layer.zPosition = CGFloat(100 - index)
            addSubview(view)
        }
        let views = avatarViews
        avatarTask = Task { [weak self] in
            for (id, view) in zip(ids, views) {
                guard let peer = await avatar(id), !Task.isCancelled, self != nil else { continue }
                view.configure(
                    file: peer.file,
                    minithumbnail: peer.minithumbnail,
                    placeholder: peer.placeholder,
                    client: client,
                )
            }
        }
    }

    /// AnimatedAvatarSetView's clipped avatars: the left neighbour's circle, 1.5 pt larger, is cut out.
    private func applyCutout(to avatar: ProfileAvatarView) {
        let bounds = avatar.bounds
        let path = UIBezierPath(rect: bounds)
        let neighbour = bounds
            .offsetBy(dx: Self.avatarOverlap - Self.avatarSize, dy: 0)
            .insetBy(dx: -1.5, dy: -1.5)
        path.append(UIBezierPath(ovalIn: neighbour))
        let mask = (avatar.layer.mask as? CAShapeLayer) ?? CAShapeLayer()
        mask.fillRule = .evenOdd
        mask.frame = bounds
        mask.path = path.cgPath
        avatar.layer.mask = mask
    }

    private func place(_ view: UIView, at x: CGFloat, size: CGSize? = nil) -> CGFloat {
        let size = size ?? view.sizeThatFits(CGSize(width: bounds.width, height: bounds.height))
        view.frame = CGRect(
            x: x,
            y: ((bounds.height - size.height) / 2).rounded(.down),
            width: size.width,
            height: size.height,
        )
        return view.frame.maxX
    }

    @objc private func deletePressed() {
        onDelete?()
    }
}
