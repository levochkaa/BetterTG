// ComposeTokenView.swift

import UIKit

// MARK: - ComposeTokenView

/// Telegram's EditableTokenListNode above a multiple selection: a chip for each chosen person, wrapping onto new
/// lines. Tapping a chip removes that person.
final class ComposeTokenView: UIView {
    struct Token: Equatable {
        let id: Int64
        let title: String
    }

    private static let horizontalInset: CGFloat = 20
    private static let verticalInset: CGFloat = 8
    private static let spacing: CGFloat = 6

    var onRemove: ((Int64) -> Void)?

    private(set) var tokens = [Token]()

    private var buttons = [(id: Int64, button: UIButton)]()

    override func layoutSubviews() {
        super.layoutSubviews()
        let frames = layout(width: bounds.width).frames
        for (entry, frame) in zip(buttons, frames) {
            entry.button.frame = frame
        }
    }

    func update(tokens: [Token]) {
        guard tokens != self.tokens else { return }
        self.tokens = tokens
        for entry in buttons {
            entry.button.removeFromSuperview()
        }
        buttons = tokens.map { token in
            var configuration = UIButton.Configuration.tinted()
            configuration.title = token.title
            configuration.cornerStyle = .capsule
            configuration.buttonSize = .small
            configuration.titleLineBreakMode = .byTruncatingTail
            let button = UIButton(configuration: configuration)
            button.accessibilityLabel = token.title
            let id = token.id
            button.addAction(UIAction { [weak self] _ in self?.onRemove?(id) }, for: .touchUpInside)
            addSubview(button)
            return (id: id, button: button)
        }
        setNeedsLayout()
    }

    /// The height the chips need at this width; zero without chips.
    func height(forWidth width: CGFloat) -> CGFloat {
        layout(width: width).height
    }

    private func layout(width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        guard !buttons.isEmpty else { return ([], 0) }
        let maximumWidth = max(1, width - Self.horizontalInset * 2)
        var frames = [CGRect]()
        var x = Self.horizontalInset
        var y = Self.verticalInset
        var lineHeight: CGFloat = 0
        for entry in buttons {
            var size = entry.button.sizeThatFits(CGSize(width: maximumWidth, height: .greatestFiniteMagnitude))
            size.width = min(size.width, maximumWidth)
            if x > Self.horizontalInset, x + size.width > width - Self.horizontalInset {
                x = Self.horizontalInset
                y += lineHeight + Self.spacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + Self.spacing
            lineHeight = max(lineHeight, size.height)
        }
        return (frames, y + lineHeight + Self.verticalInset)
    }
}
