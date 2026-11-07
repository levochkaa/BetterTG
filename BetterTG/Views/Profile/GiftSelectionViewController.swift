// GiftSelectionViewController.swift

import TDLibKit
import UIKit

// MARK: - GiftSelectionViewController

/// AddGiftsScreen: the profile's gifts in GiftsListView's grid with a check on each, those already in the collection
/// dimmed and left out, and Add N Gifts at the bottom, which hands the picked gifts back in the grid's order. The
/// sort button opens the profile's sort and filters; no more gifts are picked than the collection has room for.
final class GiftSelectionViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource {
    var onAdd: (([String]) -> Void)?

    private let client: TDLibClient
    private let collectionID: Int
    /// GiftsListView's remainingSelectionCount: the collection's room under stargifts_collection_gifts_limit.
    private let remainingCount: Int
    private let filterButton = UIButton(type: .system)
    private let pane: PeerProfileGiftsPane
    private var selected = [String]()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private let addButton = UIButton(configuration: .prominentGlass())

    init(ownerID: MessageSender, collectionID: Int, remainingCount: Int, client: TDLibClient) {
        self.client = client
        self.collectionID = collectionID
        self.remainingCount = remainingCount
        self.pane = PeerProfileGiftsPane(ownerID: ownerID, client: client) { true }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        title = L10n.telegram("AddGifts.Title")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"),
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) },
        )
        filterButton.setImage(UIImage(systemName: "line.3.horizontal.decrease"), for: .normal)
        filterButton.accessibilityLabel = L10n.betterTG("Profile.GiftsFilter")
        filterButton.addAction(UIAction { [weak self] _ in self?.openFilterMenu() }, for: .touchUpInside)
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: filterButton)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(ProfileGiftCell.self, forCellWithReuseIdentifier: ProfileGiftCell.reuseIdentifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        addButton.addAction(UIAction { [weak self] _ in self?.addPressed() }, for: .touchUpInside)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(addButton)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            addButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            addButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            addButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            addButton.heightAnchor.constraint(equalToConstant: 52),
        ])
        collectionView.contentInset.bottom = 52 + 16
        pane.onChange = { [weak self] in self?.collectionView.reloadData() }
        pane.loadMore()
        updateButton()
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        pane.items.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath,
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ProfileGiftCell.reuseIdentifier, for: indexPath,
        ) as? ProfileGiftCell
        if let gift = pane.gift(for: pane.items[indexPath.item]) {
            cell?.configure(gift: gift, client: client)
            cell?.setSelection(
                isSelecting: true,
                isSelected: selected.contains(gift.receivedGiftId),
                isDimmed: gift.collectionIds.contains(collectionID),
            )
        }
        return cell ?? UICollectionViewCell()
    }

    func collectionView(_: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? ProfileGiftCell)?.setPlaybackVisible(true)
        if indexPath.item >= pane.items.count - 6 { pane.loadMore() }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard let gift = pane.gift(for: pane.items[indexPath.item]), !gift.receivedGiftId.isEmpty,
              !gift.collectionIds.contains(collectionID) else { return }
        if let index = selected.firstIndex(of: gift.receivedGiftId) {
            selected.remove(at: index)
        } else if selected.count < remainingCount {
            selected.append(gift.receivedGiftId)
        }
        collectionView.reconfigureItems(at: [indexPath])
        updateButton()
    }

    /// AddGifts.AddGifts with at least one in its count, disabled with nothing picked.
    private func updateButton() {
        var configuration = addButton.configuration ?? .prominentGlass()
        let count = max(1, selected.count)
        configuration.title = L10n.telegramPlural("AddGifts.AddGifts", count: count, formattedCount: "\(count)")
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }
        addButton.configuration = configuration
        addButton.isEnabled = !selected.isEmpty
    }

    /// AddGiftsScreen's filter button: the same sort and filters as the profile's, Displayed and Hidden included.
    private func openFilterMenu() {
        presentTelegramContextMenu(
            sourceView: filterButton,
            actions: pane.filterMenuActions(hasVisibility: true),
            presentationStyle: .sourceMorph,
        )
    }

    private func addPressed() {
        let order = pane.items.compactMap { pane.gift(for: $0)?.receivedGiftId }.filter(selected.contains)
        dismiss(animated: true) { [onAdd] in onAdd?(order) }
    }

    /// GiftsListView's grid: square tiles 10 pt apart, 16 pt from the sides, three to a row.
    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { _, environment in
            let width = environment.container.effectiveContentSize.width
            let columns = width > 480 ? 5 : 3
            let side = floor((width - 32 - 10 * CGFloat(columns - 1)) / CGFloat(columns))
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .absolute(side), heightDimension: .absolute(side),
            ))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(side),
                ),
                repeatingSubitem: item,
                count: columns,
            )
            group.interItemSpacing = .fixed(10)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 10
            section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
            return section
        }
    }
}
