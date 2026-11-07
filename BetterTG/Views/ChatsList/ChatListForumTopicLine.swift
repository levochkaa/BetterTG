// ChatListForumTopicLine.swift

import Combine
import TDLibKit
import UIKit

// MARK: - ChatListForumTopics

/// The forum topics chat list rows name (ChatListItem's `forumThread`): each topic's info from getForumTopic, kept per
/// client and refreshed by `updateForumTopicInfo`.
@MainActor final class ChatListForumTopics {
    /// What the recent topics were read for: a new last message or a changed unread count reads them again.
    struct Revision: Equatable {
        let lastMessageID: Int64
        let unreadCount: Int
    }

    /// One of a forum's recent topics (Postbox's ChatListForumTopicData): the topic as getForumTopics read it, with
    /// the info `updateForumTopicInfo` keeps current.
    struct RecentTopic {
        let topic: ForumTopic
        var info: ForumTopicInfo

        var id: Int { info.forumTopicId }
        /// ForumTopicData's isUnread: incoming messages are unread in the topic.
        var isUnread: Bool { topic.unreadCount > 0 }
    }

    private struct Key: Hashable {
        let clientID: Int32
        let chatID: Int64
        let topicID: Int
    }

    private struct ChatKey: Hashable {
        let clientID: Int32
        let chatID: Int64
    }

    static let shared = ChatListForumTopics()

    /// ChatListView's topForumTopics: the five topics with the latest messages.
    static let recentLimit = 5

    /// The chat whose topic changed or arrived.
    let changes = PassthroughSubject<Int64, Never>()

    private var infos = [Key: ForumTopicInfo]()
    private var pending = Set<Key>()
    private var recent = [ChatKey: (revision: Revision, topics: [RecentTopic])]()
    private var recentPending = [ChatKey: Revision]()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        nc.scopedPublisher(&cancellables, for: .updateForumTopicInfo) { [weak self] event in
            let info = event.value.info
            let key = Key(clientID: event.source.clientID, chatID: info.chatId, topicID: info.forumTopicId)
            let chatKey = ChatKey(clientID: event.source.clientID, chatID: info.chatId)
            guard let self else { return }
            let index = recent[chatKey]?.topics.firstIndex { $0.id == info.forumTopicId }
            guard infos[key] != nil || index != nil else { return }
            if infos[key] != nil { infos[key] = info }
            if let index { recent[chatKey]?.topics[index].info = info }
            changes.send(info.chatId)
        }
    }

    /// The forum's recent topics, newest first, as last read; a revision they weren't read for reads them again and
    /// `changes` reports the chat once they arrive.
    func recentTopics(chatID: Int64, revision: Revision, client: TDLibClient) -> [RecentTopic] {
        let key = ChatKey(clientID: client.id, chatID: chatID)
        let cached = recent[key]
        if cached?.revision != revision, recentPending[key] != revision {
            recentPending[key] = revision
            Task { [weak self] in
                // Pinned topics come first in getForumTopics; Postbox orders the index by the last message alone.
                let page = try? await client.getForumTopics(
                    chatId: chatID,
                    limit: 20,
                    offsetDate: 0,
                    offsetForumTopicId: 0,
                    offsetMessageId: 0,
                    query: "",
                )
                guard let self, recentPending[key] == revision else { return }
                recentPending[key] = nil
                guard let page else { return }
                let topics = page.topics
                    .sorted {
                        ($0.lastMessage?.date ?? $0.info.creationDate) > ($1.lastMessage?.date ?? $1.info.creationDate)
                    }
                    .prefix(Self.recentLimit)
                    .map { RecentTopic(topic: $0, info: $0.info) }
                recent[key] = (revision, topics)
                changes.send(chatID)
            }
        }
        return cached?.topics ?? []
    }

    /// A recent topic of the forum, as the chat list last read it.
    func recentTopic(chatID: Int64, topicID: Int, client: TDLibClient) -> ForumTopic? {
        recent[ChatKey(clientID: client.id, chatID: chatID)]?.topics.first { $0.id == topicID }?.topic
    }

    /// The topic's info if known; otherwise it is requested and `changes` reports the chat once it arrives.
    func info(chatID: Int64, topicID: Int, client: TDLibClient) -> ForumTopicInfo? {
        let key = Key(clientID: client.id, chatID: chatID, topicID: topicID)
        if let info = infos[key] { return info }
        guard pending.insert(key).inserted else { return nil }
        Task { [weak self] in
            let topic = try? await client.getForumTopic(chatId: chatID, forumTopicId: topicID)
            guard let self else { return }
            pending.remove(key)
            guard let topic else { return }
            infos[key] = topic.info
            changes.send(chatID)
        }
        return nil
    }
}

