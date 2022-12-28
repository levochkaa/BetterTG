// ChatView.swift

import SwiftUIX
import TDLibKit

struct ChatView: View {
    
    @StateObject var viewModel: ChatViewModel
    @State var isPreview: Bool
    
    @Binding var openedPhotoInfo: OpenedPhotoInfo?
    var openedPhotoNamespace: Namespace.ID?
    
    @FocusState var focused
    @State var showPicker = false
    
    let scroll = "chatScroll"
    @State private var scrollOnFocus = true
    
    let tdApi: TdApi = .shared
    let logger = Logger("ChatView")
    let nc: NotificationCenter = .default
    
    init(chat: Chat,
         isPreview: Bool = false,
         openedPhotoInfo: Binding<OpenedPhotoInfo?>? = nil,
         openedPhotoNamespace: Namespace.ID? = nil
    ) {
        self._viewModel = StateObject(wrappedValue: ChatViewModel(chat: chat))
        self._isPreview = State(initialValue: isPreview)
        
        if let openedPhotoInfo {
            self._openedPhotoInfo = Binding(projectedValue: openedPhotoInfo)
        } else {
            self._openedPhotoInfo = Binding(get: { nil }, set: { _ in })
        }
        self.openedPhotoNamespace = openedPhotoNamespace
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
                                    openedPhotoNamespace: openedPhotoNamespace
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
                                    openedPhotoNamespace: openedPhotoNamespace
                                )
                            }
                        }
                    }
            }
        }
        .navigationTitle(viewModel.chat.title)
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
                        if viewModel.isScrollToBottomButtonShown == false {
                            withAnimation {
                                viewModel.isScrollToBottomButtonShown = true
                            }
                        }
                    } else {
                        scrollOnFocus = true
                        if viewModel.isScrollToBottomButtonShown == true {
                            withAnimation {
                                viewModel.isScrollToBottomButtonShown = false
                            }
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
            if viewModel.isScrollToBottomButtonShown {
                Image(systemName: "chevron.down")
                    .padding(10)
                    .background(.black)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(.blue, lineWidth: 1)
                    )
                    .padding(.trailing)
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
