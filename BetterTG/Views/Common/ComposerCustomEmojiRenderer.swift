// ComposerCustomEmojiRenderer.swift

import TDLibKit
import UIKit

// MARK: - ComposerCustomEmojiRenderer

@MainActor final class ComposerCustomEmojiRenderer {
    @MainActor private final class Placement {
        let id: Int64
        var range: NSRange
        let view = CustomEmojiInlineView()
        var ready = false
        var configured = false

        init(id: Int64, range: NSRange) { self.id = id
            self.range = range
        }
    }

    /// The composer's chat client. Its account owns the custom emoji stickers, so a composer that outlives an
    /// account switch keeps resolving them there; without a client the emoji stay plain glyphs.
    var client: TDLibClient? {
        didSet {
            if client?.id != oldValue?.id { update() }
        }
    }

    private weak var textView: UITextView?
    private var placements = [Placement]()
    private var task: Task<Void, Never>?
    private var clientID: Int32?

    init(textView: UITextView) { self.textView = textView }
    deinit { task?.cancel() }

    /// Preserve exactly the emoji frames the editor shows, with their text-colour masks. A new decoder could
    /// finish after the 0.1 s send fade, briefly exposing the Unicode placeholder instead of the custom emoji.
    func copyVisibleFrames(to destination: UITextView) {
        var hidden = [NSRange]()
        for item in placements where item.ready {
            guard let view = item.view.makeSendTransitionView() else { continue }
            view.frame = item.view.frame
            destination.addSubview(view)
            hidden.append(item.range)
        }
        (destination.layoutManager as? ComposerEmojiLayoutManager)?.hiddenCharacterRanges = hidden
    }

    func update() {
        guard let textView else { return }
        let requests = TelegramCustomEmojiRun.extract(from: textView.textStorage).map { ($0.id, $0.range) }
        let client = requests.isEmpty ? nil : client
        let old = placements
        placements = client == nil
            ? []
            : requests.enumerated().map { index, request in
                if clientID == client?.id, index < old.count, old[index].id == request.0 {
                    old[index].range = request.1
                    return old[index]
                }
                let placement = Placement(id: request.0, range: request.1)
                placement.view.isUserInteractionEnabled = false
                // A template emoji takes the composer's text colour.
                placement.view.templateColor = textView.textColor ?? .label
                textView.addSubview(placement.view)
                return placement
            }
        for item in old where !placements.contains(where: { $0 === item }) {
            item.view.prepareForReuse()
            item.view.removeFromSuperview()
        }
        clientID = client?.id
        task?.cancel()
        let pending = placements.filter { !$0.configured }
        if let client, !pending.isEmpty {
            task = Task { [weak self] in
                let stickers = await CustomEmojiStickerRepository.shared.stickers(
                    for: pending.map(\.id),
                    client: client,
                )
                guard let self, !Task.isCancelled, clientID == client.id else { return }
                for item in pending {
                    guard placements.contains(where: { $0 === item }), let sticker = stickers[item.id] else { continue }
                    item.view.onFirstFrameReady = { [weak self, weak item] in
                        item?.ready = true
                        self?.layout()
                    }
                    item.view.configure(sticker: sticker, client: client)
                    item.configured = true
                }
                layout()
            }
        }
        layout()
    }

    func layout() {
        guard let textView else { return }
        let manager = textView.layoutManager
        var hidden = [NSRange]()
        manager.ensureLayout(for: textView.textContainer)
        for item in placements where NSMaxRange(item.range) <= textView.textStorage.length {
            let glyphs = manager.glyphRange(forCharacterRange: item.range, actualCharacterRange: nil)
            let rect = manager.boundingRect(forGlyphRange: glyphs, in: textView.textContainer)
                .offsetBy(dx: textView.textContainerInset.left, dy: textView.textContainerInset.top)
            let size = max(20, min(28, rect.height))
            item.view.frame = CGRect(x: rect.midX - size / 2, y: rect.midY - size / 2, width: size, height: size)
            item.view.setPlaybackVisible(textView.window != nil)
            if item.ready { hidden.append(item.range) }
        }
        (manager as? ComposerEmojiLayoutManager)?.hiddenCharacterRanges = hidden
    }
}

// MARK: - ComposerEmojiLayoutManager

final class ComposerEmojiLayoutManager: NSLayoutManager {
    var hiddenCharacterRanges = [NSRange]() {
        didSet {
            if hiddenCharacterRanges != oldValue, let textStorage {
                invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textStorage.length))
            }
        }
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        let hidden = hiddenCharacterRanges.map { glyphRange(forCharacterRange: $0, actualCharacterRange: nil) }
            .sorted { $0.location < $1.location }
        var cursor = glyphsToShow.location
        let end = NSMaxRange(glyphsToShow)
        for range in hidden {
            let intersection = NSIntersectionRange(range, glyphsToShow)
            guard intersection.length > 0 else { continue }
            if intersection.location > cursor {
                super.drawGlyphs(
                    forGlyphRange: NSRange(location: cursor, length: intersection.location - cursor),
                    at: origin,
                )
            }
            cursor = max(cursor, NSMaxRange(intersection))
        }
        if cursor < end { super.drawGlyphs(forGlyphRange: NSRange(location: cursor, length: end - cursor), at: origin) }
    }
}
