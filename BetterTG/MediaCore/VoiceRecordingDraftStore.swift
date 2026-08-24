// VoiceRecordingDraftStore.swift

import Foundation
import TDLibKit

struct VoiceRecordingDraft: Equatable {
    let id: UUID
    let chatID: Int64
    let caption: FormattedText
    let createdAt: Foundation.Date
    var exactDuration: Double
    var fileURL: URL
    let replyMessageID: Int64?
    let replyTo: InputMessageReplyTo?
    var revision: Int
    var trimEnd: Double?
    var trimStart: Double?
    var waveform: Data

    var effectiveRange: Range<Double> {
        let lowerBound = max(0, min(trimStart ?? 0, exactDuration))
        let upperBound = max(lowerBound, min(trimEnd ?? exactDuration, exactDuration))
        return lowerBound ..< upperBound
    }
}

private struct VoiceRecordingDraftManifest: Codable {
    let id: UUID
    let chatID: Int64
    let caption: FormattedText
    let createdAt: Foundation.Date
    let exactDuration: Double
    let mediaFileName: String
    let replyMessageID: Int64?
    let replyTo: InputMessageReplyTo?
    let revision: Int
    let trimEnd: Double?
    let trimStart: Double?
    let waveform: Data

    init(_ draft: VoiceRecordingDraft) {
        id = draft.id
        chatID = draft.chatID
        caption = draft.caption
        createdAt = draft.createdAt
        exactDuration = draft.exactDuration
        mediaFileName = draft.fileURL.lastPathComponent
        replyMessageID = draft.replyMessageID
        replyTo = draft.replyTo
        revision = draft.revision
        trimEnd = draft.trimEnd
        trimStart = draft.trimStart
        waveform = draft.waveform
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
            exactDuration: exactDuration,
            fileURL: directoryURL.appendingPathComponent(mediaFileName),
            replyMessageID: replyMessageID,
            replyTo: replyTo,
            revision: revision,
            trimEnd: trimEnd,
            trimStart: trimStart,
            waveform: waveform,
        )
    }
}

enum VoiceRecordingDraftStoreError: Swift.Error {
    case cancelled
    case missingDraft
    case staleRevision
}

actor VoiceRecordingDraftStore {
    static let shared = VoiceRecordingDraftStore()

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
        guard canonicalDraft.revision == draft.revision else {
            throw VoiceRecordingDraftStoreError.staleRevision
        }
        var updatedDraft = canonicalDraft
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

    func discard(id: UUID) {
        cancelledDraftIDs.insert(id)
        if let draft = load(id: id) {
            try? fileManager.removeItem(at: draft.fileURL)
        }
        try? fileManager.removeItem(at: manifestURL(for: id))
    }

    private let fileManager = FileManager.default
    private var cancelledDraftIDs = Set<UUID>()
    private lazy var directoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("VoiceRecordingDrafts", isDirectory: true)

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
