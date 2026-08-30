// VoiceNoteCodec.swift

import AVFoundation
import FFmpegBridge
import Foundation
import TDLibKitDynamic

// MARK: - VoiceNoteCodec

enum VoiceNoteCodec {
    // MARK: Internal

    enum CodecError: Swift.Error {
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
        guard !Task.isCancelled else {
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        }
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
        guard maximumSamples > 0 else { return Data() }
        guard !peakPowers.isEmpty else {
            return Data(repeating: 0, count: (maximumSamples * 5 + 7) / 8)
        }
        return pack(samples: resample(peakPowers: peakPowers, maximumSamples: maximumSamples))
    }

    static func normalizedWaveform(peakPowers: [Float], maximumSamples: Int = 100) -> [Float] {
        guard maximumSamples > 0, !peakPowers.isEmpty else { return [] }
        return resample(peakPowers: peakPowers, maximumSamples: maximumSamples).map { Float($0) / 31 }
    }

    static func encodeWaveform(linearPCMNormalizedPeaks: [Float], maximumSamples: Int = 100) -> Data {
        guard maximumSamples > 0 else { return Data() }
        guard !linearPCMNormalizedPeaks.isEmpty else {
            return Data(repeating: 0, count: (maximumSamples * 5 + 7) / 8)
        }
        let peaks = (0..<maximumSamples).map { sampleIndex -> Int in
            let lowerBound = sampleIndex * linearPCMNormalizedPeaks.count / maximumSamples
            let upperBound = max(
                lowerBound + 1,
                (sampleIndex + 1) * linearPCMNormalizedPeaks.count / maximumSamples,
            )
            let peak = linearPCMNormalizedPeaks[
                lowerBound..<min(upperBound, linearPCMNormalizedPeaks.count),
            ].max() ?? 0
            return Int((min(1, max(0, peak)) * Float(Int16.max)).rounded())
        }
        let normalizationPeak = max(2500, Int(Double(peaks.reduce(0, +)) * 1.8 / Double(maximumSamples)))
        let samples = peaks.map { peak -> UInt8 in
            UInt8(clamping: min(31, min(peak, normalizationPeak) * 31 / normalizationPeak))
        }
        return pack(samples: samples)
    }

    static func normalizedWaveform(data: Data) -> [Float] {
        guard !data.isEmpty else { return [] }
        return unpack(data: data, sampleCount: data.count * 8 / 5).map { Float($0) / 31 }
    }

