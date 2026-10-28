// TelegramGlassPlatter.swift

import UIKit

// MARK: - TelegramGlassPlatter

/// A navigation bar's Liquid Glass capsule around one or more of its buttons, as UIKit groups a bar's items into
/// sections on iOS 26 (Telegram's NavigationBarRowLayout): one icon is a 44 pt circle, several icons share a pill
/// with 6 pt ends, a text button gets a pill of its own. The items keep their own actions; the platter only hosts them.
final class TelegramGlassPlatter: UIView {
    // MARK: Internal

    /// Where a platter sits in its bar, which the push and pop morph pairs across screens.
    enum Role: Hashable {
        /// The back button or the bar's left buttons.
        case leading
        /// A further left pill, counted from the leading one inward, such as a picker's selected count.
        case leadingSection(Int)
        /// A right pill, counted from the screen edge inward.
        case trailing(Int)
        /// A chat header's title pill; it pairs only with another screen's title pill.
        case title
    }

    static let height: CGFloat = 44
    /// UIKit's gap between two pills on one side of the bar (`interSectionSpacing`, read on iOS 27).
    static let interSectionSpacing: CGFloat = 12
    /// The bar's inset from the safe area to its first platter.
    static let edgeInset: CGFloat = 16
    /// The space under a bar's row of platters: UIKit's iOS 26 bar is 54 pt with its 44 pt items at the top.
    static let barBottomInset: CGFloat = 10
    /// An icon item's width; several icons in one pill get 6 pt ends.
    static let iconWidth: CGFloat = 44
    static let pillEndInset: CGFloat = 6
    /// A text item's padding on either side (NavigationButtonComponent's textInset).
    static let textInset: CGFloat = 12
    /// A title pill's padding on either side of its text (ChatTitleComponent's `containerSideInset`).
    static let titleInset: CGFloat = 14

    override var intrinsicContentSize: CGSize {
        CGSize(width: customContent == nil ? preferredWidth : UIView.noIntrinsicMetric, height: Self.height)
    }

    let role: Role
    let glassView = UIVisualEffectView()

    /// A view the owner lays out inside the glass itself, such as a chat header's title, in place of items. Its own
    /// constraints size the platter.
    var customContent: UIView? {
        didSet { invalidateIntrinsicContentSize() }
    }

    // MARK: Private

    /// The hosted items, laid out by hand: a stack view gave a text button after a hidden one no height.
    private var items = [UIView]()

    /// The visible items, in the order shown.
    var visibleItems: [UIView] {
        if let customContent { return customContent.isHidden ? [] : [customContent] }
        return items.filter { !$0.isHidden }
    }

    /// Whether any item shows; the platter hides itself otherwise.
    var hasVisibleItems: Bool { !visibleItems.isEmpty }

    /// The pill's width for its visible items: an icon's 44 pt, a text's own width, a custom view's fitting width,
    /// and the ends.
    var preferredWidth: CGFloat {
        let visible = visibleItems
        guard customContent == nil else { return bounds.width }
        return visible.reduce(endInset(for: visible) * 2) { $0 + Self.width(of: $1) }
    }

