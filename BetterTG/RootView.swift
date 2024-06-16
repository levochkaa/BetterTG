// RootView.swift

import SwiftUI
import TDLibKit

struct RootView: View {
    @AppStorage("loggedIn") var loggedIn = false
    @State private var chats = [CustomChat]()
    
    var body: some View {
        ZStack {
            if loggedIn {
                ChatsListView(chats: $chats)
            } else {
                LoginView()
            }
        }
        .transition(.opacity)
        .onReceive(nc.publisher(for: .authorizationStateReady)) { _ in
            withAnimation { loggedIn = true }
            Task.background {
                let chatIds = try await td.getChats(chatList: .chatListMain, limit: 200).chatIds
                let customChats = await chatIds.asyncCompactMap { await getCustomChat(from: $0) }
                await main {
                    withAnimation {
                        chats = customChats
                    }
                }
            }
        }
        .onReceive(nc.mergeMany([
            .authorizationStateClosed,
            .authorizationStateClosing,
            .authorizationStateLoggingOut,
            .authorizationStateWaitPhoneNumber,
            .authorizationStateWaitCode,
            .authorizationStateWaitPassword
        ])) { _ in
            withAnimation {
                loggedIn = false
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
