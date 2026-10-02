// FFmpegAnimationTimingProbe.swift

#if DEBUG
    import FFmpegBridge
    import Foundation

    actor FFmpegAnimationWaiterRegistrationGate {
        private(set) var entered = false

        private var continuation: CheckedContinuation<Void, Never>?
        private var opened = false

        func wait() async {
            entered = true
            guard !opened else { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func open() {
            opened = true
            continuation?.resume()
            continuation = nil
        }
    }

    /// Only probe counters/gates cross executors; native handles stay in the scan.
    final class FFmpegAnimationTimingObserver: @unchecked Sendable {
        private let lock = NSLock()
        private let gate = DispatchSemaphore(value: 0)
        private let holdsFirstRead: Bool
        private var starts = 0
        private var reads = 0
        private var finishes = 0
        private var active = 0
        private var maximumActive = 0
        private var onMain = false
        private var held = false
        private var timedOut = false

        init(holdsFirstRead: Bool = false) { self.holdsFirstRead = holdsFirstRead }

        func begin() {
            lock.lock()
            starts += 1
            active += 1
            maximumActive = max(maximumActive, active)
            onMain = onMain || Thread.isMainThread
            lock.unlock()
        }

        func read() {
            lock.lock()
            reads += 1
            onMain = onMain || Thread.isMainThread
            let shouldHold = holdsFirstRead && !held
            if shouldHold { held = true }
            lock.unlock()
            if shouldHold, gate.wait(timeout: .now() + 5) == .timedOut {
                lock.lock()
                timedOut = true
                lock.unlock()
            }
        }

        func end() {
            lock.lock()
            active -= 1
            finishes += 1
            onMain = onMain || Thread.isMainThread
            lock.unlock()
        }

        func release() { gate.signal() }

        func snapshot()
            -> (starts: Int, reads: Int, finishes: Int, maximumActive: Int, onMain: Bool, held: Bool, timedOut: Bool)
        {
            lock.lock()
            defer { lock.unlock() }
            return (starts, reads, finishes, maximumActive, onMain, held, timedOut)
        }
    }

    @MainActor enum FFmpegAnimationTimingProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-animation-timing") else { return }
            Task {
                let root = FileManager.default
.temporaryDirectory
                    .appendingPathComponent("animation-timing-\(UUID().uuidString)")
                let result: String
                do {
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: root) }
                    try await verifyFiles(root: root)
                    try await verifyOwnership(root: root)
                    try await verifyCancellationBeforeRegistration(root: root)
                    result = "Animation timing probe passed: native-VFR-holds=true; native-60fps=120; "
                        + "native-long=660; actual-EOF/last-interval=true; offset-PTS-normalized=true; "
                        + "zero/under/over-duration-ignored=true; one-frame=true; malformed-fallback=true; "
                        + "bounded-index-no-prefix=true; coalesced-scan=true; waiter-cancel-isolated=true; "
                        + "last-cancel/restart-serialized=true; pre-registration-cancel-no-scan=true; "
                        + "native-scan-off-main=true; "
                        + "first-frame-retained=true; real-TDLib/UI/performance=unverified"
                } catch {
                    result = "Animation timing probe failed: \(error)"
                }
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("animation-timing-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func verifyFiles(root: URL) async throws {
            for (name, ext, count, expectedDuration) in [
                ("variable", "gif", 4, 0.4), ("sixty", "webm", 120, 2.0),
                ("long", "webm", 660, 22.0), ("offset", "webm", 10, 1.0),
                ("one", "gif", 1, 0.12),
            ] {
                let url = try writeFixture(name, extension: ext, root: root)
                let observer = FFmpegAnimationTimingObserver()
                let loader = FFmpegVideoTimingLoader(path: url.path)
                await loader.observe(with: observer)
                guard let timeline = await loader.value()
                    else { throw Failure(description: "timeline missing: \(name)") }
                try require(
                    timeline.starts.count == count && abs(timeline.duration - expectedDuration) < 0.015,
                    "native duration/count mismatch: \(name) \(timeline.starts.count)/\(timeline.duration)",
                )
                try require(
                    timeline.starts.first == 0 && timeline.frameIndex(at: timeline.duration - 0.001) == count - 1
                    && timeline.frameIndex(at: timeline.duration) == 0,
                    "EOF loop boundary: \(name)",
                )
                if name == "variable" {
                    try require(
                        timeline.frameIndex(at: 0.03) == 0 && timeline.frameIndex(at: 0.041) == 1
                        && timeline.frameIndex(at: 0.239) == 1 && timeline.frameIndex(at: 0.241) == 2
                        && timeline.frameIndex(at: 0.281) == 3,
                        "VFR hold lost",
                    )
                }
                if name == "sixty" {
                    try require(timeline.frameIndex(at: 1.9) >= 110, "60fps tail unreachable")
                }
                if name == "long" {
                    try require(timeline.frameIndex(at: 21.5) > 600, "long tail unreachable")
                }
                let snapshot = observer.snapshot()
                try require(
                    snapshot.starts == 1 && snapshot.finishes == 1 && !snapshot.onMain,
                    "scan lifetime/main-thread violation",
                )
                guard let asset = await FFmpegVideoRepository.asset(at: url.path), asset.firstFrame != nil else {
                    throw Failure(description: "first frame missing: \(name)")
                }
                let decoder = FFmpegVideoFrameDecoder(asset: asset)
                guard await decoder.prepare(), let last = await decoder.frame(at: count - 1),
                      let first = await decoder.frame(at: 0)
                else { throw Failure(description: "actual pixel decoding/reset: \(name)") }
                let origin = first.presentationTime
                try require(
                    last.index == count - 1 && first.index == 0
                    && abs(last.presentationTime - origin - timeline.starts[count - 1]) < 0.002,
                    "selected index disagrees with native PTS: \(name)",
                )
                try require(
                    last.image.cgImage != nil && first.image.cgImage != nil
                    && asset.frameIndex(at: timeline.duration - 0.001) == count - 1,
                    "production selector/pixels: \(name)",
                )
            }

            for duration in [0.0, 500.0, 9000.0] {
                var data = try FFmpegAnimationTimingFixture.data("sixty")
                guard let marker = data.range(of: Data([0x44, 0x89, 0x88])) else {
                    throw Failure(description: "missing fixture Duration element")
                }
                var bits = duration.bitPattern.bigEndian
                let payload = withUnsafeBytes(of: &bits) { Data($0) }
                data.replaceSubrange(marker.upperBound..<(marker.upperBound + 8), with: payload)
                let url = root.appendingPathComponent("duration-\(Int(duration)).webm")
                try data.write(to: url)
                guard let timeline = await FFmpegVideoTimingLoader(path: url.path).value() else {
                    throw Failure(description: "altered metadata rejected")
                }
                try require(
                    timeline.starts.count == 120 && abs(timeline.duration - 2) < 0.015,
                    "metadata became EOF authority",
                )
            }

            let long = root.appendingPathComponent("long.webm")
            let capped = await FFmpegVideoTimingLoader(path: long.path, maximumFrames: 2).value()
            try require(capped == nil, "partial timing index published at limit")
            guard let firstFrameAsset = await FFmpegVideoRepository.asset(at: long.path) else {
                throw Failure(description: "fallback asset lost")
            }
            try require(firstFrameAsset.firstFrame != nil, "index failure removed first-frame fallback")
            let corrupt = root.appendingPathComponent("corrupt.webm")
            try Data("invalid webm".utf8).write(to: corrupt)
            let invalid = await FFmpegVideoTimingLoader(path: corrupt.path).value()
            try require(invalid == nil, "malformed input published timeline")
        }

        private static func verifyOwnership(root: URL) async throws {
            let url = root.appendingPathComponent("shared.webm")
            try FFmpegAnimationTimingFixture.data("long").write(to: url, options: .atomic)
            let observer = FFmpegAnimationTimingObserver(holdsFirstRead: true)
            defer { observer.release() }
            let loader = FFmpegVideoTimingLoader.shared(path: url.path)
            let sameFile = FFmpegVideoTimingLoader.shared(path: url.path)
            let otherFile = FFmpegVideoTimingLoader.shared(path: root.appendingPathComponent("long.webm").path)
            try require(loader === sameFile && loader !== otherFile, "file/account-path registry isolation failed")
            await loader.observe(with: observer)
            let first = Task { await loader.value() }
            try await wait { observer.snapshot().held }
            let second = Task { await sameFile.value() }
            try await waitForWaiters(loader, count: 2)
            first.cancel()
            let cancelled = await first.value
            try require(cancelled == nil && observer.snapshot().starts == 1, "one waiter cancelled shared scan")
            observer.release()
            let shared = await second.value
            let cached = await loader.value()
            try require(
                shared?.starts.count == 660 && cached?.starts.count == 660
                && observer.snapshot().starts == 1,
                "shared scan/cache failed",
            )

            let replacementObserver = FFmpegAnimationTimingObserver(holdsFirstRead: true)
            defer { replacementObserver.release() }
            let replacementLoader = FFmpegVideoTimingLoader(path: url.path)
            await replacementLoader.observe(with: replacementObserver)
            let old = Task { await replacementLoader.value() }
            try await wait { replacementObserver.snapshot().held }
            old.cancel()
            let oldResult = await old.value
            let successor = Task { await replacementLoader.value() }
            try await waitForWaiters(replacementLoader, count: 1)
            try require(
                oldResult == nil && replacementObserver.snapshot().starts == 1,
                "replacement raced cancelled native handle",
            )
            replacementObserver.release()
            let final = await successor.value
            let snapshot = replacementObserver.snapshot()
            try require(
                final?.starts.count == 660 && snapshot.starts == 2 && snapshot.finishes == 2
                && snapshot.maximumActive == 1 && !snapshot.onMain && !snapshot.timedOut,
                "cancel/restart cleanup or worker violation",
            )
        }

        private static func writeFixture(_ name: String, extension ext: String, root: URL) throws -> URL {
            let url = root.appendingPathComponent("\(name).\(ext)")
            try FFmpegAnimationTimingFixture.data(name).write(to: url, options: .atomic)
            return url
        }

        private static func verifyCancellationBeforeRegistration(root: URL) async throws {
            let loader = FFmpegVideoTimingLoader(path: root.appendingPathComponent("long.webm").path)
            let observer = FFmpegAnimationTimingObserver()
            let gate = FFmpegAnimationWaiterRegistrationGate()
            await loader.observe(with: observer)
            await loader.holdRegistration(with: gate)
            let request = Task { await loader.value() }
            defer {
                request.cancel()
                Task { await gate.open() }
            }
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while await !gate.entered {
                try require(ContinuousClock.now < deadline, "pre-registration gate timeout")
                try await Task<Never, Never>.sleep(for: .milliseconds(10))
            }
            request.cancel()
            while await loader.debugUnregisteredCancellationCount == 0 {
                try require(ContinuousClock.now < deadline, "pre-registration cancellation timeout")
                try await Task<Never, Never>.sleep(for: .milliseconds(10))
            }
            await gate.open()
            let result = await request.value
            let waiters = await loader.debugWaiterCount
            try require(
                result == nil && waiters == 0 && observer.snapshot().starts == 0,
                "cancelled unregistered waiter started native scan",
            )
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func wait(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while !condition() {
                try require(ContinuousClock.now < deadline, "probe gate timeout")
                try await Task<Never, Never>.sleep(for: .milliseconds(10))
            }
        }

        private static func waitForWaiters(_ loader: FFmpegVideoTimingLoader, count: Int) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while await loader.debugWaiterCount != count {
                try require(ContinuousClock.now < deadline, "waiter registration timeout")
                try await Task<Never, Never>.sleep(for: .milliseconds(10))
            }
        }
    }
#endif
