// ChatViewModel+CommandCenter.swift

import MediaPlayer

extension ChatViewModel {
    // swiftlint:disable:next function_body_length
    func setCommandCenterControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.skipBackwardCommand.preferredIntervals = [5.0]
        commandCenter.skipForwardCommand.preferredIntervals = [5.0]
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !savedMediaPath.isEmpty, mediaPlayer.media != nil, !isPlaying {
                mediaPlay()
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !savedMediaPath.isEmpty, mediaPlayer.media != nil, isPlaying {
                mediaPause()
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !savedMediaPath.isEmpty, mediaPlayer.media != nil {
                mediaToggle()
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self else { return .commandFailed }
            if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
                timeSliderValue = positionEvent.positionTime
                mediaSeekTo()
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !savedMediaPath.isEmpty, mediaPlayer.media != nil {
                mediaSeekForward()
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
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
