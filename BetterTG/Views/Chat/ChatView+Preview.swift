// ChatView+Preview.swift

import SwiftUI
import TDLibKit

struct ChatViewPreview: View {

    @StateObject var viewModel: ChatViewVM

    let logger = Logger(label: "ChatViewPreview")
    
    init(chat: Chat) {
        self._viewModel = StateObject(wrappedValue: ChatViewVM(chat: chat))
    }
    
    var body: some View {
        ScrollViewReader { scrollViewProxy in
            ScrollView {
                ForEach(viewModel.messages) { customMessage in
                    HStack {
                        if customMessage.message.isOutgoing { Spacer() }
                        
                        MessageView(customMessage: customMessage)
                            .environmentObject(viewModel)
                        
                        if !customMessage.message.isOutgoing { Spacer() }
                    }
                    .id(customMessage.message.id)
                    .padding(customMessage.message.isOutgoing ? .trailing : .leading)
                    .transition(.move(edge: .bottom))
                    .onAppear {
                        guard let initSavedFirstMessage = viewModel.initSavedFirstMessage,
                              let lastId = viewModel.messages.last?.message.id,
                              customMessage.message.id == initSavedFirstMessage.message.id
                        else { return }
                        
                        scrollViewProxy.scrollTo(lastId, anchor: .bottom)
                        viewModel.initSavedFirstMessage = nil
                    }
                }
            }
        }
        .background(.black)
    }
}
