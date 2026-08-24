// VideoNoteFileStore.swift

import CoreGraphics
import Foundation
import ImageIO
import TDLibKit
import UniformTypeIdentifiers

struct VideoNoteFailedSendState: Codable {
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

struct VideoNoteInputThumbnailAsset: Sendable {
    let height: Int
    let url: URL
    let width: Int
}

struct VideoNoteSendDraft: Codable {
    let id: UUID
    let chatID: Int64
    let createdAt: Foundation.Date
    let duration: Double
    var enqueueStartedAt: Foundation.Date?
    var failedSendState: VideoNoteFailedSendState?
    var fileURL: URL
    let length: Int
    let originRecordingDraftID: UUID?
    var removalRequestedAt: Foundation.Date?
    let replyMessageID: Int64?
    let replyTo: InputMessageReplyTo?
    let thumbnailFileURL: URL?
    let thumbnailHeight: Int?
    let thumbnailWidth: Int?
    var temporaryMessageID: Int64?

    var asset: VideoNoteAsset {
        VideoNoteAsset(duration: duration, length: length, url: fileURL)
    }

}

enum VideoNoteSendOutcome: String, Codable, Equatable {
    case failed
    case succeeded
}

struct VideoNoteEnqueueRegistration {
    let draft: VideoNoteSendDraft
    let outcome: VideoNoteSendOutcome?
}

enum VideoNoteEnqueuePreparation {
    case alreadyEnqueued(VideoNoteSendDraft)
    case ready(VideoNoteSendDraft)
    case retained(VideoNoteSendDraft)
}

struct VideoNoteDraftResolution {
    let chatID: Int64
    let draft: VideoNoteSendDraft
    let outcome: VideoNoteSendOutcome
    let temporaryMessageID: Int64
}

private struct VideoNoteOutcomeRecord: Codable {
    let draftID: UUID
    let failedSendState: VideoNoteFailedSendState?
    let outcome: VideoNoteSendOutcome
}

private enum VideoNoteFileStoreError: Swift.Error {
    case draftBeingRemoved
    case enqueueAlreadyActive
    case managedFileMissing(String)
    case invalidThumbnail
    case removalPersistenceFailed
    case unmanagedFile(String, root: String)
}

actor VideoNoteFileStore {
    static let shared = VideoNoteFileStore()

    #if DEBUG
        nonisolated static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-video-note-drafts") else { return }
            Task { await shared.runDebugProbe() }
        }
    #endif

