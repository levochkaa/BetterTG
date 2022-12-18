// ChatView+BottomArea.swift

import SwiftUI
import PhotosUI

extension ChatView {
    @ViewBuilder var bottomReplyEdit: some View {
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
}

extension ChatView {
    @ViewBuilder var textFieldCustom: some View {
        HStack(alignment: .center, spacing: 10) {
            PhotosPicker(selection: $viewModel.selectedPhotos,
                         maxSelectionCount: 10,
                         selectionBehavior: .default,
                         matching: .any(of: [.images, .screenshots]),
                         preferredItemEncoding: .automatic,
                         photoLibrary: .shared()
            ) {
                Image(systemName: "paperclip")
                    .font(.title3)
                    .foregroundColor(.white)
            }
            
            TextField(
                textFieldPrompt(),
                text: textFieldText(),
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
            
            Button {
                Task {
                    if viewModel.editMessage == nil && viewModel.displayedPhotos.isEmpty {
                        await viewModel.sendMessage()
                    } else if viewModel.editMessage != nil {
                        await viewModel.editMessage()
                    } else if !viewModel.displayedPhotos.isEmpty {
                        await viewModel.sendMedia()
                    } else {
                        logger.log("Unknown send action")
                    }
                }
            } label: {
                Group {
                    if viewModel.editMessage == nil && viewModel.displayedPhotos.isEmpty {
                        Image("send")
                            .resizable()
                            .disabled(viewModel.text.isEmpty)
                    } else if viewModel.editMessage != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .disabled(viewModel.editMessageText.isEmpty)
                    } else if !viewModel.displayedPhotos.isEmpty {
                        Image(systemName: "arrow.up.circle.fill")
                            .resizable()
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                    }
                }
                .clipShape(Circle())
                .frame(width: 32, height: 32)
                .transition(.scale)
            }
        }
    }
}

extension ChatView {
    @ViewBuilder var bottomArea: some View {
        VStack(alignment: .center, spacing: 5) {
            Group {
                bottomReplyEdit
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))

            Group {
                displayedPhotos
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))

            textFieldCustom
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(.bar)
        .cornerRadius(10)
        .padding([.bottom, .horizontal], 5)
    }
    
    func textFieldText() -> Binding<String> {
        if viewModel.editMessage == nil && viewModel.displayedPhotos.isEmpty {
            return $viewModel.text
        } else if viewModel.editMessage != nil {
            return $viewModel.editMessageText
        } else if !viewModel.displayedPhotos.isEmpty {
            return $viewModel.caption
        } else {
            logger.log("Unknown state of textFieldText")
            return Binding(get: { String() }, set: { _ in })
        }
    }
    
    func textFieldPrompt() -> String {
        if viewModel.editMessage == nil && viewModel.displayedPhotos.isEmpty {
            return "Message..."
        } else if viewModel.editMessage != nil {
            return "New message text..."
        } else if !viewModel.displayedPhotos.isEmpty {
            return "Caption..."
        } else {
            logger.log("Unknown state of textFieldPrompt")
            return "Unknown state"
        }
    }
    
    @ViewBuilder func replyMessageView(
        _ customMessage: CustomMessage,
        type: ReplyMessageType,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            ReplyMessageView(customMessage: customMessage, type: type)
                .environmentObject(viewModel)
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
