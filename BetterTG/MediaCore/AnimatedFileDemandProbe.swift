// AnimatedFileDemandProbe.swift

#if DEBUG
    import Combine
    import Foundation
    import TDLibKit

    @MainActor enum AnimatedFileDemandProbe {
        private enum Failure: Swift.Error { case check(String) }

        @MainActor private final class Fixture {
            let center = NotificationCenter()
            let changes = PassthroughSubject<TdUpdateSource, Never>()
            lazy var demand = AnimatedFileDemand(center: center)
            var source = TdUpdateSource(accountID: UUID(), clientID: 71)
            var events = [String]()
            var paths = [String: [String]]()
            var heldDownloads = Set<String>()
            var failedDownloads = Set<String>()
            var heldCancellations = Set<String>()
            var downloads = [String: CheckedContinuation<File?, Never>]()
            var cancellations = [String: CheckedContinuation<Void, Never>]()

            func request(_ name: String, id: Int = 7) -> AnimatedFileDownload {
                AnimatedFileDownload(
                    fileID: id, source: source,
                    backend: .init(download: { [self] id in
                        events.append("start:\(name)")
                        if heldDownloads.contains(name) {
                            return await withCheckedContinuation { downloads[name] = $0 }
                        }
                        return failedDownloads.contains(name) ? nil : file(id: id)
                    }, cancel: { [self] _ in
                        events.append("cancel:\(name)")
                        if heldCancellations.contains(name) {
                            await withCheckedContinuation { cancellations[name] = $0 }
                        }
                        events.append("cancelled:\(name)")
                    }),
                    demand: demand, currentSource: { [weak self] in self?.source },
                    sourceChanges: changes.eraseToAnyPublisher(),
                )
            }

            func start(_ request: AnimatedFileDownload, name: String) {
                request.start(file: file(id: request.fileID), onFile: { [weak self] file in
                    if file.local.isDownloadingCompleted { self?.paths[name, default: []].append(file.local.path) }
                }, onInvalidated: {})
            }

            func post(_ path: String, source: TdUpdateSource? = nil, id: Int = 7, active: Bool = true) {
                center.postTdUpdate(
                    name: TdNotification<UpdateFile>.updateFile.name,
                    object: UpdateFile(file: file(path: path, id: id, active: active)), source: source ?? self.source,
                )
            }

            func finish() {
                for value in downloads.values {
                    value.resume(returning: nil)
                }
                downloads.removeAll()
                for value in cancellations.values {
                    value.resume()
                }
                cancellations.removeAll()
            }
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-animation-demand") else { return }
            Task {
                let result: String
                do {
                    try await verify()
                    result = "Animation demand probe: shared-visible=true, prefetch-cancel-isolated=true, "
                        + "last-owner-cancel=true, restart-after-cancel-reply=true, source-key=true, "
                        + "queued-completion/inactive-before-cancel=true, "
                        + "late-initial-state-fenced=true, deinit-release=true, cancelled-before-start=true, "
                        + "failure-retry=true, cached-no-transport=true, empty-pool=true, no-server-calls=true"
                } catch {
                    result = "Animation demand probe failed: \(error)"
                }
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("animation-demand-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func verify() async throws {
            let fixture = Fixture()
            defer { fixture.finish() }
            var first: AnimatedFileDownload? = fixture.request("first")
            weak let weakFirst = first
            fixture.start(first!, name: "first")
            try await wait { fixture.events == ["start:first"] }
            let second = fixture.request("second")
            fixture.start(second, name: "second")
            let prefetch = fixture.request("prefetch")
            let prefetchTask = Task { await prefetch.completedFile(file: file()) }
            try await flush()
            first = nil
            prefetchTask.cancel()
            let cancelledPrefetch = await prefetchTask.value
            try await wait { weakFirst == nil }
            try require(
                cancelledPrefetch == nil && fixture.events == ["start:first"],
                "a released view/prefetch cancelled visible demand",
            )
            fixture.post("shared-file")
            try await wait { fixture.paths["second"] == ["shared-file"] }
            second.cancel()
            try await wait { fixture.demand.entryCount == 0 }
            try require(fixture.events == ["start:first"], "completed file cancelled or duplicate transport started")

            // Queue the only completion before a release/reacquire in one UI turn.
            // A scheduled (not yet issued) cancellation must not drop that update.
            let beforeCancel = fixture.request("before-cancel")
            fixture.start(beforeCancel, name: "before-cancel")
            try await wait { fixture.events.contains("start:before-cancel") }
            try await flush()
            fixture.post("completion-before-cancel")
            beforeCancel.cancel()
            let afterCancel = fixture.request("after-cancel")
            fixture.start(afterCancel, name: "after-cancel")
            try await wait { fixture.paths["after-cancel"]?.contains("completion-before-cancel") == true }
            try require(
                !fixture.events.contains("cancel:before-cancel") && !fixture.events.contains("start:after-cancel"),
                "queued completion was dropped during an aborted cancellation",
            )
            afterCancel.cancel()
            try await wait { fixture.demand.entryCount == 0 }

            let beforeInactive = fixture.request("before-inactive")
            fixture.start(beforeInactive, name: "before-inactive")
            try await wait { fixture.events.contains("start:before-inactive") }
            try await flush()
            fixture.post("", active: false)
            beforeInactive.cancel()
            let afterInactive = fixture.request("after-inactive")
            let inactive = await afterInactive.completedFile(file: file())
            try require(inactive == nil && fixture.demand.entryCount == 0, "queued inactive update stranded prefetch")
            try require(!fixture.events.contains("start:after-inactive"), "inactive update unexpectedly retried")

            fixture.heldCancellations.insert("old")
            let old = fixture.request("old")
            fixture.start(old, name: "old")
            try await wait { fixture.events.contains("start:old") }
            old.cancel()
            old.cancel()
            try await wait { fixture.cancellations["old"] != nil }
            let replacement = fixture.request("replacement")
            fixture.start(replacement, name: "replacement")
            fixture.post("cancelled-generation")
            try await flush()
            try require(
                !fixture.events.contains("start:replacement") && fixture.paths["replacement"] == nil,
                "replacement raced old cancellation",
            )
            fixture.cancellations.removeValue(forKey: "old")?.resume()
            try await wait { fixture.events.contains("start:replacement") }
            try require(
                fixture.events.firstIndex(of: "cancelled:old")! < fixture.events.firstIndex(of: "start:replacement")!,
                "transport restart preceded cancellation reply",
            )
            fixture.post("replacement-file")
            try await wait { fixture.paths["replacement"] == ["replacement-file"] }
            replacement.cancel()
            try await wait { fixture.demand.entryCount == 0 }

            // A still-suspended start can be reused without cancelling/restarting.
            fixture.heldDownloads.insert("suspended")
            let suspended = fixture.request("suspended")
            fixture.start(suspended, name: "suspended")
            try await wait { fixture.downloads["suspended"] != nil }
            suspended.cancel()
            let joined = fixture.request("joined")
            fixture.start(joined, name: "joined")
            fixture.downloads.removeValue(forKey: "suspended")?.resume(returning: file())
            try await flush()
            try require(
                !fixture.events.contains("start:joined") && !fixture.events.contains("cancel:suspended"),
                "pending start was not shared",
            )
            fixture.post("joined-file")
            try await wait { fixture.paths["joined"] == ["joined-file"] }
            joined.cancel()
            try await wait { fixture.demand.entryCount == 0 }

            // An accepted completion outranks a delayed initial-state response.
            fixture.heldDownloads.insert("late")
            let late = fixture.request("late")
            fixture.start(late, name: "late")
            try await wait { fixture.downloads["late"] != nil }
            fixture.post("complete-before-rpc")
            try await wait { fixture.paths["late"] == ["complete-before-rpc"] }
            late.cancel()
            fixture.downloads.removeValue(forKey: "late")?.resume(returning: file())
            try await wait { fixture.demand.entryCount == 0 }
            try require(
                !fixture.events.contains("cancel:late"),
                "late initial-state reply regressed completed transport",
            )

            // A same-account replacement client uses a different demand key.
            let previousSource = fixture.source
            fixture.heldCancellations.insert("source-old")
            let previous = fixture.request("source-old")
            fixture.start(previous, name: "source-old")
            try await wait { fixture.events.contains("start:source-old") }
            fixture.source = TdUpdateSource(accountID: previousSource.accountID, clientID: previousSource.clientID + 1)
            fixture.changes.send(fixture.source)
            try await wait { fixture.cancellations["source-old"] != nil }
            let current = fixture.request("source-new")
            fixture.start(current, name: "source-new")
            try await wait { fixture.events.contains("start:source-new") }
            fixture.post("foreign-client", source: previousSource)
            fixture.post("current-client")
            try await wait { fixture.paths["source-new"] == ["current-client"] }
            current.cancel()
            fixture.cancellations.removeValue(forKey: "source-old")?.resume()
            try await wait { fixture.demand.entryCount == 0 }

            let never = fixture.request("never")
            fixture.start(never, name: "never")
            never.cancel()
            let cached = fixture.request("cached")
            let cachedFile = await cached.completedFile(file: file(path: "already-cached"))
            try await flush()
            try require(
                !fixture.events.contains("start:never") && !fixture.events.contains("start:cached"),
                "unnecessary transport started",
            )
            try require(cachedFile?.local.path == "already-cached", "cached prefetch did not complete")

            fixture.failedDownloads.insert("failure")
            let failure = fixture.request("failure")
            let failed = await failure.completedFile(file: file())
            try require(failed == nil && fixture.demand.entryCount == 0, "failed prefetch retained its lease")
            let retry = fixture.request("retry")
            let retryTask = Task { await retry.completedFile(file: file()) }
            try await wait { fixture.events.contains("start:retry") }
            fixture.post("retried-file")
            let retried = await retryTask.value
            try require(
                retried?.local.path == "retried-file" && fixture.demand.entryCount == 0,
                "explicit retry failed or retained an entry",
            )
        }

        private static func file(path: String = "", id: Int = 7, active: Bool = true) -> File {
            File(
                expectedSize: 1, id: id,
                local: .init(
                    canBeDeleted: false, canBeDownloaded: true, downloadOffset: 0,
                    downloadedPrefixSize: path.isEmpty ? 0 : 1, downloadedSize: path.isEmpty ? 0 : 1,
                    isDownloadingActive: path.isEmpty && active, isDownloadingCompleted: !path.isEmpty, path: path,
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
