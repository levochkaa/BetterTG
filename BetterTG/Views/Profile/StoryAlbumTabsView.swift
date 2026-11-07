// StoryAlbumTabsView.swift

import UIKit

// MARK: - StoryAlbumTabsView

/// PeerInfoStoryPaneNode's folder tab (TabSelectorComponent) over the Posts grid: All Stories, then the profile's
/// albums, as 34 pt capsules in a 44 pt row that scrolls sideways; the chosen one sits on a filled capsule. For an
/// account that manages the stories + Add Album ends the row, and holding an album opens its menu.
final class StoryAlbumTabsView: UICollectionReusableView {
    static let reuseIdentifier = "StoryAlbumTabsView"
    static let height: CGFloat = 44

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var onSelect: ((Int?) -> Void)?
    private var onAdd: (() -> Void)?
    private var onMenu: ((Int, UIView, ContextMenuPressGestureRecognizer) -> Void)?
    /// While the grid reorders, a held album tab follows the finger along the row; the new order goes here.
    private var onReorder: (([Int]) -> Void)?
    private var draggedButton: UIButton?
    private var ids = [Int?]()

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        stack.axis = .horizontal
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerYAnchor),
            stack.heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The albums by identifier and name, nil standing for All Stories (or `allTitle`, such as the gift collections'
    /// All Gifts).
    func configure(
        albums: [(id: Int, name: String)],
        selectedID: Int?,
        allTitle: String = L10n.telegram("Stories.AlbumAll"),
        onSelect: @escaping (Int?) -> Void,
        onAdd: (() -> Void)? = nil,
        onMenu: ((Int, UIView, ContextMenuPressGestureRecognizer) -> Void)? = nil,
        onReorder: (([Int]) -> Void)? = nil,
    ) {
        self.onReorder = onReorder
        self.onSelect = onSelect
        self.onAdd = onAdd
        self.onMenu = onMenu
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        ids = [nil] + albums.map(\.id)
        let titles = [allTitle] + albums.map(\.name)
        for (index, title) in titles.enumerated() {
            let isSelected = ids[index] == selectedID
            var configuration = UIButton.Configuration.plain()
            configuration.title = title
            configuration.cornerStyle = .capsule
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
            configuration.baseForegroundColor = isSelected ? .label : .secondaryLabel
            configuration.background.backgroundColor = isSelected ? .tertiarySystemFill : .clear
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 15, weight: isSelected ? .semibold : .medium)
                return outgoing
            }
            let button = UIButton(configuration: configuration)
            button.tag = index
            button.accessibilityTraits = isSelected ? [.button, .selected] : .button
            button.addAction(UIAction { [weak self] action in
                guard let self, let sender = action.sender as? UIButton else { return }
                self.onSelect?(ids[sender.tag])
            }, for: .touchUpInside)
            if onReorder != nil, ids[index] != nil {
                let drag = UILongPressGestureRecognizer(target: self, action: #selector(albumDragged(_:)))
                drag.minimumPressDuration = 0.15
                button.addGestureRecognizer(drag)
            } else if onMenu != nil, ids[index] != nil {
                let press = ContextMenuPressGestureRecognizer(target: self, action: #selector(albumHeld(_:)))
                press.castsShadow = false
                button.addGestureRecognizer(press)
            }
            stack.addArrangedSubview(button)
        }
        if onAdd != nil {
            var configuration = UIButton.Configuration.plain()
            configuration.title = L10n.telegram("Stories.AlbumAdd")
            configuration.baseForegroundColor = .tintColor
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 15, weight: .medium)
                return outgoing
            }
            let button = UIButton(configuration: configuration)
            button.addAction(UIAction { [weak self] _ in self?.onAdd?() }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }

    /// TabSelectorComponent's reorderable items: the held tab lifts and swaps places as it passes its neighbours'
    /// centres; All Stories stays first.
    @objc private func albumDragged(_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view as? UIButton else { return }
        switch gesture.state {
        case .began:
            draggedButton = button
            UIView.animate(withDuration: 0.15) { button.transform = CGAffineTransform(scaleX: 1.08, y: 1.08) }
        case .changed:
            let x = gesture.location(in: stack).x
            let views = stack.arrangedSubviews
            guard let current = views.firstIndex(of: button) else { return }
            let target = views.indices.last { index in
                index > 0 && views[index] is UIButton && ids.indices.contains((views[index] as? UIButton)?.tag ?? -1)
                    && ids[(views[index] as? UIButton)?.tag ?? 0] != nil && views[index].frame.minX <= x
            } ?? current
            guard target != current else { return }
            UIView.animate(withDuration: 0.2) {
                self.stack.removeArrangedSubview(button)
                self.stack.insertArrangedSubview(button, at: target)
                self.stack.layoutIfNeeded()
            }
        default:
            draggedButton = nil
            UIView.animate(withDuration: 0.15) { button.transform = .identity }
            let order = stack.arrangedSubviews.compactMap { view -> Int? in
                guard let button = view as? UIButton, ids.indices.contains(button.tag) else { return nil }
                return ids[button.tag]
            }
            onReorder?(order)
        }
    }

    @objc private func albumHeld(_ gesture: ContextMenuPressGestureRecognizer) {
        guard gesture.state == .began, let button = gesture.view as? UIButton, let id = ids[button.tag] else { return }
        onMenu?(id, button, gesture)
    }
}
