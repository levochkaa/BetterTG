// RootViewModel+Load.swift

import SwiftUI

extension RootViewModel {
    func loadArchivedChats() {
        Task {
            let chatIds = await tdGetChats(for: .chatListArchive)
            let customChats = await chatIds.asyncCompactMap { await getCustomChat(from: $0) }
            await MainActor.run {
                archivedChats = customChats
            }
        }
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
}
