// VideoSendTranscoder.swift

import AVFoundation
import Network
import UIKit

// MARK: - VideoSendPreset

/// Telegram's presets for videos sent from the gallery, `TGMediaVideoConversionPresetCompressedVeryLow` to
/// `CompressedVeryHigh` (`TGMediaVideoConverter`, `TGMediaVideoConversionPresetSettings`), with
/// `TGMediaVideoConversionPreset`'s raw values. Medium is the default; the gallery's quality tool picks another, at
/// most the source's own size (`bestAvailablePresetForDimensions`).
enum VideoSendPreset: Int, CaseIterable, Comparable {
    case veryLow = 1
    case low = 2
    case medium = 3
    case high = 4
    case veryHigh = 5

    static let audioSampleRate = 44100
    /// Presets below CompressedVeryHigh always render at 30 fps.
    static let frameRate: Int32 = 30
    static let thumbnailSide: CGFloat = 320
    static let thumbnailQuality: CGFloat = 0.4

    /// `maximumSizeForPreset:`.
    var maximumSide: CGFloat {
        switch self {
        case .veryLow: 480
        case .low: 640
        case .medium: 848
        case .high: 1280
        case .veryHigh: 1920
        }
    }

    /// `_videoBitrateKbpsForPreset:`.
    var videoBitrateKbps: Int {
        switch self {
        case .veryLow: 400
        case .low: 700
        case .medium: 1600
        case .high: 3000
        case .veryHigh: 6600
        }
    }

    /// `_audioBitrateKbpsForPreset:`.
    var audioBitrateKbps: Int {
        self <= .low ? 32 : 64
    }

    /// `_audioChannelsCountForPreset:`: mono for the two lowest presets.
    var audioChannels: Int {
        self <= .low ? 1 : 2
    }

    /// CompressedVeryHigh keeps the source's frame rate; the others render at 30 fps.
    var keepsSourceFrameRate: Bool {
        self == .veryHigh
    }

    /// TGPhotoQualityController's labels.
    var title: String {
        switch self {
        case .veryLow: "240p"
        case .low: "360p"
        case .medium: "480p"
        case .high: "720p"
        case .veryHigh: "1080p"
        }
    }

    /// The TDLib conversion that names this preset. Medium keeps the name it had before the other presets, so
    /// TDLib can restart an unfinished generation from an earlier launch.
    var conversion: String {
        switch self {
        case .veryLow: "bettertg-video-verylow-v1"
        case .low: "bettertg-video-low-v1"
        case .medium: "bettertg-video-medium-v1"
        case .high: "bettertg-video-high-v1"
        case .veryHigh: "bettertg-video-veryhigh-v1"
        }
    }

    init?(conversion: String) {
        guard let preset = Self.allCases.first(where: { $0.conversion == conversion }) else { return nil }
        self = preset
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// `bestAvailablePresetForDimensions:`: the largest preset whose side the source reaches, at least Low.
    static func bestAvailable(for size: CGSize) -> Self {
        let side = max(size.width, size.height)
        return [.veryHigh, .high, .medium].first { side >= $0.maximumSide } ?? .low
    }

    /// `defaultVideoPresetForContext`: the server's auto-download preset for the current network, high on Wi-Fi and
    /// medium otherwise. Its video upload bitrate, a percentage, picks one of the five presets; 0 keeps Medium.
    static func uploadDefault(client: TDLibClient) async -> Self {
        guard let presets = try? await client.getAutoDownloadSettingsPresets() else { return .medium }
        let settings = VideoSendNetwork.shared.isWiFi ? presets.high : presets.medium
        let bitrate = settings.videoUploadBitrate
        switch bitrate == 0 ? 0 : bitrate * 5 / 100 {
        case 1: return .veryLow
        case 2: return .low
        case 4: return .high
        case 5: return .veryHigh
        default: return .medium
        }
    }

    /// The preset a video of `size` converts with: this one, capped at the source's best (TGMediaVideoConverter).
    func capped(for size: CGSize) -> Self {
        min(self, Self.bestAvailable(for: size))
    }

    /// `dimensionsFor:adjustments:preset:` for an uncropped video, or a crop's size: `TGFitSizeF` into the preset's
    /// square, round up, then `_renderSizeWithCropSize:` takes the width down to a multiple of 16 and the height
    /// with it.
    func outputDimensions(for size: CGSize) -> CGSize {
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
    func estimatedSize(duration: Double, hasAudio: Bool) -> Int64 {
        var bitrate = videoBitrateKbps
        if hasAudio { bitrate += audioBitrateKbps * audioChannels }
        return Int64(Double(bitrate * 1000 / 8) * max(0, duration))
    }
}

// MARK: - VideoSendNetwork

/// Telegram's account network type for the upload default: Wi-Fi unless the path goes over cellular.
final class VideoSendNetwork: @unchecked Sendable {
    static let shared = VideoSendNetwork()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var cellular = false

    var isWiFi: Bool {
        lock.withLock { !cellular }
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let usesCellular = path.usesInterfaceType(.cellular)
            lock.withLock { self.cellular = usesCellular }
        }
        monitor.start(queue: DispatchQueue(label: "BetterTG.VideoSendNetwork"))
    }
}

// MARK: - SelectedVideoLoader

/// Reads a picked movie into a composer item: the app's copy of the file, its first frame, the 320 pt JPEG
/// thumbnail Telegram uploads with a video (`LegacyMediaPickers`), duration and displayed size.
enum SelectedVideoLoader {
    /// Conversion output before TDLib takes it. Picked videos and thumbnails live in `SelectedDocumentFileStore`.
    static let directory = FileManager.default
        .temporaryDirectory
        .appendingPathComponent("bettertg-video-send", isDirectory: true)

