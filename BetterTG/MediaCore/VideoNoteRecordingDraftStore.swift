// VideoNoteRecordingDraftStore.swift

import AVFoundation
import Foundation
@preconcurrency import TDLibKit

// MARK: - VideoNoteRecordingSegment

struct VideoNoteRecordingSegment: Equatable {
    let id: UUID
    let duration: Double
    let fileURL: URL
    let length: Int

    var asset: VideoNoteAsset {
        VideoNoteAsset(duration: duration, length: length, url: fileURL)
    }
}

// MARK: - VideoNoteRecordingDraft

struct VideoNoteRecordingDraft: ChatDraftScoped, Equatable {
    let id: UUID
    let chatID: Int64
    let createdAt: Foundation.Date
    let replyMessageID: Int64?
    let replyTo: InputMessageReplyTo?
    var sendTopic: MessageTopic?
    var revision: Int
    var segments: [VideoNoteRecordingSegment]
    var trimEnd: Double?
    var trimStart: Double?
    var destination: ChatDraftKey?

    var totalDuration: Double {
        segments.reduce(0) { $0 + $1.duration }
    }

    var effectiveRange: Range<Double> {
        let duration = totalDuration
        let lowerBound = min(duration, max(0, trimStart ?? 0))
        let upperBound = min(duration, max(lowerBound, trimEnd ?? duration))
        return lowerBound..<upperBound
    }

    var canRecordMore: Bool {
        totalDuration < 59
    }

    var assets: [VideoNoteAsset] {
        segments.map(\.asset)
    }
}

// MARK: - VideoNoteRecordingSegmentManifest

private struct VideoNoteRecordingSegmentManifest: Codable {
    let id: UUID
    let duration: Double
    let fileName: String
    let length: Int

    init(_ segment: VideoNoteRecordingSegment) {
        self.id = segment.id
        self.duration = segment.duration
        self.fileName = segment.fileURL.lastPathComponent
        self.length = segment.length
    }

    func makeSegment(directoryURL: URL) -> VideoNoteRecordingSegment? {
        guard fileName == "\(id.uuidString).mp4",
              URL(fileURLWithPath: fileName).lastPathComponent == fileName,
              duration.isFinite,
              duration > 0,
              length == 400
        else { return nil }
        return VideoNoteRecordingSegment(
            id: id,
            duration: duration,
            fileURL: directoryURL.appendingPathComponent(fileName),
            length: length,
        )
    }
}

// MARK: - VideoNoteRecordingDraftManifest

private struct VideoNoteRecordingDraftManifest: Codable {
    let id: UUID
    let chatID: Int64
    let createdAt: Foundation.Date
    let replyMessageID: Int64?
    let replyTo: InputMessageReplyTo?
    let sendTopic: MessageTopic?
    let revision: Int
    let segments: [VideoNoteRecordingSegmentManifest]
    let trimEnd: Double?
    let trimStart: Double?
    let destination: ChatDraftKey?

    init(_ draft: VideoNoteRecordingDraft) {
        self.id = draft.id
        self.chatID = draft.chatID
        self.createdAt = draft.createdAt
        self.replyMessageID = draft.replyMessageID
        self.replyTo = draft.replyTo
        self.sendTopic = draft.sendTopic
        self.revision = draft.revision
        self.segments = draft.segments.map(VideoNoteRecordingSegmentManifest.init)
        self.trimEnd = draft.trimEnd
        self.trimStart = draft.trimStart
        self.destination = draft.destination
    }

