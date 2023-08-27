// RootView+ChatsList.swift

import SwiftUI
import TDLibKit

extension RootView {
    @ViewBuilder func chatsList(
        _ customChats: [CustomChat],
        chatList: ChatList = .chatListMain
    ) -> some View {
        ForEach(customChats) { customChat in
            NavigationLink(value: customChat) {
                chatsListItem(for: customChat, chatList: chatList)
                    .matchedGeometryEffect(id: customChat.chat.id, in: namespace)
            }
            .contextMenu {
                contextMenu(for: customChat, chatList: chatList)
            } preview: {
                NavigationStack {
                    ChatView(customChat: customChat)
                        .environment(viewModel)
                        .environment(\.isPreview, true)
                }
            }
            .task {
                await viewModel.tdGetChatHistory(chatId: customChat.chat.id)
            }
        }
    }
}
