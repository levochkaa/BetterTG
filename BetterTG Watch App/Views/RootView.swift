// RootView.swift

import SwiftUI
import TDLibKit

struct RootView: View {

    @StateObject private var viewModel = RootViewVM()

    var body: some View {
        if viewModel.loggedIn {
            bodyView
        } else {
            LoginView(rootVM: viewModel)
        }
    }

    @ViewBuilder var bodyView: some View {
        NavigationStack {
            mainChatsListView
                .navigationTitle("BetterTG")
        }
    }

    @ViewBuilder var mainChatsListView: some View {
        List(viewModel.mainChats, id: \.id) { chat in
            NavigationLink {
                ChatView(viewModel: ChatViewVM(chat: chat))
            } label: {
                chatListView(for: chat)
            }
        }
    }

    @ViewBuilder var placeholder: some View {
        Circle()
            .foregroundColor(.black)
            .frame(width: 40, height: 40)
    }

    @ViewBuilder func message(for content: MessageContent) -> some View {
        switch content {
            case let .messageText(text):
                Text(text.text.text)
            case .messageAudio(_):
                Text("Audio")
            case .messagePhoto(_):
                Text("Photo")
            case .messageUnsupported:
                Text("TDLib not supported")
            default:
                Text("BTG not supported")
        }
    }

    @ViewBuilder func chatListView(for chat: Chat) -> some View {
        HStack {
            if chat.photo != nil {
                AsyncTdImage(id: chat.photo!.small.id) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(Circle())
                        .frame(width: 40, height: 40)
//                        .interpolation(.medium)
//                        .antialiased(true)
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }

            VStack {
                Text(chat.title)
                    .lineLimit(1)
                    .font(.body)

                if let lastMessage = chat.lastMessage {
                    message(for: lastMessage.content)
                        .lineLimit(1)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
    }
}
