// ChatView.swift

import SwiftUI
import TDLibKit

struct ChatView: View {

    @StateObject var viewModel: ChatViewVM

    @State var text = ""

    let tempChat: Chat

    init(chat: Chat) {
        self.tempChat = chat
        self._viewModel = StateObject(wrappedValue: ChatViewVM(chat: chat))
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
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
                            .frame(maxWidth: SystemInfo.size.width * 0.7, alignment: msg.isOutgoing ? .trailing : .leading)

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
            .onChange(of: viewModel.messages) { newValue in
                proxy.scrollTo(viewModel.messages.last!.id, anchor: .bottom)
            }
            //        .onAppear {
            //            proxy.scrollTo(viewModel.messages.last!.id)
            //        }
        }
        .navigationTitle(tempChat.title)
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
