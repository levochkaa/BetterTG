// PeerProfileRestorationProbe.swift

#if DEBUG
import TDLibKitDynamic
import UIKit

@MainActor enum PeerProfileRestorationProbe {
    private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

    @MainActor private final class Rows: NSObject, UICollectionViewDataSource {
        var ids = Array(Int64(1)...90)

        func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int { ids.count }
        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath,
        ) -> UICollectionViewCell {
            collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        }

        func path(_ id: Int64) -> IndexPath? { ids.firstIndex(of: id).map { IndexPath(item: $0, section: 0) } }
    }

    @MainActor private final class Collection: UICollectionView {
        override var isDragging: Bool { simulatedDragging }

        var simulatedDragging = false
    }

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-profile-restoration") else { return }
        let result: String
        do {
            try verifySeed()
            try verifyViewport()
            result = "Profile restoration prerequisite probe passed: production-seed/tab/page/cursor/metadata=true; "
                + "account/actor/chat/topic-isolation=true; stale-history-token-fenced=true; "
                + "actual-UICollectionView/stable-message/header-resize/prepend/empty/drag/layout=true; "
                + "controller-activation/factory-callbacks/TDLib/foreground=unverified; server-reads/writes=0"
        } catch {
            result = "Profile restoration prerequisite probe failed: \(error)"
        }
        log(result)
        if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? Data(result.utf8).write(
                to: directory.appendingPathComponent("profile-restoration-probe.txt"),
                options: .atomic,
            )
        }
    }

    private static func require(_ value: Bool, _ reason: String) throws {
        if !value { throw Failure(description: reason) }
    }

    private static func verifySeed() throws {
        let source = TdUpdateSource(accountID: UUID(), clientID: 71)
        let forum = MessageTopic.messageTopicForum(.init(forumTopicId: 42))
        for topic in [nil, forum] {
            for tab in PeerProfileViewController.SharedTab.allCases {
                var request = PeerProfileHistoryRequest()
                let old = request.begin()
                let seed = PeerProfileRestorationState(
                    source: source, actorID: 77, chatID: 8, topic: topic, tab: tab,
                    messages: [message(id: 90), message(id: 70)], cursor: 61, hasMore: true,
                    total: 200, error: "prior retry", resumePage: request.currentID != nil,
                    bio: "accepted bio", details: ["accepted username"],
                    viewport: .init(messageID: 70, minY: -12, distanceFromTop: 600),
                )
                request.invalidate()
                let current = request.begin()
                try require(!request.finish(old) && request.currentID == current, "retired page consumed retry")
                try require(
                    seed.matches(accountID: source.accountID, actorID: 77, chatID: 8, topic: topic)
                        && seed.messages.map(\.id) == [90, 70] && seed.cursor == 61 && seed.resumePage
                        && seed.hasMore && seed.total == 200 && seed.tab == tab && seed.error == "prior retry"
                        && seed.bio == "accepted bio" && seed.details == ["accepted username"],
                    "accepted display/cursor replaced by pending page",
                )
                try require(
                    !seed.matches(accountID: UUID(), actorID: 77, chatID: 8, topic: topic)
                        && !seed.matches(accountID: source.accountID, actorID: 78, chatID: 8, topic: topic)
                        && !seed.matches(accountID: source.accountID, actorID: nil, chatID: 8, topic: topic)
                        && !seed.matches(accountID: source.accountID, actorID: 77, chatID: 9, topic: topic)
                        && !seed.matches(
                            accountID: source.accountID,
                            actorID: 77,
                            chatID: 8,
                            topic: topic == nil
                            ? forum
                            : nil,
                        ),
                    "foreign seed admitted",
                )
            }
        }
    }

    private static func verifyViewport() throws {
        let rows = Rows()
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 100, height: 100)
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        let collection = Collection(frame: CGRect(x: 0, y: 0, width: 300, height: 420), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.dataSource = rows
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        collection.contentInset.top = 260
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 412
        collection.layoutIfNeeded()
        let saved = PeerProfileViewport.capture(collection, messageID: { rows.ids[$0.item] })
        guard let id = saved.messageID else { throw Failure(description: "missing actual grid anchor") }
        rows.ids.insert(contentsOf: [100, 101, 102], at: 0)
        collection.contentInset.top = 390
        collection.reloadData()
        try require(saved.restore(collection, indexPath: rows.path), "restore rejected laid-out grid")
        guard let path = rows.path(id), let attributes = collection.layoutAttributesForItem(at: path)
        else { throw Failure(description: "missing restored attributes") }
        try require(
            abs(attributes.frame.minY - collection.contentOffset.y - saved.minY) < 0.5,
            "prepend/header moved message pixels",
        )
        collection.simulatedDragging = true
        try require(!saved.restore(collection, indexPath: rows.path), "restore overrode active drag")
        collection.simulatedDragging = false
        collection.bounds.size.height = 0
        try require(!saved.restore(collection, indexPath: rows.path), "unlaid-out view consumed anchor")
        collection.bounds.size.height = 420
        collection.contentOffset.y = -300
        let header = PeerProfileViewport.capture(collection, messageID: { rows.ids[$0.item] })
        try require(header.messageID == nil && header.distanceFromTop == 90, "header offset classified as grid")
        collection.contentInset.top = 440
        try require(
            header.restore(collection, indexPath: rows.path) && collection.contentOffset.y == -350,
            "header resize lost top distance",
        )
        rows.ids = []
        collection.reloadData()
        try require(
            saved.restore(collection, indexPath: rows.path) && collection.contentOffset.y == -420,
            "removed anchor escaped empty bounds",
        )
    }

    private static func message(id: Int64) -> Message {
        Message(
            authorSignature: "", autoDeleteIn: 0, canBeSaved: true, chatId: 8,
            containsUnreadMention: false, containsUnreadPollVotes: false,
            content: .messageText(.init(
                linkPreview: nil,
                linkPreviewOptions: nil,
                text: .init(entities: [], text: "accepted"),
            )),
            date: Int(id), editDate: 0, effectId: 0, ephemeralMessageId: 0, factCheck: nil, forwardInfo: nil,
            guestBotCallerId: nil, hasTimestampedMedia: false, id: id, importInfo: nil, interactionInfo: nil,
            isChannelPost: false, isFromOffline: false, isOutgoing: false, isPaidGramSuggestedPost: false,
            isPaidStarSuggestedPost: false, isPinned: false, mediaAlbumId: 0, paidMessageStarCount: 0,
            receiverId: nil, replyMarkup: nil, replyTo: nil, restrictionInfo: nil, schedulingState: nil,
            selfDestructIn: 0, selfDestructType: nil, senderBoostCount: 0, senderBusinessBotUserId: 0,
            senderId: .messageSenderUser(.init(userId: 1)), senderTag: "", sendingState: nil,
            suggestedPostInfo: nil, summaryLanguageCode: "", topicId: nil, unreadReactions: [], viaBotUserId: 0,
        )
    }
}
#endif
