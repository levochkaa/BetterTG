// ForumTopicsReadEnvironment.swift

import Combine
import Foundation
import TDLibKitDynamic

/// Live defaults keep the captured client. Native probes inject only reads and
/// local update/source delivery; they never change global TDLib ownership.
@MainActor struct ForumTopicsReadEnvironment {
    let currentSource: () -> TdUpdateSource?
    let sourceChanges: AnyPublisher<TdUpdateSource, Never>
    let center: NotificationCenter
    let opensChat: Bool
    let page: (ChatLocation, ForumTopicPageCursor, String) async throws -> ForumTopics
    let topic: (ChatLocation, Int) async throws -> ForumTopic

    static func live(client: TDLibClient) -> Self {
        Self(
            currentSource: { TDLib.shared.activeUpdateSource }, sourceChanges: TDLib.shared.activeClientChanges,
            center: nc, opensChat: true,
            page: { location, cursor, query in
                try await client.getForumTopics(
                    chatId: location.chatID, limit: 50, offsetDate: cursor.date,
                    offsetForumTopicId: cursor.forumTopicID, offsetMessageId: cursor.messageID, query: query,
                )
            },
            topic: { try await client.getForumTopic(chatId: $0.chatID, forumTopicId: $1) },
        )
    }
}
