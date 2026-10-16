// MusicPlayerViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - MusicPlayerViewController

/// Telegram's music player (OverlayAudioPlayerController), opened from the playback header while music plays: the
/// chat's tracks (ChatHistoryListNode's music list) above the playback controls (OverlayAudioPlayerControlsNode). The
/// sheet opens with three and a half tracks over the controls and grows as the list is dragged up; a chat with a
/// single track shows the controls alone.
final class MusicPlayerViewController: UIViewController {
    // MARK: Private

    /// The list's inset leaves room for three and a half 62 pt rows above the controls (containerLayoutUpdated).
    private static let rowHeight = CGFloat(62)
    private static let visibleRows = CGFloat(3.5)
    /// effectiveHeaderHeight: the strip over the list that holds the grabber.
    private static let headerHeight = CGFloat(38)
    private static let pageSize = 50
    private static let compactDetent = UISheetPresentationController.Detent.Identifier(
        rawValue: "BetterTG.musicPlayer.compact",
    )

    private let accountID: UUID
    private let initialMessageID: Int64
    private var chatID: Int64
    /// The playing track while it's this account's music; nil while the playlist loads its next track.
    private var currentItem: Media.NowPlaying?
    /// The chat's tracks loaded so far, by message ID.
    private var tracks = [Int64: Message]()
    private var rows = [Message]()
    /// OverlayAudioPlayerControllerNode's currentIsReversed: oldest tracks first outside the regular order.
    private var isReversed: Bool
    /// ChatHistoryEntriesForView shows no music playlist for a chat's only track.
    private var hasList = true
    private var canLoadOlder = true
    private var canLoadNewer = true
    private var loadedAnchor: Int64?
    private var listGeneration = 0
    private var loadTask: Task<Void, Never>?
    private var olderTask: Task<Void, Never>?
    private var newerTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let separator = UIView()
    private let controlsView = MusicPlayerControlsView()
    private let closeButton = UIButton(type: .close)
    private var albumArtOverlay: UIVisualEffectView?

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private init(accountID: UUID, item: Media.NowPlaying) {
        self.accountID = accountID
        self.chatID = item.chatID
        self.initialMessageID = item.messageID
        self.isReversed = Media.shared.musicSettings.order != .regular
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = sheetDetents()
            sheet.selectedDetentIdentifier = Self.compactDetent
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureList()
        configureControls()
        configureCloseButton()
        loadTracks(around: initialMessageID)
        bind()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        stackRowsFromBottom()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed else { return }
        cancelLoading()
    }

    // MARK: Internal

    /// MediaPlaybackHeaderPanelComponent's tapAction for music: the player opens over the current screen at the
    /// playing track.
    static func present(from presenter: UIViewController) {
        guard presenter.presentedViewController == nil, let item = Media.shared.nowPlaying, item.isMusic,
              let accountID = item.accountID, TDLib.shared.activeAccountID == accountID else { return }
        presenter.view.window?.endEditing(true)
        presenter.present(MusicPlayerViewController(accountID: accountID, item: item), animated: true)
    }

    /// The compact detent fits the header, three and a half tracks and the controls; the large one shows more of the
    /// list.
    private func sheetDetents() -> [UISheetPresentationController.Detent] {
        // The 1 pt is the separator over the controls.
        let listHeight = (hasList ? Self.rowHeight * Self.visibleRows : 0) + 1
        let height = Self.headerHeight + listHeight + MusicPlayerControlsView.panelHeight
        let compact = UISheetPresentationController.Detent.custom(identifier: Self.compactDetent) { context in
            min(height, context.maximumDetentValue)
        }
        return hasList ? [compact, .large()] : [compact]
    }

