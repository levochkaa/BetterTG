// ChatView+BottomArea.swift

import SwiftUI

extension ChatView {
    @ViewBuilder var bottomArea: some View {
        VStack(alignment: .center, spacing: 5) {
            if viewModel.editMessage != nil { // edit
                HStack {
                    ReplyMessageView(customMessage: viewModel.editMessage!, isEdit: true)
                        .environmentObject(viewModel)
                        .padding(5)
                        .background(Color.gray6)
                        .cornerRadius(10)
                    
                    Image(systemName: "xmark")
                        .onTapGesture {
                            withAnimation {
                                viewModel.editMessage = nil
                                viewModel.editMessageText = ""
                            }
                        }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if viewModel.replyMessage != nil { // reply
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
                TextField(
                    viewModel.editMessage == nil ? "Message..." : "New message text...",
                    text: viewModel.editMessage == nil ? $viewModel.text : $viewModel.editMessageText,
                    axis: .vertical
                )
                .focused($focused)
                .lineLimit(10)
                .padding(5)
                .background(Color.gray6)
                .cornerRadius(10)
                .onReceive(viewModel.$text.debounce(for: 2, scheduler: DispatchQueue.main)) { _ in
                    Task {
                        try await viewModel.updateDraft()
                    }
                }
                
                AsyncButton {
                    if await viewModel.editMessage == nil {
                        try await viewModel.sendMessage()
                    } else {
                        try await viewModel.editMessage()
                    }
                } label: {
                    Group {
                        if viewModel.editMessage == nil {
                            Image("send")
                                .resizable()
                        } else {
                            Image(systemName: "pencil.circle")
                                .resizable()
                                .disabled(viewModel.editMessageText.isEmpty)
                        }
                    }
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
