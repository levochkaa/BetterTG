// VoiceRecordingLifecycleProbe.swift

#if DEBUG
    import AVFoundation
    import Foundation
    import TDLibKitDynamic
    import UIKit

    @MainActor enum VoiceRecordingLifecycleProbe {
        @MainActor private final class LifecycleState {
            var value = VoiceRecordingLifecycle()
        }

        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        private final class Gate {
            private(set) var entered = false

            private var continuation: CheckedContinuation<Void, Never>?
            private var opened = false

            func wait() async {
                entered = true
                if !opened { await withCheckedContinuation { continuation = $0 } }
            }

            func open() {
                opened = true
                continuation?.resume()
                continuation = nil
            }

            func waitUntilEntered() async throws {
                let deadline = ContinuousClock.now.advanced(by: .seconds(10))
                while !entered {
                    guard ContinuousClock.now < deadline else { throw Failure(description: "gate timeout") }
                    try await Task<Never, Never>.sleep(for: .milliseconds(10))
                }
            }
        }

        private enum SendPoint: String, CaseIterable {
            case promotion, encoding, replyValidation, resendPreflight, acceptedRequest
        }

        private static var stage = "started"

        static func run() {
            Task {
                write("Voice lifecycle probe started")
                var timedOut = false
                let timeout = Task {
                    do { try await Task<Never, Never>.sleep(for: .seconds(60)) } catch { return }
                    timedOut = true
                    write("Voice lifecycle probe failed: timeout at \(stage)")
                }
                defer { timeout.cancel() }
                let root = FileManager.default
.temporaryDirectory
                    .appendingPathComponent("voice-lifecycle-\(UUID().uuidString)", isDirectory: true)
                let result: String
                do {
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: root) }
                    try verifyReasons()
                    try await verifyCheckpoint(root: root)
                    for point in SendPoint.allCases {
                        try await verifySend(point, root: root)
                    }
                    result = "Voice lifecycle probe passed: independent-navigation/background/audio-reasons; "
                        + "permission/trim-resume/preview-intent-epoch=true; foreground-clears-only-background; "
                        + "actual-PCM/recording-store/codec/send-store=true; exact-route-barrier/account-isolation=true; "
                        + "duplicate-background=one-lease; expiry=save-not-cancelled; immediate-expiry=handled; "
                        + "promotion/encode/reply-validation/resend-preflight=stale-send-rejected; "
                        + "accepted-request=actual-ID-registered; promoted-recording=not-resurrected; "
                        + "caption/reply/topic/route-preserved; failed-append=prior-preserved; explicit-discard=destructive; "
                        + "ChatVM/microphone/OS-notifications/server-RPC=unverified; user-stores=untouched"
                } catch {
                    result = "Voice lifecycle probe failed at \(stage): \(error)"
                }
                if !timedOut { write(result) }
            }
        }

        private static func verifyReasons() throws {
            stage = "reasons"
            var lifecycle = VoiceRecordingLifecycle()
            let permissionIntent = lifecycle.generation
            try require(lifecycle.suspend(.background), "background reason missing")
            let epoch = lifecycle.generation
            try require(
                !lifecycle.suspend(.background) && lifecycle.generation == epoch,
                "duplicate event renewed epoch",
            )
            lifecycle.resumeInteraction()
            try require(lifecycle.isSuspended, "UI resume cleared system background")
            _ = lifecycle.suspend(.audioInterruption)
            _ = lifecycle.suspend()
            lifecycle.resume(.background)
            try require(lifecycle.isSuspended, "foreground cleared navigation/interruption")
            lifecycle.resume(.audioInterruption)
            try require(lifecycle.isSuspended, "audio end cleared navigation")
            lifecycle.resumeInteraction()
            try require(
                !lifecycle.isSuspended && !lifecycle.permitsContinuation(permissionIntent),
                "old permission revived",
            )
            try lifecycle.requireCurrentIntent(lifecycle.generation)
            var immediateEnds = 0
            let immediate = VoiceRecordingBackgroundLease(backend: .init(begin: { expire in
                expire()
                return UIBackgroundTaskIdentifier(rawValue: 91)
            }, end: { _ in immediateEnds += 1 }))
            immediate.finish()
            try require(immediateEnds == 1, "immediate lease expiry lost/duplicated")
        }

        private static func verifyCheckpoint(root: URL) async throws {
            stage = "checkpoint"
            let directory = root.appendingPathComponent("checkpoint")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let route = ChatDraftKey(accountID: UUID(), chatID: 70, topic: nil)
            let store = VoiceRecordingDraftStore(directoryURL: directory.appendingPathComponent("store"))
            let draft = try await makeRecording(root: directory, route: route)
            let gate = Gate()
            defer { gate.open() }
            var result: Result<VoiceRecordingDraft, Swift.Error>?
            let save = VoiceRecordingDraftPreservation.start(for: route) {
                await gate.wait()
                do { result = try await .success(store.adopt(draft)) } catch { result = .failure(error) }
            }
            var begins = 0
            var ends = 0
            var expiration: (@MainActor @Sendable () -> Void)?
            let protection = VoiceRecordingCheckpointProtection(backend: .init(begin: { callback in
                begins += 1
                expiration = callback
                return UIBackgroundTaskIdentifier(rawValue: begins)
            }, end: { _ in ends += 1 }))
            protection.protect([save])
            protection.protect([save])
            try await gate.waitUntilEntered()
            var restored: [VoiceRecordingDraft]?
            let restore = Task {
                await VoiceRecordingDraftPreservation.wait(for: route)
                restored = await store.drafts(for: route)
            }
            await VoiceRecordingDraftPreservation.wait(for: .init(accountID: UUID(), chatID: route.chatID, topic: nil))
            expiration?()
            expiration?()
            protection.protect([save])
            try require(
                begins == 1 && ends == 1 && result == nil && restored == nil,
                "expiry cancelled save/renewed lease",
            )
            gate.open()
            await protection.wait()
            await restore.value
            guard let result else { throw Failure(description: "missing canonical result") }
            let canonical = try result.get()
            try require(
                restored?.map(\.id) == [canonical.id] && !protection.hasPendingWork,
                "route join/cleanup failed",
            )
            try require(
                canonical.caption == draft.caption && canonical.replyMessageID == draft.replyMessageID
                && canonical.sendTopic == draft.sendTopic && canonical.destination == route,
                "checkpoint metadata changed",
            )

            stage = "trim-resume"
            let lifecycle = LifecycleState()
            let intent = lifecycle.value.generation
            let trimGate = Gate()
            defer { trimGate.open() }
            var trimmed: VoiceRecordingDraft?
            var trimError: Swift.Error?
            var resumes = 0
            let trim = VoiceRecordingDraftPreservation.start(for: route) {
                let output = directory.appendingPathComponent("trim.wav")
                do {
                    let inspection = try await VoiceNotePCMEditor.trim(
                        canonical.fileURL,
                        outputURL: output,
                        range: 0.1..<0.8,
                    )
                    await trimGate.wait()
                    trimmed = try await store.replaceMedia(in: canonical, with: output, inspection: inspection)
                    if lifecycle.value.permitsContinuation(intent) { resumes += 1 }
                } catch { trimError = error }
            }
            try await trimGate.waitUntilEntered()
            _ = lifecycle.value.suspend(.audioInterruption)
            lifecycle.value.resumeInteraction()
            lifecycle.value.resume(.background)
            try require(lifecycle.value.isSuspended, "foreground/UI lifted audio suspension")
            lifecycle.value.resume(.audioInterruption)
            trimGate.open()
            await trim.value
            if let trimError { throw trimError }
            guard let trimmed else { throw Failure(description: "trim missing") }
            try require(resumes == 0 && abs(trimmed.exactDuration - 0.7) < 0.01, "old trim resumed or save lost")
            let current = try await store.updateTrim(in: trimmed, range: trimmed.effectiveRange)
            let appendOutput = directory.appendingPathComponent("stale-append.wav")
            let appendInspection = try await VoiceNotePCMEditor.concatenate(
                [trimmed.fileURL, trimmed.fileURL],
                outputURL: appendOutput,
            )
            do {
                _ = try await store.replaceMedia(in: trimmed, with: appendOutput, inspection: appendInspection)
                throw Failure(description: "stale append committed")
            } catch VoiceRecordingDraftStoreError.staleRevision {}
            let preserved = await store.drafts(for: route)
            try require(preserved.first == current && exists(current.fileURL), "failed append removed prior canonical")
            await store.discard(id: current.id)
            try require(!exists(current.fileURL), "explicit discard retained canonical file")
        }

        private static func verifySend(_ point: SendPoint, root: URL) async throws {
            stage = point.rawValue
            let directory = root.appendingPathComponent(point.rawValue)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let route = ChatDraftKey(accountID: UUID(), chatID: 71, topic: nil)
            let recordingStore = VoiceRecordingDraftStore(directoryURL: directory.appendingPathComponent("recordings"))
            let sendStore = VoiceNoteDraftStore(
                directoryURL: directory.appendingPathComponent("sends"),
                legacyBindingAllowed: { _ in false },
            )
            let preparedRecording = try await makeRecording(root: directory, route: route)
            let recording = try await recordingStore.adopt(preparedRecording)
            let snapshot = VoiceNoteSendDraft(
                id: recording.id, chatID: recording.chatID, caption: recording.caption, createdAt: recording.createdAt,
                duration: 1, enqueueStartedAt: nil, failedSendState: nil, fileURL: recording.fileURL,
                isEncoded: false, replyMessageID: recording.replyMessageID, replyTo: recording.replyTo,
                sendTopic: recording.sendTopic, temporaryMessageID: nil, waveform: recording.waveform,
                destination: route,
            )
            let lifecycle = LifecycleState()
            let intent = lifecycle.value.generation
            let gate = Gate()
            defer { gate.open() }
            var requests = 0
            var failure: Swift.Error?
            let operation = Task {
                var draft = snapshot
                var lease: VoiceNoteFinalizationLease?
                var requestStarted = false
                do {
                    draft = try await sendStore.adopt(draft)
                    if point == .promotion { await gate.wait() }
                    await recordingStore.discard(id: recording.id)
                    let claim = try await sendStore.claimFinalization(draft)
                    lease = claim.lease
                    let output = try await VoiceNoteCodec.encodeOggOpus(from: claim.draft.fileURL)
                    defer { try? FileManager.default.removeItem(at: output) }
                    if point == .encoding { await gate.wait() }
                    draft = try await sendStore.replaceFile(in: claim.draft, with: output, finalization: claim.lease)
                    try lifecycle.value.requireCurrentIntent(intent)
                    draft = try await sendStore.beginEnqueue(draft, finalization: claim.lease)
                    if point == .replyValidation || point == .resendPreflight { await gate.wait() }
                    try lifecycle.value.requireCurrentIntent(intent)
                    requestStarted = true
                    requests += 1
                    if point == .acceptedRequest { await gate.wait() }
                    _ = try await sendStore.registerEnqueued(draft, temporaryMessageID: 4201, finalization: claim.lease)
                    lease = nil
                } catch is CancellationError {
                    if let lease, !requestStarted, draft.enqueueStartedAt != nil {
                        _ = try? await sendStore.markPending(draft, failedSendState: nil, finalization: lease)
                    }
                } catch { failure = error }
                if let lease { await sendStore.finishFinalization(lease) }
            }
            try await gate.waitUntilEntered()
            _ = lifecycle.value.suspend(.background)
            _ = lifecycle.value.suspend(.audioInterruption)
            lifecycle.value.resume(.background)
            lifecycle.value.resume(.audioInterruption)
            lifecycle.value.resumeInteraction()
            gate.open()
            await operation.value
            if let failure { throw failure }
            let status = await sendStore.status(id: recording.id, destination: route)
            guard let draft = status.draft else { throw Failure(description: "promoted send draft missing") }
            let oldRecordings = await recordingStore.drafts(for: route)
            let accepted = point == .acceptedRequest
            try require(
                oldRecordings.isEmpty && exists(draft.fileURL) && draft.isEncoded && !status.isFinalizing,
                "promotion ownership lost or recording resurrected",
            )
            try require(
                requests == (accepted ? 1 : 0)
                && draft.temporaryMessageID == (accepted ? 4201 : nil)
                && (accepted || draft.enqueueStartedAt == nil),
                "pre-request fence or accepted-ID registration failed",
            )
            try require(
                draft.caption == snapshot.caption && draft.replyTo == snapshot.replyTo
                && draft.replyMessageID == snapshot.replyMessageID && draft.sendTopic == snapshot.sendTopic
                && draft.destination == route,
                "send metadata changed",
            )
        }

        private static func makeRecording(root: URL, route: ChatDraftKey) async throws -> VoiceRecordingDraft {
            let url = root.appendingPathComponent("\(UUID().uuidString).wav")
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 57600),
                  let samples = buffer.floatChannelData?[0]
            else { throw Failure(description: "PCM fixture") }
            buffer.frameLength = buffer.frameCapacity
            for index in 0..<Int(buffer.frameLength) {
                samples[index] = sin(Float(index) * 2 * .pi * 440 / 48000) * 0.2
            }
            try AVAudioFile(forWriting: url, settings: VoiceNotePCMEditor.recordingSettings).write(from: buffer)
            let inspection = try await VoiceNotePCMEditor.inspect(url)
            return VoiceRecordingDraft(
                id: UUID(), chatID: route.chatID, caption: .init(entities: [], text: "frozen caption"),
                createdAt: Foundation.Date(), exactDuration: inspection.duration, fileURL: url,
                replyMessageID: 17,
                replyTo: .inputMessageReplyToMessage(.init(
                    checklistTaskId: 0, messageId: 17, pollOptionId: "", quote: nil,
                )),
                sendTopic: .messageTopicForum(.init(forumTopicId: 42)),
                revision: 0, trimEnd: nil, trimStart: nil, waveform: inspection.waveform, destination: route,
            )
        }

        private static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func write(_ message: String) {
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(message.utf8).write(
                    to: directory.appendingPathComponent("voice-lifecycle-probe.txt"),
                    options: .atomic,
                )
            }
            log(message)
        }
    }
#endif
