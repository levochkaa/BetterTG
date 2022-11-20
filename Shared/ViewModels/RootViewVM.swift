// RootViewVM.swift

import SwiftUI
import Combine
import TDLibKit
import CollectionConcurrencyKit

class RootViewVM: ObservableObject {
    
    @Published var loggedIn = false
    @Published var mainChats = [Chat]()
    
    private let tdApi: TdApi = .shared
    private let logger = Logger(label: "RootVM")
    private let nc = NotificationCenter.default
    private var cancellable = Set<AnyCancellable>()
    
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
            nc.publisher(for: .loggingOut)
        ], in: &cancellable) { _ in
            DispatchQueue.main.async {
                self.loggedIn = false
            }
        }
        
        nc.publisher(for: .ready, in: &cancellable) { _ in
            DispatchQueue.main.async {
                self.loggedIn = true
            }
        }
    }
    
    func loadMainChats() async throws {
        _ = try await tdApi.loadChats(chatList: .chatListMain, limit: 30)
        let chats = try await tdApi.getChats(chatList: .chatListMain, limit: 30)
        let mainChats = try await chats.chatIds.asyncMap { id in
            return try await tdApi.getChat(chatId: id)
        }
        DispatchQueue.main.async {
            self.mainChats = mainChats
        }
    }
}
