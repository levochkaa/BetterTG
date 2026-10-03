// ForumTopicsRestorationState.swift

import Foundation
import TDLibKitDynamic

// MARK: - ForumTopicPageRequest

struct ForumTopicPageRequest {
    let cursor: ForumTopicPageCursor
    let resets: Bool
}

// MARK: - ForumTopicsRestorationState

/// Values cross a same-account client epoch; request tasks, leases and UI ownership never do.
struct ForumTopicsRestorationState {
    let location: ChatLocation
    let query: String
    let topics: [ForumTopic]
    let pinnedTopicIDs: [Int]
    let cursor: ForumTopicPageCursor
    let completedCursors: Set<ForumTopicPageCursor>
    let hasMore: Bool
    let pendingReset: Bool?

    init(
        location: ChatLocation,
        rawQuery: String,
        modelQuery: String,
        acceptedQuery: String,
        topics: [ForumTopic],
        cursor: ForumTopicPageCursor,
        requestedCursors: Set<ForumTopicPageCursor>,
        hasMore: Bool,
        request: ForumTopicPageRequest?,
        pinnedTopicIDs: [Int] = [],
    ) {
        self.location = location
        self.query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsNewQuery = query != modelQuery || query != acceptedQuery
        self.topics = query == acceptedQuery ? topics : []
        self.pinnedTopicIDs = needsNewQuery ? [] : pinnedTopicIDs
        self.cursor = needsNewQuery ? .zero : cursor
        var completed = needsNewQuery ? [] : requestedCursors
        if let request { completed.remove(request.cursor) }
        self.completedCursors = completed
        self.hasMore = needsNewQuery ? true : hasMore
        self.pendingReset = needsNewQuery ? true : request?.resets ?? (topics.isEmpty ? true : nil)
    }

    func accepts(_ destination: ChatLocation) -> Bool {
        location.accountID != nil && location.accountID == destination.accountID
            && location.chatID == destination.chatID && location.topic == destination.topic
    }
}

// MARK: - ForumTopicTargetIntent

/// A canceled lookup remains pending. Only the owner that actually opened its target consumes it.
struct ForumTopicTargetIntent {
    private(set) var consumed: Bool

    private var attempt: UUID?

    init(consumed: Bool = false) { self.consumed = consumed }

    mutating func begin() -> UUID? {
        guard !consumed, attempt == nil else { return nil }
        let token = UUID()
        attempt = token
        return token
    }

    func owns(_ token: UUID) -> Bool { attempt == token && !consumed }

    mutating func finish(_ token: UUID, opened: Bool = false) {
        guard owns(token) else { return }
        attempt = nil
        consumed = opened
    }

    mutating func cancel() { attempt = nil }
}
