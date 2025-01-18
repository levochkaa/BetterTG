// ChatView.swift

import SwiftUI
import TDLibKit
import PhotosUI
import Combine

struct ChatView: View {
    @State var chatVM: ChatVM
    
    init(customChat: CustomChat) {
        self._chatVM = .init(initialValue: .init(customChat: customChat))
    }
    
    @FocusState var focused
    
    @Environment(\.isPreview) var isPreview
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollViewReader { scrollViewProxy in
            bodyView.onAppear { self.chatVM.scrollViewProxy = scrollViewProxy }
        }
        .overlay {
            if chatVM.customChat.lastMessage == nil {
                Text("No messages")
                    .center(.vertically)
                    .fullScreenBackground(color: .black)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isPreview {
                ChatBottomArea(focused: $focused)
            }
        }
        .dropDestination(for: SelectedImage.self) { items, _ in
            nc.post(name: .localOnSelectedImagesDrop, object: Array(items.prefix(10)))
            return true
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { principal }
            ToolbarItem(placement: .topBarTrailing) { topBarTrailing }
        }
        .environment(chatVM)
    }
    
    private var principal: some View {
        VStack(spacing: 0) {
            Text(chatVM.customChat.chat.title)
            
            Group {
                if chatVM.actionStatus.isEmpty {
                    Text(chatVM.onlineStatus)
                } else {
                    Text(chatVM.actionStatus)
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
            .foregroundStyle(!chatVM.actionStatus.isEmpty || chatVM.onlineStatus == "online" ? .blue : .gray)
        }
    }
    
    private var topBarTrailing: some View {
        ZStack {
            if let chatPhoto = chatVM.customChat.chat.photo {
                AsyncTdImage(id: chatPhoto.big.id) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .contentShape(.contextMenuPreview, Circle())
                        .contextMenu {
                            Button("Save", systemImage: "square.and.arrow.down") {
                                guard let uiImage = UIImage(contentsOfFile: chatPhoto.big.local.path) else { return }
                                UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                            }
                        } preview: {
                            image
                                .resizable()
                                .scaledToFit()
                        }
                } placeholder: {
                    PlaceholderView(customChat: chatVM.customChat, fontSize: 20)
                }
            } else {
                PlaceholderView(customChat: chatVM.customChat, fontSize: 20)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(.circle)
    }
    
    var bodyView: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(chatVM.messages) { customMessage in
                    HStack(spacing: 0) {
                        if customMessage.message.isOutgoing { Spacer(minLength: 0) }
                        
                        MessageView(customMessage: customMessage)
                            .frame(
                                maxWidth: Utils.maxMessageContentWidth,
                                alignment: customMessage.message.isOutgoing ? .trailing : .leading
                            )
                            .onVisible {
                                chatVM.viewMessage(id: customMessage.message.id)
                            }
                        
                        if !customMessage.message.isOutgoing { Spacer(minLength: 0) }
                    }
                    .padding(customMessage.message.isOutgoing ? .trailing : .leading, 16)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top),
                            removal: .move(edge: customMessage.message.isOutgoing ? .trailing : .leading)
                        )
                        .combined(with: .opacity)
                    )
                    .flipped()
                }
            }
            .overlay {
                GeometryReader { geometryProxy in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: geometryProxy.frame(in: .named(chatVM.chatScrollNamespaceId))
                    )
                }
            }
        }
        .background(.black)
        .flipped()
        .coordinateSpace(name: chatVM.chatScrollNamespaceId)
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.always)
        .scrollIndicators(.hidden)
        .onPreferenceChange(ScrollOffsetPreferenceKey.self, perform: chatVM.onPreferenceChange)
        .onTapGesture { focused = false }
        .overlay(alignment: .bottomTrailing) {
            if chatVM.showScrollToBottomButton {
                scrollToBottomButton
            }
        }
    }
    
    @ViewBuilder var scrollToBottomButton: some View {
        Image(systemName: "chevron.down")
            .offset(y: 1)
            .font(.title3)
            .padding(10)
            .background(.black)
            .clipShape(.circle)
            .overlay {
                Circle()
                    .stroke(.blue, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                if chatVM.customChat.unreadCount != 0 {
                    Circle()
                        .fill(.blue)
                        .frame(width: 16, height: 16)
                        .overlay {
                            Text("\(chatVM.customChat.unreadCount)")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.5)
                        }
                        .offset(y: -5)
                }
            }
            .transition(.move(edge: .bottom).combined(with: .scale).combined(with: .opacity))
            .padding(.trailing)
            .padding(.bottom, 5)
            .onTapGesture(perform: chatVM.scrollToLast)
    }
}
