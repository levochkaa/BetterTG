// ChatView.swift

import SwiftUI
import TDLibKit

struct ChatView: View {
    
    @StateObject var viewModel: ChatViewVM
    
    @FocusState var focused
    
    let scroll = "chatScroll"
    
    let tdApi: TdApi = .shared
    let logger = Logger(label: "ChatView")
    
    init(chat: Chat) {
        self._viewModel = StateObject(wrappedValue: ChatViewVM(chat: chat))
    }
    
    var body: some View {
        Group {
            if viewModel.initLoadingMessages {
                VStack {
                    Spacer()
                    Text("Loading...")
                    Spacer()
                }
            } else if viewModel.messages.isEmpty {
                VStack {
                    Spacer()
                    Text("No messages")
                    Spacer()
                }
            } else {
                bodyView
            }
        }
        .navigationTitle(viewModel.chat.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            bottomArea
        }
        
    }
    
    var bodyView: some View {
        ScrollViewReader { scrollViewProxy in
            messagesList
                .coordinateSpace(name: scroll)
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    let maxY = Int(value.maxY)
                    if maxY > 800 {
                        if viewModel.isScrollToBottomButtonShown == false {
                            withAnimation {
                                viewModel.isScrollToBottomButtonShown = true
                            }
                        }
                    } else {
                        if viewModel.isScrollToBottomButtonShown == true {
                            withAnimation {
                                viewModel.isScrollToBottomButtonShown = false
                            }
                        }
                    }
                }
                .onChange(of: focused) { _ in
                    if focused {
                        guard let lastId = viewModel.messages.last?.id else { return }
                        withAnimation {
                            scrollViewProxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.replyMessage) { _ in
                    guard let lastId = viewModel.messages.last?.message.id else { return }
                    withAnimation {
                        viewModel.scrollViewProxy?.scrollTo(lastId, anchor: .bottom)
                    }
                }
                .onAppear {
                    viewModel.scrollViewProxy = scrollViewProxy
                }
                .onTapGesture {
                    focused = false
                }
        }
        .overlay(alignment: .bottomTrailing) {
            if viewModel.isScrollToBottomButtonShown {
                scrollToBottomButton
                    .transition(.move(edge: .trailing))
            }
        }
    }
}
