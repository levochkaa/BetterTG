// ChatsListView.swift

import SwiftUI
@preconcurrency import TDLibKit
import Combine

struct ChatsListView: View {
    @Binding var chats: [CustomChat]
    @State var cancellables = Set<AnyCancellable>()
    @State var showConfirmChatDelete = false
    @State var deleteChatForAllUsers = false
    @State var confirmedChat: Chat?
    @State var query = ""
    @Namespace var namespace
    @Environment(\.scenePhase) var scenePhase
    
    @State var filteredSortedChats = [CustomChat]()
    func updateChats() {
        filteredSortedChats = chats
            .uniqued()
            .sorted {
                if let firstOrder = $0.positions.main?.order, let secondOrder = $1.positions.main?.order {
                    return firstOrder > secondOrder
                } else {
                    return $0.chat.id > $1.chat.id
                }
            }
            .filter {
                query.isEmpty
                || $0.chat.title.lowercased().contains(query.lowercased())
                || $0.user.firstName.lowercased().contains(query.lowercased())
                || $0.user.lastName.lowercased().contains(query.lowercased())
            }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach($filteredSortedChats) { $customChat in
                        NavigationLink(value: customChat) {
                            ChatsListItemView(customChat: $customChat)
                                .matchedGeometryEffect(id: customChat.chat.id, in: namespace)
                                .matchedTransitionSource(id: customChat.chat.id, in: namespace)
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
                .padding(.top, 8)
            }
            .searchable(text: $query, prompt: "Search chats...")
            .onChange(of: query, updateChats)
            .onChange(of: chats, updateChats)
            .navigationTitle("BetterTG")
            .navigationDestination(for: CustomChat.self) { customChat in
                ChatView(customChat: customChat)
                    .navigationTransition(.zoom(sourceID: customChat.chat.id, in: namespace))
            }
            .confirmationDialog(
                "Are you sure you want to delete chat with \(confirmedChat?.title ?? "User")?",
                isPresented: $showConfirmChatDelete
            ) {
                Button("Delete", role: .destructive) {
                    guard let id = confirmedChat?.id else { return }
                    Task.background {
                        try await td.deleteChatHistory(
                            chatId: id, removeFromChatList: true, revoke: deleteChatForAllUsers
                        )
                    }
                }
            }
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
        .onAppear(perform: setPublishers)
    }
    
    // swiftlint:disable:next function_body_length
    private func setPublishers() {
        nc.publisher(&cancellables, for: .updateChatReadInbox) { updateChatReadInbox in
            guard let index = chats.firstIndex(where: { $0.chat.id == updateChatReadInbox.chatId }) else { return }
            Task.main {
                withAnimation {
                    chats[index].unreadCount = updateChatReadInbox.unreadCount
                }
            }
        }
        nc.publisher(&cancellables, for: .updateNewChat) { updateNewChat in
            Task.background {
                guard let customChat = await getCustomChat(from: updateNewChat.chat.id) else { return }
                await main {
                    withAnimation {
                        chats.append(customChat)
                    }
                }
            }
        }
        nc.publisher(&cancellables, for: .updateChatPosition) { updateChatPosition in
//            guard updateChatPosition.position.order != 0 else {
//                return Task.main {
//                    chats.removeAll(where: { $0.chat.id == updateChatPosition.chatId })
//                }
//            }
            guard let index = chats.firstIndex(where: { $0.chat.id == updateChatPosition.chatId }),
                  let positionIndex = chats[index].positions.firstIndex(where: {
                      $0.list == updateChatPosition.position.list
                  })
            else { return }
            Task.main {
                withAnimation {
                    chats[index].positions[positionIndex] = updateChatPosition.position
                }
            }
        }
        nc.publisher(&cancellables, for: .updateChatDraftMessage) { updateChatDraftMessage in
            guard let index = chats.firstIndex(where: { $0.chat.id == updateChatDraftMessage.chatId }) else { return }
            Task.main {
                withAnimation {
                    chats[index].draftMessage = updateChatDraftMessage.draftMessage
                    chats[index].positions = updateChatDraftMessage.positions
                }
            }
        }
        nc.publisher(&cancellables, for: .updateChatLastMessage) { updateChatLastMessage in
            if let index = chats.firstIndex(where: { $0.chat.id == updateChatLastMessage.chatId }) {
                Task.main {
                    withAnimation {
                        chats[index].lastMessage = updateChatLastMessage.lastMessage
                        chats[index].positions = updateChatLastMessage.positions
                    }
                }
            } else if !chats.isEmpty {
                Task.background {
                    guard let customChat = await getCustomChat(from: updateChatLastMessage.chatId) else { return }
                    await main {
                        withAnimation {
                            chats.append(customChat)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder func contextMenu(for customChat: CustomChat) -> some View {
        if let isPinned = customChat.positions.main?.isPinned {
            Button(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash.fill" : "pin.fill") {
                Task.background {
                    try await td.toggleChatIsPinned(
                        chatId: customChat.chat.id, chatList: .chatListMain, isPinned: !isPinned
                    )
                }
            }
        }
        
        if !customChat.chat.canBeDeletedOnlyForSelf, customChat.chat.canBeDeletedForAllUsers {
            Button("Delete for everyone", systemImage: "trash.fill", role: .destructive) {
                deleteChatForAllUsers = true
                confirmedChat = customChat.chat
                showConfirmChatDelete = true
            }
        }
        
        if customChat.chat.canBeDeletedOnlyForSelf, !customChat.chat.canBeDeletedForAllUsers {
            Button("Delete", systemImage: "trash", role: .destructive) {
                deleteChatForAllUsers = false
                confirmedChat = customChat.chat
                showConfirmChatDelete = true
            }
        }
        
        if customChat.chat.canBeDeletedOnlyForSelf, customChat.chat.canBeDeletedForAllUsers {
            Menu("Delete") {
                Button("Delete only for me", systemImage: "trash", role: .destructive) {
                    deleteChatForAllUsers = false
                    confirmedChat = customChat.chat
                    showConfirmChatDelete = true
                }
                
                Button("Delete for all users", systemImage: "trash.fill", role: .destructive) {
                    deleteChatForAllUsers = true
                    confirmedChat = customChat.chat
                    showConfirmChatDelete = true
                }
            }
        }
    }
}
