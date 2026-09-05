// UIPasteboard.swift

import TDLibKit
import UIKit
import UniformTypeIdentifiers

let defaultDocumentAttributes = [
    NSAttributedString.DocumentAttributeKey.documentType: NSAttributedString.DocumentType.rtf,
]

extension UIPasteboard {
    static func setFormattedText(_ formattedText: FormattedText) {
        setTelegramAttributedText(getAttributedString(from: formattedText).telegramNSAttributedString)
    }

    static func setTelegramAttributedText(_ attributedString: NSAttributedString) {
        guard let data = try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: defaultDocumentAttributes,
        ) else { return }
        var item: [String: Any] = [
            UTType.rtf.identifier: data.string,
            UTType.utf8PlainText.identifier: attributedString.string,
        ]
        let payload = TelegramEmojiPasteboardPayload(attributedString)
        if !payload.emojis.isEmpty, let data = try? JSONEncoder().encode(payload) {
            item[TelegramEmojiPasteboardPayload.type] = data
        }
        UIPasteboard.general.items = [item]
    }

    static func setPlainText(_ string: String) {
        UIPasteboard.general.items = [[UTType.utf8PlainText.identifier: string]]
    }
}
