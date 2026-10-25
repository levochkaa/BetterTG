// StickerSetsSettingsViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - StickerSuggestionMode

/// StickerSettings' emojiStickerSuggestionMode, kept on the device as Telegram keeps it: which stickers the input
/// suggests for a lone emoji.
enum StickerSuggestionMode: String, CaseIterable {
    case all
    case installed
    case off

    // MARK: Private

    private static let defaultsKey = "BetterTG.stickerSuggestionMode"

    // MARK: Internal

    /// Telegram suggests from all sets by default.
    static var current: StickerSuggestionMode {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .all }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    var title: String {
        switch self {
        case .all: L10n.telegram("Stickers.SuggestAll")
        case .installed: L10n.telegram("Stickers.SuggestAdded")
        case .off: L10n.telegram("Stickers.SuggestNone")
        }
    }
}

// MARK: - StickerPackOrder

/// StickerSettings' dynamicPackOrder: a sticker sent from its pack in the keyboard moves the pack to the top.
enum StickerPackOrder {
    private static let defaultsKey = "BetterTG.dynamicStickerPackOrder"

    /// On by default, as in Telegram.
    static var isDynamic: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
}

// MARK: - InstalledStickerSetsViewController

/// InstalledStickerPacksController. Stickers: Trending Stickers, Archived Stickers and Emoji with their counts, Quick
/// Reaction, Suggest
/// Stickers by
/// Emoji, Large Emoji (TDLib's `disable_animated_emoji`), Dynamic Pack Order, then My Stickers with the @stickers note.
/// Emoji: Archived
/// Emoji and the custom emoji sets. A set opens its preview; Telegram's Delete swipe asks whether to archive or delete
/// it, with Undo; Edit selects sets to delete, archive or share and drags them into a new order.
final class InstalledStickerSetsViewController: SettingsListViewController, UITextViewDelegate {
    enum Mode {
        case stickers
        case emoji

        // MARK: Internal

        var stickerType: TDNativeStickerType {
            switch self {
            case .stickers: .stickerTypeRegular
            case .emoji: .stickerTypeCustomEmoji
            }
        }

        func matches(_ type: TDNativeStickerType) -> Bool {
            switch (self, type) {
            case (.emoji, .stickerTypeCustomEmoji),
                 (.stickers, .stickerTypeRegular): true
            default: false
            }
        }

        func countText(_ count: Int) -> String {
            L10n.telegramPlural(
                self == .stickers ? "StickerPack.StickerCount" : "StickerPack.EmojiCount",
                count: count,
                formattedCount: count.formatted(.number),
            )
        }
    }

    private let mode: Mode
    private var sets: [TDNativeStickerSetInfo]?
    private var archivedCount = 0
    private var trendingCount = 0
    private var emojiCount = 0
    private var largeEmoji = true
    private var loadTask: Task<Void, Never>?
    private var updatesCancellable: AnyCancellable?
    private var reactionCancellable: AnyCancellable?
    /// TDLib changed the sets while the user was editing; they reload on Done.
    private var needsReload = false
    /// The section of Suggest Stickers by Emoji, where its menu opens.
    private var suggestionSection: Int?

    /// My Stickers, which follows the other sections.
    private var packsSection: Int? {
        sets == nil ? nil : sections.count - 1
    }

    private var selectedSets: [TDNativeStickerSetInfo] {
        guard let sets, let packsSection else { return [] }
        let rows = Set((tableView.indexPathsForSelectedRows ?? []).filter { $0.section == packsSection }.map(\.row))
        return sets.enumerated().filter { rows.contains($0.offset) }.map(\.element)
    }

