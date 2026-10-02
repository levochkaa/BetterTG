// PeerProfileRestoration.swift

import TDLibKitDynamic
import UIKit

// MARK: - PeerProfileRestorationState

/// Accepted display state only. Requests, permissions and media capabilities stay with their client.
struct PeerProfileRestorationState {
    let source: TdUpdateSource
    let actorID: Int64
    let chatID: Int64
    let topic: MessageTopic?
    let tab: PeerProfileViewController.SharedTab
    let messages: [Message]
    let cursor: Int64?
    let hasMore: Bool
    let total: Int?
    let error: String?
    let resumePage: Bool
    let bio: String
    let details: [String]
    let viewport: PeerProfileViewport

    var shouldResumePage: Bool { resumePage || messages.isEmpty && hasMore && error == nil }

    func matches(accountID: UUID, actorID: Int64?, chatID: Int64, topic: MessageTopic?) -> Bool {
        source.accountID == accountID && self.actorID == actorID && self.chatID == chatID && self.topic == topic
    }
}

// MARK: - PeerProfileViewport

struct PeerProfileViewport {
    let messageID: Int64?
    let minY: CGFloat
    let distanceFromTop: CGFloat

    @MainActor static func capture(
        _ collection: UICollectionView,
        messageID: (IndexPath) -> Int64?,
    ) -> Self {
        let first = collection.contentOffset.y >= 0
            ? collection.indexPathsForVisibleItems
                .compactMap { path -> (Int64, CGFloat)? in
                    guard let id = messageID(path), let attributes = collection.layoutAttributesForItem(at: path)
                    else { return nil }
                    return (id, attributes.frame.minY - collection.contentOffset.y)
                }
                .min { $0.1 == $1.1 ? $0.0 > $1.0 : $0.1 < $1.1 }
            : nil
        return Self(
            messageID: first?.0, minY: first?.1 ?? 0,
            distanceFromTop: collection.contentOffset.y + collection.contentInset.top,
        )
    }

    @MainActor func restore(_ collection: UICollectionView, indexPath: (Int64) -> IndexPath?) -> Bool {
        guard collection.bounds.height > 0, !collection.isDragging, !collection.isDecelerating else { return false }
        collection.layoutIfNeeded()
        let offset = messageID.flatMap(indexPath)
            .flatMap { collection.layoutAttributesForItem(at: $0) }
            .map { $0.frame.minY - minY } ?? distanceFromTop - collection.contentInset.top
        let minimum = -collection.contentInset.top
        let maximum = max(
            minimum,
            collection.contentSize.height - collection.bounds.height + collection.contentInset.bottom,
        )
        collection.setContentOffset(
            CGPoint(x: collection.contentOffset.x, y: min(maximum, max(minimum, offset))),
            animated: false,
        )
        return true
    }
}

// MARK: - PeerProfileRestorationIdentity

struct PeerProfileRestorationIdentity {
    let origin: TdUpdateSource
    let actorID: Int64?
    var readySource: TdUpdateSource?
    private(set) var revoked = false

    mutating func observe(source: TdUpdateSource?, actorID: Int64?) {
        if source?.accountID != origin.accountID || (actorID != nil && actorID != self.actorID) { revoked = true }
    }

    func accepts(_ source: TdUpdateSource, current: TdUpdateSource?, actorID: Int64?) -> Bool {
        !revoked && self.actorID != nil && self.actorID == actorID && source == current && source == readySource
            && source.accountID == origin.accountID && source.clientID != origin.clientID
    }
}

// MARK: - PeerProfileMetadataPreparation

/// Keeps an uncancellable old metadata RPC from publishing into a replacement attempt.
@MainActor final class PeerProfileMetadataPreparation {
    private(set) var source: TdUpdateSource?

    private var token: UUID?
    private var task: Task<Void, Never>?

    deinit { task?.cancel() }

    func request(
        source: TdUpdateSource, fetch: @escaping () async -> CustomChat?,
        accepts: @escaping () -> Bool, completion: @escaping (CustomChat?) -> Void,
    ) {
        guard self.source != source else { return }
        cancel()
        let token = UUID()
        self.source = source
        self.token = token
        task = Task { [weak self] in
            guard self?.token == token, !Task.isCancelled, accepts() else {
                if self?.token == token { self?.cancel() }
                return
            }
            let chat = await fetch()
            guard let self, self.token == token else { return }
            self.token = nil
            self.source = nil
            task = nil
            guard !Task.isCancelled, accepts() else { return }
            completion(chat)
        }
    }

    func cancel() {
        token = nil
        source = nil
        task?.cancel()
        task = nil
    }
}