    func adopt(
        _ asset: VideoNoteAsset,
        thumbnail: VideoNoteInputThumbnailAsset? = nil,
        chatID: Int64,
        originRecordingDraftID: UUID? = nil,
        replyMessageID: Int64?,
        replyTo: InputMessageReplyTo?,
    ) throws -> VideoNoteSendDraft {
        try ensureDirectory()
        if let thumbnail {
            guard let dimensions = Self.validatedThumbnailDimensions(at: thumbnail.url),
                  dimensions.width == thumbnail.width,
                  dimensions.height == thumbnail.height
            else { throw VideoNoteFileStoreError.invalidThumbnail }
        }
        let allManifests = try loadAllManifests()
        if allManifests.contains(where: {
            (removingDraftIDs.contains($0.id) || $0.removalRequestedAt != nil)
                && (
                    $0.fileURL.standardizedFileURL == asset.url.standardizedFileURL
                        || originRecordingDraftID != nil && $0.originRecordingDraftID == originRecordingDraftID
                )
        }) {
            throw VideoNoteFileStoreError.draftBeingRemoved
        }
        if let originRecordingDraftID,
           removingOriginCounts[originRecordingDraftID, default: 0] > 0
        {
            throw VideoNoteFileStoreError.draftBeingRemoved
        }
        let drafts = allManifests.filter {
            !removingDraftIDs.contains($0.id)
                && $0.removalRequestedAt == nil
                && fileManager.fileExists(atPath: $0.fileURL.path(percentEncoded: false))
        }
        if let originRecordingDraftID,
           let existing = drafts.first(where: {
               $0.chatID == chatID && $0.originRecordingDraftID == originRecordingDraftID
           })
        {
            if existing.fileURL.standardizedFileURL != asset.url.standardizedFileURL,
               !isManagedFile(asset.url)
            {
                try? fileManager.removeItem(at: asset.url)
            }
            discardUnmanagedThumbnailInput(thumbnail)
            return existing
        }
        if let existing = drafts.first(where: {
            $0.chatID == chatID && $0.fileURL.standardizedFileURL == asset.url.standardizedFileURL
        }) {
            discardUnmanagedThumbnailInput(thumbnail)
            return existing
        }
        let id = UUID()
        let destination = directoryURL.appendingPathComponent(id.uuidString).appendingPathExtension("mp4")
        let thumbnailDestination = thumbnail.map { _ in
            directoryURL.appendingPathComponent("\(id.uuidString)-thumbnail").appendingPathExtension("jpg")
        }
        try? fileManager.removeItem(at: destination)
        try fileManager.copyItem(at: asset.url, to: destination)
        applyFileProtection(to: destination)
        do {
            if let thumbnail, let thumbnailDestination {
                try? fileManager.removeItem(at: thumbnailDestination)
                try fileManager.copyItem(at: thumbnail.url, to: thumbnailDestination)
                applyFileProtection(to: thumbnailDestination)
            }
        } catch {
            try? fileManager.removeItem(at: destination)
            if let thumbnailDestination {
                try? fileManager.removeItem(at: thumbnailDestination)
            }
            throw error
        }
        let draft = VideoNoteSendDraft(
            id: id,
            chatID: chatID,
            createdAt: Foundation.Date(),
            duration: asset.duration,
            enqueueStartedAt: nil,
            failedSendState: nil,
            fileURL: destination,
            length: asset.length,
            originRecordingDraftID: originRecordingDraftID,
            removalRequestedAt: nil,
            replyMessageID: replyMessageID,
            replyTo: replyTo,
            thumbnailFileURL: thumbnailDestination,
            thumbnailHeight: thumbnail?.height,
            thumbnailWidth: thumbnail?.width,
            temporaryMessageID: nil,
        )
        do {
            try save(draft)
        } catch {
            try? fileManager.removeItem(at: destination)
            if let thumbnailDestination {
                try? fileManager.removeItem(at: thumbnailDestination)
            }
            throw error
        }
        try? fileManager.removeItem(at: asset.url)
        discardUnmanagedThumbnailInput(thumbnail)
        return draft
    }

    func beginEnqueue(_ draft: VideoNoteSendDraft) throws -> VideoNoteSendDraft {
        guard !removingDraftIDs.contains(draft.id) else {
            throw VideoNoteFileStoreError.draftBeingRemoved
        }
        let visibleDrafts = try loadVisibleDrafts()
        guard visibleDrafts.contains(where: { $0.id == draft.id }) else {
            throw VideoNoteFileStoreError.draftBeingRemoved
        }
        guard !visibleDrafts.contains(where: {
            $0.chatID == draft.chatID && $0.enqueueStartedAt != nil
        }) else { throw VideoNoteFileStoreError.enqueueAlreadyActive }
        removeOutcomes(draftID: draft.id)
        var updatedDraft = draft
        updatedDraft.enqueueStartedAt = Foundation.Date()
        try save(updatedDraft)
        registrationOwnedDraftIDs.insert(draft.id)
        return updatedDraft
    }

    func adoptAndPrepareEnqueue(
        _ asset: VideoNoteAsset,
        thumbnail: VideoNoteInputThumbnailAsset? = nil,
        chatID: Int64,
        originRecordingDraftID: UUID?,
        replyMessageID: Int64?,
        replyTo: InputMessageReplyTo?,
    ) throws -> VideoNoteEnqueuePreparation {
        let draft = try adopt(
            asset,
            thumbnail: thumbnail,
            chatID: chatID,
            originRecordingDraftID: originRecordingDraftID,
            replyMessageID: replyMessageID,
            replyTo: replyTo,
        )
        guard draft.enqueueStartedAt == nil, draft.temporaryMessageID == nil else {
            return .alreadyEnqueued(draft)
        }
        do {
            return .ready(try beginEnqueue(draft))
        } catch {
            return .retained(draft)
        }
    }