    init(mode: Mode) {
        self.mode = mode
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram(mode == .stickers ? "StickerPacksSettings.Title" : "EmojiPacksSettings.Title")
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.register(
            SettingsLinkFooterView.self,
            forHeaderFooterViewReuseIdentifier: SettingsLinkFooterView.reuseIdentifier,
        )
        updateNavigationItems()
        load()
        reactionCancellable = DefaultReactionType.shared
            .changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self, !tableView.isEditing else { return }
                reload()
            }
        let mode = mode
        let accountID = accountID
        updatesCancellable = NotificationCenter.default
            .publisher(for: .updateInstalledStickerSets)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, contextIsCurrent,
                      let update = TdScopedUpdate<TDNativeUpdateInstalledStickerSets>(notification: note),
                      update.source == TDLib.shared.activeUpdateSource, update.source.accountID == accountID,
                      // The sticker list counts the emoji sets too.
                      mode == .stickers || mode.matches(update.value.stickerType) else { return }
                if tableView.isEditing {
                    needsReload = true
                } else {
                    load()
                }
            }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if tableView.isEditing { setEditingSets(false) }
    }

    override func makeSections() -> [SettingsSection] {
        guard let sets else { return [] }
        var sections = [SettingsSection]()
        var shortcuts = [SettingsRow]()
        if trendingCount > 0 {
            var trending = SettingsRow(
                title: L10n.telegram("StickerPacksSettings.TrendingStickers"),
                symbol: "flame",
                accessory: .disclosure,
            ) { [weak self] in
                guard let self else { return }
                FeaturedStickersViewController.present(from: self)
            }
            trending.badge = trendingCount.formatted(.number)
            shortcuts.append(trending)
        }
        if archivedCount > 0 {
            shortcuts.append(SettingsRow(
                title: L10n.telegram(mode == .stickers
                    ? "StickerPacksSettings.ArchivedPacks"
                    : "StickersList.ArchivedEmojiItem"),
                detail: archivedCount.formatted(.number),
                symbol: "archivebox",
                accessory: .disclosure,
            ) { [weak self] in self?.openArchived() })
        }
        if mode == .stickers, emojiCount > 0 {
            shortcuts.append(SettingsRow(
                title: L10n.telegram("StickerPacksSettings.Emoji"),
                detail: emojiCount.formatted(.number),
                symbol: "face.smiling",
                accessory: .disclosure,
            ) { [weak self] in
                self?.navigationController?.pushViewController(
                    InstalledStickerSetsViewController(mode: .emoji),
                    animated: true,
                )
            })
        }
        if mode == .stickers {
            let reaction = DefaultReactionType.shared.type(for: client)
            let client = client
            shortcuts.append(SettingsRow(
                title: L10n.telegram("Settings.QuickReactionSetup.NavigationTitle"),
                symbol: "heart",
                accessory: .disclosure,
                action: { [weak self] in
                    self?.navigationController?.pushViewController(QuickReactionSetupViewController(), animated: true)
                },
                trailingView: SettingsTrailingView { QuickReactionIconView(type: reaction, client: client) },
            ))
        }
        if !shortcuts.isEmpty {
            sections.append(SettingsSection(rows: shortcuts))
        }
        suggestionSection = nil
        if mode == .stickers {
            suggestionSection = sections.count
            sections.append(SettingsSection(footer: L10n.telegram("StickerPacksSettings.DynamicOrderInfo"), rows: [
                SettingsRow(
                    title: L10n.telegram("Stickers.SuggestStickers"),
                    detail: StickerSuggestionMode.current.title,
                    accessory: .disclosure,
                ) { [weak self] in self?.presentSuggestionMenu() },
                SettingsRow(
                    title: L10n.telegram("Appearance.LargeEmoji"),
                    accessory: .toggle(isOn: largeEmoji) { [weak self] isOn in self?.setLargeEmoji(isOn) },
                ),
                SettingsRow(
                    title: L10n.telegram("StickerPacksSettings.DynamicOrder"),
                    accessory: .toggle(isOn: StickerPackOrder.isDynamic) { StickerPackOrder.isDynamic = $0 },
                ),
            ]))
        }
        let isEditing = isViewLoaded && tableView.isEditing
        var rows = [SettingsRow]()
        for set in sets {
            var row = SettingsRow(
                title: set.title,
                detail: mode.countText(set.size),
                style: .stickerSet(SettingsStickerSet(info: set)),
            )
            row.action = { [weak self] in self?.openSet(set) }
            if !isEditing {
                row.swipeAction = (
                    title: L10n.telegram("Common.Delete"),
                    handler: { [weak self] in self?.confirmRemoval(of: set) },
                )
            }
            rows.append(row)
        }
        let header = mode == .stickers ? L10n.telegram("StickerPacksSettings.MyStickers").uppercased() : nil
        sections.append(SettingsSection(header: header, rows: rows))
        return sections
    }

    // MARK: Table

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section == packsSection,
              let footer = tableView.dequeueReusableHeaderFooterView(
                  withIdentifier: SettingsLinkFooterView.reuseIdentifier,
              ) as? SettingsLinkFooterView
        else { return nil }
        let text = L10n.telegram(mode == .stickers ? "StickerPacksSettings.ManagingHelp" : "EmojiStickerSettings.Info")
        footer.configure(text: text, link: "https://t.me/stickers", delegate: self)
        return footer
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard tableView.isEditing else { return indexPath }
        return indexPath.section == packsSection ? indexPath : nil
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard tableView.isEditing else {
            super.tableView(tableView, didSelectRowAt: indexPath)
            return
        }
        updateToolbar()
    }

    override func tableView(_ tableView: UITableView, didDeselectRowAt _: IndexPath) {
        if tableView.isEditing { updateToolbar() }
    }

    override func tableView(_: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == packsSection
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        tableView.isEditing && indexPath.section == packsSection
    }

    override func tableView(
        _: UITableView,
        targetIndexPathForMoveFromRowAt source: IndexPath,
        toProposedIndexPath proposed: IndexPath,
    ) -> IndexPath {
        guard let packsSection, let sets else { return source }
        if proposed.section < packsSection { return IndexPath(row: 0, section: packsSection) }
        if proposed.section > packsSection { return IndexPath(row: sets.count - 1, section: packsSection) }
        return proposed
    }

    /// The new order goes to TDLib at once (reorderInstalledStickerSets).
    override func tableView(_: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        guard var sets, source != destination, sets.indices.contains(source.row) else { return }
        let set = sets.remove(at: source.row)
        sets.insert(set, at: min(destination.row, sets.count))
        self.sets = sets
        rebuildSections()
        let type = mode.stickerType
        let order = sets.map(\.id)
        perform { client in
            _ = try await client.send(TDNativeRequests.reorderInstalledStickerSets(
                stickerType: type,
                stickerSetIds: order,
            ))
        }
    }

    // MARK: UITextViewDelegate

    func textView(
        _: UITextView,
        primaryActionFor textItem: UITextItem,
        defaultAction _: UIAction,
    ) -> UIAction? {
        guard case .link(let url) = textItem.content else { return nil }
        return UIAction { [weak self] _ in
            TelegramLinkRouter.shared.open(url, from: self)
        }
    }

    // MARK: Private

    private func load() {
        guard contextIsCurrent else { return }
        loadTask?.cancel()
        let client = client
        let mode = mode
        loadTask = Task { [weak self] in
            let installed = try? await client.send(TDNativeRequests.getInstalledStickerSets(
                stickerType: mode.stickerType,
            ))
            let archived = try? await client.send(TDNativeRequests.getArchivedStickerSets(
                stickerType: mode.stickerType,
                offsetStickerSetId: 0,
                limit: 1,
            ))
            var emojiCount = 0
            var trendingCount = 0
            var largeEmoji = true
            if mode == .stickers {
                let trending = try? await client.send(TDNativeRequests.getTrendingStickerSets(
                    stickerType: .stickerTypeRegular,
                    offset: 0,
                    limit: 100,
                ))
                trendingCount = trending?.sets.count ?? 0
                let emoji = try? await client.send(TDNativeRequests.getInstalledStickerSets(
                    stickerType: .stickerTypeCustomEmoji,
                ))
                emojiCount = emoji?.sets.count ?? 0
                if case .optionValueBoolean(let disabled) = try? await client.getOption(
                    name: "disable_animated_emoji",
                ) {
                    largeEmoji = !disabled.value
                }
            }
            guard let self, !Task.isCancelled, contextIsCurrent, let installed else { return }
            sets = installed.sets
            archivedCount = archived?.totalCount ?? 0
            self.emojiCount = emojiCount
            self.trendingCount = trendingCount
            self.largeEmoji = largeEmoji
            reload()
            updateNavigationItems()
        }
    }

    private func openSet(_ set: TDNativeStickerSetInfo) {
        StickerPackPreviewViewController.present(setID: set.id, client: client, from: self, onSend: nil)
    }

    private func openArchived() {
        let controller = ArchivedStickerSetsViewController(mode: mode)
        controller.onChange = { [weak self] in self?.load() }
        navigationController?.pushViewController(controller, animated: true)
    }

    /// openSuggestOptions: All Sets, My Sets or None, the current one checked.
    private func presentSuggestionMenu() {
        guard let suggestionSection,
              let cell = tableView.cellForRow(at: IndexPath(row: 0, section: suggestionSection)) else { return }
        let current = StickerSuggestionMode.current
        let actions = StickerSuggestionMode.allCases.map { mode in
            TelegramContextMenuAction(
                title: mode.title,
                image: mode == current ? UIImage(systemName: "checkmark") : nil,
            ) { [weak self] in
                StickerSuggestionMode.current = mode
                self?.reload()
            }
        }
        presentTelegramContextMenu(sourceView: cell, actions: actions, presentationStyle: .menuOnly)
    }

    private func setLargeEmoji(_ isOn: Bool) {
        largeEmoji = isOn
        perform { client in
            _ = try await client.setOption(
                name: "disable_animated_emoji",
                value: .optionValueBoolean(TDNativeOptionValueBoolean(value: !isOn)),
            )
        } completion: {}
    }

    /// removePack's sheet: Telegram's note on archiving, Archive, Delete and Cancel.
    private func confirmRemoval(of set: TDNativeStickerSetInfo) {
        let sheet = UIAlertController(
            title: nil,
            message: L10n.telegram(mode == .stickers
                ? "StickerSettings.ContextInfo"
                : "StickerSettings.EmojiContextInfo"),
            preferredStyle: .actionSheet,
        )
        sheet.addAction(UIAlertAction(title: L10n.telegram("StickerSettings.ContextHide"), style: .default) {
            [weak self] _ in self?.remove(set, archive: true)
        })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Delete"), style: .destructive) { [weak self] _ in
            self?.remove(set, archive: false)
        })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(sheet, animated: true)
    }

    /// removeStickerPackInteractively, then Telegram's "Stickers Archived" or "Stickers Removed" with Undo, which
    /// installs the set again in its old place.
    private func remove(_ set: TDNativeStickerSetInfo, archive: Bool) {
        guard let order = sets?.map(\.id) else { return }
        let type = mode.stickerType
        let mode = mode
        perform { client in
            _ = try await client.send(TDNativeRequests.changeStickerSet(
                setId: set.id,
                isInstalled: false,
                isArchived: archive,
            ))
        } completion: { [weak self] in
            guard let self else { return }
            load()
            let title =
                switch (mode, archive) {
                case (.stickers, true): L10n.telegram("StickerPackActionInfo.ArchivedTitle")
                case (.stickers, false): L10n.telegram("StickerPackActionInfo.RemovedTitle")
                case (.emoji, true): L10n.telegram("EmojiPackActionInfo.ArchivedTitle")
                case (.emoji, false): L10n.telegram("EmojiPackActionInfo.RemovedTitle")
                }
            let text = L10n.telegram(
                mode == .stickers ? "StickerPackActionInfo.RemovedText" : "EmojiPackActionInfo.RemovedText",
                set.title,
            )
            TelegramUndoToast.show(
                title: title,
                text: text.withoutTelegramMarkup,
                in: navigationController?.view ?? view,
                bottomInset: 12,
            ) { [weak self] in
                self?.perform { client in
                    _ = try await client.send(TDNativeRequests.changeStickerSet(
                        setId: set.id,
                        isInstalled: true,
                        isArchived: false,
                    ))
                    _ = try? await client.send(TDNativeRequests.reorderInstalledStickerSets(
                        stickerType: type,
                        stickerSetIds: order,
                    ))
                } completion: { [weak self] in self?.load() }
            }
        }
    }

    // MARK: Editing

    /// Edit while there are sets; Done, in bold, while editing.
    private func updateNavigationItems() {
        guard isViewLoaded else { return }
        let editing = tableView.isEditing
        guard editing || sets?.isEmpty == false else {
            navigationItem.rightBarButtonItem = nil
            return
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram(editing ? "Common.Done" : "Common.Edit"),
            style: editing ? .prominent : .plain,
            target: self,
            action: editing ? #selector(doneTapped) : #selector(editTapped),
        )
    }

    @objc private func editTapped() {
        setEditingSets(true)
    }

    @objc private func doneTapped() {
        setEditingSets(false)
    }

    /// StickersToolbarItem under the list while editing: Delete, Archive and Share for the chosen sets.
    private func setEditingSets(_ editing: Bool) {
        tableView.setEditing(editing, animated: true)
        rebuildSections()
        updateNavigationItems()
        if editing {
            updateToolbar()
        }
        navigationController?.setToolbarHidden(!editing, animated: true)
        if !editing, needsReload {
            needsReload = false
            load()
        }
    }

    private func updateToolbar() {
        let hasSelection = !selectedSets.isEmpty
        let delete = UIBarButtonItem(
            title: L10n.telegram("StickerPacks.ActionDelete"),
            style: .plain,
            target: self,
            action: #selector(deleteSelected),
        )
        let archive = UIBarButtonItem(
            title: L10n.telegram("StickerPacks.ActionArchive"),
            style: .plain,
            target: self,
            action: #selector(archiveSelected),
        )
        let share = UIBarButtonItem(
            title: L10n.telegram("StickerPacks.ActionShare"),
            style: .plain,
            target: self,
            action: #selector(shareSelected),
        )
        for item in [delete, archive, share] {
            item.isEnabled = hasSelection
        }
        toolbarItems = [delete, .flexibleSpace(), archive, .flexibleSpace(), share]
    }

    @objc private func deleteSelected() {
        let chosen = selectedSets
        guard !chosen.isEmpty else { return }
        let title = L10n.telegramPlural(
            mode == .stickers
                ? "StickerPacks.DeleteStickerPacksConfirmation"
                : "StickerPacks.DeleteEmojiPacksConfirmation",
            count: chosen.count,
        )
        confirmBulk(title: title) { [weak self] in self?.removeSets(chosen, archive: false) }
    }

    @objc private func archiveSelected() {
        let chosen = selectedSets
        guard !chosen.isEmpty else { return }
        let title = L10n.telegramPlural("StickerPacks.ArchiveStickerPacksConfirmation", count: chosen.count)
        confirmBulk(title: title) { [weak self] in self?.removeSets(chosen, archive: true) }
    }

    /// Share: the chosen sets' t.me/addstickers links, one a line.
    @objc private func shareSelected() {
        let links = selectedSets.map { "https://t.me/addstickers/\($0.name)" }
        guard !links.isEmpty else { return }
        setEditingSets(false)
        let activity = UIActivityViewController(
            activityItems: [links.joined(separator: "\n")],
            applicationActivities: nil,
        )
        activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(activity, animated: true)
    }

    private func confirmBulk(title: String, perform action: @escaping () -> Void) {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: title, style: .destructive) { _ in action() })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = toolbarItems?.first
        present(sheet, animated: true)
    }

    /// removeStickerPacksInteractively for the chosen sets; editing ends at once, as in Telegram.
    private func removeSets(_ chosen: [TDNativeStickerSetInfo], archive: Bool) {
        setEditingSets(false)
        let ids = chosen.map(\.id)
        perform { client in
            for id in ids {
                _ = try await client.send(TDNativeRequests.changeStickerSet(
                    setId: id,
                    isInstalled: false,
                    isArchived: archive,
                ))
            }
        } completion: { [weak self] in self?.load() }
    }
}

