// VoiceNoteFinalizationProbe.swift

#if DEBUG
    import AVFoundation
    import Foundation
    import TDLibKit

    enum VoiceNoteFinalizationProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        /// Deliberately ignores cancellation, like a native codec or an already
        /// submitted RPC. Tests control exactly when the operation returns.
        private actor Gate {
            private var entered = false
            private var opened = false
            private var waiter: CheckedContinuation<Void, Never>?
            private var observers = [CheckedContinuation<Void, Never>]()

            func wait() async {
                entered = true
                observers.forEach { $0.resume() }
                observers.removeAll()
                guard !opened else { return }
                await withCheckedContinuation { waiter = $0 }
            }

            func waitUntilEntered() async {
                guard !entered else { return }
                await withCheckedContinuation { observers.append($0) }
            }

            func open() {
                opened = true
                waiter?.resume()
                waiter = nil
            }
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-voice-finalization") else { return }
            Task {
                let root = FileManager.default
.temporaryDirectory
                    .appendingPathComponent("voice-finalization-\(UUID().uuidString)", isDirectory: true)
                let result: String
                do {
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: root) }
                    try await verify(root: root)
                    result = "Voice finalization probe passed: canonical-lease; suspended-encode/reopen; "
                        + "duplicate-claim/discard/mutation-denied; unique-native-codec-outputs; "
                        + "stale-snapshot/token/release-fenced; cancel-before-RPC-retryable; "
                        + "cancel-after-RPC-actual-ID-registered; provisional-outcome-held; "
                        + "process-death-runtime-lease-released; unresolved-enqueue-retained; "
                        + "route/caption/reply-preserved; unrelated-file-preserved; isolated-stores=true"
                } catch {
                    result = "Voice finalization probe failed: \(error)"
                }
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("voice-finalization-probe.txt"), options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func rejects(_ operation: () async throws -> Void) async -> Bool {
            do { try await operation()
            return false
            } catch { return true }
        }

        private static func makeDraft(root: URL, route: ChatDraftKey) throws -> VoiceNoteSendDraft {
            let url = root.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600),
                  let samples = buffer.floatChannelData?[0]
            else { throw Failure(description: "PCM fixture") }
            buffer.frameLength = buffer.frameCapacity
            for index in 0..<Int(buffer.frameLength) {
                samples[index] = sin(Float(index) * 2 * .pi * 440 / 16000) * 0.2
            }
            try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
            return VoiceNoteSendDraft(
                id: UUID(), chatID: route.chatID, caption: .init(entities: [], text: "preserve caption"),
                createdAt: Foundation.Date(), duration: 1, enqueueStartedAt: nil, failedSendState: nil,
                fileURL: url, isEncoded: false, replyMessageID: 17, replyTo: nil,
                sendTopic: .messageTopicForum(.init(forumTopicId: 42)), temporaryMessageID: nil,
                waveform: Data([1, 2, 3]), destination: route,
            )
        }

        private static func verify(root: URL) async throws {
            let directory = root.appendingPathComponent("store", isDirectory: true)
            let store = VoiceNoteDraftStore(directoryURL: directory, legacyBindingAllowed: { _ in false })
            let route = ChatDraftKey(accountID: UUID(), chatID: 100, topic: nil)
            let snapshot = try makeDraft(root: root, route: route)
            let claim = try await store.claimFinalization(snapshot)
            let raw = claim.draft
            let encodeGate = Gate()
            let encoding = Task {
                await encodeGate.wait()
                return try await VoiceNoteCodec.encodeOggOpus(from: raw.fileURL)
            }
            await encodeGate.waitUntilEntered()
            let restored = await store.drafts(for: route)
            let busy = await store.status(id: raw.id, destination: route)
            let duplicate = await rejects { _ = try await store.claimFinalization(snapshot) }
            let removeDenied = await !(store.remove(snapshot))
            let mutationDenied = await rejects { _ = try await store.markPending(snapshot) }
            await encodeGate.open()
            let firstOutput = try await encoding.value
            let secondOutput = try await VoiceNoteCodec.encodeOggOpus(from: raw.fileURL)
            try require(restored.map(\.id) == [raw.id] && busy.isFinalizing, "reopened route missed canonical lease")
            try require(duplicate && removeDenied && mutationDenied, "active owner bypassed")
            try require(
                firstOutput != secondOutput && exists(firstOutput) && exists(secondOutput),
                "codec outputs collided",
            )
            let encoded = try await store.replaceFile(in: snapshot, with: firstOutput, finalization: claim.lease)
            try require(
                !exists(raw.fileURL) && exists(encoded.fileURL) && exists(secondOutput),
                "replace removed another attempt",
            )
            let staleAdoption = try await store.adopt(snapshot)
            try require(
                staleAdoption.fileURL == encoded.fileURL && staleAdoption.isEncoded,
                "stale adoption rewound encoding",
            )
            try require(
                encoded.caption == snapshot.caption && encoded.replyMessageID == snapshot.replyMessageID
                    && encoded.sendTopic == snapshot.sendTopic && encoded.destination == route,
                "canonical metadata changed",
            )

            let unrelatedRoute = ChatDraftKey(accountID: UUID(), chatID: route.chatID, topic: nil)
            let unrelated = try await store.claimFinalization(makeDraft(root: root, route: unrelatedRoute))
            var enqueued = try await store.beginEnqueue(snapshot, finalization: claim.lease)
            let wrongToken = await rejects {
                _ = try await store.registerEnqueued(enqueued, temporaryMessageID: -11, finalization: unrelated.lease)
            }
            let early = try await store.handleSendSucceeded(delivery: enqueued.deliveryKey, temporaryMessageID: -11)
            let duringEnqueue = await store.drafts(for: route)
            let enqueueAdoption = try await store.adopt(snapshot)
            try require(
                wrongToken && early == nil && exists(encoded.fileURL)
                    && duringEnqueue.first?.enqueueStartedAt != nil && enqueueAdoption.enqueueStartedAt != nil,
                "stale token/snapshot released enqueue ownership",
            )
            let registration = try await store.registerEnqueued(
                enqueued,
                temporaryMessageID: -11,
                finalization: claim.lease,
            )
            let resolvedDrafts = await store.drafts(for: route)
            try require(
                // The sent note keeps its uploaded file for the abandoned-file sweep; only the draft is resolved.
                registration.outcome == .succeeded && exists(encoded.fileURL)
                    && !resolvedDrafts.contains(where: { $0.id == enqueued.id }),
                "exact early success did not resolve",
            )
            try require(exists(unrelated.draft.fileURL) && exists(secondOutput), "resolution removed unrelated file")
            await store.finishFinalization(unrelated.lease)

            // A cancelled native operation must finish before its lease is released.
            let cancelClaim = try await store.claimFinalization(makeDraft(root: root, route: route))
            let cancelGate = Gate()
            let cancelOutput = root.appendingPathComponent("cancelled-attempt.ogg")
            let cancelledEncoding = Task {
                await cancelGate.wait()
                do {
                    try Data([1]).write(to: cancelOutput)
                    defer { try? FileManager.default.removeItem(at: cancelOutput) }
                    try Task.checkCancellation()
                    _ = try await store.replaceFile(
                        in: cancelClaim.draft,
                        with: cancelOutput,
                        finalization: cancelClaim.lease,
                    )
                } catch {
                    await store.finishFinalization(cancelClaim.lease)
                    throw error
                }
            }
            await cancelGate.waitUntilEntered()
            cancelledEncoding.cancel()
            let cancellationHeld = await !(store.remove(cancelClaim.draft))
            await cancelGate.open()
            let cancelled = await rejects { try await cancelledEncoding.value }
            try require(
                cancellationHeld && cancelled && exists(cancelClaim.draft.fileURL) && !exists(cancelOutput),
                "cancelled worker ownership",
            )
            let nextClaim = try await store.claimFinalization(cancelClaim.draft)
            await store.finishFinalization(cancelClaim.lease)
            let staleReplace = await rejects {
                _ = try await store.replaceFile(
                    in: cancelClaim.draft,
                    with: secondOutput,
                    finalization: cancelClaim.lease,
                )
            }
            let nextBusy = await store.status(id: nextClaim.draft.id, destination: route)
            try require(
                staleReplace && nextBusy.isFinalizing && exists(secondOutput),
                "stale release/replace affected new owner",
            )
            let nextEncoded = try await store.replaceFile(
                in: nextClaim.draft,
                with: secondOutput,
                finalization: nextClaim.lease,
            )
            enqueued = try await store.beginEnqueue(nextEncoded, finalization: nextClaim.lease)
            let staleRegister = await rejects {
                _ = try await store.registerEnqueued(enqueued, temporaryMessageID: -12, finalization: cancelClaim.lease)
            }
            try require(staleRegister, "stale registration accepted")
            // A cancelled preflight has not submitted an RPC and can safely retry.
            let preflight = try await store.markPending(enqueued, finalization: nextClaim.lease)
            await store.finishFinalization(nextClaim.lease)
            try require(
                preflight.enqueueStartedAt == nil && exists(preflight.fileURL),
                "preflight rollback lost source",
            )

            let sendClaim = try await store.claimFinalization(preflight)
            let sending = try await store.beginEnqueue(preflight, finalization: sendClaim.lease)
            let sendGate = Gate()
            let rpc = Task {
                await sendGate.wait()
                // Actual returned ID must be persisted even when the awaiting UI is cancelled.
                return try await store.registerEnqueued(sending, temporaryMessageID: -12, finalization: sendClaim.lease)
            }
            await sendGate.waitUntilEntered()
            rpc.cancel()
            let sendDiscardDenied = await !(store.remove(sending))
            await sendGate.open()
            let accepted = try await rpc.value
            let registeredDiscardDenied = await !(store.remove(preflight))
            try require(
                sendDiscardDenied && registeredDiscardDenied && accepted.draft.temporaryMessageID == -12
                    && exists(accepted.draft.fileURL),
                "cancel-after-RPC lost accepted message ownership",
            )
            _ = try await store.handleSendSucceeded(delivery: accepted.draft.deliveryKey, temporaryMessageID: -12)

            let deathClaim = try await store.claimFinalization(makeDraft(root: root, route: route))
            let restarted = VoiceNoteDraftStore(directoryURL: directory, legacyBindingAllowed: { _ in false })
            let restartClaim = try await restarted.claimFinalization(deathClaim.draft)
            let restartOutput = try await VoiceNoteCodec.encodeOggOpus(from: restartClaim.draft.fileURL)
            let restartEncoded = try await restarted.replaceFile(
                in: restartClaim.draft,
                with: restartOutput,
                finalization: restartClaim.lease,
            )
            let interrupted = try await restarted.beginEnqueue(restartEncoded, finalization: restartClaim.lease)
            _ = try await restarted.handleSendSucceeded(delivery: interrupted.deliveryKey, temporaryMessageID: -13)
            let anotherRestart = VoiceNoteDraftStore(directoryURL: directory, legacyBindingAllowed: { _ in false })
            let unresolved = await anotherRestart.drafts(for: route)
            try require(
                unresolved.first?.enqueueStartedAt != nil && unresolved.first?.temporaryMessageID == nil
                    && exists(interrupted.fileURL),
                "process-death guessed an unregistered outcome",
            )
            let unresolvedRemoveDenied = await !(anotherRestart.remove(deathClaim.draft))
            try require(unresolvedRemoveDenied && exists(unrelated.draft.fileURL), "unresolved/unrelated file deleted")
        }

        private static func exists(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.path)
        }
    }
#endif
