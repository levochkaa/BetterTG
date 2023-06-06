// VoiceNote.swift

import SwiftUI
import TDLibKit
import MobileVLCKit

extension MessageView {
    @ViewBuilder func makeMessageVoiceNote(from voiceNote: VoiceNote, with message: Message) -> some View {
        AsyncTdFile(id: voiceNote.voice.id) { voice in
            Group {
                if isListeningVoiceNote, viewModel.savedMediaPath == voice.local.path {
                    voiceNoteViewExpanded(voice.local.path, from: voiceNote)
                } else {
                    voiceNoteView(voice.local.path, from: voiceNote)
                }
            }
            .onReceive(nc.publisher(for: .localIsListeningVoice)) { notification in
                guard let value = notification.object as? (Bool, String) else { return }
                if voice.local.path != value.1 {
                    isListeningVoiceNote = value.0
                }
            }
        } placeholder: {
            voiceNoteView(from: voiceNote)
        }
        .padding(5)
        .onChange(of: isListeningVoiceNote) {
            nc.post(name: .localIsListeningVoice, object: nil)
        }
        .onChange(of: recognizeSpeech) {
            nc.post(name: .localRecognizeSpeech, object: nil)
        }
    }
    
    func formattedDuration(from duration: Double) -> String {
        Duration(secondsComponent: Int64(duration), attosecondsComponent: 0)
            .formatted(.time(pattern: .minuteSecond))
    }
    
    func formattedDuration<T: BinaryInteger>(from duration: T) -> String {
        Duration(secondsComponent: Int64(duration), attosecondsComponent: 0)
            .formatted(.time(pattern: .minuteSecond))
    }
}