    private func configureList() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 65, bottom: 0, right: 0)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = Self.rowHeight
        tableView.tableFooterView = UIView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(MusicPlayerTrackCell.self, forCellReuseIdentifier: MusicPlayerTrackCell.reuseIdentifier)
        view.addSubview(tableView)
        setContentScrollView(tableView, for: [.top, .bottom])

        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        view.addSubview(separator)
    }

    private func configureControls() {
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsView)
        controlsView.onTogglePlayback = { Media.shared.togglePlayback() }
        controlsView.onPrevious = { Media.shared.playPreviousTrack() }
        controlsView.onNext = { Media.shared.playNextTrack() }
        controlsView.onRate = { Media.shared.cyclePlaybackRate() }
        controlsView.onSeek = { Media.shared.seek(to: $0) }
        controlsView.onOrder = {
            VoicePlaylistContinuation.shared.setMusicOrder(Media.shared.musicSettings.order.following)
        }
        controlsView.onLooping = {
            VoicePlaylistContinuation.shared.setMusicLooping(Media.shared.musicSettings.looping.following)
        }
        controlsView.onAlbumArt = { [weak self] in self?.showAlbumArt() }

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.headerHeight),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: separator.topAnchor),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / max(view.traitCollection.displayScale, 1)),
            separator.bottomAnchor.constraint(equalTo: controlsView.topAnchor),
            controlsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsView.heightAnchor.constraint(equalToConstant: MusicPlayerControlsView.panelHeight),
            controlsView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private func configureCloseButton() {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.accessibilityLabel = L10n.telegram("Common.Close")
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            closeButton.centerYAnchor.constraint(equalTo: view.topAnchor, constant: Self.headerHeight / 2 + 2),
        ])
    }

    /// The controls follow SharedMediaPlayer's state; the list marks the playing and the downloading track.
    private func bind() {
        let media = Media.shared
        Publishers.CombineLatest4(media.$nowPlaying, media.$isPlaying, media.$playbackPosition, media.$playbackRate)
            .combineLatest(media.$nowPlayingDisplay, media.$musicSettings, media.$albumArtImage)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshPlayback() }
            .store(in: &cancellables)
        VoicePlaylistContinuation.shared
            .$loadingMusic
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshRowStates() }
            .store(in: &cancellables)
        // The player belongs to the account it opened in; Media stops that account's music when another one opens.
        TDLib.shared
            .activeClientChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in
                guard let self, source.accountID != accountID else { return }
                dismiss(animated: true)
            }
            .store(in: &cancellables)
    }

    /// Reads the playback state after Media published it. Without a track (the playlist loading its next one, or
    /// its end), Telegram disables the playback buttons and keeps the player open.
    private func refreshPlayback() {
        let media = Media.shared
        let item = media.nowPlaying.flatMap { $0.isMusic && $0.accountID == accountID ? $0 : nil }
        if item != currentItem {
            // requestAlbumArtDisplay(nil): another track puts the enlarged cover away.
            hideAlbumArt()
            currentItem = item
            if let item { follow(item) }
        }
        let reversed = media.musicSettings.order != .regular
        if reversed != isReversed {
            isReversed = reversed
            // updateOrder rebuilds the list at the playing track (transitionToUpdatedHistoryNode).
            applyRows(scrollingTo: currentItem?.messageID)
        }
        let display: Media.NowPlayingDisplay? = item.flatMap { item in
            if let display = media.nowPlayingDisplay, display.item == item { return display }
            guard let message = tracks[item.messageID], case .messageAudio(let content) = message.content
            else { return nil }
            return Media.NowPlayingDisplay.music(content.audio, item: item)
        }
        controlsView.configure(MusicPlayerControlsView.Content(
            title: display?.title ?? "",
            performer: display?.subtitle ?? "",
            isPlaying: item != nil && media.isPlaying,
            position: media.playbackPosition,
            duration: media.playbackDuration,
            rate: media.playbackRate,
            isLong: display?.showsRate ?? false,
            settings: media.musicSettings,
            isEnabled: item != nil,
        ))
        let albumArt = item == nil ? nil : media.albumArtImage
        controlsView.setAlbumArt(albumArt)
        if albumArt == nil { hideAlbumArt() }
        refreshRowStates()
    }

    /// A track the playlist moved to: the list loads around it unless it already holds it; another chat's track
    /// starts the list over.
    private func follow(_ item: Media.NowPlaying) {
        if item.chatID != chatID {
            chatID = item.chatID
            tracks = [:]
            rows = []
            tableView.reloadData()
            loadTracks(around: item.messageID)
        } else if tracks[item.messageID] == nil, loadTask == nil, loadedAnchor != item.messageID {
            loadTracks(around: item.messageID)
        }
    }

    /// The chat's music around a track, as the history list opens at the playing message: half a page on either side
    /// of it.
    private func loadTracks(around messageID: Int64) {
        cancelLoading()
        listGeneration += 1
        loadedAnchor = messageID
        guard TDLib.shared.activeAccountID == accountID else { return }
        let client = TDLib.shared.activeClient
        let chat = chatID
        let generation = listGeneration
        let pageSize = Self.pageSize
        loadTask = Task { [weak self] in
            let found = try? await client.searchChatMessages(
                chatId: chat,
                filter: .searchMessagesFilterAudio,
                fromMessageId: messageID,
                limit: pageSize,
                offset: -(pageSize / 2),
                query: "",
                senderId: nil,
                topicId: nil,
            )
            var messages = found?.messages ?? []
            if !messages.contains(where: { $0.id == messageID }),
               let current = try? await client.getMessage(chatId: chat, messageId: messageID)
            {
                messages.append(current)
            }
            guard let self, !Task.isCancelled, listGeneration == generation else { return }
            loadTask = nil
            tracks = [:]
            merge(messages)
            canLoadOlder = (found?.nextFromMessageId ?? 0) != 0
            canLoadNewer = found != nil
            applyRows(scrollingTo: currentItem?.messageID ?? messageID)
        }
    }

    private func loadOlderTracks() {
        guard canLoadOlder, loadTask == nil, olderTask == nil, let oldestID = tracks.keys.min(),
              TDLib.shared.activeAccountID == accountID else { return }
        let client = TDLib.shared.activeClient
        let chat = chatID
        let generation = listGeneration
        let pageSize = Self.pageSize
        olderTask = Task { [weak self] in
            let found = try? await client.searchChatMessages(
                chatId: chat,
                filter: .searchMessagesFilterAudio,
                fromMessageId: oldestID,
                limit: pageSize,
                offset: 0,
                query: "",
                senderId: nil,
                topicId: nil,
            )
            guard let self, !Task.isCancelled, listGeneration == generation else { return }
            olderTask = nil
            var added = 0
            if let found { added = merge(found.messages) }
            canLoadOlder = added > 0 && (found?.nextFromMessageId ?? 0) != 0
            if added > 0 { applyRows() }
        }
    }

    private func loadNewerTracks() {
        guard canLoadNewer, loadTask == nil, newerTask == nil, let newestID = tracks.keys.max(),
              TDLib.shared.activeAccountID == accountID else { return }
        let client = TDLib.shared.activeClient
        let chat = chatID
        let generation = listGeneration
        let pageSize = Self.pageSize
        newerTask = Task { [weak self] in
            let found = try? await client.searchChatMessages(
                chatId: chat,
                filter: .searchMessagesFilterAudio,
                fromMessageId: newestID,
                limit: pageSize,
                offset: -(pageSize - 1),
                query: "",
                senderId: nil,
                topicId: nil,
            )
            guard let self, !Task.isCancelled, listGeneration == generation else { return }
            newerTask = nil
            var added = 0
            if let found { added = merge(found.messages) }
            canLoadNewer = added > 0
            if added > 0 { applyRows() }
        }
    }

    private func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
        olderTask?.cancel()
        olderTask = nil
        newerTask?.cancel()
        newerTask = nil
    }

    /// Adds the chat's music tracks among `messages`; returns how many were new.
    @discardableResult private func merge(_ messages: [Message]) -> Int {
        var added = 0
        for message in messages where message.chatId == chatID {
            guard case .messageAudio = message.content else { continue }
            if tracks.updateValue(message, forKey: message.id) == nil { added += 1 }
        }
        return added
    }

    /// The list's order: newest tracks first, an album's tracks first to last within it (reverseGroups), in the
    /// regular order; oldest first otherwise.
    private func orderedRows() -> [Message] {
        guard hasList else { return [] }
        let newestFirst = tracks.values.sorted { $0.id > $1.id }
        if isReversed { return Array(newestFirst.reversed()) }
        var ordered = [Message]()
        var album = [Message]()
        for message in newestFirst {
            if let last = album.last, message.mediaAlbumId != 0, message.mediaAlbumId == last.mediaAlbumId {
                album.append(message)
            } else {
                ordered += album.reversed()
                album = [message]
            }
        }
        ordered += album.reversed()
        return ordered
    }

    /// Reloads the list. `messageID` centers that track; otherwise the top visible row stays where it was while
    /// pages load above it.
    private func applyRows(scrollingTo messageID: Int64? = nil) {
        let anchor = messageID == nil ? visibleAnchor() : nil
        updateListPresence()
        rows = orderedRows()
        tableView.reloadData()
        tableView.layoutIfNeeded()
        stackRowsFromBottom()
        if let messageID, let row = rows.firstIndex(where: { $0.id == messageID }) {
            tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .middle, animated: false)
        } else if let anchor, let row = rows.firstIndex(where: { $0.id == anchor.id }) {
            let rect = tableView.rectForRow(at: IndexPath(row: row, section: 0))
            let minimum = -tableView.contentInset.top
            let maximum = max(minimum, tableView.contentSize.height - tableView.bounds.height)
            tableView.contentOffset.y = min(max(rect.minY - anchor.offset, minimum), maximum)
        }
    }

    private func visibleAnchor() -> (id: Int64, offset: CGFloat)? {
        guard let path = tableView.indexPathsForVisibleRows?.first, path.row < rows.count else { return nil }
        return (rows[path.row].id, tableView.rectForRow(at: path).minY - tableView.contentOffset.y)
    }

    /// A chat's only track leaves the list out and the sheet holds the controls alone.
    private func updateListPresence() {
        let present = tracks.count > 1
        guard present != hasList else { return }
        hasList = present
        tableView.isHidden = !present
        separator.isHidden = !present
        guard let sheet = sheetPresentationController else { return }
        sheet.animateChanges {
            sheet.detents = sheetDetents()
            if !present { sheet.selectedDetentIdentifier = Self.compactDetent }
        }
    }

    /// ChatHistoryListNode's stackFromBottom: a list shorter than its space sits against the controls.
    private func stackRowsFromBottom() {
        let top = max(0, tableView.bounds.height - tableView.contentSize.height)
        guard abs(tableView.contentInset.top - top) > 0.5 else { return }
        tableView.contentInset.top = top
        if top > 0 { tableView.contentOffset.y = -top }
    }

    private func refreshRowStates() {
        for path in tableView.indexPathsForVisibleRows ?? [] where path.row < rows.count {
            guard let cell = tableView.cellForRow(at: path) as? MusicPlayerTrackCell else { continue }
            cell.setState(rowState(for: rows[path.row]))
        }
    }

    private func rowState(for message: Message) -> MusicPlayerTrackCell.State {
        if let loading = VoicePlaylistContinuation.shared.loadingMusic, loading.accountID == accountID,
           loading.chatID == message.chatId, loading.messageID == message.id
        {
            return .loading
        }
        guard let currentItem, currentItem.chatID == message.chatId, currentItem.messageID == message.id else {
            return .idle
        }
        return Media.shared.isPlaying ? .playing : .paused
    }

    /// openChatMessage from the list: the playing track pauses or resumes; another one plays and the playlist goes
    /// on from it.
    private func playTrack(_ message: Message) {
        if let currentItem, currentItem.chatID == message.chatId, currentItem.messageID == message.id {
            Media.shared.togglePlayback()
            return
        }
        guard TDLib.shared.activeAccountID == accountID else { return }
        VoicePlaylistContinuation.shared.playMusic(message, accountID: accountID, client: TDLib.shared.activeClient)
    }

    /// The album art display (albumArtTap): the cover grows from the controls to at most 360 pt over a blur, and a
    /// tap puts it back.
    private func showAlbumArt() {
        let source = controlsView.albumArtView
        guard albumArtOverlay == nil, let image = source.image else { return }
        let overlay = UIVisualEffectView(effect: nil)
        overlay.frame = view.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.isAccessibilityElement = true
        overlay.accessibilityLabel = L10n.betterTG("Accessibility.MusicAlbumArt")
        overlay.accessibilityTraits = [.image, .button]
        overlay.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(albumArtOverlayTapped)))
        view.addSubview(overlay)
        albumArtOverlay = overlay

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerCurve = .continuous
        imageView.layer.cornerRadius = 10
        imageView.autoresizingMask = [
            .flexibleLeftMargin,
            .flexibleRightMargin,
            .flexibleTopMargin,
            .flexibleBottomMargin,
        ]
        imageView.frame = source.convert(source.bounds, to: view)
        overlay.contentView.addSubview(imageView)
        source.alpha = 0

        let side = min(360, view.bounds.width - 32, view.bounds.height - 32)
        let target = CGRect(
            x: floor((view.bounds.width - side) / 2),
            y: floor((view.bounds.height - side) / 2),
            width: side,
            height: side,
        )
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        UIView.animate(
            withDuration: reduceMotion ? 0 : 0.4,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState],
        ) {
            imageView.frame = target
            imageView.layer.cornerRadius = 4
        }
        UIView.animate(withDuration: reduceMotion ? 0 : 0.2) {
            overlay.effect = UIBlurEffect(style: .systemMaterial)
        }
        UIAccessibility.post(notification: .screenChanged, argument: overlay)
    }

    private func hideAlbumArt() {
        guard let overlay = albumArtOverlay else { return }
        albumArtOverlay = nil
        controlsView.albumArtView.alpha = 1
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.2) {
            overlay.effect = nil
            overlay.contentView.alpha = 0
        } completion: { _ in
            overlay.removeFromSuperview()
        }
        UIAccessibility.post(notification: .screenChanged, argument: controlsView.albumArtView)
    }

    @objc private func albumArtOverlayTapped() {
        hideAlbumArt()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}

