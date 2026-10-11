// PeerProfileSharedMessageRefresh.swift

import TDLibKit
import UIKit

// MARK: - PeerProfileSharedMessageRefresh

/// Seed values retain geometry, never fresh media or action authority.
@MainActor final class PeerProfileSharedMessageRefresh {
    enum State { case loading, retry, ready }
    enum Change { case quarantine(Set<Int64>), message(Message), remove(Int64), retry(Int64) }
    struct PageAdmission {
        let accepted: [Message]
        let quarantined: [Message]

        func install(into values: inout [Int64: Message]) {
            for message in quarantined where values[message.id] == nil {
                values[message.id] = message
            }
            for message in accepted {
                values[message.id] = message
            }
        }
    }

    let source: TdUpdateSource
    let location: ChatLocation
    let tab: PeerProfileViewController.SharedTab
    var onChange: ((Change) -> Void)?

    private let accepts: () -> Bool
    private let canStart: () -> Bool
    private let read: (Int64) async throws -> Message
    private let seeds: [Int64]
    private let visibleIDs: [Int64]
    private var knownIDs: Set<Int64>
    private var readyIDs = Set<Int64>()
    private var retryIDs = Set<Int64>()
    private var removedIDs = Set<Int64>()
    private var pageIsPending = false
    private var stopped = false
    private var task: Task<Void, Never>?
    private lazy var ledger = ChatHistoryRestorationRefresh(
        location: location, source: source, seedIDs: seeds, visibleIDs: visibleIDs,
        currentSource: { [weak self] in self?.isCurrent == true ? self?.source : nil },
        read: read, retriesPartialRaces: true,
        deliver: { [weak self] in self?.receive($0) },
    )

    #if DEBUG
        var debugRefreshTask: Task<Void, Never>? { task }
    #endif
    var canRead: Bool { !stopped && accepts() }

    private var isCurrent: Bool { canRead }

    init(
        source: TdUpdateSource, location: ChatLocation, tab: PeerProfileViewController.SharedTab,
        seedIDs: [Int64], visibleIDs: [Int64], accepts: @escaping () -> Bool,
        canStart: @escaping () -> Bool = { true },
        read: @escaping (Int64) async throws -> Message,
    ) {
        self.source = source
        self.location = location
        self.tab = tab
        self.seeds = seedIDs
        self.visibleIDs = visibleIDs
        self.knownIDs = Set(seedIDs)
        self.accepts = accepts
        self.canStart = canStart
        self.read = read
    }

    deinit { task?.cancel() }

    func state(for id: Int64) -> State {
        guard isCurrent else { return .loading }
        return readyIDs.contains(id) ? .ready : retryIDs.contains(id) ? .retry : .loading
    }

    func allows(_ id: Int64) -> Bool { state(for: id) == .ready }

    @discardableResult func perform(id: Int64, _ action: () -> Void) -> Bool {
        guard allows(id) else { return false }
        action()
        return true
    }

