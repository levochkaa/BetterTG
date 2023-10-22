// ChatViewModel+Media.swift

import MobileVLCKit
import AVKit
import AVFoundation
import MediaPlayer
import TDLibKit

extension ChatViewModel {
    func setMediaPublishers() {
        setCommandCenterControls()
        
        mediaPlayer
            .publisher(for: \.time, options: [.new])
            .sink { [weak self] time in
                guard let self else { return }
                currentTime = time.intValue / 1000
                changeCurrentTime()
            }
            .store(in: &cancellables)
        
        mediaPlayer
            .publisher(for: \.state, options: [.new])
            .sink { [weak self] state in
                guard let self, case .ended = state else { return }
                mediaStop()
            }
            .store(in: &cancellables)
    }
    
    @MainActor func mediaStartRecordingVoice() async {
        setAudioSessionRecord()
        mediaStop()
        
        let granted = await AVAudioApplication.requestRecordPermission()
        if granted {
            log("Access to Microphone for Voice messages is granted")
        } else {
            log("Access to Microphone for Voice messages is not granted")
            self.errorMessage = """
            Access to Microphone isn't granted.
            Go to Settings -> BetterTG -> Microphone
            if you want to record Voice
            """
            self.errorShown = true
        }
        
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
        ]
        
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).wav")
        savedVoiceNoteUrl = url
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder.isMeteringEnabled = true
            audioRecorder.prepareToRecord()
            audioRecorder.record()
            withAnimation {
                recordingVoiceNote = true
            }
            await tdSendChatAction(.chatActionRecordingVoiceNote)
        } catch {
            log("Error creating AudioRecorder: \(error)")
        }
    }
    
    func mediaStopRecordingVoice(duration: Int, wave: [Float]) {
        audioRecorder.stop()
        withAnimation {
            recordingVoiceNote = false
        }
        Task {
            await tdSendChatAction(.chatActionCancel)
        }
        
        let intWave: [Int] = wave.compactMap { wave in
            let intWave = abs(Int(wave))
            if intWave == 120 || intWave == 160 { return nil }
            return intWave
        }
        let resultWave: [Int] = intWave.map { wave in
            let value = 32 - Int(Double(wave) * Double(32) / Double(66)) // 66 is a random number, need to be tested
            return value < 0 ? 0 : value
        }
        let collapsedWave: [Int] = resultWave.reduce([]) { result, element in
            if result.last != element { return result + [element] }
            return result
        }
        let endWave = collapsedWave.map { UInt8($0) }
        let bytesWave = getBytesWave(from: endWave)
        let waveform = Data(bytesWave).prefix(63)
        
        Task {
            await tdSendChatAction(.chatActionUploadingVoiceNote(.init(progress: 0)))
            await sendMessageVoiceNote(duration: duration, waveform: waveform)
        }
    }
    
    func getBytesWave(from waves: [UInt8]) -> [UInt8] {
        var bytesWave = [UInt8]()
        var count = 0
        for wave in waves {
            let index = bytesWave.count - 1
            switch count {
                case 0:
                    bytesWave.append((wave & 0b00011111) << 3)
                case 1:
                    bytesWave[index] = bytesWave.last! | ((wave & 0b00011100) >> 2)
                    bytesWave.append((wave & 0b00000011) << 6)
                case 2:
                    bytesWave[index] = bytesWave.last! | ((wave & 0b00011111) << 1)
                case 3:
                    bytesWave[index] = bytesWave.last! | ((wave & 0b00010000) >> 4)
                    bytesWave.append((wave & 0b00001111) << 4)
                case 4:
                    bytesWave[index] = bytesWave.last! | ((wave & 0b00011110) >> 1)
                    bytesWave.append((wave & 0b00000001) << 7)
                case 5:
                    bytesWave[index] = bytesWave.last! | ((wave & 0b00011111) << 2)
                case 6:
                    bytesWave[index] = bytesWave.last! | ((wave & 0b00011000) >> 3)
                    bytesWave.append((wave & 0b00000111) << 5)
                case 7:
                    bytesWave[index] = bytesWave.last! | wave
                default:
                    break
            }
            count += count == 7 ? -7 : 1
        }
        return bytesWave
    }
    
    func mediaToggle(with path: String, duration: Int) {
        self.duration = duration
        withAnimation {
            if savedMediaPath.isEmpty || savedMediaPath != path {
                savedMediaPath = path
                mediaStop()
                savedMediaPath = path
                mediaPlayer.media = VLCMedia(path: path)
                mediaPlay()
            } else {
                mediaToggle()
            }
        }
    }
    
    func mediaToggle() {
        withAnimation {
            if isPlaying {
                mediaPause()
            } else {
                mediaPlay()
            }
        }
    }
    
    func mediaSeekTo(_ timeInterval: TimeInterval) {
        // swiftlint:disable:next compiler_protocol_init
        let number = NSNumber(floatLiteral: timeInterval * 1000)
        let time = VLCTime(number: number)
        mediaPlayer.time = time
    }
    
    func mediaSeekForward() {
        mediaPlayer.jumpForward(5)
    }
    
    func mediaSeekBackward() {
        mediaPlayer.jumpBackward(5)
    }
    
    func mediaPause() {
        mediaPlayer.pause()
        isPlaying = false
    }
    
    func mediaPlay() {
        setAudioSessionPlayback()
        mediaPlayer.play()
        isPlaying = true
        setNowPlaying()
    }
    
    func mediaStop() {
        withAnimation {
            isPlaying = false
            currentTime = 0
            savedMediaPath = ""
            mediaPlayer.media = nil
            mediaPlayer.stop()
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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
    
    func setAudioSessionPlayback() {
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
}
