// TDLibVODRangeSource.swift

import Combine
import Foundation
import Network
@preconcurrency import TDLibKit

// MARK: - TDLibVODRangeClient

struct TDLibVODRangeClient: @unchecked Sendable {
    let cancel: @Sendable (Int) async throws -> Void
    let download: @Sendable (Int, Int64, Int64, Int, Bool) async throws -> File
    let downloadedPrefixSize: @Sendable (Int, Int64) async throws -> Int64
    let getFile: @Sendable (Int) async throws -> File
    let isNetworkAvailable: @Sendable () -> Bool

    static func live(_ client: TDLibClient) -> TDLibVODRangeClient {
        TDLibVODRangeClient(
            cancel: { fileID in
                _ = try await client.cancelDownloadFile(fileId: fileID, onlyIfPending: false)
            },
            download: { fileID, offset, limit, priority, synchronous in
                try await client.downloadFile(
                    fileId: fileID,
                    limit: limit,
                    offset: offset,
                    priority: priority,
                    synchronous: synchronous,
                )
            },
            downloadedPrefixSize: { fileID, offset in
                try await client.getFileDownloadedPrefixSize(fileId: fileID, offset: offset).size
            },
            getFile: { fileID in
                try await client.getFile(fileId: fileID)
            },
            isNetworkAvailable: { TDLibVODNetworkMonitor.shared.isAvailable },
        )
    }
}

// MARK: - TDLibVODRangeState

enum TDLibVODRangeState: Equatable, Sendable {
    case idle
    case cachedReady(Range<Int64>)
    case buffering(requested: Range<Int64>, fetch: Range<Int64>)
    case offlineMissingRange(Range<Int64>)
    case retryableFailure(String)
    case terminalFailure(String)
    case cancelled
}

// MARK: - TDLibVODRangeError

enum TDLibVODRangeError: Swift.Error, Equatable {
    case cancelled
    case invalidRange
    case missingLocalPath
    case offline
    case readFailed
    case staleRequest
    case timedOut
    case unknownSize
}

// MARK: - TDLibVODChunk

struct TDLibVODChunk: Sendable {
    let confirmedRange: Range<Int64>
    let data: Data
    let fileURL: URL?
    let range: Range<Int64>
}

// MARK: - TDLibVODRangeSource

