// VoiceNotePCMEditor.swift

import AVFoundation
import Foundation

// MARK: - VoiceNotePCMInspection

struct VoiceNotePCMInspection {
    let duration: Double
    let frameCount: AVAudioFramePosition
    let waveform: Data
}

// MARK: - VoiceNotePCMEditor

enum VoiceNotePCMEditor {
    enum EditorError: Swift.Error {
        case emptyAudio
        case incompatibleFormat
        case invalidRange
        case unsupportedPCMFormat
    }

    static let recordingSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    private static let sampleRate = 48000.0
    private static let bufferFrames: AVAudioFrameCount = 8192

    static func inspect(_ url: URL) async throws -> VoiceNotePCMInspection {
        let task = Task.detached(priority: .userInitiated) {
            try inspectSynchronously(url)
        }
        return try await withTaskCancellationHandler {
            let inspection = try await task.value
            try Task.checkCancellation()
            return inspection
        } onCancel: {
            task.cancel()
        }
    }

    static func concatenate(_ sourceURLs: [URL], outputURL: URL) async throws -> VoiceNotePCMInspection {
        let task = Task.detached(priority: .userInitiated) {
            try concatenateSynchronously(sourceURLs, outputURL: outputURL)
        }
        return try await withTaskCancellationHandler {
            let inspection = try await task.value
            do {
                try Task.checkCancellation()
                return inspection
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                throw error
            }
        } onCancel: {
            task.cancel()
        }
    }

    static func trim(
        _ sourceURL: URL,
        outputURL: URL,
        range: Range<Double>,
    ) async throws -> VoiceNotePCMInspection {
        let task = Task.detached(priority: .userInitiated) {
            try trimSynchronously(sourceURL, outputURL: outputURL, range: range)
        }
        return try await withTaskCancellationHandler {
            let inspection = try await task.value
            do {
                try Task.checkCancellation()
                return inspection
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                throw error
            }
        } onCancel: {
            task.cancel()
        }
    }

