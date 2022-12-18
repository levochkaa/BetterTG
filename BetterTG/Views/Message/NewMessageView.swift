// NewMessageView.swift

import SwiftUIX
import TDLibKit

extension View {
    func bubble(padding: CGFloat) -> some View {
        self
            .padding(padding)
            .background(Color.gray6)
            .cornerRadius(15)
    }
}

struct NewMessageView: View {
    
    @State var customMessage: CustomMessage
    
    @Binding var openedPhotoInfo: OpenedPhotoInfo?
    var openedPhotoNamespace: Namespace.ID?
    
    @EnvironmentObject var viewModel: ChatViewModel
    
    @State var replyWidth: Double = 0
    @State var textWidth: Double = 0
    @State var contentWidth: Double = 0
    @State var editWidth: Double = 0
    
    let logger = Logger(label: "MessageView")
    let nc: NotificationCenter = .default
    
    enum MessagePart {
        case reply, text, content, edit
    }
    
    func corners(for type: MessagePart) -> [RectangleCorner] {
        let isOutgoing = customMessage.message.isOutgoing
        var corners = [RectangleCorner]()
        
        switch type {
            case .reply:
                corners.append(contentsOf: [.topLeading, .topTrailing])
                
                if contentWidth != 0 && replyWidth < contentWidth {
                    //
                } else if textWidth != 0 && replyWidth < textWidth {
                    //
                }
                
                if contentWidth != 0 && replyWidth > contentWidth {
                    corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                } else if textWidth != 0 && replyWidth > textWidth {
                    corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                }
                
                return corners
            case .content:
                if replyWidth != 0 && replyWidth < contentWidth {
                    corners.append(isOutgoing ? .topLeading : .topTrailing)
                } else if replyWidth != 0 && replyWidth > contentWidth {
                    //
                } else if replyWidth == 0 {
                    corners.append(contentsOf: [.topLeading, .topTrailing])
                }
                
                if textWidth != 0 && textWidth > contentWidth {
                    //
                } else if textWidth != 0 && textWidth < contentWidth {
                    corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                } else if textWidth == 0 {
                    if editWidth == 0 {
                        corners.append(contentsOf: [.bottomLeading, .bottomTrailing])
                    } else if editWidth != 0 && editWidth > contentWidth {
                        //
                    } else if editWidth != 0 && editWidth < contentWidth {
                        corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                    }
                }
                
                return corners
            case .text:
                if contentWidth != 0 {
                    if contentWidth > textWidth {
                        //
                    } else if contentWidth < textWidth {
                        corners.append(isOutgoing ? .topLeading : .topTrailing)
                    }
                } else if replyWidth != 0 {
                    if replyWidth > textWidth {
                        //
                    } else if replyWidth < textWidth {
                        corners.append(isOutgoing ? .topLeading : .topTrailing)
                    }
                } else {
                    corners.append(contentsOf: [.topLeading, .topTrailing])
                }
                
                if editWidth != 0 {
                    if editWidth < textWidth {
                        corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                    } else if editWidth > textWidth {
                        //
                    }
                } else if editWidth == 0 {
                    corners.append(contentsOf: [.bottomLeading, .bottomTrailing])
                }
                
                return corners
            case .edit:
                corners.append(contentsOf: [.bottomLeading, .bottomTrailing])
                
                if textWidth != 0 {
                    if textWidth < editWidth {
                        corners.append(isOutgoing ? .topLeading : .topTrailing)
                    } else if textWidth > editWidth {
                        //
                    }
                } else if contentWidth != 0 {
                    if contentWidth < editWidth {
                        corners.append(isOutgoing ? .topLeading : .topTrailing)
                    } else if contentWidth > editWidth {
                        //
                    }
                }
                
                return corners
        }
    }
    
    var body: some View {
        VStack(alignment: customMessage.message.isOutgoing ? .trailing : .leading, spacing: 1) {
            if let replyUser = customMessage.replyUser, let replyToMessage = customMessage.replyToMessage {
                replyMessage(replyUser: replyUser, replyToMessage: replyToMessage)
                    .padding(5)
                    .background(.gray6)
                    .cornerRadius(corners(for: .reply), 15)
                    .frame(maxWidth: replyMaxWidth, alignment: customMessage.message.isOutgoing ? .trailing : .leading)
                    .readSize {
                        replyMaxWidth = $0.width
                        replyWidth = $0.width
                    }
            }
            
            messageContent
                .padding(1)
                .if(viewModel.highlightedMessageId == customMessage.message.id) {
                    $0.background(.white.opacity(0.5))
                } else: {
                    $0.background(.gray6)
                }
                .cornerRadius(corners(for: .content), 15)
                .readSize { contentWidth = $0.width }
            
            messageText
                .multilineTextAlignment(.leading)
                .padding(8)
                .if(viewModel.highlightedMessageId == customMessage.message.id) {
                    $0.background(.white.opacity(0.5))
                } else: {
                    $0.background(.gray6)
                }
                .cornerRadius(corners(for: .text), 15)
                .readSize { textWidth = $0.width }
            
            if customMessage.message.editDate != 0 {
                Text("edited")
                    .font(.caption)
                    .foregroundColor(.white).opacity(0.5)
                    .padding(3)
                    .background(.gray6)
                    .cornerRadius(corners(for: .edit), 15)
                    .readSize { editWidth = $0.width }
            }
        }
        .contextMenu {
            contextMenu
        }
    }
    
