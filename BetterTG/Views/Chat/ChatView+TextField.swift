// ChatView+TextField.swift

import SwiftUI

extension ChatView {
    @ViewBuilder var textField: some View {
        HStack(alignment: .bottom) {
            TextField("Message", text: $text, axis: .vertical)
                .focused($focused)
                .lineLimit(10)
                .padding(5)
                .background(Color.gray6)
                .cornerRadius(10)
            
            Button(action: sendMessage) {
                Image("send")
                    .resizable()
                    .clipShape(Circle())
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
