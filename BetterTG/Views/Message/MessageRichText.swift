// MessageRichText.swift

import TDLibKit
import UIKit

/// TDLib's recursive rich text stays structured until layout, as in Telegram's
/// InstantPageV2 renderer. Entities retain UTF-16 offsets for links and emoji.
@MainActor struct MessageRichText {
    let attributed: NSAttributedString
    let formatted: FormattedText
    let buttons: [String: TDNativeInlineButton]

    init(_ text: TDNativeRichText, font: UIFont = .body, isRTL: Bool = false, traits: UITraitCollection = .current) {
        let result = NSMutableAttributedString()
        var entities = [TextEntity]()
        var buttons = [String: TDNativeInlineButton]()
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = isRTL ? .rightToLeft : .natural
        paragraph.lineSpacing = 1
        func append(_ text: TDNativeRichText, attributes: [NSAttributedString.Key: Any], depth: Int = 0) {
            guard depth < 128 else { return }
            let start = result.length
            func child(
                _ value: TDNativeRichText,
                entity: TextEntityType? = nil,
                extra: [NSAttributedString.Key: Any] = [:],
            ) {
                append(value, attributes: attributes.merging(extra) { _, value in value }, depth: depth + 1)
                if let entity, result.length > start {
                    entities.append(TextEntity(length: result.length - start, offset: start, type: entity))
                }
            }
            func trait(_ value: TDNativeRichText, _ trait: UIFontDescriptor.SymbolicTraits, entity: TextEntityType) {
                let current = attributes[.font] as? UIFont ?? font
                let descriptor = current.fontDescriptor
                    .withSymbolicTraits(current.fontDescriptor.symbolicTraits.union(trait))
                child(
                    value,
                    entity: entity,
                    extra: [.font: descriptor.map { UIFont(descriptor: $0, size: current.pointSize) } ?? current],
                )
            }
            func link(_ value: TDNativeRichText, _ url: String) {
                child(
                    value,
                    entity: .textEntityTypeTextUrl(TextEntityTypeTextUrl(url: url)),
                    extra: [.foregroundColor: UIColor.systemBlue, .link: url],
                )
            }
            switch text {
            case .richTextPlain(let value): result.append(NSAttributedString(
                    string: value.text,
                    attributes: attributes,
                ))
            case .richTexts(let value): value.texts.forEach { append($0, attributes: attributes, depth: depth + 1) }
            case .richTextBold(let value): trait(value.text, .traitBold, entity: .textEntityTypeBold)
            case .richTextItalic(let value): trait(value.text, .traitItalic, entity: .textEntityTypeItalic)
            case .richTextUnderline(let value): child(
                    value.text,
                    entity: .textEntityTypeUnderline,
                    extra: [.underlineStyle: 1],
                )
            case .richTextStrikethrough(let value): child(
                    value.text,
                    entity: .textEntityTypeStrikethrough,
                    extra: [.strikethroughStyle: 1],
                )
            case .richTextSpoiler(let value): child(value.text, entity: .textEntityTypeSpoiler)
            case .richTextFixed(let value):
                child(
                    value.text,
                    entity: .textEntityTypeCode,
                    extra: [.font: UIFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)],
                )
            case .richTextSubscript(let value): child(
                    value.text,
                    extra: [.baselineOffset: -font.pointSize * 0.2, .font: font.withSize(font.pointSize * 0.75)],
                )
            case .richTextSuperscript(let value): child(
                    value.text,
                    extra: [.baselineOffset: font.pointSize * 0.35, .font: font.withSize(font.pointSize * 0.75)],
                )
            case .richTextMarked(let value): child(
                    value.text,
                    extra: [.backgroundColor: UIColor.systemYellow.withAlphaComponent(0.3)],
                )
            case .richTextUrl(let value): link(value.text, value.url)
            case .richTextMention(let value): link(value.text, "https://t.me/\(value.username)")
            case .richTextMentionName(let value): link(value.text, "tg://user?id=\(value.userId)")
            case .richTextEmailAddress(let value): link(value.text, "mailto:\(value.emailAddress)")
            case .richTextPhoneNumber(let value): link(value.text, "tel:\(value.phoneNumber)")
            case .richTextReferenceLink(let value): link(value.text, value.url)
            case .richTextAnchorLink(let value): link(value.text, value.url)
            case .richTextCustomEmoji(let value):
                result.append(NSAttributedString(
                    string: value.alternativeText.isEmpty ? "◻︎" : value.alternativeText,
                    attributes: attributes,
                ))
                entities.append(TextEntity(
                    length: result.length - start,
                    offset: start,
                    type: .textEntityTypeCustomEmoji(TextEntityTypeCustomEmoji(customEmojiId: value
                            .customEmojiId)),
                ))
            case .richTextMathematicalExpression(let value):
                if let rendered = MessageMathRenderer.render(
                    value.expression,
                    fontSize: font.pointSize,
                    inline: true,
                    traits: traits,
                ) {
                    let attachment = NSTextAttachment()
                    attachment.image = rendered.image
                    attachment.bounds = CGRect(
                        x: 0,
                        y: -rendered.descent,
                        width: rendered.image.size.width,
                        height: rendered.image.size.height,
                    )
                    result.append(NSAttributedString(attachment: attachment))
                    break
                }
                result.append(NSAttributedString(
                    string: value.expression,
                    attributes: attributes.merging([.font: UIFont.monospaced]) { _, value in value },
                ))
            case .richTextButton(let value):
                let url = "bettertg-rich-action://button/\(buttons.count)"
                buttons[url] = value.button
                link(value.button.text, url)
            case .richTextDiff(let value): child(value.text)
            case .richTextDateTime(let value): child(value.text)
            case .richTextReference(let value): child(value.text)
            case .richTextHashtag(let value): child(value.text)
            case .richTextCashtag(let value): child(value.text)
            case .richTextBankCardNumber(let value): child(value.text)
            case .richTextTonAddress(let value): child(value.text)
            case .richTextBotCommand(let value): child(value.text)
            case .richTextIcon(let value):
                result.append(NSAttributedString(string: value.document.fileName, attributes: attributes))
            case .richTextAnchor: break
            }
        }
        append(text, attributes: [.font: font, .foregroundColor: UIColor.label, .paragraphStyle: paragraph])
        self.attributed = result
        self.formatted = FormattedText(entities: entities, text: result.string)
        self.buttons = buttons
    }
}