    private static func inspectSynchronously(_ url: URL) throws -> VoiceNotePCMInspection {
        let file = try AVAudioFile(forReading: url)
        try validate(file, url: url)
        let frameCount = file.length
        guard frameCount > 0 else { throw EditorError.emptyAudio }
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferFrames) else {
            throw EditorError.incompatibleFormat
        }
        var peaks = [Float](repeating: 0, count: 100)
        var frameOffset = AVAudioFramePosition.zero
        while frameOffset < frameCount {
            try Task.checkCancellation()
            buffer.frameLength = 0
            try file.read(into: buffer, frameCount: min(bufferFrames, AVAudioFrameCount(frameCount - frameOffset)))
            guard buffer.frameLength > 0 else { break }
            try accumulatePeaks(
                from: buffer,
                frameOffset: frameOffset,
                totalFrames: frameCount,
                peaks: &peaks,
            )
            frameOffset += AVAudioFramePosition(buffer.frameLength)
        }
        guard frameOffset == frameCount else { throw EditorError.emptyAudio }
        return VoiceNotePCMInspection(
            duration: Double(frameCount) / sampleRate,
            frameCount: frameCount,
            waveform: VoiceNoteCodec.encodeWaveform(linearPCMNormalizedPeaks: peaks),
        )
    }

    private static func concatenateSynchronously(
        _ sourceURLs: [URL],
        outputURL: URL,
    ) throws -> VoiceNotePCMInspection {
        let standardizedOutputURL = outputURL.standardizedFileURL
        guard !sourceURLs.contains(where: { $0.standardizedFileURL == standardizedOutputURL }) else {
            throw EditorError.incompatibleFormat
        }
        guard let firstURL = sourceURLs.first else { throw EditorError.emptyAudio }
        let firstFile = try AVAudioFile(forReading: firstURL)
        try validate(firstFile, url: firstURL)
        try? FileManager.default.removeItem(at: outputURL)
        do {
            do {
                let outputFile = try AVAudioFile(forWriting: outputURL, settings: recordingSettings)
                for sourceURL in sourceURLs {
                    try Task.checkCancellation()
                    let sourceFile = try AVAudioFile(forReading: sourceURL)
                    try validate(sourceFile, url: sourceURL)
                    guard sourceFile.length > 0 else { throw EditorError.emptyAudio }
                    guard formatsAreCompatible(firstFile.processingFormat, sourceFile.processingFormat),
                          let buffer = AVAudioPCMBuffer(
                              pcmFormat: sourceFile.processingFormat,
                              frameCapacity: bufferFrames,
                          ) else { throw EditorError.incompatibleFormat }
                    while sourceFile.framePosition < sourceFile.length {
                        try Task.checkCancellation()
                        buffer.frameLength = 0
                        try sourceFile.read(
                            into: buffer,
                            frameCount: min(
                                bufferFrames,
                                AVAudioFrameCount(sourceFile.length - sourceFile.framePosition),
                            ),
                        )
                        guard buffer.frameLength > 0 else { throw EditorError.emptyAudio }
                        try outputFile.write(from: buffer)
                    }
                    guard sourceFile.framePosition == sourceFile.length else { throw EditorError.emptyAudio }
                }
            }
            return try inspectSynchronously(outputURL)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private static func trimSynchronously(
        _ sourceURL: URL,
        outputURL: URL,
        range: Range<Double>,
    ) throws -> VoiceNotePCMInspection {
        guard sourceURL.standardizedFileURL != outputURL.standardizedFileURL else {
            throw EditorError.incompatibleFormat
        }
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        try validate(sourceFile, url: sourceURL)
        let sourceDuration = Double(sourceFile.length) / sampleRate
        guard range.lowerBound >= 0,
              range.lowerBound < range.upperBound,
              range.upperBound <= sourceDuration + 0.000_001
        else { throw EditorError.invalidRange }
        let startFrame = max(
            AVAudioFramePosition.zero,
            AVAudioFramePosition(floor(range.lowerBound * sampleRate)),
        )
        let endFrame = min(
            sourceFile.length,
            AVAudioFramePosition(ceil(range.upperBound * sampleRate)),
        )
        guard startFrame < endFrame else { throw EditorError.invalidRange }
        try? FileManager.default.removeItem(at: outputURL)
        do {
            do {
                let outputFile = try AVAudioFile(forWriting: outputURL, settings: recordingSettings)
                sourceFile.framePosition = startFrame
                guard let buffer = AVAudioPCMBuffer(
                    pcmFormat: sourceFile.processingFormat,
                    frameCapacity: bufferFrames,
                ) else { throw EditorError.incompatibleFormat }
                while sourceFile.framePosition < endFrame {
                    try Task.checkCancellation()
                    let remainingFrames = endFrame - sourceFile.framePosition
                    buffer.frameLength = 0
                    try sourceFile.read(
                        into: buffer,
                        frameCount: min(bufferFrames, AVAudioFrameCount(remainingFrames)),
                    )
                    guard buffer.frameLength > 0 else { throw EditorError.emptyAudio }
                    try outputFile.write(from: buffer)
                }
                guard sourceFile.framePosition == endFrame else { throw EditorError.emptyAudio }
            }
            return try inspectSynchronously(outputURL)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private static func validate(_ file: AVAudioFile, url: URL) throws {
        let format = file.processingFormat
        let settings = file.fileFormat.settings
        let formatID = (settings[AVFormatIDKey] as? NSNumber)?.uint32Value
        let bitDepth = (settings[AVLinearPCMBitDepthKey] as? NSNumber)?.intValue
        let isFloat = (settings[AVLinearPCMIsFloatKey] as? NSNumber)?.boolValue ?? false
        let isBigEndian = (settings[AVLinearPCMIsBigEndianKey] as? NSNumber)?.boolValue ?? false
        guard url.pathExtension.lowercased() == "wav",
              formatID == kAudioFormatLinearPCM,
              bitDepth == 16,
              !isFloat,
              !isBigEndian,
              abs(format.sampleRate - sampleRate) < 0.5,
              format.channelCount == 1
        else {
            throw EditorError.incompatibleFormat
        }
    }

    private static func formatsAreCompatible(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        abs(lhs.sampleRate - rhs.sampleRate) < 0.5
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }

    private static func accumulatePeaks(
        from buffer: AVAudioPCMBuffer,
        frameOffset: AVAudioFramePosition,
        totalFrames: AVAudioFramePosition,
        peaks: inout [Float],
    ) throws {
        let frameLength = Int(buffer.frameLength)
        let sample: (Int) throws -> Float
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channel = buffer.floatChannelData?[0] else { throw EditorError.unsupportedPCMFormat }
            sample = { abs(channel[$0]) }
        case .pcmFormatInt16:
            guard let channel = buffer.int16ChannelData?[0] else { throw EditorError.unsupportedPCMFormat }
            sample = { Float(abs(Int(channel[$0]))) / Float(Int16.max) }
        case .pcmFormatInt32:
            guard let channel = buffer.int32ChannelData?[0] else { throw EditorError.unsupportedPCMFormat }
            sample = { Float(abs(Int64(channel[$0]))) / Float(Int64(Int32.max)) }
        default:
            throw EditorError.unsupportedPCMFormat
        }
        for index in 0..<frameLength {
            let absoluteFrame = frameOffset + AVAudioFramePosition(index)
            let bucket = min(peaks.count - 1, Int(absoluteFrame * AVAudioFramePosition(peaks.count) / totalFrames))
            peaks[bucket] = try max(peaks[bucket], min(1, sample(index)))
        }
    }
}
