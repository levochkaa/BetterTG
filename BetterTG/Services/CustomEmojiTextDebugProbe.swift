// CustomEmojiTextDebugProbe.swift

#if DEBUG
import TDLibKit
import UIKit

@MainActor enum CustomEmojiTextDebugProbe {
    private static var didRun = false

    static func runIfRequested() {
        guard !didRun, ProcessInfo.processInfo.arguments.contains("-custom-emoji-text-probe") else { return }
        didRun = true
        let value = NSMutableAttributedString(string: "a🙂🙂b", attributes: defaultAttributes())
        let id: Int64 = 5_000_000_000_123
        value.addAttribute(.telegramCustomEmoji, value: NSNumber(value: id), range: NSRange(location: 1, length: 4))
        value.addAttribute(.font, value: UIFont.bold, range: NSRange(location: 1, length: 2))
        var lines = [String]()
        func check(_ name: String, _ condition: Bool) { lines.append("\(condition ? "PASS" : "FAIL") \(name)") }
        // The composer turns visual custom emoji runs into one semantic entity per emoji, as CustomTextField does
        // for pasted and inserted emoji; outgoing entities, drafts and edits read only that semantic layer.
        ComposerText.setCustomEmoji(TelegramCustomEmojiRun.extract(from: value), in: value)
        let state = ComposerText.value(value)
        let roundTrip = ComposerText.uiKit(state)
        let runs = TelegramCustomEmojiRun.extract(from: roundTrip)
        check("scope retains 64-bit custom emoji ids", runs.count == 2 && runs.allSatisfy { $0.id == id })
        check(
            "adjacent emoji remain two UTF-16 ranges",
            runs.map(\.range) == [NSRange(location: 1, length: 2), NSRange(location: 3, length: 2)],
        )
        let entities = getEntities(from: state)
        let custom = entities.filter {
            if case .textEntityTypeCustomEmoji = $0.type {
                true
            } else {
                false
            }
        }
        check("outgoing entities retain separate emoji", custom.count == 2 && custom.map(\.offset) == [1, 3])
        check(
            "overlapping formatting survives",
            entities
            .contains {
                if case .textEntityTypeBold = $0.type {
                    $0.offset == 1 && $0.length == 2
                } else {
                    false
                }
            },
        )
        let restored = getAttributedString(from: FormattedText(entities: entities, text: value.string))
        check(
            "draft round trip preserves emoji",
            TelegramCustomEmojiRun.extract(from: restored.telegramNSAttributedString).map(\.range) == runs.map(\.range),
        )
        let payload = TelegramEmojiPasteboardPayload(roundTrip)
        let pasted = NSMutableAttributedString(string: value.string, attributes: defaultAttributes())
        if let data = try? JSONEncoder().encode(payload), let decoded = try? JSONDecoder().decode(
            TelegramEmojiPasteboardPayload.self,
            from: data,
        ) {
            decoded.apply(to: pasted)
        }
        check("copy payload preserves repeated emoji", TelegramCustomEmojiRun.extract(from: pasted).count == 2)
        pasted.replaceCharacters(in: NSRange(location: 1, length: 2), with: "")
        let remaining = TelegramCustomEmojiRun.extract(from: pasted)
        check(
            "deleting one emoji retains its neighbor",
            remaining.count == 1 && remaining.first?.range == NSRange(location: 1, length: 2),
        )
        let quoteSource = FormattedText(
            entities: entities + [TextEntity(length: value.string.utf16.count, offset: 0, type: .textEntityTypeBold)],
            text: value.string,
        )
        let selectedQuote = MessageQuoteBuilder.make(
            from: quoteSource, maximumLength: 1024, range: NSRange(location: 3, length: 3),
        )
        check(
            "selected quote retains original UTF-16 position",
            selectedQuote?.position == 3 && selectedQuote?.text.text == "🙂b",
        )
        check("selected quote rebases custom emoji", selectedQuote?.text.entities.contains {
            if case .textEntityTypeCustomEmoji = $0.type {
                $0.offset == 0 && $0.length == 2
            } else {
                false
            }
        } == true)
        check("selected quote clips crossing formatting", selectedQuote?.text.entities.contains {
            if case .textEntityTypeBold = $0.type {
                $0.offset == 0 && $0.length == 3
            } else {
                false
            }
        } == true)
        check("quote maximum never splits a surrogate", MessageQuoteBuilder.make(
            from: quoteSource, maximumLength: 1, range: NSRange(location: 3, length: 3),
        ) == nil)
        check("quote rejects invalid native selection", MessageQuoteBuilder.make(
            from: quoteSource, maximumLength: 1024, range: NSRange(location: 2, length: 2),
        ) == nil)
        check("quote maximum retains whole joined emoji", MessageQuoteBuilder.make(
            from: FormattedText(entities: [], text: "a👨‍👩‍👧‍👦b"),
            maximumLength: 5, range: NSRange(location: 1, length: 11),
        ) == nil)
        let trimmedQuote = MessageQuoteBuilder.make(
            from: FormattedText(entities: [], text: "a\n bc \nd"),
            maximumLength: 1, range: NSRange(location: 1, length: 6),
        )
        check(
            "quote trims spaces and line feeds before the limit",
            trimmedQuote?.position == 3 && trimmedQuote?.text.text == "b",
        )
        check("blank quote falls back to a plain reply", MessageQuoteBuilder.make(
            from: FormattedText(entities: [], text: "a \nb"),
            maximumLength: 1024, range: NSRange(location: 1, length: 2),
        ) == nil)
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("custom-emoji-text-probe.txt")
        try? lines.joined(separator: "\n").write(to: path, atomically: true, encoding: .utf8)
    }
}
#endif
