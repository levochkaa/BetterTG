// MessageVoiceNoteView.swift

import SwiftUI
import TDLibKit

struct MessageVoiceNoteView: View {
    let voiceNote: VoiceNote
    
    @State private var voiceLocalPath: String?
    private var isCurrentVoiceActive: Bool { media.savedMediaPath == voiceLocalPath && media.isPlaying }
    
    @Environment(Media.self) var media
    
    var body: some View {
        AsyncTdFile(id: voiceNote.voice.id) { voice in
            voiceNoteView
                .onAppear { voiceLocalPath = voice.local.path }
        } placeholder: {
            voiceNoteView
        }
        .padding(4)
        .disabled(voiceLocalPath == nil)
    }
    
    @ViewBuilder var voiceNoteView: some View {
        VStack(spacing: 5) {
            HStack(spacing: 10) {
                Button {
                    media.seekBackward()
                } label: {
                    Image(systemName: "gobackward.5")
                }
                .disabled(!isCurrentVoiceActive)
                
                Button {
                    guard let voiceLocalPath else { return }
                    media.toggle(with: voiceLocalPath, duration: voiceNote.duration)
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 34)
                        .overlay {
                            Group {
                                if isCurrentVoiceActive {
                                    Image(systemName: "pause.fill")
                                        .transition(.scale)
                                } else {
                                    Image(systemName: "play.fill")
                                        .transition(.scale)
                                }
                            }
                            .font(.system(size: 18))
                            .foregroundStyle(Color.gray6)
                        }
                }
                
                Button {
                    media.seekForward()
                } label: {
                    Image(systemName: "goforward.5")
                }
                .disabled(!isCurrentVoiceActive)
            }
            .font(.system(size: 24))
            
            HStack(spacing: 0) {
                Text(media.savedMediaPath == voiceLocalPath ? formattedDuration(from: media.currentTime) : "0:00")
                Text(" / ")
                Text(formattedDuration(from: voiceNote.duration))
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 15)
    }
    
    func formattedDuration<I: BinaryInteger>(from duration: I) -> String {
        Duration(secondsComponent: Int64(duration), attosecondsComponent: 0)
            .formatted(.time(pattern: .minuteSecond))
    }
}
