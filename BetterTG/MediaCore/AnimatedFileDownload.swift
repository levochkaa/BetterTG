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
    private let center: NotificationCenter
    private let currentSource: () -> TdUpdateSource?
    private let sourceChanges: AnyPublisher<TdUpdateSource, Never>
    private var subscriptions = Set<AnyCancellable>()
    private var downloadTask: Task<Void, Never>?
    private var didStartDownload = false
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
            center: nc,
            currentSource: { TDLib.shared.activeUpdateSource },
            sourceChanges: TDLib.shared.activeClientChanges,
        )
    }

    init(
        fileID: Int,
        source: TdUpdateSource,
        backend: Backend,
        center: NotificationCenter,
        currentSource: @escaping () -> TdUpdateSource?,
        sourceChanges: AnyPublisher<TdUpdateSource, Never>,
    ) {
        self.fileID = fileID
        self.source = source
        self.backend = backend
        self.center = center
        self.currentSource = currentSource
        self.sourceChanges = sourceChanges
    }

    deinit {
        downloadTask?.cancel()
        if didStartDownload {
            let cancel = backend.cancel
            let id = fileID
            Task { await cancel(id) }
        }
    }

    func start(file: File, onFile: @escaping (File) -> Void, onInvalidated: @escaping () -> Void) {
        guard !didStart, isCurrent, file.id == fileID else { return }
        didStart = true
        self.onFile = onFile
        self.onInvalidated = onInvalidated
        center.scopedPublisher(&subscriptions, for: .updateFile) { [weak self] event in
            guard let self, event.source == source else { return }
            deliver(event.value.file)
        }
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
        let download = backend.download
        let id = fileID
        downloadTask = Task { [weak self] in
            guard self?.isCurrent == true, !Task.isCancelled else { return }
            self?.didStartDownload = true
            if let file = await download(id), !Task.isCancelled {
                self?.deliver(file)
            }
        }
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onFile = nil
        onInvalidated = nil
        subscriptions.removeAll()
        downloadTask?.cancel()
        downloadTask = nil
        if didStartDownload {
            didStartDownload = false
            let cancel = backend.cancel
            let id = fileID
            Task { await cancel(id) }
        }
    }

    private func deliver(_ file: File) {
        guard isCurrent, file.id == fileID else { return }
        if file.local.isDownloadingCompleted { didStartDownload = false }
        onFile?(file)
    }
}
