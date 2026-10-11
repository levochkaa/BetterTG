// ForumTopicsSnapshotState.swift

import Foundation
import TDLibKit

/// Cell models belong to the diffable transaction, not the independently advancing VM.
/// Keep outgoing rows until UIKit finishes; coalesce only the next transaction.
struct ForumTopicsSnapshotState {
    struct Batch {
        let token = UUID()
        let ids: [Int]
        let models: [Int: ForumTopic]
        let clients: [Int: TDLibClient]
    }

    private(set) var displayedIDs = [Int]()

    private var models = [Int: ForumTopic]()
    private var clients = [Int: TDLibClient]()
    private var pending: (topics: [ForumTopic], client: TDLibClient?)?
    private var batch: Batch?
    private var retired = false

    var isApplying: Bool { batch != nil }
    var hasPending: Bool { pending != nil }
    var canSelect: Bool { !retired && !isApplying && !hasPending }

    func topic(id: Int) -> ForumTopic? { models[id] }
    func client(id: Int) -> TDLibClient? { clients[id] }

    mutating func enqueue(_ topics: [ForumTopic], client: TDLibClient? = nil) {
        guard !retired else { return }
        pending = (topics, client)
    }

    mutating func begin() -> Batch? {
        guard !retired, batch == nil, let pending else { return nil }
        self.pending = nil
        var ids = [Int]()
        var incoming = [Int: ForumTopic]()
        var incomingClients = [Int: TDLibClient]()
        for topic in pending.topics {
            let id = topic.info.forumTopicId
            if incoming.updateValue(topic, forKey: id) == nil { ids.append(id) }
            incomingClients[id] = pending.client
        }
        let next = Batch(ids: ids, models: incoming, clients: incomingClients)
        models.merge(incoming) { _, new in new }
        clients.merge(incomingClients) { _, new in new }
        batch = next
        return next
    }

    @discardableResult mutating func complete(_ token: UUID) -> Bool {
        guard !retired, let batch, batch.token == token else { return false }
        models = batch.models
        clients = batch.clients
        displayedIDs = batch.ids
        self.batch = nil
        return true
    }

    mutating func retire() {
        retired = true
        pending = nil
        batch = nil
        models.removeAll()
        clients.removeAll()
        displayedIDs.removeAll()
    }
}
