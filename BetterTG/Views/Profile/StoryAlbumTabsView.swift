// StoryAlbumTabsView.swift

import UIKit

// MARK: - StoryAlbumTabsView

/// PeerInfoStoryPaneNode's folder tab (TabSelectorComponent) over the Posts grid: All Stories, then the profile's
/// albums, as 34 pt capsules in a 44 pt row that scrolls sideways; the chosen one sits on a filled capsule.
final class StoryAlbumTabsView: UICollectionReusableView {
    static let reuseIdentifier = "StoryAlbumTabsView"
    static let height: CGFloat = 44

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var onSelect: ((Int?) -> Void)?
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

    /// The albums by identifier and name, nil standing for All Stories.
    func configure(albums: [(id: Int, name: String)], selectedID: Int?, onSelect: @escaping (Int?) -> Void) {
        self.onSelect = onSelect
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        ids = [nil] + albums.map(\.id)
        let titles = [L10n.telegram("Stories.AlbumAll")] + albums.map(\.name)
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
            stack.addArrangedSubview(button)
        }
    }
}
