// StoryViewerViewListPanel.swift

import TDLibKit
import UIKit

// MARK: - StoryViewListPanel

/// StoryItemSetViewListComponent's panel under the account's own story: the title, or the All Viewers and Contacts
/// tabs, the sort button and search in a 56-point bar, then 60-point rows with the viewer, when they viewed and how,
/// and their reaction. Rows not loaded yet show Telegram's placeholder shapes; an empty list says why.
final class StoryViewListPanel: UIView, UITableViewDataSource, UITableViewDelegate {
    // MARK: Internal

    /// What the panel needs from the viewer: the story, its client, and how to load and name the viewers.
    struct Source {
        var story: Story
        let client: TDLibClient
        let accountID: UUID?
        let fetch: StoryViewListLoader.Fetch
        let resolvePeer: (MessageSender) async -> SettingsPeer?
        var scope = StoryViewList.Scope.own
    }

    static let navigationHeight = CGFloat(56)
    static let searchHeight = CGFloat(46)
    static let rowHeight = CGFloat(60)

    var onSelect: ((StoryViewList.Item) -> Void)?
    /// A row held for its menu (peerContextAction), with the row to lift and the press that keeps tracking.
    var onContextMenu: ((StoryViewList.Item, UIView, ContextMenuPressGestureRecognizer) -> Void)?
    /// The search field took or gave up the keyboard; Telegram expands the list for it.
    var onSearchActiveChanged: ((Bool) -> Void)?

    // MARK: Private

    private let navigationView = UIView()
    private let titleLabel = UILabel()
    private let tabsView = TelegramContextMenuSourceTabsView()
    private let sortButton = StoryViewListSortButton()
    private let searchField = UISearchTextField()
    private let navigationSeparator = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyView = UIView()
    private let emptyIconView = UIImageView()
    private let emptyLabel = UILabel()
    private let retryButton = UIButton(type: .system)

    private var source: Source?
    private var loader: StoryViewListLoader?
    private var header = StoryViewList.Header(title: "", showsTabs: false, showsSearch: false, showsSort: false)
    private var peers = [Int64: SettingsPeer]()
    private var pendingPeers = Set<Int64>()
    private var stickers = [Int64: Sticker]()
    private var pendingStickers = Set<Int64>()
    private var searchTask: Task<Void, Never>?
    private var keyboardOverlap = CGFloat.zero
    private var tabsConfigured = false

    /// Whether the list scrolls by itself; collapsed, a drag moves the panel instead.
    var isScrollEnabled: Bool {
        get { tableView.isScrollEnabled }
        set { tableView.isScrollEnabled = newValue }
    }

    /// The list scrolled to its top, where a pull moves the panel down.
    var isAtTop: Bool {
        tableView.contentOffset.y <= 0
    }

    var scrollView: UIScrollView {
        tableView
    }

    #if DEBUG
        var probeHeader: StoryViewList.Header { header }
        var probeQuery: StoryViewList.Query? { loader?.query }
        func probeSort(_ mode: StoryViewList.SortMode) { selectSort(mode) }
        var probeHasFailed: Bool { loader?.hasFailed == true }
        func probeRetry() { loader?.retry() }
        func probeOpenSortMenu() { openSortMenu() }
        var probeTitle: String? {
            titleLabel.isHidden ? (tabsView.isHidden ? nil : "tabs") : titleLabel.text
        }

        /// Each loaded row as "name|subtitle|reaction or kind", or the empty text.
        var probeRows: [String] {
            guard let loader, loader.isLoaded else { return ["loading"] }
            if loader.items.isEmpty { return ["empty:" + (emptyLabel.attributedText?.string ?? "")] }
            return loader.items.map { item in
                let detail =
                    switch item.kind {
                    case .view(let reaction): reaction?.standardEmoji ?? (reaction == nil ? "view" : "custom")
                    case .forward: "forward"
                    case .repost: "repost"
                    }
                return [peers[item.actorID]?.title ?? "?", StoryViewList.subtitle(for: item), detail]
                    .joined(separator: "|")
            }
        }

        func probeItem(at index: Int) -> StoryViewList.Item? {
            guard let loader, loader.items.indices.contains(index) else { return nil }
            return loader.items[index]
        }

