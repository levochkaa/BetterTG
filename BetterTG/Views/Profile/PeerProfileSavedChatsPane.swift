// PeerProfileSavedChatsPane.swift

import Combine
import TDLibKit
import UIKit

// MARK: - SavedMessagesViewMode

/// Telegram's displaySavedChatsAsTopics, kept on the device for each account: Saved Messages opens as its chats (the
/// profile's Chats pane) or as one chat of messages, which is the default.
enum SavedMessagesViewMode {
    static func viewsAsChats(accountID: UUID?) -> Bool {
        guard let accountID else { return false }
        return UserDefaults.standard.bool(forKey: key(accountID))
    }

    static func setViewsAsChats(_ value: Bool, accountID: UUID?) {
        guard let accountID else { return }
        UserDefaults.standard.set(value, forKey: key(accountID))
    }

    private static func key(_ accountID: UUID) -> String {
        "savedMessagesViewsAsChats.\(accountID.uuidString)"
    }
}

extension SavedMessagesViewMode {
    /// PeerInfoScreenImpl.openSavedMessagesMoreMenu: View as Chats and View as Messages, the current one checked.
    static func menuActions(
        viewsAsChats: Bool,
        viewAsChats: @escaping () -> Void,
        viewAsMessages: @escaping () -> Void,
    ) -> [TelegramContextMenuAction] {
        [
            TelegramContextMenuAction(
                title: L10n.telegram("Chat.SavedMessagesModeMenu.ViewAsChats"),
                image: viewsAsChats ? UIImage(systemName: "checkmark") : UIImage(),
                handler: viewAsChats,
            ),
            TelegramContextMenuAction(
                title: L10n.telegram("Chat.SavedMessagesModeMenu.ViewAsMessages"),
                image: viewsAsChats ? UIImage() : UIImage(systemName: "checkmark"),
                handler: viewAsMessages,
            ),
        ]
    }

    /// Whether Saved Messages has chats to view: sublists from other chats, or the mode already on.
    @MainActor static func hasChats(accountID: UUID?, client: TDLibClient) -> Bool {
        viewsAsChats(accountID: accountID)
            || TelegramChatListStore.shared.savedMessagesTopicList(clientID: client.id).contains {
                if case .savedMessagesTopicTypeMyNotes = $0.type {
                    false
                } else {
                    true
                }
            }
    }
}

extension PeerProfileViewController {
    /// Saved Messages viewed as chats (NavigateToChatController's makePeerInfoController for the account's own chat):
    /// the profile on its own, opening the chat for a message or a search.
    static func savedMessagesChats(
        customChat: CustomChat,
        client: TDLibClient,
        accountID: UUID,
    ) -> PeerProfileViewController {
        let profile = PeerProfileViewController(
            customChat: customChat,
            topic: nil,
            client: client,
            accountID: accountID,
        )
        profile.onOpenMessage = { [weak profile] messageID in
            profile?.navigationController?.pushViewController(
                ChatViewController(customChat: customChat, targetMessageID: messageID),
                animated: true,
            )
        }
        profile.onSearch = { [weak profile] in
            profile?.navigationController?.pushViewController(
                ChatViewController(customChat: customChat),
                animated: true,
            )
        }
        return profile
    }
}

// MARK: - PeerProfileSavedChatsPane

/// PeerInfoChatListPaneNode on the Saved Messages profile: the sublists of Saved Messages as chat list rows, one for
/// each chat messages were saved from, My Notes and Author Hidden, pinned ones first in TDLib's order. TDLib sends the
/// sublists only as updateSavedMessagesTopic, a page at a time as loadSavedMessagesTopics asks; the store keeps them.
/// A row opens its sublist, and its menu pins it or deletes its messages.
@MainActor final class PeerProfileSavedChatsPane {
    var onChange: (() -> Void)?

    private(set) var items = [Int64]()
    private(set) var isComplete = false
    /// The first page has been asked for and answered.
    private(set) var hasLoaded = false
    /// The My Notes sublist, which alone doesn't make Saved Messages list its chats.
    private(set) var myNotesItem: Int64?

    private var rows = [Int64: CustomChat]()
    private let savedMessages: CustomChat
    private let client: TDLibClient
    private var loadTask: Task<Void, Never>?
    private var cancellable: AnyCancellable?

    var isLoading: Bool {
        loadTask != nil
    }

