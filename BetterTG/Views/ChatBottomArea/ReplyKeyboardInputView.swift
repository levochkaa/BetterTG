// ReplyKeyboardInputView.swift

import TDLibKit
import UIKit

// MARK: - ComposerInputResponder

/// Shows a composer panel where the system keyboard goes, as Telegram's `.inputButtons` (a bot's reply keyboard)
/// and `.media` (the emoji, sticker and GIF panel) input modes do: the composer makes this view first responder with
/// the panel as its input view or input view controller, and focusing the text view brings the system keyboard back.
final class ComposerInputResponder: UIView {
    /// Whether a composer panel currently stands in for the system keyboard, so its frame isn't taken for the system
    /// keyboard's height.
    private(set) static var isAnyActive = false

    override var canBecomeFirstResponder: Bool { keyboardInputView != nil || keyboardInputViewController != nil }

    override var inputView: UIView? { keyboardInputView }

    override var inputViewController: UIInputViewController? { keyboardInputViewController }

    var keyboardInputView: UIView?
    var keyboardInputViewController: UIInputViewController?
    var onActiveChange: (() -> Void)?

    @discardableResult override func becomeFirstResponder() -> Bool {
        let wasActive = isFirstResponder
        let became = super.becomeFirstResponder()
        if became, !wasActive {
            Self.isAnyActive = true
            onActiveChange?()
        }
        return became
    }

    @discardableResult override func resignFirstResponder() -> Bool {
        let wasActive = isFirstResponder
        let resigned = super.resignFirstResponder()
        if resigned, wasActive {
            Self.isAnyActive = false
            onActiveChange?()
        }
        return resigned
    }
}

// MARK: - ReplyKeyboardInputView

/// Telegram's `ChatButtonKeyboardInputNode`: rows of equal-width buttons with 18 pt insets, 6 pt between columns and
/// 5 pt between rows. The panel is as tall as the system keyboard and stretches its buttons to fill it; a resized
/// keyboard fits its rows instead. Taller content scrolls.
final class ReplyKeyboardInputView: UIInputView {
    // MARK: Private

    private static let verticalInset: CGFloat = 18
    private static let sideInset: CGFloat = 18
    private static let buttonHeight: CGFloat = 43
    private static let columnSpacing: CGFloat = 6
    private static let rowSpacing: CGFloat = 5

    private static var systemKeyboardHeights = [Int: CGFloat]()
    private static var systemKeyboardObserver: NSObjectProtocol?

    // MARK: Internal

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: panelHeight)
    }

    private let scrollView = UIScrollView()
    private var buttonRows = [[ReplyKeyboardButtonView]]()
    private var resizes = false
    private var panelHeight: CGFloat = 0
    private var configuredMessageID: Int64?
    private var configuredRevision: Int?
    private var onTap: ((TDNativeKeyboardButton) -> Void)?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 260), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.alwaysBounceVertical = false
        scrollView.scrollsToTop = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsHorizontalScrollIndicator = false
        addSubview(scrollView)
        accessibilityLabel = L10n.telegram("VoiceOver.BotKeyboard")
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        guard !buttonRows.isEmpty else { return }
        let bottomInset = safeAreaInsets.bottom
        let rowCount = CGFloat(buttonRows.count)
        let rowsHeight = Self.rowsHeight(rowCount: buttonRows.count)
        var buttonHeight = Self.buttonHeight
        if !resizes, rowsHeight < bounds.height {
            buttonHeight = floor(
                (bounds.height - bottomInset - Self.verticalInset * 2 - max(0, rowCount - 1) * Self.rowSpacing)
                    / rowCount,
            )
        }
        let leadingInset = Self.sideInset + safeAreaInsets.left
        let trailingInset = Self.sideInset + safeAreaInsets.right
        var y = Self.verticalInset
        for row in buttonRows {
            let count = CGFloat(row.count)
            let width = floor(
                (bounds.width - leadingInset - trailingInset + Self.columnSpacing - count * Self.columnSpacing) / count,
            )
            for (column, button) in row.enumerated() {
                button.frame = CGRect(
                    x: leadingInset + CGFloat(column) * (width + Self.columnSpacing),
                    y: y,
                    width: width,
                    height: buttonHeight,
                )
            }
            y += buttonHeight + Self.rowSpacing
        }
        scrollView.contentSize = CGSize(width: bounds.width, height: rowsHeight)
        scrollView.contentInset.bottom = bottomInset
    }

    /// Remembers the system keyboard's height, which a bot keyboard takes (`standardInputHeight`).
    static func observeSystemKeyboard() {
        guard systemKeyboardObserver == nil else { return }
        systemKeyboardObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification,
            object: nil,
            queue: .main,
        ) { notification in
            guard let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?
                .cgRectValue else { return }
            MainActor.assumeIsolated {
                // A hardware keyboard leaves only a shortcut bar; it isn't a keyboard height to match.
                guard !ComposerInputResponder.isAnyActive, frame.height >= 150 else { return }
                ReplyKeyboardInputView.systemKeyboardHeights[Int(frame.width.rounded())] = frame.height
            }
        }
    }

    /// The last system keyboard height for this width; before one was seen, Telegram's `DeviceMetrics` keyboard and
    /// predictive bar heights, which include the home indicator inset. Telegram's panels take it as
    /// `standardInputHeight`.
    static func standardHeight(containerSize: CGSize, bottomInset: CGFloat) -> CGFloat {
        if let height = systemKeyboardHeights[Int(containerSize.width.rounded())] { return height }
        let isLandscape = containerSize.width > containerSize.height
        let hasHomeIndicator = bottomInset > 0
        return switch (isLandscape, hasHomeIndicator) {
        case (false, true): 291 + 42
        case (false, false): 216 + 42
        case (true, true): 171 + 37
        case (true, false): 162 + 37
        }
    }

    private static func rowsHeight(rowCount: Int) -> CGFloat {
        verticalInset * 2 + CGFloat(rowCount) * buttonHeight + CGFloat(max(0, rowCount - 1)) * rowSpacing
    }

    private static func panelHeight(
        rowCount: Int,
        resizes: Bool,
        standardHeight: CGFloat,
        bottomInset: CGFloat,
    ) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return resizes
            ? min(standardHeight + bottomInset, rowsHeight(rowCount: rowCount) + bottomInset)
            : standardHeight
    }

    /// Shows a keyboard's rows; true when the panel's height changed, so the responder must reload its input view.
    @discardableResult func configure(
        keyboard: ChatReplyKeyboardModel.Keyboard,
        containerSize: CGSize,
        bottomInset: CGFloat,
        onTap: @escaping (TDNativeKeyboardButton) -> Void,
    ) -> Bool {
        self.onTap = onTap
        if configuredMessageID != keyboard.messageID || configuredRevision != keyboard.revision {
            configuredMessageID = keyboard.messageID
            configuredRevision = keyboard.revision
            resizes = keyboard.markup.resizeKeyboard
            rebuild(keyboard.markup.rows.filter { !$0.isEmpty })
        }
        let height = Self.panelHeight(
            rowCount: buttonRows.count,
            resizes: resizes,
            standardHeight: Self.standardHeight(containerSize: containerSize, bottomInset: bottomInset),
            bottomInset: bottomInset,
        )
        guard abs(height - panelHeight) > 0.5 else { return false }
        panelHeight = height
        frame.size.height = height
        invalidateIntrinsicContentSize()
        return true
    }

    private func rebuild(_ rows: [[TDNativeKeyboardButton]]) {
        for row in buttonRows {
            for button in row {
                button.removeFromSuperview()
            }
        }
        buttonRows = rows.map { row in
            row.map { button in
                let view = ReplyKeyboardButtonView(button: button)
                view.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
                scrollView.addSubview(view)
                return view
            }
        }
        scrollView.setContentOffset(.zero, animated: false)
        setNeedsLayout()
    }

    @objc private func buttonTapped(_ sender: ReplyKeyboardButtonView) {
        onTap?(sender.button)
    }
}

