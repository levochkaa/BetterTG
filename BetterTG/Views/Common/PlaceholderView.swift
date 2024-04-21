// PlaceholderView.swift

import SwiftUI

struct PlaceholderView: View {
    @Binding var customChat: CustomChat
    var fontSize: CGFloat = 40
    
    var body: some View {
        Text(String(customChat.chat.title.prefix(1).capitalized))
            .font(.system(size: fontSize, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(userId: customChat.chat.id).gradient)
    }
}
