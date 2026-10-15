// PendingMessageForwardStore.swift

import Foundation
import TDLibKit

// MARK: - StoredMessageForward

/// A forward waiting in a destination's composer, as Telegram keeps the forwarded message IDs and options in that
/// chat's interface state (ChatControllerForwardMessages, `withUpdatedForwardMessageIds` and `forwardOptionsState`).
/// Client identifiers are left out: the forward is prepared again on the client that opens the chat.
struct StoredMessageForward: Codable, Equatable {
    enum Mode: String, Codable {
        case forward
        case copy
        case copyWithoutCaption

        var forwardMode: MessageForwardMode {
            switch self {
            case .forward: .forward
            case .copy: .copy(removeCaption: false)
            case .copyWithoutCaption: .copy(removeCaption: true)
            }
        }

        init(_ mode: MessageForwardMode) {
            self =
                switch mode {
                case .forward: .forward
                case .copy(let removeCaption): removeCaption ? .copyWithoutCaption : .copy
                }
        }
    }

    let destination: ChatDraftKey
    let source: ChatDraftKey
    let messageIDs: [Int64]
    let mode: Mode
    let restoresNamesWithCaptions: Bool
    let authors: String
    let authorCount: Int
    let messageSummary: String

    /// Only a forward within one account is saved; its source keeps that account.
    init?(_ forward: PendingMessageForward, destination: ChatDraftKey) {
        guard let accountID = destination.accountID else { return nil }
        let request = forward.prepared.request
        let source = request.sourceLocation.map(ChatDraftKey.init(location:))
            ?? ChatDraftKey(accountID: accountID, chatID: request.sourceChatID, topic: nil)
        guard source.accountID == accountID else { return nil }
        self.destination = destination
        self.source = source
        self.messageIDs = request.messageIDs
        self.mode = Mode(forward.mode)
        self.restoresNamesWithCaptions = forward.restoresNamesWithCaptions
        self.authors = forward.authors
        self.authorCount = forward.authorCount
        self.messageSummary = forward.messageSummary
    }

    /// The forward again with the messages' current permissions; a saved option they no longer allow falls back to
    /// the default one.
    func pending(prepared: PreparedMessageForward) -> PendingMessageForward {
        let savedMode = mode.forwardMode
        return PendingMessageForward(
            prepared: prepared,
            mode: prepared.supports(savedMode) ? savedMode : prepared.defaultMode,
            authors: authors,
            authorCount: authorCount,
            messageSummary: messageSummary,
            restoresNamesWithCaptions: restoresNamesWithCaptions,
        )
    }
}

// MARK: - PendingMessageForwardStore

/// One saved forward per account and chat location. Logging out removes the account's forwards with its drafts.
@MainActor final class PendingMessageForwardStore {
    static let shared = PendingMessageForwardStore()

    private let fileURL: URL
    private var cache: [StoredMessageForward]?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PendingForwards", isDirectory: true)
            .appendingPathComponent("forwards-v1.json")
    }

    func forward(for destination: ChatDraftKey) -> StoredMessageForward? {
        load().first { $0.destination == destination }
    }

    /// Replaces the destination's saved forward.
    func save(_ forward: StoredMessageForward) {
        var forwards = load().filter { $0.destination != forward.destination }
        forwards.append(forward)
        write(forwards)
    }

    func remove(destination: ChatDraftKey) {
        let forwards = load()
        let remaining = forwards.filter { $0.destination != destination }
        guard remaining.count != forwards.count else { return }
        write(remaining)
    }

    /// Removes exactly this saved forward; a newer one saved for the destination meanwhile stays.
    func remove(_ forward: StoredMessageForward) {
        let forwards = load()
        let remaining = forwards.filter { $0 != forward }
        guard remaining.count != forwards.count else { return }
        write(remaining)
    }

    func discardAccount(_ accountID: UUID) {
        let forwards = load()
        let remaining = forwards.filter { $0.destination.accountID != accountID }
        guard remaining.count != forwards.count else { return }
        write(remaining)
    }

    private func load() -> [StoredMessageForward] {
        if let cache { return cache }
        let loaded = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([StoredMessageForward].self, from: $0) } ?? []
        cache = loaded
        return loaded
    }

    private func write(_ forwards: [StoredMessageForward]) {
        cache = forwards
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try JSONEncoder().encode(forwards).write(to: fileURL, options: .atomic)
        } catch {
            log("Pending forwards couldn't be saved: \(error)")
        }
    }
}
