// MainView.swift

import SwiftUI
import TDLibKit

struct MainView: View {
    @Bindable private var rootVM = RootVM.shared
    
    var body: some View {
        NavigationStack {
            TabView(selection: $rootVM.currentFolder) {
                ForEach(rootVM.folders) { folder in
                    FolderView(folder: folder)
                        .tag(folder.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("BetterTG")
            .navigationDestination(isPresented: $rootVM.showArchive) {
                if let archive = rootVM.archive {
                    FolderView(folder: archive)
                }
            }
            .searchable(text: $rootVM.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search chats...")
            .confirmationDialog(
                "Are you sure you want to delete chat with \(rootVM.confirmChatDelete.chat?.title ?? "User")?",
                isPresented: $rootVM.confirmChatDelete.show
            ) {
                Button("Delete", role: .destructive) {
                    guard let id = rootVM.confirmChatDelete.chat?.id else { return }
                    Task.background { [rootVM] in
                        try await td.deleteChatHistory(
                            chatId: id, removeFromChatList: true, revoke: rootVM.confirmChatDelete.forAll
                        )
                    }
                }
            }
            .toolbar {
                if rootVM.archive != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(systemImage: "archivebox") {
                            rootVM.showArchive = true
                        }
                    }
                }
            }
        }
    }
}
