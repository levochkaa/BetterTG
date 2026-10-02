// VoiceNoteDraftStore.swift

import Foundation
import TDLibKitDynamic

// MARK: - VoiceNoteFailedSendState

struct VoiceNoteFailedSendState: Codable {
    let canRetry: Bool
    let messageID: Int64
    let needAnotherReplyQuote: Bool
    let needAnotherSender: Bool
    let requiredPaidMessageStarCount: Int64
    let retryAvailableAt: Foundation.Date

    var canRetryNow: Bool {
        canRetry
            && !needAnotherReplyQuote
            && !needAnotherSender
            && requiredPaidMessageStarCount == 0
            && retryAvailableAt <= Foundation.Date()
    }
}

// MARK: - VoiceNoteSendDraft

struct VoiceNoteSendDraft: Codable, ChatDraftSendScoped {
    let id: UUID
    let chatID: Int64
    let caption: FormattedText
    let createdAt: Foundation.Date
    let duration: Int
    var enqueueStartedAt: Foundation.Date?
    var failedSendState: VoiceNoteFailedSendState?
    var fileURL: URL
    var isEncoded: Bool
    let replyMessageID: Int64?
    let replyTo: InputMessageReplyTo?
    var sendTopic: MessageTopic? = nil
    var temporaryMessageID: Int64?
    let waveform: Data
    var destination: ChatDraftKey? = nil
}

// MARK: - VoiceNoteSendOutcome

enum VoiceNoteSendOutcome: String, Codable, Equatable {
    case failed
    case succeeded
}

// MARK: - VoiceNoteEnqueueRegistration

struct VoiceNoteEnqueueRegistration {
    let draft: VoiceNoteSendDraft
    let outcome: VoiceNoteSendOutcome?
}

// MARK: - VoiceNoteDraftResolution

struct VoiceNoteDraftResolution {
    let chatID: Int64
    let draft: VoiceNoteSendDraft
    let outcome: VoiceNoteSendOutcome
    let temporaryMessageID: Int64
}

// MARK: - VoiceNoteOutcomeRecord

private struct VoiceNoteOutcomeRecord: Codable {
    let draftID: UUID
    let failedSendState: VoiceNoteFailedSendState?
    let outcome: VoiceNoteSendOutcome
}

// MARK: - VoiceNoteDraftStoreError

private enum VoiceNoteDraftStoreError: Swift.Error {
    case enqueueAlreadyActive
}

// MARK: - VoiceNoteDraftStore

