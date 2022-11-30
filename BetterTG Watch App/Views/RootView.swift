// RootView.swift

import SwiftUI
import TDLibKit

struct RootView: View {
    
    @StateObject private var viewModel = RootViewVM()
    
    var body: some View {
        if let loggedIn = viewModel.loggedIn {
            if loggedIn {
                bodyView
            } else {
                LoginView()
            }
        } else {
            Text("Loading")
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
                ChatView(for: chat)
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
            case let .messageText(messageText):
                Text(messageText.text.text)
            case .messageUnsupported:
                Text("TDLib not supported")
            default:
                Text("BTG not supported")
        }
    }
    
    @ViewBuilder func chatListView(for chat: Chat) -> some View {
        HStack {
            if let photo = chat.photo {
                AsyncTdImage(id: photo.small.id) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(Circle())
                        .frame(width: 40, height: 40)
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