    init(savedMessages: CustomChat, client: TDLibClient) {
        self.savedMessages = savedMessages
        self.client = client
        self.cancellable = TelegramChatListStore.shared
            .savedMessagesTopicChanges
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    func chat(for item: Int64) -> CustomChat? {
        rows[item]
    }

    func loadMore() {
        guard !isComplete, loadTask == nil else { return }
        let client = client
        loadTask = Task { [weak self] in
            var complete = false
            do {
                _ = try await client.send(TDNativeRequests.loadSavedMessagesTopics(limit: 50))
            } catch {
                // TDLib answers 404 once every sublist has been sent.
                complete = true
            }
            guard let self else { return }
            loadTask = nil
            hasLoaded = true
            if complete { isComplete = true }
            refresh()
        }
    }

    func suspend() {
        loadTask?.cancel()
        loadTask = nil
    }

    /// The sublist's chat: ChatController on Saved Messages' `.replyThread`.
    func open(_ item: Int64) {
        NavigationStorage.shared.push(.customChat(savedMessages, location: location(of: item)))
    }

    /// The sublist as the menu's chat preview.
    func previewController(for item: Int64) -> ChatViewController {
        ChatViewController(customChat: savedMessages, location: location(of: item), presentationMode: .contextPreview)
    }

    /// chatContextMenuItems for a Saved Messages chat: Pin or Unpin, and Delete.
    func menuActions(for item: Int64, host: UIViewController) -> [TelegramContextMenuAction] {
        guard let topic = TelegramChatListStore.shared.savedMessagesTopic(item, clientID: client.id) else { return [] }
        let client = client
        let isPinned = topic.isPinned
        return [
            TelegramContextMenuAction(
                title: L10n.telegram(isPinned ? "ChatList.Context.Unpin" : "ChatList.Context.Pin"),
                image: UIImage(systemName: isPinned ? "pin.slash" : "pin"),
            ) {
                Task {
                    _ = try? await client.send(TDNativeRequests.toggleSavedMessagesTopicIsPinned(
                        savedMessagesTopicId: item,
                        isPinned: !isPinned,
                    ))
                }
            },
            TelegramContextMenuAction(
                title: L10n.telegram("ChatList.Context.Delete"),
                image: UIImage(systemName: "trash"),
                isDestructive: true,
            ) { [weak self, weak host] in
                guard let self, let host else { return }
                confirmDelete(topic, host: host)
            },
        ]
    }

    private func location(of item: Int64) -> ChatLocation {
        ChatLocation.current(
            chatID: savedMessages.id,
            topic: .messageTopicSavedMessages(MessageTopicSavedMessages(savedMessagesTopicId: item)),
            client: client,
        )
    }

    /// DeleteChatPeerActionSheetItem's question for a Saved Messages chat, then deleteSavedMessagesTopicHistory.
    private func confirmDelete(_ topic: SavedMessagesTopic, host: UIViewController) {
        let text =
            if case .savedMessagesTopicTypeMyNotes = topic.type {
                L10n.telegram(
                    "ChatList.DeleteSavedPeerMyNotesConfirmation",
                    L10n.telegram("ChatList.DeleteSavedPeerMyNotesConfirmationTitle"),
                )
            } else {
                L10n.telegram("ChatList.DeleteSavedPeerConfirmation", rows[topic.id]?.displayTitle ?? "")
            }
        let sheet = UIAlertController(title: nil, message: text, preferredStyle: .actionSheet)
        let client = client
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Delete"), style: .destructive) { _ in
            Task {
                _ = try? await client.send(TDNativeRequests.deleteSavedMessagesTopicHistory(
                    savedMessagesTopicId: topic.id,
                ))
            }
        })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        host.present(sheet, animated: true)
    }

    private func refresh() {
        let topics = TelegramChatListStore.shared.savedMessagesTopicList(clientID: client.id)
        var updated = [Int64: CustomChat]()
        var ids = [Int64]()
        for topic in topics {
            guard let row = row(for: topic) else { continue }
            updated[topic.id] = row
            ids.append(topic.id)
        }
        rows = updated
        items = ids
        myNotesItem = topics.first {
            if case .savedMessagesTopicTypeMyNotes = $0.type {
                true
            } else {
                false
            }
        }?.id
        onChange?()
    }

    /// The sublist as a chat list row: its chat's name and photo, or the account's own chat titled and drawn as My
    /// Notes or Author Hidden, with the sublist's last message and draft.
    private func row(for topic: SavedMessagesTopic) -> CustomChat? {
        let position = ChatPosition(isPinned: topic.isPinned, list: .chatListMain, order: topic.order, source: nil)
        let chat: Chat
        let type: CustomChat.CustomChatType
        var titleOverride: String?
        var iconOverride: TelegramAvatarIcon?
        switch topic.type {
        case .savedMessagesTopicTypeMyNotes:
            (chat, type) = (savedMessages.chat, savedMessages.type)
            titleOverride = L10n.telegram("DialogList.MyNotes")
            iconOverride = .myNotes
        case .savedMessagesTopicTypeAuthorHidden:
            (chat, type) = (savedMessages.chat, savedMessages.type)
            titleOverride = L10n.telegram("ChatList.AuthorHidden")
            iconOverride = .anonymousSavedMessages
        case .savedMessagesTopicTypeSavedFromChat(let from):
            let store = TelegramChatListStore.shared
            guard let source = store.chat(id: from.chatId, clientID: client.id),
                  let sourceType = store.peerType(chatID: from.chatId)
            else { return nil }
            (chat, type) = (source, sourceType)
        }
        let row = CustomChat(
            chat: chat,
            position: position,
            unreadCount: 0,
            type: type,
            lastMessage: topic.lastMessage,
            draftMessage: topic.draftMessage,
        )
        row.titleOverride = titleOverride
        row.avatarIconOverride = iconOverride
        row.isSavedMessagesSublist = true
        return row
    }
}

// MARK: - SavedChatRowCell

/// The Chats pane's row: the chat list's own row in a collection view cell.
final class SavedChatRowCell: UICollectionViewCell {
    static let reuseIdentifier = "SavedChatRowCell"

    override var isHighlighted: Bool {
        didSet { row.setHighlighted(isHighlighted, animated: !isHighlighted) }
    }

    private let row = ChatListCell(style: .default, reuseIdentifier: nil)

    override init(frame: CGRect) {
        super.init(frame: frame)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isUserInteractionEnabled = false
        row.showsReorderControl = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            row.topAnchor.constraint(equalTo: contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            row.heightAnchor.constraint(equalToConstant: ChatListCell.cardRowHeight),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        row.prepareForReuse()
    }

    func configure(chat: CustomChat, client: TDLibClient) {
        row.configure(chat: chat, isMuted: false, showsAvatarBadges: false, client: client)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = row.accessibilityLabel
    }
}
