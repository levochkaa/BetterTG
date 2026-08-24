// TDLibVODResourceLoader.swift

import AVFoundation
import Combine
import Foundation
import UniformTypeIdentifiers

enum TDLibVODResourceLoaderStatus: Equatable, Sendable {
    case failed
    case idle
    case loading
    case offline
    case ready
    case retrying
}

// MARK: - TDLibVODResourceLoaderSession

final class TDLibVODResourceLoaderSession: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    // MARK: Lifecycle

    init?(
        lease: TDLibVODRangeLease,
        mimeType: String,
        fileName: String,
    ) {
        let extensionValue = (fileName as NSString).pathExtension.lowercased()
        let mimeContentType = Self.contentType(forMIMEType: mimeType)
        let extensionContentType = Self.contentType(forExtension: extensionValue)
        guard mimeContentType == nil
            || extensionContentType == nil
            || mimeContentType == extensionContentType
        else { return nil }
        guard let contentType = mimeContentType ?? extensionContentType else { return nil }

        let fallbackExtension = contentType == UTType.quickTimeMovie.identifier ? "mov" : "mp4"
        let candidateName = (fileName as NSString).lastPathComponent
        let resourceName = candidateName.isEmpty ? "media.\(fallbackExtension)" : candidateName
        var components = URLComponents()
        components.scheme = Self.urlScheme
        components.host = "file-\(lease.source.fileID)"
        components.path = "/\(resourceName)"
        guard let resourceURL = components.url else { return nil }

        let delegateQueue = DispatchQueue(
            label: "bettertg.vod.resource-loader.\(lease.source.fileID)",
            qos: .userInitiated,
        )
        let statusSubject = CurrentValueSubject<TDLibVODResourceLoaderStatus, Never>(.idle)
        self.resourceURL = resourceURL
        self.statusSubject = statusSubject
        self.state = TDLibVODResourceLoaderState(
            lease: lease,
            contentType: contentType,
            delegateQueue: delegateQueue,
            statusSubject: statusSubject,
        )
        self.asset = AVURLAsset(
            url: resourceURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true],
        )
        super.init()
        asset.resourceLoader.setDelegate(self, queue: delegateQueue)
    }

    deinit {
        state.invalidate()
    }

    // MARK: Internal

    let asset: AVURLAsset

    var statusPublisher: AnyPublisher<TDLibVODResourceLoaderStatus, Never> {
        statusSubject.removeDuplicates().eraseToAnyPublisher()
    }

    #if DEBUG
        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-vod-resource-loader") else { return }
            writeDebugProbeResult("VOD resource-loader probe started")
            Task { await runDebugProbe() }
        }
    #endif

    func invalidate() {
        state.invalidate()
    }

    func resourceLoader(
        _: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest,
    ) -> Bool {
        guard loadingRequest.request.url == resourceURL else { return false }
        return state.start(loadingRequest)
    }

    func resourceLoader(
        _: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest,
    ) {
        state.cancel(loadingRequest)
    }

    // MARK: Private

    private static let urlScheme = "bettertg-vod"

    private let resourceURL: URL
    private let state: TDLibVODResourceLoaderState
    private let statusSubject: CurrentValueSubject<TDLibVODResourceLoaderStatus, Never>

    private static func contentType(forMIMEType mimeType: String) -> String? {
        switch mimeType.lowercased() {
        case "application/mp4", "video/mp4", "video/x-m4v":
            UTType.mpeg4Movie.identifier
        case "video/quicktime":
            UTType.quickTimeMovie.identifier
        default:
            nil
        }
    }

    private static func contentType(forExtension pathExtension: String) -> String? {
        switch pathExtension {
        case "m4v", "mp4":
            UTType.mpeg4Movie.identifier
        case "mov":
            UTType.quickTimeMovie.identifier
        default:
            nil
        }
    }
}

// MARK: - TDLibVODResourceLoaderState

