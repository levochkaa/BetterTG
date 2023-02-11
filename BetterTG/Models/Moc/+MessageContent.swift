// +MessageContent.swift

import Foundation
import TDLibKit

extension MessageContent {
    static let moc = Self.messageText(
        .init(
            text: .init(
                entities: [],
                text: "texttextexttexttexttextexttexttexttextexttexttexttextexttexttexttextexttexttexttextexttexttext"
            ),
            webPage: nil
        )
    )
}
