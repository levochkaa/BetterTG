// FeaturedStickersViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - StickerSetSearch

/// StickerPaneSearchContentNode's set search: the installed sets matching the query (searchInstalledStickerSets),
/// then the server's (searchStickerSets), for a single emoji or at least two characters.
enum StickerSetSearch {
    static func sets(matching query: String, client: TDLibClient) async -> [TDNativeStickerSetInfo] {
        let isSingleEmoji = query.count == 1 && query.unicodeScalars.contains { $0.properties.isEmojiPresentation }
        guard query.count >= 2 || isSingleEmoji else { return [] }
        async let installedRequest = client.send(TDNativeRequests.searchInstalledStickerSets(
            stickerType: .stickerTypeRegular, query: query, limit: 20,
        ))
        async let remoteRequest = client.send(TDNativeRequests.searchStickerSets(
            stickerType: .stickerTypeRegular, query: query,
        ))
        let installed = await (try? installedRequest)?.sets ?? []
        let remote = await (try? remoteRequest)?.sets ?? []
        var seen = Set<Int64>()
        return (installed + remote).filter { seen.insert($0.id).inserted }
    }
}

// MARK: - FeaturedStickersViewController

/// FeaturedStickersScreen: Search Stickers in the navigation bar with Done, then TDLib's trending sets as
/// StickerPaneSearchGlobalItem rows. A set unread when the screen opened keeps its dot while it stays open, and sets on
/// screen are marked viewed (viewTrendingStickerSets). Older sets load near the end under Other Stickers. ADD and ADDED
/// install and remove a set; a tap opens it.
final class FeaturedStickersViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate,
UISearchBarDelegate {
    private enum Section: Int {
        case featured
        case other
    }

    private let accountID: UUID?
    private let client: TDLibClient
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private let searchBar = UISearchBar()
    private var featured = [TDNativeStickerSetInfo]()
    /// requestOldFeaturedStickerPacks: sets loaded past the first page.
    private var older = [TDNativeStickerSetInfo]()
    /// The search's results while the search field has text.
    private var found: [TDNativeStickerSetInfo]?
    private var installedIDs = Set<Int64>()
    private var busyIDs = Set<Int64>()
    /// fixedUnread: the sets that were unread, dotted until the screen closes.
    private var unreadIDs = Set<Int64>()
    private var viewedIDs = Set<Int64>()
    private var canLoadMore = true
    private var isLoadingMore = false
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var updatesCancellable: AnyCancellable?

    private var contextIsCurrent: Bool {
        accountID != nil && TDLib.shared.activeAccountID == accountID && TDLib.shared.activeClient.id == client.id
    }

    init() {
        self.accountID = TDLib.shared.activeAccountID
        self.client = TDLib.shared.activeClient
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        searchTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        searchBar.placeholder = L10n.telegram("Stickers.Search")
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        navigationItem.titleView = searchBar
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Done"),
            style: .prominent,
            target: self,
            action: #selector(doneTapped),
        )

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.keyboardDismissMode = .onDrag
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(
            FeaturedStickerSetCell.self,
            forCellWithReuseIdentifier: FeaturedStickerSetCell.reuseIdentifier,
        )
        collectionView.register(
            FeaturedStickersSectionHeader.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: FeaturedStickersSectionHeader.reuseIdentifier,
        )
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        load()
        let accountID = accountID
        updatesCancellable = NotificationCenter.default
            .publisher(for: .updateInstalledStickerSets)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, contextIsCurrent,
                      let update = TdScopedUpdate<TDNativeUpdateInstalledStickerSets>(notification: note),
                      update.source == TDLib.shared.activeUpdateSource, update.source.accountID == accountID,
                      case .stickerTypeRegular = update.value.stickerType else { return }
                installedIDs = Set(update.value.stickerSetIds)
                reconfigureVisibleCells()
            }
    }

    /// Telegram's `.modal` presentation: a sheet over the settings.
    static func present(from host: UIViewController) {
        let navigation = UINavigationController(rootViewController: FeaturedStickersViewController())
        navigation.modalPresentationStyle = .pageSheet
        host.present(navigation, animated: true)
    }

    // MARK: UICollectionViewDataSource

    func numberOfSections(in _: UICollectionView) -> Int {
        found == nil ? 2 : 1
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sets(in: section).count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath,
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: FeaturedStickerSetCell.reuseIdentifier,
            for: indexPath,
        )
        if let cell = cell as? FeaturedStickerSetCell, let set = sets(in: indexPath.section)[safe: indexPath.item] {
            configure(cell, with: set, showsSeparator: indexPath.item != 0)
        }
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath,
    ) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: FeaturedStickersSectionHeader.reuseIdentifier,
            for: indexPath,
        )
        (header as? FeaturedStickersSectionHeader)?.title = L10n.telegram("FeaturedStickers.OtherSection")
        return header
    }

    // MARK: UICollectionViewDelegate

    func collectionView(_: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? FeaturedStickerSetCell)?.setPlaybackVisible(true)
        guard found == nil else { return }
        if let set = sets(in: indexPath.section)[safe: indexPath.item] { markViewed(set) }
        let shown = indexPath.section == Section.featured.rawValue ? indexPath.item : featured.count + indexPath.item
        if shown >= featured.count + older.count - 15 { loadMore() }
    }

    func collectionView(_: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt _: IndexPath) {
        (cell as? FeaturedStickerSetCell)?.setPlaybackVisible(false)
    }

    // MARK: UISearchBarDelegate

    func searchBar(_: UISearchBar, textDidChange text: String) {
        searchTask?.cancel()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            found = nil
            collectionView.reloadData()
            return
        }
        let client = client
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let sets = await StickerSetSearch.sets(matching: query, client: client)
            guard let self, !Task.isCancelled, contextIsCurrent else { return }
            found = sets
            collectionView.reloadData()
        }
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    // MARK: Private

    private func sets(in section: Int) -> [TDNativeStickerSetInfo] {
        if let found { return found }
        return section == Section.featured.rawValue ? featured : older
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] section, _ in
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(FeaturedStickerSetCell.height),
            ))
            let group = NSCollectionLayoutGroup.vertical(layoutSize: item.layoutSize, subitems: [item])
            let layoutSection = NSCollectionLayoutSection(group: group)
            if let self, found == nil, section == Section.other.rawValue, !older.isEmpty {
                layoutSection.boundarySupplementaryItems = [NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .absolute(28),
                    ),
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top,
                )]
            }
            return layoutSection
        }
    }

    private func load() {
        guard contextIsCurrent else { return }
        let client = client
        loadTask = Task { [weak self] in
            async let trendingRequest = client.send(TDNativeRequests.getTrendingStickerSets(
                stickerType: .stickerTypeRegular,
                offset: 0,
                limit: 100,
            ))
            async let installedRequest = client.send(TDNativeRequests.getInstalledStickerSets(
                stickerType: .stickerTypeRegular,
            ))
            let trending = await (try? trendingRequest)?.sets ?? []
            let installed = await (try? installedRequest)?.sets ?? []
            guard let self, !Task.isCancelled, contextIsCurrent else { return }
            featured = trending
            installedIDs = Set(installed.map(\.id))
            unreadIDs = Set(trending.filter { !$0.isViewed }.map(\.id))
            collectionView.reloadData()
        }
    }

    /// loadMore: 50 older sets at a time, until a page comes back short.
    private func loadMore() {
        guard canLoadMore, !isLoadingMore, !featured.isEmpty, contextIsCurrent else { return }
        isLoadingMore = true
        let client = client
        let offset = featured.count + older.count
        Task { [weak self] in
            let page = try? await client.send(TDNativeRequests.getTrendingStickerSets(
                stickerType: .stickerTypeRegular,
                offset: offset,
                limit: 50,
            ))
            guard let self, contextIsCurrent else { return }
            isLoadingMore = false
            let sets = page?.sets ?? []
            canLoadMore = sets.count >= 50
            var known = Set((featured + older).map(\.id))
            let added = sets.filter { known.insert($0.id).inserted }
            unreadIDs.formUnion(added.filter { !$0.isViewed }.map(\.id))
            older += added
            guard found == nil, !added.isEmpty else { return }
            collectionView.reloadData()
        }
    }

    /// markFeaturedStickerPacksAsSeenInteractively, once per set.
    private func markViewed(_ set: TDNativeStickerSetInfo) {
        guard unreadIDs.contains(set.id), viewedIDs.insert(set.id).inserted else { return }
        let client = client
        let id = set.id
        Task {
            _ = try? await client.send(TDNativeRequests.viewTrendingStickerSets(stickerSetIds: [id]))
        }
    }

    private func configure(_ cell: FeaturedStickerSetCell, with set: TDNativeStickerSetInfo, showsSeparator: Bool) {
        cell.configure(
            set: set,
            isInstalled: installedIDs.contains(set.id),
            isUnread: found == nil && unreadIDs.contains(set.id),
            isBusy: busyIDs.contains(set.id),
            showsSeparator: showsSeparator,
            client: client,
        )
        cell.onToggle = { [weak self] in self?.toggle(set) }
        cell.onOpen = { [weak self] in
            guard let self else { return }
            searchBar.resignFirstResponder()
            StickerPackPreviewViewController.present(setID: set.id, client: client, from: self, onSend: nil)
        }
    }

    private func reconfigureVisibleCells() {
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: indexPath) as? FeaturedStickerSetCell,
                  let set = sets(in: indexPath.section)[safe: indexPath.item] else { continue }
            configure(cell, with: set, showsSeparator: indexPath.item != 0)
        }
    }

    /// installPack: ADD installs the set, ADDED removes it.
    private func toggle(_ set: TDNativeStickerSetInfo) {
        guard contextIsCurrent, busyIDs.insert(set.id).inserted else { return }
        let install = !installedIDs.contains(set.id)
        reconfigureVisibleCells()
        let client = client
        Task { [weak self] in
            let succeeded = await (try? client.send(TDNativeRequests.changeStickerSet(
                setId: set.id,
                isInstalled: install,
                isArchived: false,
            ))) != nil
            guard let self, contextIsCurrent else { return }
            busyIDs.remove(set.id)
            if succeeded {
                if install { installedIDs.insert(set.id) } else { installedIDs.remove(set.id) }
            } else {
                presentChatListActionFailure()
            }
            reconfigureVisibleCells()
        }
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }
}