private final class TDLibVODResourceLoaderState: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        lease: TDLibVODRangeLease,
        contentType: String,
        delegateQueue: DispatchQueue,
        statusSubject: CurrentValueSubject<TDLibVODResourceLoaderStatus, Never>,
    ) {
        self.lease = lease
        self.contentType = contentType
        self.delegateQueue = delegateQueue
        self.statusSubject = statusSubject
    }

    deinit {
        invalidate()
    }

    // MARK: Internal

    func start(_ loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        let operation = LoadingOperation(request: loadingRequest)
        lock.lock()
        guard !invalidated else {
            lock.unlock()
            loadingRequest.finishLoading(with: URLError(.cancelled))
            return true
        }
        operations[operation.identifier] = operation
        lock.unlock()

        let task = Task { [self, operation] in
            await fulfill(operation)
        }
        operation.install(task: task)
        return true
    }

    func cancel(_ loadingRequest: AVAssetResourceLoadingRequest) {
        let identifier = ObjectIdentifier(loadingRequest)
        lock.lock()
        let operation = operations.removeValue(forKey: identifier)
        lock.unlock()
        operation?.cancel()
    }

    func invalidate() {
        lock.lock()
        guard !invalidated else {
            lock.unlock()
            return
        }
        invalidated = true
        let currentOperations = Array(operations.values)
        operations.removeAll()
        lock.unlock()
        publish(.idle, force: true)

        let cancellationError = URLError(.cancelled)
        for operation in currentOperations {
            operation.cancel()
            delegateQueue.async {
                guard !operation.request.isCancelled, !operation.request.isFinished else { return }
                operation.request.finishLoading(with: cancellationError)
            }
        }
        let lease = lease
        leaseReleaseTask = Task { await lease.invalidate() }
    }

    // MARK: Private

    private enum ResourceError: Swift.Error {
        case invalidRange
        case shortRead
        case unreadable
        case unsupportedContentType
    }

    private final class LoadingOperation: @unchecked Sendable {
        // MARK: Lifecycle

        init(request: AVAssetResourceLoadingRequest) {
            self.request = request
            self.identifier = ObjectIdentifier(request)
        }

        // MARK: Internal

        let identifier: ObjectIdentifier
        let request: AVAssetResourceLoadingRequest

        func install(task: Task<Void, Never>) {
            lock.lock()
            if !cancelled {
                self.task = task
            }
            let shouldCancel = cancelled
            lock.unlock()
            if shouldCancel {
                task.cancel()
            }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let task = task
            self.task = nil
            lock.unlock()
            task?.cancel()
        }

        func finish() {
            lock.lock()
            task = nil
            lock.unlock()
        }

        // MARK: Private

        private let lock = NSLock()
        private var cancelled = false
        private var task: Task<Void, Never>?
    }

    private let lease: TDLibVODRangeLease
    private let contentType: String
    private let delegateQueue: DispatchQueue
    private let gate = TDLibVODResourceReadGate()
    private let lock = NSLock()
    private let statusSubject: CurrentValueSubject<TDLibVODResourceLoaderStatus, Never>
    private var currentStatus = TDLibVODResourceLoaderStatus.idle
    private var invalidated = false
    private var leaseReleaseTask: Task<Void, Never>?
    private var operations = [ObjectIdentifier: LoadingOperation]()

    private func isActive(_ operation: LoadingOperation) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !invalidated && operations[operation.identifier] === operation
    }

    private func takeActive(
        _ operation: LoadingOperation,
        terminalStatus: TDLibVODResourceLoaderStatus?,
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard operations[operation.identifier] === operation else { return false }
        operations[operation.identifier] = nil
        operation.finish()
        guard !invalidated,
              !operation.request.isCancelled,
              !operation.request.isFinished
        else { return false }
        if let terminalStatus {
            publishLocked(terminalStatus, force: false)
        }
        return true
    }

    private func fulfill(_ operation: LoadingOperation) async {
        do {
            let size = try await lease.source.resolvedFileSize()
            try Task.checkCancellation()
            try await publishContentInformation(size: size, operation: operation)
            if let dataRequest = operation.request.dataRequest {
                try await fulfill(dataRequest: dataRequest, size: size, operation: operation)
            }
            complete(operation, error: nil)
        } catch is CancellationError {
            complete(operation, error: URLError(.cancelled))
        } catch let error as TDLibVODRangeError {
            complete(
                operation,
                error: resourceError(for: error),
                terminalStatus: status(for: error),
            )
        } catch {
            complete(operation, error: error, terminalStatus: .failed)
        }
    }

    private func fulfill(
        dataRequest: AVAssetResourceLoadingDataRequest,
        size: Int64,
        operation: LoadingOperation,
    ) async throws {
        let requestedOffset = dataRequest.requestedOffset
        let currentOffset = max(requestedOffset, dataRequest.currentOffset)
        guard requestedOffset >= 0, currentOffset >= 0, currentOffset <= size else {
            throw ResourceError.invalidRange
        }
        let upperBound: Int64
        if dataRequest.requestsAllDataToEndOfResource {
            upperBound = size
        } else {
            let requestedLength = Int64(max(0, dataRequest.requestedLength))
            upperBound = requestedOffset + min(requestedLength, size - requestedOffset)
        }

        let isAllDataToEnd = dataRequest.requestsAllDataToEndOfResource
        guard var permit = await gate.acquire(isAllDataToEnd: isAllDataToEnd) else {
            throw CancellationError()
        }
        do {
            var offset = currentOffset
            while offset < upperBound {
                try Task.checkCancellation()
                guard isActive(operation) else { throw CancellationError() }
                let count = Int(min(
                    TDLibVODRangeSource.maximumReadSize,
                    upperBound - offset,
                ))
                let chunk = try await read(offset: offset, count: count, operation: operation)
                guard !chunk.data.isEmpty else { throw ResourceError.shortRead }
                guard await publish(
                    data: chunk.data,
                    dataRequest: dataRequest,
                    operation: operation,
                ) else { throw CancellationError() }
                offset += Int64(chunk.data.count)

                if isAllDataToEnd, await gate.hasBoundedWaiter {
                    await gate.release(permit)
                    guard let resumedPermit = await gate.acquire(isAllDataToEnd: true) else {
                        throw CancellationError()
                    }
                    permit = resumedPermit
                }
            }
            await gate.release(permit)
        } catch {
            await gate.release(permit)
            throw error
        }
    }

    private func read(
        offset: Int64,
        count: Int,
        operation: LoadingOperation,
    ) async throws -> TDLibVODChunk {
        guard isActive(operation) else { throw CancellationError() }
        publish(.loading, operation: operation)
        while true {
            do {
                let chunk = try await lease.source.serializedRead(offset: offset, count: count)
                guard isActive(operation) else { throw CancellationError() }
                publish(.ready, operation: operation)
                return chunk
            } catch TDLibVODRangeError.staleRequest {
                try Task.checkCancellation()
                try await Task<Never, Never>.sleep(for: .milliseconds(10))
            }
        }
    }

    private func publishContentInformation(
        size: Int64,
        operation: LoadingOperation,
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
            delegateQueue.async { [weak self] in
                guard let self,
                      isActive(operation),
                      !operation.request.isCancelled,
                      !operation.request.isFinished
                else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if let information = operation.request.contentInformationRequest {
                    if let allowedTypes = information.allowedContentTypes,
                       !allowedTypes.isEmpty,
                       !allowedTypes.contains(contentType)
                    {
                        continuation.resume(throwing: ResourceError.unsupportedContentType)
                        return
                    }
                    information.contentLength = size
                    information.contentType = contentType
                    information.isByteRangeAccessSupported = true
                    information.isEntireLengthAvailableOnDemand = false
                }
                continuation.resume()
            }
        }
    }

    private func publish(
        data: Data,
        dataRequest: AVAssetResourceLoadingDataRequest,
        operation: LoadingOperation,
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            delegateQueue.async { [weak self] in
                guard let self,
                      isActive(operation),
                      !operation.request.isCancelled,
                      !operation.request.isFinished
                else {
                    continuation.resume(returning: false)
                    return
                }
                dataRequest.respond(with: data)
                continuation.resume(returning: true)
            }
        }
    }

    private func complete(
        _ operation: LoadingOperation,
        error: Swift.Error?,
        terminalStatus: TDLibVODResourceLoaderStatus? = nil,
    ) {
        delegateQueue.async { [weak self] in
            guard let self, takeActive(operation, terminalStatus: terminalStatus) else { return }
            if let error {
                operation.request.finishLoading(with: error)
            } else {
                operation.request.finishLoading()
            }
        }
    }

    private func resourceError(for error: TDLibVODRangeError) -> Swift.Error {
        switch error {
        case .cancelled, .staleRequest:
            URLError(.cancelled)
        case .offline:
            URLError(.notConnectedToInternet)
        case .timedOut:
            URLError(.timedOut)
        case .invalidRange:
            ResourceError.invalidRange
        case .missingLocalPath, .readFailed, .unknownSize:
            ResourceError.unreadable
        }
    }

    private func status(for error: TDLibVODRangeError) -> TDLibVODResourceLoaderStatus? {
        switch error {
        case .cancelled, .staleRequest:
            nil
        case .offline:
            .offline
        case .timedOut:
            .retrying
        case .invalidRange, .missingLocalPath, .readFailed, .unknownSize:
            .failed
        }
    }

    private func publish(
        _ status: TDLibVODResourceLoaderStatus,
        operation: LoadingOperation? = nil,
        force: Bool = false,
    ) {
        lock.lock()
        guard force || operation.map({ operations[$0.identifier] === $0 }) == true else {
            lock.unlock()
            return
        }
        publishLocked(status, force: force)
        lock.unlock()
    }

    private func publishLocked(
        _ status: TDLibVODResourceLoaderStatus,
        force: Bool,
    ) {
        let currentIsBlocking = Self.statusPriority(currentStatus) >= Self.statusPriority(.failed)
        let shouldPublish = force
            || !currentIsBlocking
            || Self.statusPriority(status) > Self.statusPriority(currentStatus)
        if shouldPublish {
            currentStatus = status
            statusSubject.send(status)
        }
    }

    private static func statusPriority(_ status: TDLibVODResourceLoaderStatus) -> Int {
        switch status {
        case .idle, .loading, .ready: 0
        case .failed: 1
        case .retrying: 2
        case .offline: 3
        }
    }
}