// MARK: - ArchivedStickerSetsViewController

/// ArchivedStickerPacksController: Telegram's note on the 200-set limit over the archived sets, each with ADD (then
/// "Stickers Added") and a Delete swipe that drops it from the archive.
final class ArchivedStickerSetsViewController: SettingsListViewController {
    /// The installed list reloads its counts after a change here.
    var onChange: (() -> Void)?

    private let mode: InstalledStickerSetsViewController.Mode
    private var sets: [TDNativeStickerSetInfo]?
    /// ArchivedStickerPacksControllerState's removingPackIds: sets with a request in flight.
    private var busyIDs = Set<Int64>()
    private var loadTask: Task<Void, Never>?

    init(mode: InstalledStickerSetsViewController.Mode) {
        self.mode = mode
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram(mode == .stickers
            ? "StickerPacksSettings.ArchivedPacks"
            : "EmojiPacksSettings.ArchivedPacks")
        load()
    }

    override func makeSections() -> [SettingsSection] {
        guard let sets else { return [] }
        return [SettingsSection(
            header: L10n.telegram(mode == .stickers
                ? "StickerPacksSettings.ArchivedPacks.Info"
                : "EmojiPacksSettings.ArchivedPacks.Info"),
            rows: sets.map { set in
                let isBusy = busyIDs.contains(set.id)
                return SettingsRow(
                    title: set.title,
                    detail: mode.countText(set.size),
                    style: .stickerSet(SettingsStickerSet(
                        info: set,
                        add: isBusy
                            ? nil
                            : { [weak self] in
                                self?.change(set, install: true)
                            },
                    )),
                    isEnabled: !isBusy,
                    action: { [weak self] in
                        guard let self else { return }
                        StickerPackPreviewViewController.present(setID: set.id, client: client, from: self, onSend: nil)
                    },
                    swipeAction: (
                        title: L10n.telegram("Common.Delete"),
                        handler: { [weak self] in self?.change(set, install: false) },
                    ),
                )
            },
        )]
    }

