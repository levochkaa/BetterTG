// ChatView.swift

import SwiftUI
import TDLibKit

struct ChatView: View {
    
    let chat: Chat
    
    @StateObject var viewModel: ChatViewVM
    
    @State var text = ""
    
    let tdApi: TdApi = .shared
    
    init(for chat: Chat) {
        self.chat = chat
        self._viewModel = StateObject(wrappedValue: ChatViewVM(chat: chat))
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty {
                    Text("No messages")
                }
                
                ForEach(viewModel.messages, id: \.id) { msg in
                    HStack {
                        if msg.isOutgoing { Spacer() }
                        
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
                        
                        if !msg.isOutgoing { Spacer() }
                    }
                    .padding(msg.isOutgoing ? .trailing : .leading)
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
        .navigationBarTitleDisplayMode(.inline)
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
