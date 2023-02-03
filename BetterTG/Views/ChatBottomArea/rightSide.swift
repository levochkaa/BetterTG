// rightSide.swift

import SwiftUI

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
                    .matchedGeometryEffect(id: micId, in: chatBottomAreaNamespace)
            }
        }
        .disabled(!redactionReasons.isEmpty)
        .unredacted()
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
    }
}
