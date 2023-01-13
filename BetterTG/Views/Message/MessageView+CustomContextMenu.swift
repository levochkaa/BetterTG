// MessageView+CustomContextMenu.swift

import SwiftUI

extension MessageView {
    @ViewBuilder var customContextMenu: some View {
        VStack(alignment: .leading, spacing: 10) {
            let msg = customMessage.message
            
            Group {
                if !msg.isChannelPost {
                    Button {
                        if viewModel.replyMessage != nil {
                            withAnimation {
                                viewModel.replyMessage = nil
                            }
                            Task.async(after: Utils.defaultAnimationDuration + 0.05) {
                                withAnimation {
                                    viewModel.replyMessage = customMessage
                                }
                            }
                        } else {
                            withAnimation {
                                viewModel.replyMessage = customMessage
                            }
                        }
                        withAnimation {
                            openedMessageContextMenu = nil
                        }
                    } label: {
                        HStack {
                            Label("Reply", systemImage: "arrowshape.turn.up.left")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                }
                
                if msg.canBeEdited && !msg.isChannelPost {
                    Divider()
                }
                
                if msg.canBeEdited {
                    Button {
                        if viewModel.editMessage != nil {
                            withAnimation {
                                viewModel.editMessage = nil
                            }
                            Task.async(after: Utils.defaultAnimationDuration + 0.05) {
                                withAnimation {
                                    viewModel.editMessage = customMessage
                                }
                            }
                        } else {
                            withAnimation {
                                viewModel.editMessage = customMessage
                            }
                        }
                        withAnimation {
                            openedMessageContextMenu = nil
                        }
                    } label: {
                        HStack {
                            Label("Edit", systemImage: "square.and.pencil")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
            .foregroundColor(.white)
            
            if (msg.canBeDeletedOnlyForSelf || msg.canBeDeletedForAllUsers) && (!msg.isChannelPost || msg.canBeEdited) {
                Divider()
            }
            
            Group {
                if msg.canBeDeletedOnlyForSelf {
                    AsyncButton {
                        await viewModel.deleteMessage(
                            id: customMessage.message.id,
                            deleteForBoth: false
                        )
                        await MainActor.run {
                            withAnimation {
                                openedMessageContextMenu = nil
                            }
                        }
                    } label: {
                        HStack {
                            Label("Delete for me", systemImage: "trash")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                }
                
                if msg.canBeDeletedForAllUsers && msg.canBeDeletedOnlyForSelf {
                    Divider()
                }
                
                if msg.canBeDeletedForAllUsers {
                    AsyncButton {
                        await viewModel.deleteMessage(
                            id: customMessage.message.id,
                            deleteForBoth: true
                        )
                        await MainActor.run {
                            withAnimation {
                                openedMessageContextMenu = nil
                            }
                        }
                    } label: {
                        HStack {
                            Label("Delete for both", systemImage: "trash.fill")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
            .foregroundColor(.red)
        }
        .buttonStyle(.plain)
        .frame(width: 200)
        .padding(10)
        .background(.ultraThinMaterial)
        .cornerRadius(15)
    }
}
