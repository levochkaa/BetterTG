// ComposerMediaPickerViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - ComposerMediaPickerViewController

@MainActor final class ComposerMediaPickerViewController: UIViewController, UICollectionViewDelegate,
UISearchBarDelegate {
    enum Mode: Int {
        case emoji
        case customEmoji
        case stickers
        case gifs
    }

    /// Telegram's sticker tab groups (EmojiPagerContentSignals): Favorite Stickers, Recently Used, then every installed
    /// pack in the user's order. Searches and the other tabs use one plain section.
    private enum Section: Hashable {
        case content
        case favorites
        case recent
        case pack(Int64)
    }

    private enum ItemID: Hashable {
        case animation(Int)
        case emoji(String)
        case sticker(Int)
        /// A sticker can be in Favorites, Recently Used and its pack at once.
        case groupedSticker(Section, Int)
    }

    /// Telegram shows up to 20 recently used stickers.
    private static let recentStickerLimit = 20

    private static let emojis =
        "😀 😃 😄 😁 😆 😅 😂 🙂 🙃 😉 😊 😇 🥰 😍 🤩 😘 😋 😜 🤪 🤨 🧐 🤓 😎 🥳 😏 😒 😞 😔 😟 😕 🙁 ☹️ 😣 😖 😫 😩 🥺 😢 😭 😤 😠 😡 🤬 🤯 😳 🥵 🥶 😱 😨 😰 🤗 🤔 🫡 🤭 🤫 🤥 😶 😐 😑 😬 🙄 😯 😮 😲 🥱 😴 🤤 😪 😵 🤐 🤢 🤮 🤧 😷 🤒 🤕 👍 👎 👏 🙌 🫶 ❤️ 🧡 💛 💚 💙 💜 🖤 🤍 💯 🔥 🎉 ✨ 🚀"
            .split(separator: " ")
            .map(String.init)

    var onAnimation: ((Animation) -> Void)?
    var onDismiss: (() -> Void)?
    var onEmoji: ((String) -> Void)?
    var onCustomEmoji: ((Sticker) -> Void)?
    var onSticker: ((Sticker) -> Void)?
    /// Off while a message is edited (Telegram offers only emoji input then, `ChatInterfaceInputContexts`) or when the
    /// chat doesn't take stickers and GIFs: the picker keeps only its emoji tabs.
    var allowsStickersAndGIFs = true

    private let accountID: UUID
    private let chatID: Int64
    private let client: TDLibClient
    private let segmentedControl = UISegmentedControl(items: [
        L10n.telegram("EmojiInput.TabEmoji"),
        L10n.betterTG("CustomEmoji.Tab"),
        L10n.telegram("EmojiInput.TabStickers"),
        L10n.telegram("EmojiInput.TabGifs"),
    ])
    private let searchBar = UISearchBar()
    private var searchBarHeightConstraint: NSLayoutConstraint!
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, ItemID>!
    private var animations = [Int: Animation]()
    private var savedAnimations = [Animation]()
    private var stickers = [Int: Sticker]()
    private var sectionTitles = [Section: String]()
    private var favoriteStickerIDs = Set<Int>()
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var stickerActionTask: Task<Void, Never>?
    private var canUseCustomEmoji = false
    private var clientChangeCancellable: AnyCancellable?

    private var mode: Mode {
        Mode(rawValue: segmentedControl.selectedSegmentIndex) ?? .emoji
    }

    private var contextIsCurrent: Bool {
        TDLib.shared.activeAccountID == accountID && TDLib.shared.activeClient.id == client.id
    }

    init(accountID: UUID, chatID: Int64, client: TDLibClient) {
        self.accountID = accountID
        self.chatID = chatID
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        searchTask?.cancel()
        stickerActionTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = L10n.betterTG("Composer.EmojiAndStickersTitle")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Done"), style: .plain,
            target: self,
            action: #selector(donePressed),
        )
        configureViews()
        configureDataSource()
        if !allowsStickersAndGIFs {
            segmentedControl.removeSegment(at: Mode.gifs.rawValue, animated: false)
            segmentedControl.removeSegment(at: Mode.stickers.rawValue, animated: false)
        }
        segmentedControl.selectedSegmentIndex = Mode.emoji.rawValue
        searchBar.isHidden = true
        searchBarHeightConstraint.constant = 0
        applyEmojiSnapshot()
        // Its stickers and GIFs are the presenting client's files. A renewed client (the app returning from the
        // background) closes the sheet so the chat can move to the new client, instead of losing the next tap.
        clientChangeCancellable = TDLib.shared
            .activeClientChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !contextIsCurrent, presentingViewController != nil, !isBeingDismissed else { return }
                dismissPicker()
            }
    }

    /// BetterTG sends no Premium stickers.
    private static func sendableStickers(_ values: [Sticker]) -> [Sticker] {
        values.filter {
            if case .stickerFullTypeRegular(let regular) = $0.fullType {
                regular.premiumAnimation == nil
            } else {
                false
            }
        }
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard contextIsCurrent,
              let item = dataSource.itemIdentifier(for: indexPath)
        else {
            dismissPicker()
            return
        }
        switch item {
        case .emoji(let emoji):
            onEmoji?(emoji)
        case .groupedSticker(_, let id), .sticker(let id):
            guard let sticker = stickers[id] else { return }
            if case .stickerFullTypeCustomEmoji = sticker.fullType {
                guard canUseCustomEmoji else {
                    let alert = UIAlertController(
                        title: nil,
                        message: L10n.betterTG("CustomEmoji.PremiumRequired"),
                        preferredStyle: .alert,
                    )
                    alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .cancel))
                    present(alert, animated: true)
                    return
                }
                onCustomEmoji?(sticker)
            } else { onSticker?(sticker) }
        case .animation(let id):
            guard let animation = animations[id] else { return }
            onAnimation?(animation)
        }
    }

    func collectionView(_: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt _: IndexPath) {
        (cell as? ComposerStickerCell)?.setPlaybackVisible(true)
        (cell as? ComposerAnimationCell)?.setPlaybackVisible(true)
    }

    func collectionView(_: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt _: IndexPath) {
        (cell as? ComposerStickerCell)?.setPlaybackVisible(false)
        (cell as? ComposerAnimationCell)?.setPlaybackVisible(false)
    }

    func searchBar(_: UISearchBar, textDidChange searchText: String) {
        loadTask?.cancel()
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task<Never, Never>.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            await reload(query: searchText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func configureViews() {
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        view.addSubview(segmentedControl)

        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.delegate = self
        searchBar.placeholder = L10n.telegram("StickersSearch.SearchStickersPlaceholder")
        searchBar.searchBarStyle = .minimal
        view.addSubview(searchBar)
        searchBarHeightConstraint = searchBar.heightAnchor.constraint(equalToConstant: 44)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.register(ComposerEmojiCell.self, forCellWithReuseIdentifier: ComposerEmojiCell.reuseIdentifier)
        collectionView.register(
            ComposerStickerCell.self,
            forCellWithReuseIdentifier: ComposerStickerCell.reuseIdentifier,
        )
        collectionView.register(
            ComposerAnimationCell.self,
            forCellWithReuseIdentifier: ComposerAnimationCell.reuseIdentifier,
        )
        collectionView.register(
            ComposerSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: ComposerSectionHeaderView.reuseIdentifier,
        )
        let press = ContextMenuPressGestureRecognizer(target: self, action: #selector(itemLongPressed(_:)))
        press.pressedViewProvider = { [weak self] gesture in
            guard let self, let path = collectionView.indexPathForItem(at: gesture.location(in: collectionView)),
                  let item = dataSource.itemIdentifier(for: path), hasMenu(item)
            else { return nil }
            return collectionView.cellForItem(at: path)
        }
        collectionView.addGestureRecognizer(press)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchBar.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 4),
            searchBarHeightConstraint,
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            collectionView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, _ in
            let columns = self?.mode == .emoji || self?.mode == .customEmoji ? 8 : 4
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1 / CGFloat(columns)),
                heightDimension: .fractionalHeight(1),
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .fractionalWidth(1 / CGFloat(columns)),
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                repeatingSubitem: item,
                count: columns,
            )
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 20, trailing: 8)
            if let identifier = self?.dataSource?.sectionIdentifier(for: sectionIndex),
               self?.sectionTitles[identifier] != nil
            {
                section.contentInsets.bottom = 8
                section.boundarySupplementaryItems = [NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .absolute(30),
                    ),
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top,
                )]
            }
            return section
        }
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, ItemID>(
            collectionView: collectionView,
        ) { [weak self] collectionView, indexPath, item in
            guard let self else { return UICollectionViewCell() }
            switch item {
            case .emoji(let emoji):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: ComposerEmojiCell.reuseIdentifier,
                    for: indexPath,
                ) as? ComposerEmojiCell
                cell?.configure(emoji: emoji)
                return cell ?? UICollectionViewCell()
            case .groupedSticker(_, let id), .sticker(let id):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: ComposerStickerCell.reuseIdentifier,
                    for: indexPath,
                ) as? ComposerStickerCell
                if let sticker = stickers[id] {
                    cell?.configure(sticker: sticker, client: client)
                }
                return cell ?? UICollectionViewCell()
            case .animation(let id):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: ComposerAnimationCell.reuseIdentifier,
                    for: indexPath,
                ) as? ComposerAnimationCell
                if let animation = animations[id] {
                    cell?.configure(animation: animation, client: client)
                }
                return cell ?? UICollectionViewCell()
            }
        }
        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: ComposerSectionHeaderView.reuseIdentifier,
                for: indexPath,
            ) as? ComposerSectionHeaderView
            let section = self?.dataSource.sectionIdentifier(for: indexPath.section)
            header?.configure(title: section.flatMap { self?.sectionTitles[$0] } ?? "")
            return header
        }
    }

    @objc private func modeChanged() {
        loadTask?.cancel()
        searchTask?.cancel()
        searchBar.text = ""
        searchBar.placeholder = mode == .gifs
            ? L10n.betterTG("Composer.FilterSavedGIFs")
            : L10n.telegram("StickersSearch.SearchStickersPlaceholder")
        if mode == .customEmoji { searchBar.placeholder = L10n.betterTG("CustomEmoji.Search") }
        searchBar.isHidden = mode == .emoji
        searchBarHeightConstraint.constant = mode == .emoji ? 0 : 44
        collectionView.collectionViewLayout.invalidateLayout()
        switch mode {
        case .emoji:
            applyEmojiSnapshot()
        case .customEmoji, .gifs, .stickers:
            loadTask = Task { [weak self] in await self?.reload(query: "") }
        }
    }

    private func reload(query: String) async {
        guard contextIsCurrent else { return }
        switch mode {
        case .emoji:
            applyEmojiSnapshot()
        case .customEmoji:
            let selectedMode = mode
            async let request = client.getStickers(
                chatId: chatID,
                limit: 200,
                query: query,
                stickerType: .stickerTypeCustomEmoji,
            )
            async let userRequest = client.getMe()
            let result = try? await request
            let user = try? await userRequest
            guard !Task.isCancelled, contextIsCurrent, mode == selectedMode else { return }
            canUseCustomEmoji = user?.isPremium == true || user?.id == chatID
            let values = (result?.stickers ?? [])
                .filter {
                    if case .stickerFullTypeCustomEmoji = $0.fullType {
                        true
                    } else {
                        false
                    }
                }
            stickers.merge(Dictionary(
                values.map { ($0.sticker.id, $0) },
                uniquingKeysWith: { _, latest in latest },
            )) { _, latest in latest }
            applySnapshot(values.map { .sticker($0.sticker.id) }.uniqued())
        case .stickers:
            guard !query.isEmpty else {
                await loadStickerGroups()
                return
            }
            let result = try? await client.getStickers(
                chatId: chatID,
                limit: 100,
                query: query,
                stickerType: .stickerTypeRegular,
            )
            guard !Task.isCancelled, contextIsCurrent else { return }
            let values = Self.sendableStickers(result?.stickers ?? [])
            stickers = Dictionary(uniqueKeysWithValues: values.map { ($0.sticker.id, $0) })
            applySnapshot(values.map { .sticker($0.sticker.id) })
        case .gifs:
            if savedAnimations.isEmpty {
                savedAnimations = await (try? client.getSavedAnimations().animations) ?? []
            }
            guard !Task.isCancelled, contextIsCurrent else { return }
            let values = query.isEmpty
                ? savedAnimations
                : savedAnimations.filter { $0.fileName.localizedCaseInsensitiveContains(query) }
            animations = Dictionary(uniqueKeysWithValues: values.map { ($0.animation.id, $0) })
            applySnapshot(values.map { .animation($0.animation.id) })
        }
    }

    private func applyEmojiSnapshot() {
        applySnapshot(Self.emojis.map(ItemID.emoji))
    }

    private func applySnapshot(_ items: [ItemID]) {
        sectionTitles = [:]
        var snapshot = NSDiffableDataSourceSnapshot<Section, ItemID>()
        snapshot.appendSections([.content])
        snapshot.appendItems(items)
        dataSource.apply(snapshot, animatingDifferences: true)
        collectionView.backgroundView = items.isEmpty ? emptyLabel() : nil
    }

    /// Favorite Stickers, Recently Used and the installed packs in order. Each pack fills in as TDLib returns it.
    private func loadStickerGroups() async {
        let client = client
        async let favoritesRequest = client.send(TDNativeRequests.getFavoriteStickers())
        async let recentRequest = client.send(TDNativeRequests.getRecentStickers(isAttached: false))
        async let setsRequest = client.send(TDNativeRequests.getInstalledStickerSets(stickerType: .stickerTypeRegular))
        let favorites = await Self.sendableStickers((try? favoritesRequest)?.stickers ?? [])
        let recent = await Self.sendableStickers((try? recentRequest)?.stickers ?? [])
        let sets = await (try? setsRequest)?.sets ?? []
        guard !Task.isCancelled, contextIsCurrent, mode == .stickers else { return }
        favoriteStickerIDs = Set(favorites.map(\.sticker.id))
        var groups = [(Section, [Sticker])]()
        var titles = [Section: String]()
        if !favorites.isEmpty {
            groups.append((.favorites, favorites))
            titles[.favorites] = L10n.telegram("EmojiInput.SectionTitleFavoriteStickers")
        }
        if !recent.isEmpty {
            groups.append((.recent, Array(recent.prefix(Self.recentStickerLimit))))
            titles[.recent] = L10n.telegram("Stickers.FrequentlyUsed")
        }
        applyStickerGroups(groups, titles: titles)
        for (index, info) in sets.enumerated() {
            let set = try? await client.send(TDNativeRequests.getStickerSet(setId: info.id))
            guard !Task.isCancelled, contextIsCurrent, mode == .stickers else { return }
            let values = Self.sendableStickers(set?.stickers ?? [])
            guard !values.isEmpty else { continue }
            groups.append((.pack(info.id), values))
            titles[.pack(info.id)] = info.title
            // The first packs show at once; the rest arrive in batches.
            if index < 3 || index % 6 == 5 { applyStickerGroups(groups, titles: titles) }
        }
        applyStickerGroups(groups, titles: titles)
    }

    private func applyStickerGroups(_ groups: [(Section, [Sticker])], titles: [Section: String]) {
        sectionTitles = titles
        var snapshot = NSDiffableDataSourceSnapshot<Section, ItemID>()
        for (section, values) in groups {
            for sticker in values {
                stickers[sticker.sticker.id] = sticker
            }
            let items = values.map { ItemID.groupedSticker(section, $0.sticker.id) }.uniqued()
            guard !items.isEmpty else { continue }
            snapshot.appendSections([section])
            snapshot.appendItems(items, toSection: section)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
        collectionView.backgroundView = snapshot.numberOfItems == 0 ? emptyLabel() : nil
    }

    // MARK: Item menus

    private func hasMenu(_ item: ItemID) -> Bool {
        switch item {
        case .animation, .groupedSticker: true
        // Custom emoji have no sticker menu.
        case .sticker: mode == .stickers
        case .emoji: false
        }
    }

    /// Telegram's sticker and GIF preview menus (StickerPreviewPeekContent, ChatContextResultPeekContent).
    @objc private func itemLongPressed(_ gesture: ContextMenuPressGestureRecognizer) {
        guard gesture.state == .began, contextIsCurrent,
              let path = collectionView.indexPathForItem(at: gesture.location(in: collectionView)),
              let item = dataSource.itemIdentifier(for: path),
              let cell = collectionView.cellForItem(at: path)
        else { return }
        let actions: [TelegramContextMenuAction]
        switch item {
        case .groupedSticker(let section, let id):
            guard let sticker = stickers[id] else { return }
            actions = stickerActions(sticker, section: section)
        case .sticker(let id):
            guard mode == .stickers, let sticker = stickers[id] else { return }
            actions = stickerActions(sticker, section: .content)
        case .animation(let id):
            guard let animation = animations[id] else { return }
            actions = [
                TelegramContextMenuAction(
                    title: L10n.telegram("Preview.DeleteGif"),
                    image: UIImage(systemName: "trash"),
                    isDestructive: true,
                ) { [weak self] in self?.removeSavedAnimation(animation) },
            ]
        case .emoji:
            return
        }
        presentTelegramContextMenu(sourceView: cell, actions: actions, tracking: gesture, presentationStyle: .menuOnly)
    }

    private func stickerActions(_ sticker: Sticker, section: Section) -> [TelegramContextMenuAction] {
        let isFavorite = favoriteStickerIDs.contains(sticker.sticker.id)
        var actions = [
            TelegramContextMenuAction(
                title: L10n.telegram("StickerPack.Send"),
                image: UIImage(systemName: "paperplane"),
            ) { [weak self] in
                guard let self, contextIsCurrent else { return }
                onSticker?(sticker)
            },
            TelegramContextMenuAction(
                title: L10n.telegram(isFavorite ? "Stickers.RemoveFromFavorites" : "Stickers.AddToFavorites"),
                image: UIImage(systemName: isFavorite ? "star.slash" : "star"),
            ) { [weak self] in
                self?.changeSticker(
                    sticker,
                    request: isFavorite
                        ? TDNativeRequests
                            .removeFavoriteSticker(sticker: .inputFileId(InputFileId(id: sticker.sticker.id)))
                        : TDNativeRequests
                            .addFavoriteSticker(sticker: .inputFileId(InputFileId(id: sticker.sticker.id))),
                    toast: L10n.telegram(
                        isFavorite
                            ? "Conversation.StickerRemovedFromFavorites"
                            : "Conversation.StickerAddedToFavorites",
                    ),
                )
            },
        ]
        if sticker.setId != 0 {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("StickerPack.ViewPack"),
                image: UIImage(systemName: "square.grid.2x2"),
            ) { [weak self] in self?.openStickerSet(sticker.setId) })
        }
        if section == .recent {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Stickers.RemoveFromRecent"),
                image: UIImage(systemName: "clock.arrow.circlepath"),
                isDestructive: true,
            ) { [weak self] in
                self?.changeSticker(sticker, request: TDNativeRequests.removeRecentSticker(
                    isAttached: false, sticker: .inputFileId(InputFileId(id: sticker.sticker.id)),
                ))
            })
        }
        return actions
    }

    private func changeSticker(_: Sticker, request: TDRequest<TDNativeOk>, toast: String? = nil) {
        guard stickerActionTask == nil, contextIsCurrent else { return }
        let client = client
        stickerActionTask = Task { [weak self] in
            let succeeded = await (try? client.send(request)) != nil
            guard let self, !Task.isCancelled else { return }
            stickerActionTask = nil
            guard contextIsCurrent else { return }
            guard succeeded else {
                presentChatListActionFailure()
                return
            }
            if let toast {
                TelegramUndoToast.show(text: toast, in: view, bottomInset: 12, undo: nil)
            }
            guard mode == .stickers, (searchBar.text ?? "").isEmpty else { return }
            loadTask?.cancel()
            loadTask = Task { [weak self] in await self?.loadStickerGroups() }
        }
    }

    /// Telegram's GIF preview Delete (removeSavedGif).
    private func removeSavedAnimation(_ animation: Animation) {
        guard stickerActionTask == nil, contextIsCurrent else { return }
        let client = client
        let fileID = animation.animation.id
        stickerActionTask = Task { [weak self] in
            let succeeded = await (try? client.send(TDNativeRequests.removeSavedAnimation(
                animation: .inputFileId(InputFileId(id: fileID)),
            ))) != nil
            guard let self, !Task.isCancelled else { return }
            stickerActionTask = nil
            guard contextIsCurrent else { return }
            guard succeeded else {
                presentChatListActionFailure()
                return
            }
            savedAnimations.removeAll { $0.animation.id == fileID }
            guard mode == .gifs else { return }
            await reload(query: (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func openStickerSet(_ setID: Int64) {
        guard contextIsCurrent, presentedViewController == nil else { return }
        let sendSticker = allowsStickersAndGIFs ? onSticker : nil
        StickerPackPreviewViewController.present(setID: setID, client: client, from: self, onSend: sendSticker)
    }

    private func emptyLabel() -> UIView {
        let label = UILabel()
        label.text = mode == .gifs ? L10n.betterTG("Composer.NoSavedGIFs") : L10n.telegram("Stickers.NoStickersFound")
        if mode == .customEmoji { label.text = L10n.betterTG("CustomEmoji.Empty") }
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }

    @objc private func donePressed() {
        dismissPicker()
    }

    private func dismissPicker() {
        dismiss(animated: true, completion: onDismiss)
    }
}

// MARK: - ComposerEmojiCell

private final class ComposerEmojiCell: UICollectionViewCell {
    static let reuseIdentifier = "ComposerEmojiCell"

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 30)
        label.textAlignment = .center
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    func configure(emoji: String) {
        label.text = emoji
        isAccessibilityElement = true
        accessibilityLabel = emoji
        accessibilityTraits = .button
    }
}

// MARK: - ComposerStickerCell

/// Also the sticker pack preview's cell.
final class ComposerStickerCell: UICollectionViewCell {
    static let reuseIdentifier = "ComposerStickerCell"

    private let stickerView = CustomEmojiInlineView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        stickerView.translatesAutoresizingMaskIntoConstraints = false
        stickerView.isUserInteractionEnabled = false
        contentView.addSubview(stickerView)
        NSLayoutConstraint.activate([
            stickerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            stickerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 3),
            stickerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -3),
            stickerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        stickerView.prepareForReuse()
    }

    func configure(sticker: Sticker, client: TDLibClient) {
        stickerView.configure(sticker: sticker, client: client)
        isAccessibilityElement = true
        accessibilityLabel = sticker.emoji.isEmpty
            ? L10n.telegram("Message.Sticker")
            : L10n.telegram("Message.StickerText", sticker.emoji)
        accessibilityTraits = .button
    }

    func setPlaybackVisible(_ visible: Bool) {
        stickerView.setPlaybackVisible(visible)
    }
}

// MARK: - ComposerAnimationCell

/// Telegram's GIF panel plays its visible GIFs silently in a loop (MultiplexedVideoNode); the cell reuses the
/// message bubble's player, filling the square.
private final class ComposerAnimationCell: UICollectionViewCell {
    static let reuseIdentifier = "ComposerAnimationCell"

    private let animationView = InlineAnimationMediaView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .tertiarySystemFill
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true
        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.fillsBounds = true
        animationView.isUserInteractionEnabled = false
        animationView.isAccessibilityElement = false
        contentView.addSubview(animationView)
        NSLayoutConstraint.activate([
            animationView.topAnchor.constraint(equalTo: contentView.topAnchor),
            animationView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            animationView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        animationView.prepareForReuse()
    }

    func configure(animation: Animation, client: TDLibClient) {
        animationView.configure(animation: animation, displaySize: nil, client: client)
        isAccessibilityElement = true
        accessibilityLabel = animation.fileName.isEmpty
            ? L10n.telegram("Message.Animation")
            : "\(L10n.telegram("Message.Animation")) \(animation.fileName)"
        accessibilityTraits = .button
    }

    func setPlaybackVisible(_ visible: Bool) {
        animationView.setPlaybackVisible(visible)
    }
}

// MARK: - ComposerSectionHeaderView

/// A sticker group's title, as Telegram's keyboard heads Favorite Stickers, Recently Used and each pack.
private final class ComposerSectionHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "ComposerSectionHeaderView"

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String) {
        label.text = title
        accessibilityTraits = .header
        isAccessibilityElement = true
        accessibilityLabel = title
    }
}
