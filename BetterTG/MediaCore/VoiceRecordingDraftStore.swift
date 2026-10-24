// VoiceRecordingDraftStore.swift

import Foundation
import TDLibKit

// MARK: - VoiceRecordingDraft

struct VoiceRecordingDraft: ChatDraftScoped, Equatable {
    let id: UUID
    let chatID: Int64
    let caption: FormattedText
    let createdAt: Foundation.Date
    var editRevision = 0
    var exactDuration: Double
    var fileURL: URL
    let replyMessageID: Int64?
    let replyTo: InputMessageReplyTo?
    var sendTopic: MessageTopic?
    var revision: Int
    var trimEnd: Double?
    var trimStart: Double?
    var waveform: Data
    var destination: ChatDraftKey?

    var effectiveRange: Range<Double> {
        let lowerBound = max(0, min(trimStart ?? 0, exactDuration))
        let upperBound = max(lowerBound, min(trimEnd ?? exactDuration, exactDuration))
        return lowerBound..<upperBound
    }
}

// MARK: - VoiceRecordingDraftManifest

private struct VoiceRecordingDraftManifest: Codable {
    let id: UUID
    let chatID: Int64
    let caption: FormattedText
    let createdAt: Foundation.Date
    let editRevision: Int?
    let exactDuration: Double
    let mediaFileName: String
    let replyMessageID: Int64?
    let replyTo: InputMessageReplyTo?
    let sendTopic: MessageTopic?
    let revision: Int
    let trimEnd: Double?
    let trimStart: Double?
    let waveform: Data
    let destination: ChatDraftKey?

    init(_ draft: VoiceRecordingDraft) {
        self.id = draft.id
        self.chatID = draft.chatID
        self.caption = draft.caption
        self.createdAt = draft.createdAt
        self.editRevision = draft.editRevision
        self.exactDuration = draft.exactDuration
        self.mediaFileName = draft.fileURL.lastPathComponent
        self.replyMessageID = draft.replyMessageID
        self.replyTo = draft.replyTo
        self.sendTopic = draft.sendTopic
        self.revision = draft.revision
        self.trimEnd = draft.trimEnd
        self.trimStart = draft.trimStart
        self.waveform = draft.waveform
        self.destination = draft.destination
    }

    func makeDraft(directoryURL: URL) -> VoiceRecordingDraft? {
        let expectedFileName = "\(id.uuidString)-\(revision).wav"
        guard mediaFileName == expectedFileName,
              URL(fileURLWithPath: mediaFileName).lastPathComponent == mediaFileName
        else { return nil }
        return VoiceRecordingDraft(
            id: id,
            chatID: chatID,
            caption: caption,
            createdAt: createdAt,
            editRevision: editRevision ?? 0,
            exactDuration: exactDuration,
            fileURL: directoryURL.appendingPathComponent(mediaFileName),
            replyMessageID: replyMessageID,
            replyTo: replyTo,
            sendTopic: sendTopic,
            revision: revision,
            trimEnd: trimEnd,
            trimStart: trimStart,
            waveform: waveform,
            destination: destination,
        )
    }
}

// MARK: - VoiceRecordingDraftStoreError

enum VoiceRecordingDraftStoreError: Swift.Error {
    case cancelled
    case missingDraft
    case staleRevision
}

// MARK: - VoiceRecordingDraftStore