    /// TDLib returns the archive a page at a time; Telegram shows it whole.
    private func load() {
        guard contextIsCurrent else { return }
        let client = client
        let type = mode.stickerType
        loadTask = Task { [weak self] in
            var loaded = [TDNativeStickerSetInfo]()
            var total = Int.max
            while loaded.count < total {
                guard let page = try? await client.send(TDNativeRequests.getArchivedStickerSets(
                    stickerType: type,
                    offsetStickerSetId: loaded.last?.id ?? 0,
                    limit: 100,
                )), !page.sets.isEmpty else { break }
                loaded += page.sets
                total = page.totalCount
            }
            guard let self, !Task.isCancelled, contextIsCurrent else { return }
            sets = loaded
            reload()
        }
    }

    /// addPack installs the set, which leaves the archive with Telegram's "Stickers Added"; removeArchivedStickerPack
    /// drops it from the archive without installing it. The row stays disabled while its request runs.
    private func change(_ set: TDNativeStickerSetInfo, install: Bool) {
        guard contextIsCurrent, busyIDs.insert(set.id).inserted else { return }
        reload()
        let client = client
        let mode = mode
        Task { [weak self] in
            let succeeded = await (try? client.send(TDNativeRequests.changeStickerSet(
                setId: set.id,
                isInstalled: install,
                isArchived: false,
            ))) != nil
            guard let self, contextIsCurrent else { return }
            busyIDs.remove(set.id)
            guard succeeded else {
                reload()
                presentChatListActionFailure()
                return
            }
            sets?.removeAll { $0.id == set.id }
            reload()
            onChange?()
            guard install else { return }
            TelegramUndoToast.show(
                title: L10n.telegram(mode == .stickers
                    ? "StickerPackActionInfo.AddedTitle"
                    : "EmojiPackActionInfo.AddedTitle"),
                text: L10n.telegram(
                    mode == .stickers ? "StickerPackActionInfo.AddedText" : "EmojiPackActionInfo.AddedText",
                    set.title,
                )
                .withoutTelegramMarkup,
                in: navigationController?.view ?? view,
                bottomInset: 12,
                undo: nil,
            )
        }
    }
}

