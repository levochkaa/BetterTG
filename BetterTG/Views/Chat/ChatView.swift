// ChatView.swift

import SwiftUI
import TDLibKit

struct ChatView: View {
    
    @StateObject var viewModel: ChatViewModel
    
    @FocusState var focused
    
    @State var isScrollToBottomButtonShown = false
    
    let scroll = "chatScroll"
    @State var scrollOnFocus = true
    
    @Environment(\.isPreview) var isPreview
    @Environment(\.dismiss) var dismiss
    
    @EnvironmentObject var rootViewModel: RootViewModel
    
    init(customChat: CustomChat) {
        self._viewModel = StateObject(wrappedValue: ChatViewModel(customChat: customChat))
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
            toolbar
        }
        .navigationBarTitleDisplayMode(.inline)
        .environmentObject(viewModel)
        .modify {
            if #available(iOS 16.2, *) {
                $0
                    .task {
                        await viewModel.loadLiveActivity()
                    }
                    .onDisappear {
                        Task { await LiveActivityManager.endAllActivities() }
                    }
            }
        }
    }
    
    func scrollToLastOnFocus() {
        if scrollOnFocus {
            viewModel.scrollToLast()
        }
    }
}
