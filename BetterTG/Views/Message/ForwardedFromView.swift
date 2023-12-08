// ForwardedFromView.swift

import SwiftUI

struct ForwardedFromView: View {
    @State var name: String
    
    var body: some View {
        HStack(spacing: 0) {
            Text("FF: ")
                .foregroundStyle(.white.opacity(0.5))
            
            Text(name)
                .bold()
                .lineLimit(1)
        }
        .padding(5)
    }
}