    /// Copies a file the picker owns only during its completion handler.
    static func copy(_ url: URL) -> URL? {
        do {
            let pathExtension = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            let destination = try SelectedDocumentFileStore.makeFileURL(named: "video.\(pathExtension)")
            try FileManager.default.copyItem(at: url, to: destination)
            // The store expires unleased files by modification date, which a copy keeps from the library file.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
            return destination
        } catch {
            log("Could not copy picked video: \(error)")
            return nil
        }
    }

    /// A trimmed video's first frame and thumbnail come from the trim's start, and a cropped one's are cut as the
    /// video will be.
    static func selection(forMovieAt url: URL, edit: VideoEditAdjustments? = nil) async -> SelectedImage? {
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
            let crop = edit?.crop(inFrameOf: presented)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            // A crop is read from a larger frame so the cut part keeps its detail.
            var previewSide: CGFloat = 960
            if let crop {
                let cropSide = max(1, max(crop.videoCropRect.width, crop.videoCropRect.height))
                previewSide = min(previewSide * 4, previewSide * max(presented.width, presented.height) / cropSide)
            }
            generator.maximumSize = CGSize(width: previewSide, height: previewSide)
            let start = min(edit?.trimRange?.lowerBound ?? 0, max(0, duration - 0.1))
            if start > 0 {
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
            }
            var preview = try await UIImage(
                cgImage: generator.image(at: CMTime(seconds: start, preferredTimescale: 600)).image,
            )
            if let crop {
                let pixelSize = CGSize(
                    width: preview.size.width * preview.scale,
                    height: preview.size.height * preview.scale,
                )
                preview = crop.render(preview, sourcePixelSize: pixelSize, maximumSide: 960) ?? preview
            }
            // The thumbnail fits the sent dimensions into 320 x 320 (`aspectFitted`), JPEG quality 0.4.
            // The thumbnail's shape follows the sent video's, which the presets share up to rounding.
            let sent = VideoSendPreset.medium.outputDimensions(for: presented, crop: crop)
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
                    edit: edit,
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

/// Converts a picked video as `TGMediaVideoConverter` does for its preset: H.264 High profile with CABAC at the
/// preset's bitrate and 30 fps (the source's rate for 1080p), AAC at 44.1 kHz with the preset's bitrate and
/// channels, in an MP4. The `moov` box goes first so the video streams before it downloads (`supportsStreaming`).
/// A trim reads only its range, a crop is cut, turned and mirrored as it renders, and a muted video renders at
/// `TGMediaVideoConversionPresetAnimation` without sound.
final class VideoSendTranscoder: @unchecked Sendable {
    enum Failure: Error {
        case noVideoTrack
        case unreadable
        case unwritable
        case cancelled
    }

    let preset: VideoSendPreset
    /// The gallery editor's trim, mute and crop.
    let edit: VideoEditAdjustments?

    private let lock = NSLock()
    private var reader: AVAssetReader?
    private var cancelled = false

    /// `sendAsGif` converts with `TGMediaVideoConversionPresetAnimation` (`keepAudioForPreset:` is false for it).
    private var sendsAsGIF: Bool {
        edit?.sendsAsGIF == true
    }

    /// The size and frame rate: a GIF takes the Animation preset's 848 px and 30 fps, which Medium shares.
    private var outputPreset: VideoSendPreset {
        sendsAsGIF ? .medium : preset
    }

    private var videoBitrateKbps: Int {
        sendsAsGIF ? VideoEditAdjustments.animationVideoBitrateKbps : preset.videoBitrateKbps
    }

    private var channelLayout: Data {
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = preset.audioChannels > 1
            ? kAudioChannelLayoutTag_Stereo
            : kAudioChannelLayoutTag_Mono
        return Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
    }

    private var decodedAudioSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: VideoSendPreset.audioSampleRate,
            AVNumberOfChannelsKey: preset.audioChannels,
            AVChannelLayoutKey: channelLayout,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    /// `audioSettingsForPreset:`.
    private var encodedAudioSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: VideoSendPreset.audioSampleRate,
            AVEncoderBitRateKey: preset.audioBitrateKbps * 1000,
            AVNumberOfChannelsKey: preset.audioChannels,
            AVChannelLayoutKey: channelLayout,
        ]
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    init(preset: VideoSendPreset, edit: VideoEditAdjustments? = nil) {
        self.preset = preset
        self.edit = edit
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
        let sourceAsset = AVURLAsset(url: source)
        guard let sourceVideoTrack = try await sourceAsset.loadTracks(withMediaType: .video).first else {
            throw Failure.noVideoTrack
        }
        let sourceAudioTrack = try await sendsAsGIF ? nil : preferredAudioTrack(of: sourceAsset)
        let sourceDuration = try await sourceAsset.load(.duration)
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let presented = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        guard presented.width > 0, presented.height > 0 else { throw Failure.noVideoTrack }
        let crop = edit?.crop(inFrameOf: presented.size)
        let dimensions = outputPreset.outputDimensions(for: presented.size, crop: crop)
        let frameRate = try await frameRate(of: sourceVideoTrack)
        let readable = try await readableSource(
            sourceAsset,
            video: sourceVideoTrack,
            audio: sourceAudioTrack,
            duration: sourceDuration,
            transform: preferredTransform,
        )
        let videoTrack = readable.video
        let audioTrack = readable.audio
        let duration = readable.duration

        let reader = try AVAssetReader(asset: readable.asset)
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
            crop: crop,
            dimensions: dimensions,
            frameRate: frameRate,
            duration: duration,
        )
        guard reader.canAdd(videoOutput) else { throw Failure.unreadable }
        reader.add(videoOutput)

        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings(dimensions: dimensions, frameRate: frameRate),
        )
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw Failure.unwritable }
        writer.add(videoInput)

