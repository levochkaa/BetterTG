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

enum VoiceNoteDraftStoreError: Swift.Error {
    case draftUnavailable
    case enqueueAlreadyActive
    case finalizationAlreadyActive
    case staleFinalization
}

// MARK: - VoiceNoteFinalizationLease

struct VoiceNoteFinalizationLease: Equatable {
    let draftID: UUID
    let destination: ChatDraftKey

    fileprivate let token: UUID
}

// MARK: - VoiceNoteDraftStatus

struct VoiceNoteDraftStatus {
    let draft: VoiceNoteSendDraft?
    let isFinalizing: Bool
}

// MARK: - VoiceNoteDraftChange

struct VoiceNoteDraftChange {
    let draftID: UUID
    let destination: ChatDraftKey
}

extension Foundation.Notification.Name {
    static let voiceNoteDraftChanged = Self("voiceNoteDraftChanged")
}

// MARK: - VoiceNoteDraftStore

actor VoiceNoteDraftStore {
    // MARK: Internal

    static let shared = VoiceNoteDraftStore()

    // MARK: Private

    private let fileManager = FileManager.default
    private var registrationOwnedDraftIDs = Set<UUID>()
    private var finalizations = [UUID: VoiceNoteFinalizationLease]()
    private let directoryURL: URL
    private let legacyBindingAllowed: @Sendable (ChatDraftKey) -> Bool
    private let writeManifest: @Sendable (Data, URL) throws -> Void

    init(
        directoryURL: URL? = nil,
        legacyBindingAllowed: @escaping @Sendable (ChatDraftKey) -> Bool = {
            ChatDraftLegacyMigrationPolicy.canBindLegacyDrafts(to: $0)
        },
    ) {
        self.init(directoryURL: directoryURL, legacyBindingAllowed: legacyBindingAllowed, writeManifest: { data, url in
            try data.write(to: url, options: .atomic)
        })
    }

    init(
        directoryURL: URL?,
        legacyBindingAllowed: @escaping @Sendable (ChatDraftKey) -> Bool,
        writeManifest: @escaping @Sendable (Data, URL) throws -> Void,
    ) {
        self.directoryURL = directoryURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceNoteDrafts", isDirectory: true)
        self.legacyBindingAllowed = legacyBindingAllowed
        self.writeManifest = writeManifest
    }

    func adopt(_ draft: VoiceNoteSendDraft) throws -> VoiceNoteSendDraft {
        try ensureDirectory()
        if fileManager.fileExists(atPath: manifestURL(for: draft.id).path) {
            // A UI snapshot can outlive encoding, enqueue and registration. Adoption
            // must never restore that snapshot over the canonical manifest.
            return try canonicalDraft(matching: draft)
        }
        guard finalizations[draft.id] == nil else { throw VoiceNoteDraftStoreError.finalizationAlreadyActive }
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

    func claimFinalization(_ draft: VoiceNoteSendDraft) throws
    -> (draft: VoiceNoteSendDraft, lease: VoiceNoteFinalizationLease) {
        let canonical = try adopt(draft)
        try Task.checkCancellation()
        guard finalizations[canonical.id] == nil else { throw VoiceNoteDraftStoreError.finalizationAlreadyActive }
        guard canonical.enqueueStartedAt == nil, canonical.temporaryMessageID == nil else {
            throw VoiceNoteDraftStoreError.enqueueAlreadyActive
        }
        let lease = VoiceNoteFinalizationLease(
            draftID: canonical.id,
            destination: canonical.resolvedDestination,
            token: UUID(),
        )
        finalizations[canonical.id] = lease
        publishChange(canonical)
        return (canonical, lease)
    }

    func finishFinalization(_ lease: VoiceNoteFinalizationLease) {
        guard finalizations[lease.draftID] == lease else { return }
        finalizations[lease.draftID] = nil
        registrationOwnedDraftIDs.remove(lease.draftID)
        nc.post(name: .voiceNoteDraftChanged, object: VoiceNoteDraftChange(
            draftID: lease.draftID,
            destination: lease.destination,
        ))
    }

    func status(id: UUID, destination: ChatDraftKey) -> VoiceNoteDraftStatus {
        let draft = loadCanonicalDraft(id: id).flatMap { $0.resolvedDestination == destination ? $0 : nil }
        return VoiceNoteDraftStatus(
            draft: draft,
            isFinalizing: finalizations[id]?.destination == destination,
        )
    }

    func replaceFile(
        in draft: VoiceNoteSendDraft,
        with encodedURL: URL,
        finalization: VoiceNoteFinalizationLease,
    ) throws -> VoiceNoteSendDraft {
        try Task.checkCancellation()
        try ensureDirectory()
        let canonical = try canonicalDraft(matching: draft, finalization: finalization, forMutation: true)
        guard canonical.enqueueStartedAt == nil, canonical.temporaryMessageID == nil, !canonical.isEncoded else {
            throw VoiceNoteDraftStoreError.enqueueAlreadyActive
        }
        var updatedDraft = canonical
        let destinationURL = directoryURL
            .appendingPathComponent("\(draft.id.uuidString)-\(finalization.token.uuidString)")
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
            if canonical.fileURL.standardizedFileURL != destinationURL.standardizedFileURL {
                try? fileManager.removeItem(at: destinationURL)
            }
            throw error
        }
        if canonical.fileURL.standardizedFileURL != destinationURL.standardizedFileURL {
            try? fileManager.removeItem(at: canonical.fileURL)
        }
        if encodedURL.standardizedFileURL != destinationURL.standardizedFileURL {
            try? fileManager.removeItem(at: encodedURL)
        }
        publishChange(updatedDraft)
        return updatedDraft
    }

    func registerEnqueued(
        _ draft: VoiceNoteSendDraft,
        temporaryMessageID: Int64,
        finalization: VoiceNoteFinalizationLease? = nil,
    ) throws -> VoiceNoteEnqueueRegistration {
        var updatedDraft = try canonicalDraft(matching: draft, finalization: finalization, forMutation: true)
        guard updatedDraft.enqueueStartedAt != nil, updatedDraft.temporaryMessageID == nil else {
            throw VoiceNoteDraftStoreError.enqueueAlreadyActive
        }
        defer { registrationOwnedDraftIDs.remove(draft.id) }
        updatedDraft.enqueueStartedAt = nil
        updatedDraft.temporaryMessageID = temporaryMessageID
        updatedDraft.failedSendState = nil
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
                    finalization: finalization,
                )
            case .succeeded:
                guard removeResolved(updatedDraft, finalization: finalization) else {
                    throw VoiceNoteDraftStoreError.draftUnavailable
                }
            }
        }
        removeOutcomes(draftID: draft.id)
        if let finalization { finishFinalization(finalization) }
        publishChange(updatedDraft)
        return VoiceNoteEnqueueRegistration(draft: updatedDraft, outcome: outcomeRecord?.outcome)
    }

    func beginEnqueue(_ draft: VoiceNoteSendDraft) throws -> VoiceNoteSendDraft {
        try beginEnqueue(draft, finalization: nil)
    }

    func beginEnqueue(
        _ draft: VoiceNoteSendDraft,
        finalization: VoiceNoteFinalizationLease?,
    ) throws -> VoiceNoteSendDraft {
        try Task.checkCancellation()
        let canonical = try canonicalDraft(matching: draft, finalization: finalization, forMutation: true)
        guard canonical.isEncoded, canonical.enqueueStartedAt == nil, canonical.temporaryMessageID == nil else {
            throw VoiceNoteDraftStoreError.enqueueAlreadyActive
        }
        guard try !loadAllDrafts().contains(where: {
            $0.enqueueStartedAt != nil && (
                $0.belongs(to: canonical.resolvedDestination) || $0.deliveryKey == canonical.deliveryKey
            )
        }) else {
            throw VoiceNoteDraftStoreError.enqueueAlreadyActive
        }
        removeOutcomes(draftID: draft.id)
        var updatedDraft = canonical
        updatedDraft.enqueueStartedAt = Foundation.Date()
        try save(updatedDraft)
        registrationOwnedDraftIDs.insert(draft.id)
        publishChange(updatedDraft)
        return updatedDraft
    }

    func markPending(
        _ draft: VoiceNoteSendDraft,
        failedSendState: VoiceNoteFailedSendState? = nil,
        finalization: VoiceNoteFinalizationLease? = nil,
    ) throws -> VoiceNoteSendDraft {
        var updatedDraft = try canonicalDraft(matching: draft, finalization: finalization, forMutation: true)
        updatedDraft.enqueueStartedAt = nil
        updatedDraft.failedSendState = failedSendState
        updatedDraft.temporaryMessageID = nil
        try save(updatedDraft)
        registrationOwnedDraftIDs.remove(draft.id)
        removeOutcomes(draftID: draft.id)
        publishChange(updatedDraft)
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
            guard removeResolved(draft) else { throw VoiceNoteDraftStoreError.finalizationAlreadyActive }
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

    @discardableResult func remove(_ draft: VoiceNoteSendDraft) -> Bool {
        guard let canonical = try? canonicalDraft(matching: draft, forMutation: true),
              canonical.enqueueStartedAt == nil, canonical.temporaryMessageID == nil
        else { return false }
        return removeResolved(canonical)
    }

    func discardMessages(chatID: Int64, messageIDs: [Int64]) {
        let messageIDSet = Set(messageIDs)
        guard let drafts = try? loadAllDrafts() else { return }
        for draft in drafts where draft.chatID == chatID && (
            draft.temporaryMessageID.map(messageIDSet.contains) == true
                || draft.failedSendState.map { messageIDSet.contains($0.messageID) } == true
        ) {
            _ = removeResolved(draft)
        }
    }

    func discardMessages(destination: ChatDraftKey, messageIDs: [Int64]) {
        let messageIDSet = Set(messageIDs)
        guard let drafts = try? loadAllDrafts() else { return }
        for draft in drafts where draft.belongs(to: destination) && (
            draft.temporaryMessageID.map(messageIDSet.contains) == true
                || draft.failedSendState.map { messageIDSet.contains($0.messageID) } == true
        ) {
            _ = removeResolved(draft)
        }
    }

    private func removeResolved(
        _ draft: VoiceNoteSendDraft,
        finalization: VoiceNoteFinalizationLease? = nil,
    ) -> Bool {
        guard let canonical = try? canonicalDraft(matching: draft, finalization: finalization, forMutation: true)
        else { return false }
        registrationOwnedDraftIDs.remove(draft.id)
        try? fileManager.removeItem(at: canonical.fileURL)
        try? fileManager.removeItem(at: manifestURL(for: draft.id))
        removeOutcomes(draftID: draft.id)
        publishChange(canonical)
        return !fileManager.fileExists(atPath: canonical.fileURL.path)
            && !fileManager.fileExists(atPath: manifestURL(for: draft.id).path)
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func loadCanonicalDraft(id: UUID) -> VoiceNoteSendDraft? {
        let manifestURL = manifestURL(for: id)
        guard SendDraftFileReference.isSafeManagedFile(manifestURL, directory: directoryURL),
              let data = try? Data(contentsOf: manifestURL),
              var draft = try? JSONDecoder().decode(VoiceNoteSendDraft.self, from: data),
              draft.id == id,
              let fileURL = SendDraftFileReference.resolve(
                  draft.fileURL, id: id, kind: .voice(encoded: draft.isEncoded), directory: directoryURL,
              )
        else { return nil }
        let needsMigration = draft.fileURL.isFileURL
        draft.fileURL = fileURL
        if needsMigration { try? save(draft) }
        return draft
    }

    private func canonicalDraft(
        matching snapshot: VoiceNoteSendDraft,
        finalization: VoiceNoteFinalizationLease? = nil,
        forMutation: Bool = false,
    ) throws -> VoiceNoteSendDraft {
        guard let canonical = loadCanonicalDraft(id: snapshot.id),
              canonical.resolvedDestination == snapshot.resolvedDestination,
              canonical.deliveryKey == snapshot.deliveryKey
        else { throw VoiceNoteDraftStoreError.draftUnavailable }
        if forMutation {
            if let owner = finalizations[snapshot.id] {
                guard owner == finalization else { throw VoiceNoteDraftStoreError.finalizationAlreadyActive }
            } else if finalization != nil {
                throw VoiceNoteDraftStoreError.staleFinalization
            }
        }
        return canonical
    }

    private func publishChange(_ draft: VoiceNoteSendDraft) {
        nc.post(name: .voiceNoteDraftChanged, object: VoiceNoteDraftChange(
            draftID: draft.id,
            destination: draft.resolvedDestination,
        ))
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
        SendDraftFileReference.isSafeManagedFile(url, directory: directoryURL)
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
                if !removeResolved(draft) { reconciledDrafts.append(draft) }
            }
        }
        return reconciledDrafts
    }

    private func save(_ draft: VoiceNoteSendDraft) throws {
        var manifest = draft
        manifest.fileURL = try SendDraftFileReference.relative(
            draft.fileURL, id: draft.id, kind: .voice(encoded: draft.isEncoded), directory: directoryURL,
        )
        try writeManifest(JSONEncoder().encode(manifest), manifestURL(for: draft.id))
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
                  let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent)
            else { return nil }
            guard
                let data = try? Data(contentsOf: url),
                var draft = try? JSONDecoder().decode(VoiceNoteSendDraft.self, from: data)
            else {
                try? fileManager.removeItem(at: url)
                return nil
            }
            // iOS can move the app container on an update. The managed filename
            // is stable, so recover only this draft's UUID-named local recording.
            if !isManagedFile(draft.fileURL),
               draft.fileURL.deletingPathExtension().lastPathComponent == draft.id.uuidString,
               ["wav", "ogg", "oga"].contains(draft.fileURL.pathExtension.lowercased())
            {
                let movedURL = directoryURL.appendingPathComponent(draft.fileURL.lastPathComponent)
                if fileManager.fileExists(atPath: movedURL.path) {
                    draft.fileURL = movedURL
                    try? save(draft)
                }
            }
            guard isManagedFile(draft.fileURL), fileManager.fileExists(atPath: draft.fileURL.path) else {
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
            guard !SendDraftFileReference.hasRetainedManifest(for: file, directory: directoryURL) else { continue }
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if modified.map({ $0 < cutoff }) ?? true {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
