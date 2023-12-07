// ChatView.swift

import SwiftUI
import TDLibKit

struct ChatView: View {
    @State var viewModel: ChatViewModel
    
    @FocusState var focused
    
    @State var chatPosition: UUID?
    
    let scroll = "chatScroll"
    @State var scrollOnFocus = true
    @State var showScrollToBottomButton = false
    
    @Environment(\.isPreview) var isPreview
    @Environment(\.dismiss) var dismiss
    
    @Environment(RootViewModel.self) var rootViewModel
    
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
                ForEach(viewModel.messages) { customMessage in
                    itemView(for: customMessage)
                }
            }
            .scrollTargetLayout()
            .overlay {
                GeometryReader { geometryProxy in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: geometryProxy.frame(in: .named(scroll))
                    )
                }
            }
        }
        .scrollPosition(id: $chatPosition, anchor: .top)
        .coordinateSpace(name: scroll)
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.always)
        .defaultScrollAnchor(.bottom)
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
            
            let minY = abs(Int(value.minY))
            guard !viewModel.loadingMessages, viewModel.loadingMessagesTask == nil,
                  minY != 0, minY < 500
            else { return }
            viewModel.loadMessages()
        }
        .onReceive(nc.publisher(for: .localScrollToLastOnFocus)) { _ in
            scrollToLastOnFocus()
        }
        .onChange(of: focused) { scrollToLastOnFocus() }
        .onChange(of: viewModel.displayedImages) { scrollToLastOnFocus() }
        .onChange(of: viewModel.replyMessage) { _, reply in
            if reply == nil { scrollToLastOnFocus() } else { focused = true }
        }
        .onChange(of: viewModel.editCustomMessage) { _, edit in
            if edit == nil { scrollToLastOnFocus() } else { focused = true }
        }
        .onTapGesture {
            focused = false
        }
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
    
    func itemView(for customMessage: CustomMessage) -> some View {
        HStack {
            if customMessage.message.isOutgoing { Spacer() }
            
            MessageView(customMessage: customMessage)
                .frame(
                    maxWidth: Utils.size.width * 0.8,
                    alignment: customMessage.message.isOutgoing ? .trailing : .leading
                )
            
            if !customMessage.message.isOutgoing { Spacer() }
        }
        .padding(customMessage.message.isOutgoing ? .trailing : .leading, 16)
        .transition(
            .asymmetric(
                insertion: .move(edge: .bottom),
                removal: .move(edge: customMessage.message.isOutgoing ? .trailing : .leading)
            )
            .combined(with: .opacity)
        )
    }
    
    func scrollToLastOnFocus() {
        guard scrollOnFocus else { return }
        chatPosition = viewModel.messages.last?.id
    }
}