// MARK: - SettingsStickerSetCell

/// ItemListStickerPackItem: the set's 34 pt thumbnail 15 pt from the left, its title in 15 pt bold over the count in
/// 14 pt, 65 pt from the left and 11 pt from the top and bottom, and an archived set's 28 pt ADD on the right.
final class SettingsStickerSetCell: UITableViewCell {
    static let reuseIdentifier = "SettingsStickerSetCell"

    private let thumbnailView = CustomEmojiInlineView()
    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let addButton = UIButton(configuration: .filled())
    private var add: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        showsReorderControl = true
        // ItemListStickerPackItem's playAnimatedStickers follows Sticker Animations.
        thumbnailView.energySaving = EnergySavingRole(item: .loopStickers, whenOff: .still)
        thumbnailView.isUserInteractionEnabled = false
        titleLabel.font = .boldSystemFont(ofSize: 15)
        countLabel.font = .systemFont(ofSize: 14)
        countLabel.textColor = .secondaryLabel
        addButton.configuration?.cornerStyle = .capsule
        addButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        addButton.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = .systemFont(ofSize: 13, weight: .semibold)
            return attributes
        }
        addButton.setContentHuggingPriority(.required, for: .horizontal)
        addButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        addButton.addAction(UIAction { [weak self] _ in self?.add?() }, for: .touchUpInside)

        let labels = UIStackView(arrangedSubviews: [titleLabel, countLabel])
        labels.axis = .vertical
        labels.spacing = 2
        let row = UIStackView(arrangedSubviews: [labels, addButton])
        row.alignment = .center
        row.spacing = 8
        for subview in [thumbnailView, row] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            thumbnailView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 34),
            thumbnailView.heightAnchor.constraint(equalToConstant: 34),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 65),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -11),
            addButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailView.prepareForReuse()
        add = nil
    }

    /// The set's thumbnail, else its first sticker, as ItemListStickerPackItem picks.
    func configure(set: SettingsStickerSet, detail: String?, client: TDLibClient) {
        titleLabel.text = set.info.title
        countLabel.text = detail
        add = set.add
        addButton.isHidden = set.add == nil
        addButton.configuration?.title = L10n.telegram("Stickers.Install")
        // ItemListStickerPackItem paints a template set's thumbnail in the primary text colour.
        thumbnailView.templateColor = .label
        if let thumbnail = set.info.thumbnail,
           thumbnailView.configure(setThumbnail: thumbnail, client: client, isTemplate: set.info.needsRepainting)
        {
            // The set's own thumbnail.
        } else if let cover = set.info.covers.first {
            thumbnailView.configure(sticker: cover, client: client)
        } else {
            thumbnailView.prepareForReuse()
        }
        accessibilityLabel = [set.info.title, detail].compactMap(\.self).joined(separator: ", ")
    }

    func setPlaybackVisible(_ visible: Bool) {
        thumbnailView.setPlaybackVisible(visible)
    }
}

// MARK: - SettingsLinkFooterView

/// ItemListTextItem with `.markdown` text: a footer whose first @mention opens `link`.
final class SettingsLinkFooterView: UITableViewHeaderFooterView {
    static let reuseIdentifier = "SettingsLinkFooterView"

    private let textView = UITextView()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            textView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -7),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, link: String, delegate: UITextViewDelegate) {
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .footnote),
            .foregroundColor: UIColor.secondaryLabel,
        ])
        if let mention = text.firstMatch(of: /@\w+/), let url = URL(string: link) {
            attributed.addAttribute(.link, value: url, range: NSRange(mention.range, in: text))
        }
        textView.attributedText = attributed
        textView.linkTextAttributes = [.foregroundColor: UIColor.tintColor]
        textView.delegate = delegate
    }
}
