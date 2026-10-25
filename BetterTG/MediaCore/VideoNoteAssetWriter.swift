// VideoNoteAssetWriter.swift

import AVFoundation
import CoreImage
import Foundation
import ImageIO
import VideoToolbox

// MARK: - VideoNoteAsset

struct VideoNoteAsset {
    let duration: Double
    let length: Int
    let url: URL
}

// MARK: - H264BitReader

private struct H264BitReader {
    let bytes: [UInt8]
    private(set) var bitOffset = 0

    mutating func readBit() -> UInt8? {
        guard bitOffset < bytes.count * 8 else { return nil }
        let byte = bytes[bitOffset / 8]
        let shift = 7 - bitOffset % 8
        bitOffset += 1
        return (byte >> shift) & 1
    }

    mutating func readUnsignedExpGolomb() -> UInt? {
        var leadingZeroCount = 0
        while let bit = readBit() {
            if bit == 1 { break }
            leadingZeroCount += 1
            guard leadingZeroCount <= 31 else { return nil }
        }
        var suffix = UInt.zero
        for _ in 0..<leadingZeroCount {
            guard let bit = readBit() else { return nil }
            suffix = suffix << 1 | UInt(bit)
        }
        return (UInt(1) << UInt(leadingZeroCount)) - 1 + suffix
    }
}

// MARK: - VideoNoteAssetWriterError

enum VideoNoteAssetWriterError: Swift.Error {
    case appendFailed
    case cancelled
    case invalidAsset
    case invalidTrackTiming(String)
    case probeFailed(String)
    case writerFailed
}

// MARK: - VideoNoteAssetWriter

final class VideoNoteAssetWriter: @unchecked Sendable {
    enum AppendResult: Equatable {
        case appended
        case dropped
        case reachedLimit
    }

    private let outputURL: URL
    private let length: Int
    private let maximumDuration: Double
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput
    private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let serializationQueue = DispatchQueue(label: "bettertg.video-note.writer", qos: .userInitiated)
    private let serializationQueueKey = DispatchSpecificKey<UInt8>()
    private var startTime: CMTime?
    private var lastVideoTime: CMTime?
    private var lastAudioTime: CMTime?
    private var lastAudioEndTime: CMTime?
    private var lastRenderedPixelBuffer: CVPixelBuffer?
    private var transitionSourcePixelBuffer: CVPixelBuffer?
    private var transitionFrameIndex = 0
    private let transitionFrameCount = 6
    #if DEBUG
        private var probeTransitionPixels = [(previous: UInt8, target: UInt8, output: UInt8)]()
    #endif
    private var pendingAudioBuffers = [CMSampleBuffer]()
    private let maximumPendingAudioBuffers = 256
    private var videoStreamEnded = false
    private var audioStreamEnded = false
    private var finishRequested = false
    private var finishDrainDeadline: DispatchTime?
    private var finishContinuation: CheckedContinuation<VideoNoteAsset, Error>?
    private var isCancelled = false
    private var isCompleted = false
    private var isFinishing = false

    var hasStarted: Bool {
        withSerialization { startTime != nil }
    }

    var hasCompleteAudioTail: Bool {
        withSerialization {
            guard let lastVideoTime, let lastAudioEndTime else { return false }
            return lastAudioEndTime >= lastVideoTime + CMTime(value: 1, timescale: 30)
        }
    }

    var recordedDuration: Double {
        withSerialization {
            guard let startTime, let lastVideoTime else { return 0 }
            return min(maximumDuration, max(0, (lastVideoTime - startTime).seconds + 1 / 30))
        }
    }

