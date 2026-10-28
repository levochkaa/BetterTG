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
        /// A right pill, counted from the screen edge inward.
        case trailing(Int)
        /// A chat header's title pill; it pairs as the second right pill when the bar has at most one.
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
    /// A title pill's padding on either side of its text.
    static let titleInset: CGFloat = 16

    let role: Role
    let glassView = UIVisualEffectView()

    /// A view the owner lays out inside the glass itself, such as a chat header's title, in place of items.
    var customContent: UIView? {
        didSet { stack.isHidden = customContent != nil }
    }

    // MARK: Private

    private let stack = UIStackView()
    private var widthConstraints = [NSLayoutConstraint]()

    /// The visible items, in the order shown.
    var visibleItems: [UIView] {
        if let customContent { return customContent.isHidden ? [] : [customContent] }
        return stack.arrangedSubviews.filter { !$0.isHidden }
    }

    /// Whether any item shows; the platter hides itself otherwise.
    var hasVisibleItems: Bool { !visibleItems.isEmpty }

    init(role: Role) {
        self.role = role
        super.init(frame: .zero)
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        glassView.effect = effect
        glassView.cornerConfiguration = .capsule()
        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fill
        stack.isLayoutMarginsRelativeArrangement = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.topAnchor.constraint(equalTo: glassView.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor),
            heightAnchor.constraint(equalToConstant: Self.height),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    /// Hosts `items` in order. Icon buttons get the `label` tint glass bar items use; text buttons keep theirs.
    func setItems(_ items: [UIView]) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        widthConstraints.forEach { $0.isActive = false }
        widthConstraints = []
        for item in items {
            item.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(item)
            if let button = item as? UIButton {
                guard button.title(for: .normal)?.isEmpty != false else { continue }
                let constraint = item.widthAnchor.constraint(equalToConstant: Self.iconWidth)
                constraint.isActive = true
                widthConstraints.append(constraint)
            } else if item.intrinsicContentSize.width == UIView.noIntrinsicMetric {
                // A custom view (a spinner, an avatar) takes its fitting width, at least an icon's.
                let fitting = item.sizeThatFits(CGSize(width: 200, height: Self.height)).width
                let constraint = item.widthAnchor.constraint(equalToConstant: max(Self.iconWidth, fitting))
                constraint.isActive = true
                widthConstraints.append(constraint)
            }
        }
        refresh()
    }

    /// Re-reads which items show: the pill's ends and whether the platter itself shows.
    func refresh() {
        let visible = visibleItems
        let isSingleIcon = visible.count == 1 && widthConstraints.contains { $0.firstItem === visible[0] }
        let isText = visible.contains { ($0 as? UIButton)?.title(for: .normal)?.isEmpty == false }
        let end = isSingleIcon ? 0 : isText && visible.count == 1 ? Self.textInset : Self.pillEndInset
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: end, bottom: 0, trailing: end)
        isHidden = visible.isEmpty
    }

    /// The platter's look without its items, for the morph to draw in their place.
    func renderedItems() -> UIImage? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = traitCollection.displayScale
        format.opaque = false
        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
            for item in visibleItems {
                context.cgContext.saveGState()
                let origin = item.convert(CGPoint.zero, to: self)
                context.cgContext.translateBy(x: origin.x, y: origin.y)
                item.layer.render(in: context.cgContext)
                context.cgContext.restoreGState()
            }
        }
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
