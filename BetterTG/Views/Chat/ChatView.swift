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
    let logger = Logger(label: "ChatView")
    
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
            // only possible in contextMenu, where it isn't needed
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
//                    .safeAreaInset(edge: .bottom) {
//                        Group {
//                            if !isPreview {
//                                bottomArea
////                                    .environmentObject(viewModel)
//                            }
//                        }
//                    }
            } else {
                bodyView
//                    .environmentObject(viewModel)
                    .safeAreaInset(edge: .bottom) {
                        Group {
                            if !isPreview {
                                bottomArea
//                                    .environmentObject(viewModel)
                            }
                        }
                    }
            }
        }
        .navigationTitle(viewModel.chat.title)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    var bodyView: some View {
        ScrollViewReader { scrollViewProxy in
            messagesList
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
                .onChange(of: focused) { _ in
                    if scrollOnFocus {
                        viewModel.scrollToLast()
                    }
                }
                .onChange(of: viewModel.messages) { _ in
                    if scrollOnFocus {
                        viewModel.scrollToLast()
                    }
                }
                .onChange(of: viewModel.replyMessage) { reply in
                    if reply == nil && scrollOnFocus {
                        viewModel.scrollToLast()
                    } else if reply != nil {
                        focused = true
                    }
                }
                .onChange(of: viewModel.editMessage) { edit in
                    if edit == nil && scrollOnFocus {
                        viewModel.scrollToLast()
                    } else if edit != nil {
                        focused = true
                    }
                }
                .onChange(of: viewModel.displayedPhotos) { _ in
                    if scrollOnFocus {
                        viewModel.scrollToLast()
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
                Image(systemName: "arrow.down")
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
            Task {
                await viewModel.updateDraft()
            }
        }
    }
}
