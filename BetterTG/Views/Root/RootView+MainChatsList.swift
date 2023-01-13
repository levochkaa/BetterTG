// RootView+MainChatsList.swift

import SwiftUI

extension RootView {
    @ViewBuilder var mainChatsList: some View {
        ForEach(viewModel.mainChats) { customChat in
            NavigationLink {
                ChatView(
                    customChat: customChat,
                    openedPhotoInfo: $openedPhotoInfo,
                    rootNamespace: rootNamespace
                )
            } label: {
                chatsListItem(for: customChat.chat)
                    .matchedGeometryEffect(id: customChat.chat.id, in: chatNamespace)
                    .contextMenu {
                        chatsListContextMenu(for: customChat.chat)
                    } preview: {
                        NavigationStack {
                            ChatView(customChat: customChat, isPreview: true)
                        }
                    }
            }
            .onAppear {
                Task {
                    // preloading chatHistory
                    await viewModel.tdGetChatHistory(id: customChat.chat.id)
                }
            }
        }
    }
}
