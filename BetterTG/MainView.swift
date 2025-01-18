// MainView.swift

import SwiftUI
import TDLibKit

struct MainView: View {
    @Bindable private var rootVM = RootVM.shared
    
    var body: some View {
        NavigationStack {
            TabView(selection: $rootVM.currentFolder) {
                ForEach(rootVM.folders) { folder in
                    FolderView(folder: folder)
                        .tag(folder.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("BetterTG")
            .navigationDestination(isPresented: $rootVM.showArchive) {
                if let archive = rootVM.archive {
                    FolderView(folder: archive)
                }
            }
            .searchable(text: $rootVM.query, prompt: "Search chats...")
            .navigationDestination(for: CustomChat.self) { ChatView(customChat: $0) }
            .confirmationDialog(
                "Are you sure you want to delete chat with \(rootVM.confirmChatDelete.chat?.title ?? "User")?",
                isPresented: $rootVM.confirmChatDelete.show
            ) {
                Button("Delete", role: .destructive) {
                    guard let id = rootVM.confirmChatDelete.chat?.id else { return }
                    Task.background { [rootVM] in
                        try await td.deleteChatHistory(
                            chatId: id, removeFromChatList: true, revoke: rootVM.confirmChatDelete.forAll
                        )
                    }
                }
            }
            .toolbar {
                if rootVM.archive != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(systemImage: "archivebox") {
                            rootVM.showArchive = true
                        }
                    }
                }
            }
        }
    }
}

func getCustomChat(from id: Int64, for chatList: ChatList) async -> CustomChat? {
    guard let chat = try? await td.getChat(chatId: id) else { return nil }
    
    if case .chatTypePrivate(let chatTypePrivate) = chat.type {
        guard let user = try? await td.getUser(userId: chatTypePrivate.userId) else { return nil }
        
        if case .userTypeRegular = user.type, let position = chat.positions.first(chatList) {
            return CustomChat(
                chat: chat,
                position: position,
                unreadCount: chat.unreadCount,
                user: user,
                lastMessage: chat.lastMessage,
                draftMessage: chat.draftMessage
            )
        }
    }
    
    return nil
}

func getCustomFolder(from info: ChatFolderInfo) async -> CustomFolder? {
    guard let folder = try? await td.getChatFolder(chatFolderId: info.id),
          let customChats = await getCustomChats(for: .chatListFolder(.init(chatFolderId: info.id)))
    else { return nil }
    let customFolder = CustomFolder(
        chats: customChats,
        type: .folder(info, folder)
    )
    return customFolder
}

func getCustomChats(for chatList: ChatList) async -> [CustomChat]? {
    guard let chatIds = try? await td.getChats(chatList: chatList, limit: 200).chatIds else { return nil }
    return await chatIds.asyncCompactMap { await getCustomChat(from: $0, for: chatList) }
}
