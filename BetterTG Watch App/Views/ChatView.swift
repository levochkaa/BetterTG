// ChatView.swift

import SwiftUI
import TDLibKit

struct ChatView: View {

    @StateObject var viewModel: ChatViewVM

    @State var text = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty {
                    Text("No messages")
                }
                ForEach(viewModel.messages, id: \.id) { msg in
                    HStack {
                        if msg.isOutgoing { Spacer() }

                        message(for: msg.content)
                            .id(msg.id)
                            .padding(5)
                            .background {
                                if msg.isOutgoing {
                                    RoundedRectangle(cornerRadius: 13)
                                        .frame(minWidth: 0, maxWidth: .infinity)
                                        .foregroundColor(.blue)
                                } else {
                                    RoundedRectangle(cornerRadius: 13)
                                        .foregroundColor(.green)
                                }
                            }
                            .frame(
                                maxWidth: SystemInfo.size.width * 0.7,
                                alignment: msg.isOutgoing ? .trailing : .leading
                            )

                        if !msg.isOutgoing { Spacer() }
                    }
                }
                TextField("Message", text: $text)
                    .onSubmit {
                        if text.isEmpty { return }
                        Task {
                            try await viewModel.sendMessage(text: text)
                            text = ""
                        }
                    }
            }
            .onChange(of: viewModel.messages) { _ in
                proxy.scrollTo(viewModel.messages.last!.id, anchor: .bottom)
            }
        }
        .navigationTitle(viewModel.chat.title)
    }

    @ViewBuilder func message(for content: MessageContent) -> some View {
        Group {
            switch content {
                case let .messageText(text):
                    Text(text.text.text)
                default:
                    Text("Unsopported")
            }
        }
        .multilineTextAlignment(.leading)
    }
}
