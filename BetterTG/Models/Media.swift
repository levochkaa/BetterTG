// Media.swift

import AVFoundation
import Combine
import MediaPlayer
import TDLibKit
import UIKit

final class Media: ObservableObject {
    // MARK: Internal

    /// The message whose audio is loaded, for Telegram's playback header (MediaNavigationAccessoryHeaderNode).
    struct NowPlaying: Equatable {
        let accountID: UUID?
        let chatID: Int64
        let messageID: Int64
        /// A music track, which plays on through its chat's tracks (PeerMessagesMediaPlaylist's `.music`).
        var isMusic = false
        /// Audio that isn't a message's own voice note or track, such as a poll's, played as openChatMessage's
        /// standalone playlist (`.recentActions`) with the `.file` player type: alone, without Raise to Listen, its
        /// header opening the message.
        var isFile = false
    }

    /// The header text the note's chat gave it, so the header can name it over the chat list and in other chats.
    struct NowPlayingDisplay: Equatable {
        let item: NowPlaying
        let title: String
        let subtitle: String
        /// Telegram shows the rate button for voice notes and for music over ten minutes.
        var showsRate = true
        /// A music track's lock-screen cover (SharedMediaPlaybackAlbumArt).
        var artwork: Artwork?
    }

    /// Where a track's lock-screen cover comes from, in playerAlbumArt's order: the cover embedded in the downloaded
    /// file, read with the track's MIME type, then TDLib's covers in `coverFileIDs`.
    struct Artwork: Equatable {
        let mimeType: String
        let coverFileIDs: [Int]
    }

    static let shared = Media()
    /// Telegram's playback speeds, cycled by the header's rate button (rateButtonPressed).
    static let playbackRates: [Float] = [1, 1.5, 2]

    private static let playbackRateKey = "BetterTG.voicePlaybackRate"

    /// A video note, Live Photo or play-once media took the audio. A gallery video in Picture in Picture pauses for
    /// it as for a voice note, since Telegram's media manager keeps one playing source.
    let exclusivePlaybackBegan = PassthroughSubject<Void, Never>()

    @Published var savedMediaPath = ""
    @Published var isPlaying = false
    @Published var currentTime: Int32 = 0
    /// The position with its fraction, which a voice bubble's waveform follows; currentTime keeps whole seconds.
    @Published private(set) var playbackPosition: TimeInterval = 0
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var nowPlayingDisplay: NowPlayingDisplay?
    /// A note that played to its end, so its chat can continue with the next one (Telegram's voice playlist).
    let playbackFinished = PassthroughSubject<NowPlaying, Never>()
    @Published private(set) var playbackRate: Float = {
        let stored = UserDefaults.standard.float(forKey: playbackRateKey)
        return playbackRates.contains(stored) ? stored : 1
    }()

    /// The music playlist's order and looping (MusicPlaybackSettings), which the music player changes.
    @Published private(set) var musicSettings = MusicPlaybackSettings.load()
    /// The loaded track's album art once it's read, for the music player (playerAlbumArt).
    @Published private(set) var albumArtImage: UIImage?

    // MARK: Private

    private var duration = 0
    private var title = ""
    /// The title of the chat the loaded audio came from, for the lock screen once that chat is closed.
    private var loadedTitle = ""
    /// The loaded audio played at least once; a note only positioned by scrubbing has not.
    private var hasPlayedLoadedItem = false
    /// The loaded track's album art for the lock screen (MediaManager's globalControlsArtwork).
    private var albumArtwork: MPMediaItemArtwork?
    private var albumArtworkTask: Task<Void, Never>?

    private let player = LocalMediaPlayer()
    private let audioSession = AVAudioSession.sharedInstance()
    private let nowPlayingCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var cancellables = Set<AnyCancellable>()
    /// Media activated the spoken-audio session for its own playback, so it gives it back when playback ends.
    private var ownsPlaybackSession = false
    /// The loaded voice note follows the proximity sensor (SharedMediaPlayer's controlPlaybackWithProximity).
    private var proximitySubscription: UUID?
    /// The phone is at the ear, so the voice note plays from the earpiece (forceAudioToSpeaker off).
    private var playsThroughEarpiece = false

