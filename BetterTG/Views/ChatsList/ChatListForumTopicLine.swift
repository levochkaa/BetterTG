// ChatListForumTopicLine.swift

import Combine
import TDLibKit
import UIKit

// MARK: - ChatListForumTopics

/// The forum topics chat list rows name (ChatListItem's `forumThread`): each topic's info from getForumTopic, kept per
/// client and refreshed by `updateForumTopicInfo`.
@MainActor final class ChatListForumTopics {
    private struct Key: Hashable {
        let clientID: Int32
        let chatID: Int64
        let topicID: Int
    }

    static let shared = ChatListForumTopics()

    /// The chat whose topic changed or arrived.
    let changes = PassthroughSubject<Int64, Never>()

    private var infos = [Key: ForumTopicInfo]()
    private var pending = Set<Key>()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        nc.scopedPublisher(&cancellables, for: .updateForumTopicInfo) { [weak self] event in
            let info = event.value.info
            let key = Key(clientID: event.source.clientID, chatID: info.chatId, topicID: info.forumTopicId)
            guard let self, infos[key] != nil else { return }
            infos[key] = info
            changes.send(info.chatId)
        }
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
            view.configure(sticker: sticker, client: client)
            view.setPlaybackVisible(window != nil)
        }
    }
}