        var audio: (output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)?
        if let audioTrack {
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: decodedAudioSettings)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: encodedAudioSettings)
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

    /// TGMediaVideoConverter's composition for a trim: the kept range of the video, and of the sound when it goes,
    /// placed at zero. An untrimmed video is read as it is.
    private func readableSource(
        _ asset: AVAsset,
        video: AVAssetTrack,
        audio: AVAssetTrack?,
        duration: CMTime,
        transform: CGAffineTransform,
    ) async throws -> (asset: AVAsset, video: AVAssetTrack, audio: AVAssetTrack?, duration: CMTime) {
        guard let edit, edit.trimRange != nil else { return (asset, video, audio, duration) }
        let range = edit.timeRange(in: duration)
        let composition = AVMutableComposition()
        guard let compositionVideo = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid,
        ) else { throw Failure.unreadable }
        try compositionVideo.insertTimeRange(range, of: video, at: .zero)
        compositionVideo.preferredTransform = transform
        var compositionAudio: AVAssetTrack?
        if let audio {
            // The sound may start later or end sooner than the picture.
            let audioRange = try await range.intersection(audio.load(.timeRange))
            if audioRange.duration > .zero,
               let track = composition.addMutableTrack(
                   withMediaType: .audio,
                   preferredTrackID: kCMPersistentTrackID_Invalid,
               )
            {
                try track.insertTimeRange(audioRange, of: audio, at: audioRange.start - range.start)
                compositionAudio = track
            }
        }
        return (composition, compositionVideo, compositionAudio, range.duration)
    }

    /// The track's display orientation scaled into the output, as `TGVideoTransformForOrientation` places it, with
    /// the crop cut, turned and mirrored (`TGVideoTransformForCrop`).
    private func composition(
        for track: AVAssetTrack,
        transform: CGAffineTransform,
        presented: CGRect,
        crop: PhotoCropAdjustments?,
        dimensions: CGSize,
        frameRate: Int32,
        duration: CMTime,
    ) -> AVVideoComposition {
        var layer = AVVideoCompositionLayerInstruction.Configuration(assetTrack: track)
        let placement = crop?.videoTransform(renderSize: dimensions) ?? CGAffineTransform(
            scaleX: dimensions.width / presented.width,
            y: dimensions.height / presented.height,
        )
        layer.setTransform(
            transform
                .concatenating(CGAffineTransform(translationX: -presented.minX, y: -presented.minY))
                .concatenating(placement),
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
            frameDuration: CMTime(value: 1, timescale: frameRate),
            instructions: [instruction],
            renderSize: dimensions,
        ))
    }

    /// `_setupVideoComposition`: 30 fps, except that 1080p keeps the source's rate, rounded up from its nominal
    /// rate or taken from its shortest frame.
    private func frameRate(of track: AVAssetTrack) async throws -> Int32 {
        guard outputPreset.keepsSourceFrameRate else { return VideoSendPreset.frameRate }
        let nominal = try await track.load(.nominalFrameRate)
        if nominal > 0 { return Int32(nominal.rounded(.up)) }
        let minimumDuration = try await track.load(.minFrameDuration)
        guard minimumDuration.isValid, minimumDuration.seconds > 0 else { return VideoSendPreset.frameRate }
        return Int32((1 / minimumDuration.seconds).rounded(.up))
    }

    private func videoSettings(dimensions: CGSize, frameRate: Int32) -> [String: Any] {
        var settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(dimensions.width),
            AVVideoHeightKey: Int(dimensions.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: videoBitrateKbps * 1000,
                AVVideoExpectedSourceFrameRateKey: Int(frameRate),
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
