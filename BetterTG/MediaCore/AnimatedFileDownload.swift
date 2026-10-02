// AnimatedFileDownload.swift

import Combine
import Foundation
import TDLibKitDynamic

/// One configured view's file authority. File IDs are local to a TDLib client;
/// neither queued notifications nor an RPC may bind to a replacement client.
@MainActor final class AnimatedFileDownload {
    struct Backend {
        let download: (Int) async -> File?
        let cancel: (Int) async -> Void
    }

    let source: TdUpdateSource
    let fileID: Int

    private let backend: Backend
    private let demand: AnimatedFileDemand
    private let currentSource: () -> TdUpdateSource?
    private let sourceChanges: AnyPublisher<TdUpdateSource, Never>
    private var subscriptions = Set<AnyCancellable>()
    private var demandToken: AnimatedFileDemand.Token?
    private var completion: CheckedContinuation<File?, Never>?
    private var isCancelled = false
    private var didStart = false
    private var onFile: ((File) -> Void)?
    private var onInvalidated: (() -> Void)?

    var isCurrent: Bool { !isCancelled && currentSource() == source }

    convenience init?(fileID: Int, client: TDLibClient) {
        guard let source = TDLib.shared.activeUpdateSource, source.clientID == client.id else { return nil }
        self.init(
            fileID: fileID,
            source: source,
            backend: Backend(
                download: { id in
                    try? await client.downloadFile(fileId: id, limit: 0, offset: 0, priority: 2, synchronous: false)
                },
                cancel: { id in _ = try? await client.cancelDownloadFile(fileId: id, onlyIfPending: true) },
            ),
            demand: .shared,
            currentSource: { TDLib.shared.activeUpdateSource },
            sourceChanges: TDLib.shared.activeClientChanges,
        )
    }

    init(
        fileID: Int,
        source: TdUpdateSource,
        backend: Backend,
        demand: AnimatedFileDemand,
        currentSource: @escaping () -> TdUpdateSource?,
        sourceChanges: AnyPublisher<TdUpdateSource, Never>,
    ) {
        self.fileID = fileID
        self.source = source
        self.backend = backend
        self.demand = demand
        self.currentSource = currentSource
        self.sourceChanges = sourceChanges
    }

    deinit {
        if let token = demandToken {
            let demand = demand
            Task { @MainActor in demand.release(token) }
        }
        completion?.resume(returning: nil)
    }

    func start(file: File, onFile: @escaping (File) -> Void, onInvalidated: @escaping () -> Void) {
        guard !didStart, isCurrent, file.id == fileID else { return }
        didStart = true
        self.onFile = onFile
        self.onInvalidated = onInvalidated
        sourceChanges.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !isCurrent else { return }
                let callback = self.onInvalidated
                cancel()
                callback?()
            }
            .store(in: &subscriptions)
        deliver(file)
        guard isCurrent, !file.local.isDownloadingCompleted else { return }
        demandToken = demand.acquire(file: file, source: source, backend: backend) { [weak self] file in
            guard let self, isCurrent else { return }
            if let file { deliver(file) } else { finishPrefetch(nil) }
        }
    }

    /// Prefetch owns the same demand as a visible view, including cancellation.
    /// A cancelled waiter releases only its lease and always resumes exactly once.
    func completedFile(file: File) async -> File? {
        await withTaskCancellationHandler {
            guard !Task.isCancelled, !didStart, isCurrent else { return nil }
            return await withCheckedContinuation { continuation in
                completion = continuation
                start(file: file, onFile: { [weak self] value in
                    if value.local.isDownloadingCompleted { self?.finishPrefetch(value) }
                }, onInvalidated: {})
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onFile = nil
        onInvalidated = nil
        subscriptions.removeAll()
        if let token = demandToken {
            demandToken = nil
            demand.release(token)
        }
        completion?.resume(returning: nil)
        completion = nil
    }

    private func deliver(_ file: File) {
        guard isCurrent, file.id == fileID else { return }
        onFile?(file)
    }

    private func finishPrefetch(_ file: File?) {
        guard let continuation = completion else { return }
        completion = nil
        cancel()
        continuation.resume(returning: file)
    }
}
