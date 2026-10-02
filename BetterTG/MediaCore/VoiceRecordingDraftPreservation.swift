// VoiceRecordingDraftPreservation.swift

import Foundation
import UIKit

// MARK: - VoiceRecordingLifecycle

/// Re-enabling the UI must not revive an intent from before navigation or permission loss.
struct VoiceRecordingLifecycle {
    enum Reason: Hashable {
        case interaction
        case background
        case audioInterruption
    }

    private(set) var generation = UInt64.zero

    private var reasons = Set<Reason>()

    var isSuspended: Bool { !reasons.isEmpty }

    mutating func suspend(_ reason: Reason = .interaction) -> Bool {
        guard reasons.insert(reason).inserted else { return false }
        generation &+= 1
        return true
    }

    mutating func resumeInteraction() {
        resume(.interaction)
    }

    mutating func resume(_ reason: Reason) {
        reasons.remove(reason)
    }

    func permitsContinuation(_ generation: UInt64) -> Bool {
        !isSuspended && self.generation == generation
    }

    func requireCurrentIntent(_ generation: UInt64) throws {
        guard permitsContinuation(generation) else { throw CancellationError() }
    }
}

// MARK: - VoiceRecordingBackgroundLease

/// Expiry releases time ownership, never canonical files or accepted submissions.
@MainActor final class VoiceRecordingBackgroundLease {
    @MainActor struct Backend {
        static var application: Backend {
            Backend(
                begin: { expiration in UIApplication.shared.beginBackgroundTask(
                    withName: "Voice recording checkpoint",
                    expirationHandler: { MainActor.assumeIsolated { expiration() } },
                ) },
                end: { UIApplication.shared.endBackgroundTask($0) },
            )
        }

        let begin: @MainActor (@escaping @MainActor @Sendable () -> Void) -> UIBackgroundTaskIdentifier
        let end: @MainActor (UIBackgroundTaskIdentifier) -> Void
    }

    private let backend: Backend
    private var identifier = UIBackgroundTaskIdentifier.invalid
    private var isStarting = true
    private var expiredDuringStart = false

    init(backend: Backend? = nil) {
        self.backend = backend ?? .application
        self.identifier = self.backend.begin { [weak self] in self?.expire() }
        self.isStarting = false
        if expiredDuringStart { finish() }
    }

    func finish() {
        let previous = identifier
        identifier = .invalid
        if previous != .invalid { backend.end(previous) }
    }

    private func expire() {
        if isStarting {
            expiredDuringStart = true
        } else {
            finish()
        }
    }
}

// MARK: - VoiceRecordingCheckpointProtection

@MainActor final class VoiceRecordingCheckpointProtection {
    private let backend: VoiceRecordingBackgroundLease.Backend?
    private var lease: VoiceRecordingBackgroundLease?
    private var task: Task<Void, Never>?
    private var taskID: UUID?

    var hasPendingWork: Bool { task != nil }

    init(backend: VoiceRecordingBackgroundLease.Backend? = nil) {
        self.backend = backend
    }

    func protect(_ tasks: [Task<Void, Never>]) {
        guard task == nil, !tasks.isEmpty else { return }
        let id = UUID()
        let lease = VoiceRecordingBackgroundLease(backend: backend)
        self.lease = lease
        taskID = id
        task = Task { [weak self] in
            for task in tasks {
                await task.value
            }
            lease.finish()
            guard let self, taskID == id else { return }
            taskID = nil
            self.lease = nil
            task = nil
        }
    }

    func finish() { lease?.finish() }

    func wait() async { await task?.value }
}

// MARK: - VoiceRecordingDraftPreservation

/// Registered on main before file work can suspend. A reopened route waits for the
/// previous owner's canonical recording revision before exposing recording controls.
@MainActor enum VoiceRecordingDraftPreservation {
    private static var pending = [ChatDraftKey: [UUID: Task<Void, Never>]]()

    static func start(
        for destination: ChatDraftKey,
        operation: @escaping @MainActor () async -> Void,
    ) -> Task<Void, Never> {
        let id = UUID()
        let task = Task {
            await operation()
            pending[destination]?[id] = nil
            if pending[destination]?.isEmpty == true {
                pending[destination] = nil
            }
        }
        pending[destination, default: [:]][id] = task
        return task
    }

    static func wait(for destination: ChatDraftKey) async {
        while !Task.isCancelled, let operations = pending[destination] {
            for task in operations.values {
                await task.value
            }
        }
    }
}

#if DEBUG
    extension VoiceRecordingDraftPreservation {
        static func runDebugProbeIfRequested() {
            if ProcessInfo.processInfo.arguments.contains("-media-probe-voice-lifecycle") {
                VoiceRecordingLifecycleProbe.run()
                return
            }
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-voice-preservation") else { return }
            Task {
                let key = ChatDraftKey(accountID: UUID(), chatID: Int64.min + 17, topic: nil)
                let otherAccount = ChatDraftKey(accountID: UUID(), chatID: key.chatID, topic: nil)
                let gate = ProbeGate()
                var canonicalRevision = 0
                var restoredRevision: Int?
                var otherRouteRestored = false
                let save = start(for: key) {
                    await gate.wait()
                    canonicalRevision = 1
                }
                let restoration = Task {
                    await wait(for: key)
                    restoredRevision = canonicalRevision
                }
                let unrelated = Task {
                    await wait(for: otherAccount)
                    otherRouteRestored = true
                }
                await unrelated.value
                try? await Task<Never, Never>.sleep(for: .milliseconds(50))
                let blockedUntilSave = restoredRevision == nil
                gate.release()
                await save.value
                await restoration.value

                var lifecycle = VoiceRecordingLifecycle()
                let oldIntent = lifecycle.generation
                let suspended = lifecycle.suspend()
                let rejectedWhileSuspended = !lifecycle.permitsContinuation(oldIntent)
                lifecycle.resumeInteraction()
                let oldIntentStillRejected = !lifecycle.permitsContinuation(oldIntent)
                let newIntentAllowed = lifecycle.permitsContinuation(lifecycle.generation)
                let passed = blockedUntilSave && otherRouteRestored && restoredRevision == 1
                    && suspended && rejectedWhileSuspended && oldIntentStillRejected && newIntentAllowed
                    && pending[key] == nil
                let result = passed
                    ? "Voice preservation probe: restore-waits=true, canonical-revision=true, account-isolation=true, "
                        + "barrier-cleanup=true, suspend-invalidates-intent=true, reenable-keeps-old-intent-invalid=true, "
                        + "new-intent-allowed=true"
                    : "Voice preservation probe failed"
                if let url = FileManager.default
.urls(for: .documentDirectory, in: .userDomainMask)
.first?
                    .appendingPathComponent("voice-preservation-probe.txt")
                {
                    try? Data(result.utf8).write(to: url, options: .atomic)
                }
                log(result)
            }
        }

        private final class ProbeGate {
            private var continuation: CheckedContinuation<Void, Never>?
            private var released = false

            func wait() async {
                guard !released else { return }
                await withCheckedContinuation { continuation = $0 }
            }

            func release() {
                released = true
                continuation?.resume()
                continuation = nil
            }
        }
    }
#endif
