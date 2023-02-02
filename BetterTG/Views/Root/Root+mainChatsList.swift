// Root+chatsList.swift

import SwiftUI
import TDLibKit

extension RootView {
    @ViewBuilder func chatsList(_ customChats: [CustomChat]) -> some View {
        ForEach(customChats) { customChat in
            NavigationLink {
                ChatView(
                    customChat: customChat,
                    openedPhotoInfo: $openedPhotoInfo,
                    rootNamespace: rootNamespace
                )
            } label: {
                chatsListItem(for: customChat)
                    .matchedGeometryEffect(id: customChat.chat.id, in: rootNamespace)
                    .contextMenu {
                        contextMenu(for: customChat.chat)
                    } preview: {
                        NavigationStack {
                            ChatView(customChat: customChat, isPreview: true)
                        }
                    }
            }
            .task {
                await viewModel.tdGetChatHistory(id: customChat.chat.id)
            }
        }
    }
}
