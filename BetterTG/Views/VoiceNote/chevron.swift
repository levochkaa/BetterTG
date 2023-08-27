// chevron.swift

extension MessageView {
    @ViewBuilder func voiceNoteChevron(expanded: Bool, path: String? = nil, duration: Int) -> some View {
        Image(systemName: (isOutgoing && expanded) || (!isOutgoing && !expanded) ? "chevron.right" : "chevron.left")
            .font(.title)
            .matchedGeometryEffect(id: chevronId, in: namespace)
            .onTapGesture {
                if expanded {
                    withAnimation {
                        isListeningVoiceNote = false
                    }
                } else if let path {
                    if path != viewModel.savedMediaPath {
                        viewModel.mediaToggle(with: path, duration: duration)
                    }
                    withAnimation {
                        isListeningVoiceNote = true
                    }
                }
            }
    }
}
