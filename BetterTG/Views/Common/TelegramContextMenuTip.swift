// TelegramContextMenuTip.swift

import UIKit

// MARK: - TelegramContextMenuTip

/// ContextController.Tip: a note under a message's menu, such as why the message can't be copied or how to select
/// its text.
struct TelegramContextMenuTip: Equatable {
    /// `.textSelection`: Telegram shows it for a message of three words or more, three times in all.
    static var textSelection: TelegramContextMenuTip {
        let raw = L10n.telegram("ChatContextMenu.TextSelectionTip2")
        guard let marker = raw.range(of: "|") else {
            return TelegramContextMenuTip(text: raw, showsIcon: true, selectionEnd: 1)
        }
        let end = raw.utf16.distance(from: raw.startIndex, to: marker.lowerBound)
        return TelegramContextMenuTip(text: raw.replacing("|", with: ""), showsIcon: true, selectionEnd: end)
    }

    /// Telegram's text, `**bold**` included.
    let text: String
    let showsIcon: Bool
    /// Where the selection the tip pretends to make ends, from the "|" in Telegram's text.
    let selectionEnd: Int?

    static func copyProtection(_ text: String) -> TelegramContextMenuTip {
        TelegramContextMenuTip(text: text, showsIcon: false, selectionEnd: nil)
    }
}

// MARK: - TelegramContextMenuTipView

/// InnerTextSelectionTipContainerNode outside the actions: the menu's glass, as round as the menu allows, with 13 pt
/// text 16 pt from the top and bottom, 18 pt from the left or 60 pt after the lamp, and 8 pt from the right. The text
/// selection tip pretends to select its first word, then more of the text half a second later.
final class TelegramContextMenuTipView: UIView {
    private static let font = UIFont.systemFont(ofSize: 13)
    private static let boldFont = UIFont.boldSystemFont(ofSize: 13)

    private let tip: TelegramContextMenuTip
    private let fallbackGlassView = UIVisualEffectView()
    private let textView = UITextView()
    private let iconView = UIImageView(image: UIImage(systemName: "lightbulb"))
    private let selectionLayer = CAShapeLayer()
    private let startKnob = CAShapeLayer()
    private let endKnob = CAShapeLayer()
    private var usesNativeGlass = false

    private var textLeftInset: CGFloat { tip.showsIcon ? 60 : 18 }

    init(tip: TelegramContextMenuTip) {
        self.tip = tip
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerCurve = .continuous
        self.usesNativeGlass = ContextMenuNativeGlass.applyMenuGlass(to: self)
        if !usesNativeGlass {
            fallbackGlassView.effect = UIGlassEffect(style: .regular)
            addSubview(fallbackGlassView)
        }
        selectionLayer.fillColor = UIColor.label.withAlphaComponent(0.15).cgColor
        for knob in [startKnob, endKnob] {
            knob.fillColor = UIColor.label.cgColor
        }
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.isSelectable = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.attributedText = Self.attributedText(tip.text)
        textView.layer.insertSublayer(selectionLayer, at: 0)
        textView.layer.addSublayer(startKnob)
        textView.layer.addSublayer(endKnob)
        addSubview(textView)
        iconView.tintColor = .label
        iconView.contentMode = .center
        iconView.isHidden = !tip.showsIcon
        addSubview(iconView)
        isAccessibilityElement = true
        accessibilityLabel = tip.text.withoutTelegramMarkup
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = min(TelegramContextMenuLayout.menuCornerRadius, bounds.height / 2)
        layer.cornerRadius = radius
        fallbackGlassView.frame = bounds
        fallbackGlassView.layer.cornerRadius = radius
        fallbackGlassView.clipsToBounds = true
        let textWidth = max(1, bounds.width - textLeftInset - 8)
        textView.frame = CGRect(x: textLeftInset, y: 16, width: textWidth, height: bounds.height - 32)
        // The lamp sits in a 32 pt slot 20 pt from the left.
        iconView.frame = CGRect(x: 20, y: 0, width: 32, height: bounds.height)
    }

    private static func attributedText(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, part) in text.components(separatedBy: "**").enumerated() {
            result.append(NSAttributedString(string: part, attributes: [
                .font: index % 2 == 1 ? boldFont : font,
                .foregroundColor: UIColor.label,
            ]))
        }
        return result
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        let textWidth = max(1, width - textLeftInset - 8)
        let size = textView.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        return ceil(size.height) + 32
    }

    /// TextSelectionNode's pretendInitiateSelection, then pretendExtendSelection to the marker after 0.5 s.
    func animateSelection() {
        guard let end = tip.selectionEnd else { return }
        layoutIfNeeded()
        let text = textView.text as NSString
        let firstWord = text.rangeOfCharacter(from: .whitespaces).location
        let wordEnd = firstWord == NSNotFound ? min(end, text.length) : firstWord
        showSelection(NSRange(location: 0, length: wordEnd))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showSelection(NSRange(location: 0, length: min(end, text.length)))
        }
    }

    private func showSelection(_ range: NSRange) {
        let layoutManager = textView.layoutManager
        let container = textView.textContainer
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rects = [CGRect]()
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, lineGlyphs, _ in
            let part = NSIntersectionRange(lineGlyphs, glyphs)
            guard part.length > 0 else { return }
            rects.append(layoutManager.boundingRect(forGlyphRange: part, in: container))
        }
        guard let first = rects.first, let last = rects.last else { return }
        let path = UIBezierPath()
        for rect in rects {
            path.append(UIBezierPath(rect: rect))
        }
        // TextSelectionNode's knobs: a 2 pt bar along the line with an 8 pt dot above the start and below the end.
        let start = UIBezierPath(rect: CGRect(x: first.minX - 1, y: first.minY, width: 2, height: first.height))
        start.append(UIBezierPath(ovalIn: CGRect(x: first.minX - 4, y: first.minY - 8, width: 8, height: 8)))
        let finish = UIBezierPath(rect: CGRect(x: last.maxX - 1, y: last.minY, width: 2, height: last.height))
        finish.append(UIBezierPath(ovalIn: CGRect(x: last.maxX - 4, y: last.maxY, width: 8, height: 8)))
        selectionLayer.path = path.cgPath
        startKnob.path = start.cgPath
        endKnob.path = finish.cgPath
    }
}