// MARK: UITableViewDataSource, UITableViewDelegate

extension MusicPlayerViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: MusicPlayerTrackCell.reuseIdentifier, for: indexPath)
        guard let trackCell = cell as? MusicPlayerTrackCell, indexPath.row < rows.count else { return cell }
        let message = rows[indexPath.row]
        trackCell.configure(message: message, accountID: accountID, state: rowState(for: message))
        return trackCell
    }

    /// The list pages in more of the chat's tracks near either end: newer ones at the top in the regular order, older
    /// ones at the top otherwise.
    func tableView(_: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row < 5 {
            if isReversed { loadOlderTracks() } else { loadNewerTracks() }
        }
        if indexPath.row >= rows.count - 5 {
            if isReversed { loadNewerTracks() } else { loadOlderTracks() }
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < rows.count else { return }
        playTrack(rows[indexPath.row])
    }
}

// MARK: - MusicPlayerTrackCell

/// ListMessageFileItemNode's music row: the round album art (the accent color without one) with the play state on it,
/// then the title over the duration and performer, or the file size without a performer.
private final class MusicPlayerTrackCell: UITableViewCell {
    enum State {
        case idle
        case playing
        case paused
        case loading
    }

    static let reuseIdentifier = "MusicPlayerTrackCell"

    private let iconView = UIView()
    private let artView = TDImageLoadingView()
    private let dimView = UIView()
    private let statusView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private var state: State?
    private var title = ""
    private var detail = ""

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.backgroundColor = .systemBlue
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 20
        iconView.isUserInteractionEnabled = false
        contentView.addSubview(iconView)