        func probeSelectRow(_ index: Int) {
            guard let loader, loader.items.indices.contains(index) else { return }
            onSelect?(loader.items[index])
        }

        func probeSearch(_ text: String) {
            searchField.text = text
            searchChanged()
        }
    #endif

    private var navigationHeight: CGFloat {
        Self.navigationHeight + (header.showsSearch ? Self.searchHeight : 0)
    }

    /// Rows shown before the first page arrives: Telegram's placeholders up to the expected count.
    private var placeholderCount: Int {
        guard let loader, !loader.isLoaded else { return 0 }
        let expected = loader.query == source?.scope.defaultQuery
            ? source?.story.interactionInfo?.viewCount ?? 0
            : 6
        return min(expected, 20)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        overrideUserInterfaceStyle = .dark
        retryButton.setTitle(L10n.telegram("ChatImportActivity.Retry"), for: .normal)
        retryButton.addAction(UIAction { [weak self] _ in self?.loader?.retry() }, for: .touchUpInside)
        backgroundColor = UIColor(white: 0.11, alpha: 1)

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        navigationView.addSubview(titleLabel)

        tabsView.onSelect = { [weak self] index in self?.selectTab(index) }
        navigationView.addSubview(tabsView)

        sortButton.addAction(UIAction { [weak self] _ in self?.openSortMenu() }, for: .touchUpInside)
        navigationView.addSubview(sortButton)

        searchField.placeholder = L10n.telegram("Common.Search")
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.addAction(UIAction { [weak self] _ in self?.searchChanged() }, for: .editingChanged)
        searchField.addAction(UIAction { [weak self] _ in self?.onSearchActiveChanged?(true) }, for: .editingDidBegin)
        searchField.addAction(UIAction { [weak self] _ in self?.onSearchActiveChanged?(false) }, for: .editingDidEnd)
        searchField.addAction(
            UIAction { [weak self] _ in self?.searchField.resignFirstResponder() },
            for: .editingDidEndOnExit,
        )
        navigationView.addSubview(searchField)

        navigationSeparator.backgroundColor = UIColor.separator
        navigationSeparator.alpha = 0
        navigationView.addSubview(navigationSeparator)

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = Self.rowHeight
        tableView.keyboardDismissMode = .onDrag
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(StoryViewListCell.self, forCellReuseIdentifier: StoryViewListCell.reuseIdentifier)
        let press = ContextMenuPressGestureRecognizer(target: self, action: #selector(rowPressed(_:)))
        press.pressedViewProvider = { [weak self] gesture in
            guard let self, source?.scope == .own,
                  let path = tableView.indexPathForRow(at: gesture.location(in: tableView)),
                  loader?.items.indices.contains(path.row) == true
            else { return nil }
            return tableView.cellForRow(at: path)?.contentView
        }
        tableView.addGestureRecognizer(press)
        addSubview(tableView)
        addSubview(navigationView)

        emptyIconView.tintColor = .secondaryLabel
        emptyIconView.contentMode = .scaleAspectFit
        emptyView.addSubview(emptyIconView)
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyView.addSubview(emptyLabel)
        emptyView.isHidden = true
        emptyView.isUserInteractionEnabled = false
        addSubview(emptyView)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
        )
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        searchTask?.cancel()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        navigationView.frame = CGRect(x: 0, y: 0, width: width, height: navigationHeight)
        let titleHeight = ceil(titleLabel.font.lineHeight)
        titleLabel.frame = CGRect(
            x: 80,
            y: ((Self.navigationHeight - titleHeight) / 2).rounded(.down),
            width: max(0, width - 160),
            height: titleHeight,
        )
        let tabsSize = tabsView.sizeThatFits(CGSize(width: width - 20, height: Self.navigationHeight))
        tabsView.frame = CGRect(
            x: ((width - tabsSize.width) / 2).rounded(.down),
            y: ((Self.navigationHeight - tabsSize.height) / 2).rounded(.down),
            width: tabsSize.width,
            height: tabsSize.height,
        )
        sortButton.frame = CGRect(
            x: width - 16 - StoryViewListSortButton.size.width,
            y: ((Self.navigationHeight - StoryViewListSortButton.size.height) / 2).rounded(.down),
            width: StoryViewListSortButton.size.width,
            height: StoryViewListSortButton.size.height,
        )
        searchField.frame = CGRect(x: 16, y: Self.navigationHeight - 4, width: max(0, width - 32), height: 36)
        navigationSeparator.frame = CGRect(
            x: 0,
            y: navigationHeight - 1 / max(1, traitCollection.displayScale),
            width: width,
            height: 1 / max(1, traitCollection.displayScale),
        )
        tableView.frame = CGRect(
            x: 0,
            y: navigationHeight,
            width: width,
            height: max(0, bounds.height - navigationHeight),
        )
        tableView.contentInset.bottom = max(safeAreaInsets.bottom, keyboardOverlap)
        tableView.verticalScrollIndicatorInsets.bottom = tableView.contentInset.bottom
        layoutEmptyView()
    }

