// ChatViewModel+Scroll.swift

import SwiftUI

extension ChatViewModel {
    func scrollToLast() {
        guard let lastId = messages.last?.message.id, let scrollViewProxy else { return }
        
        withAnimation {
            scrollViewProxy.scrollTo(lastId, anchor: .bottom)
        }
    }
    
    func scrollTo(id: Int64?, anchor: UnitPoint = .center) {
        guard let scrollViewProxy, let id else { return }
        
        withAnimation {
            scrollViewProxy.scrollTo(id, anchor: anchor)
            highlightedMessageId = id
        }
        
        Task.async(after: 0.5) {
            withAnimation {
                self.highlightedMessageId = nil
            }
        }
    }
}
