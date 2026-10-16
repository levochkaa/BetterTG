// MusicPlayerProbe.swift

#if DEBUG
    import AVFoundation
    import UIKit

    /// Launch with `-ui-probe-music-player`. Once an account is active it plays a generated quiet tone as music from
    /// a chat that doesn't exist, so no account content plays, and opens the music player over the current screen.
    /// That chat has no tracks to list, so the player shows its controls alone. Pass `-ui-probe-music-player-long` to
    /// mark the track as longer than ten minutes, which shows the rate button.
    @MainActor enum MusicPlayerProbe {
        private static let toneDuration = 120.0

        static func runIfRequested(in window: UIWindow) {
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("-ui-probe-music-player") else { return }
            let isLong = arguments.contains("-ui-probe-music-player-long")
            Task { @MainActor in
                for _ in 0..<60 where TDLib.shared.activeAccountID == nil {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                guard let accountID = TDLib.shared.activeAccountID, let url = try? makeTone() else { return }
                try? await Task.sleep(for: .seconds(2))
                let item = Media.NowPlaying(accountID: accountID, chatID: -1, messageID: 1, isMusic: true)
                Media.shared.toggle(with: url.path, duration: Int(toneDuration), item: item)
                Media.shared.setDisplay(Media.NowPlayingDisplay(
                    item: item,
                    title: "Probe Tone",
                    subtitle: "BetterTG",
                    showsRate: isLong,
                ))
                var presenter = window.rootViewController
                while let presented = presenter?.presentedViewController {
                    presenter = presented
                }
                if let presenter { MusicPlayerViewController.present(from: presenter) }
            }
        }

        /// Two minutes of a quiet 440 Hz tone, long enough to inspect the player before it ends.
        private static func makeTone() throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("music-player-probe-120.wav")
            if FileManager.default.fileExists(atPath: url.path) { return url }
            let sampleRate = 8000.0
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let frames = AVAudioFrameCount(sampleRate * toneDuration)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                  let samples = buffer.floatChannelData?[0] else { throw CocoaError(.fileWriteUnknown) }
            buffer.frameLength = frames
            let step = Float(2 * Double.pi * 440 / sampleRate)
            for index in 0..<Int(frames) {
                samples[index] = 0.05 * sin(step * Float(index))
            }
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            return url
        }
    }
#endif
