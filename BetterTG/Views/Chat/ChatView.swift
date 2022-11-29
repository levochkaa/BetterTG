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
                    if viewModel.loadingMessages {
                        return
                    }

                    let range = Range(uncheckedBounds: (lower: -500, upper: 100))
                    if range.contains(value) {
                        Task {
                            try await viewModel.loadMessages()
                        }
                    }
                }
                .onChange(of: focused) { _ in
                    guard let firstId = viewModel.messages.first?.id else {
                        return
                    }
                    withAnimation {
                        proxy.scrollTo(firstId, anchor: .bottom)
                    }
                }
                .onAppear {
                    viewModel.scrollViewProxy = proxy
                }
                .onTapGesture {
                    focused = false
                }
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
