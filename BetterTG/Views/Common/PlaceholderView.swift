// PlaceholderView.swift

import SwiftUI

struct PlaceholderView: View {
    let title: String
    let id: Int64
    var fontSize: CGFloat = 40
    
    var body: some View {
        Text(String(title.prefix(1).capitalized))
            .font(.system(size: fontSize, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(userId: id).gradient)
    }
}