    func registerEnqueued(
        _ draft: VideoNoteSendDraft,
        temporaryMessageID: Int64,
    ) async throws -> VideoNoteEnqueueRegistration {
        guard !removingDraftIDs.contains(draft.id) else {
            throw VideoNoteFileStoreError.draftBeingRemoved
        }
        let visibleDrafts = try loadVisibleDrafts()
        guard visibleDrafts.contains(where: { $0.id == draft.id }) else {
            throw VideoNoteFileStoreError.draftBeingRemoved
        }
        defer { registrationOwnedDraftIDs.remove(draft.id) }
        if let currentDraft = visibleDrafts.first(where: { $0.id == draft.id }),
           currentDraft.enqueueStartedAt == nil,
           currentDraft.failedSendState != nil
        {
            return VideoNoteEnqueueRegistration(draft: currentDraft, outcome: .failed)
        }
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
                guard await remove(updatedDraft) else {
                    throw VideoNoteFileStoreError.removalPersistenceFailed
                }
            }
        } else {
            try save(updatedDraft)
        }
        removeOutcome(chatID: draft.chatID, temporaryMessageID: temporaryMessageID)
        return VideoNoteEnqueueRegistration(draft: updatedDraft, outcome: outcomeRecord?.outcome)
    }

    func markPending(
        _ draft: VideoNoteSendDraft,
        failedSendState: VideoNoteFailedSendState? = nil,
    ) throws -> VideoNoteSendDraft {
        guard !removingDraftIDs.contains(draft.id) else {
            throw VideoNoteFileStoreError.draftBeingRemoved
        }
        guard try loadVisibleDrafts().contains(where: { $0.id == draft.id }) else {
            throw VideoNoteFileStoreError.draftBeingRemoved
        }
        var updatedDraft = draft
        updatedDraft.enqueueStartedAt = nil
        updatedDraft.failedSendState = failedSendState
        updatedDraft.temporaryMessageID = nil
        try save(updatedDraft)
        registrationOwnedDraftIDs.remove(draft.id)
        removeOutcomes(draftID: draft.id)
        return updatedDraft
    }

    func drafts(for chatID: Int64) async -> [VideoNoteSendDraft] {
        do {
            try ensureDirectory()
            let drafts = try await reconcileInterruptedDrafts()
            let manifests = try loadAllManifests()
            removeAbandonedFiles(referencedBy: Set(manifests.flatMap {
                [$0.fileURL] + [$0.thumbnailFileURL].compactMap { $0 }
            }))
            return drafts.filter { $0.chatID == chatID }.sorted { $0.createdAt < $1.createdAt }
        } catch {
            log("Video note draft load failed: \(error)")
            return []
        }
    }

    func recordingDraftOrigins() throws -> Set<UUID> {
        Set(try loadAllManifests().compactMap(\.originRecordingDraftID))
    }

    func inputThumbnail(for draft: VideoNoteSendDraft) -> InputThumbnail? {
        guard let thumbnailFileURL = draft.thumbnailFileURL,
              let expectedHeight = draft.thumbnailHeight,
              let expectedWidth = draft.thumbnailWidth,
              let dimensions = Self.validatedThumbnailDimensions(at: thumbnailFileURL),
              dimensions.height == expectedHeight,
              dimensions.width == expectedWidth
        else { return nil }
        return InputThumbnail(
            height: dimensions.height,
            thumbnail: .inputFileLocal(.init(path: thumbnailFileURL.path(percentEncoded: false))),
            width: dimensions.width,
        )
    }

    func reconcileRemovalTombstones() async throws -> Bool {
        let tombstones = try loadAllManifests().filter { $0.removalRequestedAt != nil }
        var allRemoved = true
        for draft in tombstones where !removingDraftIDs.contains(draft.id) {
            allRemoved = await remove(draft) && allRemoved
        }
        return allRemoved
    }

    func handleSendSucceeded(
        chatID: Int64,
        temporaryMessageID: Int64,
    ) async throws -> VideoNoteDraftResolution? {
        if let draft = draft(chatID: chatID, temporaryMessageID: temporaryMessageID) {
            try saveOutcome(
                .succeeded,
                draftID: draft.id,
                chatID: chatID,
                temporaryMessageID: temporaryMessageID,
            )
            guard await remove(draft) else {
                throw VideoNoteFileStoreError.removalPersistenceFailed
            }
            removeOutcome(chatID: chatID, temporaryMessageID: temporaryMessageID)
            return VideoNoteDraftResolution(
                chatID: chatID,
                draft: draft,
                outcome: .succeeded,
                temporaryMessageID: temporaryMessageID,
            )
        }
        if let activeDraft = try loadVisibleDrafts().first(where: {
            $0.chatID == chatID && $0.enqueueStartedAt != nil
        }) {
            try saveOutcome(
                .succeeded,
                draftID: activeDraft.id,
                chatID: chatID,
                temporaryMessageID: temporaryMessageID,
            )
            guard !registrationOwnedDraftIDs.contains(activeDraft.id) else { return nil }
            _ = try await reconcileInterruptedDrafts()
            return VideoNoteDraftResolution(
                chatID: chatID,
                draft: activeDraft,
                outcome: .succeeded,
                temporaryMessageID: temporaryMessageID,
            )
        }
        return nil
    }

    func handleSendFailed(
        chatID: Int64,
        temporaryMessageID: Int64,
        failedSendState: VideoNoteFailedSendState?,
    ) async throws -> VideoNoteDraftResolution? {
        if let draft = draft(chatID: chatID, temporaryMessageID: temporaryMessageID) {
            let pending = try markPending(draft, failedSendState: failedSendState)
            removeOutcome(chatID: chatID, temporaryMessageID: temporaryMessageID)
            return VideoNoteDraftResolution(
                chatID: chatID,
                draft: pending,
                outcome: .failed,
                temporaryMessageID: temporaryMessageID,
            )
        }
        if let activeDraft = try loadVisibleDrafts().first(where: {
            $0.chatID == chatID && $0.enqueueStartedAt != nil
        }) {
            try saveOutcome(
                .failed,
                draftID: activeDraft.id,
                failedSendState: failedSendState,
                chatID: chatID,
                temporaryMessageID: temporaryMessageID,
            )
            guard !registrationOwnedDraftIDs.contains(activeDraft.id) else { return nil }
            let reconciled = try await reconcileInterruptedDrafts()
            guard let pendingDraft = reconciled.first(where: { $0.id == activeDraft.id }) else {
                return nil
            }
            return VideoNoteDraftResolution(
                chatID: chatID,
                draft: pendingDraft,
                outcome: .failed,
                temporaryMessageID: temporaryMessageID,
            )
        }
        return nil
    }

    func handleMessageDeleted(
        chatID: Int64,
        temporaryMessageID: Int64,
    ) throws -> VideoNoteDraftResolution? {
        guard let draft = draft(chatID: chatID, temporaryMessageID: temporaryMessageID) else { return nil }
        let pending = try markPending(draft)
        return VideoNoteDraftResolution(
            chatID: chatID,
            draft: pending,
            outcome: .failed,
            temporaryMessageID: temporaryMessageID,
        )
    }

    @discardableResult func remove(_ draft: VideoNoteSendDraft) async -> Bool {
        if removingDraftIDs.contains(draft.id) {
            await withCheckedContinuation { continuation in
                removalWaiters[draft.id, default: []].append(continuation)
            }
            return !fileManager.fileExists(atPath: manifestURL(for: draft.id).path(percentEncoded: false))
        }
        removingDraftIDs.insert(draft.id)
        var removalDraft = draft
        do {
            if var storedDraft = try loadAllManifests().first(where: { $0.id == draft.id }) {
                if storedDraft.removalRequestedAt == nil {
                    storedDraft.removalRequestedAt = Foundation.Date()
                    try saveManifest(storedDraft)
                }
                removalDraft = storedDraft
            }
        } catch {
            removingDraftIDs.remove(draft.id)
            let waiters = removalWaiters.removeValue(forKey: draft.id) ?? []
            waiters.forEach { $0.resume() }
            log("Video note removal tombstone failed: \(error)")
            return false
        }
        let originID = removalDraft.originRecordingDraftID
        var originWasRemoved = true
        if let originID {
            removingOriginCounts[originID, default: 0] += 1
            originWasRemoved = await VideoNoteRecordingDraftStore.shared.discard(id: originID)
        }
        let removed = originWasRemoved && removeFiles(for: removalDraft)
        removingDraftIDs.remove(draft.id)
        if let originID {
            let remainingCount = removingOriginCounts[originID, default: 1] - 1
            if remainingCount > 0 {
                removingOriginCounts[originID] = remainingCount
            } else {
                removingOriginCounts.removeValue(forKey: originID)
            }
        }
        let waiters = removalWaiters.removeValue(forKey: draft.id) ?? []
        waiters.forEach { $0.resume() }
        return removed
    }

    @discardableResult private func removeFiles(for draft: VideoNoteSendDraft) -> Bool {
        registrationOwnedDraftIDs.remove(draft.id)
        let manifestURL = manifestURL(for: draft.id)
        do {
            if fileManager.fileExists(atPath: manifestURL.path(percentEncoded: false)) {
                try fileManager.removeItem(at: manifestURL)
            }
        } catch {
            log("Video note removal manifest cleanup failed: \(error)")
            return false
        }
        try? fileManager.removeItem(at: draft.fileURL)
        if let thumbnailFileURL = draft.thumbnailFileURL {
            try? fileManager.removeItem(at: thumbnailFileURL)
        }
        removeOutcomes(draftID: draft.id)
        return true
    }

    func discardAsset(at url: URL) async {
        if let draft = try? loadAllDrafts().first(where: {
            $0.fileURL.standardizedFileURL == url.standardizedFileURL
        }) {
            await remove(draft)
        } else {
            try? fileManager.removeItem(at: url)
        }
    }

    func discardMessages(chatID: Int64, messageIDs: [Int64]) async {
        let ids = Set(messageIDs)
        guard let drafts = try? loadAllDrafts() else { return }
        for draft in drafts where draft.chatID == chatID && draft.enqueueStartedAt == nil && (
            draft.temporaryMessageID.map(ids.contains) == true
                || draft.failedSendState.map { ids.contains($0.messageID) } == true
        ) {
            await remove(draft)
        }
    }

    private let fileManager = FileManager.default
    private var removingOriginCounts = [UUID: Int]()
    private var removalWaiters = [UUID: [CheckedContinuation<Void, Never>]]()
    private var removingDraftIDs = Set<UUID>()
    private var registrationOwnedDraftIDs = Set<UUID>()
    private lazy var directoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("VideoNoteDrafts", isDirectory: true)

    private func ensureDirectory() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedDirectory = directoryURL
        try? protectedDirectory.setResourceValues(values)
    }

    private func applyFileProtection(to url: URL) {
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path(percentEncoded: false),
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedURL = url
        try? protectedURL.setResourceValues(values)
    }

    private func isManagedFile(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(directoryURL.standardizedFileURL.path + "/")
    }

    private func discardUnmanagedThumbnailInput(_ thumbnail: VideoNoteInputThumbnailAsset?) {
        guard let thumbnail, !isManagedFile(thumbnail.url) else { return }
        try? fileManager.removeItem(at: thumbnail.url)
    }

    private func manifestURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private func outcomeURL(chatID: Int64, temporaryMessageID: Int64) -> URL {
        directoryURL.appendingPathComponent("outcome_\(chatID)_\(temporaryMessageID).json")
    }

    private func draft(chatID: Int64, temporaryMessageID: Int64) -> VideoNoteSendDraft? {
        try? loadVisibleDrafts().first {
            $0.chatID == chatID && $0.temporaryMessageID == temporaryMessageID
        }
    }

    private func save(_ draft: VideoNoteSendDraft) throws {
        let filePath = draft.fileURL.path(percentEncoded: false)
        guard fileManager.fileExists(atPath: filePath) else {
            throw VideoNoteFileStoreError.managedFileMissing(filePath)
        }
        try saveManifest(draft)
    }

    private func saveManifest(_ draft: VideoNoteSendDraft) throws {
        guard isManagedFile(draft.fileURL),
              draft.thumbnailFileURL.map(isManagedFile) ?? true
        else {
            throw VideoNoteFileStoreError.unmanagedFile(
                draft.fileURL.standardizedFileURL.path(percentEncoded: false),
                root: directoryURL.standardizedFileURL.path(percentEncoded: false),
            )
        }
        let data = try JSONEncoder().encode(draft)
        try data.write(to: manifestURL(for: draft.id), options: .atomic)
    }

    private func loadAllManifests() throws -> [VideoNoteSendDraft] {
        try ensureDirectory()
        let files = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
        )
        return files.compactMap { url in
            guard url.pathExtension == "json",
                  UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil,
                  let data = try? Data(contentsOf: url),
                  let draft = try? JSONDecoder().decode(VideoNoteSendDraft.self, from: data),
                  isManagedFile(draft.fileURL),
                  draft.thumbnailFileURL.map(isManagedFile) ?? true
            else { return nil }
            return draft
        }
    }

    private func loadAllDrafts() throws -> [VideoNoteSendDraft] {
        try loadAllManifests().filter {
            fileManager.fileExists(atPath: $0.fileURL.path(percentEncoded: false))
        }
    }

    private func loadVisibleDrafts() throws -> [VideoNoteSendDraft] {
        try loadAllDrafts().filter {
            !removingDraftIDs.contains($0.id) && $0.removalRequestedAt == nil
        }
    }

    private func saveOutcome(
        _ outcome: VideoNoteSendOutcome,
        draftID: UUID,
        failedSendState: VideoNoteFailedSendState? = nil,
        chatID: Int64,
        temporaryMessageID: Int64,
    ) throws {
        try ensureDirectory()
        let record = VideoNoteOutcomeRecord(
            draftID: draftID,
            failedSendState: failedSendState,
            outcome: outcome,
        )
        try JSONEncoder().encode(record).write(
            to: outcomeURL(chatID: chatID, temporaryMessageID: temporaryMessageID),
            options: .atomic,
        )
    }

    private func loadOutcome(
        draftID: UUID,
        chatID: Int64,
        temporaryMessageID: Int64,
    ) -> VideoNoteOutcomeRecord? {
        let url = outcomeURL(chatID: chatID, temporaryMessageID: temporaryMessageID)
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(VideoNoteOutcomeRecord.self, from: data),
              record.draftID == draftID
        else { return nil }
        return record
    }

    private func removeOutcome(chatID: Int64, temporaryMessageID: Int64) {
        try? fileManager.removeItem(at: outcomeURL(chatID: chatID, temporaryMessageID: temporaryMessageID))
    }

    private func removeOutcomes(draftID: UUID) {
        for (url, _) in outcomeRecordsWithURLs(draftID: draftID) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func outcomeRecordsWithURLs(draftID: UUID) -> [(URL, VideoNoteOutcomeRecord)] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
        ) else { return [] }
        return files.compactMap { url in
            guard url.lastPathComponent.hasPrefix("outcome_"),
                  url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let record = try? JSONDecoder().decode(VideoNoteOutcomeRecord.self, from: data),
                  record.draftID == draftID
            else { return nil }
            return (url, record)
        }
    }

    private func reconcileInterruptedDrafts() async throws -> [VideoNoteSendDraft] {
        while true {
            _ = try await reconcileRemovalTombstones()
            let drafts = try loadVisibleDrafts()
            var succeededDrafts = [VideoNoteSendDraft]()
            for draft in drafts where !registrationOwnedDraftIDs.contains(draft.id) {
                let records = outcomeRecordsWithURLs(draftID: draft.id).map(\.1)
                guard records.count == 1, let record = records.first else { continue }
                switch record.outcome {
                case .failed:
                    _ = try markPending(draft, failedSendState: record.failedSendState)
                case .succeeded:
                    succeededDrafts.append(draft)
                }
            }
            guard !succeededDrafts.isEmpty else {
                return try loadVisibleDrafts()
            }
            for draft in succeededDrafts {
                guard await remove(draft) else {
                    throw VideoNoteFileStoreError.removalPersistenceFailed
                }
            }
        }
    }

    private func removeAbandonedFiles(referencedBy referencedURLs: Set<URL>) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles],
        ) else { return }
        let cutoff = Foundation.Date().addingTimeInterval(-24 * 60 * 60)
        for file in files where ["jpg", "mp4"].contains(file.pathExtension) && !referencedURLs.contains(file) {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if modified.map({ $0 < cutoff }) ?? true {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private static func validatedThumbnailDimensions(
        at url: URL,
    ) -> (height: Int, width: Int)? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              values.fileSize.map({ $0 > 0 && $0 < 200_000 }) == true,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) == UTType.jpeg.identifier as CFString,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0,
              width <= 320,
              height <= 320,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCache: true,
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary),
              image.width == width,
              image.height == height
        else { return nil }
        return (height, width)
    }

    #if DEBUG
        private func runDebugProbe() async {
            let chatID = Int64.min + 4_004
            var draftsToRemove = [VideoNoteSendDraft]()
            var stage = "success adopt"
            do {
                let successSource = fileManager.temporaryDirectory
                    .appendingPathComponent("video-note-draft-success-\(UUID().uuidString).mp4")
                try Data([0, 1, 2, 3]).write(to: successSource, options: .atomic)
                let successPreparation = try adoptAndPrepareEnqueue(
                    VideoNoteAsset(duration: 1, length: 400, url: successSource),
                    chatID: chatID,
                    originRecordingDraftID: nil,
                    replyMessageID: nil,
                    replyTo: nil,
                )
                guard case let .ready(successDraft) = successPreparation else {
                    throw CocoaError(.fileWriteUnknown)
                }
                draftsToRemove.append(successDraft)
                stage = "success outcome"
                _ = try await handleSendSucceeded(chatID: chatID, temporaryMessageID: -9_001)
                stage = "success register"
                let successRegistration = try await registerEnqueued(
                    successDraft,
                    temporaryMessageID: -9_001,
                )
                guard successRegistration.outcome == .succeeded,
                      !fileManager.fileExists(atPath: successDraft.fileURL.path(percentEncoded: false))
                else { throw CocoaError(.fileWriteUnknown) }
                stage = "legacy decode"
                let encodedLegacyDraft = try JSONEncoder().encode(successDraft)
                let legacyObject = try JSONSerialization.jsonObject(with: encodedLegacyDraft)
                guard let legacyDictionary = legacyObject as? [String: Any],
                      legacyDictionary["originRecordingDraftID"] == nil,
                      legacyDictionary["removalRequestedAt"] == nil,
                      legacyDictionary["thumbnailFileURL"] == nil
                else { throw CocoaError(.coderInvalidValue) }
                let legacyDraft = try JSONDecoder().decode(
                    VideoNoteSendDraft.self,
                    from: encodedLegacyDraft,
                )
                guard legacyDraft.originRecordingDraftID == nil,
                      legacyDraft.removalRequestedAt == nil,
                      legacyDraft.thumbnailFileURL == nil
                else {
                    throw CocoaError(.coderInvalidValue)
                }

                let failureSource = fileManager.temporaryDirectory
                    .appendingPathComponent("video-note-draft-failure-\(UUID().uuidString).mp4")
                let failureThumbnailSource = fileManager.temporaryDirectory
                    .appendingPathComponent("video-note-draft-failure-thumbnail-\(UUID().uuidString).jpg")
                let corruptThumbnailSource = fileManager.temporaryDirectory
                    .appendingPathComponent("video-note-draft-corrupt-thumbnail-\(UUID().uuidString).jpg")
                try Data([4, 5, 6, 7]).write(to: failureSource, options: .atomic)
                try Self.writeDebugThumbnail(to: failureThumbnailSource)
                try Data([0xff, 0xd8, 0xff, 0xd9]).write(to: corruptThumbnailSource, options: .atomic)
                stage = "corrupt thumbnail rejection"
                var rejectedCorruptThumbnail = false
                do {
                    _ = try adopt(
                        VideoNoteAsset(duration: 2, length: 400, url: failureSource),
                        thumbnail: VideoNoteInputThumbnailAsset(
                            height: 40,
                            url: corruptThumbnailSource,
                            width: 40,
                        ),
                        chatID: chatID,
                        replyMessageID: 42,
                        replyTo: nil,
                    )
                } catch VideoNoteFileStoreError.invalidThumbnail {
                    rejectedCorruptThumbnail = true
                }
                guard rejectedCorruptThumbnail,
                      fileManager.fileExists(atPath: failureSource.path(percentEncoded: false)),
                      fileManager.fileExists(atPath: corruptThumbnailSource.path(percentEncoded: false))
                else { throw CocoaError(.fileWriteUnknown) }
                try? fileManager.removeItem(at: corruptThumbnailSource)
                stage = "failure adopt"
                var failureDraft = try adopt(
                    VideoNoteAsset(duration: 2, length: 400, url: failureSource),
                    thumbnail: VideoNoteInputThumbnailAsset(
                        height: 40,
                        url: failureThumbnailSource,
                        width: 40,
                    ),
                    chatID: chatID,
                    replyMessageID: 42,
                    replyTo: nil,
                )
                draftsToRemove.append(failureDraft)
                guard let managedFailureThumbnail = failureDraft.thumbnailFileURL,
                      inputThumbnail(for: failureDraft) != nil,
                      !fileManager.fileExists(atPath: failureThumbnailSource.path(percentEncoded: false))
                else { throw CocoaError(.fileWriteUnknown) }
                stage = "failure begin"
                failureDraft = try beginEnqueue(failureDraft)
                let failedState = VideoNoteFailedSendState(
                    canRetry: true,
                    messageID: -9_002,
                    needAnotherReplyQuote: false,
                    needAnotherSender: false,
                    requiredPaidMessageStarCount: 0,
                    retryAvailableAt: Foundation.Date(),
                )
                stage = "failure outcome"
                _ = try await handleSendFailed(
                    chatID: chatID,
                    temporaryMessageID: -9_003,
                    failedSendState: failedState,
                )
                stage = "failure register"
                let failureRegistration = try await registerEnqueued(
                    failureDraft,
                    temporaryMessageID: -9_003,
                )
                stage = "failure reload"
                guard failureRegistration.outcome == .failed,
                      failureRegistration.draft.failedSendState?.messageID == -9_002,
                      await drafts(for: chatID).contains(where: { $0.id == failureDraft.id })
                else { throw CocoaError(.fileWriteUnknown) }
                await remove(failureRegistration.draft)
                guard !fileManager.fileExists(atPath: managedFailureThumbnail.path(percentEncoded: false)) else {
                    throw CocoaError(.fileWriteUnknown)
                }

                let relaunchSource = fileManager.temporaryDirectory
                    .appendingPathComponent("video-note-draft-relaunch-\(UUID().uuidString).mp4")
                try Data([8, 9, 10, 11]).write(to: relaunchSource, options: .atomic)
                stage = "relaunch adopt"
                var relaunchDraft = try adopt(
                    VideoNoteAsset(duration: 3, length: 400, url: relaunchSource),
                    chatID: chatID,
                    replyMessageID: nil,
                    replyTo: nil,
                )
                draftsToRemove.append(relaunchDraft)
                relaunchDraft = try beginEnqueue(relaunchDraft)
                registrationOwnedDraftIDs.remove(relaunchDraft.id)
                stage = "relaunch reconcile"
                let relaunchResolution = try await handleSendFailed(
                    chatID: chatID,
                    temporaryMessageID: -9_004,
                    failedSendState: failedState,
                )
                guard relaunchResolution?.outcome == .failed,
                      await drafts(for: chatID).contains(where: {
                          $0.id == relaunchDraft.id && $0.enqueueStartedAt == nil
                      })
                else { throw CocoaError(.fileWriteUnknown) }
                if let relaunchResolution {
                    await remove(relaunchResolution.draft)
                }

                let tombstoneSource = fileManager.temporaryDirectory
                    .appendingPathComponent("video-note-draft-tombstone-\(UUID().uuidString).mp4")
                try Data([12, 13, 14, 15]).write(to: tombstoneSource, options: .atomic)
                stage = "tombstone adopt"
                var tombstoneDraft = try adopt(
                    VideoNoteAsset(duration: 4, length: 400, url: tombstoneSource),
                    chatID: chatID,
                    originRecordingDraftID: UUID(),
                    replyMessageID: nil,
                    replyTo: nil,
                )
                draftsToRemove.append(tombstoneDraft)
                tombstoneDraft.removalRequestedAt = Foundation.Date()
                try save(tombstoneDraft)
                stage = "tombstone relaunch"
                let visibleAfterTombstone = await drafts(for: chatID)
                guard visibleAfterTombstone.allSatisfy({ $0.id != tombstoneDraft.id }),
                      !fileManager.fileExists(atPath: tombstoneDraft.fileURL.path(percentEncoded: false)),
                      !fileManager.fileExists(
                          atPath: manifestURL(for: tombstoneDraft.id).path(percentEncoded: false),
                      )
                else { throw CocoaError(.fileWriteUnknown) }

                let proof = "Video note draft probe: outcome-before-register success/failure, "
                    + "atomic adopt+begin, legacy-origin decode, "
                    + "durable thumbnail, relaunch reconciliation/removal-tombstone, cleanup=true"
                writeDebugProbeResult(proof)
                log(proof)
            } catch {
                draftsToRemove.forEach { _ = removeFiles(for: $0) }
                writeDebugProbeResult("Video note draft probe failed at \(stage): \(error)")
                assertionFailure("Video note draft probe failed at \(stage): \(error)")
            }
        }

        private func writeDebugProbeResult(_ result: String) {
            guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return
            }
            try? Data(result.utf8).write(
                to: documentsURL.appendingPathComponent("video-note-draft-probe.txt"),
                options: .atomic,
            )
        }

        private static func writeDebugThumbnail(to url: URL) throws {
            guard let context = CGContext(
                data: nil,
                width: 40,
                height: 40,
                bitsPerComponent: 8,
                bytesPerRow: 40 * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { throw CocoaError(.fileWriteUnknown) }
            context.setFillColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            guard let image = context.makeImage(),
                  let destination = CGImageDestinationCreateWithURL(
                      url as CFURL,
                      UTType.jpeg.identifier as CFString,
                      1,
                      nil,
                  )
            else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(destination, image, [
                kCGImageDestinationLossyCompressionQuality: 0.4,
            ] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    #endif
}
