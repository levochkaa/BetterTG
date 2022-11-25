// RootViewVM.swift

import SwiftUI
import Combine
import TDLibKit
import CollectionConcurrencyKit

class RootViewVM: ObservableObject {
    
    @Published var loggedIn: Bool?
    @Published var mainChats = [Chat]()
    
    private let tdApi: TdApi = .shared
    private let logger = Logger(label: "RootVM")
    private let nc: NotificationCenter = .default
    
    init() {
        self.setPublishers()
    }
    
    func setPublishers() {
        self.setAuthPublishers()
    }
    
    func setAuthPublishers() {
        nc.mergeMany([
            nc.publisher(for: .closed),
            nc.publisher(for: .closing),
            nc.publisher(for: .loggingOut),
            nc.publisher(for: .waitPhoneNumber)
        ]) { _ in
            DispatchQueue.main.async {
                self.loggedIn = false
            }
        }
        
        nc.publisher(for: .ready) { _ in
            Task {
                try await self.loadMainChats()
            }
            DispatchQueue.main.async {
                self.loggedIn = true
            }
        }
    }
    
    func loadMainChats() async throws {
        _ = try await tdApi.loadChats(chatList: .chatListMain, limit: 50)
        let chats = try await tdApi.getChats(chatList: .chatListMain, limit: 50)
        let mainChats = try await chats.chatIds.asyncCompactMap { id in
            let chat = try await tdApi.getChat(chatId: id)
            switch chat.type {
            case .chatTypePrivate:
                return try await tdApi.getUser(userId: chat.id).type == .userTypeRegular ? chat : nil
            default:
                return nil
            }
        }
        DispatchQueue.main.async {
            self.mainChats = mainChats
        }
    }
}
