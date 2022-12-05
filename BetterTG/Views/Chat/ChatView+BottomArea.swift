// ChatView+BottomArea.swift

import SwiftUI

extension ChatView {
    @ViewBuilder var bottomArea: some View {
        VStack(alignment: .center, spacing: 5) {
            // reply
            if viewModel.replyMessage != nil {
                HStack {
                    ReplyMessageView(customMessage: viewModel.replyMessage!, isReply: true)
                        .environmentObject(viewModel)
                        .padding(5)
                        .background(Color.gray6)
                        .cornerRadius(10)
                        
                    Image(systemName: "xmark")
                        .onTapGesture {
                            withAnimation {
                                viewModel.replyMessage = nil
                            }
                        }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // message
            HStack(alignment: .bottom) {
                TextField("Message", text: $text, axis: .vertical)
                    .focused($focused)
                    .lineLimit(10)
                    .padding(5)
                    .background(Color.gray6)
                    .cornerRadius(10)
                
                Button(action: sendMessage) {
                    Image("send")
                        .resizable()
                        .clipShape(Circle())
                        .frame(width: 32, height: 32)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
        .background(.bar)
        .cornerRadius(10)
        .padding([.horizontal, .bottom], 5)
    }
}