    func start() {
        guard isCurrent, canStart(), task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            while isCurrent, !Task.isCancelled, await ledger.refreshNextBatch() {}
            task = nil
        }
    }

    /// Used on Ready, appearance and initial anchor settlement; handled errors wait for user retry.
    func resume(needsPage: Bool, hasError: Bool, loadPage: () -> Void) {
        guard isCurrent, canStart() else { return }
        start()
        if needsPage, !hasError { loadPage() }
    }

    func retry() {
        guard isCurrent else { return }
        let ids = retryIDs
        retryIDs.removeAll()
        ledger.retryFailures()
        ledger.enqueue(messageIDs: Array(ids))
        if !ids.isEmpty { onChange?(.quarantine(ids)) }
        start()
    }

    func stop() {
        stopped = true
        ledger.cancel()
        task?.cancel()
        task = nil
        onChange = nil
    }

    func invalidate(id: Int64, chatID: Int64, source: TdUpdateSource) {
        guard isCurrent, self.source == source, location.chatID == chatID,
              knownIDs.contains(id) || pageIsPending else { return }
        ledger.noteLiveUpdate(messageIDs: [id])
        guard knownIDs.contains(id) else { return }
        readyIDs.remove(id)
        retryIDs.remove(id)
        onChange?(.quarantine([id]))
        ledger.enqueue(messageIDs: [id])
        start()
    }

    func delete(_ update: UpdateDeleteMessages, source: TdUpdateSource) {
        guard isCurrent, self.source == source, location.chatID == update.chatId else { return }
        let ids = update.messageIds.filter { knownIDs.contains($0) || pageIsPending }
        guard update.isPermanent, !update.fromCache else {
            ids.forEach { invalidate(id: $0, chatID: update.chatId, source: source) }
            return
        }
        ledger.notePermanentDeletion(messageIDs: ids)
        removedIDs.formUnion(ids)
        readyIDs.subtract(ids)
        retryIDs.subtract(ids)
        onChange?(.quarantine(Set(ids)))
        for id in ids where knownIDs.remove(id) != nil {
            onChange?(.remove(id))
        }
    }

    func beginPage() -> ChatHistoryRestorationRefresh.ReadToken? {
        guard isCurrent, canStart(), let token = ledger.beginRead() else { return nil }
        pageIsPending = true
        return token
    }

    func finishPage() { pageIsPending = false }

    /// Caller installs these values synchronously, before any await or snapshot completion.
    func acceptPage(_ messages: [Message], token: ChatHistoryRestorationRefresh.ReadToken) -> PageAdmission {
        guard isCurrent else { return PageAdmission(accepted: [], quarantined: []) }
        pageIsPending = false
        let scoped = messages.filter { location.matches(message: $0) }
        knownIDs.formUnion(scoped.map(\.id))
        let accepted = ledger.takeCurrentValues(scoped.map {
            ChatHistoryMessageValue(CustomMessage(message: $0, properties: .default))
        }, token: token)
            .map(\.message)
        for message in accepted {
            removedIDs.remove(message.id)
            readyIDs.insert(message.id)
            retryIDs.remove(message.id)
        }
        knownIDs.subtract(removedIDs)
        start()
        return PageAdmission(
            accepted: accepted,
            quarantined: scoped.filter { !readyIDs.contains($0.id) && !removedIDs.contains($0.id) },
        )
    }

    private func receive(_ delivery: ChatHistoryRestorationRefresh.Delivery) {
        guard isCurrent, delivery.source == source else { return }
        let id = delivery.messageID
        switch delivery.result {
        case .message(let value):
            guard let included = tab.includes(value.message) else {
                retryIDs.insert(id)
                onChange?(.retry(id))
                return
            }
            guard included else { remove(id)
                return
            }
            readyIDs.insert(id)
            removedIDs.remove(id)
            retryIDs.remove(id)
            knownIDs.insert(id)
            onChange?(.message(value.message))
        case .missing: remove(id)
        case .retry:
            retryIDs.insert(id)
            onChange?(.retry(id))
        }
    }

    private func remove(_ id: Int64) {
        removedIDs.insert(id)
        knownIDs.remove(id)
        readyIDs.remove(id)
        retryIDs.remove(id)
        onChange?(.remove(id))
    }
}

private extension PeerProfileViewController.SharedTab {
    /// TDLib 022d6020 MessageContent.cpp media/text search index masks.
    func includes(_ message: Message) -> Bool? {
        // Rich blocks can carry photo/video/audio/document index bits. No rich UI is implemented.
        if case .messageRichMessage = message.content { return nil }
        return switch self {
        case .media:
            switch message.content { case .messagePhoto, .messageVideo: true
            default: false }
        case .files:
            if case .messageDocument = message.content {
                true
            } else {
                false
            }
        case .audio:
            if case .messageAudio = message.content {
                true
            } else {
                false
            }
        case .links:
            switch message.content {
            case .messageGame: false
            // Unsupported content must not be misclassified as a confirmed filter removal.
            case .messageGift, .messageGiftedGrams, .messageGiftedPremium, .messageGiftedStars,
                 .messageInvoice, .messagePaidMedia, .messagePremiumGiftCode, .messageRichMessage, .messageUpgradedGift:
                nil
            default:
                MessageContentPresentation.make(message).formattedText?.entities.contains {
                    switch $0.type {
                    case .textEntityTypeEmailAddress, .textEntityTypeTextUrl, .textEntityTypeUrl: true
                    default: false
                    }
                } ?? false
            }
        }
    }
}
