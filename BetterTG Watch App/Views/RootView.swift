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
            List(viewModel.mainChats, id: \.id) { chat in
                HStack {
                    if chat.photo != nil {
                        AsyncTdImage(id: chat.photo!.small.id) { image in
                            image
                                .resizable()
                                .scaledToFit()
                                .clipShape(Circle())
                                .frame(width: 40, height: 40)
//                                .interpolation(.medium)
//                                .antialiased(true)
                        } placeholder: {
                            Circle()
                                .frame(width: 40, height: 40)
                        }
                    } else {
                        Circle()
                            .frame(width: 40, height: 40)
                    }

                    VStack {
                        Text(chat.title)
                            .lineLimit(1)
                            .font(.body)

                        Group {
                            switch chat.lastMessage?.content {
                                case let .messageText(text):
                                    Text(text.text.text)
                                case .messageAudio(_):
                                    Text("Audio")
                                case .messagePhoto(_):
                                    Text("Photo")
                                case .messageUnsupported:
                                    Text("Unsupported TDLib")
                                default:
                                    Text("Not supported")
                            }
                        }
                        .lineLimit(1)
                        .font(.caption)
                        .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("BetterTG")
        }
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
    }
}
