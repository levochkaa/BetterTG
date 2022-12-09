// ChatView+MessagesList.swift


extension ChatView {
    @ViewBuilder var messagesList: some View {
        ScrollView {
            ZStack {
                LazyVStack {
                    Group {
                        if viewModel.loadingMessages {
                            ProgressView()
                        } else {
                            AsyncButton("Load messages") {
                                await viewModel.loadMessages()
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    
                    ForEach(viewModel.messages) { customMessage in
                        HStack {
                            if customMessage.message.isOutgoing { Spacer() }
                            
                            MessageView(customMessage: customMessage)
                            
                            if !customMessage.message.isOutgoing { Spacer() }
                        }
                        .id(customMessage.message.id)
                        .padding(customMessage.message.isOutgoing ? .trailing : .leading)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom),
                                removal: .move(edge: customMessage.message.isOutgoing ? .trailing : .leading)
                            )
                            .combined(with: .opacity)
                        )
                        .onAppear {
                            guard let scrollViewProxy = viewModel.scrollViewProxy else { return }
                            
                            // for init scrollTo bottom
                            if let initSavedFirstMessage = viewModel.initSavedFirstMessage,
                               let lastId = viewModel.messages.last?.message.id,
                               customMessage.message.id == initSavedFirstMessage.message.id {
                                scrollViewProxy.scrollTo(lastId, anchor: .bottom)
                                viewModel.initSavedFirstMessage = nil
                            }
                            
                            // for scrollTo top, when loading messages
                            if let savedFirstMessage = viewModel.savedFirstMessage,
                               let firstId = viewModel.messages.first?.message.id,
                               customMessage.message.id == firstId {
                                scrollViewProxy.scrollTo(savedFirstMessage.message.id, anchor: .top)
                                viewModel.savedFirstMessage = nil
                            }
                        }
                    }
                }
                
                GeometryReader { geometryProxy in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: geometryProxy.frame(in: .named(scroll))
                    )
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
