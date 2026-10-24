// LivePhotoDebugProbe.swift

#if DEBUG
import AVFoundation
import ImageIO
import Photos

@MainActor enum LivePhotoDebugProbe {
    private static var didRun = false

    static func runIfRequested() {
        guard !didRun, ProcessInfo.processInfo.arguments.contains("-live-photo-probe") else { return }
        didRun = true
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let source = documents.appendingPathComponent("parity-live-source", isDirectory: true)
        let output = documents.appendingPathComponent("live-photo-probe.txt")
        Task {
            var lines = [String]()
            do {
                let pair = try await LivePhotoResources.prepare(
                    photo: source.appendingPathComponent("photo.jpg"),
                    video: source.appendingPathComponent("motion.mp4"),
                )
                defer { pair.cleanup() }
                let image = CGImageSourceCreateWithURL(pair.photo as CFURL, nil)
                let properties = image.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] }
                let maker = properties?[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any]
                let photoID = maker?["17"] as? String
                let metadata = try await AVURLAsset(url: pair.video).load(.metadata)
                var videoID: String?
                for item in metadata where item.identifier == .quickTimeMetadataContentIdentifier {
                    videoID = try await item.load(.stringValue)
                }
                lines
                    .append(
                        "\(photoID != nil && photoID == videoID ? "PASS" : "FAIL") matching JPEG/MOV content identifiers",
                    )
                let request = LivePhotoValidationRequest()
                let valid = await request.validate(pair)
                lines.append("\(valid ? "PASS" : "FAIL") Photos recognizes the pair as PHLivePhoto")
                let marker = documents.appendingPathComponent("parity-live-photo-added.txt")
                if valid, ProcessInfo.processInfo.arguments.contains("-add-live-photo-test-asset"),
                   !FileManager.default.fileExists(atPath: marker.path)
                {
                    var permission = PHPhotoLibrary.authorizationStatus(for: .addOnly)
                    if permission ==
                        .notDetermined { permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly) }
                    guard permission == .authorized || permission == .limited
                        else { throw CocoaError(.fileWriteNoPermission) }
                    try await pair.save(creationDate: Date())
                    try "Synthetic BetterTG test Live Photo added once.".write(
                        to: marker,
                        atomically: true,
                        encoding: .utf8,
                    )
                    lines.append("PASS added one synthetic Live Photo to the simulator library")
                }
            } catch {
                lines.append("FAIL \(error.localizedDescription)")
            }
            try? lines.joined(separator: "\n").write(to: output, atomically: true, encoding: .utf8)
        }
    }
}

@MainActor private final class LivePhotoValidationRequest {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var requestID: PHLivePhotoRequestID?
    private var timeout: Task<Void, Never>?

    func validate(_ resources: LivePhotoResources) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            requestID = PHLivePhoto.request(
                withResourceFileURLs: [resources.photo, resources.video],
                placeholderImage: nil,
                targetSize: CGSize(width: 320, height: 240),
                contentMode: .aspectFit,
            ) { [weak self] photo, info in
                let valid = photo != nil
                let degraded = (info[PHLivePhotoInfoIsDegradedKey] as? Bool) == true
                Task { @MainActor [weak self] in if !degraded { self?.finish(valid) } }
            }
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                if !Task.isCancelled { self?.finish(false) }
            }
        }
    }

    private func finish(_ success: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        if let requestID { PHLivePhoto.cancelRequest(withRequestID: requestID) }
        continuation.resume(returning: success)
    }
}
#endif