// MARK: - ChatListTopicIconView

/// The topic's 16 pt icon before its name in a chat list row: its custom emoji, a circle in the topic's colour with
/// its first letter, or General's grey "#".
final class ChatListTopicIconView: UIView {
    private let circle = UILabel()
    private var emojiView: CustomEmojiInlineView?
    private var representedEmojiID: Int64 = 0
    private var loadTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        circle.translatesAutoresizingMaskIntoConstraints = false
        circle.font = .systemFont(ofSize: 9, weight: .bold)
        circle.textColor = .white
        circle.textAlignment = .center
        circle.layer.cornerRadius = 7
        circle.clipsToBounds = true
        addSubview(circle)
        NSLayoutConstraint.activate([
            circle.centerXAnchor.constraint(equalTo: centerXAnchor),
            circle.centerYAnchor.constraint(equalTo: centerYAnchor),
            circle.widthAnchor.constraint(equalToConstant: 14),
            circle.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        emojiView?.setPlaybackVisible(window != nil)
    }

    func configure(info: ForumTopicInfo, client: TDLibClient) {
        // generalForumTopicIcon: General's plain grey hash.
        circle.backgroundColor = info.isGeneral ? .clear : UIColor(rgb: info.icon.color)
        circle.textColor = info.isGeneral ? .secondaryLabel : .white
        circle.font = .systemFont(ofSize: info.isGeneral ? 14 : 9, weight: .bold)
        circle.text = info.isGeneral ? "#" : info.name.first.map { String($0).uppercased() }
        let emojiID = info.icon.customEmojiId
        guard emojiID != representedEmojiID else { return }
        representedEmojiID = emojiID
        loadTask?.cancel()
        emojiView?.prepareForReuse()
        emojiView?.removeFromSuperview()
        emojiView = nil
        circle.isHidden = false
        guard emojiID != 0 else { return }
        loadTask = Task { [weak self] in
            let sticker = await CustomEmojiStickerRepository.shared.stickers(for: [emojiID], client: client)[emojiID]
            guard !Task.isCancelled, let self, representedEmojiID == emojiID, let sticker else { return }
            let view = CustomEmojiInlineView()
            view.energySaving = EnergySavingRole(item: .loopEmoji, whenOff: .still)
            view.isUserInteractionEnabled = false
            view.frame = bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(view)
            emojiView = view
            view.onFirstFrameReady = { [weak self, weak view] in
                guard let self, emojiView === view else { return }
                circle.isHidden = true
            }
            // ChatListItem's topic icon themeColor: a template emoji takes the accent colour.
            view.templateColor = .systemBlue
            view.repaintsAccentPacks = true
            view.configure(sticker: sticker, client: client)
            view.setPlaybackVisible(window != nil)
        }
    }
}

// MARK: - ChatListForumTopicsLineView

/// ChatListItem's AuthorNode for a forum: the last message's topic, then the other recent topics
/// (topForumTopicItems), each its icon and name, as many as fit on the line.
final class ChatListForumTopicsLineView: UIView {
    struct Entry {
        let info: ForumTopicInfo
        let isUnread: Bool
    }