// MARK: - TDLibVODResourceReadGate

private actor TDLibVODResourceReadGate {
    // MARK: Internal

    struct Permit: Sendable {
        fileprivate let id: UUID
    }

    var hasBoundedWaiter: Bool {
        waiters.contains { !$0.isAllDataToEnd }
    }

    #if DEBUG
        static func runDebugProbe() async throws {
            let gate = TDLibVODResourceReadGate()
            guard let first = await gate.acquire(isAllDataToEnd: true) else {
                throw TDLibVODResourceLoaderProbeError.gate
            }
            let allToEnd = Task { await gate.acquire(isAllDataToEnd: true) }
            try await Task<Never, Never>.sleep(for: .milliseconds(5))
            let bounded = Task { await gate.acquire(isAllDataToEnd: false) }
            try await Task<Never, Never>.sleep(for: .milliseconds(5))
            await gate.release(first)
            guard let boundedPermit = await bounded.value else {
                throw TDLibVODResourceLoaderProbeError.gate
            }
            let cancelled = Task { await gate.acquire(isAllDataToEnd: false) }
            try await Task<Never, Never>.sleep(for: .milliseconds(5))
            cancelled.cancel()
            guard await cancelled.value == nil else {
                throw TDLibVODResourceLoaderProbeError.gate
            }
            await gate.release(boundedPermit)
            guard let allToEndPermit = await allToEnd.value else {
                throw TDLibVODResourceLoaderProbeError.gate
            }
            await gate.release(allToEndPermit)
        }
    #endif

    func acquire(isAllDataToEnd: Bool) async -> Permit? {
        guard !Task.isCancelled else { return nil }
        let permit = Permit(id: UUID())
        if holder == nil {
            holder = permit
            return permit
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let waiter = Waiter(
                    continuation: continuation,
                    isAllDataToEnd: isAllDataToEnd,
                    permit: permit,
                )
                if isAllDataToEnd {
                    waiters.append(waiter)
                } else {
                    let insertion = waiters.firstIndex(where: \.isAllDataToEnd) ?? waiters.endIndex
                    waiters.insert(waiter, at: insertion)
                }
            }
        } onCancel: {
            Task { await self.cancel(id: permit.id) }
        }
    }

    func release(_ permit: Permit) {
        guard holder?.id == permit.id else { return }
        if waiters.isEmpty {
            holder = nil
        } else {
            let waiter = waiters.removeFirst()
            holder = waiter.permit
            waiter.continuation.resume(returning: waiter.permit)
        }
    }

    // MARK: Private

    private struct Waiter {
        let continuation: CheckedContinuation<Permit?, Never>
        let isAllDataToEnd: Bool
        let permit: Permit
    }

    private var holder: Permit?
    private var waiters = [Waiter]()

    private func cancel(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.permit.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: nil)
    }
}

