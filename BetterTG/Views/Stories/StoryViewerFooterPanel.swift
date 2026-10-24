// StoryViewerFooterPanel.swift

import TDLibKit
import UIKit

// MARK: - StoryFooterPanel

/// StoryFooterPanelComponent under the account's own story, where someone else's story has the reply panel: the
/// latest viewers' avatars, the view count or No Views, the reactions in red and the reposts in green, and the delete
/// button on the right. The counts open the viewers list. The upload status of a story being posted (BetterTG doesn't
/// post stories) and the channel footer with its like and share buttons are left out.
enum StoryFooterPanel {
    struct Configuration: Equatable {
        let viewCount: Int
        let reactionCount: Int
        let forwardCount: Int
        /// AnimatedAvatarSetContext's peers: the latest three viewers.
        let recentViewerIDs: [Int64]
        let canDelete: Bool
        /// A channel's story, or a group's the account can't write to: the views, then the like and share buttons
        /// on the right.
        var isChannel = false
        /// forwardAction: a public channel's story that may be forwarded.
        var canShare = false
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

    /// The channel footer (isChannel) under a channel's story, or a group's where the account can't write: at least one
    /// view, the reactions, and Share for a public channel's forwardable story. A live
    /// stream has none. Telegram's repost button opens its story editor, which BetterTG doesn't have.
    static func channelConfiguration(story: Story, poster: StoryReplyPanel.Poster) -> Configuration? {
        if case .storyContentLive = story.content { return nil }
        let isPublic: Bool
        switch poster {
        case .channel(let value):
            isPublic = value
        case .group(false, let value):
            isPublic = value
        case .group,
             .other,
             .user:
            return nil
        }
        let info = story.interactionInfo.flatMap { $0.viewCount != 0 ? $0 : nil }
        return Configuration(
            viewCount: max(1, info?.viewCount ?? 0),
            reactionCount: info?.reactionCount ?? 0,
            forwardCount: info?.forwardCount ?? 0,
            recentViewerIDs: [],
            canDelete: false,
            isChannel: true,
            canShare: isPublic && story.canBeForwarded,
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

    private static let reactionColor = UIColor(red: 1, green: 0x3B / 255, blue: 0x30 / 255, alpha: 1)
    private static let forwardColor = UIColor(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255, alpha: 1)

    var onDelete: (() -> Void)?
    /// The channel footer's like and share buttons (likeAction, forwardAction).
    var onLike: (() -> Void)?
    var onShare: (() -> Void)?
    /// The channel footer's like button, which shows the account's reaction.
    let likeButton = StoryLikeButton()
    /// viewStatsButton's expandViewStats: the avatars and counts open the viewers list.
    var onOpenViews: (() -> Void)?

    /// expandFraction while the viewers list opens: the avatars and the views label shrink away, an eye takes the
    /// count, the counts gather in the middle in white, and the delete button drops 45 points as it fades.
    var expandFraction = CGFloat.zero {
        didSet {
            guard expandFraction != oldValue else { return }
            setNeedsLayout()
            layoutIfNeeded()
        }
    }

    private(set) var configuration: StoryFooterPanel.Configuration?

    private var avatarViews = [ProfileAvatarView]()
    private let countLabel = UILabel()
    private let viewsLabel = UILabel()
    private let reactionIcon = UIImageView()
    private let reactionLabel = UILabel()
    private let forwardIcon = UIImageView()
    private let forwardLabel = UILabel()
    private let deleteButton = UIButton(type: .system)
    private let eyeIcon = UIImageView()
    private let statsButton = UIControl()
    private let likeCountLabel = UILabel()
    private let shareButton = UIButton(type: .system)
    private var avatarTask: Task<Void, Never>?

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        statsButton.addTarget(self, action: #selector(openViews), for: .touchUpInside)
        statsButton.isAccessibilityElement = true
        statsButton.accessibilityTraits = .button
        statsButton.accessibilityIdentifier = "story-footer-views"
        addSubview(statsButton)
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
        reactionIcon.tintColor = Self.reactionColor
        forwardIcon.image = UIImage(systemName: "arrow.2.squarepath")
        forwardIcon.tintColor = Self.forwardColor
        eyeIcon.image = UIImage(systemName: "eye.fill")
        eyeIcon.tintColor = .white
        eyeIcon.alpha = 0
        for icon in [eyeIcon, reactionIcon, forwardIcon] {
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
        likeButton.addAction(UIAction { [weak self] _ in self?.onLike?() }, for: .touchUpInside)
        likeButton.accessibilityIdentifier = "story-footer-like"
        addSubview(likeButton)
        likeCountLabel.font = numbers
        likeCountLabel.textColor = .white
        likeCountLabel.isUserInteractionEnabled = false
        likeButton.addSubview(likeCountLabel)
        shareButton.tintColor = .white
        shareButton.setImage(
            UIImage(systemName: "paperplane", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)),
            for: .normal,
        )
        shareButton.accessibilityLabel = L10n.telegram("Story.Context.Share")
        shareButton.accessibilityIdentifier = "story-footer-share"
        shareButton.addAction(UIAction { [weak self] _ in self?.onShare?() }, for: .touchUpInside)
        addSubview(shareButton)
    }

    deinit {
        avatarTask?.cancel()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let configuration else { return }
        if configuration.isChannel {
            layoutChannel(configuration)
            return
        }
        let height = bounds.height
        let fraction = expandFraction
        for (index, avatar) in avatarViews.enumerated() {
            avatar.transform = .identity
            avatar.frame = CGRect(
                x: 16 + CGFloat(index) * (Self.avatarSize - Self.avatarOverlap),
                y: ((height - Self.avatarSize) / 2).rounded(.down),
                width: Self.avatarSize,
                height: Self.avatarSize,
            )
            if index > 0 { applyCutout(to: avatar) }
            let scale = 1 - 0.9 * fraction
            avatar.transform = CGAffineTransform(scaleX: scale, y: scale)
            avatar.alpha = 1 - fraction
        }

        // At rest: the avatars, the count and Views, then the reactions and reposts.
        let collapsed = layoutPositions(
            start: (avatarViews.last.map(\.frame.maxX) ?? 16)
                + (avatarViews.isEmpty ? 0 : Self.avatarViewsSpacing),
            showsEye: false,
            showsViewsLabel: true,
            configuration: configuration,
        )
        // Expanded: an eye with the count, the reactions and reposts, gathered in the middle.
        let expandedWidth = layoutPositions(
            start: 0,
            showsEye: true,
            showsViewsLabel: false,
            configuration: configuration,
        ).end
        let expanded = layoutPositions(
            start: ((bounds.width - expandedWidth) / 2).rounded(.down),
            showsEye: true,
            showsViewsLabel: false,
            configuration: configuration,
        )
        func place(_ view: UIView, _ key: String) {
            guard let from = collapsed.frames[key] ?? expanded.frames[key],
                  let to = expanded.frames[key] ?? collapsed.frames[key] else { return }
            view.transform = .identity
            view.frame = CGRect(
                x: from.minX + (to.minX - from.minX) * fraction,
                y: ((height - from.height) / 2).rounded(.down),
                width: from.width,
                height: from.height,
            )
        }
        place(eyeIcon, "eye")
        place(countLabel, "count")
        place(viewsLabel, "views")
        place(reactionIcon, "reactionIcon")
        place(reactionLabel, "reaction")
        place(forwardIcon, "forwardIcon")
        place(forwardLabel, "forward")
        eyeIcon.alpha = fraction
        eyeIcon.transform = CGAffineTransform(scaleX: 0.1 + 0.9 * fraction, y: 0.1 + 0.9 * fraction)
        // Telegram's single count shows only expanded where nobody viewed the story.
        countLabel.alpha = configuration.viewCount != 0 ? 1 : fraction
        viewsLabel.alpha = 1 - fraction
        viewsLabel.transform = CGAffineTransform(scaleX: 1 - 0.9 * fraction, y: 1 - 0.9 * fraction)
        reactionIcon.tintColor = Self.mixed(Self.reactionColor, with: .white, amount: fraction)
        forwardIcon.tintColor = Self.mixed(Self.forwardColor, with: .white, amount: fraction)
        deleteButton.frame = CGRect(
            x: bounds.width - 12 - 44,
            y: (height - 44) / 2 + 45 * fraction,
            width: 44,
            height: 44,
        )
        deleteButton.alpha = 1 - fraction
        let statsEnd = max(collapsed.end, viewsLabel.frame.maxX) + 8
        statsButton.frame = CGRect(x: 0, y: 0, width: min(statsEnd, deleteButton.frame.minX), height: height)
        // viewStatsButton and the buttons take touches only at rest.
        isUserInteractionEnabled = fraction == 0
    }

    private static func mixed(_ color: UIColor, with other: UIColor, amount: CGFloat) -> UIColor {
        var r1 = CGFloat.zero
        var g1 = CGFloat.zero
        var b1 = CGFloat.zero
        var a1 = CGFloat.zero
        var r2 = CGFloat.zero
        var g2 = CGFloat.zero
        var b2 = CGFloat.zero
        var a2 = CGFloat.zero
        color.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * amount,
            green: g1 + (g2 - g1) * amount,
            blue: b1 + (b2 - b1) * amount,
            alpha: a1 + (a2 - a1) * amount,
        )
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
        viewsLabel.text = StoryFooterPanel.viewsLabel(count: configuration.viewCount)
        reactionLabel.text = String(configuration.reactionCount)
        reactionIcon.isHidden = configuration.reactionCount == 0
        reactionLabel.isHidden = configuration.reactionCount == 0
        forwardLabel.text = String(configuration.forwardCount)
        forwardIcon.isHidden = configuration.forwardCount == 0
        forwardLabel.isHidden = configuration.forwardCount == 0
        deleteButton.isHidden = !configuration.canDelete
        // The channel footer's views, like and share in place of the own story's avatars, labels and delete button.
        let isChannel = configuration.isChannel
        viewsLabel.isHidden = isChannel
        if isChannel {
            reactionIcon.isHidden = true
            reactionLabel.isHidden = true
            forwardIcon.isHidden = true
            forwardLabel.isHidden = true
        }
        likeButton.isHidden = !isChannel
        shareButton.isHidden = !isChannel || !configuration.canShare
        statsButton.isEnabled = !isChannel
        if viewersChanged { loadAvatars(configuration.recentViewerIDs, avatar: avatar, client: client) }
        // VoiceOver reads the views with their count and the reactions and reposts beside them; they open the list.
        statsButton.accessibilityLabel = [
            configuration.viewCount != 0 ? countLabel.text : nil,
            viewsLabel.text,
            configuration.reactionCount != 0 ? "❤ \(configuration.reactionCount)" : nil,
            configuration.forwardCount != 0 ? "🔁 \(configuration.forwardCount)" : nil,
        ]
            .compactMap(\.self)
            .joined(separator: " ")
        if isChannel {
            statsButton.accessibilityLabel = L10n.telegramPlural(
                "Story.Footer.ViewCount",
                count: configuration.viewCount,
            )
            .replacing("|", with: "")
            accessibilityElements = [statsButton, likeButton] + (configuration.canShare ? [shareButton] : [])
        } else {
            accessibilityElements = configuration.canDelete ? [statsButton, deleteButton] : [statsButton]
        }
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

    /// The channel footer: the eye and the views 16 points in; from 12 points before the right edge the reactions'
    /// count after the 33-point like button, then 14 points to the left the share button.
    private func layoutChannel(_ configuration: StoryFooterPanel.Configuration) {
        let height = bounds.height
        let eye = CGRect(
            x: 16,
            y: ((height - Self.iconSize.height) / 2).rounded(.down),
            width: Self.iconSize.width,
            height: Self.iconSize.height,
        )
        eyeIcon.transform = .identity
        eyeIcon.frame = eye
        eyeIcon.alpha = 1
        let countSize = countLabel.sizeThatFits(bounds.size)
        countLabel.frame = CGRect(
            x: eye.maxX + Self.iconSpacing,
            y: ((height - countSize.height) / 2).rounded(.down),
            width: countSize.width,
            height: countSize.height,
        )
        countLabel.alpha = 1
        var right = bounds.width - 12
        // The account's own reaction counts at once, as Telegram's myReaction does, before TDLib's count follows.
        let reactions = likeButton.reaction != nil ? max(1, configuration.reactionCount) : configuration.reactionCount
        likeCountLabel.text = String(reactions)
        likeCountLabel.isHidden = reactions == 0
        let likeCountSize = likeCountLabel.sizeThatFits(bounds.size)
        let likeCountWidth = reactions != 0 ? likeCountSize.width + 1 : 0
        right -= likeCountWidth
        let buttonY = ((height - 33) / 2).rounded(.down)
        likeButton.frame = CGRect(x: right - 33, y: buttonY, width: 33, height: 33)
        likeCountLabel.frame = CGRect(
            x: 33 + 1,
            y: ((33 - likeCountSize.height) / 2).rounded(.down),
            width: likeCountSize.width,
            height: likeCountSize.height,
        )
        right -= 33 + 14
        shareButton.frame = CGRect(x: right - 33, y: buttonY, width: 33, height: 33)
        statsButton.frame = .zero
        isUserInteractionEnabled = true
    }

    /// The frames of the stats from `start` in one of the two arrangements, and where they end.
    private func layoutPositions(
        start: CGFloat,
        showsEye: Bool,
        showsViewsLabel: Bool,
        configuration: StoryFooterPanel.Configuration,
    ) -> (frames: [String: CGRect], end: CGFloat) {
        var frames = [String: CGRect]()
        var x = start
        func add(_ key: String, _ view: UIView, at origin: CGFloat, size: CGSize? = nil) {
            let size = size ?? view.sizeThatFits(CGSize(width: bounds.width, height: bounds.height))
            frames[key] = CGRect(x: origin, y: 0, width: size.width, height: size.height)
            x = origin + size.width
        }
        if showsEye { add("eye", eyeIcon, at: x, size: Self.iconSize) }
        if configuration.viewCount != 0 || showsEye {
            add("count", countLabel, at: showsEye ? x + Self.iconSpacing : x)
        }
        if showsViewsLabel { add("views", viewsLabel, at: x) }
        if configuration.reactionCount != 0 {
            add("reactionIcon", reactionIcon, at: x + Self.groupSpacing, size: Self.iconSize)
            add("reaction", reactionLabel, at: x + Self.iconSpacing)
        }
        if configuration.forwardCount != 0 {
            add("forwardIcon", forwardIcon, at: x + Self.groupSpacing, size: Self.iconSize)
            add("forward", forwardLabel, at: x + Self.iconSpacing)
        }
        return (frames, x)
    }

    @objc private func deletePressed() {
        onDelete?()
    }

    @objc private func openViews() {
        onOpenViews?()
    }
}
