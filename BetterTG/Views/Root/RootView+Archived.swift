// Root+archived.swift

import SwiftUI
import TDLibKit

extension RootView {
    @ViewBuilder var archivedChatsView: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    chatsList(viewModel.filteredSortedChats(queryArchived, for: .chatListArchive))
                }
                .padding(.top, 8)
                .animation(.default, value: viewModel.archivedChats)
            }
            .background(.black)
            .navigationTitle("Archived")
            .searchable(text: $queryArchived, prompt: "Search archived chats...")
        }
    }
}
