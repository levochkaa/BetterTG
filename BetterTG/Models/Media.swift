// Media.swift

import AVFoundation
import Combine
import MediaPlayer

final class Media: ObservableObject {
    // MARK: Internal

    static let shared = Media()

    @Published var savedMediaPath = ""
    @Published var isPlaying = false
    @Published var currentTime: Int32 = 0

    // MARK: Private

    private var duration = 0
    private var title = ""

    private let player = VLCMediaPlayer()
    private let audioSession = AVAudioSession.sharedInstance()
    private let nowPlayingCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setPublishers()
        setCommandCenterControls()
    }

    func stop() {
        isPlaying = false
        currentTime = 0
        savedMediaPath = ""
        player.stop()
        nowPlayingCenter.nowPlayingInfo = nil
    }

    func beginExclusivePlayback() {
        stop()
        setAudioSessionPlayback()
    }

    func onChatOpen(title: String) {
        self.title = title
    }

    func onChatDismiss() {
        stop()
    }

    func seekForward() {
        player.jump(by: 5)
    }

    func seekBackward() {
        player.jump(by: -5)
    }

    func seek(to timeInterval: TimeInterval) {
        seekTo(max(0, min(TimeInterval(duration), timeInterval)))
    }

    func toggle(with path: String, duration: Int) {
        self.duration = duration
        if savedMediaPath.isEmpty || savedMediaPath != path {
            stop()
            savedMediaPath = path
            player.load(
                url: URL(fileURLWithPath: path),
                autoplay: false,
                prefersFFmpegAudioFallback: true,
            )
            play()
        } else {
            toggle()
        }
    }

    func setAudioSessionRecord() {
        do {
            try audioSession.setActive(false)
            try audioSession.setCategory(.playAndRecord, mode: .default, policy: .default, options: [
                .allowAirPlay,
                .allowBluetoothHFP,
                .allowBluetoothA2DP,
                .defaultToSpeaker,
                .overrideMutedMicrophoneInterruption,
            ])
            try audioSession.setActive(true)
        } catch {
            log("Error setting audioSessionRecord: \(error)")
        }
    }

    func endAudioSessionRecord() {
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            log("Error ending audioSessionRecord: \(error)")
        }
    }

    // MARK: Private

    private var duration = 0
    private var title = ""

    private let player = LocalMediaPlayer()
    private let audioSession = AVAudioSession.sharedInstance()
    private let nowPlayingCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var cancellables = Set<AnyCancellable>()

    private func setPublishers() {
        player.timePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self else { return }
                currentTime = Int32(time)
                changeCurrentTime()
            }
            .store(in: &cancellables)

        player.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .playing:
                    isPlaying = true
                case .ended, .failed:
                    stop()
                case .buffering, .idle, .paused, .preparing:
                    isPlaying = false
                }
            }
            .store(in: &cancellables)
    }

    private func setCommandCenterControls() {
        commandCenter.skipBackwardCommand.preferredIntervals = [5.0]
        commandCenter.skipForwardCommand.preferredIntervals = [5.0]

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !savedMediaPath.isEmpty, player.hasItem, !isPlaying {
                DispatchQueue.main.async { self.play() }
                return .success
            }
            return .commandFailed
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !savedMediaPath.isEmpty, player.hasItem, isPlaying {
                DispatchQueue.main.async { self.pause() }
                return .success
            }
            return .commandFailed
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !savedMediaPath.isEmpty, player.hasItem {
                DispatchQueue.main.async { self.toggle() }
                return .success
            }
            return .commandFailed
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self else { return .commandFailed }
            if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
                DispatchQueue.main.async { self.seekTo(positionEvent.positionTime) }
                return .success
            }
            return .commandFailed
        }

        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !savedMediaPath.isEmpty, player.hasItem {
                DispatchQueue.main.async { self.seekForward() }
                return .success
            }
            return .commandFailed
        }

        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !savedMediaPath.isEmpty, player.hasItem {
                DispatchQueue.main.async { self.seekBackward() }
                return .success
            }
            return .commandFailed
        }
    }

    private func toggle() {
        if player.isPlaybackRequested {
            pause()
        } else {
            play()
        }
    }

    private func pause() {
        player.pause()
        isPlaying = false
    }

    private func setAudioSessionPlayback() {
        do {
            try audioSession.setActive(false)
            try audioSession.setCategory(.playback, mode: .spokenAudio, policy: .default, options: [
                .allowBluetoothHFP,
                .allowBluetoothA2DP,
            ])
            try audioSession.setActive(true)
        } catch {
            log("Error setting audioSessionPlayback: \(error)")
        }
    }

    private func play() {
        setAudioSessionPlayback()
        player.play()
        isPlaying = true
        setNowPlaying()
    }

    private func changeCurrentTime() {
        nowPlayingCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentTime)
    }

    private func seekTo(_ timeInterval: TimeInterval) {
        player.seek(to: timeInterval)
    }

    private func setNowPlaying() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = title
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentTime)
        info[MPMediaItemPropertyPlaybackDuration] = Double(duration)
        nowPlayingCenter.nowPlayingInfo = info
    }
}