actor VoiceRecordingDraftStore {
    static let shared = VoiceRecordingDraftStore()

    private let fileManager = FileManager.default
    private var cancelledDraftIDs = Set<UUID>()
    private let directoryURL: URL

    init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceRecordingDrafts", isDirectory: true)
    }

    func adopt(_ draft: VoiceRecordingDraft) throws -> VoiceRecordingDraft {
        try Task.checkCancellation()
        try ensureDirectory()
        guard !cancelledDraftIDs.contains(draft.id) else {
            try? fileManager.removeItem(at: draft.fileURL)
            throw VoiceRecordingDraftStoreError.cancelled
        }
        guard load(id: draft.id) == nil else {
            throw VoiceRecordingDraftStoreError.staleRevision
        }
        var storedDraft = draft
        storedDraft.revision = 0
        let destinationURL = mediaURL(id: draft.id, revision: storedDraft.revision)
        try? fileManager.removeItem(at: destinationURL)
        try fileManager.copyItem(at: draft.fileURL, to: destinationURL)
        storedDraft.fileURL = destinationURL
        do {
            try Task.checkCancellation()
            try save(storedDraft)
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
        try? fileManager.removeItem(at: draft.fileURL)
        return storedDraft
    }

    func replaceMedia(
        in draft: VoiceRecordingDraft,
        with sourceURL: URL,
        inspection: VoiceNotePCMInspection,
    ) throws -> VoiceRecordingDraft {
        try Task.checkCancellation()
        try ensureDirectory()
        guard !cancelledDraftIDs.contains(draft.id) else {
            try? fileManager.removeItem(at: sourceURL)
            throw VoiceRecordingDraftStoreError.cancelled
        }
        guard let canonicalDraft = load(id: draft.id) else {
            throw VoiceRecordingDraftStoreError.missingDraft
        }
        guard canonicalDraft.revision == draft.revision, canonicalDraft.editRevision == draft.editRevision else {
            throw VoiceRecordingDraftStoreError.staleRevision
        }
        var updatedDraft = canonicalDraft
        updatedDraft.editRevision += 1
        updatedDraft.exactDuration = inspection.duration
        updatedDraft.revision += 1
        updatedDraft.trimStart = nil
        updatedDraft.trimEnd = nil
        updatedDraft.waveform = inspection.waveform
        let destinationURL = mediaURL(id: draft.id, revision: updatedDraft.revision)
        try? fileManager.removeItem(at: destinationURL)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        updatedDraft.fileURL = destinationURL
        do {
            try Task.checkCancellation()
            try save(updatedDraft)
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
        if canonicalDraft.fileURL != destinationURL {
            try? fileManager.removeItem(at: canonicalDraft.fileURL)
        }
        try? fileManager.removeItem(at: sourceURL)
        return updatedDraft
    }

    func updateTrim(
        in draft: VoiceRecordingDraft,
        range: Range<Double>,
    ) throws -> VoiceRecordingDraft {
        try Task.checkCancellation()
        guard !cancelledDraftIDs.contains(draft.id) else {
            throw VoiceRecordingDraftStoreError.cancelled
        }
        guard let canonicalDraft = load(id: draft.id) else {
            throw VoiceRecordingDraftStoreError.missingDraft
        }
        guard canonicalDraft.revision == draft.revision,
              canonicalDraft.editRevision == draft.editRevision, range.lowerBound >= 0,
              range.lowerBound < range.upperBound,
              range.upperBound <= canonicalDraft.exactDuration
        else { throw VoiceRecordingDraftStoreError.staleRevision }
        var updatedDraft = canonicalDraft
        updatedDraft.editRevision += 1
        if range.lowerBound <= 0.000_001,
           abs(range.upperBound - canonicalDraft.exactDuration) <= 0.000_001
        {
            updatedDraft.trimStart = nil
            updatedDraft.trimEnd = nil
        } else {
            updatedDraft.trimStart = range.lowerBound
            updatedDraft.trimEnd = range.upperBound
        }
        try Task.checkCancellation()
        try save(updatedDraft)
        return updatedDraft
    }

    func drafts(for chatID: Int64) -> [VoiceRecordingDraft] {
        do {
            try ensureDirectory()
            let drafts = try loadAllDrafts()
            removeAbandonedFiles(referencedBy: Set(drafts.map(\.fileURL)))
            return drafts.filter { $0.chatID == chatID }.sorted { $0.createdAt < $1.createdAt }
        } catch {
            log("Voice recording draft load failed: \(error)")
            return []
        }
    }

    func drafts(
        for destination: ChatDraftKey,
        migrateLegacy: Bool = false,
    ) -> [VoiceRecordingDraft] {
        do {
            try ensureDirectory()
            let shouldMigrateLegacy = migrateLegacy
                && ChatDraftLegacyMigrationPolicy.canBindLegacyDrafts(to: destination)
            var drafts = try loadAllDrafts()
            for index in drafts.indices where drafts[index].belongs(
                to: destination,
                allowingLegacy: shouldMigrateLegacy,
            ) {
                if drafts[index].destination == nil {
                    drafts[index].destination = destination
                    try save(drafts[index])
                }
            }
            removeAbandonedFiles(referencedBy: Set(drafts.map(\.fileURL)))
            return drafts
                .filter { $0.destination == destination }
                .sorted { $0.createdAt < $1.createdAt }
        } catch {
            log("Voice recording scoped draft load failed: \(error)")
            return []
        }
    }

    func discard(id: UUID) {
        cancelledDraftIDs.insert(id)
        if let draft = load(id: id) {
            try? fileManager.removeItem(at: draft.fileURL)
        }
        try? fileManager.removeItem(at: manifestURL(for: id))
    }

    /// Logging out removes the account's drafts with its TDLib directory; drafts never bound to an account stay.
    func discardAccount(_ accountID: UUID) {
        guard let drafts = try? loadAllDrafts() else { return }
        for draft in drafts where draft.destination?.accountID == accountID {
            discard(id: draft.id)
        }
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func manifestURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private func mediaURL(id: UUID, revision: Int) -> URL {
        directoryURL.appendingPathComponent("\(id.uuidString)-\(revision)").appendingPathExtension("wav")
    }

    private func save(_ draft: VoiceRecordingDraft) throws {
        guard isManagedFile(draft.fileURL), fileManager.fileExists(atPath: draft.fileURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try JSONEncoder().encode(VoiceRecordingDraftManifest(draft))
        try data.write(to: manifestURL(for: draft.id), options: .atomic)
    }

    private func load(id: UUID) -> VoiceRecordingDraft? {
        guard let data = try? Data(contentsOf: manifestURL(for: id)),
              let manifest = try? JSONDecoder().decode(VoiceRecordingDraftManifest.self, from: data),
              manifest.id == id,
              let draft = manifest.makeDraft(directoryURL: directoryURL),
              isManagedFile(draft.fileURL),
              fileManager.fileExists(atPath: draft.fileURL.path)
        else { return nil }
        return draft
    }

    private func loadAllDrafts() throws -> [VoiceRecordingDraft] {
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

    private func isManagedFile(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(directoryURL.standardizedFileURL.path + "/")
    }

    private func removeAbandonedFiles(referencedBy referencedURLs: Set<URL>) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles],
        ) else { return }
        let cutoff = Foundation.Date().addingTimeInterval(-24 * 60 * 60)
        for file in files where file.pathExtension == "wav" && !referencedURLs.contains(file) {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if modified.map({ $0 < cutoff }) ?? true {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
