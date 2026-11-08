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
