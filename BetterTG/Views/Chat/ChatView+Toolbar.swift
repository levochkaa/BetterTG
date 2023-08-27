// ChatView+Toolbar.swift

import TDLibKit

extension ChatView {
    var toolbar: some ToolbarContent {
        Group {
            ToolbarItem(placement: .principal) {
                principal
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                chatPhoto
            }
        }
    }
    
    @ViewBuilder var principal: some View {
        VStack(spacing: 0) {
            Text(viewModel.customChat.chat.title)
            
            Group {
                if viewModel.actionStatus.isEmpty {
                    Text(viewModel.onlineStatus)
                } else {
                    Text(viewModel.actionStatus)
                }
            }
            .transition(
                .asymmetric(
                    insertion: .move(edge: .top),
                    removal: .move(edge: .bottom)
                )
                .combined(with: .opacity)
            )
            .font(.caption)
            .foregroundColor(
                !viewModel.actionStatus.isEmpty || viewModel.onlineStatus == "online" ? .blue : .gray
            )
            .animation(value: viewModel.actionStatus)
            .animation(value: viewModel.onlineStatus)
        }
    }
    
    @ViewBuilder var chatPhoto: some View {
        Group {
            if let chatPhoto = viewModel.customChat.chat.photo {
                AsyncTdImage(id: chatPhoto.big.id) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .contextMenu {
                            Button("Save", systemImage: "square.and.arrow.down") {
                                guard let uiImage = UIImage(contentsOfFile: chatPhoto.big.local.path)
                                else { return }
                                UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                            }
                        } preview: {
                            image
                                .resizable()
                                .scaledToFit()
                        }
                } placeholder: {
                    PlaceholderView(
                        userId: viewModel.customChat.user.id,
                        title: viewModel.customChat.user.firstName,
                        fontSize: 20
                    )
                }
            } else {
                PlaceholderView(
                    userId: viewModel.customChat.user.id,
                    title: viewModel.customChat.user.firstName,
                    fontSize: 20
                )
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }
}
