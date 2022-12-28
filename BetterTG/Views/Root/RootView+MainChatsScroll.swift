// RootView+MainChatsScroll.swift

import SwiftUI
import TDLibKit

extension RootView {
    @ViewBuilder var mainChatsScroll: some View {
        ScrollView {
            ZStack {
                LazyVStack(spacing: RootView.spacing) {
                    mainChatsList
                }
                .padding(.top, 8)
                
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named(scroll))
                    )
                }
            }
        }
        .coordinateSpace(name: scroll)
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            if viewModel.loadingUsers { return }
            
            let maxY = Int(value.maxY)
            
            if viewModel.mainChats.count <= RootView.maxChatsOnScreen {
                let approximateValue = viewModel.loadedUsers * RootView.chatListViewHeight
                let bottom = approximateValue - 30
                let top = approximateValue + 30
                let range = (bottom...top)
                if range.contains(maxY) {
                    Task {
                        await viewModel.loadMainChats()
                    }
                }
            } else {
                let range = (700...1100)
                if range.contains(maxY) {
                    Task {
                        await viewModel.loadMainChats()
                    }
                }
            }
        }
    }
    
    @ViewBuilder func chatsListContextMenu(for chat: Chat) -> some View {
        Button("Delete", role: .destructive) {
            showConfirmChatDelete = true
            confirmedChat = chat
        }
    }
}