    /// Telegram's markdown in the empty texts: **bold**.
    private static func emptyText(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let result = NSMutableAttributedString()
        for (index, part) in text.components(separatedBy: "**").enumerated() {
            result.append(NSAttributedString(string: part, attributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: index.isMultiple(of: 2) ? .regular : .semibold),
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: paragraph,
            ]))
        }
        return result
    }

    /// Shows the story's viewers, starting over with Telegram's default list.
    func configure(_ source: Source) {
        self.source = source
        peers = [:]
        pendingPeers = []
        stickers = [:]
        pendingStickers = []
        tabsConfigured = false
        searchField.text = nil
        let loader = StoryViewListLoader(fetch: source.fetch)
        loader.onChange = { [weak self] in self?.loaderChanged() }
        self.loader = loader
        loader.load(source.scope.defaultQuery)
    }

    func endSearch() {
        searchField.resignFirstResponder()
    }

    /// Counts/privacy may change while another story is selected; keep this panel's query and scroll position.
    func updateStory(_ story: Story) {
        guard source?.story.id == story.id, source?.story.posterChatId == story.posterChatId else { return }
        source?.story = story
        loaderChanged()
    }

    /// The viewer's place after a menu choice, so the next menu offers the opposite.
    func setBlockList(_ blockList: BlockList?, for actorID: Int64) {
        loader?.setBlockList(blockList, for: actorID)
    }

    func numberOfSections(in _: UITableView) -> Int {
        1
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        guard let loader else { return 0 }
        return loader.isLoaded ? loader.items.count : placeholderCount
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: StoryViewListCell.reuseIdentifier,
            for: indexPath,
        ) as! StoryViewListCell
        guard let loader, let source, loader.isLoaded, loader.items.indices.contains(indexPath.row) else {
            cell.configurePlaceholder()
            return cell
        }
        let item = loader.items[indexPath.row]
        let reaction: ReactionType? =
            if case .view(let reaction) = item.kind {
                reaction
            } else {
                nil
            }
        cell.configure(
            item: item,
            peer: peers[item.actorID],
            sticker: reaction?.customEmojiID.flatMap { stickers[$0] },
            hasNext: indexPath.row != loader.items.count - 1,
            client: source.client,
            accountID: source.accountID,
        )
        resolvePeer(item)
        return cell
    }

    func tableView(_: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let loader, loader.isLoaded, indexPath.row >= loader.items.count - 10 else { return }
        loader.loadMore()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let loader, loader.items.indices.contains(indexPath.row) else { return }
        onSelect?(loader.items[indexPath.row])
    }

    func tableView(_: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        loader?.items.indices.contains(indexPath.row) == true
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        navigationSeparator.alpha = scrollView.contentOffset.y > 0 ? 1 : 0
    }

    private func loaderChanged() {
        guard let loader, let source else { return }
        let query = loader.query
        // The header follows the full list's count, as Telegram's mainViewListState does.
        let total = query.text.isEmpty && query.listMode == .everyone ? loader.totalCount : nil
        let header = StoryViewList.header(story: source.story, totalCount: total, scope: source.scope)
        if header != self.header {
            self.header = header
            setNeedsLayout()
        }
        titleLabel.text = header.title
        titleLabel.isHidden = header.showsTabs
        tabsView.isHidden = !header.showsTabs
        if header.showsTabs, !tabsConfigured {
            tabsConfigured = true
            tabsView.configure(
                titles: [
                    L10n.telegram("Story.ViewList.TabTitleAll"),
                    L10n.telegram("Story.ViewList.TabTitleContacts"),
                ],
                selectedIndex: query.listMode == .everyone ? 0 : 1,
            )
        }
        sortButton.isHidden = !header.showsSort
        sortButton.mode = query.sortMode
        searchField.isHidden = !header.showsSearch
        let isEmpty = loader.isLoaded && loader.items.isEmpty
        emptyView.isHidden = !isEmpty
        emptyView.isUserInteractionEnabled = loader.hasFailed
        if isEmpty {
            emptyIconView.image = UIImage(
                systemName: loader.hasFailed
                    ? "exclamationmark.triangle"
                    : (query.text.isEmpty ? "eye.slash" : "magnifyingglass"),
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 56, weight: .light),
            )
            emptyLabel.attributedText = Self.emptyText(loader.hasFailed
                ? L10n.telegram("Login.UnknownError")
                : StoryViewList.emptyText(
                    query: query,
                    story: source.story,
                    scope: source.scope,
                ))
            setNeedsLayout()
        }
        requestStickers(loader.items)
        tableView.tableFooterView = nil
        retryButton.removeFromSuperview()
        if loader.hasFailed {
            if isEmpty { emptyView.addSubview(retryButton) }
            else {
                retryButton.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 52)
                tableView.tableFooterView = retryButton
            }
        }
        tableView.reloadData()
    }

    private func layoutEmptyView() {
        let width = bounds.width - 64
        let textSize = emptyLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let iconSize = CGFloat(72)
        let height = iconSize + 16 + textSize.height + (loader?.hasFailed == true ? 52 : 0)
        let available = bounds.height - navigationHeight - max(safeAreaInsets.bottom, keyboardOverlap)
        let top = navigationHeight + max(16, ((available - height) / 2).rounded(.down))
        emptyView.frame = CGRect(x: 32, y: top, width: width, height: height)
        emptyIconView.frame = CGRect(
            x: ((width - iconSize) / 2).rounded(.down),
            y: 0,
            width: iconSize,
            height: iconSize,
        )
        emptyLabel.frame = CGRect(x: 0, y: iconSize + 16, width: width, height: textSize.height)
        if retryButton.superview === emptyView {
            retryButton.frame = CGRect(x: 0, y: emptyLabel.frame.maxY + 8, width: width, height: 44)
        }
    }

    private func selectTab(_ index: Int) {
        guard var query = loader?.query else { return }
        query.listMode = index == 0 ? .everyone : .contacts
        guard query != loader?.query else { return }
        tabsView.setSelectedIndex(index, animated: true)
        loader?.load(query)
    }

    private func searchChanged() {
        searchTask?.cancel()
        let text = searchField.text ?? ""
        searchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, var query = loader?.query, query.text != text else { return }
            query.text = text
            loader?.load(query)
        }
    }

    /// openSortModeMenu for a user's story: Reactions First or Recent First, with the order's explanation below.
    private func openSortMenu() {
        guard let loader, let source, let controller = nearestViewController else { return }
        let current = loader.query.sortMode
        func option(_ mode: StoryViewList.SortMode, title: String) -> TelegramContextMenuAction {
            TelegramContextMenuAction(
                title: L10n.telegram(title),
                image: mode == current ? UIImage(systemName: "checkmark") : UIImage(),
            ) { [weak self] in
                self?.selectSort(mode)
            }
        }
        var info = TelegramContextMenuAction(title: L10n.telegram(source.scope == .chat
                ? "Story.ViewList.ContextSortChannelInfo"
                : "Story.ViewList.ContextSortInfo"))
        info.isInformational = true
        info.startsNewSection = true
        sortButton.alpha = 0.5
        controller.presentTelegramContextMenu(
            sourceView: sortButton,
            actions: [
                source.scope == .chat
                    ? option(.repostsFirst, title: "Story.ViewList.ContextSortReposts")
                    : option(.reactionsFirst, title: "Story.ViewList.ContextSortReactions"),
                option(.recentFirst, title: "Story.ViewList.ContextSortRecent"),
                info,
            ],
            presentationStyle: .sourceMorph,
            onDismiss: { [weak self] in
                UIView.animate(withDuration: 0.25) { self?.sortButton.alpha = 1 }
            },
        )
    }

    @objc private func rowPressed(_ gesture: ContextMenuPressGestureRecognizer) {
        guard source?.scope == .own, gesture.state == .began, let loader,
              let path = tableView.indexPathForRow(at: gesture.location(in: tableView)),
              loader.items.indices.contains(path.row), let cell = tableView.cellForRow(at: path)
        else { return }
        // The row's content lifts without the press's highlight, which lies under it.
        cell.setHighlighted(false, animated: false)
        onContextMenu?(loader.items[path.row], cell.contentView, gesture)
    }

    private func selectSort(_ mode: StoryViewList.SortMode) {
        guard var query = loader?.query, query.sortMode != mode else { return }
        query.sortMode = mode
        loader?.load(query)
    }

    private func resolvePeer(_ item: StoryViewList.Item) {
        let id = item.actorID
        guard peers[id] == nil, !pendingPeers.contains(id), let source else { return }
        pendingPeers.insert(id)
        Task { @MainActor [weak self] in
            let peer = await source.resolvePeer(item.actor)
            guard let self, self.source?.story.id == source.story.id else { return }
            pendingPeers.remove(id)
            guard let peer else { return }
            peers[id] = peer
            reloadRows { $0.actorID == id }
        }
    }

    private func requestStickers(_ items: [StoryViewList.Item]) {
        guard let source else { return }
        let identifiers = items.compactMap { item -> Int64? in
            guard case .view(let reaction?) = item.kind, let id = reaction.customEmojiID,
                  stickers[id] == nil, !pendingStickers.contains(id) else { return nil }
            return id
        }
        guard !identifiers.isEmpty else { return }
        pendingStickers.formUnion(identifiers)
        Task { @MainActor [weak self] in
            let found = await CustomEmojiStickerRepository.shared.stickers(for: identifiers, client: source.client)
            guard let self, self.source?.story.id == source.story.id else { return }
            stickers.merge(found) { $1 }
            reloadRows { item in
                if case .view(let reaction?) = item.kind, let id = reaction.customEmojiID { return found[id] != nil }
                return false
            }
        }
    }

    private func reloadRows(where matches: (StoryViewList.Item) -> Bool) {
        guard let loader, loader.isLoaded else { return }
        let paths = (tableView.indexPathsForVisibleRows ?? []).filter { path in
            loader.items.indices.contains(path.row) && matches(loader.items[path.row])
        }
        guard !paths.isEmpty else { return }
        UIView.performWithoutAnimation { tableView.reloadRows(at: paths, with: .none) }
    }

    @objc private func keyboardChanged(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let window else { return }
        let keyboard = convert(frame, from: window.screen.coordinateSpace)
        keyboardOverlap = max(0, bounds.maxY - keyboard.minY)
        setNeedsLayout()
    }
}

