// MessageView+FormattedText.swift

import SwiftUI
import TDLibKit

extension MessageView {
    @ViewBuilder func formattedTextView(_ formattedText: FormattedText) -> some View {
        if isPreview {
            Text(formattedText.text)
                .fixedSize(horizontal: false, vertical: true)
                .readSize { textSize = $0 }
        } else if !redactionReasons.isEmpty {
            Text(formattedText.text)
                .fixedSize(horizontal: false, vertical: true)
                .readSize { textSize = $0 }
        } else {
            ZStack {
                Text(attributedString(for: formattedText))
                    .fixedSize(horizontal: false, vertical: true)
                    .readSize { textSize = $0 }
                    .hidden()
                
                if textSize != .zero {
                    TextView(
                        formattedText: formattedText,
                        textSize: textSize
                    )
                    .frame(width: textSize.width, height: textSize.height, alignment: .topLeading)
                    .equatable(by: textSize)
                    .draggable(formattedText.text) {
                        Text(attributedStringWithoutDate)
                            .frame(size: draggableTextSize)
                            .multilineTextAlignment(.leading)
                            .padding(8)
                            .foregroundColor(.white)
                            .background(.gray6)
                            .cornerRadius([.bottomLeft, .bottomRight, .topLeft, .topRight])
                    }
                    .overlay {
                        Text(attributedStringWithoutDate)
                            .fixedSize(horizontal: false, vertical: true)
                            .readSize { draggableTextSize = $0 }
                            .hidden()
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                messageDate
//                    .menuOnPress { menu }
                    .offset(y: 3)
            }
        }
    }
}
