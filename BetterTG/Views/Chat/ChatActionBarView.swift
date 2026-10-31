// ChatActionBarView.swift

import UIKit

// MARK: - ChatActionBarView

/// Telegram's ChatReportPeerTitlePanelNode in its classic layout, under the navigation bar of a chat from someone new:
/// 16 pt buttons (Block and the spam reports in red, the rest in the accent) spread across a 40 pt bar with the
/// encircled close button on the right, or the notice that the person is an admin of a chat the user asked to join.
final class ChatActionBarView: UIView {
    enum Content: Equatable {
        case buttons([ChatVM.ActionBarButton])
        /// The notice text, the person's and the chat's names in bold.
        case notice(NSAttributedString)
    }

    static let buttonsHeight = CGFloat(40)

    /// ChatReportPeerTitlePanelNode's contentRightInset and the close button's room (additionalRightInset).
    private static let contentRightInset = CGFloat(14)
    private static let closeRoom = CGFloat(36)

    var onButton: ((ChatVM.ActionBarButton) -> Void)?
    var onNotice: (() -> Void)?
    var onClose: (() -> Void)?

    private(set) var content: Content?

    private var buttons = [(ChatVM.ActionBarButton, UIButton)]()
    private let noticeLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let separator = UIView()

    #if DEBUG
        var probeButtonFrames: [CGRect] {
            buttons.map(\.1.frame)
        }

        var probeCloseFrame: CGRect {
            closeButton.frame
        }
    #endif

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        separator.backgroundColor = .separator
        addSubview(separator)
        noticeLabel.numberOfLines = 0
        noticeLabel.textAlignment = .center
        noticeLabel.isUserInteractionEnabled = true
        noticeLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(noticeTapped)))
        addSubview(noticeLabel)
        closeButton.setImage(
            UIImage(systemName: "xmark.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18)),
            for: .normal,
        )
        closeButton.accessibilityLabel = L10n.telegram("Common.Close")
        closeButton.accessibilityIdentifier = "chat-action-bar-close"
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        addSubview(closeButton)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let pixel = 1 / max(traitCollection.displayScale, 1)
        separator.frame = CGRect(x: 0, y: bounds.height - pixel, width: width, height: pixel)
        let contentRightInset = Self.contentRightInset + safeAreaInsets.right
        let panelHeight = content.map { height(for: $0, width: width) } ?? Self.buttonsHeight
        let closeSize = closeButton.sizeThatFits(CGSize(width: 44, height: 44))
        closeButton.frame = CGRect(
            x: width - contentRightInset - closeSize.width,
            y: floor((panelHeight - closeSize.height) / 2),
            width: closeSize.width,
            height: closeSize.height,
        )
        if case .notice = content {
            let noticeWidth = noticeWidth(for: width)
            let size = noticeLabel.sizeThatFits(CGSize(width: noticeWidth, height: 80))
            noticeLabel.frame = CGRect(
                x: floor((width - size.width) / 2),
                y: 10,
                width: size.width,
                height: size.height,
            )
            return
        }
        layoutButtons(width: width, contentRightInset: contentRightInset)
    }

    /// The bar's height for its content: 40 pt, and for the notice its text's height past 19 pt with 15 pt at least.
    func height(for content: Content, width: CGFloat) -> CGFloat {
        switch content {
        case .buttons:
            return Self.buttonsHeight
        case .notice(let text):
            let textHeight = ceil(text.boundingRect(
                with: CGSize(width: noticeWidth(for: width), height: 80),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil,
            )
            .height)
            return Self.buttonsHeight + max(15, textHeight - 19)
        }
    }

    func update(content: Content) {
        guard content != self.content else { return }
        self.content = content
        for (_, button) in buttons {
            button.removeFromSuperview()
        }
        buttons = []
        switch content {
        case .buttons(let items):
            noticeLabel.isHidden = true
            for item in items {
                let button = UIButton(type: .system)
                button.setTitle(item.title, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 16)
                button.titleLabel?.lineBreakMode = .byTruncatingTail
                button.accessibilityIdentifier = "chat-action-bar-button"
                button.addAction(UIAction { [weak self] _ in self?.onButton?(item) }, for: .touchUpInside)
                addSubview(button)
                buttons.append((item, button))
            }
        case .notice(let text):
            noticeLabel.attributedText = text
            noticeLabel.isHidden = false
        }
        applyColors()
        setNeedsLayout()
    }

    /// ChatReportPeerTitlePanelNode.updateLayout: one button fills the room left of the close button; several share
    /// it at their own widths with up to 110 pt between them, centred, and step 16 pt left if they reach the edge.
    private func layoutButtons(width: CGFloat, contentRightInset: CGFloat) {
        guard !buttons.isEmpty else { return }
        // Beside iPhone Duo's strip the sides differ: the buttons centre between them.
        let leftInset = max(safeAreaInsets.left, contentRightInset - safeAreaInsets.right)
        let height = Self.buttonsHeight
        if buttons.count == 1 {
            let buttonWidth = floor(width - leftInset - contentRightInset - Self.closeRoom)
            buttons[0].1.frame = CGRect(
                x: floor(leftInset + Self.closeRoom / 2),
                y: 0,
                width: buttonWidth,
                height: height,
            )
            return
        }
        var areaWidth = width - leftInset - contentRightInset - Self.closeRoom
        let maxButtonWidth = floor(areaWidth / CGFloat(buttons.count))
        let buttonsWidth = buttons.map {
            min(maxButtonWidth, $0.1.sizeThatFits(CGSize(width: maxButtonWidth, height: 100)).width)
        }
        .reduce(0, +)
        if buttonsWidth < areaWidth - 20 { areaWidth += Self.closeRoom }
        let maxSpacing = floor((areaWidth - buttonsWidth) / CGFloat(buttons.count - 1))
        let spacing = min(maxSpacing, 110)
        let totalWidth = buttonsWidth + CGFloat(buttons.count - 1) * spacing
        var originX = leftInset + floor((areaWidth - totalWidth) / 2)
        let buttonWidth = floor(totalWidth / CGFloat(buttons.count))
        var frames = [CGRect]()
        for _ in buttons {
            frames.append(CGRect(x: originX, y: 0, width: buttonWidth, height: height))
            originX += buttonWidth
        }
        if let last = frames.last, last.maxX >= width - 20 {
            frames = frames.map { $0.offsetBy(dx: -16, dy: 0) }
        }
        for (index, frame) in frames.enumerated() {
            buttons[index].1.frame = frame
        }
    }

    /// The notice is 80 pt narrower than the bar.
    private func noticeWidth(for width: CGFloat) -> CGFloat {
        max(1, width - safeAreaInsets.left - safeAreaInsets.right - 80)
    }

    private func applyColors() {
        for (item, button) in buttons {
            let color: UIColor = item.isDestructive ? .systemRed : tintColor
            button.setTitleColor(color, for: .normal)
            button.setTitleColor(color.withAlphaComponent(0.7), for: .highlighted)
        }
        closeButton.tintColor = tintColor
    }

    @objc private func noticeTapped() {
        onNotice?()
    }
}
