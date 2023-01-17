// Chat+commandCenter.swift

import SwiftUI
import MediaPlayer

extension ChatViewModel {
    func setCommandCenterControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [unowned self] _ in
            if !savedMediaPath.isEmpty, mediaPlayer.media != nil, !isPlaying {
                mediaPlay()
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.pauseCommand.addTarget { [unowned self] _ in
            if !savedMediaPath.isEmpty, mediaPlayer.media != nil, isPlaying {
                mediaPause()
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [unowned self] _ in
            if !savedMediaPath.isEmpty, mediaPlayer.media != nil {
                mediaToggle()
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [unowned self] event in
            if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
                timeSliderValue = positionEvent.positionTime
                mediaSeekTo()
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.skipForwardCommand.addTarget { [unowned self] _ in
            if !savedMediaPath.isEmpty, mediaPlayer.media != nil {
                mediaSeekForward()
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.skipBackwardCommand.addTarget { [unowned self] _ in
            if !savedMediaPath.isEmpty, mediaPlayer.media != nil {
                mediaSeekBackward()
                return .success
            }
            return .commandFailed
        }
    }
    
    func changeCurrentTime() {
        MPNowPlayingInfoCenter.default()
            .nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentTime)
    }
    
    func setNowPlaying() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = customChat.user.firstName
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentTime)
        info[MPMediaItemPropertyPlaybackDuration] = Double(duration)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