    func makeDraft(directoryURL: URL) -> VideoNoteRecordingDraft? {
        let resolvedSegments = segments.compactMap { $0.makeSegment(directoryURL: directoryURL) }
        guard !resolvedSegments.isEmpty,
              resolvedSegments.count == segments.count,
              Set(resolvedSegments.map(\.id)).count == resolvedSegments.count
        else { return nil }
        let draft = VideoNoteRecordingDraft(
            id: id,
            chatID: chatID,
            createdAt: createdAt,
            replyMessageID: replyMessageID,
            replyTo: replyTo,
            sendTopic: sendTopic,
            revision: revision,
            segments: resolvedSegments,
            trimEnd: trimEnd,
            trimStart: trimStart,
            destination: destination,
        )
        let range = draft.effectiveRange
        let hasExplicitTrim = trimStart != nil || trimEnd != nil
        guard draft.totalDuration >= 0.5,
              draft.totalDuration <= 60.01,
              range.lowerBound >= 0,
              range.upperBound <= draft.totalDuration,
              !hasExplicitTrim || range.upperBound - range.lowerBound >= 1 - 0.000_001
        else { return nil }
        return draft
    }
}

// MARK: - VideoNoteRecordingDraftStoreError

enum VideoNoteRecordingDraftStoreError: Swift.Error {
    case cancelled
    case invalidAsset
    case missingDraft
    case staleRevision
}

// MARK: - VideoNoteRecordingDraftStore