    private static let iconSize = CGFloat(16)
    private static let iconSpacing = CGFloat(4)
    /// TopicItemNode's 4 pt between topics, beside the title's 1 pt insets.
    private static let topicSpacing = CGFloat(5)

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: ceil(font.lineHeight))
    }

    /// The first topic's frame, which a selectable unread topic's highlight wraps.
    private(set) var firstItemFrame: CGRect?

    private var items = [(icon: ChatListTopicIconView, label: UILabel)]()
    private var entries = [Entry]()
    private var font = UIFont.preferredFont(forTextStyle: .subheadline)

    #if DEBUG
        var probeEntryCount: Int { entries.count }
        var probeShownCount: Int { items.count { !$0.label.isHidden && $0.label.frame.width > 0 } }
    #endif

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        firstItemFrame = nil
        var x = CGFloat.zero
        let height = bounds.height
        for (index, item) in items.enumerated() {
            let remaining = bounds.width - x
            // TopicItemNode's layout stops once a topic can't show its icon and a few points of its name.
            guard index < entries.count, remaining > Self.iconSize + Self.iconSpacing + 10 else {
                item.icon.isHidden = true
                item.label.isHidden = true
                continue
            }
            item.icon.isHidden = false
            item.label.isHidden = false
            let available = remaining - Self.iconSize - Self.iconSpacing
            let labelWidth = min(
                ceil(item.label.sizeThatFits(CGSize(width: available, height: height)).width),
                available,
            )
            item.icon.frame = CGRect(
                x: x,
                y: ((height - Self.iconSize) / 2).rounded(),
                width: Self.iconSize,
                height: Self.iconSize,
            )
            item.label.frame = CGRect(x: x + Self.iconSize + Self.iconSpacing, y: 0, width: labelWidth, height: height)
            let width = Self.iconSize + Self.iconSpacing + labelWidth
            if index == 0 { firstItemFrame = CGRect(x: x, y: 0, width: width, height: height) }
            x += width + Self.topicSpacing
        }
    }

    func configure(_ entries: [Entry], font: UIFont, client: TDLibClient) {
        if font != self.font {
            self.font = font
            invalidateIntrinsicContentSize()
        }
        self.entries = entries
        while items.count < entries.count {
            let icon = ChatListTopicIconView()
            let label = UILabel()
            label.lineBreakMode = .byTruncatingTail
            addSubview(icon)
            addSubview(label)
            items.append((icon, label))
        }
        for (index, item) in items.enumerated() {
            guard let entry = entries[safe: index] else {
                item.icon.isHidden = true
                item.label.isHidden = true
                continue
            }
            item.icon.configure(info: entry.info, client: client)
            item.label.text = entry.info.name
            item.label.font = font
            // ChatListItem: an unread topic's name in the author colour, a read one's in the text colour.
            item.label.textColor = entry.isUnread ? .label : .secondaryLabel
        }
        setNeedsLayout()
    }

    /// The first topic dims with its highlight while the finger holds it (AuthorNode.setFirstTopicHighlighted).
    func setFirstItemAlpha(_ alpha: CGFloat) {
        guard let first = items.first else { return }
        first.icon.alpha = alpha
        first.label.alpha = alpha
    }
}

// MARK: - ChatListTopicHighlightShape

/// ChatListItem's compound highlight (LinkHighlightingNode with useModernPathCalculation): the first topic's rect over
/// the text's rect, meeting halfway between them, convex corners at the outer radius and concave ones at the inner.
enum ChatListTopicHighlightShape {
    static func path(top: CGRect, bottom: CGRect, outerRadius: CGFloat, innerRadius: CGFloat) -> CGPath {
        let midY = top.maxY
        var vertices = [(point: CGPoint, radius: CGFloat)]()
        vertices.append((CGPoint(x: top.minX, y: top.minY), outerRadius))
        vertices.append((CGPoint(x: top.maxX, y: top.minY), outerRadius))
        if abs(bottom.maxX - top.maxX) < 0.5 {
            vertices.append((CGPoint(x: top.maxX, y: bottom.maxY), outerRadius))
        } else {
            let bottomIsWider = bottom.maxX > top.maxX
            vertices.append((CGPoint(x: top.maxX, y: midY), bottomIsWider ? innerRadius : outerRadius))
            vertices.append((CGPoint(x: bottom.maxX, y: midY), bottomIsWider ? outerRadius : innerRadius))
            vertices.append((CGPoint(x: bottom.maxX, y: bottom.maxY), outerRadius))
        }
        vertices.append((CGPoint(x: bottom.minX, y: bottom.maxY), outerRadius))
        let path = CGMutablePath()
        let count = vertices.count
        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        let last = vertices[count - 1].point
        let first = vertices[0].point
        path.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for index in 0..<count {
            let previous = vertices[(index + count - 1) % count].point
            let vertex = vertices[index]
            let next = vertices[(index + 1) % count].point
            // Each corner takes at most half of either edge it joins.
            let radius = min(vertex.radius, distance(previous, vertex.point) / 2, distance(vertex.point, next) / 2)
            path.addArc(tangent1End: vertex.point, tangent2End: next, radius: max(radius, 0))
        }
        path.closeSubpath()
        return path
    }
}
