// VideoSendTranscoder.swift

import AVFoundation
import UIKit

// MARK: - VideoSendPreset

/// Telegram's default preset for videos sent from the gallery, `TGMediaVideoConversionPresetCompressedMedium`
/// (`TGMediaVideoConverter`, `TGMediaVideoConversionPresetSettings`, `LegacyMediaPickers`).
enum VideoSendPreset {
    static let maximumSide: CGFloat = 848
    static let videoBitrateKbps = 1600
    static let audioBitrateKbps = 64
    static let audioChannels = 2
    static let audioSampleRate = 44100
    /// Presets below CompressedVeryHigh always render at 30 fps.
    static let frameRate: Int32 = 30
    static let thumbnailSide: CGFloat = 320
    static let thumbnailQuality: CGFloat = 0.4

    /// `dimensionsFor:adjustments:preset:` for an uncropped video: `TGFitSizeF` into 848 x 848, round up, then
    /// `_renderSizeWithCropSize:` takes the width down to a multiple of 16 and the height with it.
    static func outputDimensions(for size: CGSize) -> CGSize {
        var fitted = CGSize(width: max(1, size.width), height: max(1, size.height))
        if fitted.width > maximumSide {
            fitted = CGSize(width: maximumSide, height: fitted.height * maximumSide / fitted.width)
        }
        if fitted.height > maximumSide {
            fitted = CGSize(width: fitted.width * maximumSide / fitted.height, height: maximumSide)
        }
        fitted = CGSize(width: fitted.width.rounded(.up), height: fitted.height.rounded(.up))
        let block: CGFloat = 16
        let width = (fitted.width / block).rounded(.down) * block
        var height = (fitted.height * width / fitted.width).rounded(.down)
        if height.truncatingRemainder(dividingBy: block) != 0 {
            height = (fitted.height / block).rounded(.down) * block
        }
        return CGSize(width: max(block, width), height: max(block, height))
    }

    /// `estimatedSizeForPreset:duration:hasAudio:`.
    static func estimatedSize(duration: Double, hasAudio: Bool) -> Int64 {
        var bitrate = videoBitrateKbps
        if hasAudio { bitrate += audioBitrateKbps * audioChannels }
        return Int64(Double(bitrate * 1000 / 8) * max(0, duration))
    }
}

// MARK: - SelectedVideoLoader

/// Reads a picked movie into a composer item: the app's copy of the file, its first frame, the 320 pt JPEG
/// thumbnail Telegram uploads with a video (`LegacyMediaPickers`), duration and displayed size.
enum SelectedVideoLoader {
    static let directory = FileManager.default
        .temporaryDirectory
        .appendingPathComponent("bettertg-video-send", isDirectory: true)

    /// Copies a file the picker owns only during its completion handler.
    static func copy(_ url: URL) -> URL? {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let pathExtension = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            let destination = directory.appendingPathComponent("\(UUID().uuidString).\(pathExtension)")
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            log("Could not copy picked video: \(error)")
            return nil
        }
    }

    static func selection(forMovieAt url: URL) async -> SelectedImage? {
        let asset = AVURLAsset(url: url)
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw VideoSendTranscoder.Failure.noVideoTrack
            }
            let duration = try await asset.load(.duration).seconds
            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let hasAudio = try await !asset.loadTracks(withMediaType: .audio).isEmpty
            let presented = CGRect(origin: .zero, size: naturalSize).applying(transform).size
            guard presented.width > 0, presented.height > 0, duration.isFinite else {
                throw VideoSendTranscoder.Failure.noVideoTrack
            }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 960, height: 960)
            let preview = try await UIImage(cgImage: generator.image(at: .zero).image)
            // The thumbnail fits the sent dimensions into 320 x 320 (`aspectFitted`), JPEG quality 0.4.
            let sent = VideoSendPreset.outputDimensions(for: presented)
            let scale = min(VideoSendPreset.thumbnailSide / sent.width, VideoSendPreset.thumbnailSide / sent.height)
            let thumbnailSize = CGSize(
                width: max(1, (sent.width * scale).rounded(.down)),
                height: max(1, (sent.height * scale).rounded(.down)),
            )
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let thumbnail = UIGraphicsImageRenderer(size: thumbnailSize, format: format).image { _ in
                preview.draw(in: CGRect(origin: .zero, size: thumbnailSize))
            }
            guard let data = thumbnail.jpegData(compressionQuality: VideoSendPreset.thumbnailQuality) else {
                throw VideoSendTranscoder.Failure.unwritable
            }
            let thumbnailURL = url.deletingPathExtension().appendingPathExtension("thumbnail.jpg")
            try data.write(to: thumbnailURL, options: .atomic)
            return SelectedImage(
                image: preview,
                url: thumbnailURL,
                video: SelectedVideo(
                    url: url,
                    duration: duration,
                    presentationSize: presented,
                    thumbnailSize: thumbnailSize,
                    hasAudio: hasAudio,
                ),
            )
        } catch {
            log("Could not read picked video: \(error)")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }
}

