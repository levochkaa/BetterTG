// EmojiSearchHeaderBar.swift

import TDLibKit
import UIKit

// MARK: - EmojiSearchHeaderBar

/// EmojiSearchHeaderView's bar over the emoji tab: the magnifier and Search, which open the expanded search, then
/// EmojiSearchSearchBarComponent's groups (getEmojiCategories' icons, 24 pt, 11 pt apart, right-aligned while they
/// fit and scrolling with Search otherwise). A tap on a group selects it under a 28 pt circle and filters the grid to
/// its emoji; a second tap clears it.
final class EmojiSearchHeaderBar: UIView {
    var onSearch: (() -> Void)?
    var onSelectGroup: ((Int?) -> Void)?

    private(set) var selectedIndex: Int?

    private let scrollView = UIScrollView()
    private let searchButton = UIButton(type: .custom)
    private let magnifier = UIImageView(image: UIImage(
        systemName: "magnifyingglass",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium),
    ))
    private let searchLabel = UILabel()
    private let selection = UIView()
    private var iconViews = [CustomEmojiInlineView]()
    private var iconButtons = [UIButton]()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .tertiarySystemFill
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        clipsToBounds = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        addSubview(scrollView)
        magnifier.tintColor = .secondaryLabel
        magnifier.contentMode = .center
        scrollView.addSubview(magnifier)
        searchLabel.text = L10n.telegram("Common.Search")
        searchLabel.font = .systemFont(ofSize: 17)
        searchLabel.textColor = .secondaryLabel
        scrollView.addSubview(searchLabel)
        searchButton.accessibilityLabel = L10n.telegram("Common.Search")
        searchButton.addAction(UIAction { [weak self] _ in self?.onSearch?() }, for: .touchUpInside)
        scrollView.addSubview(searchButton)
        selection.backgroundColor = .secondarySystemFill
        selection.layer.cornerRadius = 14
        selection.isHidden = true
        scrollView.addSubview(selection)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// EmojiSearchSearchBarComponent.ItemLayout: Search 8 pt in, the groups 11 pt after it or against the right
    /// edge, 8 pt from it.
    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        let height = bounds.height
        magnifier.frame = CGRect(x: 8, y: 0, width: 18, height: height)
        let textSize = searchLabel.sizeThatFits(CGSize(width: 200, height: height))
        searchLabel.frame = CGRect(
            x: magnifier.frame.maxX + 6,
            y: ((height - textSize.height) / 2).rounded(),
            width: textSize.width,
            height: textSize.height,
        )
        let count = CGFloat(iconViews.count)
        let itemsWidth = 24 * count + 11 * max(0, count - 1)
        var startX = searchLabel.frame.maxX + 11
        if startX + itemsWidth + 8 < bounds.width {
            startX = bounds.width - 8 - itemsWidth
        }
        searchButton.frame = CGRect(x: 0, y: 0, width: startX - 4, height: height)
        for (index, icon) in iconViews.enumerated() {
            let frame = CGRect(x: startX + CGFloat(index) * 35, y: ((height - 24) / 2).rounded(), width: 24, height: 24)
            icon.frame = frame
            iconButtons[index].frame = frame.insetBy(dx: -5, dy: -6)
        }
        if let selectedIndex, iconViews.indices.contains(selectedIndex) {
            let center = CGPoint(x: iconViews[selectedIndex].frame.midX, y: iconViews[selectedIndex].frame.midY)
            selection.frame = CGRect(x: center.x - 14, y: center.y - 14, width: 28, height: 28)
        }
        scrollView.contentSize = CGSize(width: max(bounds.width, startX + itemsWidth + 8), height: height)
    }

    /// The groups' icons, in getEmojiCategories' order.
    func setGroups(_ groups: [(name: String, icon: Sticker)], client: TDLibClient) {
        iconViews.forEach { $0.removeFromSuperview() }
        iconButtons.forEach { $0.removeFromSuperview() }
        iconViews = []
        iconButtons = []
        for (index, group) in groups.enumerated() {
            let icon = CustomEmojiInlineView()
            icon.isUserInteractionEnabled = false
            icon.templateColor = .secondaryLabel
            icon.configure(sticker: group.icon, client: client)
            icon.setPlaybackVisible(true)
            scrollView.addSubview(icon)
            iconViews.append(icon)
            let button = UIButton(type: .custom)
            button.accessibilityLabel = group.name
            button.addAction(UIAction { [weak self] _ in self?.toggle(index) }, for: .touchUpInside)
            scrollView.addSubview(button)
            iconButtons.append(button)
        }
        if let selectedIndex, selectedIndex >= groups.count { self.selectedIndex = nil }
        setNeedsLayout()
    }

    func clearSelection() {
        guard selectedIndex != nil else { return }
        selectedIndex = nil
        updateSelection()
    }

    private func toggle(_ index: Int) {
        selectedIndex = selectedIndex == index ? nil : index
        updateSelection()
        onSelectGroup?(selectedIndex)
    }

    private func updateSelection() {
        for (index, icon) in iconViews.enumerated() {
            icon.templateColor = index == selectedIndex ? .label : .secondaryLabel
            iconButtons[index].accessibilityTraits = index == selectedIndex ? [.button, .selected] : .button
        }
        selection.isHidden = selectedIndex == nil
        setNeedsLayout()
    }
}
