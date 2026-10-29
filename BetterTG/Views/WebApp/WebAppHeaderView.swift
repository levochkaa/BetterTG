// WebAppHeaderView.swift

import UIKit

/// WebAppController's ordinary navigation bar, using BetterTG's shared bar background and glass button groups.
/// Explicit Web App header colours keep their solid background and matching foreground, as Telegram requires.
final class WebAppHeaderView: UIView {
    static let contentHeight: CGFloat = 64

    var onBack: (() -> Void)?
    var menu: (() -> [UIMenuElement])?
    var title = "" {
        didSet { titleLabel.text = title }
    }

    private let backdrop = TelegramBarBackgroundView(edge: .top)
    private let leftPlatter = TelegramGlassPlatter(role: .leading)
    private let rightPlatter = TelegramGlassPlatter(role: .trailing(0))
    private let leftButton = UIButton(type: .custom)
    private let leftContent = UIStackView()
    private let leftIcon = UIImageView()
    private let leftTitle = UILabel()
    private let moreButton = UIButton.telegramGlassIcon(UIImage(systemName: "ellipsis"))
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var hasBack = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(backdrop)
        addSubview(leftPlatter)
        addSubview(rightPlatter)
        leftPlatter.customContent = leftButton
        leftPlatter.glassView.contentView.addSubview(leftButton)
        leftButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leftButton.leadingAnchor.constraint(equalTo: leftPlatter.glassView.contentView.leadingAnchor),
            leftButton.trailingAnchor.constraint(equalTo: leftPlatter.glassView.contentView.trailingAnchor),
            leftButton.topAnchor.constraint(equalTo: leftPlatter.glassView.contentView.topAnchor),
            leftButton.bottomAnchor.constraint(equalTo: leftPlatter.glassView.contentView.bottomAnchor),
        ])
        leftContent.axis = .horizontal
        leftContent.alignment = .center
        leftContent.spacing = 4
        leftContent.isUserInteractionEnabled = false
        leftContent.translatesAutoresizingMaskIntoConstraints = false
        leftIcon.contentMode = .center
        leftTitle.font = .systemFont(ofSize: 17)
        leftContent.addArrangedSubview(leftIcon)
        leftContent.addArrangedSubview(leftTitle)
        leftButton.addSubview(leftContent)
        NSLayoutConstraint.activate([
            leftContent.centerXAnchor.constraint(equalTo: leftButton.centerXAnchor),
            leftContent.centerYAnchor.constraint(equalTo: leftButton.centerYAnchor),
        ])
        leftButton.addAction(UIAction { [weak self] _ in self?.onBack?() }, for: .touchUpInside)
        moreButton.accessibilityLabel = L10n.telegram("Common.More")
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] completion in
            completion(self?.menu?() ?? [])
        }])
        rightPlatter.setItems([moreButton])
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.text = L10n.telegram("WebApp.Miniapp")
        for label in [titleLabel, subtitleLabel] {
            label.textAlignment = .center
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }
        setBackVisible(false)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        backdrop.frame = bounds
        let edge = TelegramGlassPlatter.edgeInset
        let height = TelegramGlassPlatter.height
        let leftWidth = hasBack
            ? max(height, ceil(leftContent.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width) + 24)
            : height
        leftPlatter.frame = CGRect(x: safeAreaInsets.left + edge, y: 10, width: leftWidth, height: height)
        rightPlatter.frame = CGRect(
            x: bounds.width - safeAreaInsets.right - edge - height,
            y: 10,
            width: height,
            height: height,
        )
        let inset = max(leftPlatter.frame.maxX, bounds.width - rightPlatter.frame.minX) + 8
        let width = max(0, bounds.width - 2 * inset)
        titleLabel.frame = CGRect(x: inset, y: 13, width: width, height: 22)
        subtitleLabel.frame = CGRect(x: inset, y: 35, width: width, height: 16)
    }

    func setBackVisible(_ visible: Bool) {
        hasBack = visible
        leftIcon.image = UIImage(
            systemName: visible ? "chevron.backward" : "xmark",
            withConfiguration: UIButton.telegramGlassIconConfiguration,
        )
        leftTitle.text = L10n.telegram("Common.Back")
        leftTitle.isHidden = !visible
        leftButton.accessibilityLabel = L10n.telegram(visible ? "Common.Back" : "Common.Close")
        setNeedsLayout()
    }

    func setColors(header: UIColor, isCustom: Bool, usesDarkContent: Bool) {
        backdrop.isHidden = isCustom
        backgroundColor = isCustom ? header : .clear
        let foreground: UIColor = usesDarkContent ? .black : .white
        titleLabel.textColor = foreground
        subtitleLabel.textColor = foreground.withAlphaComponent(0.6)
        leftIcon.tintColor = foreground
        leftTitle.textColor = foreground
        moreButton.tintColor = foreground
        // Match the glass's contrast to the app-provided header, without changing the page's theme.
        for platter in [leftPlatter, rightPlatter] {
            platter.overrideUserInterfaceStyle = usesDarkContent ? .light : .dark
        }
    }
}
