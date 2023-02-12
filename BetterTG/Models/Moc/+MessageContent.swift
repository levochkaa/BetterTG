// +MessageContent.swift

import Foundation
import TDLibKit

extension MessageContent {
    static func moc(_ count: Int) -> MessageContent {
        .messageText(
            .init(
                text: .init(
                    entities: [],
                    text: String(repeating: "texttexttexttexttext", count: count)
                ),
                webPage: nil
            )
        )
    }
}
