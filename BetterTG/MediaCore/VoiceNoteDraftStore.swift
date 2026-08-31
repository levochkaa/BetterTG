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

struct VoiceNoteSendDraft: Codable, ChatDraftScoped {
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
    private lazy var directoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("VoiceNoteDrafts", isDirectory: true)

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
        } else {
            try save(updatedDraft)
        }
        removeOutcomes(draftID: draft.id)
        return VoiceNoteEnqueueRegistration(draft: updatedDraft, outcome: outcomeRecord?.outcome)
    }

    func beginEnqueue(_ draft: VoiceNoteSendDraft) throws -> VoiceNoteSendDraft {
        guard try !loadAllDrafts().contains(where: {
            $0.belongs(to: draft.resolvedDestination) && $0.enqueueStartedAt != nil
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
                && ChatDraftLegacyMigrationPolicy.canBindLegacyDrafts(to: destination)
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
        destination: ChatDraftKey,
        temporaryMessageID: Int64,
        migrateLegacy: Bool = false,
    ) throws -> VoiceNoteDraftResolution? {
        if migrateLegacy {
            try bindLegacyDrafts(to: destination)
        }
        if let draft = draft(destination: destination, temporaryMessageID: temporaryMessageID) {
            remove(draft)
            removeOutcomes(draftID: draft.id)
            return VoiceNoteDraftResolution(
                chatID: destination.chatID,
                draft: draft,
                outcome: .succeeded,
                temporaryMessageID: temporaryMessageID,
            )
        }
        if let activeDraft = try loadAllDrafts().first(where: {
            $0.belongs(to: destination) && $0.enqueueStartedAt != nil
        }) {
            try saveOutcome(
                .succeeded,
                draftID: activeDraft.id,
                temporaryMessageID: temporaryMessageID,
            )
        }
        return nil
    }

    func handleSendFailed(
        destination: ChatDraftKey,
        temporaryMessageID: Int64,
        failedSendState: VoiceNoteFailedSendState?,
        migrateLegacy: Bool = false,
    ) throws -> VoiceNoteDraftResolution? {
        if migrateLegacy {
            try bindLegacyDrafts(to: destination)
        }
        if let draft = draft(destination: destination, temporaryMessageID: temporaryMessageID) {
            let pendingDraft = try markPending(draft, failedSendState: failedSendState)
            removeOutcomes(draftID: draft.id)
            return VoiceNoteDraftResolution(
                chatID: destination.chatID,
                draft: pendingDraft,
                outcome: .failed,
                temporaryMessageID: temporaryMessageID,
            )
        }
        if let activeDraft = try loadAllDrafts().first(where: {
            $0.belongs(to: destination) && $0.enqueueStartedAt != nil
        }) {
            try saveOutcome(
                .failed,
                draftID: activeDraft.id,
                failedSendState: failedSendState,
                temporaryMessageID: temporaryMessageID,
            )
        }
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

    func handleSendSucceeded(
        chatID: Int64,
        temporaryMessageID: Int64,
    ) throws -> VoiceNoteDraftResolution? {
        if let draft = draft(chatID: chatID, temporaryMessageID: temporaryMessageID) {
            remove(draft)
            removeOutcomes(draftID: draft.id)
            return VoiceNoteDraftResolution(
                chatID: chatID,
                draft: draft,
                outcome: .succeeded,
                temporaryMessageID: temporaryMessageID,
            )
        }
        if let activeDraft = try loadAllDrafts().first(where: {
            $0.chatID == chatID && $0.enqueueStartedAt != nil
        }) {
            try saveOutcome(
                .succeeded,
                draftID: activeDraft.id,
                temporaryMessageID: temporaryMessageID,
            )
            return nil
        }
        return nil
    }

    func handleSendFailed(
        chatID: Int64,
        temporaryMessageID: Int64,
        failedSendState: VoiceNoteFailedSendState?,
    ) throws -> VoiceNoteDraftResolution? {
        if let draft = draft(chatID: chatID, temporaryMessageID: temporaryMessageID) {
            let pendingDraft = try markPending(draft, failedSendState: failedSendState)
            removeOutcomes(draftID: draft.id)
            return VoiceNoteDraftResolution(
                chatID: chatID,
                draft: pendingDraft,
                outcome: .failed,
                temporaryMessageID: temporaryMessageID,
            )
        }
        if let activeDraft = try loadAllDrafts().first(where: {
            $0.chatID == chatID && $0.enqueueStartedAt != nil
        }) {
            try saveOutcome(
                .failed,
                draftID: activeDraft.id,
                failedSendState: failedSendState,
                temporaryMessageID: temporaryMessageID,
            )
            return nil
        }
        return nil
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
        guard ChatDraftLegacyMigrationPolicy.canBindLegacyDrafts(to: destination) else { return }
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
        return outcomeRecords(draftID: draftID).first(where: {
            $0.draftID == draftID
        })
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
            guard draft.enqueueStartedAt != nil else {
                reconciledDrafts.append(draft)
                continue
            }
            let records = outcomeRecords(draftID: draft.id)
            guard records.count == 1, let record = records.first else {
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

    private func outcomeRecords(draftID: UUID) -> [VoiceNoteOutcomeRecord] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
        ) else { return [] }
        return files.compactMap { file in
            guard file.lastPathComponent.hasPrefix("outcome_"),
                  file.pathExtension == "json",
                  let data = try? Data(contentsOf: file),
                  let record = try? JSONDecoder().decode(VoiceNoteOutcomeRecord.self, from: data),
                  record.draftID == draftID
            else { return nil }
            return record
        }
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