/// One account-scoped, file-scoped byte source shared by playback, fullscreen and PiP leases.
/// TDLib permits only one user-requested range per file, so all mutating file commands pass
/// through `commands` and disjoint demand explicitly supersedes the previous seek generation.
actor TDLibVODRangeSource {
    // MARK: Lifecycle

    init(
        accountID: String,
        file: File,
        client: TDLibVODRangeClient,
        requiresFullDownload: Bool = false,
        requestTimeout: Duration = .seconds(8),
    ) {
        self.accountID = accountID
        self.client = client
        self.fileID = file.id
        self.latestFile = file
        self.requestTimeout = requestTimeout
        self.requiresFullDownload = requiresFullDownload
        self.commands = TDLibVODCommandQueue(client: client, fileID: file.id)
        self.exactSize = file.size > 0 ? file.size : nil
    }

    // MARK: Internal

    static let maximumReadSize = Int64(256 * 1024)
    static let cacheProbeSize = Int64(512 * 1024)
    static let normalFetchSize = Int64(2 * 1024 * 1024)

    let accountID: String
    let fileID: Int

    private(set) var state = TDLibVODRangeState.idle

    #if DEBUG
        nonisolated static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-vod-ranges") else { return }
            writeDebugProbeResult("VOD range probe started")
            Task { await runDebugProbe() }
        }
    #endif

    func requireFullDownload() {
        requiresFullDownload = true
    }

    func resolvedFileSize() async throws -> Int64 {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await resolveSizeIfNeeded(waiterID: waiterID)
        } onCancel: {
            Task { await self.cancelWaiter(id: waiterID) }
        }
    }

    func completedFile() async throws -> File {
        requiresFullDownload = true
        _ = try await read(offset: 0, count: 1)
        guard latestFile.local.isDownloadingCompleted else {
            throw TDLibVODRangeError.readFailed
        }
        return latestFile
    }

    /// Invalidates completion from a last-lease cancellation that is still crossing the
    /// TDLib command barrier. Existing non-empty lease sets never call this method.
    func reviveAfterLastLeaseRelease() {
        seekGeneration &+= 1
        if state == .cancelled {
            state = .idle
        }
    }

    func read(offset: Int64, count: Int) async throws -> TDLibVODChunk {
        let requestedCount = min(Self.maximumReadSize, Int64(max(0, count)))
        guard offset >= 0, requestedCount > 0 else {
            state = .terminalFailure("Invalid VOD byte range.")
            throw TDLibVODRangeError.invalidRange
        }

        let waiterID = UUID()
        var classifiedRange = offset..<offset
        var operationGeneration = seekGeneration
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                let size = try await resolveSizeIfNeeded(waiterID: waiterID)
                try Task.checkCancellation()
                guard offset < size else {
                    state = .cachedReady(offset..<offset)
                    return TDLibVODChunk(
                        confirmedRange: offset..<offset,
                        data: Data(),
                        fileURL: localFileURL,
                        range: offset..<offset,
                    )
                }

                let requestedRange = offset..<Self.safeUpperBound(
                    from: offset,
                    adding: requestedCount,
                    limit: size,
                )
                let probeRange = offset..<Self.safeUpperBound(
                    from: offset,
                    adding: Self.cacheProbeSize,
                    limit: size,
                )
                classifiedRange = requestedRange
                let generation = try await prepareDemand(for: probeRange)
                operationGeneration = generation
                let confirmedRange = try await ensureAvailable(
                    requestedRange: requestedRange,
                    probeRange: probeRange,
                    generation: generation,
                    waiterID: waiterID,
                )
                try Task.checkCancellation()
                guard generation == seekGeneration else { throw TDLibVODRangeError.staleRequest }
                let local = try await readLocalData(in: requestedRange, generation: generation)
                guard generation == seekGeneration else { throw TDLibVODRangeError.staleRequest }
                state = .cachedReady(confirmedRange)
                return TDLibVODChunk(
                    confirmedRange: confirmedRange,
                    data: local.data,
                    fileURL: local.url,
                    range: requestedRange,
                )
            } catch is CancellationError {
                throw TDLibVODRangeError.cancelled
            } catch let error as TDLibVODRangeError {
                classify(
                    error,
                    requestedRange: classifiedRange,
                    generation: operationGeneration,
                )
                throw error
            } catch {
                if operationGeneration == seekGeneration {
                    state = .retryableFailure(String(describing: error))
                }
                throw error
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: waiterID) }
        }
    }

    func serializedRead(offset: Int64, count: Int) async throws -> TDLibVODChunk {
        guard let permit = await serializedReadGate.acquire() else {
            throw TDLibVODRangeError.cancelled
        }
        do {
            let chunk = try await read(offset: offset, count: count)
            await serializedReadGate.release(permit)
            return chunk
        } catch {
            await serializedReadGate.release(permit)
            throw error
        }
    }

    /// Update sequence is assigned before hopping from Combine into the actor, preventing
    /// spawned update tasks from rolling the aggregate TDLib File snapshot backwards.
    func update(file: File, sequence: UInt64) {
        guard file.id == fileID, sequence > lastUpdateSequence else { return }
        lastUpdateSequence = sequence
        accept(file)

        if ownsRangeRequest {
            if file.local.isDownloadingCompleted || !file.local.isDownloadingActive {
                detachOwnedRequest()
            } else if let activeFetchRange {
                let localRange = Self.localPrefixRange(file.local)
                let zeroPrefixMatchesActiveOffset = localRange.isEmpty
                    && max(0, file.local.downloadOffset) == activeFetchRange.lowerBound
                if !zeroPrefixMatchesActiveOffset,
                   localRange.isEmpty || !localRange.overlaps(activeFetchRange)
                {
                    // Another consumer replaced TDLib's single user range. Keep the newest
                    // File snapshot, relinquish ownership and let current demand replan.
                    detachOwnedRequest()
                }
            }
        }
        signalWaiters()
    }

    /// Called only by the account/file coordinator after the last current lease releases.
    func cancel() async {
        seekGeneration &+= 1
        let generation = seekGeneration
        failWaiters(with: TDLibVODRangeError.cancelled)
        let shouldCancel = detachOwnedRequest()
        currentDemandRange = nil
        if shouldCancel {
            try? await commands.cancel()
        }
        guard generation == seekGeneration else { return }
        state = .cancelled
    }

    // MARK: Fileprivate

    fileprivate static func fetchPlan(
        probeRange: Range<Int64>,
        activeFetchRange: Range<Int64>?,
        ownsRangeRequest: Bool,
        size: Int64,
    ) -> (range: Range<Int64>, startsNewRequest: Bool) {
        let initialUpperBound = safeUpperBound(
            from: probeRange.lowerBound,
            adding: normalFetchSize,
            limit: size,
        )
        guard ownsRangeRequest, let activeFetchRange else {
            return (probeRange.lowerBound..<initialUpperBound, true)
        }
        if contains(activeFetchRange, probeRange) {
            return (activeFetchRange, false)
        }
        guard activeFetchRange.overlaps(probeRange) else {
            return (probeRange.lowerBound..<initialUpperBound, true)
        }
        let extendedUpperBound = max(
            activeFetchRange.upperBound,
            safeUpperBound(from: probeRange.upperBound, adding: normalFetchSize, limit: size),
        )
        return (
            min(activeFetchRange.lowerBound, probeRange.lowerBound)..<extendedUpperBound,
            true,
        )
    }

    fileprivate static func safeUpperBound(
        from lowerBound: Int64,
        adding count: Int64,
        limit: Int64,
    ) -> Int64 {
        guard lowerBound < limit, count > 0 else { return min(lowerBound, limit) }
        return lowerBound + min(count, limit - lowerBound)
    }

    // MARK: Private

    private struct PendingWaiter {
        let continuation: CheckedContinuation<Void, Swift.Error>
        let generation: UInt64
        let timeoutTask: Task<Void, Never>
    }

    private let client: TDLibVODRangeClient
    private let commands: TDLibVODCommandQueue
    private let requestTimeout: Duration
    private let serializedReadGate = TDLibVODSerializedReadGate()
    private var latestFile: File
    private var exactSize: Int64?
    private var requiresFullDownload: Bool
    private var seekGeneration = UInt64(1)
    private var lastUpdateSequence = UInt64.zero
    private var activeFetchRange: Range<Int64>?
    private var activeRequestToken: UInt64?
    private var currentDemandRange: Range<Int64>?
    private var nextRequestToken = UInt64.zero
    private var ownsRangeRequest = false
    private var waiters = [UUID: PendingWaiter]()

    private var localFileURL: URL? {
        latestFile.local.path.isEmpty ? nil : URL(fileURLWithPath: latestFile.local.path)
    }

    private static func contains(_ outer: Range<Int64>, _ inner: Range<Int64>) -> Bool {
        inner.lowerBound >= outer.lowerBound && inner.upperBound <= outer.upperBound
    }

    private static func localPrefixRange(_ local: LocalFile) -> Range<Int64> {
        let lowerBound = max(0, local.downloadOffset)
        let upperBound = safeUpperBound(
            from: lowerBound,
            adding: max(0, local.downloadedPrefixSize),
            limit: Int64.max,
        )
        return lowerBound..<upperBound
    }

    private func resolveSizeIfNeeded(waiterID: UUID) async throws -> Int64 {
        if let exactSize {
            return exactSize
        }
        guard client.isNetworkAvailable() else {
            state = .offlineMissingRange(0..<0)
            throw TDLibVODRangeError.offline
        }

        let generation = seekGeneration
        var didRetry = false
        while exactSize == nil {
            try Task.checkCancellation()
            guard generation == seekGeneration else { throw TDLibVODRangeError.staleRequest }
            do {
                try await startFullDownload(generation: generation)
                guard generation == seekGeneration else { throw TDLibVODRangeError.staleRequest }
                if let exactSize {
                    return exactSize
                }
                try await waitForSignal(id: waiterID, generation: generation)
            } catch TDLibVODRangeError.timedOut where !didRetry && client.isNetworkAvailable() {
                didRetry = true
                detachOwnedRequest()
                continue
            }
        }
        guard let exactSize, exactSize > 0 else {
            state = .terminalFailure("VOD size is unavailable after full-download fallback.")
            throw TDLibVODRangeError.unknownSize
        }
        return exactSize
    }

    private func prepareDemand(for probeRange: Range<Int64>) async throws -> UInt64 {
        if state == .cancelled {
            seekGeneration &+= 1
            state = .idle
        }
        guard let currentDemandRange,
              !currentDemandRange.overlaps(probeRange)
        else {
            currentDemandRange = probeRange
            return seekGeneration
        }

        seekGeneration &+= 1
        let generation = seekGeneration
        failWaiters(with: TDLibVODRangeError.staleRequest)
        let shouldCancel = detachOwnedRequest()
        self.currentDemandRange = probeRange
        if shouldCancel {
            try? await commands.cancel()
        }
        guard generation == seekGeneration else { throw TDLibVODRangeError.staleRequest }
        return generation
    }

    private func ensureAvailable(
        requestedRange: Range<Int64>,
        probeRange: Range<Int64>,
        generation: UInt64,
        waiterID: UUID,
    ) async throws -> Range<Int64> {
        var timeoutRetries = 0
        while true {
            try Task.checkCancellation()
            guard generation == seekGeneration else { throw TDLibVODRangeError.staleRequest }

            if requiresFullDownload, !latestFile.local.isDownloadingCompleted {
                guard client.isNetworkAvailable() else { throw TDLibVODRangeError.offline }
                try await startFullDownload(generation: generation)
                guard generation == seekGeneration else { throw TDLibVODRangeError.staleRequest }
                if !latestFile.local.isDownloadingCompleted {
                    try await waitForSignal(id: waiterID, generation: generation)
                    continue
                }
            }

            let prefix = try await availablePrefix(
                from: requestedRange.lowerBound,
                generation: generation,
            )
            let requestedLength = requestedRange.upperBound - requestedRange.lowerBound
            let probeLength = probeRange.upperBound - probeRange.lowerBound
            if prefix >= requestedLength {
                if prefix < probeLength, client.isNetworkAvailable(), !requiresFullDownload {
                    // The read itself is cached; launch Telegram's 512 KiB lookahead without
                    // withholding bytes already safe for the demuxer.
                    schedulePrefetch(
                        for: probeRange,
                        requestedRange: requestedRange,
                        generation: generation,
                    )
                }
                return requestedRange.lowerBound..<Self.safeUpperBound(
                    from: requestedRange.lowerBound,
                    adding: min(prefix, probeLength),
                    limit: exactSize ?? requestedRange.upperBound,
                )
            }

            guard client.isNetworkAvailable() else { throw TDLibVODRangeError.offline }
            try await startFetch(
                for: probeRange,
                requestedRange: requestedRange,
                generation: generation,
            )
            guard generation == seekGeneration else { throw TDLibVODRangeError.staleRequest }

            let refreshedPrefix = try await availablePrefix(
                from: requestedRange.lowerBound,
                generation: generation,
            )
            if refreshedPrefix >= requestedLength {
                continue
            }

            do {
                try await waitForSignal(id: waiterID, generation: generation)
            } catch TDLibVODRangeError.timedOut where timeoutRetries == 0 && client.isNetworkAvailable() {
                timeoutRetries += 1
                // Reissue the same demand. Do not globally cancel a shared request because
                // another overlapping reader in this seek generation may still be progressing.
                detachOwnedRequest()
            }
        }
    }

    private func startFullDownload(generation: UInt64) async throws {
        if ownsRangeRequest, activeFetchRange == 0..<Int64.max {
            return
        }
        let responseSequence = lastUpdateSequence
        nextRequestToken &+= 1
        let requestToken = nextRequestToken
        activeFetchRange = 0..<Int64.max
        activeRequestToken = requestToken
        ownsRangeRequest = true
        state = .buffering(requested: 0..<0, fetch: 0..<Int64.max)
        do {
            let file = try await commands.download(
                offset: 0,
                limit: 0,
                priority: 32,
                synchronous: false,
            )
            guard generation == seekGeneration else { throw TDLibVODRangeError.staleRequest }
            if activeRequestToken == requestToken,
               responseSequence == lastUpdateSequence
            {
                accept(file)
            }
        } catch {
            guard generation == seekGeneration else { throw TDLibVODRangeError.staleRequest }
            guard activeRequestToken == requestToken else { return }
            detachOwnedRequest()
            throw error
        }
    }

    private func schedulePrefetch(
        for probeRange: Range<Int64>,
        requestedRange: Range<Int64>,
        generation: UInt64,
    ) {
        Task {
            guard generation == seekGeneration else { return }
            try? await startFetch(
                for: probeRange,
                requestedRange: requestedRange,
                generation: generation,
                updatesForegroundState: false,
            )
        }
    }

    private func startFetch(
        for probeRange: Range<Int64>,
        requestedRange: Range<Int64>,
        generation: UInt64,
        updatesForegroundState: Bool = true,
    ) async throws {
        guard let size = exactSize else { throw TDLibVODRangeError.unknownSize }
        let plan = Self.fetchPlan(
            probeRange: probeRange,
            activeFetchRange: activeFetchRange,
            ownsRangeRequest: ownsRangeRequest,
            size: size,
        )
        if updatesForegroundState {
            state = .buffering(requested: requestedRange, fetch: plan.range)
        }
        guard plan.startsNewRequest else { return }

        let responseSequence = lastUpdateSequence
        nextRequestToken &+= 1
        let requestToken = nextRequestToken
        activeFetchRange = plan.range
        activeRequestToken = requestToken
        ownsRangeRequest = true
        do {
            let file = try await commands.download(
                offset: plan.range.lowerBound,
                limit: plan.range.upperBound - plan.range.lowerBound,
                priority: 32,
                synchronous: false,
            )
            guard generation == seekGeneration else { throw TDLibVODRangeError.staleRequest }
            if activeRequestToken == requestToken,
               responseSequence == lastUpdateSequence
            {
                accept(file)
            }
        } catch {
            guard generation == seekGeneration else { throw TDLibVODRangeError.staleRequest }
            guard activeRequestToken == requestToken else { return }
            detachOwnedRequest()
            throw error
        }
    }

    private func availablePrefix(from offset: Int64, generation: UInt64) async throws -> Int64 {
        if latestFile.local.isDownloadingCompleted, let exactSize {
            return max(0, exactSize - min(offset, exactSize))
        }
        let prefix = try await client.downloadedPrefixSize(fileID, offset)
        guard generation == seekGeneration else { throw TDLibVODRangeError.staleRequest }
        guard let exactSize else { return max(0, prefix) }
        return max(0, min(prefix, exactSize - min(offset, exactSize)))
    }

    private func readLocalData(
        in range: Range<Int64>,
        generation: UInt64,
    ) async throws -> (data: Data, url: URL) {
        let length = Int(range.upperBound - range.lowerBound)
        var lastError = TDLibVODRangeError.missingLocalPath
        for attempt in 0..<2 {
            try Task.checkCancellation()
            guard generation == seekGeneration else { throw TDLibVODRangeError.staleRequest }
            if let url = localFileURL {
                do {
                    let data = try await Task.detached(priority: .userInitiated) {
                        let handle = try FileHandle(forReadingFrom: url)
                        defer { try? handle.close() }
                        try handle.seek(toOffset: UInt64(range.lowerBound))
                        return try handle.read(upToCount: length) ?? Data()
                    }.value
                    guard data.count == length else {
                        lastError = .readFailed
                        throw lastError
                    }
                    return (data, url)
                } catch let error as TDLibVODRangeError {
                    lastError = error
                } catch {
                    lastError = .readFailed
                }
            }
            guard attempt == 0 else { break }
            if let refreshed = try? await client.getFile(fileID) {
                guard generation == seekGeneration else { throw TDLibVODRangeError.staleRequest }
                accept(refreshed)
            }
        }
        throw lastError
    }

    private func waitForSignal(id: UUID, generation: UInt64) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
            guard generation == seekGeneration else {
                continuation.resume(throwing: TDLibVODRangeError.staleRequest)
                return
            }
            let timeoutTask = Task { [requestTimeout] in
                try? await Task<Never, Never>.sleep(for: requestTimeout)
                self.timeoutWaiter(id: id, generation: generation)
            }
            waiters[id] = PendingWaiter(
                continuation: continuation,
                generation: generation,
                timeoutTask: timeoutTask,
            )
        }
    }

    private func timeoutWaiter(id: UUID, generation: UInt64) {
        guard let waiter = waiters[id], waiter.generation == generation else { return }
        waiters[id] = nil
        waiter.timeoutTask.cancel()
        waiter.continuation.resume(throwing: TDLibVODRangeError.timedOut)
    }

    private func cancelWaiter(id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.timeoutTask.cancel()
        waiter.continuation.resume(throwing: TDLibVODRangeError.cancelled)
    }

    private func signalWaiters() {
        let currentWaiters = waiters
        waiters.removeAll(keepingCapacity: true)
        for waiter in currentWaiters.values {
            waiter.timeoutTask.cancel()
            waiter.continuation.resume()
        }
    }

    private func failWaiters(with error: TDLibVODRangeError) {
        let currentWaiters = waiters
        waiters.removeAll(keepingCapacity: true)
        for waiter in currentWaiters.values {
            waiter.timeoutTask.cancel()
            waiter.continuation.resume(throwing: error)
        }
    }

    @discardableResult private func detachOwnedRequest() -> Bool {
        let wasOwned = ownsRangeRequest
        ownsRangeRequest = false
        activeFetchRange = nil
        activeRequestToken = nil
        return wasOwned
    }

    private func accept(_ file: File) {
        guard file.id == fileID else { return }
        latestFile = file
        if file.size > 0 {
            // `expectedSize` is approximate and must never define EOF.
            exactSize = file.size
        }
        if file.local.isDownloadingCompleted {
            detachOwnedRequest()
        }
    }

    private func classify(
        _ error: TDLibVODRangeError,
        requestedRange: Range<Int64>,
        generation: UInt64,
    ) {
        guard generation == seekGeneration else { return }
        switch error {
        case .cancelled, .staleRequest:
            break
        case .offline:
            state = .offlineMissingRange(requestedRange)
        case .missingLocalPath, .readFailed, .timedOut:
            state = .retryableFailure(String(describing: error))
        case .invalidRange, .unknownSize:
            state = .terminalFailure(String(describing: error))
        }
    }
}

