// VideoNotePreservationProbe.swift

#if DEBUG
    import Foundation

    enum VideoNotePreservationProbe {
        struct Failure: Error, CustomStringConvertible {
            let description: String
        }

        @MainActor private static var lastProgress = "not started"

        @MainActor static func progress(_ message: String) {
            lastProgress = message
            write(message, file: "video-note-preservation-progress.txt")
            log("Video preservation progress: \(message)")
        }

        static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        @MainActor static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-video-note-preservation") else { return }
            Task {
                progress("started")
                write("Video note navigation preservation probe started", file: "video-note-preservation-probe.txt")
                var timedOut = false
                let deadline = Task {
                    do { try await Task<Never, Never>.sleep(for: .seconds(45)) } catch { return }
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
                        + "navigation-then-background=terminates; hardware/background-only-preservation=unverified; "
                        + "user-stores/server-send=untouched"
                } catch {
                    result = "Video note navigation preservation probe failed: \(error)"
                }
                guard !timedOut else { return }
                write(result, file: "video-note-preservation-probe.txt")
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
