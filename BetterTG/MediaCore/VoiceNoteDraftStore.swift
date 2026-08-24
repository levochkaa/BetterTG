// VoiceNoteDraftStore.swift

import Foundation
import TDLibKit

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

struct VoiceNoteSendDraft: Codable {
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
        var updatedDraft = draft
        updatedDraft.enqueueStartedAt = nil
        updatedDraft.temporaryMessageID = temporaryMessageID
        let outcomeRecord = loadOutcome(
            draftID: draft.id,
            chatID: draft.chatID,
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
        removeOutcome(chatID: draft.chatID, temporaryMessageID: temporaryMessageID)
        return VoiceNoteEnqueueRegistration(draft: updatedDraft, outcome: outcomeRecord?.outcome)
    }

    func beginEnqueue(_ draft: VoiceNoteSendDraft) throws -> VoiceNoteSendDraft {
        guard try !loadAllDrafts().contains(where: {
            $0.chatID == draft.chatID && $0.enqueueStartedAt != nil
        }) else {
            throw VoiceNoteDraftStoreError.enqueueAlreadyActive
        }
        removeOutcomes(draftID: draft.id)
        var updatedDraft = draft
        updatedDraft.enqueueStartedAt = Foundation.Date()
        try save(updatedDraft)
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

    func draft(chatID: Int64, temporaryMessageID: Int64) -> VoiceNoteSendDraft? {
        try? loadAllDrafts().first(where: {
            $0.chatID == chatID && $0.temporaryMessageID == temporaryMessageID
        })
    }

    func handleSendSucceeded(
        chatID: Int64,
        temporaryMessageID: Int64,
    ) throws -> VoiceNoteDraftResolution? {
        if let draft = draft(chatID: chatID, temporaryMessageID: temporaryMessageID) {
            remove(draft)
            removeOutcome(chatID: chatID, temporaryMessageID: temporaryMessageID)
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
                chatID: chatID,
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
            removeOutcome(chatID: chatID, temporaryMessageID: temporaryMessageID)
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
                chatID: chatID,
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

    // MARK: Private

    private let fileManager = FileManager.default
    private lazy var directoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("VoiceNoteDrafts", isDirectory: true)

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func isManagedFile(_ url: URL) -> Bool {
        let rootPath = directoryURL.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(rootPath)
    }

    private func manifestURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private func outcomeURL(chatID: Int64, temporaryMessageID: Int64) -> URL {
        directoryURL.appendingPathComponent("outcome_\(chatID)_\(temporaryMessageID).json")
    }

    private func saveOutcome(
        _ outcome: VoiceNoteSendOutcome,
        draftID: UUID,
        failedSendState: VoiceNoteFailedSendState? = nil,
        chatID: Int64,
        temporaryMessageID: Int64,
    ) throws {
        try ensureDirectory()
        let data = try JSONEncoder().encode(VoiceNoteOutcomeRecord(
            draftID: draftID,
            failedSendState: failedSendState,
            outcome: outcome,
        ))
        try data.write(
            to: outcomeURL(chatID: chatID, temporaryMessageID: temporaryMessageID),
            options: .atomic,
        )
    }

    private func loadOutcome(
        draftID: UUID,
        chatID: Int64,
        temporaryMessageID: Int64,
    ) -> VoiceNoteOutcomeRecord? {
        let url = outcomeURL(chatID: chatID, temporaryMessageID: temporaryMessageID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let record = try? JSONDecoder().decode(VoiceNoteOutcomeRecord.self, from: data),
              record.draftID == draftID
        else { return nil }
        return record
    }

    private func removeOutcome(chatID: Int64, temporaryMessageID: Int64) {
        try? fileManager.removeItem(at: outcomeURL(chatID: chatID, temporaryMessageID: temporaryMessageID))
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