// MARK: - ReplyKeyboardButtonView

/// `ChatButtonKeyboardInputButtonNode`: a rounded key with a regular 16 pt title of up to two lines, in Telegram's
/// button styles, and a corner glyph for a Web App button.
private final class ReplyKeyboardButtonView: UIControl {
    private static let keyFill = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.25) : UIColor(white: 1, alpha: 0.85)
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            if isHighlighted {
                fillView.alpha = 0.9
            } else {
                UIView.animate(withDuration: 0.2) { self.fillView.alpha = 1 }
            }
        }
    }

    // MARK: Internal

    let button: TDNativeKeyboardButton

    // MARK: Private

    private let fillView = UIView()
    private let titleLabel = UILabel()
    private let iconView = UIImageView()

    init(button: TDNativeKeyboardButton) {
        self.button = button
        super.init(frame: .zero)
        let (fill, foreground) = Self.colors(for: button.style)
        fillView.backgroundColor = fill
        fillView.layer.cornerRadius = 10
        fillView.layer.cornerCurve = .continuous
        fillView.isUserInteractionEnabled = false
        addSubview(fillView)

        titleLabel.text = button.text
        titleLabel.font = .systemFont(ofSize: 16)
        titleLabel.textColor = foreground
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isUserInteractionEnabled = false
        addSubview(titleLabel)

        if case .keyboardButtonTypeWebApp = button.type {
            iconView.image = UIImage(systemName: "app")
            iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            iconView.tintColor = foreground
            iconView.contentMode = .center
            iconView.isUserInteractionEnabled = false
            addSubview(iconView)
        }

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = button.text
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fillView.frame = bounds
        let maximumWidth = max(0, bounds.width - 16)
        let size = titleLabel.sizeThatFits(CGSize(width: maximumWidth, height: bounds.height))
        let width = min(ceil(size.width), maximumWidth)
        let height = min(ceil(size.height), bounds.height)
        titleLabel.frame = CGRect(
            x: floor((bounds.width - width) / 2),
            y: floor((bounds.height - height) / 2),
            width: width,
            height: height,
        )
        iconView.frame = CGRect(x: bounds.width - 16, y: 4, width: 12, height: 12)
    }

    /// Telegram's key fill: translucent white keys, or the primary, danger and success colors with white titles.
    private static func colors(for style: TDNativeButtonStyle) -> (UIColor, UIColor) {
        switch style {
        case .buttonStylePrimary: (.systemBlue, .white)
        case .buttonStyleDanger: (UIColor(red: 1, green: 0x3B / 255, blue: 0x30 / 255, alpha: 1), .white)
        case .buttonStyleSuccess: (UIColor(red: 0x21 / 255, green: 0xB2 / 255, blue: 0x46 / 255, alpha: 1), .white)
        case .buttonStyleLink: (keyFill, .systemBlue)
        case .buttonStyleDefault: (keyFill, .label)
        }
    }
}
