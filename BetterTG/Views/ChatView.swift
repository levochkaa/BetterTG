// ChatView.swift

import SwiftUI
import TDLibKit

struct ChatView: View {

    @StateObject var viewModel: ChatViewVM

    @State var text = ""
    @FocusState var focused

    let tdApi: TdApi = .shared
    let logger = Logger(label: "ChatView")

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
            ScrollView {
                LazyVStack {
                    ForEach(viewModel.messages) { msg in
                        HStack {
                            if msg.isOutgoing {
                                Spacer()
                            }

                            message(msg)
                                .padding(8)
                                .background {
                                    if msg.isOutgoing {
                                        RoundedRectangle(cornerRadius: 20)
                                            .frame(maxWidth: .infinity)
                                            .foregroundColor(.blue)
                                    } else {
                                        RoundedRectangle(cornerRadius: 20)
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(
                                    maxWidth: SystemUtils.size.width * 0.8,
                                    alignment: msg.isOutgoing ? .trailing : .leading
                                )

                            if !msg.isOutgoing {
                                Spacer()
                            }
                        }
                            .id(msg.id)
                            .padding(msg.isOutgoing ? .trailing : .leading)
                    }
                }
            }
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    guard let lastId = viewModel.messages.last?.id else {
                        return
                    }
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
                .onChange(of: viewModel.messages) { _ in
                    guard let lastId = viewModel.messages.last?.id else {
                        return
                    }
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
                .onChange(of: focused) { _ in
                    guard let lastId = viewModel.messages.last?.id else {
                        return
                    }
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
                .onTapGesture {
                    focused = false
                }
        }
            .safeAreaInset(edge: .bottom) {
                textField
                    .padding(.bottom, 5)
            }
    }

    @ViewBuilder var textField: some View {
        HStack {
            TextField("Message", text: $text, axis: .vertical)
                .focused($focused)
                .padding(5)
                .background(Color.gray6)
                .cornerRadius(10)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.black, lineWidth: 1)
                }

            Button(action: sendMessage) {
                Image("send")
                    .resizable()
                    .clipShape(Circle())
                    .frame(width: 32, height: 32)
            }
        }
            .padding(.horizontal)
            .padding(.vertical, 5)
            .background(.bar)
            .cornerRadius(10)
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

    @ViewBuilder func message(_ msg: Message) -> some View {
        Group {
            switch msg.content {
                case let .messageText(messageText):
                    Text(messageText.text.text)
                case .messageUnsupported:
                    Text("TDLib not supported")
                default:
                    Text("BTG not supported")
            }
        }
            .multilineTextAlignment(.leading)
            .foregroundColor(msg.isOutgoing ? .white : .black)
    }
}