// MARK: - StoryViewListSortButton

/// OptionButtonComponent: a 53 by 28 capsule with the order's icon and a down arrow.
private final class StoryViewListSortButton: UIControl {
    static let size = CGSize(width: 53, height: 28)

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    var mode = StoryViewList.SortMode.reactionsFirst {
        didSet { updateIcon() }
    }

    private let iconView = UIImageView()
    private let arrowView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.white.withAlphaComponent(0.09)
        layer.cornerRadius = Self.size.height / 2
        iconView.tintColor = .white
        iconView.contentMode = .center
        arrowView.image = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold),
        )
        arrowView.tintColor = .white
        arrowView.contentMode = .center
        for view in [iconView, arrowView] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        isAccessibilityElement = true
        accessibilityTraits = .button
        updateIcon()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        iconView.frame = CGRect(x: 4, y: 0, width: 24, height: bounds.height)
        arrowView.frame = CGRect(x: bounds.width - 8 - 12, y: 1, width: 12, height: bounds.height)
    }

    private func updateIcon() {
        let symbol =
            switch mode {
            case .repostsFirst: "arrow.2.squarepath"
            case .reactionsFirst: "heart"
            case .recentFirst: "clock"
            }
        iconView.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium),
        )
        let key =
            switch mode {
            case .repostsFirst: "Story.ViewList.ContextSortReposts"
            case .reactionsFirst: "Story.ViewList.ContextSortReactions"
            case .recentFirst: "Story.ViewList.ContextSortRecent"
            }
        accessibilityLabel = L10n.telegram(key)
    }
}

