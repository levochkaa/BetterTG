// Root+load.swift

import SwiftUI
import TDLibKit

extension RootViewModel {
    func loadMainChats() async {
        await tdLoadChats()
        
        await MainActor.run {
            loadingUsers = true
        }
        
        guard let chats = await tdGetChats() else { return }
        let mainChats = await chats.chatIds.asyncCompactMap { await getCustomChat(from: $0) }
        let filteredMainChats = mainChats.filter { mainChat in
            !self.mainChats.contains(where: { mainChat.chat.id == $0.chat.id })
        }
        
        loadedUsers = mainChats.count
        limit += 10
        
        await MainActor.run {
            self.mainChats.append(contentsOf: filteredMainChats)
            self.loadingUsers = false
            
            withAnimation {
                self.sortMainChats()
            }
        }
    }
}
