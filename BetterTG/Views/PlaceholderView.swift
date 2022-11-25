// PlaceholderView.swift

import SwiftUI

struct PlaceholderView: View {
    @State var userId: Int64
    @State var title: String
    
    var body: some View {
        Text(String(title.prefix(1)))
            .font(.system(size: 40, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(fromUserId: userId).gradient)
    }
}
