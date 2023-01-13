// ChatViewModel+Scroll.swift

import SwiftUI

extension ChatViewModel {
    func scrollToLast() {
        guard let firstId = messages.first?.message.id, let scrollViewProxy else { return }
        
        withAnimation {
            scrollViewProxy.scrollTo(firstId, anchor: .bottom)
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
