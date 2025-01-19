// MainView.swift

import SwiftUI
import TDLibKit

struct MainView: View {
    @Bindable private var rootVM = RootVM.shared
    @State private var progress: CGFloat = .zero
    
    var body: some View {
        NavigationStack {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(rootVM.folders) { folder in
                        FolderView(
                            folder: folder,
                            navigationBarHeight: UIApplication.safeAreaInsets.top + 91,
                            bottomBarHeight: UIApplication.safeAreaInsets.bottom + 40
                        )
                        .frame(width: UIScreen.main.bounds.width)
                        .id(folder.id)
                    }
                }
                .scrollTargetLayout()
                .readOffset(in: .scrollView(axis: .horizontal)) { progress = -$0.minX / UIScreen.main.bounds.width }
            }
            .scrollPosition(id: $rootVM.currentFolder)
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("BetterTG")
            .navigationDestination(isPresented: $rootVM.showArchive) {
                if let archive = rootVM.archive {
                    FolderView(folder: archive)
                        .navigationTitle(archive.name)
                        .navigationBarTitleDisplayMode(.inline)
                        .searchable(text: $rootVM.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search archive...")
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
            .overlay(alignment: .bottom) { bottomBarView }
        }
    }
    
    var bottomBarView: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 20) {
                ForEach(rootVM.folders) { folder in
                    Button(folder.name) {
                        withAnimation(.snappy) {
                            if rootVM.currentFolder == folder.id {
                                rootVM.scrollToTop(folderID: folder.id)
                            } else {
                                rootVM.currentFolder = folder.id
                            }
                        }
                    }
                    .foregroundStyle(.white)
                    .readOffset(in: .scrollView(axis: .horizontal)) { folder.rect = $0 }
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: .constant(rootVM.currentFolder), anchor: .center)
        .frame(height: 40)
        .background(.bar)
        .overlay(alignment: .topLeading) {
            let inputRange = rootVM.folders.indices.map { CGFloat($0) }
            let outputRange = rootVM.folders.map(\.rect.width)
            let indicatorWidth = progress.interpolate(from: inputRange, to: outputRange)
            let outputPositionRange = rootVM.folders.map(\.rect.minX)
            let indicatorPosition = progress.interpolate(from: inputRange, to: outputPositionRange)
            Rectangle()
                .fill(.white)
                .frame(width: indicatorWidth, height: 3)
                .offset(x: indicatorPosition)
        }
        .safeAreaPadding(.horizontal)
    }
}
