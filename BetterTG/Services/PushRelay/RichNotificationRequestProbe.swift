// RichNotificationRequestProbe.swift

#if DEBUG
    import Foundation

    @MainActor enum RichNotificationRequestProbe {
        private typealias Owner = RichNotificationRequestCoordinator<String>
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        private final class Receipts: @unchecked Sendable {
            private let lock = NSLock()
            private var events = [String]()
            private var replacement: Owner.Ticket?

            var values: [String] { lock.lock()
            defer { lock.unlock() }
            return events
            }

            var ticket: Owner.Ticket? { lock.lock()
            defer { lock.unlock() }
            return replacement
            }

            func add(_ value: String) { lock.lock()
            events.append(value)
            lock.unlock()
            }

            func replace(_ value: Owner.Ticket) { lock.lock()
            replacement = value
            lock.unlock()
            }
        }

        /// A deliberately uncooperative response: cancellation does not release it.
        private final class Signal: @unchecked Sendable {
            private let lock = NSLock()
            private var opened = false
            private var waiters = [UUID: CheckedContinuation<Bool, Never>]()

            func open() {
                lock.lock()
                opened = true
                let pending = Array(waiters.values)
                waiters.removeAll()
                lock.unlock()
                pending.forEach { $0.resume(returning: true) }
            }

            func wait() async -> Bool {
                await withCheckedContinuation { continuation in
                    let id = UUID()
                    lock.lock()
                    if opened { lock.unlock()
                    continuation.resume(returning: true)
                    return
                    }
                    waiters[id] = continuation
                    lock.unlock()
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) { [self] in
                        lock.lock()
                        let pending = waiters.removeValue(forKey: id)
                        lock.unlock()
                        pending?.resume(returning: false)
                    }
                }
            }
        }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-notification-request") else { return }
            Task {
                let result: String
                do {
                    try await verifyLateInstallation()
                    try await verifyHeldReplacement()
                    try await verifyCallbackReentry()
                    try await verifyCancellationReentry()
                    try await verifyEnteredProducer()
                    result = "PASS: production request coordinator; original fallback and positive content exactly once; "
                        + "expiry/finish before task registration; old delayed producer denied; replacement/cancellation/handler reentry; "
                        + "entered producer versus expiry serialized; exact tasks awaited; actual NSE/builder/APNs=unverified; "
                        + "system donation completion cannot be revoked; RPC/account/cache/donation effects=0"
                } catch {
                    result = "FAIL: \(error)"
                }
                log(result)
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("notification-request-probe.txt"), options: .atomic,
                    )
                }
            }
        }

        private static func verifyLateInstallation() async throws {
            for expires in [true, false] {
                let owner = Owner()
                let receipts = Receipts()
                let ticket = owner.begin(original: "original") { value in
                    // A foreign UUID remains false, and reentry must not deadlock.
                    receipts.add(owner.isCurrent(.init()) ? "wrong-owner" : "delivered:\(value)")
                }
                if expires { try require(owner.expire(), "expiry failed") }
                else {
                    try require(owner.finish(ticket) { receipts.add("produced")
                    return "enriched"
                    }, "finish failed")
                }
                let task = Task {
                    receipts.add(Task.isCancelled ? "cancelled" : "not-cancelled")
                    owner.finish(ticket) { receipts.add("late-producer")
                    return "wrong"
                    }
                }
                owner.install(task, for: ticket)
                try require(task.isCancelled, "retired request accepted a late task handle")
                await task.value
                try require(!owner.expire(), "request completed twice")
                try require(
                    receipts.values == (expires
                        ? ["delivered:original", "cancelled"]
                        : ["produced", "delivered:enriched", "cancelled"]),
                    "late handle revived content or fallback contract changed",
                )
            }
        }

        private static func verifyHeldReplacement() async throws {
            let owner = Owner()
            let receipts = Receipts()
            let entered = Signal()
            let response = Signal()
            defer { response.open()
            owner.expire()
            }
            let old = owner.begin(original: "A-original") { receipts.add("A:\($0)") }
            let task = Task {
                entered.open()
                let released = await response.wait()
                receipts.add(released && Task.isCancelled ? "old-cancelled" : "old-invalid")
                owner.finish(old) { receipts.add("old-producer")
                return "wrong"
                }
            }
            owner.install(task, for: old)
            try await require(entered.wait(), "old response was not held")
            let current = owner.begin(original: "B-original") { receipts.add("B:\($0)") }
            try require(!owner.isCurrent(old) && owner.isCurrent(current) && task.isCancelled, "replacement failed")
            try require(owner.finish(current) { receipts.add("new-producer")
            return "B-enriched"
            }, "new finish failed")
            response.open()
            await task.value
            try require(
                receipts.values == ["A:A-original", "new-producer", "B:B-enriched", "old-cancelled"],
                "old work reached new handler or positive producer was not called",
            )
        }

        private static func verifyCallbackReentry() async throws {
            let owner = Owner()
            let receipts = Receipts()
            _ = owner.begin(original: "A-original") { value in
                receipts.add("A:\(value)")
                receipts.replace(owner.begin(original: "C-original") { receipts.add("C:\($0)") })
            }
            let superseded = owner.begin(original: "B-original") { receipts.add("B:\($0)") }
            guard let current = receipts.ticket else { throw Failure(description: "callback did not reenter begin") }
            try require(
                !owner.isCurrent(superseded) && owner.isCurrent(current),
                "outer begin replaced reentrant request",
            )
            let task = Task {}
            owner.install(task, for: superseded)
            await task.value
            try require(task.isCancelled, "reentrant replacement admitted old outer task")
            try require(!owner.finish(superseded) { receipts.add("wrong-producer")
            return "wrong"
            }, "old ticket finished")
            try require(owner.finish(current) { "C-enriched" }, "reentrant request lost authority")
            try require(
                receipts.values == ["A:A-original", "B:B-original", "C:C-enriched"],
                "handler reentry mixed callbacks or values",
            )
        }

        private static func verifyCancellationReentry() async throws {
            let owner = Owner()
            let receipts = Receipts()
            let entered = Signal()
            let response = Signal()
            defer { response.open()
            owner.expire()
            }
            let old = owner.begin(original: "A-original") { receipts.add("A:\($0)") }
            let task = Task {
                await withTaskCancellationHandler {
                    entered.open()
                    _ = await response.wait()
                    owner.finish(old) { receipts.add("late-producer")
                    return "wrong"
                    }
                } onCancel: {
                    receipts.add("cancelled")
                    receipts.replace(owner.begin(original: "C-original") { receipts.add("C:\($0)") })
                }
            }
            owner.install(task, for: old)
            try await require(entered.wait(), "cancellation handler not armed")
            let superseded = owner.begin(original: "B-original") { receipts.add("B:\($0)") }
            guard let current = receipts.ticket
                else { throw Failure(description: "cancellation did not reenter begin") }
            try require(
                !owner.isCurrent(superseded) && owner.isCurrent(current) && task.isCancelled,
                "cancellation callback could retire wrong generation",
            )
            try require(!owner.finish(superseded) { "wrong" }, "superseded begin finished")
            try require(owner.finish(current) { "C-enriched" }, "cancellation-created request failed")
            response.open()
            await task.value
            try require(
                receipts.values == ["cancelled", "B:B-original", "A:A-original", "C:C-enriched"],
                "cancel/handler order or exact callback ownership failed",
            )
        }

        private static func verifyEnteredProducer() async throws {
            let owner = Owner()
            let receipts = Receipts()
            let entered = Signal()
            let finished = Signal()
            let expiryStarted = Signal()
            let expired = Signal()
            let release = DispatchSemaphore(value: 0)
            defer { release.signal()
            owner.expire()
            }
            let ticket = owner.begin(original: "original") { receipts.add("delivered:\($0)") }
            DispatchQueue.global(qos: .utility).async {
                if !owner.finish(ticket, producing: {
                    entered.open()
                    let released = release.wait(timeout: .now() + 5) == .success
                    receipts.add(released ? "produced" : "producer-timeout")
                    return "enriched"
                }) { receipts.add("finish-denied") }
                finished.open()
            }
            try await require(entered.wait(), "producer not armed")
            DispatchQueue.global(qos: .utility).async {
                expiryStarted.open()
                receipts.add(owner.expire() ? "expired" : "expiry-already-finished")
                expired.open()
            }
            try await require(expiryStarted.wait(), "expiry not dispatched during producer")
            release.signal()
            try await require(finished.wait(), "producer/handler did not return")
            try await require(expired.wait(), "expiry did not return")
            try require(
                receipts.values.filter { $0 != "expiry-already-finished" } == ["produced", "delivered:enriched"]
                    && receipts.values.count == 3 && !owner.isCurrent(ticket),
                "entered producer and expiry were not serialized",
            )
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }
    }
#endif
