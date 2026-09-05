// RichMessageText.swift

import TDLibKit

enum RichMessageText {
    static func plainText(_ value: TDNativeRichText, revealSpoilers: Bool) -> String {
        richText(value, revealSpoilers: revealSpoilers, depth: 0)
    }

    static func summary(_ message: TDNativeRichMessage) -> String {
        let value = blocks(message.blocks, revealSpoilers: false, depth: 0)
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
        return value.isEmpty ? "Rich message" : String(value.prefix(512))
    }

    static func copyText(_ message: TDNativeRichMessage) -> String {
        blocks(message.blocks, revealSpoilers: true, depth: 0)
    }

    private static func blocks(_ values: [TDNativePageBlock], revealSpoilers: Bool, depth: Int) -> String {
        guard depth < 32 else { return "" }
        func text(_ value: TDNativeRichText) -> String { richText(
            value,
            revealSpoilers: revealSpoilers,
            depth: depth + 1,
        ) }
        func nested(_ values: [TDNativePageBlock]) -> String { blocks(
            values,
            revealSpoilers: revealSpoilers,
            depth: depth + 1,
        ) }
        return values.prefix(512)
            .compactMap { block -> String? in
                switch block {
                case .pageBlockTitle(let value): return text(value.title)
                case .pageBlockSubtitle(let value): return text(value.subtitle)
                case .pageBlockHeader(let value): return text(value.header)
                case .pageBlockSubheader(let value): return text(value.subheader)
                case .pageBlockSectionHeading(let value): return text(value.text)
                case .pageBlockKicker(let value): return text(value.kicker)
                case .pageBlockParagraph(let value): return text(value.text)
                case .pageBlockPreformatted(let value): return text(value.text)
                case .pageBlockFooter(let value): return text(value.footer)
                case .pageBlockThinking(let value): return text(value.text)
                case .pageBlockList(let value): return value.items
                    .map { $0.label + " " + nested($0.blocks) }
                    .joined(separator: "\n")
                case .pageBlockBlockQuote(let value): return nested(value.blocks)
                case .pageBlockExpandableBlockQuote(let value): return text(value.text)
                case .pageBlockPullQuote(let value): return text(value.text)
                case .pageBlockTable(let value): return value.cells
                    .map { $0.compactMap { $0.text.map(text) }.joined(separator: "\t") }
                    .joined(separator: "\n")
                case .pageBlockDetails(let value): return text(value.header) + "\n" + nested(value.blocks)
                case .pageBlockPhoto(let value): return value.hasSpoiler && !revealSpoilers
                    ? "Spoiler"
                    : value.caption.map { text($0.text) } ?? "Photo"
                case .pageBlockVideo(let value): return value.hasSpoiler && !revealSpoilers
                    ? "Spoiler"
                    : value.caption.map { text($0.text) } ?? "Video"
                case .pageBlockAnimation(let value): return value.hasSpoiler && !revealSpoilers
                    ? "Spoiler"
                    : value.caption.map { text($0.text) } ?? "Animation"
                case .pageBlockAudio(let value): return value.caption.map { text($0.text) } ?? value.audio.title
                case .pageBlockDocument(let value): return value.caption.map { text($0.text) } ?? value.document
                    .fileName
                case .pageBlockVoiceNote(let value): return value.caption.map { text($0.text) } ?? "Voice message"
                case .pageBlockCover(let value): return nested([value.cover])
                case .pageBlockCollage(let value): return nested(value.blocks)
                case .pageBlockSlideshow(let value): return nested(value.blocks)
                case .pageBlockEmbeddedPost(let value): return nested(value.blocks)
                case .pageBlockEmbedded(let value): return value.caption.map { text($0.text) } ?? value.url
                case .pageBlockChatLink(let value): return value.title
                case .pageBlockButtonRow(let value): return value.buttons.map { text($0.text) }.joined(separator: " · ")
                case .pageBlockMathematicalExpression(let value): return value.expression
                case .pageBlockAuthorDate(let value): return text(value.author)
                case .pageBlockRelatedArticles(let value): return text(value.header)
                case .pageBlockMap: return "Location"
                case .pageBlockAnchor, .pageBlockDivider, .pageBlockUnsupported: return nil
                }
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func richText(_ value: TDNativeRichText, revealSpoilers: Bool, depth: Int) -> String {
        guard depth < 128 else { return "" }
        func text(_ value: TDNativeRichText) -> String { richText(
            value,
            revealSpoilers: revealSpoilers,
            depth: depth + 1,
        ) }
        switch value {
        case .richTextPlain(let value): return value.text
        case .richTexts(let value): return value.texts.map(text).joined()
        case .richTextBold(let value): return text(value.text)
        case .richTextItalic(let value): return text(value.text)
        case .richTextUnderline(let value): return text(value.text)
        case .richTextStrikethrough(let value): return text(value.text)
        case .richTextSpoiler(let value): return revealSpoilers ? text(value.text) : "Spoiler"
        case .richTextSubscript(let value): return text(value.text)
        case .richTextSuperscript(let value): return text(value.text)
        case .richTextMarked(let value): return text(value.text)
        case .richTextDateTime(let value): return text(value.text)
        case .richTextMention(let value): return text(value.text)
        case .richTextHashtag(let value): return text(value.text)
        case .richTextCashtag(let value): return text(value.text)
        case .richTextBankCardNumber(let value): return text(value.text)
        case .richTextBotCommand(let value): return text(value.text)
        case .richTextFixed(let value): return text(value.text)
        case .richTextMentionName(let value): return text(value.text)
        case .richTextUrl(let value): return text(value.text)
        case .richTextEmailAddress(let value): return text(value.text)
        case .richTextPhoneNumber(let value): return text(value.text)
        case .richTextCustomEmoji(let value): return value.alternativeText
        case .richTextIcon(let value): return value.document.fileName
        case .richTextMathematicalExpression(let value): return value.expression
        case .richTextButton(let value): return text(value.button.text)
        case .richTextDiff(let value): return text(value.text)
        case .richTextReference(let value): return text(value.text)
        case .richTextReferenceLink(let value): return text(value.text)
        case .richTextAnchorLink(let value): return text(value.text)
        case .richTextAnchor: return ""
        }
    }
}
