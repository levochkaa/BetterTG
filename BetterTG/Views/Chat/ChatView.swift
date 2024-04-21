// ChatView.swift

import SwiftUI
import TDLibKit

struct ChatView: View {
    @State var viewModel: ChatViewModel
    
    @FocusState var focused
    
    let scroll = "chatScroll"
    @State var scrollOnFocus = true
    @State var showScrollToBottomButton = false
    
    @Environment(\.isPreview) var isPreview
    @Environment(\.dismiss) var dismiss
    
    init(customChat: CustomChat) {
        self._viewModel = State(initialValue: ChatViewModel(customChat: customChat))
    }
    
    var body: some View {
        ZStack {
            if viewModel.customChat.lastMessage == nil {
                Text("No messages")
                    .center(.vertically)
                    .fullScreenBackground(color: .black)
            }
            
            ScrollViewReader { scrollViewProxy in
                bodyView
                    .onAppear {
                        viewModel.scrollViewProxy = scrollViewProxy
                    }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isPreview {
                ChatBottomArea(focused: $focused)
            }
        }
        .toolbar {
            toolbar
        }
        .sheet(item: $viewModel.shownAlbum) { album in
            ChatViewAlbum(album: album.photos, selection: album.selection)
        }
        .onAppear(perform: viewModel.onAppear)
        .onAppear(perform: viewModel.loadMessages)
        .onDisappear(perform: viewModel.onDisappear)
        .navigationBarTitleDisplayMode(.inline)
        .environment(viewModel)
        .onChange(of: viewModel.editCustomMessage) { _, editCustomMessage in
            guard let editCustomMessage else { return }
            viewModel.setEditMessageText(from: editCustomMessage.message)
        }
        .onChange(of: viewModel.replyMessage) {
            Task {
                await viewModel.updateDraft()
            }
        }
    }
    
    var bodyView: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach($viewModel.messages) { $customMessage in
                    MessagesListItemView(customMessage: $customMessage)
                        .flipped()
                }
            }
            .overlay {
                GeometryReader { geometryProxy in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: geometryProxy.frame(in: .named(scroll))
                    )
                }
            }
        }
        .flipped()
        .coordinateSpace(name: scroll)
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.always)
        .scrollIndicators(.hidden)
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            let maxY = Int(value.maxY)
            if maxY > 670 {
                scrollOnFocus = false
                if !showScrollToBottomButton {
                    withAnimation {
                        showScrollToBottomButton = true
                    }
                }
            } else {
                scrollOnFocus = true
                if showScrollToBottomButton {
                    withAnimation {
                        showScrollToBottomButton = false
                    }
                }
            }
            
            guard Int(value.minY) > -500 else { return }
            viewModel.loadMessages()
        }
        .onReceive(nc.publisher(for: .localScrollToLastOnFocus)) { _ in scrollToLastOnFocus() }
        .onChange(of: focused) { scrollToLastOnFocus() }
        .onChange(of: viewModel.displayedImages) { scrollToLastOnFocus() }
        .onChange(of: viewModel.replyMessage) { _, reply in
            if reply == nil { scrollToLastOnFocus() } else { focused = true }
        }
        .onChange(of: viewModel.editCustomMessage) { _, edit in
            if edit == nil { scrollToLastOnFocus() } else { focused = true }
        }
        .onTapGesture { focused = false }
        .background(.black)
        .dropDestination(for: SelectedImage.self) { items, _ in
            guard viewModel.displayedImages.count < 10 else { return false }
            viewModel.displayedImages.add(contentsOf: Array(items.prefix(10 - viewModel.displayedImages.count)))
            return true
        }
        .overlay(alignment: .bottomTrailing) {
            if showScrollToBottomButton {
                scrollToBottomButton
            }
        }
    }
    
    @ViewBuilder var scrollToBottomButton: some View {
        Image(systemName: "chevron.down")
            .offset(y: 1)
            .font(.title3)
            .padding(10)
            .background(.black)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(.blue, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                if viewModel.customChat.unreadCount != 0 {
                    Circle()
                        .fill(.blue)
                        .frame(width: 16, height: 16)
                        .overlay {
                            Text("\(viewModel.customChat.unreadCount)")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.5)
                        }
                        .offset(y: -5)
                }
            }
            .transition(.move(edge: .bottom).combined(with: .scale).combined(with: .opacity))
            .padding(.trailing)
            .padding(.bottom, 5)
            .onTapGesture(perform: viewModel.scrollToLast)
    }
    
    func scrollToLastOnFocus() {
        guard scrollOnFocus else { return }
        viewModel.scrollToLast()
    }
}
