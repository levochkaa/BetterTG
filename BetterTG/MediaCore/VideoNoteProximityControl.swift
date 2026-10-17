// VideoNoteProximityControl.swift

import Foundation

// MARK: - VideoNoteProximityControl

/// SharedMediaPlayer's `controlPlaybackWithProximity` for an instant video, which MediaManager sets while Raise to
/// Listen is on: a round video playing with sound moves to the earpiece at the ear, from its start if it had barely
/// begun, and pauses away from it. MediaPlayerAudioRenderer's message equalizer makes it louder at the ear: 12 dB when
/// playback starts there, 5 dB when the phone comes up during playback, 0 dB on the speaker.
@MainActor final class VideoNoteProximityControl {
    // MARK: Internal

    private(set) var isAtEar = false

    // MARK: Private

    private var subscription: UUID?
    private weak var player: LocalMediaPlayer?

    var isActive: Bool {
        subscription != nil
    }

    func begin(player: LocalMediaPlayer) {
        end()
        guard RaiseToListenSettings.isEnabled else { return }
        self.player = player
        let monitor = DeviceProximityMonitor.shared
        isAtEar = monitor.currentValue
        if isAtEar { Media.shared.setMessageOutput(earpiece: true) }
        player.setMessageGain(decibels: isAtEar ? 12 : 0)
        subscription = monitor.add { [weak self] value in self?.proximityChanged(value) }
    }

    func end() {
        guard let subscription else { return }
        self.subscription = nil
        DeviceProximityMonitor.shared.remove(subscription)
        player?.setMessageGain(decibels: 0)
        player = nil
        isAtEar = false
    }

    private func proximityChanged(_ value: Bool) {
        guard isAtEar != value, let player else { return }
        isAtEar = value
        player.setMessageGain(decibels: value ? 5 : 0)
        if value {
            Media.shared.setMessageOutput(earpiece: true)
            if player.currentTime < 1.5 {
                player.play(from: 0)
            } else {
                player.play()
            }
        } else {
            player.pause()
        }
    }
}
