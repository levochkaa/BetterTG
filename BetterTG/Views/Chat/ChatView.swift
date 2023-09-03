// ChatView.swift

import TDLibKit

struct ChatView: View {
    
    var viewModel: ChatViewModel
    
    @FocusState var focused
    
    @State var isScrollToBottomButtonShown = false
    @State var chatPosition: Int64?
    
    var scroll = "chatScroll"
    @State var scrollOnFocus = true
    
    @Environment(\.isPreview) var isPreview
    @Environment(\.dismiss) var dismiss
    
    @Environment(RootViewModel.self) var rootViewModel
    
    init(customChat: CustomChat) {
        self.viewModel = ChatViewModel(customChat: customChat)
    }
    
    var body: some View {
        Group {
            if viewModel.customChat.lastMessage == nil {
                Text("No messages")
                    .center(.vertically)
                    .fullScreenBackground(color: .black)
            } else {
                bodyView
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
        ScrollViewReader { scrollViewProxy in
            ScrollView(showsIndicators: false) {
                ZStack {
                    // Temporary removing `Lazy`, because iOS 17 has huge problems with scroll
                    /*Lazy*/VStack(spacing: 5) {
                        ForEach(viewModel.messages) { customMessage in
                            HStack {
                                if customMessage.message.isOutgoing { Spacer() }
                                
                                MessageView(customMessage: customMessage)
                                    .frame(
                                        maxWidth: Utils.size.width * 0.8,
                                        alignment: customMessage.message.isOutgoing ? .trailing : .leading
                                    )
//                                    .onAppear {
//                                        viewModel.lastAppearedMessageId = customMessage.id
//                                    }
                                
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
                    }
                    .scrollTargetLayout()
                    
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
            .onChange(of: chatPosition) {
                Task {
                    await viewModel.loadMessages(isInit: false)
                }
            }
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                let maxY = Int(value.maxY)
                if maxY > 670 {
                    scrollOnFocus = false
                    if !isScrollToBottomButtonShown {
                        withAnimation {
                            isScrollToBottomButtonShown = true
                        }
                    }
                } else {
                    scrollOnFocus = true
                    if isScrollToBottomButtonShown {
                        withAnimation {
                            isScrollToBottomButtonShown = false
                        }
                    }
                }
            }
            .onReceive(nc.mergeMany([.localRecognizeSpeech, .localIsListeningVoice, .localScrollToLastOnFocus])) { _ in
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
            .onAppear {
                viewModel.scrollViewProxy = scrollViewProxy
            }
            .onTapGesture {
                focused = false
            }
        }
        .background(.black)
        .dropDestination(for: SelectedImage.self) { items, _ in
            guard viewModel.displayedImages.count < 10 else { return false }
            viewModel.displayedImages.add(contentsOf: Array(items.prefix(10 - viewModel.displayedImages.count)))
            return true
        }
        .onReceive(nc.publisher(for: .chatReadInbox)) { notification in
            guard let chatReadInbox = notification.object as? UpdateChatReadInbox else { return }
            viewModel.customChat.unreadCount = chatReadInbox.unreadCount
        }
        .overlay(alignment: .bottomTrailing) {
            if isScrollToBottomButtonShown {
                scrollToBottomButton
            }
        }
        .task {
            await viewModel.loadMessages(isInit: true)
        }
        .onAppear(perform: viewModel.onAppear)
        .onDisappear {
            viewModel.mediaPlayer.stop()
            Task {
                await viewModel.updateDraft()
            }
        }
    }
    
    func scrollToLastOnFocus() {
        guard scrollOnFocus else { return }
        viewModel.scrollToLast()
    }
}
