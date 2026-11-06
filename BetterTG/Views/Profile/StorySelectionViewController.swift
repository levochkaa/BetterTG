// StorySelectionViewController.swift

import TDLibKit
import UIKit

// MARK: - StorySelectionViewController

/// PeerInfoStoryGridScreen in selection mode (makeStorySelectionController), as an album's Add Stories opens it: the
/// account's stories saved to its profile under My Stories, three to a row and all selectable, the count picked under
/// the title, and Add N Stories at the bottom, which hands the picked stories back in the grid's order.
final class StorySelectionViewController: UIViewController, UICollectionViewDelegate {
    // MARK: Internal

    var onAdd: (([Int]) -> Void)?

    // MARK: Private

    private let client: TDLibClient
    private let chatID: Int64
    private let excludedIDs: Set<Int>
    private var stories = [Story]()
    private var selected = [Int]()
    private var hasMore = true
    /// The last story a page returned, excluded ones included: the next page starts after it.
    private var lastLoadedID = 0
    private var loadTask: Task<Void, Never>?
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private let addButton = UIButton(configuration: .prominentGlass())

    init(chatID: Int64, excluding excludedIDs: [Int], client: TDLibClient) {
        self.chatID = chatID
        self.excludedIDs = Set(excludedIDs)
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = L10n.telegram("StoryList.TitleSaved")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"),
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) },
        )
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.allowsMultipleSelection = true
        collectionView.register(
            ProfileStoryGridCell.self,
            forCellWithReuseIdentifier: ProfileStoryGridCell.reuseIdentifier,
        )
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
        updateSelection()
        loadMore()
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        toggle(indexPath)
        collectionView.deselectItem(at: indexPath, animated: false)
    }

    func collectionView(_: UICollectionView, willDisplay _: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.item >= stories.count - 6 { loadMore() }
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { _, environment in
            let width = environment.container.effectiveContentSize.width
            let columns = telegramGridColumns(phoneColumns: 3, width: width)
            let side = floor((width - CGFloat(columns - 1)) / CGFloat(columns))
            let height = floor(side / ProfileStoryGridCell.aspectRatio)
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .absolute(side),
                heightDimension: .absolute(height),
            ))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(height),
                ),
                repeatingSubitem: item,
                count: columns,
            )
            group.interItemSpacing = .fixed(1)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 1
            return section
        }
    }

    private func toggle(_ indexPath: IndexPath) {
        guard stories.indices.contains(indexPath.item) else { return }
        let id = stories[indexPath.item].id
        if let index = selected.firstIndex(of: id) {
            selected.remove(at: index)
        } else {
            selected.append(id)
        }
        collectionView.reconfigureItems(at: [indexPath])
        updateSelection()
    }

    /// StoryList.SubtitleSelected under the title and Stories.AddStories on the button, disabled with nothing picked.
    private func updateSelection() {
        navigationItem.subtitle = selected.isEmpty
            ? nil
            : L10n.telegramPlural("StoryList.SubtitleSelected", count: selected.count)
        var configuration = addButton.configuration ?? .prominentGlass()
        configuration.title = selected.isEmpty
            ? L10n.telegram("Stories.AddStoriesEmpty")
            : L10n.telegramPlural("Stories.AddStories", count: selected.count, formattedCount: "\(selected.count)")
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }
        addButton.configuration = configuration
        addButton.isEnabled = !selected.isEmpty
    }

    private func addPressed() {
        let order = stories.map(\.id).filter(selected.contains)
        dismiss(animated: true) { [onAdd] in onAdd?(order) }
    }

    private func loadMore() {
        guard loadTask == nil, hasMore else { return }
        let client = client
        let chatID = chatID
        let from = lastLoadedID
        loadTask = Task { [weak self] in
            let page = try? await client.send(TDNativeRequests.getChatPostedToChatPageStories(
                chatId: chatID, fromStoryId: from, limit: 30,
            ))
            guard let self, !Task.isCancelled else { return }
            loadTask = nil
            let known = Set(stories.map(\.id))
            let previous = lastLoadedID
            let added = (page?.stories ?? []).filter { !known.contains($0.id) && $0.id != previous }
            hasMore = !added.isEmpty
            lastLoadedID = added.last?.id ?? lastLoadedID
            let excluded = excludedIDs
            stories.append(contentsOf: added.filter { !excluded.contains($0.id) })
            collectionView.reloadData()
            if hasMore, stories.count < 12 { loadMore() }
        }
    }
}

// MARK: UICollectionViewDataSource

extension StorySelectionViewController: UICollectionViewDataSource {
    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        stories.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath,
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ProfileStoryGridCell.reuseIdentifier,
            for: indexPath,
        ) as? ProfileStoryGridCell
        let story = stories[indexPath.item]
        cell?.configure(story: story, isPinned: false, client: client)
        cell?.setSelection(isSelecting: true, isSelected: selected.contains(story.id))
        return cell ?? UICollectionViewCell()
    }
}
