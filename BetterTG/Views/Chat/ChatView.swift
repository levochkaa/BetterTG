// ChatView.swift

import SwiftUI
import TDLibKit

struct ChatView: View {
    
    @StateObject var viewModel: ChatViewModel
    @State var isPreview: Bool
    
    @Binding var openedPhotoInfo: OpenedPhotoInfo?
    var rootNamespace: Namespace.ID?
    
    @FocusState var focused
    @State var showPicker = false
    
    @State var isScrollToBottomButtonShown = false
    
    let scroll = "chatScroll"
    @State private var scrollOnFocus = true
    
    init(customChat: CustomChat,
         isPreview: Bool = false,
         openedPhotoInfo: Binding<OpenedPhotoInfo?>? = nil,
         rootNamespace: Namespace.ID? = nil
    ) {
        self._viewModel = StateObject(wrappedValue: ChatViewModel(customChat: customChat))
        self._isPreview = State(initialValue: isPreview)
        self.rootNamespace = rootNamespace
        
        if let openedPhotoInfo {
            self._openedPhotoInfo = Binding(projectedValue: openedPhotoInfo)
        } else {
            self._openedPhotoInfo = Binding(get: { nil }, set: { _ in })
        }
    }
    
    var body: some View {
        Group {
            if viewModel.initLoadingMessages {
                Text("Loading...")
                    .center(.vertically)
                    .fullScreenBackground(color: .black)
            } else if viewModel.messages.isEmpty {
                Text("No messages")
                    .center(.vertically)
                    .fullScreenBackground(color: .black)
                    .safeAreaInset(edge: .bottom) {
                        Group {
                            if !isPreview {
                                ChatBottomArea(
                                    focused: $focused,
                                    openedPhotoInfo: $openedPhotoInfo,
                                    rootNamespace: rootNamespace
                                )
                            }
                        }
                    }
            } else {
                bodyView
                    .safeAreaInset(edge: .bottom) {
                        Group {
                            if !isPreview {
                                ChatBottomArea(
                                    focused: $focused,
                                    openedPhotoInfo: $openedPhotoInfo,
                                    rootNamespace: rootNamespace
                                )
                            }
                        }
                    }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
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
                    .animation(.default, value: viewModel.actionStatus)
                    .animation(.default, value: viewModel.onlineStatus)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Group {
                    if let chatPhoto = viewModel.customChat.chat.photo {
                        Image(file: chatPhoto.small)
                            .resizable()
                            .scaledToFit()
                            .equatable(by: viewModel.customChat.chat.photo)
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
        .navigationBarTitleDisplayMode(.inline)
        .environmentObject(viewModel)
    }
    
    var bodyView: some View {
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
                .onReceive(nc.publisher(for: .customIsListeningVoice)) { _ in scrollToLastOnFocus() }
                .onReceive(nc.publisher(for: .customRecognizeSpeech)) { _ in scrollToLastOnFocus() }
                .onChange(of: focused) { _ in scrollToLastOnFocus() }
                .onChange(of: viewModel.messages) { _ in scrollToLastOnFocus() }
                .onChange(of: viewModel.displayedPhotos) { _ in scrollToLastOnFocus() }
                .onChange(of: viewModel.replyMessage) { reply in
                    if reply == nil {
                        scrollToLastOnFocus()
                    } else if reply != nil {
                        focused = true
                    }
                }
                .onChange(of: viewModel.editMessage) { edit in
                    if edit == nil {
                        scrollToLastOnFocus()
                    } else if edit != nil {
                        focused = true
                    }
                }
                .onChange(of: viewModel.text) { text in
                    if text.isEmpty {
                        viewModel.bottomAreaState = .voice
                    } else if viewModel.bottomAreaState == .voice {
                        viewModel.bottomAreaState = .message
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
                    .transition(.move(edge: .trailing))
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
