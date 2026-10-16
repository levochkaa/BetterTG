// ComposerMediaPickerViewController.swift

import AudioToolbox
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

    /// A sheet with Done, or Telegram's media input panel where the system keyboard goes (ChatEntityKeyboardInputNode),
    /// whose search field opens the expanded search and whose emoji tabs add the globe and backspace keys.
    enum PresentationStyle {
        case sheet
        case input
    }

    /// Telegram's sticker tab groups (EmojiPagerContentSignals): Favorite Stickers, Recently Used, then every installed
    /// pack in the user's order. The emoji tab has Recently Used and Telegram's emoji categories. Searches and the
    /// other tabs use one plain section.
    private enum Section: Hashable {
        case content
        case favorites
        case recent
        case pack(Int64)
        case recentEmoji
        case emojiCategory(EmojiCatalog.Category)
        /// StickerPaneSearchContentNode's trending pane title, above the trending packs.
        case trending
        /// A pack found by a search or trending; its stickers open the pack.
        case foundPack(Int64)
    }

    private enum ItemID: Hashable {
        case animation(Int)
        /// A GIF the search bot found; each results page has its own inline query.
        case inlineAnimation(InlineAnimationKey)
        /// An emoji can be in Recently Used and its category at once.
        case emoji(Section, String)
        case sticker(Int)
        /// A sticker can be in Favorites, Recently Used and its pack at once.
        case groupedSticker(Section, Int)
    }

    private struct InlineAnimationKey: Hashable {
        let queryID: Int64
        let resultID: String
    }

    /// Telegram shows up to 20 recently used stickers.
    private static let recentStickerLimit = 20
    /// The emoji tab's category bar sits where the other tabs have their search field.
    private static let emojiCategoryBarHeight: CGFloat = 36

    var onAnimation: ((Animation) -> Void)?
    /// A GIF search result, sent only when tapped: the inline query and the result.
    var onInlineAnimation: ((Int64, String) -> Void)?
    var onDismiss: (() -> Void)?
    var onEmoji: ((String) -> Void)?
    var onCustomEmoji: ((Sticker) -> Void)?
    var onSticker: ((Sticker) -> Void)?
    /// Off while a message is edited (Telegram offers only emoji input then, `ChatInterfaceInputContexts`) or when the
    /// chat doesn't take stickers and GIFs: the picker keeps only its emoji tabs.
    var allowsStickersAndGIFs = true
    /// StickerAttachmentScreen's `.stickers` mode, which a poll option's Sticker button opens: the sticker tab alone,
    /// titled Sticker, with `stickersSubtitle` under the title.
    var showsStickersOnly = false
    var stickersSubtitle: String?
    var presentationStyle = PresentationStyle.sheet
    /// The tab the picker opens on; ChatEntityKeyboardInputNode's `defaultToEmojiTab` picks emoji or stickers.
    var initialMode = Mode.emoji
    /// The expanded search: the field takes focus as the sheet appears.
    var focusesSearchOnAppear = false
    /// Presents the picker's alerts, sticker packs and failures; the input panel lives in the keyboard's window.
    weak var presentationHost: UIViewController?
    var onDeleteBackward: (() -> Void)?
    var onSwitchToKeyboard: (() -> Void)?
    /// The input panel's search field opens the expanded search in this tab.
    var onExpandSearch: ((Mode) -> Void)?
    /// The sheet closed, by Done, a swipe or a pick.
    var onDidDismiss: (() -> Void)?

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
    private let switchToKeyboardButton = UIButton(type: .system)
    private let deleteBackwardButton = UIButton(type: .system)
    /// Telegram's emoji category icons (EntityKeyboardTopPanelComponent's static emoji segments) with Recently Used.
    private let emojiCategoryBar = UIStackView()
    private var emojiCategoryButtons = [(Section, UIButton)]()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, ItemID>!
    private var animations = [Int: Animation]()
    private var savedAnimations = [Animation]()
    /// GifContext.paneGifSearchForQuery: the search bot's GIFs for `gifSearchQuery`, and the next page's offset.
    private var inlineAnimations = [InlineAnimationKey: TDNativeInlineQueryResultAnimation]()
    private var inlineAnimationKeys = [InlineAnimationKey]()
    private var gifSearchQuery = ""
    private var gifNextOffset = ""
    private var gifSearchBotUserID: Int64?
    private var gifMoreTask: Task<Void, Never>?
    private var stickers = [Int: Sticker]()
    private var sectionTitles = [Section: String]()
    /// A found pack's sticker count, at the end of its header.
    private var sectionDetails = [Section: String]()
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

    private var presenter: UIViewController {
        presentationHost ?? self
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
        gifMoreTask?.cancel()
        stickerActionTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = presentationStyle == .input ? .clear : .systemBackground
        title = L10n.betterTG("Composer.EmojiAndStickersTitle")
        if presentationStyle == .sheet {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: L10n.telegram("Common.Done"), style: .plain,
                target: self,
                action: #selector(donePressed),
            )
        }
        configureViews()
        configureDataSource()
        if !allowsStickersAndGIFs {
            segmentedControl.removeSegment(at: Mode.gifs.rawValue, animated: false)
            segmentedControl.removeSegment(at: Mode.stickers.rawValue, animated: false)
        }
        segmentedControl.selectedSegmentIndex = Mode.emoji.rawValue
        searchBar.isHidden = true
        searchBarHeightConstraint.constant = Self.emojiCategoryBarHeight
        applyEmojiSnapshot()
        if showsStickersOnly, allowsStickersAndGIFs {
            title = L10n.telegram("StickerPicker.Title")
            navigationItem.subtitle = stickersSubtitle
            segmentedControl.isHidden = true
            segmentedControl.heightAnchor.constraint(equalToConstant: 0).isActive = true
            segmentedControl.selectedSegmentIndex = Mode.stickers.rawValue
            modeChanged()
        } else if initialMode != .emoji, allowsStickersAndGIFs || initialMode == .customEmoji {
            segmentedControl.selectedSegmentIndex = initialMode.rawValue
            modeChanged()
        }
        updateInputKeys(animated: false)
        // Its stickers and GIFs are the presenting client's files. A renewed client (the app returning from the
        // background) closes the sheet or the panel so the chat can move to the new client, instead of losing the
        // next tap.
        clientChangeCancellable = TDLib.shared
            .activeClientChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !contextIsCurrent else { return }
                if presentationStyle == .input {
                    onDismiss?()
                } else if presentingViewController != nil, !isBeingDismissed {
                    dismissPicker()
                }
            }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        guard focusesSearchOnAppear, !searchBar.isHidden else { return }
        focusesSearchOnAppear = false
        searchBar.becomeFirstResponder()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard presentationStyle == .sheet, isBeingDismissed || navigationController?.isBeingDismissed == true
        else { return }
        onDidDismiss?()
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

    /// StickerPaneSearchContentNode: the installed packs matching the query (searchStickerSets), then the server's
    /// (searchStickerSetsRemotely), for a single emoji or at least two characters.
    private static func foundStickerSets(query: String, client: TDLibClient) async -> [TDNativeStickerSetInfo] {
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

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard contextIsCurrent,
              let item = dataSource.itemIdentifier(for: indexPath)
        else {
            dismissPicker()
            return
        }
        switch item {
        case .emoji(_, let emoji):
            RecentEmojiStore.shared.record(emoji, accountID: accountID)
            onEmoji?(emoji)
        case .groupedSticker(.foundPack(let setID), _):
            openStickerSet(setID)
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
                    presenter.present(alert, animated: true)
                    return
                }
                onCustomEmoji?(sticker)
            } else { onSticker?(sticker) }
        case .animation(let id):
            guard let animation = animations[id] else { return }
            onAnimation?(animation)
        case .inlineAnimation(let key):
            guard inlineAnimations[key] != nil else { return }
            onInlineAnimation?(key.queryID, key.resultID)
        }
    }

    func collectionView(_: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? ComposerStickerCell)?.setPlaybackVisible(true)
        (cell as? ComposerAnimationCell)?.setPlaybackVisible(true)
        if case .inlineAnimation(let key) = dataSource.itemIdentifier(for: indexPath),
           let index = inlineAnimationKeys.firstIndex(of: key), index >= inlineAnimationKeys.count - 8
        {
            loadMoreGIFs()
        }
    }

    func collectionView(_: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt _: IndexPath) {
        (cell as? ComposerStickerCell)?.setPlaybackVisible(false)
        (cell as? ComposerAnimationCell)?.setPlaybackVisible(false)
    }

    func scrollViewDidScroll(_: UIScrollView) {
        guard mode == .emoji else { return }
        updateEmojiCategoryHighlight()
    }

    /// The input panel's search field opens Telegram's expanded search, where the system keyboard can come up.
    func searchBarShouldBeginEditing(_: UISearchBar) -> Bool {
        guard presentationStyle == .input else { return true }
        if contextIsCurrent { onExpandSearch?(mode) }
        return false
    }

    func searchBar(_: UISearchBar, textDidChange searchText: String) {
        loadTask?.cancel()
        searchTask?.cancel()
        gifMoreTask?.cancel()
        gifMoreTask = nil
        searchTask = Task { [weak self] in
            try? await Task<Never, Never>.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            await reload(query: searchText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// StickerPaneSearchContentNode shows Telegram's trending packs while the search field is active and empty.
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        guard mode == .stickers, (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        loadTask?.cancel()
        searchTask?.cancel()
        loadTask = Task { [weak self] in await self?.loadTrendingStickerSets() }
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        guard mode == .stickers, (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        loadTask?.cancel()
        searchTask?.cancel()
        loadTask = Task { [weak self] in await self?.loadStickerGroups() }
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
        configureEmojiCategoryBar()

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = presentationStyle == .input ? .clear : .systemBackground
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
        let segmentedLeading: NSLayoutConstraint
        let segmentedTrailing: NSLayoutConstraint
        if presentationStyle == .input {
            configureInputKeys()
            segmentedLeading = segmentedControl.leadingAnchor.constraint(
                equalTo: switchToKeyboardButton.trailingAnchor,
                constant: 4,
            )
            segmentedTrailing = segmentedControl.trailingAnchor.constraint(
                equalTo: deleteBackwardButton.leadingAnchor,
                constant: -4,
            )
        } else {
            segmentedLeading = segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16)
            segmentedTrailing = segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        }
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            segmentedLeading,
            segmentedTrailing,
            searchBar.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 4),
            searchBarHeightConstraint,
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            collectionView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emojiCategoryBar.topAnchor.constraint(equalTo: searchBar.topAnchor),
            emojiCategoryBar.bottomAnchor.constraint(equalTo: searchBar.bottomAnchor),
            emojiCategoryBar.leadingAnchor.constraint(equalTo: searchBar.leadingAnchor),
            emojiCategoryBar.trailingAnchor.constraint(equalTo: searchBar.trailingAnchor),
        ])
    }

    /// EntityKeyboard's emoji accessory buttons beside the tabs: the globe switches to the system keyboard and the
    /// backspace deletes the character before the caret with the keyboard's delete sound.
    private func configureInputKeys() {
        let keys = [
            (switchToKeyboardButton, "globe", L10n.telegram("VoiceOver.Keyboard")),
            (deleteBackwardButton, "delete.left", L10n.telegram("Common.Delete")),
        ]
        for (button, symbol, label) in keys {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setImage(
                UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18)),
                for: .normal,
            )
            button.tintColor = .secondaryLabel
            button.accessibilityLabel = label
            view.addSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 40),
                button.heightAnchor.constraint(equalToConstant: 32),
                button.centerYAnchor.constraint(equalTo: segmentedControl.centerYAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            switchToKeyboardButton.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 6,
            ),
            deleteBackwardButton.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -6,
            ),
        ])
        switchToKeyboardButton.addAction(UIAction { [weak self] _ in self?.onSwitchToKeyboard?() }, for: .touchUpInside)
        deleteBackwardButton.addAction(UIAction { [weak self] _ in
            self?.onDeleteBackward?()
            AudioServicesPlaySystemSound(1155)
        }, for: .touchUpInside)
    }

    /// The globe and backspace stand beside the emoji tabs only, scaling in and out over 0.2 s as Telegram's bottom
    /// panel accessory buttons do.
    private func updateInputKeys(animated: Bool) {
        guard presentationStyle == .input else { return }
        let visible = mode == .emoji || mode == .customEmoji
        for button in [switchToKeyboardButton, deleteBackwardButton] where button.isEnabled != visible {
            button.isEnabled = visible
            let changes = {
                button.alpha = visible ? 1 : 0
                button.transform = visible ? .identity : CGAffineTransform(scaleX: 0.01, y: 0.01)
            }
            if animated {
                UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState], animations: changes)
            } else {
                changes()
            }
        }
    }

    private func configureEmojiCategoryBar() {
        emojiCategoryBar.translatesAutoresizingMaskIntoConstraints = false
        emojiCategoryBar.axis = .horizontal
        emojiCategoryBar.distribution = .fillEqually
        let entries = [(Section.recentEmoji, "clock", L10n.telegram("Emoji.FrequentlyUsed"))]
            + EmojiCatalog.Category.allCases.map { (Section.emojiCategory($0), $0.symbolName, $0.title) }
        for (section, symbol, title) in entries {
            let button = UIButton(type: .system)
            button.setImage(
                UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)),
                for: .normal,
            )
            button.tintColor = .secondaryLabel
            button.accessibilityLabel = title
            button.addAction(UIAction { [weak self] _ in self?.scrollToEmojiSection(section) }, for: .touchUpInside)
            emojiCategoryBar.addArrangedSubview(button)
            emojiCategoryButtons.append((section, button))
        }
        view.addSubview(emojiCategoryBar)
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
            case .emoji(_, let emoji):
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
            case .inlineAnimation(let key):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: ComposerAnimationCell.reuseIdentifier,
                    for: indexPath,
                ) as? ComposerAnimationCell
                if let result = inlineAnimations[key] {
                    cell?.configure(animation: result.animation, client: client)
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
            var action: (() -> Void)?
            if case .foundPack(let setID) = section {
                action = { [weak self] in self?.openStickerSet(setID) }
            }
            header?.configure(
                title: section.flatMap { self?.sectionTitles[$0] } ?? "",
                detail: section.flatMap { self?.sectionDetails[$0] },
                action: action,
            )
            return header
        }
    }

    @objc private func modeChanged() {
        loadTask?.cancel()
        searchTask?.cancel()
        gifMoreTask?.cancel()
        gifMoreTask = nil
        searchBar.text = ""
        searchBar.placeholder = mode == .gifs
            ? L10n.telegram("Gif.Search")
            : L10n.telegram("StickersSearch.SearchStickersPlaceholder")
        if mode == .customEmoji { searchBar.placeholder = L10n.betterTG("CustomEmoji.Search") }
        searchBar.isHidden = mode == .emoji
        emojiCategoryBar.isHidden = mode != .emoji
        searchBarHeightConstraint.constant = mode == .emoji ? Self.emojiCategoryBarHeight : 44
        collectionView.collectionViewLayout.invalidateLayout()
        updateInputKeys(animated: true)
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
                if searchBar.isFirstResponder {
                    await loadTrendingStickerSets()
                } else {
                    await loadStickerGroups()
                }
                return
            }
            async let request = client.getStickers(
                chatId: chatID,
                limit: 100,
                query: query,
                stickerType: .stickerTypeRegular,
            )
            async let packsRequest = Self.foundStickerSets(query: query, client: client)
            let result = try? await request
            let packs = await packsRequest
            guard !Task.isCancelled, contextIsCurrent, mode == .stickers else { return }
            let values = Self.sendableStickers(result?.stickers ?? [])
            stickers = Dictionary(values.map { ($0.sticker.id, $0) }, uniquingKeysWith: { _, latest in latest })
            applyStickerSets(packs, stickers: values, heading: nil)
        case .gifs:
            guard query.isEmpty else {
                await searchGIFs(query: query, offset: "")
                return
            }
            if savedAnimations.isEmpty {
                savedAnimations = await (try? client.getSavedAnimations().animations) ?? []
            }
            guard !Task.isCancelled, contextIsCurrent, mode == .gifs else { return }
            gifSearchQuery = ""
            animations = Dictionary(
                savedAnimations.map { ($0.animation.id, $0) },
                uniquingKeysWith: { _, latest in latest },
            )
            applySnapshot(savedAnimations.map { .animation($0.animation.id) }.uniqued())
        }
    }

    // MARK: GIF search

    /// GifContext.paneGifSearchForQuery: the bot named by animation_search_bot_username, else @gif, resolved once.
    private func gifSearchBot() async -> Int64? {
        if let gifSearchBotUserID { return gifSearchBotUserID }
        var username = "gif"
        if case .optionValueString(let option) = try? await client.getOption(name: "animation_search_bot_username"),
           !option.value.isEmpty
        {
            username = option.value
        }
        guard let chat = try? await client.send(TDNativeRequests.searchPublicChat(username: username)),
              case .chatTypePrivate(let bot) = chat.type
        else { return nil }
        gifSearchBotUserID = bot.userId
        return bot.userId
    }

    /// The query goes to the GIF search bot as an inline query; its GIFs fill the grid and the next page loads near
    /// the end. Nothing is sent until a GIF is tapped.
    private func searchGIFs(query: String, offset: String) async {
        let botUserID = await gifSearchBot()
        var found: TDNativeInlineQueryResults?
        if let botUserID {
            found = try? await client.send(TDNativeRequests.getInlineQueryResults(
                botUserId: botUserID, chatId: chatID, userLocation: nil, query: query, offset: offset,
            ))
        }
        guard !Task.isCancelled, contextIsCurrent, mode == .gifs,
              (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == query
        else { return }
        if offset.isEmpty {
            inlineAnimations = [:]
            inlineAnimationKeys = []
        } else {
            guard gifSearchQuery == query, gifNextOffset == offset else { return }
        }
        gifSearchQuery = query
        gifNextOffset = found?.nextOffset ?? ""
        var seenResults = Set(inlineAnimationKeys.map(\.resultID))
        for result in found?.results ?? [] {
            guard case .inlineQueryResultAnimation(let animation) = result,
                  seenResults.insert(animation.id).inserted,
                  let queryID = found?.inlineQueryId
            else { continue }
            let key = InlineAnimationKey(queryID: queryID, resultID: animation.id)
            inlineAnimations[key] = animation
            inlineAnimationKeys.append(key)
        }
        applySnapshot(inlineAnimationKeys.map { .inlineAnimation($0) })
    }

    private func loadMoreGIFs() {
        guard mode == .gifs, !gifSearchQuery.isEmpty, !gifNextOffset.isEmpty, gifMoreTask == nil else { return }
        let query = gifSearchQuery
        let offset = gifNextOffset
        gifMoreTask = Task { [weak self] in
            await self?.searchGIFs(query: query, offset: offset)
            guard !Task.isCancelled else { return }
            self?.gifMoreTask = nil
        }
    }

    /// EmojiPagerContentSignals: Recently Used (the account's latest emoji), then Telegram's static emoji by category.
    /// An emoji used now moves to the front the next time the tab opens, so the grid stays put under the finger.
    private func applyEmojiSnapshot() {
        var titles = [Section: String]()
        var snapshot = NSDiffableDataSourceSnapshot<Section, ItemID>()
        let recent = RecentEmojiStore.shared.emojis(accountID: accountID).uniqued()
        if !recent.isEmpty {
            snapshot.appendSections([.recentEmoji])
            snapshot.appendItems(recent.map { .emoji(.recentEmoji, $0) }, toSection: .recentEmoji)
            titles[.recentEmoji] = L10n.telegram("Emoji.FrequentlyUsed")
        }
        for category in EmojiCatalog.Category.allCases {
            let section = Section.emojiCategory(category)
            snapshot.appendSections([section])
            snapshot.appendItems(category.emojis.uniqued().map { .emoji(section, $0) }, toSection: section)
            titles[section] = category.title
        }
        sectionTitles = titles
        sectionDetails = [:]
        dataSource.apply(snapshot, animatingDifferences: false)
        collectionView.backgroundView = nil
        for (section, button) in emojiCategoryButtons {
            button.isHidden = snapshot.indexOfSection(section) == nil
        }
        updateEmojiCategoryHighlight()
    }

    /// EntityKeyboardTopPanelComponent's segment tap: the category's header moves to the top.
    private func scrollToEmojiSection(_ section: Section) {
        guard mode == .emoji, let index = dataSource.snapshot().indexOfSection(section) else { return }
        collectionView.layoutIfNeeded()
        guard let header = collectionView.layoutAttributesForSupplementaryElement(
            ofKind: UICollectionView.elementKindSectionHeader,
            at: IndexPath(item: 0, section: index),
        ) else { return }
        let inset = collectionView.adjustedContentInset
        let maximum = max(-inset.top, collectionView.contentSize.height + inset.bottom - collectionView.bounds.height)
        let offset = min(max(header.frame.minY - inset.top, -inset.top), maximum)
        collectionView.setContentOffset(CGPoint(x: 0, y: offset), animated: true)
    }

    /// The bar marks the category at the top of the grid.
    private func updateEmojiCategoryHighlight() {
        let snapshot = dataSource.snapshot()
        let topSection = collectionView.indexPathsForVisibleItems.map(\.section).min() ?? 0
        let current = snapshot.sectionIdentifiers.indices.contains(topSection)
            ? snapshot.sectionIdentifiers[topSection]
            : nil
        for (section, button) in emojiCategoryButtons {
            button.tintColor = section == current ? .tintColor : .secondaryLabel
            button.accessibilityTraits = section == current ? [.button, .selected] : .button
        }
    }

    private func applySnapshot(_ items: [ItemID]) {
        sectionTitles = [:]
        sectionDetails = [:]
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
        sectionDetails = [:]
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

    /// StickerPaneSearchContentNode's trending pane (ChatMediaInputTrendingPane): Telegram's trending packs.
    private func loadTrendingStickerSets() async {
        let result = try? await client.send(TDNativeRequests.getTrendingStickerSets(
            stickerType: .stickerTypeRegular, offset: 0, limit: 30,
        ))
        guard !Task.isCancelled, contextIsCurrent, mode == .stickers, searchBar.isFirstResponder,
              (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        applyStickerSets(
            result?.sets ?? [],
            stickers: [],
            heading: L10n.telegram("StickerPacksSettings.FeaturedPacks"),
        )
    }

    /// The matching stickers, then each pack with a row of its first stickers under its title and sticker count.
    /// A pack's stickers and header open its preview, where it can be added or sent from.
    private func applyStickerSets(_ packs: [TDNativeStickerSetInfo], stickers values: [Sticker], heading: String?) {
        var titles = [Section: String]()
        var details = [Section: String]()
        var snapshot = NSDiffableDataSourceSnapshot<Section, ItemID>()
        if !values.isEmpty {
            snapshot.appendSections([.content])
            snapshot.appendItems(values.map { .sticker($0.sticker.id) }.uniqued(), toSection: .content)
        }
        var packSections = [(Section, [Sticker])]()
        for pack in packs {
            // A row of covers; BetterTG sends no Premium stickers.
            let covers = Array(Self.sendableStickers(pack.covers).prefix(4))
            guard !covers.isEmpty else { continue }
            let section = Section.foundPack(pack.id)
            packSections.append((section, covers))
            titles[section] = pack.title
            details[section] = L10n.telegramPlural(
                "StickerPack.StickerCount",
                count: pack.size,
                formattedCount: pack.size.formatted(.number),
            )
        }
        if let heading, !packSections.isEmpty {
            snapshot.appendSections([.trending])
            titles[.trending] = heading
        }
        for (section, covers) in packSections {
            for sticker in covers {
                stickers[sticker.sticker.id] = sticker
            }
            snapshot.appendSections([section])
            snapshot.appendItems(covers.map { .groupedSticker(section, $0.sticker.id) }.uniqued(), toSection: section)
        }
        sectionTitles = titles
        sectionDetails = details
        dataSource.apply(snapshot, animatingDifferences: false)
        collectionView.backgroundView = snapshot.numberOfItems == 0 ? emptyLabel() : nil
    }

    // MARK: Item menus

    private func hasMenu(_ item: ItemID) -> Bool {
        switch item {
        case .animation, .groupedSticker: true
        // Custom emoji have no sticker menu.
        case .sticker: mode == .stickers
        case .emoji, .inlineAnimation: false
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
        case .emoji, .inlineAnimation:
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
                presenter.presentChatListActionFailure()
                return
            }
            if let toast {
                TelegramUndoToast.show(text: toast, in: view, bottomInset: 12, undo: nil)
            }
            guard mode == .stickers, (searchBar.text ?? "").isEmpty, !searchBar.isFirstResponder else { return }
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
                presenter.presentChatListActionFailure()
                return
            }
            savedAnimations.removeAll { $0.animation.id == fileID }
            guard mode == .gifs else { return }
            await reload(query: (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func openStickerSet(_ setID: Int64) {
        guard contextIsCurrent, presenter.presentedViewController == nil else { return }
        let sendSticker = allowsStickersAndGIFs ? onSticker : nil
        StickerPackPreviewViewController.present(setID: setID, client: client, from: presenter, onSend: sendSticker)
    }

    private func emptyLabel() -> UIView {
        let label = UILabel()
        label.text = mode == .gifs ? L10n.betterTG("Composer.NoSavedGIFs") : L10n.telegram("Stickers.NoStickersFound")
        if mode == .gifs, !gifSearchQuery.isEmpty { label.text = L10n.telegram("Gif.NoGifsFound") }
        if mode == .customEmoji { label.text = L10n.betterTG("CustomEmoji.Empty") }
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }

    @objc private func donePressed() {
        dismissPicker()
    }

    private func dismissPicker() {
        guard presentationStyle == .sheet else {
            onDismiss?()
            return
        }
        dismiss(animated: true, completion: onDismiss)
    }
}

// MARK: - EmojiCatalog.Category

/// The emoji tab's category names and the icons of its bar, in the order of Telegram's StaticEmojiSegment.
private extension EmojiCatalog.Category {
    var title: String {
        switch self {
        case .people: L10n.betterTG("Emoji.Category.People")
        case .animalsAndNature: L10n.betterTG("Emoji.Category.AnimalsAndNature")
        case .foodAndDrink: L10n.betterTG("Emoji.Category.FoodAndDrink")
        case .activity: L10n.betterTG("Emoji.Category.Activity")
        case .travelAndPlaces: L10n.betterTG("Emoji.Category.TravelAndPlaces")
        case .objects: L10n.betterTG("Emoji.Category.Objects")
        case .symbols: L10n.betterTG("Emoji.Category.Symbols")
        case .flags: L10n.betterTG("Emoji.Category.Flags")
        }
    }

    var symbolName: String {
        switch self {
        case .people: "face.smiling"
        case .animalsAndNature: "pawprint"
        case .foodAndDrink: "fork.knife"
        case .activity: "soccerball"
        case .travelAndPlaces: "car"
        case .objects: "lightbulb"
        case .symbols: "heart"
        case .flags: "flag"
        }
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

/// A sticker group's title, as Telegram's keyboard heads Favorite Stickers, Recently Used and each pack. A found pack's
/// header also shows its sticker count and opens the pack.
private final class ComposerSectionHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "ComposerSectionHeaderView"

    private let label = UILabel()
    private let detailLabel = UILabel()
    private var action: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .tertiaryLabel
        detailLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(detailLabel)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: detailLabel.leadingAnchor, constant: -8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            detailLabel.firstBaselineAnchor.constraint(equalTo: label.firstBaselineAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, detail: String? = nil, action: (() -> Void)? = nil) {
        label.text = title
        detailLabel.text = detail
        self.action = action
        accessibilityTraits = action == nil ? .header : [.header, .button]
        isAccessibilityElement = true
        accessibilityLabel = [title, detail].compactMap(\.self).joined(separator: ", ")
    }

    @objc private func tapped() {
        action?()
    }
}
