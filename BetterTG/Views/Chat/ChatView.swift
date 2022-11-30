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
            if viewModel.messages.isEmpty {
                Text("No messages")
            } else {
                bodyView
            }
        }
        .navigationTitle(viewModel.chat.title)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    var bodyView: some View {
        ScrollViewReader { proxy in
            listOfMessages
                .coordinateSpace(name: scroll)
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    let maxY = Int(value.maxY)
                    if maxY > 672 { // 672 - lowest number of the scroll
                        if viewModel.isScrollToBottomButtonShown == false {
                            viewModel.isScrollToBottomButtonShown = true
                        }
                    } else {
                        if viewModel.isScrollToBottomButtonShown == true {
                            viewModel.isScrollToBottomButtonShown = false
                        }
                    }
                    
                    if viewModel.loadingMessages {
                        return
                    }
                    
                    let minY = Int(value.minY)
                    
                    let range = Range(uncheckedBounds: (lower: -500, upper: 100))
                    if range.contains(minY) {
                        Task {
                            try await viewModel.loadMessages()
                        }
                    }
                }
                .onChange(of: focused) { _ in
                    if focused {
                        guard let firstId = viewModel.messages.first?.message.id else {
                            return
                        }
                        withAnimation {
                            proxy.scrollTo(firstId, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    viewModel.scrollViewProxy = proxy
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
        .safeAreaInset(edge: .bottom) {
            textField
        }
        
    }
    
    func sendMessage() {
        if text.isEmpty {
            return
        }
        Task {
            try await viewModel.sendMessage(text: text)
            text = ""
        }
    }
}
