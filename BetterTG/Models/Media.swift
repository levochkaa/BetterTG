// Media.swift

import AVFoundation
import Combine
import MediaPlayer

final class Media: ObservableObject {
    // MARK: Internal

    /// The message whose audio is loaded, for Telegram's playback header (MediaNavigationAccessoryHeaderNode).
    struct NowPlaying: Equatable {
        let accountID: UUID?
        let chatID: Int64
        let messageID: Int64
    }

    static let shared = Media()
    /// Telegram's playback speeds, cycled by the header's rate button (rateButtonPressed).
    static let playbackRates: [Float] = [1, 1.5, 2]

    private static let playbackRateKey = "BetterTG.voicePlaybackRate"

    @Published var savedMediaPath = ""
    @Published var isPlaying = false
    @Published var currentTime: Int32 = 0
    /// The position with its fraction, which a voice bubble's waveform follows; currentTime keeps whole seconds.
    @Published private(set) var playbackPosition: TimeInterval = 0
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var playbackRate: Float = {
        let stored = UserDefaults.standard.float(forKey: playbackRateKey)
        return playbackRates.contains(stored) ? stored : 1
    }()

    // MARK: Private

    private var duration = 0
    private var title = ""

    private let player = LocalMediaPlayer()
    private let audioSession = AVAudioSession.sharedInstance()
    private let nowPlayingCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var cancellables = Set<AnyCancellable>()
    /// Media activated the spoken-audio session for its own playback, so it gives it back when playback ends.
    private var ownsPlaybackSession = false

    var playbackDuration: TimeInterval {
        TimeInterval(duration)
    }

    private init() {
        setPublishers()
        setCommandCenterControls()
    }

    func stop() {
        isPlaying = false
        currentTime = 0
        playbackPosition = 0
        savedMediaPath = ""
        nowPlaying = nil
        player.stop()
        nowPlayingCenter.nowPlayingInfo = nil
    }

    /// The header's close button: stops playback and gives the audio session back.
    func close() {
        stop()
        releasePlaybackSession()
    }

    func togglePlayback() {
        guard !savedMediaPath.isEmpty, player.hasItem else { return }
        toggle()
    }

    /// 1X → 1.5X → 2X → 1X, kept for later notes as Telegram keeps its voice playback rate.
    func cyclePlaybackRate() {
        let index = Self.playbackRates.firstIndex(of: playbackRate) ?? 0
        playbackRate = Self.playbackRates[(index + 1) % Self.playbackRates.count]
        UserDefaults.standard.set(playbackRate, forKey: Self.playbackRateKey)
        player.setRate(playbackRate)
        nowPlayingCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0
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

    func toggle(with path: String, duration: Int, item: NowPlaying? = nil) {
        self.duration = duration
        if savedMediaPath.isEmpty || savedMediaPath != path {
            stop()
            savedMediaPath = path
            nowPlaying = item
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

    /// Loads a voice note paused at a position, so scrubbing a note that isn't playing doesn't start it.
    func prepare(with path: String, duration: Int, at time: TimeInterval, item: NowPlaying? = nil) {
        stop()
        self.duration = duration
        savedMediaPath = path
        nowPlaying = item
        playbackPosition = max(0, time)
        player.load(
            url: URL(fileURLWithPath: path),
            autoplay: false,
            prefersFFmpegAudioFallback: true,
            initialTime: max(0, time),
        )
    }

    func setAudioSessionRecord() {
        ownsPlaybackSession = false
        // A failed deactivation (a player still holds the session) must not skip the record category.
        try? audioSession.setActive(false)
        do {
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

    private func setPublishers() {
        player.timePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self else { return }
                currentTime = Int32(time)
                playbackPosition = time
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
                    releasePlaybackSession()
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
            ownsPlaybackSession = true
        } catch {
            log("Error setting audioSessionPlayback: \(error)")
        }
    }

    /// When a voice note finishes, other apps' audio (music, podcasts) resumes, as after Telegram's playback.
    private func releasePlaybackSession() {
        guard ownsPlaybackSession else { return }
        ownsPlaybackSession = false
        guard audioSession.category == .playback, audioSession.mode == .spokenAudio else { return }
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func play() {
        setAudioSessionPlayback()
        player.setRate(playbackRate)
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