// MARK: - FeaturedStickerSetCell

/// StickerPaneSearchGlobalItem with regular insets, 152 pt tall: 12 pt down, the title in 16 pt bold 14 pt from the
/// left with a 6 pt accent dot while unread, the count in 15 pt 21 pt under it, the 28 pt ADD or ADDED 16 pt from the
/// right, and the first five stickers 48 pt down, each up to 75 pt, spread across the row 2 pt from its edges.
final class FeaturedStickerSetCell: UICollectionViewCell {
    static let reuseIdentifier = "FeaturedStickerSetCell"
    static let height: CGFloat = 152

    var onToggle: (() -> Void)?
    var onOpen: (() -> Void)?

    private let separator = UIView()
    private let titleLabel = UILabel()
    private let unreadDot = UIView()
    private let countLabel = UILabel()
    private let button = UIButton(configuration: .filled())
    private let stickerViews = (0..<5).map { _ in CustomEmojiInlineView() }

    override init(frame: CGRect) {
        super.init(frame: frame)
        separator.backgroundColor = .separator
        titleLabel.font = .boldSystemFont(ofSize: 16)
        countLabel.font = .systemFont(ofSize: 15)
        countLabel.textColor = .secondaryLabel
        unreadDot.backgroundColor = .tintColor
        unreadDot.layer.cornerRadius = 3
        button.configuration?.cornerStyle = .capsule
        button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = .systemFont(ofSize: 13, weight: .semibold)
            return attributes
        }
        button.addAction(UIAction { [weak self] _ in self?.onToggle?() }, for: .touchUpInside)
        for subview in [separator, titleLabel, unreadDot, countLabel, button] as [UIView] {
            contentView.addSubview(subview)
        }
        for stickerView in stickerViews {
            stickerView.isUserInteractionEnabled = false
            contentView.addSubview(stickerView)
        }
        contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stickerViews.forEach { $0.prepareForReuse() }
        onToggle = nil
        onOpen = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let top: CGFloat = 12
        let pixel = 1 / max(1, traitCollection.displayScale)
        separator.frame = CGRect(x: 16, y: 0, width: width - 32, height: pixel)
        let buttonSize = button.sizeThatFits(CGSize(width: width, height: 28))
        button.frame = CGRect(x: width - 16 - buttonSize.width, y: 4 + top, width: buttonSize.width, height: 28)
        let titleWidth = min(titleLabel.intrinsicContentSize.width, button.frame.minX - 20 - 14)
        titleLabel.frame = CGRect(x: 14, y: 2 + top, width: max(0, titleWidth), height: 20)
        unreadDot.frame = CGRect(x: titleLabel.frame.maxX + 2, y: titleLabel.frame.minY + 7, width: 6, height: 6)
        countLabel.frame = CGRect(x: 14, y: 23 + top, width: width - 34, height: 18)
        let sideInset: CGFloat = 2
        let available = width - sideInset * 2
        let side = min(floor(available / 5), 75)
        let spacing = max(0, available - 5 * side - sideInset * 2) / 4
        var x = sideInset
        for stickerView in stickerViews {
            stickerView.frame = CGRect(x: x, y: 48 + top, width: side, height: side)
            x += side + spacing
        }
    }

    func configure(
        set: TDNativeStickerSetInfo,
        isInstalled: Bool,
        isUnread: Bool,
        isBusy: Bool,
        showsSeparator: Bool,
        client: TDLibClient,
    ) {
        titleLabel.text = set.title
        countLabel.text = L10n.telegramPlural(
            "StickerPack.StickerCount",
            count: set.size,
            formattedCount: set.size.formatted(.number),
        )
        unreadDot.isHidden = !isUnread
        separator.isHidden = !showsSeparator
        // chatInputMediaPanelAddPackButtonImage, or AddedPackButtonImage: the accent at 8% under accent text.
        button.configuration?.title = L10n.telegram(isInstalled ? "Stickers.Installed" : "Stickers.Install")
        button.configuration?.baseBackgroundColor = isInstalled ? .tintColor.withAlphaComponent(0.08) : .tintColor
        button.configuration?.baseForegroundColor = isInstalled ? .tintColor : .white
        button.isEnabled = !isBusy
        for (index, stickerView) in stickerViews.enumerated() {
            if let sticker = set.covers[safe: index] {
                stickerView.configure(sticker: sticker, client: client)
            } else {
                stickerView.prepareForReuse()
            }
        }
        accessibilityLabel = [set.title, countLabel.text].compactMap(\.self).joined(separator: ", ")
        setNeedsLayout()
    }

    func setPlaybackVisible(_ visible: Bool) {
        stickerViews.forEach { $0.setPlaybackVisible(visible) }
    }

    @objc private func tapped() {
        onOpen?()
    }
}

// MARK: - FeaturedStickersSectionHeader

/// StickerPaneSearchGlobalSection's ListSectionHeaderNode, as ChatListSearchSectionHeaderView draws it: Other
/// Stickers over the older sets, 28 pt tall.
final class FeaturedStickersSectionHeader: UICollectionReusableView {
    static let reuseIdentifier = "FeaturedStickersSectionHeader"

    private let label = UILabel()

    var title: String? {
        get { label.text }
        set { label.text = newValue?.uppercased() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.accessibilityTraits = .header
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
