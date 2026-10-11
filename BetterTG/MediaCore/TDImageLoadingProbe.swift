// TDImageLoadingProbe.swift

#if DEBUG
import Combine
import TDLibKit
import UIKit

@MainActor enum TDImageLoadingProbe {
    private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        @MainActor private final class Fixture
    {
        let center = NotificationCenter()
        let changes = PassthroughSubject<TdUpdateSource, Never>()
        lazy var demand = AnimatedFileDemand(center: center)
        var current = TdUpdateSource(accountID: UUID(), clientID: 601)
        var starts = [Int]()
        var cancels = [Int]()
        var holdStart = false
        var holdCancel = false
        var startReply: CheckedContinuation<File?, Never>?
        var cancelReply: CheckedContinuation<Void, Never>?

        func origin() -> TDImageOrigin {
            let source = current
            return TDImageOrigin(
                source: source,
                backend: .init(download: { [self] id in
                    guard current == source else { return nil }
                    starts.append(id)
                    if holdStart { return await withCheckedContinuation { startReply = $0 } }
                    return file(id: id)
                }, cancel: { [self] id in
                    cancels.append(id)
                    if holdCancel { await withCheckedContinuation { cancelReply = $0 } }
                }),
                demand: demand, currentSource: { [weak self] in self?.current },
                changes: changes.eraseToAnyPublisher(),
            )
        }

        func post(_ file: File, source: TdUpdateSource? = nil) {
            center.postTdUpdate(
                name: TdNotification<UpdateFile>.updateFile.name,
                object: UpdateFile(file: file),
                source: source ?? current,
            )
        }

        func replace(sameAccount: Bool = false) {
            current = TdUpdateSource(
                accountID: sameAccount ? current.accountID : UUID(),
                clientID: current.clientID + 1,
            )
            changes.send(current)
        }

        func finish() {
            startReply?.resume(returning: nil)
            startReply = nil
            cancelReply?.resume()
            cancelReply = nil
        }
    }

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-media-probe-static-image") else { return }
        Task {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("static-image-\(UUID())")
            let result: String
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                let png = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12))
.image { context in
                    UIColor.red.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
                }
