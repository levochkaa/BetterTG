// RootView+Body.swift

import SwiftUI

extension RootView {
    @ViewBuilder var bodyView: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.filteredSortedChats(query, for: .chatListMain)) { customChat in
                        NavigationLink(value: customChat) {
                            chatsListItem(for: customChat, chatList: .chatListMain)
                                .matchedGeometryEffect(id: customChat.chat.id, in: namespace)
                        }
                    }
                }
                .padding(.top, 8)
                .animation(value: viewModel.mainChats)
            }
            .navigationTitle("BetterTG")
            .navigationDestination(isPresented: $showArchivedChats) {
                archivedChatsView
            }
            .navigationDestination(for: CustomChat.self) { customChat in
                ChatView(customChat: customChat)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(.ultraThinMaterial)
                    .presentationCornerRadius(20)
                    .presentationContentInteraction(.resizes)
                    .presentationCompactAdaptation(.sheet)
                    .presentationBackgroundInteraction(.disabled)
            }
            .toolbar {
                if showArchivedChatsButton {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(systemImage: "square.stack") {
                            showArchivedChats = true
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(systemImage: "gear") {
                        showSettings = true
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search chats...")
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhase(newPhase)
        }
        .confirmationDialog(
            "Are you sure you want to delete chat with \(confirmedChat?.title ?? "User")?",
            isPresented: $showConfirmChatDelete
        ) {
            Button("Delete", role: .destructive) {
                guard let id = confirmedChat?.id else { return }
                Task {
                    await viewModel.tdDeleteChatHistory(chatId: id, forAll: deleteChatForAllUsers)
                }
            }
        }
        .overlay {
            if let openedItem = viewModel.openedItem {
                ItemView(item: openedItem)
                    .zIndex(1)
            }
        }
    }
}