    var playbackDuration: TimeInterval {
        TimeInterval(duration)
    }

    #if DEBUG
        /// The message equalizer's last measured gain on the shared player, in decibels.
        var measuredMessageGain: Float? {
            player.measuredMessageGain
        }
    #endif

    private init() {
        setPublishers()
        setCommandCenterControls()
        // A note of another account stops: its chat, file and header belong to the account that was left.
        TDLib.shared
            .activeClientChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in
                guard let self, let item = nowPlaying, item.accountID != source.accountID else { return }
                close()
            }
            .store(in: &cancellables)
    }

    /// playerAlbumArt's full size: the cover embedded in the downloaded file, then TDLib's external album covers
    /// (ExternalMusicAlbumArtResource) and the sender's cover thumbnail.
    private static func albumArt(path: String, sources: Artwork, client: TDLibClient) async -> UIImage? {
        if !path.isEmpty {
            let asset = AVURLAsset(
                url: URL(fileURLWithPath: path),
                options: sources.mimeType.isEmpty ? nil : [AVURLAssetOverrideMIMETypeKey: sources.mimeType],
            )
            for item in await (try? asset.load(.metadata)) ?? [] where item.commonKey == .commonKeyArtwork {
                if let data = try? await item.load(.dataValue), let image = UIImage(data: data) { return image }
            }
        }
        for fileID in sources.coverFileIDs {
            guard !Task.isCancelled else { return nil }
            guard let file = try? await client.downloadFile(
                fileId: fileID,
                limit: 0,
                offset: 0,
                priority: 1,
                synchronous: true,
            ), file.local.isDownloadingCompleted,
            let image = UIImage(contentsOfFile: file.local.path) else { continue }
            return image
        }
        return nil
    }

    /// The system may ask for the artwork off the main thread, so the handler only returns the loaded image.
    private static func mediaArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    func stop() {
        isPlaying = false
        currentTime = 0
        playbackPosition = 0
        savedMediaPath = ""
        nowPlaying = nil
        nowPlayingDisplay = nil
        hasPlayedLoadedItem = false
        albumArtworkTask?.cancel()
        albumArtworkTask = nil
        albumArtwork = nil
        albumArtImage = nil
        player.stop()
        nowPlayingCenter.nowPlayingInfo = nil
        endProximityControl()
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
        exclusivePlaybackBegan.send()
    }

    /// SharedMediaPlayer's setForceAudioToSpeaker for a round video under proximity control: the shared session moves
    /// to the earpiece at the ear. Away from the ear the video pauses, and the next play from its bubble returns the
    /// session to the speaker through beginExclusivePlayback.
    func setMessageOutput(earpiece: Bool) {
        guard playsThroughEarpiece != earpiece else { return }
        playsThroughEarpiece = earpiece
        setAudioSessionPlayback()
    }

    func onChatOpen(title: String) {
        self.title = title
    }

    /// Leaving a chat stops its audio, except a chat's voice note that has played: Telegram keeps it going, with its
    /// playback header over the chat list (ChatListControllerNode's media header panel).
    func onChatDismiss() {
        guard nowPlaying?.accountID == nil || !hasPlayedLoadedItem else { return }
        stop()
    }

    /// Records the header text the first chat view that loaded the note gave it; later views keep it, so two views
    /// of one chat never trade updates.
    func setDisplay(_ display: NowPlayingDisplay) {
        guard display.item == nowPlaying, nowPlayingDisplay?.item != display.item else { return }
        nowPlayingDisplay = display
        guard display.item.isMusic else { return }
        // MediaManager names music on the lock screen by its title and performer, then adds the album art.
        if nowPlayingCenter.nowPlayingInfo != nil { setNowPlaying() }
        loadAlbumArtwork(for: display)
    }

    /// SharedMediaPlayer.control(.next): the playlist's next track in the saved order, from the lock screen, the
    /// header or the music player.
    func playNextTrack() {
        guard nowPlaying?.isMusic == true else { return }
        Task { @MainActor in VoicePlaylistContinuation.shared.controlMusic(.next) }
    }

    /// SharedMediaPlayer.control(.previous): past 5 s into a track longer than 5 s it starts the track again;
    /// otherwise the playlist's previous track plays.
    func playPreviousTrack() {
        guard nowPlaying?.isMusic == true else { return }
        if duration > 5, playbackPosition > 5 {
            seekTo(0)
        } else {
            Task { @MainActor in VoicePlaylistContinuation.shared.controlMusic(.previous) }
        }
    }

    /// MediaNavigationAccessoryHeaderNode's swipe, which brings in the neighbouring track the header shows beside the
    /// current one: the playlist's next track from the left, its previous one from the right. A shuffled playlist has
    /// no neighbours to swipe to.
    func swipeTrack(toNext: Bool) {
        guard nowPlaying?.isMusic == true, musicSettings.order != .random else { return }
        if toNext {
            playNextTrack()
        } else {
            playPreviousTrack()
        }
    }

    /// Plays the loaded track again from its start, as SharedMediaPlayer does when the playlist lands on it again.
    func restartCurrentTrack() {
        guard !savedMediaPath.isEmpty, player.hasItem else { return }
        seekTo(0)
        if !player.isPlaybackRequested { play() }
    }

    /// Saves the music playlist's order and looping (updateMusicPlaybackSettingsInteractively).
    func updateMusicSettings(_ settings: MusicPlaybackSettings) {
        guard settings != musicSettings else { return }
        musicSettings = settings
        settings.save()
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
            loadedTitle = title
            player.load(
                url: URL(fileURLWithPath: path),
                autoplay: false,
                prefersFFmpegAudioFallback: true,
            )
            beginProximityControl(for: item)
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
        loadedTitle = title
        playbackPosition = max(0, time)
        player.load(
            url: URL(fileURLWithPath: path),
            autoplay: false,
            prefersFFmpegAudioFallback: true,
            initialTime: max(0, time),
        )
        beginProximityControl(for: item)
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
        $nowPlaying
            .map { $0?.isMusic == true }
            .removeDuplicates()
            .sink { [weak self] isMusic in self?.updateTrackCommands(isMusic: isMusic) }
            .store(in: &cancellables)

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
                case .ended:
                    // SharedMediaPlayer's action at the end: a track looping on itself starts over.
                    if nowPlaying?.isMusic == true, musicSettings.looping == .item {
                        player.play()
                        return
                    }
                    let finished = nowPlaying
                    stop()
                    releasePlaybackSession()
                    if let finished { playbackFinished.send(finished) }
                case .failed:
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

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, nowPlaying?.isMusic == true else { return .commandFailed }
            DispatchQueue.main.async { self.playNextTrack() }
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, nowPlaying?.isMusic == true else { return .commandFailed }
            DispatchQueue.main.async { self.playPreviousTrack() }
            return .success
        }
    }

    /// MediaManager's global controls: music gets the previous and next track, which the lock screen shows in place
    /// of the 5-second skips a voice note keeps.
    private func updateTrackCommands(isMusic: Bool) {
        commandCenter.nextTrackCommand.isEnabled = isMusic
        commandCenter.previousTrackCommand.isEnabled = isMusic
        commandCenter.skipForwardCommand.isEnabled = !isMusic
        commandCenter.skipBackwardCommand.isEnabled = !isMusic
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
        nowPlayingCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentTime)
        nowPlayingCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
    }

    private func setAudioSessionPlayback() {
        do {
            if playsThroughEarpiece {
                // ManagedAudioSession's playWithPossiblePortOverride in its system output: play-and-record without
                // the speaker override routes to the earpiece. The category changes while the note keeps playing.
                try audioSession.setCategory(.playAndRecord, mode: .default, policy: .default, options: [
                    .allowBluetoothA2DP,
                ])
                try audioSession.overrideOutputAudioPort(.none)
            } else {
                try audioSession.setActive(false)
                try audioSession.setCategory(.playback, mode: .spokenAudio, policy: .default, options: [
                    .allowBluetoothHFP,
                    .allowBluetoothA2DP,
                ])
            }
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
        let isSpeaker = audioSession.category == .playback && audioSession.mode == .spokenAudio
        let isEarpiece = audioSession.category == .playAndRecord && audioSession.mode == .default
        guard isSpeaker || isEarpiece else { return }
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// SharedMediaPlayer with controlPlaybackWithProximity, which MediaManager sets for voice notes while Raise to
    /// Listen is on: the note starts on the earpiece if the phone is already at the ear, 12 dB louder as
    /// MediaPlayerAudioRenderer's message equalizer starts there.
    private func beginProximityControl(for item: NowPlaying?) {
        player.setMessageGain(decibels: 0)
        guard let item, !item.isMusic, !item.isFile, RaiseToListenSettings.isEnabled else { return }
        MainActor.assumeIsolated {
            let monitor = DeviceProximityMonitor.shared
            playsThroughEarpiece = monitor.currentValue
            proximitySubscription = monitor.add { [weak self] value in self?.proximityChanged(value) }
        }
        player.setMessageGain(decibels: playsThroughEarpiece ? 12 : 0)
    }

    private func endProximityControl() {
        playsThroughEarpiece = false
        player.setMessageGain(decibels: 0)
        guard let proximitySubscription else { return }
        self.proximitySubscription = nil
        MainActor.assumeIsolated { DeviceProximityMonitor.shared.remove(proximitySubscription) }
    }

    /// At the ear the note plays from the earpiece, 5 dB louder (the equalizer's gain when the output changes during
    /// playback), from its start if it had barely begun; away from the ear it pauses, and plays from the speaker at
    /// 0 dB again when resumed.
    private func proximityChanged(_ value: Bool) {
        guard playsThroughEarpiece != value, player.hasItem else { return }
        playsThroughEarpiece = value
        player.setMessageGain(decibels: value ? 5 : 0)
        if value {
            if playbackPosition < 1.5 { seekTo(0) }
            play()
        } else {
            pause()
        }
    }

    private func play() {
        setAudioSessionPlayback()
        player.setRate(playbackRate)
        player.play()
        isPlaying = true
        hasPlayedLoadedItem = true
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
        if let display = nowPlayingDisplay, display.item == nowPlaying, display.item.isMusic {
            // MediaManager's music info: the track's title and performer with its album art.
            info[MPMediaItemPropertyTitle] = display.title
            info[MPMediaItemPropertyArtist] = display.subtitle
            if let albumArtwork { info[MPMediaItemPropertyArtwork] = albumArtwork }
        } else {
            info[MPMediaItemPropertyTitle] = loadedTitle
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentTime)
        info[MPMediaItemPropertyPlaybackDuration] = Double(duration)
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0
        nowPlayingCenter.nowPlayingInfo = info
    }

    /// MediaManager's globalControlsArtwork: the track's album art joins the lock screen once it's loaded.
    private func loadAlbumArtwork(for display: NowPlayingDisplay) {
        albumArtworkTask?.cancel()
        albumArtworkTask = nil
        guard let sources = display.artwork, let accountID = display.item.accountID,
              TDLib.shared.activeAccountID == accountID else { return }
        let client = TDLib.shared.activeClient
        let path = savedMediaPath
        let item = display.item
        albumArtworkTask = Task { @MainActor [weak self] in
            let image = await Self.albumArt(path: path, sources: sources, client: client)
            guard !Task.isCancelled, let self, nowPlaying == item, let image else { return }
            let artwork = Self.mediaArtwork(image)
            albumArtwork = artwork
            albumArtImage = image
            nowPlayingCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork] = artwork
        }
    }
}
