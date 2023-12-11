// ChatBottomArea+RightSide.swift

import SwiftUI

extension ChatBottomArea {
    @ViewBuilder var rightSide: some View {
        Group {
            if showSendButton {
                Image("send")
                    .resizable()
                    .clipShape(Circle())
                    .frame(width: 32, height: 32)
                    .padding(.bottom, 3)
            } else {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.white)
                    .padding(.bottom, 5)
            }
        }
        .font(.title2)
        .contentShape(Rectangle())
        .transition(.scale)
        .onTapGesture {
            Task {
                await viewModel.sendMessage()
            }
        }
        .onLongPressGesture(minimumDuration: 0.1, maximumDistance: 1000) {
            Task { @MainActor in
                await viewModel.mediaStartRecordingVoice()
            }
        }
        .onChange(of: viewModel.editMessageText, setShowSendButton)
        .onChange(of: viewModel.text, setShowSendButton)
        .onChange(of: viewModel.displayedImages, setShowSendButton)
    }
    
    func setShowSendButton() {
        let value = !viewModel.displayedImages.isEmpty
            || !viewModel.editMessageText.characters.isEmpty
            || !viewModel.text.characters.isEmpty
        withAnimation {
            showSendButton = value
        }
    }
}
