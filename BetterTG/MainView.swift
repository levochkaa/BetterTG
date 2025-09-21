// MainView.swift

import SwiftUI
import TDLibKit

// MARK: - MainView

struct MainView: View {
    // MARK: Internal

    var body: some View {
        NavigationControllerWrapper(navigationController: navigationStorage.navigationController) {
            MainNavigationRootView()
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    // MARK: Private

    private let navigationStorage = NavigationStorage.shared
}

// MARK: - MainNavigationRootView

private struct MainNavigationRootView: View {
    // MARK: Internal

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(rootVM.folders) { folder in
                    FolderView(
                        folder: folder,
                        navigationBarHeight: UIApplication.safeAreaInsets.top + navigationBarHeight,
                        bottomBarHeight: UIApplication.safeAreaInsets.bottom + 40,
                    )
                    .frame(width: Utils.screen.bounds.width)
                    .id(folder.id)
                }
            }
            .scrollTargetLayout()
            .readOffset(in: .scrollView(axis: .horizontal)) { progress = -$0.minX / Utils.screen.bounds.width }
        }
        .scrollPosition(id: $rootVM.currentFolder)
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("BetterTG")
        .navigationBarHeight($navigationBarHeight.animation())
        .searchable(
            text: $rootVM.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search chats...",
        )
        .confirmationDialog(
            "Are you sure you want to delete chat with \(rootVM.confirmChatDelete.chat?.title ?? "User")?",
            isPresented: $rootVM.confirmChatDelete.show,
        ) {
            Button("Delete", role: .destructive) {
                guard let id = rootVM.confirmChatDelete.chat?.id else { return }
                Task.background { [rootVM] in
                    try await td.deleteChatHistory(
                        chatId: id, removeFromChatList: true, revoke: rootVM.confirmChatDelete.forAll,
                    )
                }
            }
        }
        .toolbar {
            if let archive = rootVM.archive {
                ToolbarItem(placement: .topBarLeading) {
                    Button(systemImage: "archivebox") {
                        navigationStorage.push(.archive(archive))
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !rootVM.folders.isEmpty {
                bottomBarView
            }
        }
        .onAppear {
            navigationStorage.setDestinationBuilder { route in
                switch route {
                case .customChat(let customChat):
                    ChatView(customChat: customChat)
                case .archive(let customFolder):
                    FolderView(folder: customFolder)
                        .navigationTitle(customFolder.name)
                        .navigationBarTitleDisplayMode(.inline)
                        .searchable(
                            text: $rootVM.query,
                            placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "Search archive...",
                        )
                }
            }
        }
    }
    
    var bottomBarView: some View {
        ScrollView(.horizontal) {
            CustomTabBar(
                folders: rootVM.folders,
                activeTab: $rootVM.currentFolder,
                tabItemView: { index, folder, control in
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
                    .padding(.horizontal)
                    .readSize { control.setWidth($0.width, forSegmentAt: index) }
                },
            )
            .glassEffect()
        }
        .scrollIndicators(.hidden)
        .scrollPosition($rootVM.scrollPosition, anchor: .center)
        .frame(height: 40)
        .padding(.bottom, UIApplication.safeAreaInsets.bottom)
        .background {
            LinearGradient(colors: [.black, .clear], startPoint: .bottom, endPoint: .top)
                .frame(height: 40 + UIApplication.safeAreaInsets.bottom)
        }
        .safeAreaPadding(.horizontal)
    }

    // MARK: Private

    @Bindable private var rootVM = RootVM.shared
    @State private var progress = CGFloat.zero

    @State private var navigationBarHeight = CGFloat.zero

    private let navigationStorage = NavigationStorage.shared
}

// MARK: - SegmentedControl

final class SegmentedControl: UISegmentedControl {
    override func gestureRecognizerShouldBegin(_: UIGestureRecognizer) -> Bool {
        true
    }
}

// MARK: - CustomTabBar

struct CustomTabBar<TabItemView: View>: UIViewRepresentable {
    final class Coordinator: NSObject {
        // MARK: Lifecycle

        init(parent: CustomTabBar) {
            self.parent = parent
        }
        
        // MARK: Internal

        var parent: CustomTabBar
        var view: SegmentedControl!
        
        @objc func tabSelected(_ control: UISegmentedControl) {
            guard control.selectedSegmentIndex >= 0,
                  control.selectedSegmentIndex < parent.folders.count else { return }
            withAnimation {
                let selectedIndex = control.selectedSegmentIndex
                parent.activeTab = parent.folders[selectedIndex].id
                scrollToSelectedSegment(control, selectedIndex: selectedIndex)
            }
        }
        
        func scrollToSelectedSegment(_ control: UISegmentedControl, selectedIndex: Int) {
            guard selectedIndex >= 0, selectedIndex < control.numberOfSegments else { return }
            let leadingWidth = (0..<selectedIndex).reduce(CGFloat.zero) { result, index in
                result + control.widthForSegment(at: index)
            }
            let selectedWidth = control.widthForSegment(at: selectedIndex)
            let selectedCenter = leadingWidth + selectedWidth / 2
            let metrics = scrollMetrics(for: control)
            let visibleWidth = metrics?.visibleWidth ?? control.bounds.width
            let contentWidth = metrics?.contentWidth ?? control.bounds.width
            let maxOffset = max(0, contentWidth - visibleWidth)
            let targetX = min(max(selectedCenter - visibleWidth / 2, 0), maxOffset)
            
            if selectedIndex == control.numberOfSegments - 1 {
                RootVM.shared.scrollPosition.scrollTo(edge: .trailing)
            } else {
                RootVM.shared.scrollPosition.scrollTo(x: targetX)
            }
        }
        
        // MARK: Private

        private func scrollMetrics(for view: UIView) -> (visibleWidth: CGFloat, contentWidth: CGFloat)? {
            var currentSuperview = view.superview
            while let superview = currentSuperview {
                if let scrollView = superview as? UIScrollView {
                    let visibleWidth = scrollView.bounds.width
                    let contentWidth = scrollView.contentSize.width > 0 ? scrollView.contentSize.width : visibleWidth
                    return (visibleWidth, contentWidth)
                }
                currentSuperview = superview.superview
            }
            return nil
        }
    }

    let folders: [CustomFolder]
    @Binding var activeTab: Int?

    @ViewBuilder var tabItemView: (Int, CustomFolder, SegmentedControl) -> TabItemView
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIView(context: Context) -> UISegmentedControl {
        let control = SegmentedControl(items: folders.map {
            UIAction(title: $0.name, handler: { _ in })
        })
        context.coordinator.view = control
        for (index, folder) in folders.enumerated() {
            let renderer = ImageRenderer(content: tabItemView(index, folder, control))
            renderer.scale = Utils.screen.scale
            control.setImage(renderer.uiImage, forSegmentAt: index)
        }
        Task.main {
            for subview in control.subviews {
                if subview is UIImageView, subview != control.subviews.last {
                    // It's a background Image View!
                    subview.alpha = 0
                }
            }
            
            log(control.subviews)
        }
        control.selectedSegmentIndex = 0
        control.apportionsSegmentWidthsByContent = true
        control.setTitleTextAttributes([
            .foregroundColor: UIColor(.white),
            .font: UIFont.systemFont(ofSize: 17),
        ], for: .selected)
        control.setTitleTextAttributes([
            .foregroundColor: UIColor(.white),
            .font: UIFont.systemFont(ofSize: 17),
        ], for: .normal)
        control.addTarget(
            context.coordinator,
            action: #selector(context.coordinator.tabSelected(_:)),
            for: .valueChanged,
        )
        return control
    }
    
    func updateUIView(_ control: UISegmentedControl, context: Context) {
        guard !folders.isEmpty, control.numberOfSegments > 0 else { return }
        let maxIndex = control.numberOfSegments - 1
        let selectedIndex = min(folders.firstIndex(where: { $0.id == activeTab }) ?? 0, maxIndex)
        if control.selectedSegmentIndex != selectedIndex {
            control.selectedSegmentIndex = selectedIndex
            withAnimation {
                context.coordinator.scrollToSelectedSegment(control, selectedIndex: selectedIndex)
            }
        }
    }
    
    func sizeThatFits(_: ProposedViewSize, uiView control: UISegmentedControl, context _: Context) -> CGSize? {
        var width: CGFloat = 0
        for index in folders.indices {
            width += control.widthForSegment(at: index)
        }
        return CGSize(width: width, height: 40)
    }
}
