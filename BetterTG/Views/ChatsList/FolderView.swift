// FolderView.swift

import SwiftUI
import TDLibKit
import Combine

struct FolderView: View {
    @State var folder: CustomFolder
    var navigationBarHeight: CGFloat = .zero
    
    var chats: [CustomChat] {
        folder.chats
            .sorted { $0.position.order > $1.position.order }
            .filter {
                rootVM.query.isEmpty
                || $0.chat.title.lowercased().contains(rootVM.query.lowercased())
                || $0.user?.firstName.lowercased().contains(rootVM.query.lowercased()) == true
                || $0.user?.lastName.lowercased().contains(rootVM.query.lowercased()) == true
            }
    }
    
    @Namespace var namespace
    @Environment(\.scenePhase) var scenePhase
    @State var rootVM: RootVM = .shared
    
    var body: some View {
        ScrollViewReader { scrollViewProxy in
            bodyView.onAppear { folder.scrollViewProxy = scrollViewProxy }
        }
        .contentMargins(.top, navigationBarHeight - 8, for: .scrollIndicators)
        .onChange(of: scenePhase) { _, newPhase in
            guard case .active = newPhase else { return }
            Task.background {
                await chats.asyncForEach { customChat in
                    _ = try? await td.getChatHistory(
                        chatId: customChat.chat.id,
                        fromMessageId: 0,
                        limit: 30,
                        offset: 0,
                        onlyLocal: false
                    )
                }
            }
        }
    }
    
    var bodyView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                Spacer()
                    .frame(height: navigationBarHeight)
                    .id("top")
                if chats.isEmpty {
                    Text("Empty folder :(")
                } else {
                    ForEach(chats) { customChat in
                        NavigationLink {
                            LazyView {
                                ChatView(customChat: customChat)
                            }
                        } label: {
                            ChatsListItemView(folder: folder, customChat: customChat)
                                .matchedGeometryEffect(id: customChat.chat.id, in: namespace)
                        }
                        .contextMenu {
                            contextMenu(for: customChat)
                        } preview: {
                            LazyView {
                                NavigationStack {
                                    ChatView(customChat: customChat)
                                        .environment(\.isPreview, true)
                                }
                            }
                        }
                        .task {
                            _ = try? await td.getChatHistory(
                                chatId: customChat.chat.id,
                                fromMessageId: 0,
                                limit: 30,
                                offset: 0,
                                onlyLocal: false
                            )
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder func contextMenu(for customChat: CustomChat) -> some View {
        let isPinned = customChat.position.isPinned
        Button(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash.fill" : "pin.fill") {
            Task.background {
                try await td.toggleChatIsPinned(
                    chatId: customChat.chat.id, chatList: folder.chatList, isPinned: !isPinned
                )
            }
        }
        
        if !customChat.chat.canBeDeletedOnlyForSelf, customChat.chat.canBeDeletedForAllUsers {
            Button("Delete for everyone", systemImage: "trash.fill", role: .destructive) {
                rootVM.confirmChatDelete = ConfirmChatDelete(chat: customChat.chat, show: true, forAll: true)
            }
        }
        
        if customChat.chat.canBeDeletedOnlyForSelf, !customChat.chat.canBeDeletedForAllUsers {
            Button("Delete", systemImage: "trash", role: .destructive) {
                rootVM.confirmChatDelete = ConfirmChatDelete(chat: customChat.chat, show: true, forAll: false)
            }
        }
        
        if customChat.chat.canBeDeletedOnlyForSelf, customChat.chat.canBeDeletedForAllUsers {
            Menu("Delete") {
                Button("Delete only for me", systemImage: "trash", role: .destructive) {
                    rootVM.confirmChatDelete = ConfirmChatDelete(chat: customChat.chat, show: true, forAll: false)
                }
                
                Button("Delete for all users", systemImage: "trash.fill", role: .destructive) {
                    rootVM.confirmChatDelete = ConfirmChatDelete(chat: customChat.chat, show: true, forAll: true)
                }
            }
        }
    }
}
