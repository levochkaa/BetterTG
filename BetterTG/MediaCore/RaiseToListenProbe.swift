// RaiseToListenProbe.swift

#if DEBUG
    import AVFoundation
    import UIKit

    /// Launch with `-ui-probe-raise-to-listen`. The Simulator has no proximity sensor, so the probe stands in for
    /// it and checks Telegram's RaiseToListenActivator rules (a raise gives the ear one second, leaving the ear
    /// deactivates, a phone still at the ear activates at once, an activation under a second old is undone in the
    /// background), SharedMediaPlayer's proximity control of a voice note and a round video (earpiece at the ear,
    /// paused away from it) and MediaPlayerAudioRenderer's message equalizer (12 dB when a note starts at the ear,
    /// 5 dB when the phone comes up during playback), measured on the samples the tap scaled. The note is a generated
    /// quiet tone from a chat that doesn't exist. The results show in an alert.
    @MainActor enum RaiseToListenProbe {
        static func runIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-raise-to-listen") else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                var results = [(String, Bool)]()
                await checkActivator(into: &results)
                await checkVoicePlayback(into: &results)
                await checkVideoNotePlayback(into: &results)
                DeviceProximityMonitor.shared.simulate(nil)
                let lines = results.map { "\($0.1 ? "PASS" : "FAIL") \($0.0)" }
                log("RaiseToListenProbe:\n" + lines.joined(separator: "\n"))
                let passed = results.allSatisfy(\.1)
                let alert = UIAlertController(
                    title: "Raise to Listen \(passed ? "PASS" : "FAIL")",
                    message: lines.joined(separator: "\n"),
                    preferredStyle: .alert,
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                var presenter = window.rootViewController
                while let presented = presenter?.presentedViewController {
                    presenter = presented
                }
                presenter?.present(alert, animated: true)
            }
        }

        private static func checkActivator(into results: inout [(String, Bool)]) async {
            let monitor = DeviceProximityMonitor.shared
            var activations = 0
            var deactivations = 0
            let activator = RaiseToListenActivator(
                shouldActivate: { true },
                activate: { activations += 1 },
                deactivate: { deactivations += 1 },
            )
            activator.isEnabled = true
            results.append(("gesture source: \(activator.gestureSourceName ?? "none")", true))

            monitor.simulate(false)
            activator.raiseDetected()
            try? await Task.sleep(for: .milliseconds(300))
            monitor.simulate(true)
            results.append(("ear within 1 s activates", activations == 1 && activator.isActivated))
            monitor.simulate(false)
            results.append(("leaving the ear deactivates", deactivations == 1 && !activator.isActivated))

            activator.raiseDetected()
            try? await Task.sleep(for: .milliseconds(1200))
            monitor.simulate(true)
            results.append(("ear after 1 s does nothing", activations == 1))
            monitor.simulate(false)

            monitor.simulate(true)
            activator.activateBasedOnProximity()
            results.append(("phone at the ear activates at once", activations == 2 && activator.isActivated))
            activator.applicationResignedActive()
            results.append(("background under 1 s undoes it", !activator.isActivated && deactivations >= 2))
            monitor.simulate(false)

            activator.isEnabled = false
            activator.raiseDetected()
            monitor.simulate(true)
            results.append(("disabled ignores raises", activations == 2))
            monitor.simulate(false)
        }

        private static func checkVoicePlayback(into results: inout [(String, Bool)]) async {
            guard RaiseToListenSettings.isEnabled, let url = try? makeTone() else {
                results.append(("voice tone (Raise to Listen on)", false))
                return
            }
            let monitor = DeviceProximityMonitor.shared
            let session = AVAudioSession.sharedInstance()
            monitor.simulate(false)
            let item = Media.NowPlaying(accountID: nil, chatID: -1, messageID: 1)
            Media.shared.toggle(with: url.path, duration: 20, item: item)
            try? await Task.sleep(for: .seconds(1))
            results.append(("voice note plays on the speaker", Media.shared.isPlaying && session.category == .playback))
            monitor.simulate(true)
            try? await Task.sleep(for: .milliseconds(600))
            results.append((
                "at the ear: earpiece route, playing",
                Media.shared.isPlaying && session.category == .playAndRecord && session.mode == .default,
            ))
            results.append(gainResult("at the ear during playback", Media.shared.measuredMessageGain, expected: 5))
            monitor.simulate(false)
            try? await Task.sleep(for: .milliseconds(300))
            results.append(("away from the ear: paused", !Media.shared.isPlaying))
            Media.shared.togglePlayback()
            try? await Task.sleep(for: .milliseconds(600))
            results.append(("resumed on the speaker", Media.shared.isPlaying && session.category == .playback))
            results.append(gainResult("resumed on the speaker", Media.shared.measuredMessageGain, expected: 0))
            Media.shared.close()

            monitor.simulate(true)
            Media.shared.toggle(with: url.path, duration: 20, item: Media.NowPlaying(
                accountID: nil,
                chatID: -1,
                messageID: 2,
            ))
            try? await Task.sleep(for: .seconds(1))
            results.append((
                "started at the ear: earpiece route, playing",
                Media.shared.isPlaying && session.category == .playAndRecord,
            ))
            results.append(gainResult("started at the ear", Media.shared.measuredMessageGain, expected: 12))
            Media.shared.close()
            monitor.simulate(false)
        }

        /// A round video's proximity control on its own player, as its bubble runs it after taking the playback.
        private static func checkVideoNotePlayback(into results: inout [(String, Bool)]) async {
            guard RaiseToListenSettings.isEnabled, let url = try? makeTone() else {
                results.append(("round video tone (Raise to Listen on)", false))
                return
            }
            let monitor = DeviceProximityMonitor.shared
            let session = AVAudioSession.sharedInstance()
            let player = LocalMediaPlayer()
            let control = VideoNoteProximityControl()
            monitor.simulate(false)
            player.load(url: url, autoplay: false)
            Media.shared.beginExclusivePlayback()
            control.begin(player: player)
            player.play()
            try? await Task.sleep(for: .seconds(1))
            results.append((
                "round video plays on the speaker",
                player.isPlaybackRequested && session.category == .playback && control.isActive,
            ))
            let before = player.currentTime
            monitor.simulate(true)
            try? await Task.sleep(for: .milliseconds(600))
            results.append((
                "round video at the ear: earpiece, restarted (\(String(format: "%.2f", before)) s -> "
                    + "\(String(format: "%.2f", player.currentTime)) s)",
                player.isPlaybackRequested && session.category == .playAndRecord && player.currentTime < before,
            ))
            results.append(gainResult("round video at the ear", player.measuredMessageGain, expected: 5))
            monitor.simulate(false)
            try? await Task.sleep(for: .milliseconds(300))
            results.append(("round video away from the ear: paused", !player.isPlaybackRequested))
            control.end()
            player.stop()
            Media.shared.close()
        }

        private static func gainResult(_ name: String, _ measured: Float?, expected: Float) -> (String, Bool) {
            let value = measured ?? (expected == 0 ? 0 : .nan)
            return (
                "\(name): \(String(format: "%.2f", value)) dB (expected \(Int(expected)))",
                abs(value - expected) < 0.5,
            )
        }

        /// Twenty seconds of a quiet 440 Hz tone.
        private static func makeTone() throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("raise-to-listen-probe.wav")
            if FileManager.default.fileExists(atPath: url.path) { return url }
            let sampleRate = 8000.0
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let frames = AVAudioFrameCount(sampleRate * 20)
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
