// ChatView.swift

import Combine
import PhotosUI
import SwiftUI
import TDLibKit

struct ChatView: View {
    // MARK: Lifecycle

    init(customChat: CustomChat) {
        self._chatVM = State(wrappedValue: ChatVM(customChat: customChat))
    }
    
    // MARK: Internal

    @Environment(\.isPreview) var isPreview
    @Environment(\.dismiss) var dismiss
    
    @FocusState var focused
    
    @State var chatVM: ChatVM
    
    var body: some View {
        ScrollViewReader { scrollViewProxy in
            bodyView.onAppear { chatVM.scrollViewProxy = scrollViewProxy }
        }
        .ignoresSafeArea(.container)
        .overlay {
            if chatVM.customChat.lastMessage == nil {
                Text("No messages")
                    .frame(maxHeight: .infinity)
                    .background(.black)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isPreview, chatVM.customChat.canPostMessages {
                ChatBottomArea(focused: $focused)
                    .readSize { chatVM.bottomAreaHeight = $0.height }
            }
        }
        .dropDestination(for: SelectedImage.self) { items, _ in
            nc.post(name: .localOnSelectedImagesDrop, object: Array(items.prefix(10)))
            return true
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHeight($navigationBarHeight)
        .toolbar {
            ToolbarItem(placement: .principal) { principal }
            ToolbarItem(placement: .topBarTrailing) { topBarTrailing }
        }
        .environment(chatVM)
        .onChange(of: focused) { chatVM.focused = focused }
    }
    
    var bodyView: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(chatVM.messages) { customMessage in
                    HStack(alignment: .bottom, spacing: 0) {
                        if customMessage.message.isOutgoing { Spacer(minLength: 0) } else {
                            if let user = customMessage.senderUser,
                               chatVM.customChat.shouldShowProfileImage,
                               let index = chatVM.messages.firstIndex(of: customMessage)
                            {
                                if chatVM.messages[safe: index - 1]?.senderUser?.id != user.id {
                                    ProfileImageView(
                                        photo: user.profilePhoto?.big,
                                        minithumbnail: user.profilePhoto?.minithumbnail,
                                        title: user.firstName,
                                        userId: user.id,
                                    )
                                    .frame(width: 32, height: 32)
                                } else {
                                    Spacer()
                                        .frame(width: 32, height: 32)
                                }
                                Spacer()
                                    .frame(width: 5)
                            }
                        }
                        
                        MessageView(customMessage: customMessage)
                            .frame(
                                maxWidth: Utils.maxMessageContentWidth,
                                alignment: customMessage.message.isOutgoing ? .trailing : .leading,
                            )
                            .onScrollVisibilityChange { visible in
                                guard !isPreview, visible else { return }
                                chatVM.viewMessage(id: customMessage.message.id)
                            }
                        
                        if !customMessage.message.isOutgoing { Spacer(minLength: 0) }
                    }
                    .padding(customMessage.message.isOutgoing ? .trailing : .leading, 16)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top),
                            removal: .move(edge: customMessage.message.isOutgoing ? .trailing : .leading),
                        )
                        .combined(with: .opacity),
                    )
                    .flipped()
                }
            }
            .padding(.top, chatVM.extraBottomPadding)
            .readOffset(in: .named(chatVM.chatScrollNamespaceId), onChange: chatVM.onPreferenceChange)
        }
        .background(.black)
        .flipped()
        .coordinateSpace(name: chatVM.chatScrollNamespaceId)
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.always)
        .scrollIndicators(.hidden)
        .scrollEdgeEffectHidden(true, for: .all)
        .onTapGesture { focused = false }
        .animation(.default, value: chatVM.extraBottomPadding)
        .overlay(alignment: .bottomTrailing) {
            if chatVM.showScrollToBottomButton {
                scrollToBottomButton
                    .padding(.bottom, chatVM.extraBottomPadding)
            }
        }
        .overlay(alignment: .top) {
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: topGradientHeight)
        }
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.black, .clear], startPoint: .bottom, endPoint: .top)
                .frame(height: bottomGradientHeight)
        }
    }
    
    var scrollToBottomButton: some View {
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
            .onTapGesture(perform: chatVM.scrollToLast)
    }
    
    // MARK: Private

    @State private var navigationBarHeight = CGFloat.zero

    private var topGradientHeight: CGFloat {
        UIApplication.safeAreaInsets.top + navigationBarHeight
    }

    private var bottomGradientHeight: CGFloat {
        UIApplication.safeAreaInsets.bottom + chatVM.bottomAreaHeight
    }

    private var principal: some View {
        VStack(spacing: 0) {
            Text(chatVM.customChat.chat.title)
            
            Group {
                if !chatVM.actionStatus.isEmpty {
                    Text(chatVM.actionStatus)
                } else if !chatVM.onlineStatus.isEmpty {
                    Text(chatVM.onlineStatus)
                }
            }
            .transition(
                .asymmetric(
                    insertion: .move(edge: .top),
                    removal: .move(edge: .bottom),
                )
                .combined(with: .opacity),
            )
            .font(.caption)
            .foregroundStyle(!chatVM.actionStatus.isEmpty || chatVM.onlineStatus == "online" ? .blue : .gray)
        }
        .frame(minWidth: Utils.screen.bounds.width * 0.5)
        .padding(.horizontal, 12)
        .frame(height: 44)
        .glassEffect(.regular.interactive())
    }
    
    @ViewBuilder private var topBarTrailing: some View {
        let chat = chatVM.customChat.chat
        ProfileImageView(
            photo: chat.photo?.big,
            minithumbnail: chat.photo?.minithumbnail,
            title: chat.title,
            userId: chat.id,
        )
        .frame(width: 32, height: 32)
    }
}
