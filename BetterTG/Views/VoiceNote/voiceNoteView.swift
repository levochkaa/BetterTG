// voiceNoteView.swift

import TDLibKit

extension MessageView {
    @ViewBuilder func voiceNoteView(_ path: String? = nil, from voiceNote: VoiceNote) -> some View {
        VStack(alignment: .center, spacing: 5) {
            voiceNoteViewTop(path, from: voiceNote)
            
            voiceNoteViewBottom(path, from: voiceNote)
            
            if recognizeSpeech {
                voiceNoteSpeechResult(for: voiceNote)
            }
        }
    }
    
    @ViewBuilder func voiceNoteViewTop(_ path: String? = nil, from voiceNote: VoiceNote) -> some View {
        HStack(alignment: .center, spacing: 5) {
            if recognizeSpeech { Spacer() }
            
            if isOutgoing {
                voiceNoteChevron(expanded: false, path: path, duration: voiceNote.duration)
            } else {
                voiceNoteSpeech(for: voiceNote)
            }
            
            if recognizeSpeech { Spacer() }
            
            Group {
                if path == nil {
                    Image(systemName: "xmark")
                } else {
                    if viewModel.savedMediaPath == path && viewModel.isPlaying {
                        Image(systemName: "pause.fill")
                    } else {
                        Image(systemName: "play.fill")
                    }
                }
            }
            .font(.largeTitle)
            .transition(.scale)
            .matchedGeometryEffect(id: playId, in: namespace)
            .onTapGesture {
                if let path {
                    viewModel.mediaToggle(with: path, duration: voiceNote.duration)
                }
            }
            
            if recognizeSpeech { Spacer() }
            
            if isOutgoing {
                voiceNoteSpeech(for: voiceNote)
            } else {
                voiceNoteChevron(expanded: false, path: path, duration: voiceNote.duration)
            }
            
            if recognizeSpeech { Spacer() }
        }
    }
    
    @ViewBuilder func voiceNoteViewBottom(_ path: String? = nil, from voiceNote: VoiceNote) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Text((viewModel.savedMediaPath == path ? formattedDuration(from: viewModel.currentTime) : "0:00"))
                .fixedSize(horizontal: true, vertical: false)
                .matchedGeometryEffect(id: currentTimeId, in: namespace)
            
            Text(" / ")
            
            Text(formattedDuration(from: voiceNote.duration))
                .fixedSize(horizontal: true, vertical: false)
                .matchedGeometryEffect(id: durationId, in: namespace)
        }
        .font(.caption)
        .foregroundColor(.white).opacity(0.5)
    }
}
