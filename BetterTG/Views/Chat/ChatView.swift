// ChatView.swift

import SwiftUI
import TDLibKit

struct ChatView: View {
    
    @StateObject var viewModel: ChatViewModel
    @State var isPreview: Bool
    
    @FocusState var focused
    @State var showPicker = false
    
    @State var isScrollToBottomButtonShown = false
    
    let scroll = "chatScroll"
    @State private var scrollOnFocus = true
    
    @Environment(\.dismiss) var dismiss
    
    @EnvironmentObject var rootViewModel: RootViewModel
    
    init(customChat: CustomChat, isPreview: Bool = false) {
        self._viewModel = StateObject(wrappedValue: ChatViewModel(customChat: customChat))
        self._isPreview = State(initialValue: isPreview)
    }
    
    @ViewBuilder var messagesPlaceholder: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                messagesList(CustomMessage.placeholder(), redacted: true)
                    .redacted(reason: .placeholder)
            }
        }
        .flippedUpsideDown()
        .scrollDisabled(true)
        .background(.black)
    }
    
    var body: some View {
        Group {
            if viewModel.initLoadingMessages, viewModel.messages.isEmpty {
                messagesPlaceholder
            } else if !viewModel.initLoadingMessages, viewModel.messages.isEmpty {
                Text("No messages")
                    .center(.vertically)
                    .fullScreenBackground(color: .black)
            } else {
                bodyView
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isPreview {
                ChatBottomArea(focused: $focused)
                    .if(viewModel.initLoadingMessages) {
                        $0.redacted(reason: .placeholder)
                    }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                principal
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                chatPhoto
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .environmentObject(viewModel)
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
    
    @ViewBuilder var bodyView: some View {
        ScrollViewReader { scrollViewProxy in
            messagesScroll
                .coordinateSpace(name: scroll)
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    let maxY = Int(value.maxY)
                    if maxY > 800 {
                        scrollOnFocus = false
                        if isScrollToBottomButtonShown == false {
                            withAnimation {
                                isScrollToBottomButtonShown = true
                            }
                        }
                    } else {
                        scrollOnFocus = true
                        if isScrollToBottomButtonShown == true {
                            withAnimation {
                                isScrollToBottomButtonShown = false
                            }
                        }
                    }
                    
                    if viewModel.loadingMessages { return }
                    
                    let minY = Int(value.minY)
                    if minY > -1000 {
                        Task {
                            await viewModel.loadMessages()
                        }
                    }
                }
                .onReceive(nc.publisher(for: .localIsListeningVoice)) { _ in scrollToLastOnFocus() }
                .onReceive(nc.publisher(for: .localRecognizeSpeech)) { _ in scrollToLastOnFocus() }
                .onChange(of: focused) { _ in scrollToLastOnFocus() }
                .onChange(of: viewModel.messages) { _ in scrollToLastOnFocus() }
                .onChange(of: viewModel.displayedImages) { _ in scrollToLastOnFocus() }
                .onChange(of: viewModel.replyMessage) { reply in
                    if reply == nil {
                        scrollToLastOnFocus()
                    } else if reply != nil {
                        focused = true
                    }
                }
                .onChange(of: viewModel.editCustomMessage) { edit in
                    if edit == nil {
                        scrollToLastOnFocus()
                    } else if edit != nil {
                        focused = true
                    }
                }
                .onAppear {
                    viewModel.scrollViewProxy = scrollViewProxy
                }
                .onTapGesture {
                    focused = false
                }
        }
        .background(.black)
        .dropDestination(for: SelectedImage.self) { items, _ in
            viewModel.displayedImages = Array(items.prefix(10))
            return true
        }
        .overlay(alignment: .bottomTrailing) {
            if isScrollToBottomButtonShown {
                Image(systemName: "chevron.down")
                    .padding(10)
                    .background(.black)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(.blue, lineWidth: 1)
                    }
                    .padding(.trailing)
                    .padding(.bottom, 5)
                    .onTapGesture {
                        viewModel.scrollToLast()
                    }
                    .transition(.move(edge: .trailing).combined(with: .scale).combined(with: .opacity))
            }
        }
        .onDisappear {
            viewModel.mediaPlayer.stop()
            Task {
                await viewModel.updateDraft()
            }
        }
    }
    
    func scrollToLastOnFocus() {
        if scrollOnFocus {
            viewModel.scrollToLast()
        }
    }
}
