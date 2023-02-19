// RootViewModel+Get.swift

import SwiftUI
import TDLibKit

extension RootViewModel {
    func getCustomChat(from id: Int64) async -> CustomChat? {
        guard let chat = await tdGetChat(id: id) else { return nil }
        
        if case .chatTypePrivate(let chatTypePrivate) = chat.type {
            guard let user = await tdGetUser(id: chatTypePrivate.userId) else { return nil }
            
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
}
