// RootViewModel.swift

import SwiftUI
import Combine
import TDLibKit

class RootViewModel: ObservableObject {
    
    @Published var loggedIn: Bool?
    @Published var mainChats = [CustomChat]()
    
    init() {
        setPublishers()
    }
    
    func loadMainChats() {
        Task {
            let chatIds = await tdGetChats()
            let customChats = await chatIds.asyncCompactMap { await getCustomChat(from: $0) }
            await MainActor.run {
                mainChats = customChats
            }
        }
    }
    
    func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
            case .active:
                log("App is Active")
                Task {
                    await mainChats.asyncForEach { customChat in
                        await tdGetChatHistory(id: customChat.chat.id)
                    }
                }
            case .inactive:
                log("App is Inactive")
            case .background:
                log("App is in a Background")
            @unknown default:
                log("Unknown state of an App")
        }
    }
    
    func sortedMainChats() -> [CustomChat] {
        mainChats.sorted {
            let firstOrder = $0.positions.first(where: { $0.list == .chatListMain })?.order
            let secondOrder = $1.positions.first(where: { $0.list == .chatListMain })?.order
            
            if let firstOrder, let secondOrder {
                return firstOrder > secondOrder
            } else {
                return $0.chat.id < $1.chat.id
            }
        }
    }
    
    func getCustomChat(from id: Int64) async -> CustomChat? {
        guard let chat = await tdGetChat(id: id) else { return nil }
        
        if case .chatTypePrivate(let chatTypePrivate) = chat.type {
            guard let user = await tdGetUser(id: chatTypePrivate.userId) else { return nil }
            
            if case .userTypeRegular = user.type {
                return CustomChat(
                    chat: chat,
                    user: user,
                    positions: chat.positions,
                    lastMessage: chat.lastMessage,
                    draftMessage: chat.draftMessage
                )
            }
        }
        
        return nil
    }
}
