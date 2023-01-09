// RootView+MainChatsList.swift

import SwiftUI

extension RootView {
    @ViewBuilder var mainChatsList: some View {
        ForEach(viewModel.mainChats, id: \.id) { chat in
            NavigationLink {
                ChatView(
                    chat: chat,
                    openedPhotoInfo: $openedPhotoInfo,
                    openedPhotoNamespace: openedPhotoNamespace
                )
            } label: {
                chatsListItem(for: chat)
                    .matchedGeometryEffect(id: chat.id, in: chatNamespace)
                    .contextMenu {
                        chatsListContextMenu(for: chat)
                    } preview: {
                        NavigationStack {
                            ChatView(chat: chat, isPreview: true)
                        }
                    }
            }
            .onAppear {
                Task {
                    // preloading chatHistory
                    await viewModel.tdGetChatHistory(id: chat.id)
                }
            }
        }
    }
}