// MARK: - TDLibVODSerializedReadGate

private actor TDLibVODSerializedReadGate {
    // MARK: Internal

    struct Permit: Sendable {
        fileprivate let id: UUID
    }

    func acquire() async -> Permit? {
        guard !Task.isCancelled else { return nil }
        let permit = Permit(id: UUID())
        if holder == nil {
            holder = permit
            return permit
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters.append(Waiter(continuation: continuation, permit: permit))
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
        let permit: Permit
    }

    private var holder: Permit?
    private var waiters = [Waiter]()

    private func cancel(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.permit.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: nil)
    }
}

// MARK: - TDLibVODCommandQueue

/// Serializes TDLib's mutating commands without relying on Swift Task cancellation, which
/// doesn't cancel generated TDLib async queries. Full fallback also uses asynchronous mode,
/// so an ordered cancel can always run and a newer download always follows that cancel.
private actor TDLibVODCommandQueue {
    // MARK: Lifecycle

    init(client: TDLibVODRangeClient, fileID: Int) {
        self.client = client
        self.fileID = fileID
    }

    // MARK: Internal

    func download(
        offset: Int64,
        limit: Int64,
        priority: Int,
        synchronous: Bool,
    ) async throws -> File {
        let predecessor = tail
        let client = client
        let fileID = fileID
        let operation = Task<File, Swift.Error> {
            await predecessor?.value
            return try await client.download(fileID, offset, limit, priority, synchronous)
        }
        tail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    func cancel() async throws {
        let predecessor = tail
        let client = client
        let fileID = fileID
        let operation = Task<Void, Swift.Error> {
            await predecessor?.value
            try await client.cancel(fileID)
        }
        tail = Task { _ = try? await operation.value }
        try await operation.value
    }

    // MARK: Private

    private let client: TDLibVODRangeClient
    private let fileID: Int
    private var tail: Task<Void, Never>?
}

// MARK: - TDLibVODRangeLease

final class TDLibVODRangeLease: @unchecked Sendable {
    // MARK: Lifecycle

    fileprivate init(
        source: TDLibVODRangeSource,
        release: @escaping @Sendable () async -> Void,
    ) {
        self.source = source
        self.releaseOperation = release
    }

    deinit {
        guard let release = takeReleaseOperation() else { return }
        Task { await release() }
    }

    // MARK: Internal

    let source: TDLibVODRangeSource

    func invalidate() async {
        guard let release = takeReleaseOperation() else { return }
        await release()
    }

    // MARK: Private

    private let lock = NSLock()
    private var releaseOperation: (@Sendable () async -> Void)?

    private func takeReleaseOperation() -> (@Sendable () async -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        let operation = releaseOperation
        releaseOperation = nil
        return operation
    }
}

// MARK: - TDLibVODRangeCoordinator

/// One instance belongs to one TDLib client/account. File IDs are deliberately keyed only
/// inside that account-scoped instance so future accounts cannot cross-satisfy updates.
final class TDLibVODRangeCoordinator: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        accountID: String,
        client: TDLibVODRangeClient,
        updates: AnyPublisher<UpdateFile, Never>? = nil,
        requestTimeout: Duration = .seconds(8),
    ) {
        self.storage = Storage(accountID: accountID, client: client, requestTimeout: requestTimeout)
        self.updateCancellable = updates?.sink { [weak self] update in
            self?.route(file: update.file)
        }
    }

    // MARK: Internal

    func acquire(file: File, requiresFullDownload: Bool = false) async -> TDLibVODRangeLease {
        await storage.acquire(file: file, requiresFullDownload: requiresFullDownload)
    }

    // MARK: Private

    private actor Storage {
        // MARK: Lifecycle

        init(accountID: String, client: TDLibVODRangeClient, requestTimeout: Duration) {
            self.accountID = accountID
            self.client = client
            self.requestTimeout = requestTimeout
        }

        // MARK: Internal

        struct Entry {
            let source: TDLibVODRangeSource
            var leases: Set<UUID>
        }

        func acquire(file: File, requiresFullDownload: Bool) async -> TDLibVODRangeLease {
            let leaseID = UUID()
            let source: TDLibVODRangeSource
            if var entry = entries[file.id] {
                let revivesLastLeaseRelease = entry.leases.isEmpty
                entry.leases.insert(leaseID)
                entries[file.id] = entry
                source = entry.source
                if revivesLastLeaseRelease {
                    await source.reviveAfterLastLeaseRelease()
                }
                if requiresFullDownload {
                    await source.requireFullDownload()
                }
            } else {
                source = TDLibVODRangeSource(
                    accountID: accountID,
                    file: file,
                    client: client,
                    requiresFullDownload: requiresFullDownload,
                    requestTimeout: requestTimeout,
                )
                entries[file.id] = Entry(source: source, leases: [leaseID])
            }
            return TDLibVODRangeLease(source: source) { [storage = self] in
                await storage.release(fileID: file.id, leaseID: leaseID, source: source)
            }
        }

        func update(file: File, sequence: UInt64) async {
            guard let source = entries[file.id]?.source else { return }
            await source.update(file: file, sequence: sequence)
        }

        // MARK: Private

        private let accountID: String
        private let client: TDLibVODRangeClient
        private let requestTimeout: Duration
        private var entries = [Int: Entry]()

        private func release(fileID: Int, leaseID: UUID, source: TDLibVODRangeSource) async {
            guard var entry = entries[fileID], entry.source === source,
                  entry.leases.remove(leaseID) != nil
            else { return }
            entries[fileID] = entry
            guard entry.leases.isEmpty else { return }

            // Keep the entry visible while cancellation crosses an await. A concurrent
            // acquire then revives this exact source and can't be killed by a late deinit.
            await source.cancel()
            guard let current = entries[fileID], current.source === source,
                  current.leases.isEmpty
            else { return }
            entries[fileID] = nil
        }
    }

    private let storage: Storage
    private var updateCancellable: AnyCancellable?
    private let sequenceLock = NSLock()
    private var updateSequence = UInt64.zero

    private func route(file: File) {
        sequenceLock.lock()
        updateSequence &+= 1
        let sequence = updateSequence
        sequenceLock.unlock()
        Task { [storage] in
            await storage.update(file: file, sequence: sequence)
        }
    }
}

