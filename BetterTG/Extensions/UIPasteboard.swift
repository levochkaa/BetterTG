// UIPasteboard.swift

import SwiftUI
import MobileCoreServices
import UniformTypeIdentifiers
import TDLibKit

let defaultDocumentAttributes = [
    NSAttributedString.DocumentAttributeKey.documentType: NSAttributedString.DocumentType.rtf
]

extension UIPasteboard {
    static func setFormattedText(_ formattedText: FormattedText) {
        let attributedString = NSAttributedString(getAttributedString(from: formattedText))
        guard let data = try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: defaultDocumentAttributes
        ) else { return }
        UIPasteboard.general.items = [[
            UTType.rtf.identifier: data.string,
            UTType.utf8PlainText.identifier: formattedText.text
        ]]
    }
}
