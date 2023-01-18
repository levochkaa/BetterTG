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
    
    @MainActor func sortMainChats() {
        self.mainChats.sort(by: {
            let firstPosition = $0.chat.positions.first(where: { $0.list == .chatListMain })
            let secondPosition = $1.chat.positions.first(where: { $0.list == .chatListMain })
            
            if let firstOrder = firstPosition?.order, let secondOrder = secondPosition?.order {
                return firstOrder > secondOrder
            } else {
                return $0.chat.id < $1.chat.id
            }
        })
    }
    
    func getCustomChat(from id: Int64) async -> CustomChat? {
        guard let chat = await tdGetChat(id: id) else { return nil }
        
        if case .chatTypePrivate = chat.type {
            guard let user = await tdGetUser(id: id) else { return nil }
            
            if case .userTypeRegular = user.type {
                return CustomChat(chat: chat, user: user)
            }
        }
        
        return nil
    }
}
