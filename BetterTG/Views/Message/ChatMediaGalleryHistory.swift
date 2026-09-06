// ChatMediaGalleryHistory.swift

import TDLibKit
import UIKit

/// The pager spans chat history; album membership only controls the thumbnail strip.
@MainActor final class ChatMediaGalleryHistory {
    var onUpdate: (([Message]) -> Void)?
    var onFailure: (() -> Void)?

    private let client: TDLibClient
    private let location: ChatLocation
    private var messagesByID: [Int64: Message]
    private var deletedIDs = Set<Int64>()
    private var olderTask: Task<Void, Never>?
    private var newerTask: Task<Void, Never>?
    private var hasOlder = true
    private var hasNewer = true

    private var contextIsCurrent: Bool {
        TDLib.shared.activeAccountID == location.accountID && TDLib.shared.activeClient.id == location.clientID
    }

    init(client: TDLibClient, location: ChatLocation, messages: [Message]) {
        self.client = client
        self.location = location
        self.messagesByID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    deinit {
        olderTask?.cancel()
        newerTask?.cancel()
    }

    func removeMessages(chatID: Int64, ids: Set<Int64>) {
        guard chatID == location.chatID else { return }
        deletedIDs.formUnion(ids)
        for id in ids {
            messagesByID.removeValue(forKey: id)
        }
    }

    func loadOlder() { load(newer: false) }
    func loadNewer() { load(newer: true) }

    private func load(newer: Bool) {
        guard contextIsCurrent,
              newer ? hasNewer && newerTask == nil : hasOlder && olderTask == nil,
              let cursor = newer ? messagesByID.keys.max() : messagesByID.keys.min()
        else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if newer { newerTask = nil } else { olderTask = nil }
            }
            do {
                let result = try await client.searchChatMessages(
                    chatId: location.chatID,
                    filter: .searchMessagesFilterPhotoAndVideo,
                    fromMessageId: cursor,
                    limit: 50,
                    offset: newer ? -49 : 0,
                    query: "",
                    senderId: nil,
                    topicId: location.topic,
                )
                guard !Task.isCancelled, contextIsCurrent else { return }
                let expectedLocation = location
                let excludedIDs = deletedIDs
                let page = result.messages
                    .filter { expectedLocation.matches(message: $0) && !excludedIDs.contains($0.id) }
                let advanced = page.contains { newer ? $0.id > cursor : $0.id < cursor }
                if newer { hasNewer = advanced } else { hasOlder = advanced }
                for message in page {
                    messagesByID[message.id] = message
                }
                if advanced { onUpdate?(messagesByID.values.sorted { $0.id > $1.id }) }
            } catch {
                guard !Task.isCancelled, contextIsCurrent else { return }
                onFailure?()
            }
        }
        if newer { newerTask = task } else { olderTask = task }
    }
}
