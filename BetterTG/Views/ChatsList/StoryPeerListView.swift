// StoryPeerListView.swift

import TDLibKit
import UIKit

// MARK: - StoryPeerListCollapsedView

/// StoryPeerListComponent collapsed into the chat list's title: up to three posters with active stories as 24 pt
/// avatars 14 pt apart, each in its story ring, the first on top, 8 pt before the title.
final class StoryPeerListCollapsedView: UIView {
    struct Item: Equatable {
        let peer: SettingsPeer
        let ringStyle: StoryAvatarRingView.Style

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.peer.id == rhs.peer.id && lhs.ringStyle == rhs.ringStyle
                && lhs.peer.file?.id == rhs.peer.file?.id
        }
    }

    static let itemSize: CGFloat = 24
    static let itemDistance: CGFloat = 14

    override var intrinsicContentSize: CGSize {
        guard !items.isEmpty else { return .zero }
        return CGSize(
            width: Self.itemSize + Self.itemDistance * CGFloat(items.count - 1),
            height: Self.itemSize,
        )
    }

    private(set) var items = [Item]()

    private var itemViews = [(ring: StoryAvatarRingView, avatar: ProfileAvatarView)]()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let y = ((bounds.height - Self.itemSize) / 2).rounded()
        for (index, view) in itemViews.enumerated() {
            view.ring.frame = CGRect(
                x: CGFloat(index) * Self.itemDistance,
                y: y,
                width: Self.itemSize,
                height: Self.itemSize,
            )
            // AvatarNode.updateStoryIndicator: one line width between the avatar and its ring.
            view.avatar.frame = view.ring.bounds.insetBy(dx: 2.5, dy: 2.5)
        }
    }

    func update(items: [Item], client: TDLibClient, accountID: UUID?) {
        let items = Array(items.prefix(3))
        guard items != self.items else { return }
        self.items = items
        itemViews.forEach { $0.ring.removeFromSuperview() }
        itemViews = items.map { item in
            let ring = StoryAvatarRingView(activeLineWidth: 1.33, inactiveLineWidth: 1)
            ring.style = item.ringStyle
            let avatar = ProfileAvatarView()
            avatar.isUserInteractionEnabled = false
            avatar.configure(
                file: item.peer.file,
                minithumbnail: item.peer.minithumbnail,
                placeholder: item.peer.placeholder,
                accountID: accountID,
                client: client,
            )
            ring.addSubview(avatar)
            return (ring, avatar)
        }
        // The first poster on top, as StoryPeerListComponent stacks the collapsed items.
        for view in itemViews.reversed() {
            addSubview(view.ring)
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}

// MARK: - StorySubscriptions

/// EngineStorySubscriptions for the account's main story list: the chats with active stories (loadActiveStories,
/// updateChatActiveStories) by their order, unseen ones first as TDLib orders them.
@MainActor final class StorySubscriptions {
    struct Entry {
        let chatID: Int64
        let order: Int64
        let ringStyle: StoryAvatarRingView.Style
    }

    var onChange: (() -> Void)?
    private(set) var entries = [Entry]()

    private var byChat = [Int64: Entry]()
    private var loadTask: Task<Void, Never>?

    /// The posters in TDLib's order.
    var ordered: [Entry] {
        byChat.values.sorted { $0.order > $1.order }
    }

    func reset() {
        loadTask?.cancel()
        byChat = [:]
        entries = []
        onChange?()
    }

    /// Asks TDLib for the main list until it has sent every poster (a 404), each arriving as
    /// updateChatActiveStories; while the client is still starting it asks again a second later.
    func load(client: TDLibClient) {
        loadTask?.cancel()
        loadTask = Task {
            var pages = 0
            for _ in 0..<60 {
                guard !Task.isCancelled, pages < 20 else { return }
                do {
                    _ = try await client.send(TDNativeRequests.loadActiveStories(storyList: .storyListMain))
                    pages += 1
                } catch let error as TDLibError where error.code != 404 {
                    try? await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
    }

    func apply(_ stories: TDNativeChatActiveStories) {
        guard case .storyListMain? = stories.list, stories.order != 0, let last = stories.stories.last else {
            if byChat.removeValue(forKey: stories.chatId) != nil { changed() }
            return
        }
        let isLive = stories.stories.contains { $0.isLive }
        let style: StoryAvatarRingView.Style = isLive
            ? .live
            : stories.maxReadStoryId < last.storyId ? .unseen : .seen
        let entry = Entry(chatID: stories.chatId, order: stories.order, ringStyle: style)
        guard byChat[stories.chatId].map({ $0.order != entry.order || $0.ringStyle != entry.ringStyle }) ?? true
        else { return }
        byChat[stories.chatId] = entry
        changed()
    }

    private func changed() {
        entries = ordered
        onChange?()
    }
}

// MARK: - StoryPeerListExpandedView

/// StoryPeerListComponent unlocked: a row of 60 by 77 pt items 14 pt apart, 16 pt under the bar, each a 52 pt avatar
/// in its story ring with the poster's name under it in 11 pt, dimmed once everything is seen; the account's own
/// stories lead as My Story.
final class StoryPeerListExpandedView: UIView {
    struct Item: Equatable {
        let chatID: Int64
        let peer: SettingsPeer
        let title: String
        /// None for the account before its first story.
        let ringStyle: StoryAvatarRingView.Style?
        /// StoryPeerListItemComponent's plus on My Story while the account has no story.
        var showsAdd = false
        /// ringAnimation's indefinite dashes while a story uploads.
        var isUploading = false
        /// ringAnimation's progress once TDLib reports it; left out of equality, as it moves the arc in place.
        var uploadProgress: Float?

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.chatID == rhs.chatID && lhs.title == rhs.title && lhs.ringStyle == rhs.ringStyle
                && lhs.peer.file?.id == rhs.peer.file?.id && lhs.showsAdd == rhs.showsAdd
                && lhs.isUploading == rhs.isUploading
        }
    }

    private final class ItemView: UIControl {
        override var isHighlighted: Bool {
            didSet { alpha = isHighlighted ? 0.6 : 1 }
        }

        let ringView = StoryAvatarRingView(activeLineWidth: 2.33, inactiveLineWidth: 1.33)
        let chatID: Int64

        private let avatar = ProfileAvatarView()
        private let titleLabel = UILabel()
        private let addBadge = UIImageView()
        /// StoryPeerListItemComponent's indefiniteDashLayer: a dashed ring turning while the story uploads.
        private let uploadRing = CAShapeLayer()
        /// StoryProgressLayer's uploadProgressLayer: an arc as long as the share uploaded, turning every 2 s.
        private let progressRing = CAShapeLayer()

        init(item: Item, client: TDLibClient, accountID: UUID?) {
            self.chatID = item.chatID
            super.init(frame: .zero)
            ringView.isUserInteractionEnabled = false
            ringView.style = item.ringStyle
            avatar.isUserInteractionEnabled = false
            avatar.configure(
                file: item.peer.file,
                minithumbnail: item.peer.minithumbnail,
                placeholder: item.peer.placeholder,
                // The account's own item shows its photo, not Saved Messages.
                usesPeerPhotoForSavedMessages: true,
                accountID: accountID,
                client: client,
            )
            addSubview(ringView)
            addSubview(avatar)
            titleLabel.text = item.title
            titleLabel.font = .systemFont(ofSize: 11)
            titleLabel.textAlignment = .center
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.textColor = item.ringStyle == .seen ? .label.withAlphaComponent(0.5) : .label
            addSubview(titleLabel)
            // A 20 pt accent circle with a white plus, cut out of the avatar by the background's 2 pt ring.
            addBadge.image = UIImage(
                systemName: "plus",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold),
            )
            addBadge.tintColor = .white
            addBadge.contentMode = .center
            addBadge.backgroundColor = .systemBlue
            addBadge.layer.cornerRadius = 10
            addBadge.layer.borderWidth = 2
            addBadge.layer.borderColor = UIColor.systemGroupedBackground.cgColor
            addBadge.isHidden = !item.showsAdd || item.isUploading
            addSubview(addBadge)
            uploadRing.fillColor = nil
            uploadRing.strokeColor = UIColor.systemBlue.cgColor
            uploadRing.lineWidth = 2.33
            uploadRing.lineCap = .round
            uploadRing.lineDashPattern = [8, 6]
            uploadRing.isHidden = !item.isUploading
            layer.addSublayer(uploadRing)
            progressRing.fillColor = nil
            progressRing.strokeColor = UIColor.systemBlue.cgColor
            progressRing.lineWidth = 2.33
            progressRing.lineCap = .round
            progressRing.strokeEnd = 0
            progressRing.isHidden = true
            layer.addSublayer(progressRing)
            if item.isUploading {
                ringView.isHidden = true
                for ring in [uploadRing, progressRing] {
                    let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                    spin.fromValue = 0
                    spin.toValue = 2 * Double.pi
                    spin.duration = 2
                    spin.repeatCount = .infinity
                    ring.add(spin, forKey: "spin")
                }
                setUploadProgress(item.uploadProgress)
            }
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ItemView, _) in
                view.addBadge.layer.borderColor = UIColor.systemGroupedBackground.cgColor
            }
            isAccessibilityElement = true
            accessibilityLabel = item.title
            accessibilityTraits = .button
        }

        @available(*, unavailable) required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// StoryPeerListItemComponent: the 52 pt avatar 4 pt down, its ring around it, the name 2 pt under the ring.
        override func layoutSubviews() {
            super.layoutSubviews()
            ringView.frame = CGRect(x: (bounds.width - 60) / 2, y: 0, width: 60, height: 60)
            avatar.frame = CGRect(x: ringView.frame.minX + 4, y: 4, width: 52, height: 52)
            let height = ceil(titleLabel.font.lineHeight)
            titleLabel.frame = CGRect(x: -4, y: ringView.frame.maxY + 2, width: bounds.width + 8, height: height)
            uploadRing.frame = ringView.frame
            uploadRing.path = UIBezierPath(ovalIn: ringView.bounds.insetBy(dx: 1.2, dy: 1.2)).cgPath
            progressRing.frame = ringView.frame
            progressRing.path = uploadRing.path
            addBadge.frame = CGRect(x: ringView.frame.minX + 4 + 52 - 20 + 2, y: 4 + 52 - 20 + 2, width: 20, height: 20)
        }

        /// StoryProgressLayer.updateAnimations: the dashes give way to the arc once progress is known, and the arc
        /// eases to each new share over 0.3 s.
        func setUploadProgress(_ progress: Float?) {
            guard let progress else { return }
            // updateStoryUploadProgress keeps the arc between 0.027 and 0.99 until the post succeeds.
            let end = CGFloat(max(0.027, min(0.99, progress)))
            if progressRing.isHidden {
                progressRing.isHidden = false
                progressRing.strokeEnd = end
                uploadRing.isHidden = true
                return
            }
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = progressRing.presentation()?.strokeEnd ?? progressRing.strokeEnd
            animation.toValue = end
            animation.duration = 0.3
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            progressRing.strokeEnd = end
            progressRing.add(animation, forKey: "progress")
        }
    }

    static let height: CGFloat = 96

    var onSelect: ((Int64, UIView) -> Void)?
    /// storyContextPeerAction: a long press on an item.
    var onContextMenu: ((Int64, UIView, ContextMenuPressGestureRecognizer) -> Void)?
    private(set) var items = [Item]()

    private let scrollView = UIScrollView()
    private var itemViews = [ItemView]()

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        addSubview(scrollView)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The row's frame within the view, so its items rest 16 pt under the bar's bottom however much shows.
    override func layoutSubviews() {
        super.layoutSubviews()
        let rowFrame = CGRect(x: 0, y: bounds.height - Self.height, width: bounds.width, height: Self.height)
        scrollView.frame = rowFrame
        // StoryPeerListComponent.ItemLayout: 16 pt down and 4 pt short of the side inset.
        let leading = safeAreaInsets.left + 12
        for (index, view) in itemViews.enumerated() {
            view.frame = CGRect(x: leading + CGFloat(index) * (60 + 14), y: 16, width: 60, height: 77)
        }
        scrollView.contentSize = CGSize(
            width: leading + CGFloat(itemViews.count) * 74 - 14 + 12 + safeAreaInsets.right,
            height: Self.height,
        )
    }

    func update(items: [Item], client: TDLibClient, accountID: UUID?) {
        guard items != self.items else {
            self.items = items
            for (view, item) in zip(itemViews, items) where item.isUploading {
                view.setUploadProgress(item.uploadProgress)
            }
            return
        }
        self.items = items
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews = items.map { item in
            let view = ItemView(item: item, client: client, accountID: accountID)
            view.addAction(UIAction { [weak self, weak view] _ in
                guard let view else { return }
                self?.onSelect?(item.chatID, view.ringView)
            }, for: .touchUpInside)
            view.addGestureRecognizer(ContextMenuPressGestureRecognizer(
                target: self,
                action: #selector(itemLongPressed(_:)),
            ))
            scrollView.addSubview(view)
            return view
        }
        setNeedsLayout()
    }

    @objc private func itemLongPressed(_ gesture: ContextMenuPressGestureRecognizer) {
        guard gesture.state == .began, let view = gesture.view as? ItemView else { return }
        onContextMenu?(view.chatID, view, gesture)
    }
}
