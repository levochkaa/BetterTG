// VideoNoteSegmentComposer.swift

import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

final class VideoNoteCompositionResult: @unchecked Sendable {
    init(
        asset: AVComposition,
        duration: Double,
        segmentRanges: [Range<Double>],
        snapshotDirectory: URL,
    ) {
        self.asset = asset
        self.duration = duration
        self.segmentRanges = segmentRanges
        self.snapshotDirectory = snapshotDirectory
    }

    deinit {
        try? FileManager.default.removeItem(at: snapshotDirectory)
    }

    let asset: AVComposition
    let duration: Double
    let segmentRanges: [Range<Double>]
    private let snapshotDirectory: URL
}

struct VideoNoteThumbnailSample: Sendable {
    let jpegData: Data
    let time: Double
}

enum VideoNoteSegmentComposerError: Swift.Error {
    case exportFailed
    case invalidDuration
    case invalidSegment
}

enum VideoNoteSegmentComposer {
    #if DEBUG
        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-video-note-segments") else { return }
            Task { await runDebugProbe() }
        }
    #endif

    static func compose(_ segments: [VideoNoteAsset]) async throws -> VideoNoteCompositionResult {
        guard !segments.isEmpty else { throw VideoNoteSegmentComposerError.invalidSegment }
        let snapshot = try await snapshotSegments(segments)
        var ownsSnapshot = true
        defer {
            if ownsSnapshot {
                try? FileManager.default.removeItem(at: snapshot.directory)
            }
        }
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid,
        ),
            let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid,
            )
        else { throw VideoNoteSegmentComposerError.invalidSegment }

        var cursor = CMTime.zero
        var expectedLength: Int?
        var ranges = [Range<Double>]()
        for segment in snapshot.segments {
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath: segment.url.path(percentEncoded: false)) else {
                throw VideoNoteSegmentComposerError.invalidSegment
            }
            let source = AVURLAsset(url: segment.url)
            let sourceDuration = try await source.load(.duration)
            let videoTracks = try await source.loadTracks(withMediaType: .video)
            let audioTracks = try await source.loadTracks(withMediaType: .audio)
            guard let videoTrack = videoTracks.first,
                  let audioTrack = audioTracks.first,
                  sourceDuration.seconds.isFinite,
                  sourceDuration.seconds > 0
            else { throw VideoNoteSegmentComposerError.invalidSegment }
            let naturalSize = try await videoTrack.load(.naturalSize)
            try Task.checkCancellation()
            let length = Int(abs(naturalSize.width).rounded())
            guard length == Int(abs(naturalSize.height).rounded()),
                  length == 400,
                  expectedLength.map({ $0 == length }) ?? true
            else { throw VideoNoteSegmentComposerError.invalidSegment }
            expectedLength = length

            let duration = sourceDuration.seconds
            guard duration > 0,
                  abs(duration - segment.duration) < 0.05,
                  cursor.seconds + duration <= 60.01
            else { throw VideoNoteSegmentComposerError.invalidDuration }
            let timeRange = CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: duration, preferredTimescale: 600),
            )
            try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: cursor)
            try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: cursor)
            try Task.checkCancellation()
            let start = cursor.seconds
            cursor = cursor + timeRange.duration
            ranges.append(start ..< cursor.seconds)
        }
        guard cursor.seconds.isFinite,
              cursor.seconds >= 1,
              cursor.seconds <= 60.01
        else { throw VideoNoteSegmentComposerError.invalidDuration }
        try Task.checkCancellation()
        ownsSnapshot = false
        return VideoNoteCompositionResult(
            asset: composition,
            duration: cursor.seconds,
            segmentRanges: ranges,
            snapshotDirectory: snapshot.directory,
        )
    }

    static func thumbnails(
        for segments: [VideoNoteAsset],
        count: Int = 13,
        maximumPixelSize: Int = 160,
    ) async throws -> [VideoNoteThumbnailSample] {
        let result = try await compose(segments)
        defer { withExtendedLifetime(result) {} }
        let range = 0 ..< result.duration
        let sampleCount = max(1, count)
        let generator = AVAssetImageGenerator(asset: result.asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumPixelSize, height: maximumPixelSize)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await withTaskCancellationHandler {
            var samples = [VideoNoteThumbnailSample]()
            samples.reserveCapacity(sampleCount)
            for index in 0 ..< sampleCount {
                try Task.checkCancellation()
                let fraction = Double(index) / Double(sampleCount)
                let time = range.lowerBound + (range.upperBound - range.lowerBound) * fraction
                let image = try await generator.image(
                    at: CMTime(seconds: time, preferredTimescale: 600),
                ).image
                let jpegData = try await Task.detached(priority: .utility) {
                    try encodeJPEG(SendableCGImage(image), quality: 0.72)
                }.value
                try Task.checkCancellation()
                samples.append(VideoNoteThumbnailSample(jpegData: jpegData, time: time))
            }
            try Task.checkCancellation()
            return samples
        } onCancel: {
            generator.cancelAllCGImageGeneration()
        }
    }

    static func materialize(
        segments: [VideoNoteAsset],
        trimRange: Range<Double>?,
        outputURL: URL,
    ) async throws -> VideoNoteAsset {
        let resolvedOutputURL = outputURL.resolvingSymlinksInPath().standardizedFileURL
        guard !segments.contains(where: {
            $0.url.resolvingSymlinksInPath().standardizedFileURL == resolvedOutputURL
        }) else { throw VideoNoteSegmentComposerError.invalidSegment }
        try? FileManager.default.removeItem(at: outputURL)
        try Task.checkCancellation()
        let result = try await compose(segments)
        defer { withExtendedLifetime(result) {} }
        let range = try normalizedRange(trimRange, duration: result.duration, minimumDuration: 1)
        let timeRange = CMTimeRange(
            start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
            duration: CMTime(seconds: range.upperBound - range.lowerBound, preferredTimescale: 600),
        )
        let presets = [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
        var lastError: Error?
        for preset in presets {
            try Task.checkCancellation()
            try? FileManager.default.removeItem(at: outputURL)
            do {
                try await export(
                    asset: result.asset,
                    timeRange: timeRange,
                    outputURL: outputURL,
                    presetName: preset,
                )
                try Task.checkCancellation()
                let validated = try await VideoNoteAssetWriter.validate(url: outputURL, expectedLength: 400)
                try Task.checkCancellation()
                guard abs(validated.duration - timeRange.duration.seconds) < 0.05 else {
                    throw VideoNoteSegmentComposerError.invalidDuration
                }
                try Task.checkCancellation()
                return validated
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: outputURL)
                throw CancellationError()
            } catch {
                lastError = error
                try? FileManager.default.removeItem(at: outputURL)
            }
        }
        throw lastError ?? VideoNoteSegmentComposerError.exportFailed
    }

    #if DEBUG
        private static func runDebugProbe() async {
            let temporaryDirectory = FileManager.default.temporaryDirectory
            let firstURL = temporaryDirectory.appendingPathComponent("video-note-segment-a-\(UUID().uuidString).mp4")
            let secondURL = temporaryDirectory.appendingPathComponent("video-note-segment-b-\(UUID().uuidString).mp4")
            let outputURL = temporaryDirectory.appendingPathComponent("video-note-segments-output-\(UUID().uuidString).mp4")
            let cleanupURLs = [firstURL, secondURL, outputURL]
            defer { cleanupURLs.forEach { try? FileManager.default.removeItem(at: $0) } }
            var stage = "segments"
            do {
                async let first = VideoNoteAssetWriter.makeDebugSegment(
                    outputURL: firstURL,
                    duration: 0.7,
                    frameSeed: 3,
                )
                async let second = VideoNoteAssetWriter.makeDebugSegment(
                    outputURL: secondURL,
                    duration: 0.8,
                    frameSeed: 70,
                )
                let segments = try await [first, second]
                stage = "ownership guards"
                var rejectedAlias = false
                do {
                    _ = try await materialize(
                        segments: segments,
                        trimRange: nil,
                        outputURL: firstURL,
                    )
                } catch {
                    rejectedAlias = true
                }
                guard rejectedAlias,
                      FileManager.default.fileExists(atPath: firstURL.path(percentEncoded: false))
                else { throw VideoNoteSegmentComposerError.invalidSegment }
                try Data([12, 13]).write(to: outputURL, options: .atomic)
                do {
                    _ = try await materialize(segments: [], trimRange: nil, outputURL: outputURL)
                } catch {
                    guard !FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)) else {
                        throw VideoNoteSegmentComposerError.exportFailed
                    }
                }
                var rejectedMetadataMismatch = false
                do {
                    _ = try await compose([
                        VideoNoteAsset(duration: 0.2, length: first.length, url: first.url),
                    ])
                } catch {
                    rejectedMetadataMismatch = true
                }
                guard rejectedMetadataMismatch else {
                    throw VideoNoteSegmentComposerError.invalidSegment
                }
                stage = "composition"
                let composition = try await compose(segments)
                guard abs(composition.duration - 1.5) < 0.03,
                      composition.segmentRanges.count == 2,
                      abs(composition.segmentRanges[0].upperBound - 0.7) < 0.03,
                      abs(composition.segmentRanges[1].lowerBound - 0.7) < 0.03
                else { throw VideoNoteSegmentComposerError.invalidDuration }
                let compositionVideoTracks = try await composition.asset.loadTracks(withMediaType: .video)
                let compositionAudioTracks = try await composition.asset.loadTracks(withMediaType: .audio)
                guard let compositionVideoTrack = compositionVideoTracks.first,
                      let compositionAudioTrack = compositionAudioTracks.first
                else { throw VideoNoteSegmentComposerError.invalidSegment }
                let videoMappings = try await compositionVideoTrack.load(.segments).map(\.timeMapping.target)
                let audioMappings = try await compositionAudioTrack.load(.segments).map(\.timeMapping.target)
                guard videoMappings.count == 2,
                      audioMappings.count == 2,
                      zip(videoMappings, audioMappings).allSatisfy({ video, audio in
                          abs(video.start.seconds - audio.start.seconds) < 0.001
                              && abs(video.duration.seconds - audio.duration.seconds) < 0.001
                      }),
                      abs(videoMappings[1].start.seconds - 0.7) < 0.03
                else { throw VideoNoteSegmentComposerError.invalidSegment }
                stage = "thumbnails"
                let thumbnails = try await thumbnails(for: segments)
                guard thumbnails.count == 13,
                      thumbnails.allSatisfy({ !$0.jpegData.isEmpty }),
                      thumbnails.first?.time == 0,
                      thumbnails.enumerated().allSatisfy({ index, thumbnail in
                          abs(thumbnail.time - Double(index) * composition.duration / 13) < 0.001
                      }),
                      thumbnails.first?.jpegData != thumbnails.last?.jpegData
                else { throw VideoNoteSegmentComposerError.invalidSegment }
                stage = "materialization"
                let materialized = try await materialize(
                    segments: segments,
                    trimRange: 0.2 ..< 1.3,
                    outputURL: outputURL,
                )
                guard abs(materialized.duration - 1.1) < 0.05,
                      materialized.length == 400
                else { throw VideoNoteSegmentComposerError.invalidDuration }
                stage = "decoded order"
                let outputAsset = AVURLAsset(url: materialized.url)
                let sourceFirstGreen = try await centerGreen(asset: composition.asset, time: 0.25)
                let sourceSecondGreen = try await centerGreen(asset: composition.asset, time: 0.75)
                let sourceLastGreen = try await centerGreen(asset: composition.asset, time: 1.25)
                let outputFirstGreen = try await centerGreen(asset: outputAsset, time: 0.05)
                let outputBoundaryGreen = try await centerGreen(asset: outputAsset, time: 0.55)
                let outputLastGreen = try await centerGreen(asset: outputAsset, time: 1.05)
                let outputVideoTrack = try await outputAsset.loadTracks(withMediaType: .video).first
                let outputAudioTrack = try await outputAsset.loadTracks(withMediaType: .audio).first
                guard abs(Int(sourceFirstGreen) - Int(sourceSecondGreen)) > 20,
                      abs(Int(outputFirstGreen) - Int(sourceFirstGreen)) < 12,
                      abs(Int(outputBoundaryGreen) - Int(sourceSecondGreen)) < 12,
                      abs(Int(outputLastGreen) - Int(sourceLastGreen)) < 12,
                      let outputVideoTrack,
                      let outputAudioTrack,
                      abs(try await outputVideoTrack.load(.timeRange).start.seconds) < 0.05,
                      abs(try await outputAudioTrack.load(.timeRange).start.seconds) < 0.05
                else { throw VideoNoteSegmentComposerError.invalidSegment }
                stage = "decoded audio"
                let firstRMS = try await audioRMS(asset: outputAsset, range: 0.2 ..< 0.4)
                let secondRMS = try await audioRMS(asset: outputAsset, range: 0.65 ..< 0.85)
                guard firstRMS > 100,
                      secondRMS > firstRMS * 1.12
                else { throw VideoNoteSegmentComposerError.invalidSegment }
                let proof = "Video note segment probe: ordered=2, duration=\(composition.duration), "
                    + "A/V-boundaries=2, thumbnails=\(thumbnails.count), "
                    + "global-trim=\(materialized.duration), decoded-order/audio=true, zero-start=true"
                writeDebugProbeResult(proof)
                log(proof)
            } catch {
                writeDebugProbeResult("Video note segment probe failed at \(stage): \(error)")
                assertionFailure("Video note segment probe failed at \(stage): \(error)")
            }
        }

        private static func centerGreen(asset: AVAsset, time: Double) async throws -> UInt8 {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let image = try await generator.image(
                at: CMTime(seconds: time, preferredTimescale: 600),
            ).image
            let ciImage = CIImage(cgImage: image)
            let context = CIContext(options: [.cacheIntermediates: false])
            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(
                ciImage,
                toBitmap: &pixel,
                rowBytes: 4,
                bounds: CGRect(x: image.width / 2, y: image.height / 2, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB(),
            )
            return pixel[1]
        }

        private static func audioRMS(asset: AVAsset, range: Range<Double>) async throws -> Double {
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                throw VideoNoteSegmentComposerError.invalidSegment
            }
            let reader = try AVAssetReader(asset: asset)
            reader.timeRange = CMTimeRange(
                start: CMTime(seconds: range.lowerBound, preferredTimescale: 48_000),
                duration: CMTime(
                    seconds: range.upperBound - range.lowerBound,
                    preferredTimescale: 48_000,
                ),
            )
            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false,
                ],
            )
            guard reader.canAdd(output) else { throw VideoNoteSegmentComposerError.invalidSegment }
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? VideoNoteSegmentComposerError.invalidSegment }
            var squaredSum = Double.zero
            var count = 0
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
                guard status == kCMBlockBufferNoErr else {
                    throw VideoNoteSegmentComposerError.invalidSegment
                }
                data.withUnsafeBytes { bytes in
                    for sample in bytes.bindMemory(to: Int16.self) {
                        let value = Double(sample)
                        squaredSum += value * value
                        count += 1
                    }
                }
            }
            guard reader.status == .completed, count > 1_000 else {
                throw reader.error ?? VideoNoteSegmentComposerError.invalidSegment
            }
            return sqrt(squaredSum / Double(count))
        }

        private static func writeDebugProbeResult(_ result: String) {
            guard let documentsURL = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask,
            ).first else { return }
            try? Data(result.utf8).write(
                to: documentsURL.appendingPathComponent("video-note-segment-probe.txt"),
                options: .atomic,
            )
        }
    #endif

    private struct SegmentSnapshot: Sendable {
        let directory: URL
        let segments: [VideoNoteAsset]
    }

    private static func snapshotSegments(_ segments: [VideoNoteAsset]) async throws -> SegmentSnapshot {
        let task = Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let directory = fileManager.temporaryDirectory
                .appendingPathComponent("bettertg-video-note-composition-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            do {
                var snapshots = [VideoNoteAsset]()
                snapshots.reserveCapacity(segments.count)
                for (index, segment) in segments.enumerated() {
                    try Task.checkCancellation()
                    let sourcePath = segment.url.path(percentEncoded: false)
                    guard fileManager.fileExists(atPath: sourcePath) else {
                        throw VideoNoteSegmentComposerError.invalidSegment
                    }
                    let destination = directory
                        .appendingPathComponent(String(format: "%03d", index))
                        .appendingPathExtension("mp4")
                    try fileManager.copyItem(at: segment.url, to: destination)
                    snapshots.append(VideoNoteAsset(
                        duration: segment.duration,
                        length: segment.length,
                        url: destination,
                    ))
                }
                return SegmentSnapshot(directory: directory, segments: snapshots)
            } catch {
                try? fileManager.removeItem(at: directory)
                throw error
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func normalizedRange(
        _ requestedRange: Range<Double>?,
        duration: Double,
        minimumDuration: Double,
    ) throws -> Range<Double> {
        guard duration.isFinite, duration > 0 else {
            throw VideoNoteSegmentComposerError.invalidDuration
        }
        let lowerBound = min(duration, max(0, requestedRange?.lowerBound ?? 0))
        let upperBound = min(duration, max(lowerBound, requestedRange?.upperBound ?? duration))
        guard upperBound - lowerBound >= minimumDuration,
              upperBound - lowerBound <= 60
        else { throw VideoNoteSegmentComposerError.invalidDuration }
        return lowerBound ..< upperBound
    }

    private static func export(
        asset: AVAsset,
        timeRange: CMTimeRange,
        outputURL: URL,
        presetName: String,
    ) async throws {
        guard let exporter = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw VideoNoteSegmentComposerError.exportFailed
        }
        exporter.shouldOptimizeForNetworkUse = true
        exporter.timeRange = timeRange
        let exporterBox = ExportSessionBox(exporter)
        try await withTaskCancellationHandler {
            try await exporterBox.value.export(to: outputURL, as: .mp4)
        } onCancel: {
            exporterBox.value.cancelExport()
        }
    }

    private final class ExportSessionBox: @unchecked Sendable {
        init(_ value: AVAssetExportSession) { self.value = value }
        let value: AVAssetExportSession
    }

    private struct SendableCGImage: @unchecked Sendable {
        init(_ image: CGImage) { self.image = image }
        let image: CGImage
    }

    private static func encodeJPEG(_ image: SendableCGImage, quality: Double) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil,
        ) else { throw VideoNoteSegmentComposerError.exportFailed }
        CGImageDestinationAddImage(
            destination,
            image.image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary,
        )
        guard CGImageDestinationFinalize(destination) else {
            throw VideoNoteSegmentComposerError.exportFailed
        }
        return data as Data
    }
}
