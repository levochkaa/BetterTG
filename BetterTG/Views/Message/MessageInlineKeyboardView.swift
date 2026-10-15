// MessageInlineKeyboardView.swift

import TDLibKit
import UIKit

// MARK: - MessageInlineKeyboardView

/// Telegram's inline keyboard under a message (`ChatMessageActionButtonsNode`): rows of equal-width 42 pt buttons,
/// 2 pt apart, as wide as the bubble. The bubble widens to the widest row's minimum width.
final class MessageInlineKeyboardView: UIView {
    // MARK: Internal

    static let buttonHeight: CGFloat = 42
    static let spacing: CGFloat = 2

    /// The narrowest width that fits every row's titles: the widest button of a row times its count.
    private(set) var minimumWidth: CGFloat = 0
    private(set) var buttons = [(button: TDNativeInlineKeyboardButton, view: UIView)]()

    // MARK: Private

    private let rowsStack = UIStackView()
    private var onTap: ((TDNativeInlineKeyboardButton, UIView) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        rowsStack.axis = .vertical
        rowsStack.spacing = Self.spacing
        addSubview(rowsStack)
        NSLayoutConstraint.activate([
            rowsStack.topAnchor.constraint(equalTo: topAnchor),
            rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowsStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func isDisabled(_ button: TDNativeInlineKeyboardButton) -> Bool {
        if case .inlineKeyboardButtonTypeDisabled = button.type { return true }
        return false
    }

    /// Lays out the rows; false when there is nothing to show. A keyboard that isn't interactive (while messages are
    /// selected) keeps its look.
    @discardableResult func configure(
        rows: [[TDNativeInlineKeyboardButton]],
        isInteractive: Bool,
        onTap: @escaping (TDNativeInlineKeyboardButton, UIView) -> Void,
    ) -> Bool {
        prepareForReuse()
        let rows = rows.filter { !$0.isEmpty }
        guard !rows.isEmpty else { return false }
        self.onTap = onTap
        isUserInteractionEnabled = isInteractive
        var minimumWidth = CGFloat.zero
        for (rowIndex, row) in rows.enumerated() {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.spacing = Self.spacing
            var widestButton = CGFloat.zero
            for (columnIndex, button) in row.enumerated() {
                let isLastRow = rowIndex == rows.count - 1
                let view = InlineKeyboardButtonView(
                    button: button,
                    roundsBottomLeft: isLastRow && columnIndex == 0,
                    roundsBottomRight: isLastRow && columnIndex == row.count - 1,
                )
                view.isEnabled = !Self.isDisabled(button)
                view.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
                widestButton = max(widestButton, view.minimumWidth)
                rowStack.addArrangedSubview(view)
                buttons.append((button, view))
            }
            minimumWidth = max(
                minimumWidth,
                widestButton * CGFloat(row.count) + Self.spacing * CGFloat(row.count - 1),
            )
            rowsStack.addArrangedSubview(rowStack)
        }
        self.minimumWidth = ceil(minimumWidth)
        return true
    }

    func prepareForReuse() {
        onTap = nil
        buttons = []
        minimumWidth = 0
        for row in rowsStack.arrangedSubviews {
            rowsStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
    }

    /// Sends a button's tap, as VoiceOver's custom actions for the cell do.
    func activate(_ index: Int) {
        guard isUserInteractionEnabled, buttons.indices.contains(index),
              (buttons[index].view as? UIControl)?.isEnabled == true else { return }
        onTap?(buttons[index].button, buttons[index].view)
    }

    @objc private func buttonTapped(_ sender: UIControl) {
        guard let index = buttons.firstIndex(where: { $0.view === sender }) else { return }
        onTap?(buttons[index].button, sender)
    }
}

// MARK: - InlineKeyboardButtonView

/// One button of `ChatMessageActionButtonNode`: a medium 16 pt title, Telegram's styles, and a 12 pt corner icon
/// for buttons that leave the chat.
private final class InlineKeyboardButtonView: UIControl {
    // MARK: Private

    private static let sideInset: CGFloat = 8
    private static let iconSize: CGFloat = 12

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : (isEnabled ? 1 : 0.5) }
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.5 }
    }

    // MARK: Internal

    let minimumWidth: CGFloat

    private let titleLabel = UILabel()
    private let iconView = UIImageView()
    private let backgroundLayer = CAShapeLayer()
    private let fillColor: UIColor
    private let roundsBottomLeft: Bool
    private let roundsBottomRight: Bool

    init(button: TDNativeInlineKeyboardButton, roundsBottomLeft: Bool, roundsBottomRight: Bool) {
        self.roundsBottomLeft = roundsBottomLeft
        self.roundsBottomRight = roundsBottomRight
        let (fill, foreground) = Self.colors(for: button.style)
        self.fillColor = fill
        let iconName = Self.iconName(for: button.type)
        let titleFont = UIFont.systemFont(ofSize: 16, weight: .medium)
        let titleWidth = ceil((button.text as NSString).size(withAttributes: [.font: titleFont]).width)
        // Telegram keeps the title clear of the corner icon (`minimumSideInset`).
        let inset = iconName == nil ? Self.sideInset : 4 + Self.iconSize
        self.minimumWidth = titleWidth + inset * 2
        super.init(frame: .zero)

        layer.addSublayer(backgroundLayer)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: InlineKeyboardButtonView, _) in
            view.setNeedsLayout()
        }