// MARK: - TDLibVODNetworkMonitor

private final class TDLibVODNetworkMonitor: @unchecked Sendable {
    // MARK: Lifecycle

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            lock.lock()
            self.available = path.status == .satisfied
            lock.unlock()
        }
        monitor.start(queue: queue)
    }

    // MARK: Internal

    static let shared = TDLibVODNetworkMonitor()

    var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return available
    }

    // MARK: Private

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "bettertg.vod.network")
    private let lock = NSLock()
    private var available = true
}

#if DEBUG
    private extension TDLibVODRangeSource {
        static func runDebugProbe() async {
            let temporaryURL = FileManager.default
.temporaryDirectory
                .appendingPathComponent("bettertg-vod-range-probe.bin")
            let fileSize = Int64(12 * 1024 * 1024)
            do {
                try Data(repeating: 0x5A, count: Int(fileSize)).write(to: temporaryURL, options: .atomic)
                defer { try? FileManager.default.removeItem(at: temporaryURL) }

                try probePlanner(fileSize: fileSize)
                let cacheProof = try await probeCacheAndReuse(fileURL: temporaryURL, fileSize: fileSize)
                let coalescingProof = try await probeOverlappingWaiters(
                    fileURL: temporaryURL,
                    fileSize: fileSize,
                )
                let seekProof = try await probeDisjointSeek(fileURL: temporaryURL, fileSize: fileSize)
                let offlineProof = try await probeOfflineAndApproximateSize(
                    fileURL: temporaryURL,
                    fileSize: fileSize,
                )
                let leaseProof = try await probeLeaseOwnership(fileURL: temporaryURL, fileSize: fileSize)
                let proof = "VOD range probe: cap/probe/planner=true, \(cacheProof), "
                    + "\(coalescingProof), \(seekProof), \(offlineProof), \(leaseProof)"
                writeDebugProbeResult(proof)
                log(proof)
            } catch {
                let proof = "VOD range probe failed: \(error)"
                writeDebugProbeResult(proof)
                assertionFailure(proof)
            }
        }

        static func probePlanner(fileSize: Int64) throws {
            let mib = Int64(1024 * 1024)
            let contained = fetchPlan(
                probeRange: 256 * 1024..<768 * 1024,
                activeFetchRange: 0..<2 * mib,
                ownsRangeRequest: true,
                size: fileSize,
            )
            guard !contained.startsNewRequest, contained.range == 0..<2 * mib else {
                throw TDLibVODProbeError.invariant("contained probe restarted")
            }
            let partial = fetchPlan(
                probeRange: 512 * 1024..<mib,
                activeFetchRange: 0..<600 * 1024,
                ownsRangeRequest: true,
                size: fileSize,
            )
            guard partial.startsNewRequest, partial.range == 0..<3 * mib else {
                throw TDLibVODProbeError.invariant("partial overlap did not extend")
            }
            let disjoint = fetchPlan(
                probeRange: 3 * mib..<3 * mib + 512 * 1024,
                activeFetchRange: 0..<2 * mib,
                ownsRangeRequest: true,
                size: fileSize,
            )
            guard disjoint.range == 3 * mib..<5 * mib else {
                throw TDLibVODProbeError.invariant("disjoint plan mismatch")
            }
            guard safeUpperBound(
                from: Int64.max - 10,
                adding: 512 * 1024,
                limit: Int64.max,
            ) == Int64.max else {
                throw TDLibVODProbeError.invariant("overflow clamp mismatch")
            }
        }

        static func probeCacheAndReuse(fileURL: URL, fileSize: Int64) async throws -> String {
            let network = TDLibVODProbeNetwork(available: true)
            let backend = TDLibVODProbeBackend(fileURL: fileURL, fileSize: fileSize, network: network)
            await backend.addCached(0..<maximumReadSize)
            await backend.setAutoFulfill(false)
            let source = await TDLibVODRangeSource(
                accountID: "probe-cache",
                file: backend.file(expectedSize: fileSize * 2),
                client: backend.client,
                requestTimeout: .milliseconds(300),
            )
            let first = try await source.read(offset: 0, count: Int(maximumReadSize * 2))
            guard first.data.count == Int(maximumReadSize) else {
                throw TDLibVODProbeError.invariant("read cap mismatch")
            }
            try await waitUntil { await backend.downloadCalls.count == 1 }
            try await Task<Never, Never>.sleep(for: .milliseconds(20))
            if case .buffering = await source.state {
                throw TDLibVODProbeError.invariant("opportunistic fetch overwrote cached-ready state")
            }
            let firstCalls = await backend.downloadCalls
            guard firstCalls.count == 1, firstCalls[0].range == 0..<normalFetchSize else {
                throw TDLibVODProbeError.invariant("cached lookahead missing")
            }

            await backend.addCached(maximumReadSize..<maximumReadSize * 2)
            _ = try await source.read(offset: maximumReadSize, count: Int(maximumReadSize))
            guard await backend.downloadCalls.count == 1 else {
                throw TDLibVODProbeError.invariant("contained range was replaced")
            }
            await source.cancel()
            return "cached-lookahead/reuse=true"
        }

        static func probeDisjointSeek(fileURL: URL, fileSize: Int64) async throws -> String {
            let mib = Int64(1024 * 1024)
            let network = TDLibVODProbeNetwork(available: true)
            let backend = TDLibVODProbeBackend(fileURL: fileURL, fileSize: fileSize, network: network)
            await backend.setAutoFulfill(false)
            await backend.setSuspendCancel(true)
            let source = await TDLibVODRangeSource(
                accountID: "probe-seek",
                file: backend.file(expectedSize: fileSize),
                client: backend.client,
                requestTimeout: .seconds(1),
            )
            let staleRead = Task { try await source.read(offset: 0, count: Int(maximumReadSize)) }
            try await waitUntil { await backend.downloadCalls.count == 1 }
            let replacement = Task { try await source.read(offset: 3 * mib, count: Int(maximumReadSize)) }
            try await waitUntil { await backend.cancelStarted }
            guard await backend.downloadCalls.count == 1 else {
                throw TDLibVODProbeError.invariant("replacement crossed cancel barrier")
            }
            await backend.resumeCancel()
            try await waitUntil { await backend.downloadCalls.count == 2 }
            await backend.addCached(3 * mib..<3 * mib + maximumReadSize)
            await source.update(file: backend.file(expectedSize: fileSize), sequence: 1)
            _ = try await replacement.value
            do {
                _ = try await staleRead.value
                throw TDLibVODProbeError.invariant("stale read succeeded")
            } catch TDLibVODRangeError.staleRequest {
                // Expected: disjoint demand is a new seek generation.
            }
            await source.cancel()
            return "disjoint/cancel-order/stale=true"
        }

        static func probeOverlappingWaiters(fileURL: URL, fileSize: Int64) async throws -> String {
            let network = TDLibVODProbeNetwork(available: true)
            let backend = TDLibVODProbeBackend(fileURL: fileURL, fileSize: fileSize, network: network)
            await backend.setAutoFulfill(false)
            let source = await TDLibVODRangeSource(
                accountID: "probe-coalescing",
                file: backend.file(expectedSize: fileSize),
                client: backend.client,
                requestTimeout: .seconds(1),
            )
            let first = Task { try await source.read(offset: 0, count: 64 * 1024) }
            try await waitUntil { await backend.downloadCalls.count == 1 }
            await source.update(file: backend.file(expectedSize: fileSize), sequence: 1)
            try await Task<Never, Never>.sleep(for: .milliseconds(20))
            guard await backend.downloadCalls.count == 1 else {
                throw TDLibVODProbeError.invariant("zero-prefix update displaced owned fetch")
            }
            let second = Task { try await source.read(offset: 64 * 1024, count: 64 * 1024) }
            try await Task<Never, Never>.sleep(for: .milliseconds(20))
            guard await backend.downloadCalls.count == 1 else {
                throw TDLibVODProbeError.invariant("overlapping waiter replaced fetch")
            }
            await backend.addCached(0..<128 * 1024)
            await source.update(file: backend.file(expectedSize: fileSize), sequence: 2)
            let firstChunk = try await first.value
            let secondChunk = try await second.value
            guard firstChunk.data.count == 64 * 1024,
                  secondChunk.data.count == 64 * 1024
            else { throw TDLibVODProbeError.invariant("overlapping waiter read mismatch") }
            await source.cancel()
            return "overlapping-waiters=true"
        }

        static func probeOfflineAndApproximateSize(fileURL: URL, fileSize: Int64) async throws -> String {
            let network = TDLibVODProbeNetwork(available: false)
            let cachedBackend = TDLibVODProbeBackend(fileURL: fileURL, fileSize: fileSize, network: network)
            await cachedBackend.addCached(0..<maximumReadSize)
            let cachedSource = await TDLibVODRangeSource(
                accountID: "probe-offline-cached",
                file: cachedBackend.file(expectedSize: fileSize * 2),
                client: cachedBackend.client,
                requestTimeout: .milliseconds(300),
            )
            _ = try await cachedSource.read(offset: 0, count: Int(maximumReadSize))

            let missingBackend = TDLibVODProbeBackend(fileURL: fileURL, fileSize: fileSize, network: network)
            let missingSource = await TDLibVODRangeSource(
                accountID: "probe-offline-missing",
                file: missingBackend.file(expectedSize: fileSize * 2),
                client: missingBackend.client,
                requestTimeout: .milliseconds(300),
            )
            do {
                _ = try await missingSource.read(offset: 0, count: 1)
                throw TDLibVODProbeError.invariant("offline miss succeeded")
            } catch TDLibVODRangeError.offline {
                // Expected.
            }

            network.available = true
            let approximateBackend = TDLibVODProbeBackend(fileURL: fileURL, fileSize: fileSize, network: network)
            await approximateBackend.setAutoFulfill(true)
            let approximateSource = await TDLibVODRangeSource(
                accountID: "probe-approximate",
                file: approximateBackend.file(expectedSize: 10 * 1024 * 1024, exactSize: 0),
                client: approximateBackend.client,
                requestTimeout: .milliseconds(300),
            )
            let beyondEstimate = try await approximateSource.read(
                offset: 11 * 1024 * 1024,
                count: 64,
            )
            guard beyondEstimate.data.count == 64 else {
                throw TDLibVODProbeError.invariant("expected size became EOF")
            }
            return "offline-cache/miss+exact-size=true"
        }

        static func probeLeaseOwnership(fileURL: URL, fileSize: Int64) async throws -> String {
            let network = TDLibVODProbeNetwork(available: true)
            let backend = TDLibVODProbeBackend(fileURL: fileURL, fileSize: fileSize, network: network)
            await backend.setAutoFulfill(false)
            let coordinator = TDLibVODRangeCoordinator(
                accountID: "probe-leases",
                client: backend.client,
                requestTimeout: .seconds(1),
            )
            let file = await backend.file(expectedSize: fileSize)
            let first = await coordinator.acquire(file: file)
            let second = await coordinator.acquire(file: file)
            let read = Task { try await first.source.read(offset: 0, count: 1) }
            try await waitUntil { await backend.downloadCalls.count == 1 }
            await first.invalidate()
            guard await backend.cancelCount == 0 else {
                throw TDLibVODProbeError.invariant("first lease cancelled shared request")
            }
            await second.invalidate()
            try await waitUntil { await backend.cancelCount == 1 }
            _ = try? await read.value

            let revivalBackend = TDLibVODProbeBackend(
                fileURL: fileURL,
                fileSize: fileSize,
                network: network,
            )
            await revivalBackend.setAutoFulfill(false)
            await revivalBackend.setSuspendCancel(true)
            let revivalCoordinator = TDLibVODRangeCoordinator(
                accountID: "probe-lease-revival",
                client: revivalBackend.client,
                requestTimeout: .seconds(1),
            )
            let revivalFile = await revivalBackend.file(expectedSize: fileSize)
            let releasingLease = await revivalCoordinator.acquire(file: revivalFile)
            let pendingRead = Task { try await releasingLease.source.read(offset: 0, count: 1) }
            try await waitUntil { await revivalBackend.downloadCalls.count == 1 }
            let releaseTask = Task { await releasingLease.invalidate() }
            try await waitUntil { await revivalBackend.cancelStarted }
            let revivedLease = await revivalCoordinator.acquire(file: revivalFile)
            await revivalBackend.addCached(0..<cacheProbeSize)
            let revivedChunk = try await revivedLease.source.read(offset: 0, count: 1)
            guard revivedChunk.data.count == 1 else {
                throw TDLibVODProbeError.invariant("revived lease cached read failed")
            }
            await revivalBackend.resumeCancel()
            await releaseTask.value
            if case .cancelled = await revivedLease.source.state {
                throw TDLibVODProbeError.invariant("old cancel overwrote revived lease")
            }
            _ = try? await pendingRead.value
            await revivedLease.invalidate()
            return "last-lease-cancel/revive=true"
        }

        static func waitUntil(
            _ condition: @escaping @Sendable () async -> Bool,
        ) async throws {
            for _ in 0..<100 {
                if await condition() {
                    return
                }
                try await Task<Never, Never>.sleep(for: .milliseconds(10))
            }
            throw TDLibVODProbeError.invariant("probe timed out")
        }

        static func writeDebugProbeResult(_ result: String) {
            guard let documentsURL = FileManager.default
.urls(
    for: .documentDirectory,
    in: .userDomainMask,
)
.first else { return }
            try? Data(result.utf8).write(
                to: documentsURL.appendingPathComponent("vod-range-probe.txt"),
                options: .atomic,
            )
        }
    }

    private enum TDLibVODProbeError: Swift.Error {
        case invariant(String)
    }

    struct TDLibVODProbeDownload: Sendable {
        let isFullDownload: Bool
        let range: Range<Int64>
    }

    final class TDLibVODProbeNetwork: @unchecked Sendable {
        // MARK: Lifecycle

        init(available: Bool) {
            self.storedAvailable = available
        }

        // MARK: Internal

        var available: Bool {
            get {
                lock.lock()
                defer { lock.unlock() }
                return storedAvailable
            }
            set {
                lock.lock()
                storedAvailable = newValue
                lock.unlock()
            }
        }

        // MARK: Private

        private let lock = NSLock()
        private var storedAvailable: Bool
    }

    actor TDLibVODProbeBackend {
        // MARK: Lifecycle

        init(fileURL: URL, fileSize: Int64, network: TDLibVODProbeNetwork) {
            self.fileURL = fileURL
            self.fileSize = fileSize
            self.network = network
        }

        // MARK: Internal

        private(set) var downloadCalls = [TDLibVODProbeDownload]()
        private(set) var activeDownloadCount = 0
        private(set) var cancelCount = 0
        private(set) var completedCancelCount = 0
        private(set) var cancelStarted = false

        nonisolated let fileSize: Int64
        nonisolated let network: TDLibVODProbeNetwork

        nonisolated var client: TDLibVODRangeClient {
            TDLibVODRangeClient(
                cancel: { [weak self] _ in
                    guard let self else { return }
                    await cancel()
                },
                download: { [weak self] _, offset, limit, _, _ in
                    guard let self else { throw TDLibVODRangeError.cancelled }
                    return await download(offset: offset, limit: limit)
                },
                downloadedPrefixSize: { [weak self] _, offset in
                    guard let self else { return 0 }
                    return await prefix(from: offset)
                },
                getFile: { [weak self] _ in
                    guard let self else { throw TDLibVODRangeError.cancelled }
                    return await file(expectedSize: fileSize)
                },
                isNetworkAvailable: { [network] in network.available },
            )
        }

        func setAutoFulfill(_ value: Bool) {
            autoFulfill = value
        }

        func setReportsExactSize(_ value: Bool) {
            reportsExactSize = value
        }

        func setDownloadDelay(_ value: Duration?) {
            downloadDelay = value
        }

        func setSuspendCancel(_ value: Bool) {
            suspendCancel = value
        }

        func addCached(_ range: Range<Int64>) {
            cachedRanges.append(range)
        }

        func resumeCancel() {
            suspendCancel = false
            let continuation = cancelContinuation
            cancelContinuation = nil
            continuation?.resume()
        }

        func file(expectedSize: Int64, exactSize: Int64? = nil) -> File {
            makeFile(
                downloadOffset: lastDownloadRange?.lowerBound ?? 0,
                downloadedPrefixSize: prefix(from: lastDownloadRange?.lowerBound ?? 0),
                expectedSize: expectedSize,
                exactSize: exactSize ?? fileSize,
                isActive: !autoFulfill && lastDownloadRange != nil,
                isCompleted: covers(0..<fileSize),
            )
        }

        // MARK: Private

        private let fileURL: URL
        private var autoFulfill = false
        private var downloadDelay: Duration?
        private var reportsExactSize = true
        private var suspendCancel = false
        private var cachedRanges = [Range<Int64>]()
        private var lastDownloadRange: Range<Int64>?
        private var cancelContinuation: CheckedContinuation<Void, Never>?

        private func cancel() async {
            cancelStarted = true
            cancelCount += 1
            if suspendCancel {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    cancelContinuation = continuation
                }
            }
            lastDownloadRange = nil
            completedCancelCount += 1
        }

        private func download(offset: Int64, limit: Int64) async -> File {
            let range = limit == 0
                ? 0..<fileSize
                : offset..<TDLibVODRangeSource.safeUpperBound(
                    from: offset,
                    adding: limit,
                    limit: fileSize,
                )
            downloadCalls.append(TDLibVODProbeDownload(
                isFullDownload: limit == 0,
                range: range,
            ))
            activeDownloadCount += 1
            defer { activeDownloadCount -= 1 }
            lastDownloadRange = range
            if let downloadDelay {
                try? await Task<Never, Never>.sleep(for: downloadDelay)
            }
            if autoFulfill {
                cachedRanges.append(range)
            }
            return makeFile(
                downloadOffset: range.lowerBound,
                downloadedPrefixSize: prefix(from: range.lowerBound),
                expectedSize: fileSize * 2,
                exactSize: reportsExactSize ? fileSize : 0,
                isActive: !autoFulfill,
                isCompleted: covers(0..<fileSize),
            )
        }

        private func prefix(from offset: Int64) -> Int64 {
            var cursor = offset
            for range in cachedRanges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
                if range.upperBound <= cursor {
                    continue
                }
                guard range.lowerBound <= cursor else { break }
                cursor = max(cursor, range.upperBound)
            }
            return max(0, cursor - offset)
        }

        private func covers(_ target: Range<Int64>) -> Bool {
            prefix(from: target.lowerBound) >= target.upperBound - target.lowerBound
        }

        private func makeFile(
            downloadOffset: Int64,
            downloadedPrefixSize: Int64,
            expectedSize: Int64,
            exactSize: Int64,
            isActive: Bool,
            isCompleted: Bool,
        ) -> File {
            File(
                expectedSize: expectedSize,
                id: 7777,
                local: LocalFile(
                    canBeDeleted: false,
                    canBeDownloaded: true,
                    downloadOffset: downloadOffset,
                    downloadedPrefixSize: downloadedPrefixSize,
                    downloadedSize: cachedRanges.reduce(Int64.zero) {
                        $0 + $1.upperBound - $1.lowerBound
                    },
                    isDownloadingActive: isActive,
                    isDownloadingCompleted: isCompleted,
                    path: fileURL.path,
                ),
                remote: RemoteFile(
                    id: "probe",
                    isUploadingActive: false,
                    isUploadingCompleted: true,
                    uniqueId: "probe",
                    uploadedSize: exactSize,
                ),
                size: exactSize,
            )
        }
    }
#endif
