// Root+get.swift

import SwiftUI
import TDLibKit

extension RootViewModel {
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
