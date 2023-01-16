// chevron.swift

import SwiftUI

extension MessageView {
    @ViewBuilder func voiceNoteChevron(expanded: Bool, path: String? = nil) -> some View {
        Image(systemName: (isOutgoing && expanded) || (!isOutgoing && !expanded) ? "chevron.right" : "chevron.left")
            .font(.title)
            .matchedGeometryEffect(id: chevronId, in: voiceNoteNamespace)
            .onTapGesture {
                if expanded {
                    withAnimation {
                        isListeningVoiceNote = false
                    }
                } else if let path {
                    if path != viewModel.savedMediaPath {
                        viewModel.mediaToggle(with: path)
                    }
                    withAnimation {
                        isListeningVoiceNote = true
                    }
                }
            }
    }
}