        artView.translatesAutoresizingMaskIntoConstraints = false
        artView.contentMode = .scaleAspectFill
        artView.clipsToBounds = true
        // playerAlbumArt's overlayColor darkens a cover under the play state.
        artView.onFullImage = { [weak self] in self?.dimView.isHidden = false }
        iconView.addSubview(artView)
        dimView.translatesAutoresizingMaskIntoConstraints = false
        dimView.backgroundColor = UIColor(white: 0, alpha: 0.3)
        dimView.isHidden = true
        iconView.addSubview(dimView)
        statusView.translatesAutoresizingMaskIntoConstraints = false
        statusView.tintColor = .white
        iconView.addSubview(statusView)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .white
        spinner.hidesWhenStopped = true
        iconView.addSubview(spinner)

        // ListMessageFileItemNode: the title in semibold 16, the description in regular 14.
        titleLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 16, weight: .semibold))
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingTail
        descriptionLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 14))
        descriptionLabel.adjustsFontForContentSizeCategory = true
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.lineBreakMode = .byTruncatingTail
        let labels = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel])
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.axis = .vertical
        labels.spacing = 2
        contentView.addSubview(labels)

        let minimumHeight = contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 58)
        minimumHeight.priority = UILayoutPriority(999)
        var constraints = [
            minimumHeight,
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),
            statusView.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
            statusView.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            labels.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 65),
            labels.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            labels.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 9),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -9),
        ]
        for overlay in [artView, dimView] as [UIView] {
            constraints += [
                overlay.leadingAnchor.constraint(equalTo: iconView.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: iconView.trailingAnchor),
                overlay.topAnchor.constraint(equalTo: iconView.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: iconView.bottomAnchor),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        isAccessibilityElement = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artView.cancel()
        artView.image = nil
        dimView.isHidden = true
        state = nil
    }

    func configure(message: Message, accountID: UUID, state: State) {
        artView.cancel()
        artView.image = nil
        dimView.isHidden = true
        self.state = nil
        guard case .messageAudio(let content) = message.content else { return }
        let audio = content.audio
        let trackTitle = audio.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let performer = audio.performer.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = audio.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let size = max(audio.audio.size, audio.audio.expectedSize)
        title =
            if !trackTitle.isEmpty {
                trackTitle
            } else if !fileName.isEmpty {
                fileName
            } else {
                L10n.telegram("MediaPlayer.UnknownTrack")
            }
        detail =
            if !performer.isEmpty {
                "\(MusicPlayerControlsView.timeString(seconds: audio.duration)) • \(performer)"
            } else if size > 0 {
                ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            } else {
                ""
            }
        titleLabel.text = title
        descriptionLabel.text = detail.isEmpty ? " " : detail
        accessibilityLabel = detail.isEmpty ? title : "\(title), \(detail)"
        // playerAlbumArt's thumbnail: the cover inside the file, then an external one except for .ogg files.
        let externalCover = fileName.lowercased().hasSuffix(".ogg")
            ? nil
            : audio.externalAlbumCovers.min { $0.width * $0.height < $1.width * $1.height }
        if let cover = audio.albumCoverThumbnail ?? externalCover {
            dimView.isHidden = audio.albumCoverMinithumbnail == nil
            artView.load(
                file: cover.file,
                placeholderData: audio.albumCoverMinithumbnail?.data,
                maximumPixelSize: 120,
                accountID: accountID,
                client: TDLib.shared.activeClient,
            )
        }
        setState(state)
    }

    /// ListMessageFileItemNode's icon status: pause while the track plays, play otherwise, progress while it loads.
    func setState(_ state: State) {
        guard state != self.state else { return }
        self.state = state
        if state == .loading {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
        statusView.isHidden = state == .loading
        statusView.image = UIImage(
            systemName: state == .playing ? "pause.fill" : "play.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold),
        )
        accessibilityTraits = state == .idle ? .button : [.button, .selected]
    }
}
