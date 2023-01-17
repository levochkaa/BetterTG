// Message+voiceNoteSide.swift

import SwiftUI
import SwiftUIX
import TDLibKit

extension MessageView {
    @ViewBuilder func voiceNoteSide(from voiceNote: VoiceNote) -> some View {
        VStack {
            if !voiceNote.voice.local.path.isEmpty, voiceNote.voice.local.path == viewModel.savedMediaPath {
                cancelVoiceNote
                    .transition(.move(edge: isOutgoing ? .trailing : .leading).combined(with: .opacity))
            }
            
            Spacer()
            
            messageOverlayDate
        }
        .padding(5)
    }
    
    @ViewBuilder var cancelVoiceNote: some View {
        Image(systemName: .xmark)
            .padding(3)
            .background(.gray6)
            .cornerRadius(15)
            .onTapGesture {
                viewModel.mediaStop()
            }
    }
    
    @ViewBuilder var messageOverlayDate: some View {
        messageDate
            .padding(3)
            .background(.gray6)
            .cornerRadius(15)
            .menuOnPress { menu }
    }
}
