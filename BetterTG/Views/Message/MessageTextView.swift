// MessageTextView.swift

import SwiftUI
import TDLibKit

struct MessageTextView: View {
    let formattedText: FormattedText
    let formattedTextSize: CGSize
    let formattedMessageDate: String
    
    var body: some View {
        TextView(formattedText: formattedText)
            .frame(size: formattedTextSize)
            .overlay(alignment: .bottomTrailing) {
                captionText(from: formattedMessageDate)
                    .offset(y: 3)
            }
            .multilineTextAlignment(.leading)
            .padding(8)
            .foregroundStyle(.white)
    }
}