    init(
        outputURL: URL,
        length: Int = 400,
        maximumDuration: Double = 60,
    ) throws {
        let normalizedLength = min(640, max(1, length))
        let normalizedMaximumDuration = min(60, max(0.5, maximumDuration))
        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: normalizedLength,
            AVVideoHeightKey: normalizedLength,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1_000_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
            ],
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        let pixelAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: normalizedLength,
            kCVPixelBufferHeightKey as String: normalizedLength,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelAttributes,
        )

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            throw VideoNoteAssetWriterError.writerFailed
        }
        writer.add(videoInput)
        writer.add(audioInput)
        self.outputURL = outputURL
        self.length = normalizedLength
        self.maximumDuration = normalizedMaximumDuration
        self.writer = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.pixelBufferAdaptor = pixelBufferAdaptor
        serializationQueue.setSpecific(key: serializationQueueKey, value: 1)
    }

    static func validate(url: URL, expectedLength: Int? = nil) async throws -> VideoNoteAsset {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard duration.isFinite,
              duration > 0,
              duration <= 60.01,
              let videoTrack = videoTracks.first,
              let audioTrack = audioTracks.first
        else { throw VideoNoteAssetWriterError.invalidAsset }
        let naturalSize = try await videoTrack.load(.naturalSize)
        let width = Int(abs(naturalSize.width).rounded())
        let height = Int(abs(naturalSize.height).rounded())
        guard width == height,
              width > 0,
              width <= 640,
              expectedLength.map({ $0 == width }) ?? true
        else { throw VideoNoteAssetWriterError.invalidAsset }
        let videoFormats = try await videoTrack.load(.formatDescriptions)
        let audioFormats = try await audioTrack.load(.formatDescriptions)
        let videoTimeRange = try await videoTrack.load(.timeRange)
        let audioTimeRange = try await audioTrack.load(.timeRange)
        guard videoFormats.contains(where: isH264HighCABAC),
              audioFormats.contains(where: { format in
                  guard CMFormatDescriptionGetMediaSubType(format) == kAudioFormatMPEG4AAC,
                        let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)
                  else { return false }
                  return abs(description.pointee.mSampleRate - 48000) < 1
                      && description.pointee.mChannelsPerFrame == 1
              }),
              abs(videoTimeRange.start.seconds) < 0.05,
              abs(audioTimeRange.start.seconds) < 0.05,
              videoTimeRange.duration.seconds >= duration - 0.05,
              audioTimeRange.duration.seconds >= duration - 0.05
        else {
            throw VideoNoteAssetWriterError.invalidTrackTiming(
                "duration=\(duration), video=\(videoTimeRange.start.seconds)+\(videoTimeRange.duration.seconds), "
                    + "audio=\(audioTimeRange.start.seconds)+\(audioTimeRange.duration.seconds), "
                    + "videoFormats=\(videoFormats), audioFormats=\(audioFormats)",
            )
        }
        return VideoNoteAsset(duration: duration, length: width, url: url)
    }

    #if DEBUG
        static func makeDebugSegment(
            outputURL: URL,
            duration: Double,
            frameSeed: Int,
        ) async throws -> VideoNoteAsset {
            let writer = try await makeDebugRecording(
                outputURL: outputURL, duration: duration, frameSeed: frameSeed,
            )
            do {
                return try await writer.finish()
            } catch {
                writer.cancel()
                throw error
            }
        }

        static func makeDebugRecording(
            outputURL: URL,
            duration: Double,
            frameSeed: Int,
        ) async throws -> VideoNoteAssetWriter {
            let frameCount = max(2, Int((duration * 30).rounded()))
            let exactDuration = Double(frameCount) / 30
            let writer = try VideoNoteAssetWriter(
                outputURL: outputURL,
                length: 400,
                maximumDuration: min(60, exactDuration + 0.1),
            )
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for frameIndex in 0..<frameCount {
                            let pixelBuffer = try makeProbePixelBuffer(
                                frameIndex: frameSeed + frameIndex,
                                width: 400,
                                height: 400,
                            )
                            try await appendProbeVideo(
                                writer: writer,
                                pixelBuffer: pixelBuffer,
                                presentationTime: CMTime(value: Int64(frameIndex), timescale: 30),
                                orientation: .up,
                            )
                        }
                    }
                    group.addTask {
                        let totalAudioFrames = Int64(exactDuration * 48000)
                        for frameOffset in stride(from: Int64.zero, to: totalAudioFrames, by: 1024) {
                            let frameCount = Int(min(1024, totalAudioFrames - frameOffset))
                            let sampleBuffer = try makeAudioSampleBuffer(
                                frameOffset: frameOffset,
                                frameCount: frameCount,
                                amplitude: Int16(2000 + frameSeed * 10),
                            )
                            guard try writer.appendAudio(sampleBuffer) == .appended else {
                                throw VideoNoteAssetWriterError.appendFailed
                            }
                        }
                    }
                    try await group.waitForAll()
                }
                writer.markVideoFinished()
                writer.markAudioFinished()
                return writer
            } catch {
                writer.cancel()
                throw error
            }
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-video-note-writer") else { return }
            writeDebugProbeResult("Video note writer probe started")
            Task {
                let outputURL = FileManager.default
.temporaryDirectory
                    .appendingPathComponent("bettertg-video-note-writer-probe.mp4")
                let limitURL = FileManager.default
.temporaryDirectory
                    .appendingPathComponent("bettertg-video-note-limit-probe.mp4")
                let cleanupURLs = [outputURL, limitURL]
                for url in cleanupURLs {
                    try? FileManager.default.removeItem(at: url)
                }
                defer {
                    for url in cleanupURLs {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
                var activeWriter: VideoNoteAssetWriter?
                var stage = "setup"
                do {
                    let writer = try VideoNoteAssetWriter(outputURL: outputURL, length: 400, maximumDuration: 2)
                    activeWriter = writer
                    for audioFrameOffset in stride(from: Int64.zero, to: 4096, by: 1024) {
                        let audioBuffer = try makeAudioSampleBuffer(
                            frameOffset: audioFrameOffset,
                            frameCount: 1024,
                            amplitude: 12000,
                        )
                        guard try writer.appendAudio(audioBuffer) == .appended else {
                            throw VideoNoteAssetWriterError.appendFailed
                        }
                    }
                    let firstPixelBuffer = try makeProbePixelBuffer(
                        frameIndex: 0,
                        width: 640,
                        height: 480,
                    )
                    try await appendProbeVideo(
                        writer: writer,
                        pixelBuffer: firstPixelBuffer,
                        presentationTime: .zero,
                        orientation: .rightMirrored,
                    )
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for frameIndex in 1..<30 {
                                if frameIndex == 15 {
                                    writer.beginCameraTransition()
                                }
                                let pixelBuffer = try makeProbePixelBuffer(
                                    frameIndex: frameIndex,
                                    width: 640,
                                    height: 480,
                                )
                                try await appendProbeVideo(
                                    writer: writer,
                                    pixelBuffer: pixelBuffer,
                                    presentationTime: CMTime(value: Int64(frameIndex), timescale: 30),
                                    orientation: .rightMirrored,
                                )
                            }
                        }
                        group.addTask {
                            for audioFrameOffset in stride(from: Int64(4096), to: 48128, by: 1024) {
                                let afterSyntheticSwitch = audioFrameOffset >= 24576
                                let rawFrameOffset = afterSyntheticSwitch ? audioFrameOffset + 4800 : audioFrameOffset
                                let audioBuffer = try makeAudioSampleBuffer(
                                    frameOffset: rawFrameOffset,
                                    frameCount: 1024,
                                    amplitude: 0,
                                )
                                let offset = afterSyntheticSwitch
                                    ? CMTime(seconds: 0.1, preferredTimescale: 48000)
                                    : .zero
                                guard try writer.appendAudio(
                                    audioBuffer,
                                    presentationTimeOffset: offset,
                                ) == .appended else {
                                    throw VideoNoteAssetWriterError.appendFailed
                                }
                            }
                        }
                        try await group.waitForAll()
                    }
                    let finishTask = Task { try await writer.finish() }
                    try await writer.waitForProbeFinishRequest()
                    writer.markVideoFinished()
                    try await Task<Never, Never>.sleep(for: .milliseconds(10))
                    guard !writer.probeFinishHasStarted else {
                        throw VideoNoteAssetWriterError.invalidAsset
                    }
                    writer.markAudioFinished()
                    stage = "finish/drain"
                    let result = try await finishTask.value
                    activeWriter = nil
                    guard abs(result.duration - 1) < 0.02 else {
                        throw VideoNoteAssetWriterError.invalidAsset
                    }
                    stage = "round/orientation"
                    try await validateProbeRoundMask(url: result.url)
                    stage = "pre-video audio"
                    try await validateProbeAudioStart(url: result.url)
                    stage = "switch transition"
                    let transitionPixels = writer.probeCameraTransitionPixels
                    guard transitionPixels.count == 6,
                          let firstTransition = transitionPixels.first,
                          let lastTransition = transitionPixels.last,
                          abs(Int(firstTransition.output) - Int(firstTransition.previous))
                          < abs(Int(firstTransition.target) - Int(firstTransition.previous)),
                          firstTransition.output != firstTransition.target,
                          abs(Int(lastTransition.output) - Int(lastTransition.target)) <= 2
                    else {
                        throw VideoNoteAssetWriterError.probeFailed(
                            "rendered transition pixels=\(transitionPixels)",
                        )
                    }
                    stage = "switch audio continuity"
                    try await validateProbeAudioContinuity(url: result.url)
                    let attributes = try FileManager.default.attributesOfItem(atPath: result.url.path)
                    let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
                    stage = "post-success cancel"
                    writer.cancel()
                    guard FileManager.default.fileExists(atPath: result.url.path) else {
                        throw VideoNoteAssetWriterError.invalidAsset
                    }

                    stage = "limit/cancel"
                    let limitWriter = try VideoNoteAssetWriter(
                        outputURL: limitURL,
                        length: 400,
                        maximumDuration: 0.5,
                    )
                    activeWriter = limitWriter
                    let limitAudio = try makeAudioSampleBuffer(
                        frameOffset: 0,
                        frameCount: 1024,
                        amplitude: 1000,
                    )
                    guard try limitWriter.appendAudio(limitAudio) == .appended else {
                        throw VideoNoteAssetWriterError.appendFailed
                    }
                    let limitPixelBuffer = try makeProbePixelBuffer(
                        frameIndex: 0,
                        width: 400,
                        height: 400,
                    )
                    try await appendProbeVideo(
                        writer: limitWriter,
                        pixelBuffer: limitPixelBuffer,
                        presentationTime: .zero,
                        orientation: .up,
                    )
                    let limitResult = try limitWriter.appendVideo(
                        pixelBuffer: limitPixelBuffer,
                        presentationTime: CMTime(seconds: 0.5, preferredTimescale: 600),
                    )
                    guard limitResult == .reachedLimit else {
                        throw VideoNoteAssetWriterError.invalidAsset
                    }
                    limitWriter.cancel()
                    activeWriter = nil
                    guard !FileManager.default.fileExists(atPath: limitURL.path) else {
                        throw VideoNoteAssetWriterError.invalidAsset
                    }

                    let proof = "Video note writer probe: H264 High/CABAC + AAC MP4, "
                        + "\(result.length)x\(result.length), duration=\(result.duration), "
                        + "round/orientation=true, pre-video-audio=true, concurrent-drain=true, "
                        + "switch-crossfade/audio-retime=true, limit/cancel=true, bytes=\(fileSize)"
                    writeDebugProbeResult(proof)
                    log(proof)
                } catch {
                    activeWriter?.cancel()
                    for url in cleanupURLs {
                        try? FileManager.default.removeItem(at: url)
                    }
                    writeDebugProbeResult("Video note writer probe failed at \(stage): \(error)")
                    assertionFailure("Video note writer probe failed at \(stage): \(error)")
                }
            }
        }

        private static func appendProbeVideo(
            writer: VideoNoteAssetWriter,
            pixelBuffer: CVPixelBuffer,
            presentationTime: CMTime,
            orientation: CGImagePropertyOrientation,
        ) async throws {
            for _ in 0..<1000 {
                switch try writer.appendVideo(
                    pixelBuffer: pixelBuffer,
                    presentationTime: presentationTime,
                    orientation: orientation,
                ) {
                case .appended:
                    return
                case .dropped:
                    try await Task<Never, Never>.sleep(for: .milliseconds(1))
                case .reachedLimit:
                    throw VideoNoteAssetWriterError.invalidAsset
                }
            }
            throw VideoNoteAssetWriterError.appendFailed
        }

        private var probeFinishHasStarted: Bool {
            withSerialization { isFinishing }
        }

        private var probeCameraTransitionPixels: [(previous: UInt8, target: UInt8, output: UInt8)] {
            withSerialization { probeTransitionPixels }
        }

        private func waitForProbeFinishRequest() async throws {
            for _ in 0..<1000 {
                if withSerialization({ finishRequested && finishContinuation != nil }) {
                    return
                }
                try await Task<Never, Never>.sleep(for: .milliseconds(1))
            }
            throw VideoNoteAssetWriterError.writerFailed
        }
    #endif

    private static func isH264HighCABAC(_ format: CMFormatDescription) -> Bool {
        guard CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_H264,
              let rawExtensions = CMFormatDescriptionGetExtensions(format) else { return false }
        let extensions = rawExtensions as NSDictionary
        guard let atoms = extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? NSDictionary,
              let configuration = atoms["avcC"] as? Data
        else { return false }
        let bytes = [UInt8](configuration)
        guard bytes.count > 7, bytes[0] == 1, bytes[1] == 100 else { return false }
        var index = 6
        let sequenceCount = Int(bytes[5] & 0x1F)
        for _ in 0..<sequenceCount {
            guard index + 2 <= bytes.count else { return false }
            let length = Int(bytes[index]) << 8 | Int(bytes[index + 1])
            index += 2
            guard index + length <= bytes.count else { return false }
            index += length
        }
        guard index < bytes.count else { return false }
        let pictureCount = Int(bytes[index])
        index += 1
        guard pictureCount > 0, index + 2 <= bytes.count else { return false }
        let pictureLength = Int(bytes[index]) << 8 | Int(bytes[index + 1])
        index += 2
        guard pictureLength > 1, index + pictureLength <= bytes.count else { return false }
        let pictureNAL = Array(bytes[index..<index + pictureLength])
        guard pictureNAL[0] & 0x1F == 8 else { return false }
        var rawPayload = [UInt8]()
        var zeroCount = 0
        for byte in pictureNAL.dropFirst() {
            if zeroCount >= 2, byte == 3 {
                zeroCount = 0
                continue
            }
            rawPayload.append(byte)
            zeroCount = byte == 0 ? zeroCount + 1 : 0
        }
        var reader = H264BitReader(bytes: rawPayload)
        guard reader.readUnsignedExpGolomb() != nil,
              reader.readUnsignedExpGolomb() != nil,
              reader.readBit() == 1
        else { return false }
        return true
    }

    #if DEBUG
        private static func makeProbePixelBuffer(
            frameIndex: Int,
            width: Int,
            height: Int,
        ) throws -> CVPixelBuffer {
            var pixelBuffer: CVPixelBuffer?
            let attributes: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
            guard CVPixelBufferCreate(
                nil,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                attributes as CFDictionary,
                &pixelBuffer,
            ) == kCVReturnSuccess,
                let pixelBuffer
            else { throw VideoNoteAssetWriterError.writerFailed }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
            guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                throw VideoNoteAssetWriterError.writerFailed
            }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let green = UInt8((frameIndex * 13) % 255)
            for row in 0..<height {
                let pixels = baseAddress.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for column in 0..<width {
                    let offset = column * 4
                    pixels[offset] = UInt8(row * 255 / max(1, height - 1))
                    pixels[offset + 1] = green
                    pixels[offset + 2] = UInt8(column * 255 / max(1, width - 1))
                    pixels[offset + 3] = 255
                }
            }
            return pixelBuffer
        }

        private static func makeAudioSampleBuffer(
            frameOffset: Int64,
            frameCount: Int,
            amplitude: Int16,
        ) throws -> CMSampleBuffer {
            var streamDescription = AudioStreamBasicDescription(
                mSampleRate: 48000,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 2,
                mFramesPerPacket: 1,
                mBytesPerFrame: 2,
                mChannelsPerFrame: 1,
                mBitsPerChannel: 16,
                mReserved: 0,
            )
            var formatDescription: CMAudioFormatDescription?
            guard CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &streamDescription,
                layoutSize: 0,
                layout: nil,
                magicCookieSize: 0,
                magicCookie: nil,
                extensions: nil,
                formatDescriptionOut: &formatDescription,
            ) == noErr,
                let formatDescription
            else { throw VideoNoteAssetWriterError.writerFailed }
            let byteCount = frameCount * 2
            var blockBuffer: CMBlockBuffer?
            guard CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: byteCount,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: byteCount,
                flags: 0,
                blockBufferOut: &blockBuffer,
            ) == kCMBlockBufferNoErr,
                let blockBuffer
            else { throw VideoNoteAssetWriterError.writerFailed }
            var samples = [Int16](repeating: 0, count: frameCount)
            if amplitude != 0 {
                for index in samples.indices {
                    let absoluteFrame = frameOffset + Int64(index)
                    samples[index] = Int16(
                        Double(amplitude) * sin(Double(absoluteFrame) * 2 * .pi * 440 / 48000),
                    )
                }
            }
            let copyStatus = samples.withUnsafeBytes { bytes in
                CMBlockBufferReplaceDataBytes(
                    with: bytes.baseAddress!,
                    blockBuffer: blockBuffer,
                    offsetIntoDestination: 0,
                    dataLength: byteCount,
                )
            }
            guard copyStatus == kCMBlockBufferNoErr else { throw VideoNoteAssetWriterError.writerFailed }
            var timing = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: 48000),
                presentationTimeStamp: CMTime(value: frameOffset, timescale: 48000),
                decodeTimeStamp: .invalid,
            )
            var sampleSize = 2
            var sampleBuffer: CMSampleBuffer?
            guard CMSampleBufferCreate(
                allocator: kCFAllocatorDefault,
                dataBuffer: blockBuffer,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: formatDescription,
                sampleCount: frameCount,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timing,
                sampleSizeEntryCount: 1,
                sampleSizeArray: &sampleSize,
                sampleBufferOut: &sampleBuffer,
            ) == noErr,
                let sampleBuffer
            else { throw VideoNoteAssetWriterError.writerFailed }
            return sampleBuffer
        }

        private static func validateProbeRoundMask(url: URL) async throws {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let image = try await generator.image(at: CMTime(value: 1, timescale: 30)).image
            let ciImage = CIImage(cgImage: image)
            let context = CIContext(options: [.cacheIntermediates: false])
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            func pixel(at point: CGPoint) -> [UInt8] {
                var bytes = [UInt8](repeating: 0, count: 4)
                context.render(
                    ciImage,
                    toBitmap: &bytes,
                    rowBytes: 4,
                    bounds: CGRect(origin: point, size: CGSize(width: 1, height: 1)),
                    format: .RGBA8,
                    colorSpace: colorSpace,
                )
                return bytes
            }
            let corners = [
                CGPoint.zero,
                CGPoint(x: image.width - 1, y: 0),
                CGPoint(x: 0, y: image.height - 1),
                CGPoint(x: image.width - 1, y: image.height - 1),
            ].map(pixel)
            let centerPoint = CGPoint(x: image.width / 2, y: image.height / 2)
            let center = pixel(at: centerPoint)
            let outsideCirclePoints = [
                CGPoint(x: centerPoint.x - 150, y: centerPoint.y - 150),
                CGPoint(x: centerPoint.x + 150, y: centerPoint.y - 150),
                CGPoint(x: centerPoint.x - 150, y: centerPoint.y + 150),
                CGPoint(x: centerPoint.x + 150, y: centerPoint.y + 150),
            ]
            let outsideCirclePixels = outsideCirclePoints.map(pixel)
            let left = pixel(at: CGPoint(x: centerPoint.x - 100, y: centerPoint.y))
            let right = pixel(at: CGPoint(x: centerPoint.x + 100, y: centerPoint.y))
            let bottom = pixel(at: CGPoint(x: centerPoint.x, y: centerPoint.y - 100))
            let top = pixel(at: CGPoint(x: centerPoint.x, y: centerPoint.y + 100))
            let redHorizontalDifference = abs(Int(left[0]) - Int(right[0]))
            let redVerticalDifference = abs(Int(bottom[0]) - Int(top[0]))
            let blueHorizontalDifference = abs(Int(left[2]) - Int(right[2]))
            let blueVerticalDifference = abs(Int(bottom[2]) - Int(top[2]))
            guard corners.allSatisfy({ $0.prefix(3).allSatisfy { $0 < 28 } }),
                  outsideCirclePixels.allSatisfy({ $0.prefix(3).allSatisfy { $0 < 40 } }),
                  [center, left, right, bottom, top].allSatisfy({
                      $0.prefix(3).contains(where: { $0 > 40 })
                  }),
                  redVerticalDifference > redHorizontalDifference + 40,
                  blueHorizontalDifference > blueVerticalDifference + 40
            else {
                throw VideoNoteAssetWriterError.probeFailed(
                    "corners=\(corners), outside=\(outsideCirclePixels), center=\(center), "
                        + "redH=\(redHorizontalDifference), redV=\(redVerticalDifference), "
                        + "blueH=\(blueHorizontalDifference), blueV=\(blueVerticalDifference)",
                )
            }
        }

        private static func validateProbeAudioStart(url: URL) async throws {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                throw VideoNoteAssetWriterError.invalidAsset
            }
            let reader = try AVAssetReader(asset: asset)
            reader.timeRange = CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: 0.08, preferredTimescale: 48000),
            )
            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false,
                ],
            )
            guard reader.canAdd(output) else { throw VideoNoteAssetWriterError.invalidAsset }
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? VideoNoteAssetWriterError.invalidAsset }
            var peak = Int.zero
            var sampleCount = 0
            while let sampleBuffer = output.copyNextSampleBuffer(),
                  let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)
            {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var data = Data(repeating: 0, count: length)
                let status = data.withUnsafeMutableBytes { bytes in
                    CMBlockBufferCopyDataBytes(
                        blockBuffer,
                        atOffset: 0,
                        dataLength: length,
                        destination: bytes.baseAddress!,
                    )
                }
                guard status == kCMBlockBufferNoErr else { throw VideoNoteAssetWriterError.invalidAsset }
                data.withUnsafeBytes { bytes in
                    for sample in bytes.bindMemory(to: Int16.self) {
                        peak = max(peak, abs(Int(sample)))
                        sampleCount += 1
                    }
                }
            }
            guard reader.status == .completed,
                  sampleCount > 1000,
                  peak > 1000
            else { throw reader.error ?? VideoNoteAssetWriterError.invalidAsset }
        }

        private static func validateProbeAudioContinuity(url: URL) async throws {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                throw VideoNoteAssetWriterError.invalidAsset
            }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            guard reader.canAdd(output) else { throw VideoNoteAssetWriterError.invalidAsset }
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? VideoNoteAssetWriterError.invalidAsset }
            var ranges = [(start: Double, end: Double)]()
            while let sampleBuffer = output.copyNextSampleBuffer() {
                let start = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                let duration = CMSampleBufferGetDuration(sampleBuffer).seconds
                guard start.isFinite else { continue }
                let finiteDuration = duration.isFinite ? max(0, duration) : 0
                ranges.append((start, start + finiteDuration))
            }
            ranges.sort { $0.start < $1.start }
            var previousEnd: Double?
            var maximumGap = Double.zero
            for range in ranges where range.end >= 0.35 && range.start <= 0.65 {
                if let previousEnd, range.start > previousEnd {
                    maximumGap = max(maximumGap, range.start - previousEnd)
                }
                previousEnd = max(previousEnd ?? range.end, range.end)
            }
            let observedBeforeBoundary = ranges.contains { $0.start <= 0.49 && $0.end >= 0.45 }
            let observedAfterBoundary = ranges.contains { $0.start <= 0.55 && $0.end >= 0.51 }
            guard reader.status == .completed,
                  observedBeforeBoundary,
                  observedAfterBoundary,
                  maximumGap < 0.05
            else {
                throw reader.error ?? VideoNoteAssetWriterError.probeFailed(
                    "audio maximumGap=\(maximumGap), before=\(observedBeforeBoundary), "
                        + "after=\(observedAfterBoundary), ranges=\(ranges)",
                )
            }
        }

        private static func writeDebugProbeResult(_ result: String) {
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return
            }
            try? Data(result.utf8).write(
                to: documentsURL.appendingPathComponent("video-note-writer-probe.txt"),
                options: .atomic,
            )
        }
    #endif

    func appendVideo(
        pixelBuffer: CVPixelBuffer,
        presentationTime: CMTime,
        orientation: CGImagePropertyOrientation = .up,
    ) throws -> AppendResult {
        try withSerialization {
            try appendVideoIsolated(
                pixelBuffer: pixelBuffer,
                presentationTime: presentationTime,
                orientation: orientation,
            )
        }
    }

    func beginCameraTransition() {
        withSerialization {
            guard !isCancelled, !isCompleted else { return }
            #if DEBUG
                probeTransitionPixels.removeAll(keepingCapacity: true)
            #endif
            guard let lastRenderedPixelBuffer else {
                transitionSourcePixelBuffer = nil
                transitionFrameIndex = 0
                return
            }
            var snapshot: CVPixelBuffer?
            let attributes: [String: Any] = [
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
            guard CVPixelBufferCreate(
                nil,
                length,
                length,
                kCVPixelFormatType_32BGRA,
                attributes as CFDictionary,
                &snapshot,
            ) == kCVReturnSuccess,
                  let snapshot
            else {
                transitionSourcePixelBuffer = nil
                transitionFrameIndex = 0
                return
            }
            ciContext.render(
                CIImage(cvPixelBuffer: lastRenderedPixelBuffer),
                to: snapshot,
                bounds: CGRect(x: 0, y: 0, width: length, height: length),
                colorSpace: colorSpace,
            )
            transitionSourcePixelBuffer = snapshot
            transitionFrameIndex = 0
        }
    }

    func appendAudio(
        _ sampleBuffer: CMSampleBuffer,
        presentationTimeOffset: CMTime = .zero,
    ) throws -> AppendResult {
        try withSerialization {
            let adjustedSampleBuffer = try adjustedAudioSampleBuffer(
                sampleBuffer,
                presentationTimeOffset: presentationTimeOffset,
            )
            return try appendAudioIsolated(adjustedSampleBuffer)
        }
    }

    func markVideoFinished() {
        withSerialization {
            videoStreamEnded = true
            attemptFinishIsolated()
        }
    }

    func markAudioFinished() {
        withSerialization {
            audioStreamEnded = true
            attemptFinishIsolated()
        }
    }

    func finish() async throws -> VideoNoteAsset {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                serializationQueue.async { [self] in
                    guard !isCancelled else {
                        continuation.resume(throwing: VideoNoteAssetWriterError.cancelled)
                        return
                    }
                    guard finishContinuation == nil, !isFinishing else {
                        continuation.resume(throwing: VideoNoteAssetWriterError.writerFailed)
                        return
                    }
                    finishContinuation = continuation
                    finishRequested = true
                    finishDrainDeadline = .now() + 5
                    serializationQueue.asyncAfter(deadline: .now() + 5) { [weak self] in
                        guard let self,
                              finishContinuation != nil,
                              !isFinishing,
                              !isCancelled
                        else { return }
                        failFinishIsolated(VideoNoteAssetWriterError.writerFailed)
                    }
                    attemptFinishIsolated()
                }
            }
        } onCancel: {
            cancel()
        }
    }

    func cancel() {
        withSerialization {
            guard !isCancelled, !isCompleted else { return }
            isCancelled = true
            pendingAudioBuffers.removeAll()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            let continuation = finishContinuation
            finishContinuation = nil
            continuation?.resume(throwing: VideoNoteAssetWriterError.cancelled)
        }
    }

    private func appendVideoIsolated(
        pixelBuffer: CVPixelBuffer,
        presentationTime: CMTime,
        orientation: CGImagePropertyOrientation,
    ) throws -> AppendResult {
        try ensureWritable()
        guard !videoStreamEnded else { return .dropped }
        if startTime == nil {
            guard writer.startWriting() else { throw VideoNoteAssetWriterError.writerFailed }
            writer.startSession(atSourceTime: presentationTime)
            startTime = presentationTime
        }
        guard let startTime else { throw VideoNoteAssetWriterError.writerFailed }
        let elapsed = presentationTime.seconds - startTime.seconds
        if elapsed >= maximumDuration {
            return .reachedLimit
        }
        guard videoInput.isReadyForMoreMediaData else { return .dropped }
        guard let pool = pixelBufferAdaptor.pixelBufferPool else {
            throw VideoNoteAssetWriterError.writerFailed
        }
        var outputPixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputPixelBuffer) == kCVReturnSuccess,
              let outputPixelBuffer
        else { throw VideoNoteAssetWriterError.writerFailed }
        renderSquare(source: pixelBuffer, destination: outputPixelBuffer, orientation: orientation)
        guard pixelBufferAdaptor.append(outputPixelBuffer, withPresentationTime: presentationTime) else {
            throw writer.error ?? VideoNoteAssetWriterError.appendFailed
        }
        lastVideoTime = presentationTime
        try flushPendingAudioIsolated()
        return .appended
    }

    private func appendAudioIsolated(_ sampleBuffer: CMSampleBuffer) throws -> AppendResult {
        try ensureWritable()
        guard !audioStreamEnded else { return .dropped }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid else { return .dropped }
        guard let startTime else {
            pendingAudioBuffers.append(sampleBuffer)
            if pendingAudioBuffers.count > maximumPendingAudioBuffers {
                pendingAudioBuffers.removeFirst(pendingAudioBuffers.count - maximumPendingAudioBuffers)
            }
            return .appended
        }
        guard presentationTime >= startTime else { return .dropped }
        if presentationTime.seconds - startTime.seconds >= maximumDuration {
            return .reachedLimit
        }
        pendingAudioBuffers.append(sampleBuffer)
        try flushPendingAudioIsolated()
        return .appended
    }

    private func ensureWritable() throws {
        guard !isCancelled else { throw VideoNoteAssetWriterError.cancelled }
        guard !isFinishing else { throw VideoNoteAssetWriterError.writerFailed }
        guard writer.status != .failed, writer.status != .cancelled else {
            throw writer.error ?? VideoNoteAssetWriterError.writerFailed
        }
    }

    private func withSerialization<T>(_ operation: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: serializationQueueKey) == 1 {
            return try operation()
        }
        return try serializationQueue.sync(execute: operation)
    }

    private func flushPendingAudioIsolated() throws {
        guard writer.status != .failed, writer.status != .cancelled else {
            throw writer.error ?? VideoNoteAssetWriterError.writerFailed
        }
        guard let startTime, let lastVideoTime else { return }
        pendingAudioBuffers.sort {
            CMSampleBufferGetPresentationTimeStamp($0) < CMSampleBufferGetPresentationTimeStamp($1)
        }
        let videoBoundary = lastVideoTime + CMTime(value: 1, timescale: 30)
        while let sampleBuffer = pendingAudioBuffers.first {
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if presentationTime < startTime {
                pendingAudioBuffers.removeFirst()
                continue
            }
            if let lastAudioTime, presentationTime <= lastAudioTime {
                pendingAudioBuffers.removeFirst()
                continue
            }
            if presentationTime.seconds - startTime.seconds >= maximumDuration {
                pendingAudioBuffers.removeFirst()
                continue
            }
            if presentationTime > videoBoundary {
                if videoStreamEnded {
                    pendingAudioBuffers.removeFirst()
                    continue
                }
                return
            }
            guard audioInput.isReadyForMoreMediaData else { return }
            guard audioInput.append(sampleBuffer) else {
                throw writer.error ?? VideoNoteAssetWriterError.appendFailed
            }
            lastAudioTime = presentationTime
            let duration = CMSampleBufferGetDuration(sampleBuffer)
            lastAudioEndTime = presentationTime + (duration.isNumeric && duration > .zero ? duration : .zero)
            pendingAudioBuffers.removeFirst()
        }
    }

    private func attemptFinishIsolated() {
        guard finishRequested,
              videoStreamEnded,
              audioStreamEnded,
              !isCancelled,
              !isFinishing
        else { return }
        if writer.status == .failed || writer.status == .cancelled {
            failFinishIsolated(writer.error ?? VideoNoteAssetWriterError.writerFailed)
            return
        }
        if let finishDrainDeadline, DispatchTime.now() >= finishDrainDeadline {
            failFinishIsolated(VideoNoteAssetWriterError.writerFailed)
            return
        }
        do {
            try flushPendingAudioIsolated()
        } catch {
            failFinishIsolated(error)
            return
        }
        guard pendingAudioBuffers.isEmpty else {
            serializationQueue.asyncAfter(deadline: .now() + 0.005) { [weak self] in
                self?.attemptFinishIsolated()
            }
            return
        }
        guard let startTime, let lastVideoTime, lastAudioTime != nil else {
            failFinishIsolated(VideoNoteAssetWriterError.invalidAsset)
            return
        }
        isFinishing = true
        videoInput.markAsFinished()
        audioInput.markAsFinished()
        let frameEndTime = lastVideoTime + CMTime(value: 1, timescale: 30)
        let maximumEndTime = startTime + CMTime(seconds: maximumDuration, preferredTimescale: 600)
        writer.endSession(atSourceTime: min(frameEndTime, maximumEndTime))
        writer.finishWriting { [self] in
            Task {
                let result: Result<VideoNoteAsset, Error>
                if writer.status == .completed {
                    do {
                        result = try await .success(Self.validate(url: outputURL, expectedLength: length))
                    } catch {
                        result = .failure(error)
                    }
                } else {
                    result = .failure(writer.error ?? VideoNoteAssetWriterError.writerFailed)
                }
                serializationQueue.async { [self] in
                    completeFinishIsolated(result)
                }
            }
        }
    }

    private func completeFinishIsolated(_ result: Result<VideoNoteAsset, Error>) {
        guard !isCancelled else {
            try? FileManager.default.removeItem(at: outputURL)
            return
        }
        if case .failure = result {
            try? FileManager.default.removeItem(at: outputURL)
            isCancelled = true
        } else {
            isCompleted = true
        }
        let continuation = finishContinuation
        finishContinuation = nil
        continuation?.resume(with: result)
    }

    private func failFinishIsolated(_ error: Error) {
        isFinishing = true
        isCancelled = true
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: outputURL)
        let continuation = finishContinuation
        finishContinuation = nil
        continuation?.resume(throwing: error)
    }

    private func adjustedAudioSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        presentationTimeOffset: CMTime,
    ) throws -> CMSampleBuffer {
        guard presentationTimeOffset.isValid,
              presentationTimeOffset > .zero
        else { return sampleBuffer }
        var timingCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &timingCount,
        ) == noErr,
              timingCount > 0
        else { throw VideoNoteAssetWriterError.appendFailed }
        var timing = Array(repeating: CMSampleTimingInfo.invalid, count: timingCount)
        guard CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: timingCount,
            arrayToFill: &timing,
            entriesNeededOut: &timingCount,
        ) == noErr
        else { throw VideoNoteAssetWriterError.appendFailed }
        for index in timing.indices {
            if timing[index].presentationTimeStamp.isValid {
                timing[index].presentationTimeStamp = timing[index].presentationTimeStamp - presentationTimeOffset
            }
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = timing[index].decodeTimeStamp - presentationTimeOffset
            }
        }
        var adjustedSampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: timing.count,
            sampleTimingArray: &timing,
            sampleBufferOut: &adjustedSampleBuffer,
        ) == noErr,
              let adjustedSampleBuffer
        else { throw VideoNoteAssetWriterError.appendFailed }
        return adjustedSampleBuffer
    }

    private func renderSquare(
        source: CVPixelBuffer,
        destination: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
    ) {
        let image = CIImage(cvPixelBuffer: source).oriented(orientation)
        let extent = image.extent
        let side = min(extent.width, extent.height)
        let cropRect = CGRect(
            x: extent.midX - side / 2,
            y: extent.midY - side / 2,
            width: side,
            height: side,
        )
        let cropped = image.cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
            .transformed(by: CGAffineTransform(
                scaleX: CGFloat(length) / side,
                y: CGFloat(length) / side,
            ))
        let outputBounds = CGRect(x: 0, y: 0, width: length, height: length)
        let black = CIImage(color: .black).cropped(to: outputBounds)
        let radius = CGFloat(length) / 2
        let mask = CIFilter(
            name: "CIRadialGradient",
            parameters: [
                kCIInputCenterKey: CIVector(x: radius, y: radius),
                "inputRadius0": max(0, radius - 1),
                "inputRadius1": radius,
                kCIInputColor0Key: CIColor.white,
                kCIInputColor1Key: CIColor.black,
            ],
        )?.outputImage?
            .cropped(to: outputBounds)
        var roundImage = mask.map {
            cropped.applyingFilter(
                "CIBlendWithMask",
                parameters: [
                    kCIInputBackgroundImageKey: black,
                    kCIInputMaskImageKey: $0,
                ],
            )
        } ?? cropped
        #if DEBUG
            var probeTransitionInput: (previous: UInt8, target: UInt8)?
        #endif
        if let transitionSourcePixelBuffer,
           transitionFrameIndex < transitionFrameCount
        {
            #if DEBUG
                probeTransitionInput = (
                    centerGreen(in: transitionSourcePixelBuffer),
                    centerGreen(in: source),
                )
            #endif
            let progress = CGFloat(transitionFrameIndex + 1) / CGFloat(transitionFrameCount)
            let previousImage = CIImage(cvPixelBuffer: transitionSourcePixelBuffer)
                .cropped(to: outputBounds)
            let fadedPrevious = previousImage.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1 - progress),
                ],
            )
            roundImage = fadedPrevious.composited(over: roundImage).cropped(to: outputBounds)
            transitionFrameIndex += 1
            if transitionFrameIndex >= transitionFrameCount {
                self.transitionSourcePixelBuffer = nil
                transitionFrameIndex = 0
            }
        }
        ciContext.render(
            roundImage,
            to: destination,
            bounds: outputBounds,
            colorSpace: colorSpace,
        )
        #if DEBUG
            if let probeTransitionInput {
                probeTransitionPixels.append((
                    previous: probeTransitionInput.previous,
                    target: probeTransitionInput.target,
                    output: centerGreen(in: destination),
                ))
            }
        #endif
        lastRenderedPixelBuffer = destination
    }

    #if DEBUG
        private func centerGreen(in pixelBuffer: CVPixelBuffer) -> UInt8 {
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
            let row = CVPixelBufferGetHeight(pixelBuffer) / 2
            let column = CVPixelBufferGetWidth(pixelBuffer) / 2
            let offset = row * CVPixelBufferGetBytesPerRow(pixelBuffer) + column * 4 + 1
            return baseAddress.assumingMemoryBound(to: UInt8.self)[offset]
        }
    #endif
}