// MARK: - VideoSendTranscoder

/// Converts a picked video as `TGMediaVideoConverter` does for the medium preset: H.264 High profile with CABAC at
/// 1600 kbit/s and 30 fps, stereo AAC at 64 kbit/s and 44.1 kHz, in an MP4. The `moov` box goes first so the
/// video streams before it downloads (`supportsStreaming`).
final class VideoSendTranscoder: @unchecked Sendable {
    enum Failure: Error {
        case noVideoTrack
        case unreadable
        case unwritable
        case cancelled
    }

    private static var stereoLayout: Data {
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        return Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
    }

    private static var decodedAudioSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: VideoSendPreset.audioSampleRate,
            AVNumberOfChannelsKey: VideoSendPreset.audioChannels,
            AVChannelLayoutKey: stereoLayout,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    /// `audioSettingsForPreset:`.
    private static var encodedAudioSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: VideoSendPreset.audioSampleRate,
            AVEncoderBitRateKey: VideoSendPreset.audioBitrateKbps * 1000,
            AVNumberOfChannelsKey: VideoSendPreset.audioChannels,
            AVChannelLayoutKey: stereoLayout,
        ]
    }

    private let lock = NSLock()
    private var reader: AVAssetReader?
    private var cancelled = false

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Stops reading; the writer is cancelled on the pump queue once both inputs have stopped appending.
    func cancel() {
        lock.lock()
        cancelled = true
        let reader = reader
        lock.unlock()
        reader?.cancelReading()
    }

    func transcode(
        from source: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void,
    ) async throws {
        try? FileManager.default.removeItem(at: destination)
        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw Failure.noVideoTrack
        }
        let audioTrack = try await preferredAudioTrack(of: asset)
        let duration = try await asset.load(.duration)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let presented = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        guard presented.width > 0, presented.height > 0 else { throw Failure.noVideoTrack }
        let dimensions = VideoSendPreset.outputDimensions(for: presented.size)

        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            ],
        )
        videoOutput.videoComposition = composition(
            for: videoTrack,
            transform: preferredTransform,
            presented: presented,
            dimensions: dimensions,
            duration: duration,
        )
        guard reader.canAdd(videoOutput) else { throw Failure.unreadable }
        reader.add(videoOutput)

        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings(dimensions: dimensions))
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw Failure.unwritable }
        writer.add(videoInput)

        var audio: (output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)?
        if let audioTrack {
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: Self.decodedAudioSettings)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.encodedAudioSettings)
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(output), writer.canAdd(input) {
                reader.add(output)
                writer.add(input)
                audio = (output, input)
            }
        }

        guard install(reader) else { throw Failure.cancelled }
        guard reader.startReading() else { throw reader.error ?? Failure.unreadable }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw writer.error ?? Failure.unwritable
        }
        writer.startSession(atSourceTime: .zero)

        let totalSeconds = max(duration.seconds, 0.001)
        let reporter = ProgressThrottle(report: progress)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let group = DispatchGroup()
                pump(videoInput, from: videoOutput, label: "video", group: group) { sample in
                    let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    if time.isFinite { reporter.update(min(1, max(0, time / totalSeconds))) }
                }
                if let audio {
                    pump(audio.input, from: audio.output, label: "audio", group: group, onSample: nil)
                }
                group.notify(queue: .global(qos: .userInitiated)) { [self] in
                    if isCancelled || reader.status != .completed {
                        writer.cancelWriting()
                        try? FileManager.default.removeItem(at: destination)
                        continuation.resume(throwing: isCancelled
                            ? Failure.cancelled
                            : reader.error ?? Failure.unreadable)
                        return
                    }
                    let finishing = UncheckedBox(value: writer)
                    writer.finishWriting {
                        let writer = finishing.value
                        if writer.status == .completed {
                            continuation.resume()
                        } else {
                            try? FileManager.default.removeItem(at: destination)
                            continuation.resume(throwing: writer.error ?? Failure.unwritable)
                        }
                    }
                }
            }
        } onCancel: {
            cancel()
        }
        progress(1)
    }

    /// Keeps the reader for `cancel()`; false when the transcode was cancelled before it started.
    private func install(_ reader: AVAssetReader) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        self.reader = reader
        return !cancelled
    }

    private func pump(
        _ input: AVAssetWriterInput,
        from output: AVAssetReaderOutput,
        label: String,
        group: DispatchGroup,
        onSample: ((CMSampleBuffer) -> Void)?,
    ) {
        group.enter()
        let queue = DispatchQueue(label: "BetterTG.VideoSendTranscoder.\(label)", qos: .userInitiated)
        var finished = false
        input.requestMediaDataWhenReady(on: queue) { [self] in
            guard !finished else { return }
            while input.isReadyForMoreMediaData {
                let appended: Bool = autoreleasepool {
                    guard !isCancelled, let sample = output.copyNextSampleBuffer() else { return false }
                    onSample?(sample)
                    return input.append(sample)
                }
                guard appended else {
                    finished = true
                    input.markAsFinished()
                    group.leave()
                    return
                }
            }
        }
    }

    private func preferredAudioTrack(of asset: AVAsset) async throws -> AVAssetTrack? {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        for track in tracks where try await track.load(.isEnabled) {
            return track
        }
        return tracks.first
    }

    /// The track's display orientation scaled into the output, as `TGVideoTransformForOrientation` places it.
    private func composition(
        for track: AVAssetTrack,
        transform: CGAffineTransform,
        presented: CGRect,
        dimensions: CGSize,
        duration: CMTime,
    ) -> AVVideoComposition {
        var layer = AVVideoCompositionLayerInstruction.Configuration(assetTrack: track)
        layer.setTransform(
            transform
                .concatenating(CGAffineTransform(translationX: -presented.minX, y: -presented.minY))
                .concatenating(CGAffineTransform(
                    scaleX: dimensions.width / presented.width,
                    y: dimensions.height / presented.height,
                )),
            at: .zero,
        )
        let instruction = AVVideoCompositionInstruction(configuration: .init(
            layerInstructions: [AVVideoCompositionLayerInstruction(configuration: layer)],
            timeRange: CMTimeRange(start: .zero, duration: duration),
        ))
        // Rec. 709 output tone-maps HDR sources, as Telegram's `AVVideoColorPropertiesKey` does.
        return AVVideoComposition(configuration: .init(
            colorPrimaries: AVVideoColorPrimaries_ITU_R_709_2,
            colorTransferFunction: AVVideoTransferFunction_ITU_R_709_2,
            colorYCbCrMatrix: AVVideoYCbCrMatrix_ITU_R_709_2,
            frameDuration: CMTime(value: 1, timescale: VideoSendPreset.frameRate),
            instructions: [instruction],
            renderSize: dimensions,
        ))
    }

    private func videoSettings(dimensions: CGSize) -> [String: Any] {
        var settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(dimensions.width),
            AVVideoHeightKey: Int(dimensions.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: VideoSendPreset.videoBitrateKbps * 1000,
                AVVideoExpectedSourceFrameRateKey: Int(VideoSendPreset.frameRate),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
            ] as [String: Any],
        ]
        #if !targetEnvironment(simulator)
            // Telegram leaves the color properties out on the Simulator only.
            settings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ]
        #endif
        return settings
    }
}

// MARK: - UncheckedBox

private struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
}

// MARK: - ProgressThrottle

/// Forwards progress in steps of at least 1%.
private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1.0
    private let report: @Sendable (Double) -> Void

    init(report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    func update(_ value: Double) {
        lock.lock()
        guard value - last >= 0.01 else {
            lock.unlock()
            return
        }
        last = value
        lock.unlock()
        report(value)
    }
}