    #if DEBUG
        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-voice-codec") else { return }
            writeDebugProbeResult("Voice codec probe started")
            Task {
                let temporaryDirectory = FileManager.default.temporaryDirectory
                let inputURL = temporaryDirectory.appendingPathComponent("bettertg-voice-codec-probe.wav")
                let outputURL = inputURL.deletingPathExtension().appendingPathExtension("ogg")
                let firstSegmentURL = temporaryDirectory.appendingPathComponent("bettertg-voice-segment-1.wav")
                let secondSegmentURL = temporaryDirectory.appendingPathComponent("bettertg-voice-segment-2.wav")
                let thirdSegmentURL = temporaryDirectory.appendingPathComponent("bettertg-voice-segment-3.wav")
                let mergedURL = temporaryDirectory.appendingPathComponent("bettertg-voice-segments-merged.wav")
                let trimURL = temporaryDirectory.appendingPathComponent("bettertg-voice-segments-trimmed.wav")
                let replacementURL = temporaryDirectory.appendingPathComponent("bettertg-voice-segments-replaced.wav")
                let temporaryURLs = [
                    inputURL,
                    outputURL,
                    firstSegmentURL,
                    secondSegmentURL,
                    thirdSegmentURL,
                    mergedURL,
                    trimURL,
                    replacementURL,
                ]
                var recordingProbeDraftID: UUID?
                do {
                    try makeProbeInput(at: inputURL)
                    let encodedURL = try await encodeOggOpus(from: inputURL)
                    precondition(encodedURL == outputURL)
                    writeDebugProbeResult("Voice codec probe stage: encoded")
                    let playbackURL = await FFmpegAudioPlaybackCache.shared.playableURL(for: outputURL)
                    let reusedPlaybackURL = await FFmpegAudioPlaybackCache.shared.playableURL(for: outputURL)
                    precondition(playbackURL != outputURL)
                    precondition(reusedPlaybackURL == playbackURL)
                    let playbackFile = try AVAudioFile(forReading: playbackURL)
                    precondition(playbackFile.length > 0)
                    precondition(playbackFile.processingFormat.sampleRate == 48000)
                    precondition(playbackFile.processingFormat.channelCount == 1)
                    writeDebugProbeResult("Voice codec probe stage: playback")
                    let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
                    let size = attributes[.size] as? NSNumber
                    let referenceSamples = (0..<100).map { UInt8($0 % 32) }
                    let packedWaveform = pack(samples: referenceSamples)
                    precondition(encodeWaveform(peakPowers: [-60, -30, 0]).count == 63)
                    precondition(encodeWaveform(peakPowers: []).count == 63)
                    precondition(
                        unpack(data: packedWaveform, sampleCount: referenceSamples.count) == referenceSamples,
                        "Voice waveform packing must be 5-bit LSB-first",
                    )
                    let draft = VoiceNoteSendDraft(
                        id: UUID(),
                        chatID: Int64.min + 1,
                        caption: FormattedText(entities: [], text: ""),
                        createdAt: Foundation.Date(),
                        duration: 1,
                        enqueueStartedAt: nil,
                        failedSendState: nil,
                        fileURL: outputURL,
                        isEncoded: true,
                        replyMessageID: nil,
                        replyTo: nil,
                        temporaryMessageID: nil,
                        waveform: packedWaveform,
                    )
                    let storedDraft = try await VoiceNoteDraftStore.shared.adopt(draft)
                    let enqueueingDraft = try await VoiceNoteDraftStore.shared.beginEnqueue(storedDraft)
                    let probeMessageID = Int64.min + 2
                    let probeFailedState = VoiceNoteFailedSendState(
                        canRetry: true,
                        messageID: probeMessageID + 1,
                        needAnotherReplyQuote: false,
                        needAnotherSender: false,
                        requiredPaidMessageStarCount: 0,
                        retryAvailableAt: Foundation.Date(),
                    )
                    let earlyResolution = try await VoiceNoteDraftStore.shared.handleSendFailed(
                        chatID: draft.chatID,
                        temporaryMessageID: probeMessageID,
                        failedSendState: probeFailedState,
                    )
                    precondition(earlyResolution == nil)
                    let registration = try await VoiceNoteDraftStore.shared.registerEnqueued(
                        enqueueingDraft,
                        temporaryMessageID: probeMessageID,
                    )
                    precondition(registration.outcome == .failed)
                    precondition(registration.draft.temporaryMessageID == nil)
                    precondition(registration.draft.failedSendState?.messageID == probeMessageID + 1)
                    precondition(FileManager.default.fileExists(atPath: registration.draft.fileURL.path))
                    await VoiceNoteDraftStore.shared.remove(registration.draft)
                    writeDebugProbeResult("Voice codec probe stage: send draft")
                    writeDebugProbeResult("Voice codec probe stage: creating PCM 1")
                    try makePCMProbeInput(at: firstSegmentURL, frameCount: 48000, frequency: 330, amplitude: 0.08)
                    writeDebugProbeResult("Voice codec probe stage: creating PCM 2")
                    try makePCMProbeInput(at: secondSegmentURL, frameCount: 48000, frequency: 550, amplitude: 0.45)
                    writeDebugProbeResult("Voice codec probe stage: concatenating PCM")
                    let mergedInspection = try await VoiceNotePCMEditor.concatenate(
                        [firstSegmentURL, secondSegmentURL],
                        outputURL: mergedURL,
                    )
                    writeDebugProbeResult(
                        "Voice codec probe stage: PCM merge raw \(mergedInspection.frameCount) frames, "
                            + "\(mergedInspection.duration)s, \(mergedInspection.waveform.count) waveform bytes",
                    )
                    precondition(mergedInspection.frameCount == 96000)
                    precondition(abs(mergedInspection.duration - 2) < 0.001)
                    precondition(mergedInspection.waveform.count == 63)
                    let mergedSamples = normalizedWaveform(data: mergedInspection.waveform)
                    let firstAverage = mergedSamples.prefix(50).reduce(0, +) / 50
                    let secondAverage = mergedSamples.dropFirst(50).prefix(50).reduce(0, +) / 50
                    precondition(firstAverage < secondAverage)
                    let trimInspection = try await VoiceNotePCMEditor.trim(
                        mergedURL,
                        outputURL: trimURL,
                        range: 0.25..<1.75,
                    )
                    precondition(trimInspection.frameCount == 72000)
                    precondition(abs(trimInspection.duration - 1.5) < 0.000_001)
                    writeDebugProbeResult("Voice codec probe stage: PCM merge")
                    let recordingDraftID = UUID()
                    recordingProbeDraftID = recordingDraftID
                    let probeChatID = Int64.min + 3
                    for staleDraft in await VoiceRecordingDraftStore.shared.drafts(for: probeChatID) {
                        await VoiceRecordingDraftStore.shared.discard(id: staleDraft.id)
                    }
                    let recordingDraft = VoiceRecordingDraft(
                        id: recordingDraftID,
                        chatID: probeChatID,
                        caption: FormattedText(entities: [], text: ""),
                        createdAt: Foundation.Date(),
                        exactDuration: mergedInspection.duration,
                        fileURL: mergedURL,
                        replyMessageID: nil,
                        replyTo: nil,
                        revision: 0,
                        trimEnd: nil,
                        trimStart: nil,
                        waveform: mergedInspection.waveform,
                    )
                    let storedRecordingDraft = try await VoiceRecordingDraftStore.shared.adopt(recordingDraft)
                    writeDebugProbeResult("Voice codec probe stage: recording adopt")
                    try makePCMProbeInput(at: thirdSegmentURL, frameCount: 24000, frequency: 770, amplitude: 0.2)
                    let replacementInspection = try await VoiceNotePCMEditor.concatenate(
                        [storedRecordingDraft.fileURL, thirdSegmentURL],
                        outputURL: replacementURL,
                    )
                    let replacedRecordingDraft = try await VoiceRecordingDraftStore.shared.replaceMedia(
                        in: storedRecordingDraft,
                        with: replacementURL,
                        inspection: replacementInspection,
                    )
                    precondition(replacedRecordingDraft.revision == 1)
                    precondition(replacedRecordingDraft.exactDuration == 2.5)
                    precondition(replacedRecordingDraft.waveform.count == 63)
                    let restoredRecordingDrafts = await VoiceRecordingDraftStore.shared.drafts(
                        for: recordingDraft.chatID,
                    )
                    precondition(restoredRecordingDrafts == [replacedRecordingDraft])
                    writeDebugProbeResult("Voice codec probe stage: recording replace")
                    await VoiceRecordingDraftStore.shared.discard(id: recordingDraft.id)
                    recordingProbeDraftID = nil
                    let proof = "Voice codec probe: Ogg/Opus valid, \(size?.intValue ?? 0) bytes; "
                        + "waveform round-trip \(packedWaveform.count) bytes; "
                        + "cached PCM playback \(playbackFile.length) frames; durable retry reconciled; "
                            + "PCM16 segments \(replacementInspection.frameCount) frames, "
                            + "trim \(trimInspection.frameCount), order/revision restored"
                    writeDebugProbeResult(proof)
                    log(proof)
                    try? FileManager.default.removeItem(at: playbackURL)
                    cleanupDebugProbeFiles(temporaryURLs)
                } catch {
                    if let recordingProbeDraftID {
                        await VoiceRecordingDraftStore.shared.discard(id: recordingProbeDraftID)
                    }
                    cleanupDebugProbeFiles(temporaryURLs)
                    writeDebugProbeResult("Voice codec probe failed: \(error)")
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

        private static func makePCMProbeInput(
            at url: URL,
            frameCount: AVAudioFrameCount,
            frequency: Float,
            amplitude: Float,
        ) throws {
            try? FileManager.default.removeItem(at: url)
            let file = try AVAudioFile(forWriting: url, settings: VoiceNotePCMEditor.recordingSettings)
            let format = file.processingFormat
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
                let samples = buffer.floatChannelData?[0]
            else { throw CodecError.invalidOutput }
            buffer.frameLength = frameCount
            for index in 0..<Int(frameCount) {
                samples[index] = sin(Float(index) * 2 * .pi * frequency / 48000) * amplitude
            }
            try file.write(from: buffer)
        }

        private static func writeDebugProbeResult(_ result: String) {
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return
            }
            try? Data(result.utf8).write(
                to: documentsURL.appendingPathComponent("voice-codec-probe.txt"),
                options: .atomic,
            )
        }

        private static func cleanupDebugProbeFiles(_ urls: [URL]) {
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
        }

    #endif

    private static func unpack(data: Data, sampleCount: Int) -> [UInt8] {
        data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            return (0..<sampleCount).compactMap { index in
                let bitOffset = index * 5
                let byteIndex = bitOffset / 8
                guard byteIndex < bytes.count else { return nil }
                let shift = bitOffset % 8
                var value = UInt16(bytes[byteIndex])
                if byteIndex + 1 < bytes.count {
                    value |= UInt16(bytes[byteIndex + 1]) << 8
                }
                return UInt8((value >> shift) & 0x1F)
            }
        }
    }

    private static func resample(peakPowers: [Float], maximumSamples: Int) -> [UInt8] {
        let sampleCount = maximumSamples
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
