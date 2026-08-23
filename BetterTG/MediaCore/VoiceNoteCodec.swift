// VoiceNoteCodec.swift

import AVFoundation
import FFmpegBridge
import Foundation

// MARK: - VoiceNoteCodec

enum VoiceNoteCodec {
    // MARK: Internal

    enum CodecError: Error {
        case encodingFailed(Int32)
        case invalidOutput
    }

    static func encodeOggOpus(from inputURL: URL) async throws -> URL {
        let outputURL = inputURL
            .deletingPathExtension()
            .appendingPathExtension("ogg")
        guard inputURL.standardizedFileURL != outputURL.standardizedFileURL else {
            throw CodecError.invalidOutput
        }
        try? FileManager.default.removeItem(at: outputURL)
        let result = await Task.detached(priority: .userInitiated) {
            inputURL.path.withCString { inputPath in
                outputURL.path.withCString { outputPath in
                    BetterTGFFmpegTranscodeVoiceNote(inputPath, outputPath, 30720)
                }
            }
        }.value
        guard result == 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            throw CodecError.encodingFailed(result)
        }
        guard outputURL.path.withCString({ BetterTGFFmpegIsOggOpusFile($0) }) == 1 else {
            try? FileManager.default.removeItem(at: outputURL)
            throw CodecError.invalidOutput
        }
        return outputURL
    }

    static func encodeWaveform(peakPowers: [Float], maximumSamples: Int = 100) -> Data {
        guard maximumSamples > 0, !peakPowers.isEmpty else { return Data() }
        return pack(samples: resample(peakPowers: peakPowers, maximumSamples: maximumSamples))
    }

    #if DEBUG
        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-voice-codec") else { return }
            Task {
                do {
                    let temporaryDirectory = FileManager.default.temporaryDirectory
                    let inputURL = temporaryDirectory.appendingPathComponent("bettertg-voice-codec-probe.wav")
                    try makeProbeInput(at: inputURL)
                    let outputURL = try await encodeOggOpus(from: inputURL)
                    let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
                    let size = attributes[.size] as? NSNumber
                    let referenceSamples = (0..<100).map { UInt8($0 % 32) }
                    let packedWaveform = pack(samples: referenceSamples)
                    precondition(
                        unpack(data: packedWaveform, sampleCount: referenceSamples.count) == referenceSamples,
                        "Voice waveform packing must be 5-bit LSB-first",
                    )
                    log(
                        "Voice codec probe: Ogg/Opus valid, \(size?.intValue ?? 0) bytes; "
                            + "waveform round-trip \(packedWaveform.count) bytes",
                    )
                    try? FileManager.default.removeItem(at: inputURL)
                    try? FileManager.default.removeItem(at: outputURL)
                } catch {
                    assertionFailure("Voice codec probe failed: \(error)")
                }
            }
        }
    #endif

    // MARK: Private

    private static func pack(samples: [UInt8]) -> Data {
        var packed = [UInt8](repeating: 0, count: (samples.count * 5 + 7) / 8)
        for (index, sample) in samples.enumerated() {
            let value = min(sample, 31)
            let bitOffset = index * 5
            let byteIndex = bitOffset / 8
            let shift = bitOffset % 8
            packed[byteIndex] |= value << shift
            if shift > 3, byteIndex + 1 < packed.count {
                packed[byteIndex + 1] |= value >> (8 - shift)
            }
        }
        return Data(packed)
    }

    #if DEBUG
        private static func makeProbeInput(at url: URL) throws {
            try? FileManager.default.removeItem(at: url)
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000),
                  let samples = buffer.floatChannelData?[0]
            else { throw CodecError.invalidOutput }
            buffer.frameLength = buffer.frameCapacity
            for index in 0..<Int(buffer.frameLength) {
                samples[index] = sin(Float(index) * 2 * .pi * 440 / 16000) * 0.2
            }
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }

        private static func unpack(data: Data, sampleCount: Int) -> [UInt8] {
            data.withUnsafeBytes { rawBuffer in
                let bytes = rawBuffer.bindMemory(to: UInt8.self)
                return (0..<sampleCount).map { index in
                    let bitOffset = index * 5
                    let byteIndex = bitOffset / 8
                    let shift = bitOffset % 8
                    var value = UInt16(bytes[byteIndex])
                    if byteIndex + 1 < bytes.count {
                        value |= UInt16(bytes[byteIndex + 1]) << 8
                    }
                    return UInt8((value >> shift) & 0x1F)
                }
            }
        }
    #endif

    private static func resample(peakPowers: [Float], maximumSamples: Int) -> [UInt8] {
        let sampleCount = min(maximumSamples, peakPowers.count)
        return (0..<sampleCount).map { sampleIndex in
            let lowerBound = sampleIndex * peakPowers.count / sampleCount
            let upperBound = max(lowerBound + 1, (sampleIndex + 1) * peakPowers.count / sampleCount)
            let peak = peakPowers[lowerBound..<min(upperBound, peakPowers.count)].max() ?? -160
            let amplitude = pow(10, Double(max(-60, min(0, peak))) / 20)
            return UInt8((sqrt(amplitude) * 31).rounded().clamped(to: 0...31))
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