// MARK: - StoryViewListCell

/// PeerListItemComponent's generic row: the 40-point avatar 10 points in, the semibold 17-point name and the 15-point
/// subtitle 62 points in, read checks or a green repost or forward icon before the subtitle, and the reaction 14
/// points from the right edge, a red heart for ❤.
private final class StoryViewListCell: UITableViewCell {
    static let reuseIdentifier = "StoryViewListCell"

    private static let placeholderColor = UIColor.white.withAlphaComponent(0.1)
    private static let readChecks: UIImage = {
        let size = CGSize(width: 15, height: 10)
        return UIGraphicsImageRenderer(size: size)
            .image { _ in
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 0.75, y: 5.5))
                path.addLine(to: CGPoint(x: 3.75, y: 8.5))
                path.addLine(to: CGPoint(x: 10.25, y: 1.5))
                path.move(to: CGPoint(x: 6.5, y: 8))
                path.addLine(to: CGPoint(x: 7, y: 8.5))
                path.addLine(to: CGPoint(x: 13.75, y: 1.5))
                path.lineWidth = 1.5
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                UIColor.black.setStroke()
                path.stroke()
            }
            .withRenderingMode(.alwaysTemplate)
    }()

    private let avatarView = ProfileAvatarView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let subtitleIconView = UIImageView()
    private let reactionLabel = UILabel()
    private let heartView = UIImageView()
    private let separator = UIView()
    private let placeholderAvatar = UIView()
    private let placeholderTitle = UIView()
    private let placeholderSubtitle = UIView()
    private var reactionEmoji: CustomEmojiInlineView?

    private var hasReaction: Bool {
        !heartView.isHidden || !reactionLabel.isHidden || reactionEmoji != nil
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        let selection = UIView()
        selection.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        selectedBackgroundView = selection
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel
        subtitleIconView.contentMode = .center
        reactionLabel.font = .systemFont(ofSize: 20)
        reactionLabel.textAlignment = .center
        heartView.image = UIImage(
            systemName: "heart.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular),
        )
        heartView.tintColor = .systemRed
        heartView.contentMode = .center
        separator.backgroundColor = .separator
        for view in [placeholderAvatar, placeholderTitle, placeholderSubtitle] {
            view.backgroundColor = Self.placeholderColor
            view.layer.cornerCurve = .continuous
        }
        placeholderAvatar.layer.cornerRadius = 20
        placeholderTitle.layer.cornerRadius = 4
        placeholderSubtitle.layer.cornerRadius = 4
        for view in [
            avatarView, titleLabel, subtitleIconView, subtitleLabel, reactionLabel, heartView, separator,
            placeholderAvatar, placeholderTitle, placeholderSubtitle,
        ] as [UIView] {
            contentView.addSubview(view)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
        reactionEmoji?.removeFromSuperview()
        reactionEmoji = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        let avatarFrame = CGRect(x: 10, y: ((bounds.height - 40) / 2).rounded(.down), width: 40, height: 40)
        avatarView.frame = avatarFrame
        placeholderAvatar.frame = avatarFrame
        let rightInset: CGFloat = 8 + (hasReaction ? 32 : 0)
        let textWidth = max(0, bounds.width - 62 - rightInset)
        let titleHeight = ceil(titleLabel.font.lineHeight)
        let subtitleHeight = ceil(subtitleLabel.font.lineHeight)
        let top = ((bounds.height - titleHeight - 1 - subtitleHeight) / 2).rounded(.down)
        titleLabel.frame = CGRect(x: 62, y: top, width: textWidth, height: titleHeight)
        let iconWidth = subtitleIconView.isHidden ? 0 : (subtitleIconView.image?.size.width ?? 0) + 4
        subtitleIconView.frame = CGRect(x: 62, y: top + titleHeight + 1, width: iconWidth - 4, height: subtitleHeight)
        subtitleLabel.frame = CGRect(
            x: 62 + iconWidth,
            y: top + titleHeight + 1,
            width: max(0, textWidth - iconWidth),
            height: subtitleHeight,
        )
        let reactionFrame = CGRect(
            x: bounds.width - 14 - 22,
            y: ((bounds.height - 22) / 2).rounded(.down),
            width: 22,
            height: 22,
        )
        reactionLabel.frame = reactionFrame.insetBy(dx: -4, dy: -4)
        heartView.frame = reactionFrame
        reactionEmoji?.frame = reactionFrame
        placeholderTitle.frame = CGRect(x: 62, y: titleLabel.frame.midY - 4, width: 120, height: 8)
        placeholderSubtitle.frame = CGRect(x: 62, y: subtitleLabel.frame.midY - 4, width: 70, height: 8)
        let line = 1 / max(1, traitCollection.displayScale)
        separator.frame = CGRect(x: 62, y: bounds.height - line, width: bounds.width - 62, height: line)
    }

    func configurePlaceholder() {
        setPlaceholder(true)
        separator.isHidden = true
        accessibilityLabel = nil
    }

    func configure(
        item: StoryViewList.Item,
        peer: SettingsPeer?,
        sticker: Sticker?,
        hasNext: Bool,
        client: TDLibClient,
        accountID: UUID?,
    ) {
        setPlaceholder(false)
        titleLabel.text = peer?.title ?? " "
        let subtitle = StoryViewList.subtitle(for: item)
        subtitleLabel.text = subtitle
        switch item.kind {
        case .view:
            subtitleIconView.image = Self.readChecks
            subtitleIconView.tintColor = .secondaryLabel
        case .forward:
            subtitleIconView.image = UIImage(
                systemName: "arrowshape.turn.up.right.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold),
            )
            subtitleIconView.tintColor = .systemGreen
        case .repost:
            subtitleIconView.image = UIImage(
                systemName: "arrow.2.squarepath",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold),
            )
            subtitleIconView.tintColor = .systemGreen
        }
        if let peer {
            avatarView.configure(
                file: peer.file,
                minithumbnail: peer.minithumbnail,
                placeholder: peer.placeholder,
                accountID: accountID,
                client: client,
            )
        }
        configureReaction(item: item, sticker: sticker, client: client)
        separator.isHidden = !hasNext
        accessibilityLabel = [peer?.title, subtitle, reactionLabel.text]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        setNeedsLayout()
    }

    private func configureReaction(item: StoryViewList.Item, sticker: Sticker?, client: TDLibClient) {
        heartView.isHidden = true
        reactionLabel.isHidden = true
        reactionLabel.text = nil
        reactionEmoji?.removeFromSuperview()
        reactionEmoji = nil
        guard case .view(let reaction?) = item.kind else { return }
        if reaction.standardEmoji == "❤" || reaction.standardEmoji == "❤️" {
            heartView.isHidden = false
        } else if let emoji = reaction.standardEmoji {
            reactionLabel.text = emoji
            reactionLabel.isHidden = false
        } else if let sticker {
            // A custom emoji shows once its sticker loads; the row reloads then.
            let view = CustomEmojiInlineView()
            view.isUserInteractionEnabled = false
            view.configure(sticker: sticker, client: client)
            view.setPlaybackVisible(true)
            contentView.addSubview(view)
            reactionEmoji = view
        }
    }

    private func setPlaceholder(_ isPlaceholder: Bool) {
        for view in [placeholderAvatar, placeholderTitle, placeholderSubtitle] {
            view.isHidden = !isPlaceholder
        }
        for view in [avatarView, titleLabel, subtitleLabel, subtitleIconView] as [UIView] {
            view.isHidden = isPlaceholder
        }
        if isPlaceholder {
            heartView.isHidden = true
            reactionLabel.isHidden = true
            reactionEmoji?.removeFromSuperview()
            reactionEmoji = nil
        }
        selectionStyle = isPlaceholder ? .none : .default
    }
}