.pngData()!
                let url = directory.appendingPathComponent("private.png")
                try png.write(to: url)
                try await verifyAdmission(url: url, png: png)
                try await verifyDemand(url: url)
                try await verifyLateWork(url: url, png: png)
                result = "Static image probe passed: actual-UIImageView/private-PNG=true; "
                    + "nil/stale-origin-placeholder/cache/local-decode=denied; cache-hit-revoked=true; "
                    + "same-account-client-revoked=true; colliding-source-update=denied; "
                    + "shared-view/prefetch-cancel-isolated=true; last-lease-cancel/reacquire=true; "
                    + "late-RPC/decode/reuse/deinit=guarded; server/account/store-writes=0; "
                    + "production-caller-UI/unpooled-media-start/VOD=source-review-only"
            } catch {
                result = "Static image probe failed: \(error)"
            }
            log(result)
            if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: documents.appendingPathComponent("static-image-probe.txt"),
                    options: .atomic,
                )
            }
        }
    }

    private static func verifyAdmission(url: URL, png: Data) async throws {
        let f = Fixture()
        defer { f.finish() }
        let origin = f.origin()
        let local = file(path: url.path)
        let first = TDImageLoadingView()
        first.load(file: local, placeholderData: png, origin: nil)
        try require(first.image == nil && first.loadedPath == nil && f.starts.isEmpty, "nil origin admitted pixels")
        first.load(file: local, origin: origin)
        try await until("local decode") { first.image != nil }
        try require(first.loadedPath == url.path && f.starts.isEmpty, "local decode used transport")
        let cached = TDImageLoadingView()
        cached.load(file: file(), origin: origin)
        try require(cached.image != nil && cached.loadedPath == nil && f.starts.isEmpty, "decoded cache missed")
        f.replace()
        await drain()
        try require(first.image == nil && cached.image == nil, "source change retained cache/local pixels")
        cached.load(file: local, placeholderData: png, origin: origin)
        try require(
            cached.image == nil && cached.loadedPath == nil && f.starts.isEmpty,
            "stale cache/local origin admitted",
        )
        cached.loadPlaceholder(data: png, origin: origin)
        try require(cached.image == nil, "stale placeholder admitted")
        cached.load(file: file(), origin: f.origin())
        try require(cached.image == nil, "foreign cache key collided")
        try await until("new client download") { f.starts.count == 1 }
        f.post(local, source: origin.source)
        await drain()
        try require(cached.image == nil && cached.loadedPath == nil, "foreign update decoded")
        f.post(local)
        try await until("current update decode") { cached.image != nil }
        f.replace(sameAccount: true)
        await drain()
        try require(cached.image == nil, "same-account replacement retained pixels")
    }

    private static func verifyDemand(url: URL) async throws {
        let f = Fixture()
        defer { f.finish() }
        let origin = f.origin()
        let first = TDImageLoadingView()
        let second = TDImageLoadingView()
        first.load(file: file(), origin: origin)
        second.load(file: file(), origin: origin)
        let prefetch = origin.request(fileID: 7)
        let task = Task { await prefetch.completedFile(file: file()) }
        try await until("shared start") { f.starts == [7] }
        await drain()
        first.cancel()
        task.cancel()
        let result = await task.value
        await drain()
        try require(result == nil && f.cancels.isEmpty, "consumer cancel stopped shared transport")
        f.post(file(path: url.path))
        try await until("surviving consumer") { second.image != nil }
        try require(first.image == nil && f.starts == [7], "cancelled consumer received bytes or duplicate download")
        second.cancel()
        await drain()
        try require(f.cancels.isEmpty && f.demand.entryCount == 0, "completed demand cancelled transport")

        let nextFile = file(id: 8)
        f.holdCancel = true
        first.load(file: nextFile, origin: origin)
        try await until("pending second file") { f.starts == [7, 8] }
        first.cancel()
        try await until("last consumer cancellation") { f.cancelReply != nil }
        second.load(file: nextFile, origin: origin)
        await drain()
        try require(f.starts == [7, 8], "replacement started before cancellation reply")
        f.holdCancel = false
        f.cancelReply?.resume()
        f.cancelReply = nil
        try await until("replacement start") { f.starts == [7, 8, 8] }
        second.cancel()
        try await until("replacement released") { f.demand.entryCount == 0 }
        try require(f.cancels == [8, 8], "last lease cancellation count")

        var released: TDImageLoadingView? = TDImageLoadingView()
        weak let weakView = released
        released?.load(file: file(id: 9), origin: origin)
        try await until("deinit start") { f.starts.last == 9 }
        released = nil
        try await until("view deinit and lease release") { [weak weakView] in
            weakView == nil && f.demand.entryCount == 0
        }
        try require(f.cancels.last == 9, "deinit retained lease")
    }

    private static func verifyLateWork(url: URL, png: Data) async throws {
        let f = Fixture()
        defer { f.finish() }
        let origin = f.origin()
        f.holdStart = true
        let view = TDImageLoadingView()
        view.load(file: file(), origin: origin)
        try await until("suspended RPC") { f.startReply != nil }
        view.load(
            photo: .init(hasStickers: false, minithumbnail: .init(data: png, height: 12, width: 12), sizes: []),
            preferredSize: .yBox,
            origin: origin,
        )
        f.startReply?.resume(returning: file(path: url.path))
        f.startReply = nil
        await drain()
        // Placeholders decode off the main thread through TDImageThumbnailPipeline.
        try await until("empty-photo placeholder") { view.image != nil }
        try require(view.loadedPath == nil, "old RPC crossed empty-photo replacement")
        var decodeReply: CheckedContinuation<UIImage?, Never>?
        view.debugDecode = { _, _ in await withCheckedContinuation { decodeReply = $0 } }
        view.load(file: file(path: url.path, id: 10), origin: origin)
        try await until("suspended decode") { decodeReply != nil }
        f.replace()
        await drain()
        decodeReply?.resume(returning: UIImage(data: png))
        decodeReply = nil
        await drain()
        try require(view.image == nil && view.loadedPath == nil, "old decode crossed origin revocation")
        view.load(file: file(path: url.path, id: 11), origin: f.origin())
        try await until("second suspended decode") { decodeReply != nil }
        view.loadPlaceholder(data: nil, origin: f.origin())
        decodeReply?.resume(returning: UIImage(data: png))
        decodeReply = nil
        await drain()
        try require(view.image == nil && view.loadedPath == nil, "old decode crossed reuse")
    }

    private static func file(path: String = "", id: Int = 7) -> File {
        File(
            expectedSize: 1,
            id: id,
            local: .init(
                canBeDeleted: false,
                canBeDownloaded: true,
                downloadOffset: 0,
                downloadedPrefixSize: path.isEmpty ? 0 : 1,
                downloadedSize: path.isEmpty ? 0 : 1,
                isDownloadingActive: path.isEmpty,
                isDownloadingCompleted: !path.isEmpty,
                path: path,
            ),
            remote: .init(
                id: "private-image-fixture",
                isUploadingActive: false,
                isUploadingCompleted: true,
                uniqueId: "private-image-fixture",
                uploadedSize: 1,
            ),
            size: 1,
        )
    }

    private static func drain() async {
        for _ in 0..<4 {
            await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
        }
    }

    private static func until(_ reason: String, _ check: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !check() {
            guard ContinuousClock.now < deadline else { throw Failure(description: "timeout: \(reason)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(description: message) }
    }
}
#endif
