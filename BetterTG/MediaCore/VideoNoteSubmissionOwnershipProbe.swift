// VideoNoteSubmissionOwnershipProbe.swift

#if DEBUG
    import Foundation

    enum VideoNoteSubmissionOwnershipProbe {
        struct Failure: Error, CustomStringConvertible {
            let description: String
        }

        @MainActor final class Gate {
            private var entered = false
            private var continuation: CheckedContinuation<Void, Never>?
            private var observer: CheckedContinuation<Void, Never>?

            func wait() async {
                entered = true
                observer?.resume()
                observer = nil
                await withCheckedContinuation { continuation = $0 }
            }

            func waitUntilEntered() async {
                guard !entered else { return }
                await withCheckedContinuation { observer = $0 }
            }

            func open() {
                continuation?.resume()
                continuation = nil
            }
        }

        static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        @MainActor static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-video-note-submission-ownership")
                else { return }
            Task {
                let directory = FileManager.default
.temporaryDirectory
                    .appendingPathComponent("video-note-submission-probe-\(UUID().uuidString)", isDirectory: true)
                let result: String
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    try await VideoNoteRecorderViewController.verifyDebugSubmissionOwnership(directory: directory)
                    result = "Video note submission ownership probe passed: actual-recorder/store/native-media=true; "
                        + "consumed-retained=detached; pending-cancel/consumed=no-delete; "
                        + "retry-after-handoff/obsolete-cancel/deinit=preserved; exact-registration=passed; "
                        + "stale-result/successor-state=fenced; unconsumed-local-cancel=deleted; "
                        + "enqueued=detached; user-stores/server-send/capture-hardware=untouched; "
                        + "offscreen-controller-only=true; recording-draft-materialization/UI-gestures=unverified"
                } catch {
                    result = "Video note submission ownership probe failed: \(error)"
                }
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("video-note-submission-ownership-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }
    }
#endif
