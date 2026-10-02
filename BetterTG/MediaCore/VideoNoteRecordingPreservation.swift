// VideoNoteRecordingPreservation.swift

import Foundation
import TDLibKitDynamic

// MARK: - VideoNoteRecordingPreservation

@MainActor enum VideoNoteRecordingPreservation {
    private static var pending = [ChatDraftKey: [UUID: Task<Void, Never>]]()

    static func preserve(_ finalization: VideoNoteCaptureFinalization) {
        let key = finalization.destination
        let id = finalization.generation
        guard pending[key]?[id] == nil else { return }
        pending[key, default: [:]][id] = Task {
            _ = await finalization.value()
            pending[key]?[id] = nil
            if pending[key]?.isEmpty == true { pending[key] = nil }
        }
    }

    static func wait(for destination: ChatDraftKey) async {
        while !Task.isCancelled, let tasks = pending[destination] {
            for task in tasks.values {
                await task.value
            }
        }
    }
}

// MARK: - VideoNoteCaptureFinalization

/// Owns the canonical save independently of recorder UI tasks. Raw capture output
/// has one consumer; joiners receive only the committed draft result.
@MainActor final class VideoNoteCaptureFinalization {
    let generation: UUID
    let destination: ChatDraftKey
    let baseDraft: VideoNoteRecordingDraft?
    private(set) var isPreserving = false
    private(set) var isDiscarded = false
    private(set) var finishRequested = false

    private let store: VideoNoteRecordingDraftStore
    private let replyMessageID: Int64?
    private let replyTo: InputMessageReplyTo?
    private let sendTopic: MessageTopic?
    private var saveTask: Task<Void, Never>?
    private var acceptedAssetURL: URL?
    private var result: Result<VideoNoteRecordingDraft, Swift.Error>?
    private var waiters = [CheckedContinuation<Result<VideoNoteRecordingDraft, Swift.Error>, Never>]()

    var isComplete: Bool { result != nil }

    init(
        generation: UUID,
        destination: ChatDraftKey,
        baseDraft: VideoNoteRecordingDraft?,
        replyMessageID: Int64?,
        replyTo: InputMessageReplyTo?,
        sendTopic: MessageTopic?,
        store: VideoNoteRecordingDraftStore,
    ) {
        self.generation = generation
        self.destination = destination
        self.baseDraft = baseDraft
        self.replyMessageID = replyMessageID
        self.replyTo = replyTo
        self.sendTopic = sendTopic
        self.store = store
    }

    func requestFinish() { finishRequested = true }

    func preserve() {
        guard !isDiscarded else { return }
        isPreserving = true
        VideoNoteRecordingPreservation.preserve(self)
    }

    func accept(_ asset: VideoNoteAsset) {
        guard acceptedAssetURL == nil, result == nil, !isDiscarded else {
            if acceptedAssetURL != asset.url { try? FileManager.default.removeItem(at: asset.url) }
            return
        }
        acceptedAssetURL = asset.url
        saveTask = Task {
            do {
                let draft: VideoNoteRecordingDraft =
                    if let baseDraft {
                        try await store.append(asset, to: baseDraft)
                    } else {
                        try await store.adopt(
                            asset, chatID: destination.chatID, draftKey: destination,
                            replyMessageID: replyMessageID, replyTo: replyTo, sendTopic: sendTopic,
                        )
                    }
                if isDiscarded {
                    await store.discard(id: draft.id)
                    complete(.failure(CancellationError()))
                } else {
                    complete(.success(draft))
                }
            } catch {
                try? FileManager.default.removeItem(at: asset.url)
                complete(.failure(error))
            }
            saveTask = nil
        }
    }

    func fail(_ error: Swift.Error) {
        guard acceptedAssetURL == nil else { return }
        complete(.failure(error))
    }

    func discard() {
        guard !isDiscarded else { return }
        isDiscarded = true
        saveTask?.cancel()
        if case .success(let draft) = result {
            Task { await store.discard(id: draft.id) }
        } else if let baseDraft {
            Task { await store.discard(id: baseDraft.id) }
        }
        if saveTask == nil { complete(.failure(CancellationError())) }
    }

    func value() async -> Result<VideoNoteRecordingDraft, Swift.Error> {
        if let result { return result }
        return await withCheckedContinuation { waiters.append($0) }
    }

    private func complete(_ result: Result<VideoNoteRecordingDraft, Swift.Error>) {
        guard self.result == nil else { return }
        self.result = result
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume(returning: result) }
    }
}
