// Media.swift

import MediaPlayer
import MobileVLCKit
import Observation
import Combine
import SwiftUI

@Observable
final class Media {
    static let shared = Media()
    
    var savedMediaPath = ""
    var isPlaying = false
    var currentTime: Int32 = 0
    
    private var duration = 0
    private var title = ""
    
    private let player = VLCMediaPlayer()
    private let audioSession: AVAudioSession = .sharedInstance()
    private let nowPlayingCenter: MPNowPlayingInfoCenter = .default()
    private let commandCenter: MPRemoteCommandCenter = .shared()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setPublishers()
        setCommandCenterControls()
    }
    
    func stop() {
        withAnimation {
            isPlaying = false
            currentTime = 0
            savedMediaPath = ""
            player.media = nil
            player.stop()
            nowPlayingCenter.nowPlayingInfo = nil
        }
    }
    
    func onChatOpen(title: String) {
        self.title = title
    }
    
    func onChatDismiss() {
        player.stop()
    }
    
    func seekForward() {
        player.jumpForward(5)
    }
    
    func seekBackward() {
        player.jumpBackward(5)
    }
    
    func toggle(with path: String, duration: Int) {
        self.duration = duration
        withAnimation {
            if savedMediaPath.isEmpty || savedMediaPath != path {
                savedMediaPath = path
                stop()
                savedMediaPath = path
                player.media = VLCMedia(path: path)
                play()
            } else {
                toggle()
            }
        }
    }
    
    private func setPublishers() {
        player
            .publisher(for: \.time, options: [.new])
            .sink { [weak self] time in
                guard let self else { return }
                currentTime = time.intValue / 1000
                changeCurrentTime()
            }
            .store(in: &cancellables)
        
        player
            .publisher(for: \.state, options: [.new])
            .sink { [weak self] state in
                guard let self else { return }
                guard case .ended = state else { return }
                stop()
            }
            .store(in: &cancellables)
    }
    
    private func setCommandCenterControls() {
        commandCenter.skipBackwardCommand.preferredIntervals = [5.0]
        commandCenter.skipForwardCommand.preferredIntervals = [5.0]
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !savedMediaPath.isEmpty, player.media != nil, !isPlaying {
                play()
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !savedMediaPath.isEmpty, player.media != nil, isPlaying {
                pause()
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !savedMediaPath.isEmpty, player.media != nil {
                toggle()
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self else { return .commandFailed }
            if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
                seekTo(positionEvent.positionTime)
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !savedMediaPath.isEmpty, player.media != nil {
                seekForward()
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !savedMediaPath.isEmpty, player.media != nil {
                seekBackward()
                return .success
            }
            return .commandFailed
        }
    }
    
    func setAudioSessionRecord() {
        do {
            try audioSession.setActive(false)
            try audioSession.setCategory(.playAndRecord, mode: .default, policy: .default, options: [
                .allowAirPlay,
                .allowBluetooth,
                .allowBluetoothA2DP,
                .defaultToSpeaker,
                .overrideMutedMicrophoneInterruption
            ])
            try audioSession.setActive(true)
        } catch {
            log("Error setting audioSessionRecord: \(error)")
        }
    }
    
    private func toggle() {
        withAnimation {
            if isPlaying {
                pause()
            } else {
                play()
            }
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
                .allowBluetooth,
                .allowBluetoothA2DP
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
        // swiftlint:disable:next compiler_protocol_init
        let number = NSNumber(floatLiteral: timeInterval * 1000)
        let time = VLCTime(number: number)
        player.time = time
    }
    
    private func setNowPlaying() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = title
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentTime)
        info[MPMediaItemPropertyPlaybackDuration] = Double(duration)
        nowPlayingCenter.nowPlayingInfo = info
    }
}
