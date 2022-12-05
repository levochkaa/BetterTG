// ChatView.swift

import SwiftUI
import TDLibKit

struct ChatView: View {
    
    @StateObject var viewModel: ChatViewVM
    
    @State var text = ""
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
                Spacer()
                Text("Loading...")
                Spacer()
            } else if viewModel.messages.isEmpty {
                VStack {
                    Spacer()
                    Text("No messages")
                    Spacer()
                }
                .safeAreaInset(edge: .bottom) {
                    textField
                }
            } else {
                bodyView
                    .safeAreaInset(edge: .bottom) {
                        textField
                    }
            }
        }
        .navigationTitle(viewModel.chat.title)
        .navigationBarTitleDisplayMode(.inline)
        
    }
    
    var bodyView: some View {
        ScrollViewReader { scrollViewProxy in
            messagesList
                .coordinateSpace(name: scroll)
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    let maxY = Int(value.maxY)
                    if maxY > 800 {
                        if viewModel.isScrollToBottomButtonShown == false {
                            viewModel.isScrollToBottomButtonShown = true
                        }
                    } else {
                        if viewModel.isScrollToBottomButtonShown == true {
                            viewModel.isScrollToBottomButtonShown = false
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
                .onAppear {
                    viewModel.scrollViewProxy = scrollViewProxy
                }
                .onTapGesture {
                    focused = false
                }
        }
        .overlay(alignment: .bottomTrailing) {
            Group {
                if viewModel.isScrollToBottomButtonShown {
                    scrollToBottomButton
                        .transition(.move(edge: .trailing))
                } else {
                    scrollToBottomButton
                        .offset(x: 60)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.default, value: viewModel.isScrollToBottomButtonShown)
        }
    }
    
    func sendMessage() {
        if text.isEmpty { return }
        Task {
            try await viewModel.sendMessage(text: text)
            text = ""
        }
    }
}
