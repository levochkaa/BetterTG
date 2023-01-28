// Root+mainChatsList.swift

import SwiftUI
import TDLibKit

extension RootView {
    @ViewBuilder var mainChatsList: some View {
        ForEach(viewModel.sortedMainChats()) { customChat in
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
