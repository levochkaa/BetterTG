// ChatView+BottomArea.swift

import SwiftUI

extension ChatView {
    @ViewBuilder var bottomArea: some View {
        VStack(alignment: .center, spacing: 5) {
            Group {
                if let editMessage = viewModel.editMessage {
                    replyMessageView(editMessage, type: .edit) {
                        withAnimation {
                            viewModel.editMessage = nil
                            viewModel.editMessageText = ""
                        }
                    }
                } else if let replyMessage = viewModel.replyMessage {
                    replyMessageView(replyMessage, type: .reply) {
                        withAnimation {
                            viewModel.replyMessage = nil
                        }
                    }
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            
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
                        await viewModel.updateDraft()
                    }
                }
                
                AsyncButton {
                    if await viewModel.editMessage == nil {
                        await viewModel.sendMessage()
                    } else {
                        await viewModel.editMessage()
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
                    .transition(.scale)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
        .background(.bar)
        .cornerRadius(10)
        .padding([.horizontal, .bottom], 5)
    }
    
    @ViewBuilder func replyMessageView(
        _ customMessage: CustomMessage,
        type: ReplyMessageType?,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            ReplyMessageView(customMessage: customMessage, type: type)
                .padding(5)
                .background(Color.gray6)
                .cornerRadius(10)
            
            Image(systemName: "xmark")
                .onTapGesture {
                    action()
                }
        }
    }
}
