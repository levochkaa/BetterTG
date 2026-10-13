// VideoSendGenerationCoordinator.swift

import Combine
import Foundation
import TDLibKit

// MARK: - VideoSendConversionProgress

/// Conversion progress of the videos this session sends, for the upload disc. Telegram uploads a video while it
/// converts (`FetchVideoMediaResource`), so one arc covers both. TDLib uploads a generated file once it is finished,
/// so the disc spends its first half on the conversion and the second on the upload.
@MainActor enum VideoSendConversionProgress {
    struct FileKey: Hashable {
        let clientID: Int32
        let fileID: Int
    }

    private static let capacity = 64
    private static var fractionsByPath = [String: Double]()
    private static var pathsByFile = [FileKey: String]()
    private static let subject = PassthroughSubject<(key: FileKey, fraction: Double), Never>()

    /// Links the file TDLib created for a sent video to the original it converts.
    static func register(fileID: Int, clientID: Int32, originalPath: String) {
        let key = FileKey(clientID: clientID, fileID: fileID)
        let originalPath = normalized(originalPath)
        pathsByFile[key] = originalPath
        if pathsByFile.count > capacity, let any = pathsByFile.keys.first(where: { $0 != key }) {
            pathsByFile[any] = nil
        }
        subject.send((key, fractionsByPath[originalPath] ?? 0))
    }

    static func update(originalPath: String, fraction: Double) {
        let originalPath = normalized(originalPath)
        let value = max(fractionsByPath[originalPath] ?? 0, min(1, fraction))
        fractionsByPath[originalPath] = value
        if fractionsByPath.count > capacity, let any = fractionsByPath.keys.first(where: { $0 != originalPath }) {
            fractionsByPath[any] = nil
        }
        for (key, path) in pathsByFile where path == originalPath {
            subject.send((key, value))
        }
    }

    /// The converted share of `fileID`, or nil when this session didn't send it.
    static func fraction(fileID: Int, clientID: Int32) -> Double? {
        guard let path = pathsByFile[FileKey(clientID: clientID, fileID: fileID)] else { return nil }
        return fractionsByPath[path] ?? 0
    }

    static func updates(fileID: Int, clientID: Int32) -> AnyPublisher<Double, Never> {
        let key = FileKey(clientID: clientID, fileID: fileID)
        return subject.filter { $0.key == key }.map(\.fraction).eraseToAnyPublisher()
    }

    /// TDLib may report the original path through a different symlink (`/var` and `/private/var`).
    private static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}

// MARK: - VideoSendGenerationCoordinator

/// Converts picked videos when TDLib asks for them. A video goes out as `inputFileGenerated`, so its message appears
/// at once and TDLib starts the conversion with `updateFileGenerationStart`, as Telegram posts the message before
/// converting. A stop, a deleted message or an account switch cancels the conversion.
@MainActor final class VideoSendGenerationCoordinator {
    private struct Job {
        let source: TdUpdateSource
        let transcoder: VideoSendTranscoder
        let task: Task<Void, Never>
    }

    static let shared = VideoSendGenerationCoordinator()

    /// Stays the same across launches: TDLib restarts an unfinished generation with the original path and conversion.
    static let conversion = "bettertg-video-medium-v1"

    private var jobs = [Int64: Job]()
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func start() {
        guard cancellables.isEmpty else { return }
        nc.scopedPublisher(&cancellables, for: .updateFileGenerationStart) { [weak self] update in
            self?.begin(update.value, source: update.source)
        }
        nc.scopedPublisher(&cancellables, for: .updateFileGenerationStop) { [weak self] update in
            self?.stop(generationID: update.value.generationId)
        }
        TDLib.shared
            .activeClientChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in
                guard let self else { return }
                for (generationID, job) in jobs where job.source != source {
                    stop(generationID: generationID)
                }
            }
            .store(in: &cancellables)
    }

    private func begin(_ update: UpdateFileGenerationStart, source: TdUpdateSource) {
        guard update.conversion == Self.conversion else { return }
        let generationID = update.generationId
        stop(generationID: generationID)
        let original = URL(fileURLWithPath: update.originalPath)
        let originalPath = update.originalPath
        let destination = URL(fileURLWithPath: update.destinationPath)
        let transcoder = VideoSendTranscoder()
        let task = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Error? in
                let work = SelectedVideoLoader.directory.appendingPathComponent("\(UUID().uuidString).mp4")
                do {
                    try FileManager.default.createDirectory(
                        at: SelectedVideoLoader.directory,
                        withIntermediateDirectories: true,
                    )
                    try await transcoder.transcode(from: original, to: work) { fraction in
                        Task { @MainActor in
                            VideoSendConversionProgress.update(originalPath: originalPath, fraction: fraction)
                        }
                    }
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: work, to: destination)
                    return nil
                } catch {
                    try? FileManager.default.removeItem(at: work)
                    return error
                }
            }.value
            self?.finish(generationID: generationID, transcoder: transcoder, original: original, error: result)
        }
        jobs[generationID] = Job(source: source, transcoder: transcoder, task: task)
    }

    private func finish(generationID: Int64, transcoder: VideoSendTranscoder, original: URL, error: Error?) {
        guard let job = jobs[generationID], job.transcoder === transcoder else { return }
        jobs[generationID] = nil
        guard let client = TDLib.shared.authorizationClient(for: job.source) else { return }
        if let error {
            log("Video conversion failed: \(error)")
        } else {
            VideoSendConversionProgress.update(originalPath: original.path, fraction: 1)
            // TDLib keeps the generated file; the copy of the library video is no longer needed.
            Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: original) }
        }
        let failure = error.map { TDNativeError(code: 400, message: "VIDEO_CONVERSION_FAILED: \($0)") }
        Task {
            do {
                _ = try await client.finishFileGeneration(generationId: generationID, error: failure)
            } catch {
                log("finishFileGeneration failed: \(error)")
            }
        }
    }

    private func stop(generationID: Int64) {
        guard let job = jobs.removeValue(forKey: generationID) else { return }
        job.transcoder.cancel()
        job.task.cancel()
    }
}
