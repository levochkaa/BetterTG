// ChatToolbar.swift

import SwiftUI
import TDLibKit

struct ChatToolbar: ViewModifier {
    @Binding var customChat: CustomChat
    
    @State private var actionStatus = ""
    @State private var onlineStatus = ""
    
    init(customChat: Binding<CustomChat>) {
        self._customChat = customChat
        self._onlineStatus = State(initialValue: updateUserStatus(customChat.wrappedValue.user.status))
    }
    
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .principal) {
                    principal
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    topBarTrailing
                }
            }
            .onReceive(nc.publisher(for: .updateUserStatus)) { notification in
                guard let updateUserStatus = notification.object as? UpdateUserStatus,
                      updateUserStatus.userId == customChat.chat.id
                else { return }
                onlineStatus = self.updateUserStatus(updateUserStatus.status)
            }
            .onReceive(nc.publisher(for: .updateChatAction)) { notification in
                guard let updateChatAction = notification.object as? UpdateChatAction,
                      updateChatAction.chatId == customChat.chat.id
                else { return }
                self.updateChatAction(updateChatAction)
            }
    }
    
    private var principal: some View {
        VStack(spacing: 0) {
            Text(customChat.chat.title)
            
            Group {
                if actionStatus.isEmpty {
                    Text(onlineStatus)
                } else {
                    Text(actionStatus)
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
            .foregroundStyle(!actionStatus.isEmpty || onlineStatus == "online" ? .blue : .gray)
        }
    }
    
    private var topBarTrailing: some View {
        ZStack {
            if let chatPhoto = customChat.chat.photo {
                AsyncTdImage(id: chatPhoto.big.id) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .contentShape(.contextMenuPreview, Circle())
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
                    PlaceholderView(customChat: $customChat, fontSize: 20)
                }
            } else {
                PlaceholderView(customChat: $customChat, fontSize: 20)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }
    
    private func updateUserStatus(_ userStatus: UserStatus) -> String {
        switch userStatus {
            case .userStatusEmpty: "empty"
            case .userStatusOnline: /* (let userStatusOnline) */ "online"
            case .userStatusOffline(let userStatusOffline): "last seen \(getLastSeenTime(userStatusOffline.wasOnline))"
            case .userStatusRecently: "last seen recently"
            case .userStatusLastWeek: "last seen last week"
            case .userStatusLastMonth: "last seen last month"
        }
    }
    
    private func getLastSeenTime(_ time: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(time))
        let dateFormatter = DateFormatter()
        
        let difference = Date().timeIntervalSince1970 - TimeInterval(time)
        if difference < 60 {
            return "now"
        } else if difference < 60 * 60 {
            return "\(Int(difference / 60)) minutes ago"
        } else if difference < 60 * 60 * 24 {
            return "\(Int(difference / 60 / 60)) hours ago"
        } else if difference < 60 * 60 * 24 * 2 {
            dateFormatter.dateFormat = "HH:mm"
            return "yesterday at \(dateFormatter.string(from: date))"
        } else {
            dateFormatter.dateFormat = "dd.MM.yy"
            return dateFormatter.string(from: date)
        }
    }
    
    private func updateChatAction(_ updateChatAction: UpdateChatAction) {
        guard case .messageSenderUser(let messageSenderUser) = updateChatAction.senderId,
              messageSenderUser.userId == customChat.chat.id
        else { return }
        let actionStatus = switch updateChatAction.action {
            case .chatActionTyping: "typing..."
            case .chatActionRecordingVideo: "recording video..."
            case .chatActionUploadingVideo: /* (let chatActionUploadingVideo) */ "uploading video..."
            case .chatActionRecordingVoiceNote: "recording voice note..."
            case .chatActionUploadingVoiceNote: /* (let chatActionUploadingVoiceNote) */ "uploading voice note..."
            case .chatActionUploadingPhoto: /* (let chatActionUploadingPhoto) */ "uploading photo..."
            case .chatActionUploadingDocument: /* (let chatActionUploadingDocument) */ "uploading voice document..."
            case .chatActionChoosingSticker: "choosing sticker..."
            case .chatActionChoosingLocation: "choosing location..."
            case .chatActionChoosingContact: "choosing contact..."
            case .chatActionStartPlayingGame: "playing game..."
            case .chatActionRecordingVideoNote: "recording video note..."
            case .chatActionUploadingVideoNote: /* (let chatActionUploadingVideoNote) */ "uploading video note..."
            case .chatActionWatchingAnimations(let watching): "watching animations...\(watching.emoji)"
            case .chatActionCancel: ""
        }
        withAnimation { self.actionStatus = actionStatus }
    }
}
