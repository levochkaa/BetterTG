// ChatBottomArea+RightSide.swift

extension ChatBottomArea {
    @ViewBuilder var rightSide: some View {
        Group {
            if showSendButton {
                Image("send")
                    .resizable()
                    .clipShape(Circle())
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "mic.fill")
                    .foregroundColor(.white)
                    .matchedGeometryEffect(id: micId, in: namespace)
            }
        }
        .font(.title2)
        .contentShape(Rectangle())
        .transition(.scale.animation(.default))
        .onTapGesture {
            Task {
                await viewModel.sendMessage()
            }
        }
        .onLongPressGesture(minimumDuration: 0.1, maximumDistance: 1000) {
            withAnimation {
                viewModel.mediaStartRecordingVoice()
            }
        }
        .onChange(of: viewModel.editMessageText, setShowSendButton)
        .onChange(of: viewModel.text, setShowSendButton)
        .onChange(of: viewModel.displayedImages, setShowSendButton)
    }
    
    func setShowSendButton() {
        // swiftlint:disable:next line_length
        showSendButton = !viewModel.displayedImages.isEmpty || !viewModel.editMessageText.characters.isEmpty || !viewModel.text.characters.isEmpty
    }
}