    @ViewBuilder func replyMessage(replyUser: User, replyToMessage: Message) -> some View {
        HStack(alignment: .center, spacing: 5) {
            Capsule()
                .fill(.white)
                .frame(width: 2, height: 30)
            
            if case let .messagePhoto(messagePhoto) = customMessage.message.content {
                makeMessagePhoto(from: messagePhoto, with: customMessage.message)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 30)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                Text(replyUser.firstName).bold()
                inlineMessageContentText(from: replyToMessage)
            }
            .font(.subheadline)
            .lineLimit(1)
        }
        .padding(.leading, 5)
        .onTapGesture {
            viewModel.scrollTo(id: replyToMessage.id)
        }
    }
    
    @ViewBuilder func inlineMessageContentText(from message: Message) -> some View {
        switch message.content {
            case let .messageText(messageText):
                Text(messageText.text.text)
            case let .messagePhoto(messagePhoto):
                Text(messagePhoto.caption.text.isEmpty ? "Photo" : messagePhoto.caption.text)
            case .messageUnsupported:
                Text("TDLib not supported")
            default:
                Text("BTG not supported")
        }
    }
    
    @ViewBuilder var messageContent: some View {
        Group {
            if !customMessage.album.isEmpty {
                MediaAlbum {
                    ForEach(customMessage.album, id: \.id) { albumMessage in
                        if case let .messagePhoto(messagePhoto) = albumMessage.content {
                            makeMessagePhoto(from: messagePhoto, with: albumMessage)
                        }
                    }
                }
            } else {
                if case let .messagePhoto(messagePhoto) = customMessage.message.content {
                    makeMessagePhoto(from: messagePhoto, with: customMessage.message)
                        .aspectRatio(contentMode: .fit)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    @ViewBuilder func makeMessagePhoto(from messagePhoto: MessagePhoto, with message: Message) -> some View {
        if let size = messagePhoto.photo.sizes.getSize(.wBox) {
            AsyncTdImage(id: size.photo.id) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .if(openedPhotoNamespace != nil) {
                        $0
                            .matchedGeometryEffect(
                                id: "\(message.id)",
                                in: openedPhotoNamespace!,
                                properties: .frame
                            )
                    }
                    .onTapGesture {
                        withAnimation {
                            hideKeyboard()
                            self.openedPhotoInfo = OpenedPhotoInfo(
                                openedPhotoMessageId: message.id,
                                openedPhoto: image
                            )
                        }
                    }
            } placeholder: {
                placeholder(with: size)
            }
            .background {
                AsyncTdImage(id: size.photo.id) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .overlay {
                            Color.clear
                                .background(.ultraThinMaterial)
                        }
                    
                } placeholder: {
                    placeholder(with: size)
                }
            }
        }
    }
    
    @ViewBuilder func placeholder(with size: PhotoSize) -> some View {
        RoundedRectangle(cornerRadius: 20)
            .background(.gray6)
            .frame(
                width: Utils.maxMessageContentWidth,
                height: Utils.maxMessageContentWidth * (
                    CGFloat(size.height) / CGFloat(size.width)
                )
            )
    }
    
    @ViewBuilder var messageText: some View {
        Group {
            switch customMessage.message.content {
                case let .messageText(messageText):
                    Text(messageText.text.text)
                case let .messagePhoto(messagePhoto):
                    if !messagePhoto.caption.text.isEmpty {
                        Text(messagePhoto.caption.text)
                    }
                case .messageUnsupported:
                    Text("TDLib not supported")
                default:
                    Text("BTG not supported")
            }
        }
    }
    
    @ViewBuilder var contextMenu: some View {
        Button {
            if viewModel.replyMessage != nil {
                withAnimation {
                    viewModel.replyMessage = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + Utils.defaultAnimationDuration + 0.05) {
                    withAnimation {
                        viewModel.replyMessage = customMessage
                    }
                }
            } else {
                withAnimation {
                    viewModel.replyMessage = customMessage
                }
            }
        } label: {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
        }
        
        if customMessage.message.canBeEdited {
            Button {
                if viewModel.editMessage != nil {
                    withAnimation {
                        viewModel.editMessage = nil
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + Utils.defaultAnimationDuration + 0.05) {
                        withAnimation {
                            viewModel.editMessage = customMessage
                            setEditMessageText()
                        }
                    }
                } else {
                    withAnimation {
                        viewModel.editMessage = customMessage
                        setEditMessageText()
                    }
                    
                }
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }
        }
        
        Divider()
        
        AsyncButton(role: .destructive) {
            await viewModel.deleteMessage(
                id: customMessage.message.id,
                deleteForBoth: false
            )
        } label: {
            Label("Delete for me", systemImage: "trash")
        }
        
        AsyncButton(role: .destructive) {
            await viewModel.deleteMessage(
                id: customMessage.message.id,
                deleteForBoth: true
            )
        } label: {
            Label("Delete for both", systemImage: "trash.fill")
        }
    }
    
    func setEditMessageText() {
        switch customMessage.message.content {
            case let .messageText(messageText):
                viewModel.editMessageText = messageText.text.text
            case let .messagePhoto(messagePhoto):
                viewModel.editMessageText = messagePhoto.caption.text
            default:
                break
        }
    }
}
