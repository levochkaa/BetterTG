// Root+chatsList.swift

import SwiftUI
import TDLibKit

extension RootView {
    @ViewBuilder func chatsList(_ customChats: [CustomChat], redacted: Bool = false) -> some View {
        ForEach(customChats) { customChat in
            NavigationLink {
                ChatView(
                    customChat: customChat,
                    openedPhotoInfo: $openedPhotoInfo,
                    rootNamespace: rootNamespace
                )
            } label: {
                chatsListItem(for: customChat, redacted: redacted)
                    .if(!redacted) {
                        $0.matchedGeometryEffect(id: customChat.chat.id, in: rootNamespace)
                    }
                    .contextMenu {
                        contextMenu(for: customChat.chat)
                    } preview: {
                        NavigationStack {
                            ChatView(customChat: customChat, isPreview: true)
                        }
                    }
            }
            .disabled(redacted)
            .task {
                if !redacted {
                    await viewModel.tdGetChatHistory(id: customChat.chat.id)
                }
            }
        }
    }
}
