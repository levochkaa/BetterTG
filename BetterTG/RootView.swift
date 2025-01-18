// RootView.swift

import SwiftUI
import TDLibKit
import Combine

struct RootView: View {
    @AppStorage("loggedIn") var loggedIn = false
    @State private var folders = [CustomFolder]()
    @State private var archive: CustomFolder?
    @State private var openArchive = false
    @State private var currentFolder: Int = 0
    @State private var cancellables = Set<AnyCancellable>()
    @State private var confirmChatDelete = ConfirmChatDelete(chat: nil, show: false, forAll: false)
    
    var body: some View {
        ZStack {
            if loggedIn {
                NavigationStack {
                    TabView(selection: $currentFolder) {
                        ForEach($folders) { folder in
                            ChatsListView(folder: folder, chats: folder.chats, confirmChatDelete: $confirmChatDelete)
                                .tag(folder.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationTitle("BetterTG")
                    .navigationDestination(isPresented: $openArchive) {
                        if let archive {
                            ChatsListView(
                                folder: .constant(archive),
                                chats: .constant(archive.chats),
                                confirmChatDelete: $confirmChatDelete
                            )
                        }
                    }
//                    .searchable(text: $query, prompt: "Search chats...")
//                    .onChange(of: query, updateChats)
                    .navigationDestination(for: CustomChat.self) { customChat in
                        ChatView(customChat: customChat)
                    }
                    .confirmationDialog(
                        "Are you sure you want to delete chat with \(confirmChatDelete.chat?.title ?? "User")?",
                        isPresented: $confirmChatDelete.show
                    ) {
                        Button("Delete", role: .destructive) {
                            guard let id = confirmChatDelete.chat?.id else { return }
                            Task.background {
                                try await td.deleteChatHistory(
                                    chatId: id, removeFromChatList: true, revoke: confirmChatDelete.forAll
                                )
                            }
                        }
                    }
                    .toolbar {
                        if archive != nil {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(systemImage: "archivebox") {
                                    openArchive = true
                                }
                            }
                        }
                    }
                }
            } else {
                LoginView()
            }
        }
        .transition(.opacity)
        .onAppear(perform: setPublishers)
    }
    
    private func setPublishers() {
        nc.publisher(&cancellables, for: .updateChatFolders) { updateChatFolders in
            Task.background {
                var folders = await updateChatFolders.chatFolders.asyncCompactMap { await getCustomFolder(from: $0) }
                let mainFolder = await CustomFolder(chats: getCustomChats(for: .chatListMain) ?? [], type: .main)
                let archive = await CustomFolder(chats: getCustomChats(for: .chatListArchive) ?? [], type: .archive)
                folders.insert(mainFolder, at: updateChatFolders.mainChatListPosition)
                await main { [folders] in
                    withAnimation {
                        self.folders = folders
                        self.archive = archive
                    }
                }
            }
        }
        nc.publisher(&cancellables, for: .authorizationStateReady) { _ in
            Task.main { withAnimation { loggedIn = true } }
        }
        nc.mergeMany(&cancellables, [
            .authorizationStateClosed,
            .authorizationStateClosing,
            .authorizationStateLoggingOut,
            .authorizationStateWaitPhoneNumber,
            .authorizationStateWaitCode,
            .authorizationStateWaitPassword
        ]) { _ in
            Task.main {
                withAnimation {
                    loggedIn = false
                }
            }
        }
    }
}

func getCustomChat(from id: Int64) async -> CustomChat? {
    guard let chat = try? await td.getChat(chatId: id) else { return nil }
    
    if case .chatTypePrivate(let chatTypePrivate) = chat.type {
        guard let user = try? await td.getUser(userId: chatTypePrivate.userId) else { return nil }
        
        if case .userTypeRegular = user.type {
            return CustomChat(
                chat: chat,
                positions: chat.positions,
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
    return await chatIds.asyncCompactMap { await getCustomChat(from: $0) }
}