    init(role: Role) {
        self.role = role
        super.init(frame: .zero)
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        glassView.effect = effect
        glassView.cornerConfiguration = .capsule()
        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)
        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard customContent == nil else { return }
        let visible = visibleItems
        var x = endInset(for: visible)
        for item in visible {
            let width = Self.width(of: item)
            item.frame = CGRect(x: x, y: 0, width: width, height: bounds.height)
            x += width
        }
    }

    private static func width(of item: UIView) -> CGFloat {
        if let button = item as? UIButton {
            guard let title = button.title(for: .normal), !title.isEmpty else { return iconWidth }
            return ceil(button.intrinsicContentSize.width)
        }
        // A custom view (a spinner, an avatar) takes its fitting width, at least an icon's.
        let fitting = item.intrinsicContentSize.width == UIView.noIntrinsicMetric
            ? item.sizeThatFits(CGSize(width: 200, height: height)).width
            : item.intrinsicContentSize.width
        return max(iconWidth, ceil(fitting))
    }

    /// Hosts `items` in order. Icon buttons get the `label` tint glass bar items use; text buttons keep theirs.
    func setItems(_ newItems: [UIView]) {
        for item in items where !newItems.contains(where: { $0 === item }) {
            item.removeFromSuperview()
        }
        items = newItems
        for item in newItems {
            item.translatesAutoresizingMaskIntoConstraints = true
            if item.superview !== glassView.contentView { glassView.contentView.addSubview(item) }
        }
        refresh()
    }

    /// Re-reads which items show: the pill's width and ends, and whether the platter itself shows.
    func refresh() {
        isHidden = visibleItems.isEmpty
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    /// The platter's look without its items, for the morph to draw in their place. The items draw in the platter's
    /// traits: a label drawn for the picture would otherwise resolve its dynamic colour, a status's grey, in none.
    func renderedItems() -> UIImage? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat(for: traitCollection)
        format.opaque = false
        var image: UIImage?
        traitCollection.performAsCurrent {
            image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
                for item in visibleItems {
                    context.cgContext.saveGState()
                    let origin = item.convert(CGPoint.zero, to: self)
                    context.cgContext.translateBy(x: origin.x, y: origin.y)
                    item.layer.render(in: context.cgContext)
                    context.cgContext.restoreGState()
                }
            }
        }
        return image
    }

    /// One icon is a circle with no ends; a lone text gets its text inset; several items get 6 pt ends.
    private func endInset(for visible: [UIView]) -> CGFloat {
        guard visible.count == 1 else { return Self.pillEndInset }
        let isText = (visible[0] as? UIButton)?.title(for: .normal)?.isEmpty == false
        return isText ? Self.textInset : 0
    }
}

// MARK: - UIView + enclosingTelegramGlassPlatter

extension UIView {
    /// The glass platter this bar item sits in, if any.
    var enclosingTelegramGlassPlatter: TelegramGlassPlatter? {
        sequence(first: self, next: \.superview).lazy.compactMap { $0 as? TelegramGlassPlatter }.first
    }
}

// MARK: - TelegramGlassBarButton

extension UIButton {
    /// The symbol size of a glass bar item: the body size at the large scale, as UIKit draws bar button symbols (a
    /// 21 pt magnifying glass on iOS 27.2).
    static let telegramGlassIconConfiguration = UIImage.SymbolConfiguration(
        pointSize: 17,
        weight: .medium,
        scale: .large,
    )

    /// An icon button styled for a glass platter: the system bar item symbol in the label color.
    static func telegramGlassIcon(_ image: UIImage?, accessibilityLabel: String? = nil) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(image, for: .normal)
        button.setPreferredSymbolConfiguration(telegramGlassIconConfiguration, forImageIn: .normal)
        button.tintColor = .label
        button.accessibilityLabel = accessibilityLabel
        return button
    }
}

// MARK: - UIButton + floating glass

extension UIButton {
    /// Telegram 13's floating chat buttons (ChatHistoryNavigationButtonNode): a circle of interactive glass with the
    /// icon inside the glass in the label color, and no fill, border or shadow of its own. The button's own image
    /// would sit under the glass and be refracted by it, so the icon moves into the glass. The glass takes the touch,
    /// as UIKit swells interactive glass only under a touch that lands inside it, and its tap runs the button's
    /// action, as ChatHistoryNavigationButtonNode's tap on its glass does; the button's own recognizers still see it.
    func applyTelegramFloatingGlass(icon: UIImage?) {
        guard !subviews.contains(where: { $0 is TelegramFloatingGlassBackground }) else { return }
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        let glass = TelegramFloatingGlassBackground(effect: effect)
        glass.cornerConfiguration = .capsule()
        glass.contentView.addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(telegramFloatingGlassTapped),
        ))
        glass.frame = bounds
        glass.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let iconView = UIImageView(image: icon)
        iconView.tintColor = .label
        iconView.contentMode = .center
        iconView.frame = glass.contentView.bounds
        iconView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        glass.contentView.addSubview(iconView)
        insertSubview(glass, at: 0)
        setImage(nil, for: .normal)
        backgroundColor = .clear
        layer.borderWidth = 0
        layer.shadowOpacity = 0
    }

    @objc private func telegramFloatingGlassTapped() {
        guard isEnabled else { return }
        sendActions(for: .touchUpInside)
    }
}

// MARK: - TelegramFloatingGlassBackground

private final class TelegramFloatingGlassBackground: UIVisualEffectView {}