actor VideoNoteRecordingDraftStore {
    static let shared = VideoNoteRecordingDraftStore()

    private let fileManager = FileManager.default
    private var activeOperationCounts = [UUID: Int]()
    private var cancelledDraftIDs = Set<UUID>()
    private var deferredDiscardURLs = [UUID: [URL]]()
    private let directoryURL: URL
    private let adoptedRecordingOrigins: @Sendable () async throws -> Set<UUID>

    #if DEBUG
        private var beforeCaptureSaveProbe: (@Sendable () async -> Void)?

        func setBeforeCaptureSaveProbe(_ operation: (@Sendable () async -> Void)?) {
            beforeCaptureSaveProbe = operation
        }

        nonisolated static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains(
                "-media-probe-video-note-recording-drafts",
            ) else { return }
            Task { await shared.runDebugProbe() }
        }
    #endif

    init(
        directoryURL: URL? = nil,
        adoptedRecordingOrigins: @escaping @Sendable () async throws -> Set<UUID> = {
            try VideoNoteFileStore.shared.recordingDraftOrigins()
        },
    ) {
        self.directoryURL = directoryURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VideoNoteRecordingDrafts", isDirectory: true)
        self.adoptedRecordingOrigins = adoptedRecordingOrigins
    }

    func adopt(
        _ asset: VideoNoteAsset,
        chatID: Int64,
        draftKey: ChatDraftKey? = nil,
        replyMessageID: Int64?,
        replyTo: InputMessageReplyTo?,
        sendTopic: MessageTopic? = nil,
    ) async throws -> VideoNoteRecordingDraft {
        let validated = try await VideoNoteAssetWriter.validate(url: asset.url, expectedLength: 400)
        #if DEBUG
            await beforeCaptureSaveProbe?()
        #endif
        try Task.checkCancellation()
        try ensureDirectory()
        guard validated.duration >= 0.5,
              !isManagedFile(asset.url)
        else { throw VideoNoteRecordingDraftStoreError.invalidAsset }
        let draftID = UUID()
        let segment = VideoNoteRecordingSegment(
            id: UUID(),
            duration: validated.duration,
            fileURL: asset.url,
            length: validated.length,
        )
        var draft = VideoNoteRecordingDraft(
            id: draftID,
            chatID: chatID,
            createdAt: Foundation.Date(),
            replyMessageID: replyMessageID,
            replyTo: replyTo,
            sendTopic: sendTopic,
            revision: 0,
            segments: [segment],
            trimEnd: nil,
            trimStart: nil,
            destination: draftKey,
        )
        let destination = segmentURL(id: segment.id)
        try? fileManager.removeItem(at: destination)
        try fileManager.copyItem(at: asset.url, to: destination)
        draft.segments[0] = VideoNoteRecordingSegment(
            id: segment.id,
            duration: segment.duration,
            fileURL: destination,
            length: segment.length,
        )
        do {
            try Task.checkCancellation()
            try save(draft)
        } catch {
            if let persisted = load(id: draft.id), persisted.revision == draft.revision {
                try? fileManager.removeItem(at: asset.url)
                return persisted
            }
            try? fileManager.removeItem(at: destination)
            throw error
        }
        try? fileManager.removeItem(at: asset.url)
        return draft
    }

    func append(
        _ asset: VideoNoteAsset,
        to draft: VideoNoteRecordingDraft,
    ) async throws -> VideoNoteRecordingDraft {
        let validated = try await VideoNoteAssetWriter.validate(url: asset.url, expectedLength: 400)
        #if DEBUG
            await beforeCaptureSaveProbe?()
        #endif
        try Task.checkCancellation()
        guard validated.duration >= 0.5,
              !isManagedFile(asset.url)
        else {
            throw VideoNoteRecordingDraftStoreError.invalidAsset
        }
        guard !cancelledDraftIDs.contains(draft.id) else {
            try? fileManager.removeItem(at: asset.url)
            throw VideoNoteRecordingDraftStoreError.cancelled
        }
        guard let canonical = load(id: draft.id) else {
            throw VideoNoteRecordingDraftStoreError.missingDraft
        }
        guard canonical.revision == draft.revision,
              canonical.canRecordMore,
              canonical.totalDuration + validated.duration <= 60.01
        else { throw VideoNoteRecordingDraftStoreError.staleRevision }
        let segmentID = UUID()
        let segment = VideoNoteRecordingSegment(
            id: segmentID,
            duration: validated.duration,
            fileURL: segmentURL(id: segmentID),
            length: validated.length,
        )
        let destination = segmentURL(id: segment.id)
        var updated = canonical
        updated.revision += 1
        updated.segments.append(VideoNoteRecordingSegment(
            id: segment.id,
            duration: segment.duration,
            fileURL: destination,
            length: segment.length,
        ))
        updated.trimStart = nil
        updated.trimEnd = nil
        try? fileManager.removeItem(at: destination)
        try fileManager.copyItem(at: asset.url, to: destination)
        do {
            try Task.checkCancellation()
            try save(updated)
        } catch {
            if let persisted = load(id: updated.id), persisted.revision == updated.revision {
                try? fileManager.removeItem(at: asset.url)
                return persisted
            }
            try? fileManager.removeItem(at: destination)
            throw error
        }
        try? fileManager.removeItem(at: asset.url)
        return updated
    }

    func updateTrim(
        in draft: VideoNoteRecordingDraft,
        range: Range<Double>,
    ) throws -> VideoNoteRecordingDraft {
        try Task.checkCancellation()
        guard !cancelledDraftIDs.contains(draft.id) else {
            throw VideoNoteRecordingDraftStoreError.cancelled
        }
        guard let canonical = load(id: draft.id) else {
            throw VideoNoteRecordingDraftStoreError.missingDraft
        }
        var normalizedLowerBound = range.lowerBound
        var normalizedUpperBound = range.upperBound
        let requestedDuration = normalizedUpperBound - normalizedLowerBound
        if requestedDuration >= 1 - 0.000_001, requestedDuration < 1 {
            if normalizedLowerBound + 1 <= canonical.totalDuration {
                normalizedUpperBound = normalizedLowerBound + 1
            } else {
                normalizedLowerBound = max(0, normalizedUpperBound - 1)
            }
        }
        guard canonical.revision == draft.revision,
              normalizedLowerBound >= 0,
              normalizedUpperBound <= canonical.totalDuration,
              normalizedUpperBound - normalizedLowerBound >= 1 - 0.000_001,
              normalizedUpperBound - normalizedLowerBound <= 60
        else { throw VideoNoteRecordingDraftStoreError.staleRevision }
        let normalizedRange = normalizedLowerBound..<normalizedUpperBound
        var updated = canonical
        updated.revision += 1
        if normalizedRange.lowerBound <= 0.000_001,
           abs(normalizedRange.upperBound - canonical.totalDuration) <= 0.000_001
        {
            updated.trimStart = nil
            updated.trimEnd = nil
        } else {
            updated.trimStart = normalizedRange.lowerBound
            updated.trimEnd = normalizedRange.upperBound
        }
        try save(updated)
        return updated
    }

    func composition(for draft: VideoNoteRecordingDraft) async throws -> VideoNoteCompositionResult {
        let canonical = try beginOperation(draft)
        defer { endOperation(id: draft.id) }
        let result = try await VideoNoteSegmentComposer.compose(canonical.assets)
        try Task.checkCancellation()
        try validateOperation(canonical)
        return result
    }

    func thumbnails(for draft: VideoNoteRecordingDraft) async throws -> [VideoNoteThumbnailSample] {
        let canonical = try beginOperation(draft)
        defer { endOperation(id: draft.id) }
        let result = try await VideoNoteSegmentComposer.thumbnails(for: canonical.assets)
        try Task.checkCancellation()
        try validateOperation(canonical)
        return result
    }

    func preview(for draft: VideoNoteRecordingDraft) async throws -> VideoNoteRecordingPreview {
        let canonical = try beginOperation(draft)
        defer { endOperation(id: draft.id) }
        let composition = try await VideoNoteSegmentComposer.compose(canonical.assets)
        let thumbnails = try await VideoNoteSegmentComposer.thumbnails(for: composition)
        try Task.checkCancellation()
        try validateOperation(canonical)
        return VideoNoteRecordingPreview(composition: composition, thumbnails: thumbnails)
    }

    func materialize(
        _ draft: VideoNoteRecordingDraft,
        outputURL: URL,
    ) async throws -> VideoNoteAsset {
        guard !isManagedFile(outputURL) else {
            throw VideoNoteRecordingDraftStoreError.invalidAsset
        }
        let canonical = try beginOperation(draft)
        defer { endOperation(id: draft.id) }
        let result = try await VideoNoteSegmentComposer.materialize(
            segments: canonical.assets,
            trimRange: canonical.effectiveRange,
            outputURL: outputURL,
        )
        do {
            try Task.checkCancellation()
            try validateOperation(canonical)
            return result
        } catch {
            try? fileManager.removeItem(at: outputURL)
            throw error
        }
    }

    func drafts(for chatID: Int64) async -> [VideoNoteRecordingDraft] {
        do {
            try ensureDirectory()
            let adoptedOrigins = try await adoptedRecordingOrigins()
            var drafts = try loadAllDrafts()
            for draft in drafts where adoptedOrigins.contains(draft.id) {
                if !discard(id: draft.id) {
                    log("Video note recording manifest cleanup will retry: \(draft.id)")
                }
            }
            drafts.removeAll { adoptedOrigins.contains($0.id) }
            removeAbandonedFiles(referencedBy: Set(drafts.flatMap { $0.segments.map(\.fileURL) }))
            return drafts.filter { $0.chatID == chatID }.sorted { $0.createdAt < $1.createdAt }
        } catch {
            log("Video note recording draft load failed: \(error)")
            return []
        }
    }

    func drafts(
        for destination: ChatDraftKey,
        migrateLegacy: Bool = false,
    ) async -> [VideoNoteRecordingDraft] {
        do {
            try ensureDirectory()
            let shouldMigrateLegacy = migrateLegacy
                && ChatDraftLegacyMigrationPolicy.canBindLegacyDrafts(to: destination)
            let adoptedOrigins = try await adoptedRecordingOrigins()
            var drafts = try loadAllDrafts()
            for draft in drafts where adoptedOrigins.contains(draft.id) {
                if !discard(id: draft.id) {
                    log("Video note recording manifest cleanup will retry: \(draft.id)")
                }
            }
            drafts.removeAll { adoptedOrigins.contains($0.id) }
            for index in drafts.indices where drafts[index].belongs(
                to: destination,
                allowingLegacy: shouldMigrateLegacy,
            ) {
                if drafts[index].destination == nil {
                    drafts[index].destination = destination
                    try save(drafts[index])
                }
            }
            removeAbandonedFiles(referencedBy: Set(drafts.flatMap { $0.segments.map(\.fileURL) }))
            return drafts
                .filter { $0.destination == destination }
                .sorted { $0.createdAt < $1.createdAt }
        } catch {
            log("Video note recording scoped draft load failed: \(error)")
            return []
        }
    }

    @discardableResult func discard(id: UUID) -> Bool {
        cancelledDraftIDs.insert(id)
        let segmentURLs = load(id: id)?.segments.map(\.fileURL) ?? []
        let manifestURL = manifestURL(for: id)
        do {
            if fileManager.fileExists(atPath: manifestURL.path(percentEncoded: false)) {
                try fileManager.removeItem(at: manifestURL)
            }
        } catch {
            log("Video note recording manifest cleanup failed: \(error)")
            return false
        }
        guard activeOperationCounts[id, default: 0] == 0 else {
            deferredDiscardURLs[id] = Array(Set(deferredDiscardURLs[id, default: []]).union(segmentURLs))
            return true
        }
        segmentURLs.forEach { try? fileManager.removeItem(at: $0) }
        return true
    }

    /// Logging out removes the account's drafts with its TDLib directory; drafts never bound to an account stay.
    func discardAccount(_ accountID: UUID) {
        guard let drafts = try? loadAllDrafts() else { return }
        for draft in drafts where draft.destination?.accountID == accountID {
            discard(id: draft.id)
        }
    }

    private func beginOperation(_ draft: VideoNoteRecordingDraft) throws -> VideoNoteRecordingDraft {
        guard !cancelledDraftIDs.contains(draft.id) else {
            throw VideoNoteRecordingDraftStoreError.cancelled
        }
        guard let canonical = load(id: draft.id),
              canonical.revision == draft.revision
        else { throw VideoNoteRecordingDraftStoreError.staleRevision }
        activeOperationCounts[draft.id, default: 0] += 1
        return canonical
    }

    private func endOperation(id: UUID) {
        let remaining = max(0, activeOperationCounts[id, default: 1] - 1)
        if remaining == 0 {
            activeOperationCounts.removeValue(forKey: id)
        } else {
            activeOperationCounts[id] = remaining
        }
        if remaining == 0, cancelledDraftIDs.contains(id) {
            removeDraft(id: id)
        }
    }

    private func validateOperation(_ canonical: VideoNoteRecordingDraft) throws {
        guard !cancelledDraftIDs.contains(canonical.id) else {
            throw VideoNoteRecordingDraftStoreError.cancelled
        }
        guard let latest = load(id: canonical.id),
              latest.revision == canonical.revision
        else { throw VideoNoteRecordingDraftStoreError.staleRevision }
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        )
    }

    private func manifestURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private func segmentURL(id: UUID) -> URL {
        directoryURL.appendingPathComponent(id.uuidString).appendingPathExtension("mp4")
    }

    private func save(_ draft: VideoNoteRecordingDraft) throws {
        guard !draft.segments.isEmpty,
              draft.segments.allSatisfy({
                  isManagedFile($0.fileURL)
                      && fileManager.fileExists(atPath: $0.fileURL.path(percentEncoded: false))
              })
        else { throw VideoNoteRecordingDraftStoreError.invalidAsset }
        let data = try JSONEncoder().encode(VideoNoteRecordingDraftManifest(draft))
        try data.write(to: manifestURL(for: draft.id), options: .atomic)
    }

    private func load(id: UUID) -> VideoNoteRecordingDraft? {
        guard let data = try? Data(contentsOf: manifestURL(for: id)),
              let manifest = try? JSONDecoder().decode(VideoNoteRecordingDraftManifest.self, from: data),
              manifest.id == id,
              let draft = manifest.makeDraft(directoryURL: directoryURL),
              draft.segments.allSatisfy({
                  isManagedFile($0.fileURL)
                      && fileManager.fileExists(atPath: $0.fileURL.path(percentEncoded: false))
              })
        else { return nil }
        return draft
    }

    private func loadAllDrafts() throws -> [VideoNoteRecordingDraft] {
        let files = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
        )
        return files.compactMap { url in
            guard url.pathExtension == "json",
                  let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent)
            else { return nil }
            guard let draft = load(id: id) else {
                try? fileManager.removeItem(at: url)
                return nil
            }
            return draft
        }
    }

    private func removeDraft(id: UUID) {
        let urls = deferredDiscardURLs.removeValue(forKey: id)
            ?? load(id: id)?.segments.map(\.fileURL)
            ?? []
        urls.forEach { try? fileManager.removeItem(at: $0) }
        try? fileManager.removeItem(at: manifestURL(for: id))
    }

    private func isManagedFile(_ url: URL) -> Bool {
        let root = directoryURL.resolvingSymlinksInPath().standardizedFileURL
        let candidate = url.resolvingSymlinksInPath().standardizedFileURL
        return candidate == root || candidate.path.hasPrefix(root.path + "/")
    }

    private func removeAbandonedFiles(referencedBy urls: Set<URL>) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles],
        ) else { return }
        let cutoff = Foundation.Date().addingTimeInterval(-24 * 60 * 60)
        for file in files where file.pathExtension == "mp4" && !urls.contains(file) {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if modified.map({ $0 < cutoff }) ?? true {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    #if DEBUG
        private func runDebugProbe() async {
            let chatID = Int64.min + 4005
            let firstURL = fileManager.temporaryDirectory
                .appendingPathComponent("video-note-recording-a-\(UUID().uuidString).mp4")
            let secondURL = fileManager.temporaryDirectory
                .appendingPathComponent("video-note-recording-b-\(UUID().uuidString).mp4")
            let outputURL = fileManager.temporaryDirectory
                .appendingPathComponent("video-note-recording-output-\(UUID().uuidString).mp4")
            let redundantURL = fileManager.temporaryDirectory
                .appendingPathComponent("video-note-recording-redundant-\(UUID().uuidString).mp4")
            var draftID: UUID?
            var sendDraft: VideoNoteSendDraft?
            defer {
                if let draftID { discard(id: draftID) }
                if let sendDraft {
                    Task { await VideoNoteFileStore.shared.remove(sendDraft) }
                }
                for item in [firstURL, secondURL, outputURL, redundantURL] {
                    try? fileManager.removeItem(at: item)
                }
            }
            var stage = "segments"
            do {
                let frozenSendTopic = MessageTopic.messageTopicForum(MessageTopicForum(forumTopicId: 77))
                async let first = VideoNoteAssetWriter.makeDebugSegment(
                    outputURL: firstURL,
                    duration: 0.7,
                    frameSeed: 5,
                )
                async let second = VideoNoteAssetWriter.makeDebugSegment(
                    outputURL: secondURL,
                    duration: 1,
                    frameSeed: 80,
                )
                let assets = try await [first, second]
                stage = "adopt"
                var draft = try await adopt(
                    assets[0],
                    chatID: chatID,
                    replyMessageID: 77,
                    replyTo: nil,
                    sendTopic: frozenSendTopic,
                )
                draftID = draft.id
                guard !fileManager.fileExists(atPath: firstURL.path(percentEncoded: false)),
                      draft.revision == 0,
                      draft.segments.count == 1,
                      abs(draft.totalDuration - 0.7) < 0.03,
                      await drafts(for: chatID).contains(where: {
                          $0.id == draft.id && abs($0.totalDuration - 0.7) < 0.03
                      })
                else { throw VideoNoteRecordingDraftStoreError.invalidAsset }
                let shortPreview = try await composition(for: draft)
                guard abs(shortPreview.duration - 0.7) < 0.03 else {
                    throw VideoNoteRecordingDraftStoreError.invalidAsset
                }
                stage = "append"
                draft = try await append(assets[1], to: draft)
                guard !fileManager.fileExists(atPath: secondURL.path(percentEncoded: false)),
                      draft.revision == 1,
                      draft.segments.count == 2,
                      draft.trimStart == nil,
                      draft.trimEnd == nil,
                      abs(draft.totalDuration - 1.7) < 0.04
                else { throw VideoNoteRecordingDraftStoreError.invalidAsset }
                stage = "trim"
                draft = try updateTrim(in: draft, range: 0.2..<1.4)
                guard draft.revision == 2,
                      abs(draft.effectiveRange.lowerBound - 0.2) < 0.001,
                      abs(draft.effectiveRange.upperBound - 1.4) < 0.001
                else { throw VideoNoteRecordingDraftStoreError.staleRevision }
                stage = "reload"
                guard let restored = await drafts(for: chatID).first(where: { $0.id == draft.id }),
                      restored.segments.map(\.id) == draft.segments.map(\.id),
                      restored.revision == draft.revision,
                      restored.replyMessageID == 77,
                      restored.sendTopic == frozenSendTopic
                else { throw VideoNoteRecordingDraftStoreError.missingDraft }
                stage = "derivations"
                let derivedPreview = try await preview(for: restored)
                guard derivedPreview.composition.segmentRanges.count == 2,
                      derivedPreview.thumbnails.count == 13
                else { throw VideoNoteRecordingDraftStoreError.invalidAsset }
                stage = "materialization"
                let materialized = try await materialize(restored, outputURL: outputURL)
                guard abs(materialized.duration - 1.2) < 0.05 else {
                    throw VideoNoteRecordingDraftStoreError.invalidAsset
                }
                stage = "origin handoff"
                let adoptedSendDraft = try await VideoNoteFileStore.shared.adopt(
                    materialized,
                    chatID: chatID,
                    originRecordingDraftID: draft.id,
                    replyMessageID: draft.replyMessageID,
                    replyTo: draft.replyTo,
                    sendTopic: draft.sendTopic,
                )
                sendDraft = adoptedSendDraft
                try fileManager.copyItem(at: adoptedSendDraft.fileURL, to: redundantURL)
                let deduplicatedSendDraft = try await VideoNoteFileStore.shared.adopt(
                    VideoNoteAsset(
                        duration: materialized.duration,
                        length: materialized.length,
                        url: redundantURL,
                    ),
                    chatID: chatID,
                    originRecordingDraftID: draft.id,
                    replyMessageID: draft.replyMessageID,
                    replyTo: draft.replyTo,
                    sendTopic: draft.sendTopic,
                )
                let originIDs = try await VideoNoteFileStore.shared.recordingDraftOrigins()
                guard originIDs.contains(draft.id),
                      deduplicatedSendDraft.id == adoptedSendDraft.id,
                      !fileManager.fileExists(atPath: redundantURL.path(percentEncoded: false))
                else {
                    throw VideoNoteRecordingDraftStoreError.invalidAsset
                }
                stage = "origin barrier"
                let visibleDrafts = await drafts(for: chatID)
                draftID = nil
                guard visibleDrafts.allSatisfy({ $0.id != draft.id }),
                      draft.segments.allSatisfy({
                          !fileManager.fileExists(atPath: $0.fileURL.path(percentEncoded: false))
                      })
                else { throw VideoNoteRecordingDraftStoreError.invalidAsset }
                await VideoNoteFileStore.shared.remove(adoptedSendDraft)
                sendDraft = nil
                let proof = "Video note recording draft probe: ordered=2, revision=2, "
                    + "short-preview=0.7, trim=1.2, preview-lease/thumbnails=13, "
                    + "frozen-topic/origin-dedupe/barrier/reload/discard=true"
                writeDebugProbeResult(proof)
                log(proof)
            } catch {
                if let pendingSendDraft = sendDraft {
                    await VideoNoteFileStore.shared.remove(pendingSendDraft)
                    sendDraft = nil
                }
                writeDebugProbeResult("Video note recording draft probe failed at \(stage): \(error)")
                assertionFailure("Video note recording draft probe failed at \(stage): \(error)")
            }
        }

        private func writeDebugProbeResult(_ result: String) {
            guard let documentsURL = fileManager.urls(
                for: .documentDirectory,
                in: .userDomainMask,
            )
.first else { return }
            try? Data(result.utf8).write(
                to: documentsURL.appendingPathComponent("video-note-recording-draft-probe.txt"),
                options: .atomic,
            )
        }
    #endif
}
