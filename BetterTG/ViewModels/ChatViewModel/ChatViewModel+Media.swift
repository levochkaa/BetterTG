// ChatViewModel+Media.swift

import SwiftUI
import MobileVLCKit
import AVKit
import AVFoundation
import TDLibKit

extension ChatViewModel {
    func setMediaPublishers() {
        mediaPlayer
            .publisher(for: \.time, options: [.new])
            .sink { time in
                self.currentTime = time.intValue / 1000
                
                if !self.isSeeking {
                    self.timeSliderValue = Double(time.intValue) / 1000
                }
            }
            .store(in: &cancellable)
        
        mediaPlayer
            .publisher(for: \.state, options: [.new])
            .sink { state in
                switch state {
                    case .ended:
                        self.mediaStop()
                    default:
                        break
                }
            }
            .store(in: &cancellable)
    }
    
    func mediaStartRecordingVoice() {
        savedMediaPath = ""
        mediaStop()
        setAudioSessionRecord()
        
        audioSession.requestRecordPermission { granted in
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
        }
        
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, // kAudioFormatOpus
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
//            AVEncoderBitRateKey: 16
        ]
        
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).wav") // oga, ogg, opus
        savedVoiceNoteUrl = url
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder.isMeteringEnabled = true
            audioRecorder.prepareToRecord()
            audioRecorder.record()
            recordingVoiceNote = true
            Task {
                await tdSendChatAction(.chatActionRecordingVoiceNote)
            }
        } catch {
            log("Error creating AudioRecorder: \(error)")
        }
    }
    
    func mediaStopRecordingVoice(duration: Int, wave: [Float]) {
        audioRecorder.stop()
        recordingVoiceNote = false
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
    
    func mediaToggle(with path: String) {
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
    
    // swiftlint:disable compiler_protocol_init
    func mediaSeekTo() {
        let number = NSNumber(floatLiteral: timeSliderValue * 1000)
        let time = VLCTime(number: number)
        mediaPlayer.time = time
        Task.async(after: 0.1) {
            self.isSeeking = false
        }
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
        setAudioSessionPlay()
        mediaPlayer.play()
        isPlaying = true
    }
    
    func mediaStop() {
        withAnimation {
            isPlaying = false
            currentTime = 0
            timeSliderValue = 0
            isSeeking = false
            nc.post(name: .customIsListeningVoice, object: (false, savedMediaPath))
            savedMediaPath = ""
            mediaPlayer.media = nil
            mediaPlayer.stop()
        }
    }
    
    func setAudioSessionRecord() {
        do {
            try audioSession.setCategory(.record, mode: .default, options: [
                .allowAirPlay,
                .allowBluetooth,
                .allowBluetoothA2DP,
                .defaultToSpeaker,
                .interruptSpokenAudioAndMixWithOthers,
                .overrideMutedMicrophoneInterruption
            ])
            try audioSession.setActive(true)
        } catch {
            log("Error setting audioSessionRecord: \(error)")
        }
    }
    
    func setAudioSessionPlay() {
        do {
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [
                .allowAirPlay,
                .allowBluetooth,
                .allowBluetoothA2DP,
                .defaultToSpeaker,
                .interruptSpokenAudioAndMixWithOthers,
                .overrideMutedMicrophoneInterruption
            ])
            try audioSession.setActive(true)
        } catch {
            log("Error setting audioSessionPlay: \(error)")
        }
    }
}
