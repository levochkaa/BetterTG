// AudioMessageGain.swift

import Accelerate
import AVFoundation
import MediaToolbox
import Synchronization

// MARK: - AudioMessageGain

/// MediaPlayerAudioRenderer's equalizer for audio and video messages (`forAudioVideoMessage`): an NBandEQ global gain
/// between the mixer and the output, 0 dB on the speaker and louder from the earpiece. AVPlayer's volume stops at 1,
/// so an MTAudioProcessingTap on the item's audio tracks scales the decoded samples instead. The tap reads the gain
/// for every buffer, so a change applies to the playing item.
final class AudioMessageGain: Sendable {
    // MARK: Private

    /// Shared by the owner and every tap, which retains it until the tap finalizes.
    private final class Storage: Sendable {
        let factor = Atomic<UInt32>(Float(1).bitPattern)
        let isFloat32 = Atomic<Bool>(false)
        let measuredRatio = Atomic<UInt32>(0)

        /// Scales float samples in place and clips them to the output's range, as the output clips the equalizer's
        /// boosted signal.
        func apply(to bufferList: UnsafeMutablePointer<AudioBufferList>) {
            guard isFloat32.load(ordering: .relaxed) else { return }
            var factor = Float(bitPattern: factor.load(ordering: .relaxed))
            var low: Float = -1
            var high: Float = 1
            for buffer in UnsafeMutableAudioBufferListPointer(bufferList) {
                guard let data = buffer.mData else { continue }
                let count = vDSP_Length(Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
                guard count > 0 else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                #if DEBUG
                    var inputPeak: Float = 0
                    vDSP_maxmgv(samples, 1, &inputPeak, count)
                #endif
                if factor != 1 {
                    vDSP_vsmul(samples, 1, &factor, samples, 1, count)
                    vDSP_vclip(samples, 1, &low, &high, samples, 1, count)
                }
                #if DEBUG
                    var outputPeak: Float = 0
                    vDSP_maxmgv(samples, 1, &outputPeak, count)
                    if inputPeak > 0.001 {
                        measuredRatio.store((outputPeak / inputPeak).bitPattern, ordering: .relaxed)
                    }
                #endif
            }
        }
    }

    private let storage = Storage()

    // MARK: Internal

    #if DEBUG
        /// The gain the tap last applied, measured as the output peak over the input peak of a buffer.
        var measuredDecibels: Float? {
            let ratio = Float(bitPattern: storage.measuredRatio.load(ordering: .relaxed))
            return ratio > 0 ? 20 * log10(ratio) : nil
        }
    #endif

    func set(decibels: Float) {
        storage.factor.store(pow(10, decibels / 20).bitPattern, ordering: .relaxed)
    }

    /// An audio mix with the tap on every audio track; nil when the item has no audio or a tap can't be made.
    func audioMix(for tracks: [AVAssetTrack]) -> AVAudioMix? {
        guard !tracks.isEmpty else { return nil }
        var parameters = [AVMutableAudioMixInputParameters]()
        for track in tracks {
            guard let tap = makeTap() else { return nil }
            let input = AVMutableAudioMixInputParameters(track: track)
            input.audioTapProcessor = tap
            parameters.append(input)
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        return mix
    }

    private func makeTap() -> MTAudioProcessingTap? {
        let clientInfo = Unmanaged.passRetained(storage).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: clientInfo,
            init: { _, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<Storage>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                let storage = Unmanaged<Storage>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                let description = format.pointee
                let isFloat32 = description.mFormatFlags & kAudioFormatFlagIsFloat != 0
                    && description.mBitsPerChannel == 32
                storage.isFloat32.store(isFloat32, ordering: .relaxed)
            },
            unprepare: nil,
            process: { tap, numberFrames, _, bufferList, numberFramesOut, flagsOut in
                let status = MTAudioProcessingTapGetSourceAudio(
                    tap,
                    numberFrames,
                    bufferList,
                    flagsOut,
                    nil,
                    numberFramesOut,
                )
                guard status == noErr else { return }
                Unmanaged<Storage>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue()
                    .apply(to: bufferList)
            },
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            &tap,
        )
        guard status == noErr, let tap else {
            Unmanaged<Storage>.fromOpaque(clientInfo).release()
            return nil
        }
        return tap
    }
}
