// ChatView+Body.swift

import SwiftUI
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
                .onChange(of: focused) { _ in scrollToLastOnFocus() }
                .onChange(of: viewModel.messages) { _ in scrollToLastOnFocus() }
                .onChange(of: viewModel.displayedImages) { _ in scrollToLastOnFocus() }
                .onChange(of: viewModel.replyMessage) { reply in
                    if reply == nil { scrollToLastOnFocus() } else { focused = true }
                }
                .onChange(of: viewModel.editCustomMessage) { edit in
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
                                        .foregroundColor(.white)
                                        .minimumScaleFactor(0.5)
                                }
                                .offset(y: -5)
                        }
                    }
                    .padding(.trailing)
                    .padding(.bottom, 5)
                    .onTapGesture {
                        viewModel.scrollToLast()
                    }
                    .transition(.move(edge: .bottom).combined(with: .scale).combined(with: .opacity))
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