#if DEBUG
    private enum TDLibVODResourceLoaderProbeError: Swift.Error {
        case asset
        case detail(String)
        case gate
    }

    private extension TDLibVODResourceLoaderSession {
        static func runDebugProbe() async {
            let temporaryDirectory = FileManager.default.temporaryDirectory
            let url = temporaryDirectory.appendingPathComponent("bettertg-vod-resource-loader-probe.mp4")
            try? FileManager.default.removeItem(at: url)
            defer { try? FileManager.default.removeItem(at: url) }
            var stage = "gate"
            do {
                try await TDLibVODResourceReadGate.runDebugProbe()
                stage = "fixture"
                _ = try await VideoNoteAssetWriter.makeDebugSegment(
                    outputURL: url,
                    duration: 18,
                    frameSeed: 700,
                )
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                guard let size = (attributes[.size] as? NSNumber)?.int64Value,
                      size > TDLibVODRangeSource.normalFetchSize
                else { throw TDLibVODResourceLoaderProbeError.asset }

                let network = TDLibVODProbeNetwork(available: true)
                let backend = TDLibVODProbeBackend(fileURL: url, fileSize: size, network: network)
                await backend.setAutoFulfill(true)
                await backend.setDownloadDelay(.seconds(2))
                let coordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-resource-loader",
                    client: backend.client,
                    requestTimeout: .seconds(2),
                )
                let lease = await coordinator.acquire(file: backend.file(expectedSize: size * 2))
                stage = "metadata"
                guard let session = TDLibVODResourceLoaderSession(
                    lease: lease,
                    mimeType: "video/mp4",
                    fileName: "probe.mp4",
                ) else { throw TDLibVODResourceLoaderProbeError.asset }

                async let loadedDuration = session.asset.load(.duration)
                async let loadedVideoTracks = session.asset.loadTracks(withMediaType: .video)
                async let loadedAudioTracks = session.asset.loadTracks(withMediaType: .audio)
                let (duration, videoTracks, audioTracks) = try await (
                    loadedDuration,
                    loadedVideoTracks,
                    loadedAudioTracks,
                )
                let downloadCalls = await backend.downloadCalls
                let snapshot = await backend.file(expectedSize: size)
                guard duration.seconds >= 17.5,
                      !videoTracks.isEmpty,
                      !audioTracks.isEmpty,
                      !downloadCalls.isEmpty,
                      downloadCalls.allSatisfy({ !$0.isFullDownload }),
                      !snapshot.local.isDownloadingCompleted
                else { throw TDLibVODResourceLoaderProbeError.asset }
                session.invalidate()
                try await waitUntil { await backend.completedCancelCount == 1 }

                stage = "cold playback"
                let playbackBackend = TDLibVODProbeBackend(
                    fileURL: url,
                    fileSize: size,
                    network: network,
                )
                await playbackBackend.setAutoFulfill(true)
                await playbackBackend.setDownloadDelay(.seconds(2))
                let playbackCoordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-resource-loader-playback",
                    client: playbackBackend.client,
                    requestTimeout: .seconds(3),
                )
                let playbackLease = await playbackCoordinator.acquire(
                    file: playbackBackend.file(expectedSize: size * 2),
                )
                guard let playbackSession = TDLibVODResourceLoaderSession(
                    lease: playbackLease,
                    mimeType: "video/mp4",
                    fileName: "playback.mp4",
                ) else { throw TDLibVODResourceLoaderProbeError.asset }
                let playbackRecorder = TDLibVODNativePlaybackProbeRecorder()
                let playbackProbe = await MainActor.run {
                    TDLibVODNativePlaybackProbe(
                        session: playbackSession,
                        recorder: playbackRecorder,
                    )
                }
                do {
                    try await waitUntil {
                        let didAdvance = await playbackRecorder.didAdvance
                        let didLoadDuration = await playbackRecorder.didLoadDuration
                        let didLoadBufferedRanges = await playbackRecorder.didLoadBufferedRanges
                        return didAdvance && didLoadDuration && didLoadBufferedRanges
                    }
                } catch {
                    let detail = await playbackRecorder.proof
                    let calls = await playbackBackend.downloadCalls
                    throw TDLibVODResourceLoaderProbeError.detail(
                        "playback \(detail), downloads=\(calls.map(\.range))",
                    )
                }
                let coldPlaybackSnapshot = await playbackBackend.file(expectedSize: size)
                guard !coldPlaybackSnapshot.local.isDownloadingCompleted else {
                    throw TDLibVODResourceLoaderProbeError.detail("cold playback completed the download")
                }

                stage = "playback controls"
                let controlsApplied = await MainActor.run { playbackProbe.seekWithControls(to: 12) }
                guard controlsApplied else {
                    throw TDLibVODResourceLoaderProbeError.detail("control state was not applied")
                }
                await playbackRecorder.expect(time: 12.2)
                try await waitUntil { await playbackRecorder.didReachExpectedTime }
                let paused = await MainActor.run { playbackProbe.pause() }
                guard paused else {
                    throw TDLibVODResourceLoaderProbeError.detail("pause intent was not retained")
                }
                let pausedTime = await playbackRecorder.maximumTime
                let resumed = await MainActor.run { playbackProbe.resume() }
                guard resumed else {
                    throw TDLibVODResourceLoaderProbeError.detail("resume intent was not retained")
                }
                await playbackRecorder.expect(time: pausedTime + 0.2)
                try await waitUntil { await playbackRecorder.didReachExpectedTime }

                stage = "external playback controls"
                await MainActor.run { playbackProbe.beginExternalPause() }
                try await waitUntil {
                    await MainActor.run { playbackProbe.didAdoptExternalPause }
                }
                let externalPauseTime = await playbackRecorder.maximumTime
                await MainActor.run { playbackProbe.resumeExternally(atRate: 2) }
                try await waitUntil {
                    await MainActor.run { playbackProbe.didAdoptExternalPlay }
                }
                await playbackRecorder.expect(time: externalPauseTime + 0.2)
                try await waitUntil { await playbackRecorder.didReachExpectedTime }
                await MainActor.run { playbackProbe.simulateExternalEnd() }
                try await waitUntil {
                    await MainActor.run { playbackProbe.didReachExternalEnd }
                }
                let replayGeneration = await MainActor.run { playbackProbe.externalReplayGeneration }
                await MainActor.run { playbackProbe.resumeExternally(atRate: 2) }
                try await waitUntil {
                    await MainActor.run { playbackProbe.externalReplayGeneration > replayGeneration }
                }
                await MainActor.run { playbackProbe.pauseExternally() }
                try await waitUntil {
                    await MainActor.run { playbackProbe.didCancelExternalReplay }
                }
                try await Task<Never, Never>.sleep(for: .milliseconds(100))
                let replayStayedPaused = await MainActor.run { playbackProbe.didCancelExternalReplay }
                guard replayStayedPaused else {
                    throw TDLibVODResourceLoaderProbeError.detail("external pause lost the EOF replay race")
                }
                await MainActor.run { playbackProbe.resumeExternally(atRate: 2) }
                try await waitUntil {
                    await MainActor.run { playbackProbe.didRestartAfterExternalEnd }
                }
                await MainActor.run { playbackProbe.pauseExternally() }
                try await waitUntil {
                    await MainActor.run { playbackProbe.didSettleExternalPausedRate }
                }
                try await Task<Never, Never>.sleep(for: .milliseconds(100))
                let externalPauseStayedSettled = await MainActor.run {
                    playbackProbe.didSettleExternalPausedRate
                }
                guard externalPauseStayedSettled else {
                    let detail = await MainActor.run { playbackProbe.debugPlaybackSnapshot }
                    throw TDLibVODResourceLoaderProbeError.detail(
                        "external paused-rate state did not settle: \(detail)",
                    )
                }
                let externalControlEnded = await MainActor.run { playbackProbe.endExternalControl() }
                guard externalControlEnded else {
                    let detail = await MainActor.run { playbackProbe.debugPlaybackSnapshot }
                    throw TDLibVODResourceLoaderProbeError.detail(
                        "external playback intent was not retained: \(detail)",
                    )
                }

                let playbackDownloadCalls = await playbackBackend.downloadCalls
                guard playbackDownloadCalls.allSatisfy({ !$0.isFullDownload })
                else {
                    throw TDLibVODResourceLoaderProbeError.detail("playback used full-download semantics")
                }
                await MainActor.run { playbackProbe.stop() }
                stage = "playback cleanup"
                try await waitUntil { await playbackBackend.completedCancelCount == 1 }

                stage = "offline status and retry"
                let offlineNetwork = TDLibVODProbeNetwork(available: false)
                let offlineBackend = TDLibVODProbeBackend(
                    fileURL: url,
                    fileSize: size,
                    network: offlineNetwork,
                )
                await offlineBackend.setAutoFulfill(true)
                let offlineCoordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-resource-loader-offline",
                    client: offlineBackend.client,
                    requestTimeout: .seconds(2),
                )
                let offlineLease = await offlineCoordinator.acquire(
                    file: offlineBackend.file(expectedSize: size),
                )
                guard let offlineSession = TDLibVODResourceLoaderSession(
                    lease: offlineLease,
                    mimeType: "video/mp4",
                    fileName: "offline.mp4",
                ) else { throw TDLibVODResourceLoaderProbeError.asset }
                let offlineRecorder = TDLibVODStatusProbeRecorder()
                let offlineStatusCancellable = offlineSession.statusPublisher.sink { status in
                    Task { await offlineRecorder.update(status) }
                }
                var offlineLoadFailed = false
                do {
                    _ = try await offlineSession.asset.load(.duration)
                } catch {
                    offlineLoadFailed = true
                }
                guard offlineLoadFailed else {
                    throw TDLibVODResourceLoaderProbeError.detail("offline load unexpectedly succeeded")
                }
                try await waitUntil { await offlineRecorder.sawOffline }
                offlineSession.invalidate()
                offlineStatusCancellable.cancel()

                offlineNetwork.available = true
                let retryCoordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-resource-loader-offline-retry",
                    client: offlineBackend.client,
                    requestTimeout: .seconds(2),
                )
                let retryLease = await retryCoordinator.acquire(
                    file: offlineBackend.file(expectedSize: size),
                )
                guard let retrySession = TDLibVODResourceLoaderSession(
                    lease: retryLease,
                    mimeType: "video/mp4",
                    fileName: "offline-retry.mp4",
                ) else { throw TDLibVODResourceLoaderProbeError.asset }
                let retryRecorder = TDLibVODStatusProbeRecorder()
                let retryStatusCancellable = retrySession.statusPublisher.sink { status in
                    Task { await retryRecorder.update(status) }
                }
                let retryDuration = try await retrySession.asset.load(.duration)
                try await waitUntil { await retryRecorder.sawReady }
                let retryDownloadCalls = await offlineBackend.downloadCalls
                guard retryDuration.seconds >= 17.5,
                      retryDownloadCalls.allSatisfy({ !$0.isFullDownload })
                else {
                    throw TDLibVODResourceLoaderProbeError.detail("offline retry used full download")
                }
                retrySession.invalidate()
                retryStatusCancellable.cancel()

                stage = "blocked cancellation"
                let blockedBackend = TDLibVODProbeBackend(
                    fileURL: url,
                    fileSize: size,
                    network: network,
                )
                await blockedBackend.setAutoFulfill(false)
                let blockedCoordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-resource-loader-cancel",
                    client: blockedBackend.client,
                    requestTimeout: .seconds(2),
                )
                let blockedLease = await blockedCoordinator.acquire(
                    file: blockedBackend.file(expectedSize: size),
                )
                guard let blockedSession = TDLibVODResourceLoaderSession(
                    lease: blockedLease,
                    mimeType: "video/mp4",
                    fileName: "blocked.mp4",
                ) else { throw TDLibVODResourceLoaderProbeError.asset }
                let blockedLoad = Task { try await blockedSession.asset.load(.duration) }
                try await waitUntil { await blockedBackend.downloadCalls.count == 1 }
                blockedSession.invalidate()
                var blockedLoadFailed = false
                do {
                    _ = try await blockedLoad.value
                } catch {
                    blockedLoadFailed = true
                }
                guard blockedLoadFailed else { throw TDLibVODResourceLoaderProbeError.asset }
                try await waitUntil { await blockedBackend.completedCancelCount == 1 }

                let proof = "VOD resource-loader probe: duration=\(duration.seconds), tracks=A/V, "
                    + "requests=\(playbackDownloadCalls.count), progressive-before-complete=true, "
                    + "native-playing-before-complete, controls=pause/seek/rate/mute/resume/"
                    + "external-rate+replay-race+paused-exit, buffered-segments=true, "
                    + "offline-status/retry=true, finite-priority/queued-cancel/no-full-download=true"
                writeDebugProbeResult(proof)
                log(proof)
            } catch {
                let proof = "VOD resource-loader probe failed at \(stage): \(error)"
                writeDebugProbeResult(proof)
                assertionFailure(proof)
            }
        }

        static func waitUntil(
            _ condition: @escaping @Sendable () async -> Bool,
        ) async throws {
            for _ in 0..<1000 {
                if await condition() {
                    return
                }
                try await Task<Never, Never>.sleep(for: .milliseconds(10))
            }
            throw TDLibVODResourceLoaderProbeError.asset
        }

        static func writeDebugProbeResult(_ result: String) {
            let documentURLs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            guard let documentsURL = documentURLs.first else { return }
            try? Data(result.utf8).write(
                to: documentsURL.appendingPathComponent("vod-resource-loader-probe.txt"),
                options: .atomic,
            )
        }
    }

    private actor TDLibVODNativePlaybackProbeRecorder {
        // MARK: Internal

        private(set) var didAdvance = false
        private(set) var didLoadDuration = false
        private(set) var didLoadBufferedRanges = false
        private(set) var didReachExpectedTime = false
        private(set) var maximumTime = TimeInterval.zero

        var proof: String {
            "states=\(states), duration=\(duration), maxTime=\(maximumTime)"
        }

        func expect(time: TimeInterval) {
            expectedTime = time
            didReachExpectedTime = maximumTime >= time
        }

        func update(duration: TimeInterval) {
            self.duration = max(self.duration, duration)
            didLoadDuration = duration >= 17.5
        }

        func update(bufferedRanges: [LocalMediaPlayer.BufferedRange]) {
            didLoadBufferedRanges = bufferedRanges.contains { $0.end > $0.start }
        }

        func update(time: TimeInterval) {
            maximumTime = max(maximumTime, time)
            if time >= 0.2 {
                didAdvance = true
            }
            if time >= expectedTime {
                didReachExpectedTime = true
            }
        }

        func update(state: LocalMediaPlayer.State) {
            states.append(String(describing: state))
        }

        // MARK: Private

        private var duration = TimeInterval.zero
        private var expectedTime = TimeInterval.greatestFiniteMagnitude
        private var states = [String]()
    }

    private actor TDLibVODStatusProbeRecorder {
        private(set) var sawOffline = false
        private(set) var sawReady = false

        func update(_ status: TDLibVODResourceLoaderStatus) {
            sawOffline = sawOffline || status == .offline
            sawReady = sawReady || status == .ready
        }
    }

    @MainActor private final class TDLibVODNativePlaybackProbe {
        // MARK: Lifecycle

        init(
            session: TDLibVODResourceLoaderSession,
            recorder: TDLibVODNativePlaybackProbeRecorder,
        ) {
            player.timePublisher
                .sink { time in
                    Task { await recorder.update(time: time) }
                }
                .store(in: &cancellables)
            player.durationPublisher
                .sink { duration in
                    Task { await recorder.update(duration: duration) }
                }
                .store(in: &cancellables)
            player.bufferedRangesPublisher
                .sink { ranges in
                    Task { await recorder.update(bufferedRanges: ranges) }
                }
                .store(in: &cancellables)
            player.statePublisher
                .sink { state in
                    Task { await recorder.update(state: state) }
                }
                .store(in: &cancellables)
            player.load(vodSession: session, autoplay: true)
        }

        // MARK: Internal

        func seekWithControls(to time: TimeInterval) -> Bool {
            player.pause()
            guard !player.isPlaybackRequested else { return false }
            player.setMuted(true)
            player.setRate(1.5)
            player.play(from: time)
            return player.isMuted && player.rate == 1.5 && player.isPlaybackRequested
        }

        func pause() -> Bool {
            player.pause()
            return !player.isPlaybackRequested
        }

        func resume() -> Bool {
            player.play()
            return player.isPlaybackRequested && player.isMuted && player.rate == 1.5
        }

        func beginExternalPause() {
            player.setExternalPlaybackControlActive(true)
            player.simulateExternalPauseForProbe()
        }

        var didAdoptExternalPause: Bool {
            !player.isPlaybackRequested
        }

        func resumeExternally(atRate rate: Float) {
            player.simulateExternalPlayForProbe(atRate: rate)
        }

        func pauseExternally() {
            player.simulateExternalPauseForProbe()
        }

        var didAdoptExternalPlay: Bool {
            player.isPlaybackRequested && player.rate == 2
        }

        var didSettleExternalPausedRate: Bool {
            player.debugExternalPauseSettled(preferredRate: 2)
        }

        func simulateExternalEnd() {
            player.simulateExternalEndForProbe()
        }

        var didReachExternalEnd: Bool {
            player.state == .ended && !player.isPlaybackRequested
        }

        var didRestartAfterExternalEnd: Bool {
            player.isPlaybackRequested
                && player.state == .playing
                && player.currentTime >= 0.05
                && player.currentTime < 2
        }

        var externalReplayGeneration: UInt64 {
            player.debugExternalReplayGeneration
        }

        var didCancelExternalReplay: Bool {
            player.state == .ended && !player.isPlaybackRequested
        }

        func endExternalControl() -> Bool {
            player.setExternalPlaybackControlActive(false)
            return !player.isPlaybackRequested && player.rate == 2
        }

        var debugPlaybackSnapshot: String {
            player.debugPlaybackSnapshot
        }

        func stop() {
            player.stop()
            cancellables.removeAll()
        }

        // MARK: Private

        private let player = LocalMediaPlayer()
        private var cancellables = Set<AnyCancellable>()
    }
#endif