        titleLabel.text = button.text
        titleLabel.font = titleFont
        titleLabel.textColor = foreground
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.isUserInteractionEnabled = false
        addSubview(titleLabel)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = iconName.flatMap { UIImage(systemName: $0) }
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        iconView.tintColor = foreground
        iconView.contentMode = .center
        iconView.isHidden = iconName == nil
        iconView.isUserInteractionEnabled = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: MessageInlineKeyboardView.buttonHeight),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: inset),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            iconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),
        ])
        isAccessibilityElement = true
        accessibilityTraits = Self.isLink(button.type) ? [.button, .link] : .button
        accessibilityLabel = button.text
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundLayer.frame = bounds
        backgroundLayer.fillColor = fillColor.resolvedColor(with: traitCollection).cgColor
        // The bottom row's outer corners follow the bubble, as Telegram's bottomLeft/bottomRight positions do.
        backgroundLayer.path = Self.path(
            in: bounds,
            radius: 8,
            bottomLeft: roundsBottomLeft ? 16 : 8,
            bottomRight: roundsBottomRight ? 16 : 8,
        )
        .cgPath
        CATransaction.commit()
    }

    private static func colors(for style: TDNativeButtonStyle) -> (UIColor, UIColor) {
        switch style {
        case .buttonStylePrimary: (.systemBlue, .white)
        case .buttonStyleDanger: (.systemRed, .white)
        case .buttonStyleSuccess: (.systemGreen, .white)
        case .buttonStyleLink: (.secondarySystemBackground, .systemBlue)
        case .buttonStyleDefault: (.secondarySystemBackground, .label)
        }
    }

    /// Telegram's corner icons: link for URLs and logins, the web app glyph, share for inline queries, profile,
    /// payment and copy.
    private static func iconName(for type: TDNativeInlineKeyboardButtonType) -> String? {
        switch type {
        case .inlineKeyboardButtonTypeLoginUrl, .inlineKeyboardButtonTypeUrl: "arrow.up.right"
        case .inlineKeyboardButtonTypeWebApp: "app"
        case .inlineKeyboardButtonTypeSwitchInline: "arrowshape.turn.up.right.fill"
        case .inlineKeyboardButtonTypeUser: "person.fill"
        case .inlineKeyboardButtonTypeBuy: "creditcard.fill"
        case .inlineKeyboardButtonTypeCopyText: "doc.on.doc.fill"
        case .inlineKeyboardButtonTypeCallback, .inlineKeyboardButtonTypeCallbackGame,
             .inlineKeyboardButtonTypeCallbackWithPassword, .inlineKeyboardButtonTypeDisabled: nil
        }
    }

    private static func isLink(_ type: TDNativeInlineKeyboardButtonType) -> Bool {
        switch type {
        case .inlineKeyboardButtonTypeLoginUrl, .inlineKeyboardButtonTypeUrl, .inlineKeyboardButtonTypeWebApp: true
        default: false
        }
    }

    private static func path(in rect: CGRect, radius: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat)
        -> UIBezierPath
    {
        let limit = min(rect.width, rect.height) / 2
        let topLeft = min(radius, limit)
        let topRight = min(radius, limit)
        let bottomLeft = min(bottomLeft, limit)
        let bottomRight = min(bottomRight, limit)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        path.addArc(
            withCenter: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight),
            radius: topRight, startAngle: -.pi / 2, endAngle: 0, clockwise: true,
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        path.addArc(
            withCenter: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight),
            radius: bottomRight, startAngle: 0, endAngle: .pi / 2, clockwise: true,
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        path.addArc(
            withCenter: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft),
            radius: bottomLeft, startAngle: .pi / 2, endAngle: .pi, clockwise: true,
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        path.addArc(
            withCenter: CGPoint(x: rect.minX + topLeft, y: rect.minY + topLeft),
            radius: topLeft, startAngle: .pi, endAngle: .pi * 3 / 2, clockwise: true,
        )
        path.close()
        return path
    }
}
