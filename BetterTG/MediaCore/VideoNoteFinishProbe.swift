// VideoNoteFinishProbe.swift

#if DEBUG
    import Foundation

    enum VideoNoteFinishProbe {
        struct Failure: Error, CustomStringConvertible {
            let description: String
        }

        actor Gate {
            private var entered = false
            private var opened = false
            private var continuation: CheckedContinuation<Void, Never>?
            private var observer: CheckedContinuation<Void, Never>?

            var isEntered: Bool { entered }

            func wait() async {
                entered = true
                observer?.resume()
                observer = nil
                guard !opened else { return }
                await withCheckedContinuation { continuation = $0 }
            }

            func waitUntilEntered() async {
                guard !entered else { return }
                await withCheckedContinuation { observer = $0 }
            }

            func open() {
                opened = true
                continuation?.resume()
                continuation = nil
            }
        }

        static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        @MainActor static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-video-note-finish") else { return }
            Task {
                let directory = FileManager.default
.temporaryDirectory
                    .appendingPathComponent("video-note-finish-probe-\(UUID().uuidString)", isDirectory: true)
                let result: String
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    try await VideoNoteCaptureSession.verifyDebugFinishOwnership(directory: directory)
                    try await VideoNoteRecorderViewController.verifyDebugOperationOwnership()
                    result = "Video note finish probe passed: actual-capture-session=true; native-H264/AAC=true; "
                        + "auto-reserved/manual-release=ignored; writer-done/manual-release=ignored; "
                        + "duplicate-manual/automatic=ignored; callback/asset-owner=1; "
                        + "cancel-before-finish/after-writer-before-delivery=isolated; "
                        + "replacement-generation/stale-stop=fenced; adopted-output-preserved; "
                        + "missing-callback-output-cleaned; stale-operation-completion=fenced; "
                        + "caller-task-cancel=cleaned; native-writer-failure=delivered-once; "
                        + "preparing-auto/late-start/queued-duration/stopping=fenced; "
                        + "camera/microphone/UI/server-send=unverified; user-stores=untouched"
                } catch {
                    result = "Video note finish probe failed: \(error)"
                }
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("video-note-finish-probe.txt"), options: .atomic,
                    )
                }
                log(result)
            }
        }
    }
#endif
