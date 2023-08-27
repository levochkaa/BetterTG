// ChatView+Body.swift

import TDLibKit

extension ChatView {
    @ViewBuilder var bodyView: some View {
        ScrollViewReader { scrollViewProxy in
            messagesScroll
                .coordinateSpace(name: scroll)
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    let maxY = Int(value.maxY)
                    if maxY > 800 {
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
                    
                    if viewModel.loadingMessages { return }
                    
                    let minY = Int(value.minY)
                    if minY > -1000 {
                        Task {
                            await viewModel.loadMessages()
                        }
                    }
                }
                .onReceive(nc.mergeMany([.localRecognizeSpeech, .localIsListeningVoice])) { _ in scrollToLastOnFocus() }
                .onChange(of: focused) { scrollToLastOnFocus() }
                .onChange(of: viewModel.messages) { scrollToLastOnFocus() }
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
            viewModel.displayedImages = Array(items.prefix(10))
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
        .onDisappear {
            viewModel.mediaPlayer.stop()
            Task {
                await viewModel.updateDraft()
            }
        }
    }
}
