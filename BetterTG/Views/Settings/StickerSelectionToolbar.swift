// StickerSelectionToolbar.swift

import UIKit

/// ItemListControllerNode's GlassControlPanel: three separate 44 pt text capsules. BetterTG adds its shared
/// full-width bar background, 16 pt side margins and 10 pt below the buttons, as on its other bars.
final class StickerSelectionToolbar: UIView {
    static let contentHeight = TelegramGlassPlatter.height + TelegramGlassPlatter.barBottomInset

    let deleteButton = UIButton(type: .system)
    let archiveButton = UIButton(type: .system)
    let shareButton = UIButton(type: .system)

    private let background = TelegramBarBackgroundView(edge: .bottom)
    private let container: UIVisualEffectView
    private let platters = [
        TelegramGlassPlatter(role: .leading),
        TelegramGlassPlatter(role: .title),
        TelegramGlassPlatter(role: .trailing(0)),
    ]

    override init(frame: CGRect) {
        let effect = UIGlassContainerEffect()
        effect.spacing = TelegramGlassPlatter.interSectionSpacing
        self.container = UIVisualEffectView(effect: effect)
        super.init(frame: frame)
        background.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)
        addSubview(container)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.heightAnchor.constraint(equalToConstant: TelegramGlassPlatter.height),
        ])
        let buttons = [deleteButton, archiveButton, shareButton]
        let keys = ["StickerPacks.ActionDelete", "StickerPacks.ActionArchive", "StickerPacks.ActionShare"]
        for (index, platter) in platters.enumerated() {
            let button = buttons[index]
            button.setTitle(L10n.telegram(keys[index]), for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.setTitleColor(.label, for: .normal)
            button.setTitleColor(.label, for: .disabled)
            // GlassControlGroup's button fills the capsule, including its horizontal text padding.
            platter.customContent = button
            button.translatesAutoresizingMaskIntoConstraints = false
            platter.glassView.contentView.addSubview(button)
            platter.translatesAutoresizingMaskIntoConstraints = false
            container.contentView.addSubview(platter)
            let width = platter.widthAnchor.constraint(equalToConstant: max(
                TelegramGlassPlatter.height,
                ceil(button.intrinsicContentSize.width) + TelegramGlassPlatter.textInset * 2,
            ))
            width.priority = .defaultHigh
            NSLayoutConstraint.activate([
                platter.topAnchor.constraint(equalTo: container.contentView.topAnchor),
                platter.heightAnchor.constraint(equalToConstant: TelegramGlassPlatter.height),
                platter.widthAnchor.constraint(greaterThanOrEqualToConstant: TelegramGlassPlatter.height),
                width,
                button.leadingAnchor.constraint(equalTo: platter.glassView.contentView.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: platter.glassView.contentView.trailingAnchor),
                button.topAnchor.constraint(equalTo: platter.glassView.contentView.topAnchor),
                button.bottomAnchor.constraint(equalTo: platter.glassView.contentView.bottomAnchor),
            ])
        }
        let centre = platters[1].centerXAnchor.constraint(equalTo: container.contentView.centerXAnchor)
        centre.priority = .defaultLow
        NSLayoutConstraint.activate([
            platters[0].leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor),
            platters[2].trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor),
            platters[1].leadingAnchor.constraint(
                greaterThanOrEqualTo: platters[0].trailingAnchor, constant: TelegramGlassPlatter.interSectionSpacing,
            ),
            platters[2].leadingAnchor.constraint(
                greaterThanOrEqualTo: platters[1].trailingAnchor, constant: TelegramGlassPlatter.interSectionSpacing,
            ),
            centre,
        ])
        update(hasSelection: false)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    func update(hasSelection: Bool) {
        for button in [deleteButton, archiveButton, shareButton] {
            button.isEnabled = hasSelection
            button.alpha = hasSelection ? 1 : 0.5
        }
        // Telegram keeps disabled glass visible but does not let it begin an interactive press.
        for platter in platters {
            platter.isUserInteractionEnabled = hasSelection
        }
    }
}