actor VoiceNoteDraftStore {
    // MARK: Internal

    static let shared = VoiceNoteDraftStore()

    // MARK: Private

    private let fileManager = FileManager.default
    private var registrationOwnedDraftIDs = Set<UUID>()
    private let directoryURL: URL
    private let legacyBindingAllowed: @Sendable (ChatDraftKey) -> Bool

    init(
        directoryURL: URL? = nil,
        legacyBindingAllowed: @escaping @Sendable (ChatDraftKey) -> Bool = {
            ChatDraftLegacyMigrationPolicy.canBindLegacyDrafts(to: $0)
        },
    ) {
        self.directoryURL = directoryURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceNoteDrafts", isDirectory: true)
        self.legacyBindingAllowed = legacyBindingAllowed
    }

    func adopt(_ draft: VoiceNoteSendDraft) throws -> VoiceNoteSendDraft {
        try ensureDirectory()
        var storedDraft = draft
        if !isManagedFile(draft.fileURL) {
            let fileExtension = draft.fileURL.pathExtension.isEmpty ? "wav" : draft.fileURL.pathExtension
            let destinationURL = directoryURL
                .appendingPathComponent(draft.id.uuidString)
                .appendingPathExtension(fileExtension)
            try? fileManager.removeItem(at: destinationURL)
            try fileManager.copyItem(at: draft.fileURL, to: destinationURL)
            storedDraft.fileURL = destinationURL
            do {
                try save(storedDraft)
            } catch {
                try? fileManager.removeItem(at: destinationURL)
                throw error
            }
            try? fileManager.removeItem(at: draft.fileURL)
            return storedDraft
        }
        try save(storedDraft)
        return storedDraft
    }

    func replaceFile(in draft: VoiceNoteSendDraft, with encodedURL: URL) throws -> VoiceNoteSendDraft {
        try ensureDirectory()
        var updatedDraft = draft
        let destinationURL = directoryURL
            .appendingPathComponent(draft.id.uuidString)
            .appendingPathExtension("ogg")
        if encodedURL.standardizedFileURL != destinationURL.standardizedFileURL {
            try? fileManager.removeItem(at: destinationURL)
            try fileManager.copyItem(at: encodedURL, to: destinationURL)
        }
        updatedDraft.fileURL = destinationURL
        updatedDraft.isEncoded = true
        do {
            try save(updatedDraft)
        } catch {
            if draft.fileURL.standardizedFileURL != destinationURL.standardizedFileURL {
                try? fileManager.removeItem(at: destinationURL)
            }
            throw error
        }
        if draft.fileURL.standardizedFileURL != destinationURL.standardizedFileURL {
            try? fileManager.removeItem(at: draft.fileURL)
        }
        if encodedURL.standardizedFileURL != destinationURL.standardizedFileURL {
            try? fileManager.removeItem(at: encodedURL)
        }
        return updatedDraft
    }

    func registerEnqueued(
        _ draft: VoiceNoteSendDraft,
        temporaryMessageID: Int64,
    ) throws -> VoiceNoteEnqueueRegistration {
        defer { registrationOwnedDraftIDs.remove(draft.id) }
        var updatedDraft = draft
        updatedDraft.enqueueStartedAt = nil
        updatedDraft.temporaryMessageID = temporaryMessageID
        // Persist the actual TDLib ID before consuming candidate evidence, including
        // a crash between registration and success/failure cleanup.
        try save(updatedDraft)
        let outcomeRecord = loadOutcome(
            draftID: draft.id,
            temporaryMessageID: temporaryMessageID,
        )
        if let outcomeRecord {
            switch outcomeRecord.outcome {
            case .failed:
                updatedDraft = try markPending(
                    updatedDraft,
                    failedSendState: outcomeRecord.failedSendState,
                )
            case .succeeded:
                remove(updatedDraft)
            }
        }
        removeOutcomes(draftID: draft.id)
        return VoiceNoteEnqueueRegistration(draft: updatedDraft, outcome: outcomeRecord?.outcome)
    }

    func beginEnqueue(_ draft: VoiceNoteSendDraft) throws -> VoiceNoteSendDraft {
        guard try !loadAllDrafts().contains(where: {
            $0.enqueueStartedAt != nil && (
                $0.belongs(to: draft.resolvedDestination) || $0.deliveryKey == draft.deliveryKey
            )
        }) else {
            throw VoiceNoteDraftStoreError.enqueueAlreadyActive
        }
        removeOutcomes(draftID: draft.id)
        var updatedDraft = draft
        updatedDraft.enqueueStartedAt = Foundation.Date()
        try save(updatedDraft)
        registrationOwnedDraftIDs.insert(draft.id)
        return updatedDraft
    }

    func markPending(
        _ draft: VoiceNoteSendDraft,
        failedSendState: VoiceNoteFailedSendState? = nil,
    ) throws -> VoiceNoteSendDraft {
        var updatedDraft = draft
        updatedDraft.enqueueStartedAt = nil
        updatedDraft.failedSendState = failedSendState
        updatedDraft.temporaryMessageID = nil
        try save(updatedDraft)
        registrationOwnedDraftIDs.remove(draft.id)
        removeOutcomes(draftID: draft.id)
        return updatedDraft
    }

    func drafts(for chatID: Int64) -> [VoiceNoteSendDraft] {
        do {
            try ensureDirectory()
            let allDrafts = try reconcileInterruptedDrafts(loadAllDrafts())
            removeAbandonedFiles(referencedBy: Set(allDrafts.map(\.fileURL)))
            return allDrafts.filter { $0.chatID == chatID }.sorted(by: { $0.createdAt < $1.createdAt })
        } catch {
            log("Voice note draft load failed: \(error)")
            return []
        }
    }

    func drafts(
        for destination: ChatDraftKey,
        migrateLegacy: Bool = false,
    ) -> [VoiceNoteSendDraft] {
        do {
            try ensureDirectory()
            let shouldMigrateLegacy = migrateLegacy
                && legacyBindingAllowed(destination)
            var allDrafts = try reconcileInterruptedDrafts(loadAllDrafts())
            for index in allDrafts.indices where allDrafts[index].belongs(
                to: destination,
                allowingLegacy: shouldMigrateLegacy,
            ) {
                if allDrafts[index].destination == nil {
                    allDrafts[index].destination = destination
                    try save(allDrafts[index])
                }
            }
            removeAbandonedFiles(referencedBy: Set(allDrafts.map(\.fileURL)))
            return allDrafts
                .filter { $0.destination == destination }
                .sorted { $0.createdAt < $1.createdAt }
        } catch {
            log("Voice note scoped draft load failed: \(error)")
            return []
        }
    }

    func draft(chatID: Int64, temporaryMessageID: Int64) -> VoiceNoteSendDraft? {
        try? loadAllDrafts().first(where: {
            $0.chatID == chatID && $0.temporaryMessageID == temporaryMessageID
        })
    }

    func handleSendSucceeded(
        delivery: ChatDraftDeliveryKey,
        temporaryMessageID: Int64,
        migrateLegacy: Bool = false,
    ) throws -> VoiceNoteDraftResolution? {
        if migrateLegacy {
            try bindLegacyDrafts(to: delivery.legacyBaseRoute)
        }
        guard let draft = try delivery.candidate(
            in: loadAllDrafts(),
            temporaryMessageID: temporaryMessageID,
        ) else { return nil }
        if draft.temporaryMessageID == temporaryMessageID {
            remove(draft)
            removeOutcomes(draftID: draft.id)
            return VoiceNoteDraftResolution(
                chatID: draft.chatID,
                draft: draft,
                outcome: .succeeded,
                temporaryMessageID: temporaryMessageID,
            )
        }
        try saveOutcome(.succeeded, draftID: draft.id, temporaryMessageID: temporaryMessageID)
        return nil
    }

    func handleSendFailed(
        delivery: ChatDraftDeliveryKey,
        temporaryMessageID: Int64,
        failedSendState: VoiceNoteFailedSendState?,
        migrateLegacy: Bool = false,
    ) throws -> VoiceNoteDraftResolution? {
        if migrateLegacy {
            try bindLegacyDrafts(to: delivery.legacyBaseRoute)
        }
        guard let draft = try delivery.candidate(
            in: loadAllDrafts(),
            temporaryMessageID: temporaryMessageID,
        ) else { return nil }
        if draft.temporaryMessageID == temporaryMessageID {
            let pendingDraft = try markPending(draft, failedSendState: failedSendState)
            removeOutcomes(draftID: draft.id)
            return VoiceNoteDraftResolution(
                chatID: draft.chatID,
                draft: pendingDraft,
                outcome: .failed,
                temporaryMessageID: temporaryMessageID,
            )
        }
        try saveOutcome(
            .failed,
            draftID: draft.id,
            failedSendState: failedSendState,
            temporaryMessageID: temporaryMessageID,
        )
        return nil
    }

    func handleMessageDeleted(
        destination: ChatDraftKey,
        temporaryMessageID: Int64,
    ) throws -> VoiceNoteDraftResolution? {
        guard let draft = draft(destination: destination, temporaryMessageID: temporaryMessageID)
        else { return nil }
        let pendingDraft = try markPending(draft, failedSendState: nil)
        return VoiceNoteDraftResolution(
            chatID: destination.chatID,
            draft: pendingDraft,
            outcome: .failed,
            temporaryMessageID: temporaryMessageID,
        )
    }

    func handleMessageDeleted(
        accountID: UUID?,
        chatID: Int64,
        temporaryMessageID: Int64,
    ) throws -> VoiceNoteDraftResolution? {
        let baseDestination = ChatDraftKey(accountID: accountID, chatID: chatID, topic: nil)
        try bindLegacyDrafts(to: baseDestination)
        guard let draft = try loadAllDrafts().first(where: {
            $0.belongsToAccount(accountID, chatID: chatID)
                && $0.temporaryMessageID == temporaryMessageID
        }) else { return nil }
        let pendingDraft = try markPending(draft, failedSendState: nil)
        return VoiceNoteDraftResolution(
            chatID: chatID,
            draft: pendingDraft,
            outcome: .failed,
            temporaryMessageID: temporaryMessageID,
        )
    }

    func handleMessageDeleted(
        chatID: Int64,
        temporaryMessageID: Int64,
    ) throws -> VoiceNoteDraftResolution? {
        guard let draft = draft(chatID: chatID, temporaryMessageID: temporaryMessageID) else { return nil }
        let pendingDraft = try markPending(draft, failedSendState: nil)
        return VoiceNoteDraftResolution(
            chatID: chatID,
            draft: pendingDraft,
            outcome: .failed,
            temporaryMessageID: temporaryMessageID,
        )
    }

    func remove(_ draft: VoiceNoteSendDraft) {
        registrationOwnedDraftIDs.remove(draft.id)
        try? fileManager.removeItem(at: draft.fileURL)
        try? fileManager.removeItem(at: manifestURL(for: draft.id))
    }

    func discardMessages(chatID: Int64, messageIDs: [Int64]) {
        let messageIDSet = Set(messageIDs)
        guard let drafts = try? loadAllDrafts() else { return }
        for draft in drafts where draft.chatID == chatID && (
            draft.temporaryMessageID.map(messageIDSet.contains) == true
                || draft.failedSendState.map { messageIDSet.contains($0.messageID) } == true
        ) {
            remove(draft)
            removeOutcomes(draftID: draft.id)
        }
    }

    func discardMessages(destination: ChatDraftKey, messageIDs: [Int64]) {
        let messageIDSet = Set(messageIDs)
        guard let drafts = try? loadAllDrafts() else { return }
        for draft in drafts where draft.belongs(to: destination) && (
            draft.temporaryMessageID.map(messageIDSet.contains) == true
                || draft.failedSendState.map { messageIDSet.contains($0.messageID) } == true
        ) {
            remove(draft)
            removeOutcomes(draftID: draft.id)
        }
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func draft(
        destination: ChatDraftKey,
        temporaryMessageID: Int64,
    ) -> VoiceNoteSendDraft? {
        try? loadAllDrafts().first(where: {
            $0.belongs(to: destination) && $0.temporaryMessageID == temporaryMessageID
        })
    }

    private func bindLegacyDrafts(to destination: ChatDraftKey) throws {
        guard legacyBindingAllowed(destination) else { return }
        var drafts = try loadAllDrafts()
        for index in drafts.indices where drafts[index].destination == nil
            && drafts[index].chatID == destination.chatID
        {
            drafts[index].destination = destination
            try save(drafts[index])
        }
    }

    private func isManagedFile(_ url: URL) -> Bool {
        let rootPath = directoryURL.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(rootPath)
    }

    private func manifestURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private func outcomeURL(draftID: UUID, temporaryMessageID: Int64) -> URL {
        directoryURL.appendingPathComponent("outcome_\(draftID.uuidString)_\(temporaryMessageID).json")
    }

    private func saveOutcome(
        _ outcome: VoiceNoteSendOutcome,
        draftID: UUID,
        failedSendState: VoiceNoteFailedSendState? = nil,
        temporaryMessageID: Int64,
    ) throws {
        try ensureDirectory()
        let data = try JSONEncoder().encode(VoiceNoteOutcomeRecord(
            draftID: draftID,
            failedSendState: failedSendState,
            outcome: outcome,
        ))
        try data.write(
            to: outcomeURL(draftID: draftID, temporaryMessageID: temporaryMessageID),
            options: .atomic,
        )
    }

    private func loadOutcome(
        draftID: UUID,
        temporaryMessageID: Int64,
    ) -> VoiceNoteOutcomeRecord? {
        let url = outcomeURL(draftID: draftID, temporaryMessageID: temporaryMessageID)
        if let data = try? Data(contentsOf: url),
           let record = try? JSONDecoder().decode(VoiceNoteOutcomeRecord.self, from: data),
           record.draftID == draftID
        {
            return record
        }
        return nil
    }

    private func removeOutcomes(draftID: UUID) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
        ) else { return }
        for file in files where file.lastPathComponent.hasPrefix("outcome_") && file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let record = try? JSONDecoder().decode(VoiceNoteOutcomeRecord.self, from: data),
                  record.draftID == draftID
            else { continue }
            try? fileManager.removeItem(at: file)
        }
    }

    private func reconcileInterruptedDrafts(_ drafts: [VoiceNoteSendDraft]) -> [VoiceNoteSendDraft] {
        var reconciledDrafts = [VoiceNoteSendDraft]()
        for draft in drafts {
            if registrationOwnedDraftIDs.contains(draft.id) {
                reconciledDrafts.append(draft)
                continue
            }
            // An unregistered enqueue has no proven TDLib ID. A lone early outcome
            // may belong to another send; retain the draft until exact registration.
            guard let temporaryMessageID = draft.temporaryMessageID,
                  let record = loadOutcome(draftID: draft.id, temporaryMessageID: temporaryMessageID)
            else {
                reconciledDrafts.append(draft)
                continue
            }
            switch record.outcome {
            case .failed:
                if let pendingDraft = try? markPending(
                    draft,
                    failedSendState: record.failedSendState,
                ) {
                    reconciledDrafts.append(pendingDraft)
                } else {
                    reconciledDrafts.append(draft)
                }
            case .succeeded:
                remove(draft)
                removeOutcomes(draftID: draft.id)
            }
        }
        return reconciledDrafts
    }

    private func save(_ draft: VoiceNoteSendDraft) throws {
        guard isManagedFile(draft.fileURL), fileManager.fileExists(atPath: draft.fileURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try JSONEncoder().encode(draft)
        try data.write(to: manifestURL(for: draft.id), options: .atomic)
    }

    private func loadAllDrafts() throws -> [VoiceNoteSendDraft] {
        try ensureDirectory()
        let files = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
        )
        return files.compactMap { url in
            guard url.pathExtension == "json",
                  UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
            else { return nil }
            guard
                let data = try? Data(contentsOf: url),
                let draft = try? JSONDecoder().decode(VoiceNoteSendDraft.self, from: data),
                isManagedFile(draft.fileURL),
                fileManager.fileExists(atPath: draft.fileURL.path)
            else {
                try? fileManager.removeItem(at: url)
                return nil
            }
            return draft
        }
    }

    private func removeAbandonedFiles(referencedBy referencedURLs: Set<URL>) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles],
        ) else { return }
        let cutoff = Foundation.Date().addingTimeInterval(-24 * 60 * 60)
        for file in files where ["wav", "ogg"].contains(file.pathExtension) && !referencedURLs.contains(file) {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if modified.map({ $0 < cutoff }) ?? true {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
