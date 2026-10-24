// VideoNotePreservationProbe.swift

#if DEBUG
    import Foundation

    enum VideoNotePreservationProbe {
        struct Failure: Error, CustomStringConvertible {
            let description: String
        }

        @MainActor private static var lastProgress = "not started"
        @MainActor private static var lastLifecycleProgress = "not started"

        @MainActor static func progress(_ message: String) {
            lastProgress = message
            write(message, file: "video-note-preservation-progress.txt")
            log("Video preservation progress: \(message)")
        }

        @MainActor static func lifecycleProgress(_ message: String) {
            lastLifecycleProgress = message
            write(message, file: "video-note-lifecycle-progress.txt")
            log("Video lifecycle progress: \(message)")
        }

        static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        @MainActor static func waitForGate(
            _ gate: VideoNoteFinishProbe.Gate,
            finalization: VideoNoteCaptureFinalization,
        ) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            while await !(gate.isEntered) {
                if finalization.isComplete {
                    let result = await finalization.value()
                    switch result {
                    case .success:
                        throw Failure(
                            description: "canonical save completed without entering the requested finish gate",
                        )
                    case .failure(let error):
                        throw Failure(description: "finalization ended before finish gate: \(error)")
                    }
                }
                guard ContinuousClock.now < deadline else {
                    throw Failure(description: "finish gate was not entered within 15 seconds")
                }
                try await Task<Never, Never>.sleep(for: .milliseconds(10))
            }
        }

        @MainActor static func runDebugProbeIfRequested() {
            if ProcessInfo.processInfo.arguments.contains("-media-probe-video-note-lifecycle") {
                runLifecycleProbe()
                return
            }
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-video-note-preservation") else { return }
            Task {
                progress("started")
                write("Video note navigation preservation probe started", file: "video-note-preservation-probe.txt")
                var timedOut = false
                let deadline = Task {
                    do {
                        try await Task<Never, Never>.sleep(for: .seconds(45))
                    } catch {
                        return
                    }
                    timedOut = true
                    let result = "Video note navigation preservation probe failed: timeout at \(lastProgress)"
                    write(result, file: "video-note-preservation-probe.txt")
                    log(result)
                }
                defer { deadline.cancel() }
                let directory = FileManager.default
.temporaryDirectory
                    .appendingPathComponent("video-note-preservation-\(UUID().uuidString)", isDirectory: true)
                let result: String
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    try await VideoNoteRecorderViewController.verifyDebugNavigationPreservation(directory: directory)
                    result = "Video note navigation preservation probe passed: actual-recorder/capture/writer/store=true; "
                        + "manual/auto/before-finish/after-finish/before-save=joined; "
                        + "single-canonical-adopt/append=true; route-barrier/account-isolation=true; "
                        + "reply/topic/route-preserved; detached-UI/send=0; explicit-cancel=destructive; "
                        + "stale-cancel=no-op; failed-append/prior-draft=preserved; "
                        + "navigation-then-capture-failure=terminates; hardware/background-only-preservation=unverified; "
                        + "user-stores/server-send=untouched"
                } catch {
                    result = "Video note navigation preservation probe failed: \(error)"
                }
                guard !timedOut else { return }
                write(result, file: "video-note-preservation-probe.txt")
                log(result)
            }
        }

        @MainActor private static func runLifecycleProbe() {
            Task {
                lifecycleProgress("started")
                write("Video note lifecycle probe started", file: "video-note-lifecycle-probe.txt")
                var timedOut = false
                let deadline = Task {
                    do {
                        try await Task<Never, Never>.sleep(for: .seconds(60))
                    } catch {
                        return
                    }
                    timedOut = true
                    let result = "Video note lifecycle probe failed: timeout at \(lastLifecycleProgress)"
                    write(result, file: "video-note-lifecycle-probe.txt")
                    log(result)
                }
                defer { deadline.cancel() }
                let directory = FileManager.default
.temporaryDirectory
                    .appendingPathComponent("video-note-lifecycle-\(UUID().uuidString)", isDirectory: true)
                let result: String
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    try await VideoNoteRecorderViewController.verifyDebugLifecyclePreservation(directory: directory)
                    result = "Video note lifecycle probe passed: actual-recorder/capture/writer/store=true; "
                        + "background/camera-interruption=canonical-preview; manual/automatic/pending-start=joined; "
                        + "duplicate-events/foreground-cycles=single-lease; immediate-expiry=handled; "
                        + "expiry-before-adopt=prior-preserved; expiry-during-save=commit-preserved; "
                        + "failed-append=prior-preserved; explicit-cancel=destructive; "
                        + "route/reply/topic-preserved; foreground-autoplay/capture-restart/implicit-send=0; "
                        + "stale-generation/detached-UI=rejected; accepted-submit=not-cancelled; "
                        + "background-foreground-during-export=send-rejected/own-export-cleaned/canonical-kept; "
                        + "hardware/real-OS-suspension/audio-notification=unverified; user-stores/server-send=untouched"
                } catch {
                    result = "Video note lifecycle probe failed: \(error)"
                }
                guard !timedOut else { return }
                write(result, file: "video-note-lifecycle-probe.txt")
                log(result)
            }
        }

        private static func write(_ message: String, file: String) {
            if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(message.utf8).write(to: documents.appendingPathComponent(file), options: .atomic)
            }
        }
    }
#endif
