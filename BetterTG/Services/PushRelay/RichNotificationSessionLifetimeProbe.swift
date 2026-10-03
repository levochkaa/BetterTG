// RichNotificationSessionLifetimeProbe.swift

#if DEBUG
    import Foundation

    @MainActor enum RichNotificationSessionLifetimeProbe {
        private typealias Lifetime = RichNotificationSessionLifetime<Int>
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        /// Only lock-protected fixture receipts cross queues. No account/client is created.
        private final class Log: @unchecked Sendable {
            private let lock = NSLock()
            private var events = [String]()

            var values: [String] { lock.lock()
            defer { lock.unlock() }
            return events
            }

            func add(_ event: String) { lock.lock()
            events.append(event)
            lock.unlock()
            }
        }

        /// Cancellation deliberately does not release this stand-in for a pending
        /// pinned-TDLib continuation. Every test owns an explicit release.
        private final class Signal: @unchecked Sendable {
            private let lock = NSLock()
            private var opened = false
            private var waiters = [UUID: CheckedContinuation<Bool, Never>]()

            func open() {
                lock.lock()
                opened = true
                let waiters = Array(waiters.values)
                self.waiters.removeAll()
                lock.unlock()
                waiters.forEach { $0.resume(returning: true) }
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
                        let waiter = waiters.removeValue(forKey: id)
                        lock.unlock()
                        waiter?.resume(returning: false)
                    }
                }
            }
        }

        private final class BlockingGate: @unchecked Sendable {
            let entered = Signal()

            private let release = DispatchSemaphore(value: 0)

            func hold() -> Bool {
                entered.open()
                return release.wait(timeout: .now() + 5) == .success
            }

            func open() { release.signal() }
        }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-notification-session-lifetime") else { return }
            Task {
                let result: String
                do {
                    try verifyRegistration()
                    try await verifyHeldTasks()
                    try await verifyBootstrap()
                    try await verifyPublication()
                    result = "PASS: production lifetime/target authority; cancel before begin/create; "
                        + "bootstrap versus retirement and early callback; task completion before registration; "
                        + "three role cancellations, one exact resolver, late uncooperative response denied; "
                        + "strict synchronous publication/retirement order, one result/close claim; "
                        + "actual NSE/TDLib close and RPC cancellation/callback drain=unverified; "
                        + "entered synchronous IO may delay retirement; RPC/cache/account/donation effects=0"
                } catch { result = "FAIL: \(error)" }
                log(result)
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("notification-session-lifetime-probe.txt"),
                        options: .atomic,
                    )
                }
            }
        }

        private static func verifyRegistration() throws {
            let early = Lifetime(), events = Log()
            try require(early.finish(nil), "cancel-before-begin was not accepted")
            try require(!early.begin { events.add($0 == nil ? "nil" : "value") }, "retired begin admitted")
            try require(!early.createClient { events.add("create")
            return 11
            }, "retired client created")
            try require(events.values == ["nil"] && !early.claimClose(), "early retirement resumed/closed incorrectly")

            let between = Lifetime()
            try require(between.begin { _ in events.add("between") }, "continuation not installed")
            between.finish(nil)
            try require(!between.createClient { events.add("late-create")
            return 11
            }, "create crossed retirement")
            try require(events.values == ["nil", "between"], "between-registration completion not exact")

            let live = Lifetime(), replies = Log()
            try require(live.begin { value in
                // Reentry would deadlock if finish resumed its continuation under the lock.
                replies.add(value == 7 && !live.isCurrent(clientID: 11) ? "result" : "wrong")
            }, "live begin failed")
            try require(live.createClient { 11 }, "live client not installed")
            try require(!live.begin { _ in replies.add("duplicate") }, "duplicate resolve overwrote continuation")
            try require(live.reserve(.resolve, clientID: 22) == nil, "wrong client reserved resolver")
            let target = RichNotificationTarget(
                accountID: 101, peer: .init(kind: .supergroup, id: 77), serverMessageID: 88,
            )!
            let wrongChat: Int64 = -1_000_000_000_078
            let wrongTicket = wrongChat == target.expectedChatID ? live.reserve(.resolve, clientID: 11) : nil
            try require(wrongTicket == nil, "unrelated chat consumed sole resolver")
            let ticket = live.reserve(.resolve, clientID: 11)!
            try require(live.reserve(.resolve, clientID: 11) == nil, "duplicate resolver admitted")
            let other = Lifetime.Ticket(role: .resolve, clientID: 11)
            try require(!live.publish(other) { replies.add("wrong-publish") }, "foreign ticket published")
            try require(!live.finish(9, ticket: other), "foreign ticket finished")
            try require(live.publish(ticket) { replies.add("publish") }, "ordinary publication refused")
            try require(live.finish(7, ticket: ticket), "ordinary result refused")
            try require(
                !live.finish(8) && !live.publish(ticket) { replies.add("late-publish") },
                "late finish/write admitted",
            )
            try require(live.claimClose() && !live.claimClose(), "close claim not exact once")
            try require(
                replies.values == ["duplicate", "publish", "result"],
                "normal result or reentrant completion failed",
            )
        }

        private static func verifyHeldTasks() async throws {
            let lifetime = Lifetime(), began = Signal(), resumed = Signal(), response = Signal(), events = Log()
            defer { response.open()
            lifetime.finish(nil)
            }
            let outer = Task {
                await withTaskCancellationHandler {
                    await withCheckedContinuation { continuation in
                        _ = lifetime.begin { value in
                            events.add(value == nil ? "result-nil" : "result-value")
                            resumed.open()
                            continuation.resume(returning: value)
                        }
                        began.open()
                    }
                } onCancel: { lifetime.finish(nil) }
            }
            try await require(began.wait(), "outer continuation did not register")
            try require(lifetime.createClient { 11 }, "held-task client not installed")
            var tasks = [Task<Void, Never>]()
            var completed = [Signal]()
            for role in [Lifetime.Role.configure, .process, .resolve] {
                let ticket = lifetime.reserve(role, clientID: 11)!
                let entered = Signal(), done = Signal()
                completed.append(done)
                let task = Task {
                    entered.open()
                    let released = await response.wait()
                    events.add(released && Task.isCancelled ? "cancelled" : "not-cancelled")
                    if lifetime.publish(ticket, { events.add("late-write") }) { events.add("admitted") }
                    if lifetime.finish(7, ticket: ticket) { events.add("late-finish") }
                    lifetime.complete(ticket)
                    done.open()
                }
                lifetime.install(task, for: ticket)
                tasks.append(task)
                try await require(entered.wait(), "role task never entered held response")
            }
            outer.cancel()
            try await require(resumed.wait(), "outer cancellation did not resume result")
            try await require(outer.value == nil, "outer cancellation produced a result")
            try require(lifetime.claimClose(), "close could not precede held RPC returns")
            try require(events.values == ["result-nil"], "held RPC unexpectedly completed before close")
            response.open()
            for done in completed {
                try await require(
                    done.wait(),
                    "cancelled role did not return from released response",
                )
            }
            for task in tasks {
                await task.value
            }
            try require(
                events.values.filter { $0 == "cancelled" }.count == 3 && events.values.count == 4,
                "late response published or role task was not cancelled",
            )

            let fast = Lifetime(), returned = Signal()
            _ = fast.begin { _ in }
            _ = fast.createClient { 22 }
            let ticket = fast.reserve(.process, clientID: 22)!
            let task = Task { fast.complete(ticket)
            returned.open()
            }
            try await require(returned.wait(), "fast role did not complete")
            await task.value
            fast.install(task, for: ticket)
            try require(task.isCancelled && !fast.isCurrent(ticket), "completed-before-install role revived")
            let pending = fast.reserve(.resolve, clientID: 22)!
            fast.finish(nil)
            let late = Task {}
            fast.install(late, for: pending)
            try require(late.isCancelled, "handle installed after retirement was not cancelled")
        }

        private static func verifyBootstrap() async throws {
            let lifetime = Lifetime(), gate = BlockingGate(), callbackStarted = Signal(), callbackDone = Signal()
            let retireStarted = Signal(), retired = Signal(), created = Signal(), events = Log()
            defer { gate.open()
            lifetime.finish(nil)
            }
            _ = lifetime.begin { _ in events.add("retired")
            retired.open()
            }
            DispatchQueue.global(qos: .utility).async {
                let admitted = lifetime.createClient {
                    DispatchQueue.global(qos: .utility).async {
                        callbackStarted.open()
                        _ = lifetime.isCurrent(clientID: 11)
                        callbackDone.open()
                    }
                    let released = gate.hold()
                    events.add(released ? "create" : "create-timeout")
                    return 11
                }
                if !admitted { events.add("create-denied") }
                created.open()
            }
            try await require(gate.entered.wait(), "bootstrap not armed")
            try await require(callbackStarted.wait(), "callback not armed")
            DispatchQueue.global(qos: .utility).async {
                retireStarted.open()
                lifetime.finish(nil)
            }
            try await require(retireStarted.wait(), "retirement not dispatched during bootstrap")
            gate.open()
            try await require(created.wait(), "bootstrap deadlocked")
            try await require(retired.wait(), "bootstrap retirement deadlocked")
            try await require(callbackDone.wait(), "early callback deadlocked")
            try require(
                events.values == ["create", "retired"] && lifetime.claimClose() && !lifetime.claimClose(),
                "close crossed client creation or result repeated",
            )
        }

        private static func verifyPublication() async throws {
            let lifetime = Lifetime(), gate = BlockingGate(), retireStarted = Signal(), retired = Signal()
            let published = Signal(), events = Log()
            defer { gate.open()
            lifetime.finish(nil)
            }
            _ = lifetime.begin { _ in
                events.add(lifetime.isCurrent(clientID: 11) ? "still-live" : "retired")
                retired.open()
            }
            _ = lifetime.createClient { 11 }
            let ticket = lifetime.reserve(.resolve, clientID: 11)!
            DispatchQueue.global(qos: .utility).async {
                if !lifetime.publish(ticket, {
                    let released = gate.hold()
                    events.add(released ? "write" : "write-timeout")
                }) { events.add("write-denied") }
                published.open()
            }
            try await require(gate.entered.wait(), "synchronous publication not armed")
            DispatchQueue.global(qos: .utility).async {
                retireStarted.open()
                lifetime.finish(nil)
            }
            try await require(retireStarted.wait(), "publication retirement not dispatched")
            gate.open()
            try await require(published.wait(), "publication deadlocked")
            try await require(retired.wait(), "publication retirement deadlocked")
            try require(
                !lifetime.publish(ticket) { events.add("late-write") }
                            && events.values == ["write", "retired"],
                "write did not linearize before retirement",
            )
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }
    }
#endif
