// voiceNoteViewExpanded.swift

import SwiftUI
import TDLibKit

extension MessageView {
    @ViewBuilder func voiceNoteViewExpanded(_ path: String, from voiceNote: VoiceNote) -> some View {
        VStack(alignment: .center, spacing: 10) {
            voiceNoteViewExpandedTop(path, from: voiceNote)
            
            voiceNoteViewExpandedBottom(for: voiceNote)
            
            if recognizeSpeech {
                voiceNoteSpeechResult(for: voiceNote)
            }
        }
    }
    
    @ViewBuilder func voiceNoteViewExpandedTop(_ path: String, from voiceNote: VoiceNote) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Spacer()
            
            if isOutgoing {
                voiceNoteChevron(expanded: true, duration: voiceNote.duration)
            } else {
                voiceNoteSpeech(for: voiceNote)
            }
            
            SpacingAround {
                Image(systemName: "gobackward.5")
                    .font(.title)
                    .onTapGesture {
                        viewModel.mediaSeekBackward()
                    }
            }
            
            Group {
                if viewModel.isPlaying {
                    Image(systemName: "pause.fill")
                } else {
                    Image(systemName: "play.fill")
                }
            }
            .font(.system(size: 40, weight: .bold))
            .transition(.scale)
            .matchedGeometryEffect(id: playId, in: namespace)
            .onTapGesture {
                viewModel.mediaToggle(with: path, duration: voiceNote.duration)
            }
            
            SpacingAround {
                Image(systemName: "goforward.5")
                    .font(.title)
                    .onTapGesture {
                        viewModel.mediaSeekForward()
                    }
            }
            
            if isOutgoing {
                voiceNoteSpeech(for: voiceNote)
            } else {
                voiceNoteChevron(expanded: true, duration: voiceNote.duration)
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder func voiceNoteViewExpandedBottom(for voiceNote: VoiceNote) -> some View {
        Slider(value: $viewModel.timeSliderValue, in: 0...Double(voiceNote.duration)) {
            Text("Voice Note Time Slider")
        } onEditingChanged: { value in
            if !value {
                viewModel.mediaSeekTo()
            } else {
                viewModel.isSeeking = true
            }
        }
        .padding(.horizontal, 10)
        
        HStack(alignment: .center, spacing: 0) {
            Text(viewModel.isSeeking
                 ? formattedDuration(from: viewModel.timeSliderValue)
                 : formattedDuration(from: viewModel.currentTime)
            )
            .fixedSize(horizontal: true, vertical: false)
            .matchedGeometryEffect(id: currentTimeId, in: namespace)
            
            Spacer()
            
            Text(formattedDuration(from: voiceNote.duration))
                .fixedSize(horizontal: true, vertical: false)
                .matchedGeometryEffect(id: durationId, in: namespace)
        }
        .padding(.horizontal, 10)
        .foregroundColor(.white.opacity(0.5))
    }
}
