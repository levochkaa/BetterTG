// ChatView.swift

import SwiftUI
import TDLibKit

struct ChatView: View {

    let chat: Chat

    @StateObject var viewModel: ChatViewVM

    @State var text = ""
    @FocusState var focused

    let tdApi: TdApi = .shared
    let logger = Logger(label: "ChatView")

    private let lastMessage = "lastMessage"

    init(for chat: Chat) {
        self.chat = chat
        self._viewModel = StateObject(wrappedValue: ChatViewVM(chat: chat))
    }

    var body: some View {
        VStack {
            if viewModel.messages.isEmpty {
                Text("No messages")
            } else {
                bodyView
            }
        }
            .task {
                do {
                    try await viewModel.update()
                } catch {
                    guard let tdError = error as? TDLibKit.Error else {
                        return
                    }
                    logger.log(tdError)
                }
            }
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
                                .id(msg.id)
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
                            .padding(msg.isOutgoing ? .trailing : .leading)
                    }
                }
                    .id(lastMessage)
                    .onChange(of: viewModel.messages) { _ in
                        proxy.scrollTo(lastMessage, anchor: .bottom)
                    }
            }
                .onAppear {
                    proxy.scrollTo("lastMessage", anchor: .bottom)
                }
                .onTapGesture {
                    focused = false
                }
        }
            .navigationTitle(viewModel.chat.title)
            .safeAreaInset(edge: .bottom) {
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
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
                    .padding(.bottom, 5)
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
