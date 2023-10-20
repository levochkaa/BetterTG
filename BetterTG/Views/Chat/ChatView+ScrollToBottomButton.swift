// ChatView+ScrollToBottomButton.swift

extension ChatView {
    @ViewBuilder var scrollToBottomButton: some View {
        Image(systemName: "chevron.down")
            .offset(y: 1)
            .font(.title3)
            .padding(10)
            .background(.black)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(.blue, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                if let unreadCount = viewModel.customChat?.unreadCount, unreadCount != 0 {
                    Circle()
                        .fill(.blue)
                        .frame(width: 16, height: 16)
                        .overlay {
                            Text("\(unreadCount)")
                                .font(.caption)
                                .foregroundColor(.white)
                                .minimumScaleFactor(0.5)
                        }
                        .offset(y: -5)
                }
            }
            .transition(.move(edge: .bottom).combined(with: .scale).combined(with: .opacity))
            .padding(.trailing)
            .padding(.bottom, 5)
            .onTapGesture {
                viewModel.scrollToLast()
            }
    }
}
