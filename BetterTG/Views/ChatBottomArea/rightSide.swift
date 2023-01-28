// rightSide.swift

import SwiftUI

extension ChatBottomArea {
    @ViewBuilder var rightSide: some View {
        Group {
            switch viewModel.bottomAreaState {
                case .message, .reply:
                    Image("send")
                        .resizable()
                        .clipShape(Circle())
                        .frame(width: 32, height: 32)
                        .disabled(viewModel.text.isEmpty)
                case .edit:
                    Image(systemName: "checkmark.circle.fill")
                        .disabled(viewModel.editMessageText.isEmpty)
                case .caption:
                    Image(systemName: "arrow.up.circle.fill")
                case .voice:
                    if !onLongPressVoice {
                        Image(systemName: "mic.fill")
                            .foregroundColor(viewModel.recordingVoiceNote ? .blue : .white)
                            .matchedGeometryEffect(id: micId, in: chatBottomAreaNamespace)
                    }
            }
        }
        .font(.title2)
        .contentShape(Rectangle())
        .transition(.scale)
        .onTapGesture {
            Task {
                switch viewModel.bottomAreaState {
                    case .message, .reply:
                        await viewModel.sendMessageText()
                    case .caption:
                        await viewModel.sendMessagePhotos()
                    case .edit:
                        await viewModel.editMessage()
                    case .voice:
                        viewModel.mediaStopRecordingVoice(duration: Int(timerCount), wave: wave)
                }
                
                await MainActor.run {
                    viewModel.bottomAreaState = .voice
                }
            }
        }
        .if(viewModel.bottomAreaState == .voice) {
            $0.onLongPressGesture(minimumDuration: 1, maximumDistance: 1000) {
                withAnimation {
                    viewModel.mediaStartRecordingVoice()
                }
            } onPressingChanged: { value in
                withAnimation(.linear(duration: 1)) {
                    onLongPressVoice = value
                }
            }
        }
    }
}
