// AnimatedFileDownloadProbe.swift

#if DEBUG
    import Combine
    import Foundation
    import TDLibKitDynamic

    @MainActor enum AnimatedFileDownloadProbe {
        private enum Failure: Swift.Error { case check(String) }

        private final class State {
            var source: TdUpdateSource?
            var paths = [String]()
            var invalidations = 0
            var downloads = [String]()
            var cancellations = [String]()
            var pending = [String: CheckedContinuation<File?, Never>]()
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-animation-authority") else { return }
            Task {
                let result: String
                do {
                    try await verify()
                    result = "Animation authority probe: scoped-update=true, queued-account-switch=true, "
                        + "captured-download-cancel=true, replacement-client=true, reused-file-fenced=true, "
                        + "late-rpc-rejected=true, unscoped-rejected=true, deinit-cancel=true, no-server-calls=true"
                } catch {
                    result = "Animation authority probe failed: \(error)"
                }
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("animation-authority-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func verify() async throws {
            let state = State()
            let center = NotificationCenter()
            let changes = PassthroughSubject<TdUpdateSource, Never>()
            let a = TdUpdateSource(accountID: UUID(), clientID: 11)
            let b = TdUpdateSource(accountID: UUID(), clientID: 22)
            let a2 = TdUpdateSource(accountID: a.accountID, clientID: 33)
            state.source = a
            func request(_ name: String, source: TdUpdateSource) -> AnimatedFileDownload {
                AnimatedFileDownload(
                    fileID: 7,
                    source: source,
                    backend: .init(download: { id in
                        state.downloads.append("\(name):\(id)")
                        return await withCheckedContinuation { state.pending[name] = $0 }
                    }, cancel: { id in state.cancellations.append("\(name):\(id)") }),
                    center: center,
                    currentSource: { state.source },
                    sourceChanges: changes.eraseToAnyPublisher(),
                )
            }
            func start(_ request: AnimatedFileDownload) {
                request.start(file: file(path: ""), onFile: { value in
                    if !value.local.path.isEmpty { state.paths.append(value.local.path) }
                }, onInvalidated: { state.invalidations += 1 })
            }
            func post(_ path: String, source: TdUpdateSource?, id: Int = 7) {
                center.postTdUpdate(
                    name: TdNotification<UpdateFile>.updateFile.name,
                    object: UpdateFile(file: file(path: path, id: id)),
                    source: source,
                )
            }
            defer {
                for continuation in state.pending.values {
                    continuation.resume(returning: nil)
                }
                state.pending.removeAll()
            }

            let first = request("A1", source: a)
            start(first)
            try await wait { state.pending["A1"] != nil }
            post("foreign", source: b)
            post("unscoped", source: nil)
            post("queued-own", source: a)
            // The queued accepted A event must not become B's file after main delivery.
            state.source = b
            changes.send(b)
            try await wait { state.invalidations == 1 && state.cancellations == ["A1:7"] }
            state.pending.removeValue(forKey: "A1")?.resume(returning: file(path: "late-A"))
            try await flush()
            try require(state.paths.isEmpty && !first.isCurrent, "old account escaped delivery")

            let second = request("B", source: b)
            start(second)
            try await wait { state.pending["B"] != nil }
            post("B-foreign", source: a)
            post("B-unscoped", source: nil)
            post("B-wrong-id", source: b, id: 8)
            post("B-own", source: b)
            try await wait { state.paths == ["B-own"] }
            // Complete files do not issue a cancellation against unrelated pending demand.
            second.cancel()
            state.pending.removeValue(forKey: "B")?.resume(returning: file(path: "late-B"))
            state.source = a2
            changes.send(a2)

            let old = request("A2-old", source: a2)
            start(old)
            try await wait { state.pending["A2-old"] != nil }
            old.cancel()
            old.cancel()
            let replacement = request("A2-new", source: a2)
            start(replacement)
            try await wait { state.pending["A2-new"] != nil }
            post("old-client", source: a)
            post("new-client", source: a2)
            state.pending.removeValue(forKey: "A2-old")?.resume(returning: file(path: "obsolete-reuse"))
            state.pending.removeValue(forKey: "A2-new")?.resume(returning: file(path: "new-rpc"))
            try await wait { state.paths.contains("new-rpc") }
            try require(state.paths == ["B-own", "new-client", "new-rpc"], "wrong source or reused result installed")
            replacement.cancel()
            try await flush()
            try require(state.cancellations == ["A1:7", "A2-old:7"], "cancel did not stay with its originating request")

            var released: AnimatedFileDownload? = request("released", source: a2)
            weak let weakReleased = released
            start(released!)
            try await wait { state.pending["released"] != nil }
            released = nil
            try await wait { weakReleased == nil && state.cancellations.last == "released:7" }
            state.pending.removeValue(forKey: "released")?.resume(returning: file(path: "after-deinit"))
            let neverStarted = request("never-started", source: a2)
            start(neverStarted)
            neverStarted.cancel()
            try await flush()
            try require(
                state.downloads == ["A1:7", "B:7", "A2-old:7", "A2-new:7", "released:7"],
                "canceled request started transport",
            )
            try require(!state.paths.contains("after-deinit"), "deinitialized request delivered")
        }

        private static func file(path: String, id: Int = 7) -> File {
            File(
                expectedSize: 1, id: id,
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
                    id: "fixture",
                    isUploadingActive: false,
                    isUploadingCompleted: true,
                    uniqueId: "fixture",
                    uploadedSize: 1,
                ),
                size: 1,
            )
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw Failure.check(message) }
        }

        private static func wait(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while !condition() {
                try require(ContinuousClock.now < deadline, "timed out")
                try await Task<Never, Never>.sleep(for: .milliseconds(10))
            }
        }

        private static func flush() async throws {
            try await Task<Never, Never>.sleep(for: .milliseconds(30))
        }
    }
#endif
