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
    /// effectiveHeaderHeight: the strip over the list that holds the grabber, and a profile playlist's title too.
    private static let chatHeaderHeight = CGFloat(38)
    private static let profileHeaderHeight = CGFloat(78)
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
    private var rows = [TrackRow]()
    /// The list is a user's profile music (Telegram's `.savedMusic` playlist), whose ID `chatID` holds.
    private var isProfile: Bool
    private let headerHeight: CGFloat
    private let titleLabel = UILabel()
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
    /// The Add to Profile or Remove from Profile button under the controls.
    private let profileButton = UIButton(configuration: .filled())
    private var controlsToSafeArea: NSLayoutConstraint!
    private var controlsToProfileButton: NSLayoutConstraint!
    /// isProfileAudio's answers by file ID.
    private var savedFiles = [Int: Bool]()
    private var savedChecks = Set<Int>()
    /// The playing track's place in the account's profile music; nil hides the button.
    private var isSaved: Bool?
    private var albumArtOverlay: UIVisualEffectView?

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private init(accountID: UUID, item: Media.NowPlaying) {
        self.accountID = accountID
        self.chatID = item.chatID
        self.initialMessageID = item.messageID
        self.isReversed = Media.shared.musicSettings.order != .regular
        self.isProfile = item.isProfileAudio
        self.headerHeight = item.isProfileAudio ? Self.profileHeaderHeight : Self.chatHeaderHeight
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
        configureTitle()
        if isProfile {
            applyRows(scrollingTo: initialMessageID)
        } else {
            loadTracks(around: initialMessageID)
        }
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

    /// PeerInfoScreen's displaySavedMusic: the profile's playlist opens at `item`, which may still be downloading.
    static func presentProfileMusic(from presenter: UIViewController, item: Media.NowPlaying) {
        guard presenter.presentedViewController == nil, let accountID = item.accountID,
              TDLib.shared.activeAccountID == accountID else { return }
        presenter.present(MusicPlayerViewController(accountID: accountID, item: item), animated: true)
    }

    /// The compact detent fits the header, three and a half tracks and the controls; the large one shows more of the
    /// list.
    private func sheetDetents() -> [UISheetPresentationController.Detent] {
        // The 1 pt is the separator over the controls.
        let listHeight = (hasList ? Self.rowHeight * Self.visibleRows : 0) + 1
        // heightForLayout adds the 52 pt profile button with its insets while it shows.
        let buttonHeight: CGFloat = isSaved == nil ? 0 : 52 + 16
        let height = headerHeight + listHeight + MusicPlayerControlsView.panelHeight + buttonHeight
        let compact = UISheetPresentationController.Detent.custom(identifier: Self.compactDetent) { context in
            min(height, context.maximumDetentValue)
        }
        return hasList ? [compact, .large()] : [compact]
    }

    private func configureList() {
        tableView.addGestureRecognizer(UILongPressGestureRecognizer(
            target: self,
            action: #selector(rowLongPressed(_:)),
        ))
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
        // OverlayAudioPlayerControlsNode cycles without a tooltip; its menu shows one.
        controlsView.onRate = { Media.shared.cyclePlaybackRate() }
        controlsView.onRateMenu = { [weak self] source, gesture in
            guard let self else { return }
            AudioPlaybackRateMenu.present(from: self, sourceView: source, gesture: gesture) { [weak self] text in
                guard let self else { return }
                TelegramUndoToast.show(text: text, in: view, bottomInset: 8, undo: nil)
            }
        }
        controlsView.onSeek = { Media.shared.seek(to: $0) }
        controlsView.onOrder = {
            VoicePlaylistContinuation.shared.setMusicOrder(Media.shared.musicSettings.order.following)
        }
        controlsView.onLooping = {
            VoicePlaylistContinuation.shared.setMusicLooping(Media.shared.musicSettings.looping.following)
        }
        controlsView.onAlbumArt = { [weak self] in self?.showAlbumArt() }

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor, constant: headerHeight),
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
        ])
        configureProfileButton()
    }

    /// OverlayAudioPlayerControlsNode's profileAudio button: a 52 pt glass capsule 30 pt from the sides.
    private func configureProfileButton() {
        profileButton.translatesAutoresizingMaskIntoConstraints = false
        profileButton.isHidden = true
        profileButton.configuration?.cornerStyle = .capsule
        profileButton.configuration?.imagePadding = 8
        profileButton.addTarget(self, action: #selector(profileButtonTapped), for: .touchUpInside)
        view.addSubview(profileButton)
        controlsToSafeArea = controlsView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        controlsToProfileButton = controlsView.bottomAnchor.constraint(equalTo: profileButton.topAnchor, constant: -8)
        NSLayoutConstraint.activate([
            controlsToSafeArea,
            profileButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 30),
            profileButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -30),
            profileButton.heightAnchor.constraint(equalToConstant: 52),
            profileButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
    }

    /// The playing track's audio, and its message for a chat's track.
    private func currentAudio() -> (audio: Audio, message: Message?)? {
        guard let currentItem else { return nil }
        if currentItem.isProfileAudio {
            return ProfileMusicPlaylist.shared.audio(for: currentItem).map { ($0, nil) }
        }
        guard let message = tracks[currentItem.messageID], case .messageAudio(let content) = message.content
        else { return nil }
        return (content.audio, message)
    }

    /// The node's isSaved: none for a protected chat's track; the account's own playlist holds only saved tracks;
    /// otherwise isProfileAudio answers once per file.
    private func updateProfileButton() {
        var saved: Bool?
        if let (audio, message) = currentAudio(), message?.canBeSaved != false {
            let fileID = audio.audio.id
            if isProfile, chatID == TDLib.shared.activeAccount?.userID {
                saved = savedFiles[fileID] ?? true
            } else if let known = savedFiles[fileID] {
                saved = known
            } else {
                checkSaved(fileID)
            }
        }
        guard saved != isSaved else { return }
        isSaved = saved
        profileButton.isHidden = saved == nil
        controlsToSafeArea.isActive = saved == nil
        controlsToProfileButton.isActive = saved != nil
        if let saved {
            var configuration = profileButton.configuration ?? .filled()
            var title = AttributedString(L10n.telegram(saved
                    ? "MediaPlayer.SavedMusic.RemoveFromProfileShort"
                    : "MediaPlayer.SavedMusic.AddToProfile"))
            title.font = .systemFont(ofSize: 17, weight: .semibold)
            configuration.attributedTitle = title
            configuration.image = saved ? nil : UIImage(systemName: "music.note.list")
            configuration.baseBackgroundColor = saved ? .tertiarySystemFill : view.tintColor
            configuration.baseForegroundColor = saved ? .label : .white
            profileButton.configuration = configuration
        }
        guard let sheet = sheetPresentationController else { return }
        sheet.animateChanges { sheet.detents = sheetDetents() }
    }

    private func checkSaved(_ fileID: Int) {
        guard !savedChecks.contains(fileID), TDLib.shared.activeAccountID == accountID else { return }
        savedChecks.insert(fileID)
        let client = TDLib.shared.activeClient
        Task { [weak self] in
            // isProfileAudio answers 404 for a file outside the profile music.
            let saved = await (try? client.isProfileAudio(fileId: fileID)) != nil
            guard let self else { return }
            savedFiles[fileID] = saved
            updateProfileButton()
        }
    }

    /// requestSaveToProfile and requestRemoveFromProfile: the toast, then addProfileAudio or removeProfileAudio. The
    /// own playlist's last track leaves with the player, which stops.
    @objc private func profileButtonTapped() {
        guard let (audio, _) = currentAudio(), let saved = isSaved, TDLib.shared.activeAccountID == accountID
        else { return }
        let client = TDLib.shared.activeClient
        let fileID = audio.audio.id
        let ownUserID = TDLib.shared.activeAccount?.userID
        let isOwnPlaylist = isProfile && chatID == ownUserID
        let ownerToReload = ProfileMusicPlaylist.shared.owner.flatMap { $0.userID == ownUserID ? $0 : nil }
        savedFiles[fileID] = !saved
        if saved {
            let text = L10n.telegram("MediaPlayer.SavedMusic.RemovedFromProfile")
            if isOwnPlaylist, ProfileMusicPlaylist.shared.audios.count == 1, let host = presentingViewController?.view {
                Media.shared.close()
                dismiss(animated: true) {
                    TelegramUndoToast.show(text: text, in: host, bottomInset: 80, undo: nil)
                }
            } else {
                TelegramUndoToast.show(text: text, in: view, bottomInset: 8, undo: nil)
                updateProfileButton()
            }
            Task {
                _ = try? await client.removeProfileAudio(fileId: fileID)
                if let ownerToReload { await ProfileMusicPlaylist.shared.reload(ownerToReload, client: client) }
            }
            return
        }
        // The View action opens My Profile, except over the account's own playlist.
        TelegramUndoToast.show(
            text: L10n.telegram("MediaPlayer.SavedMusic.AddedToProfile"),
            in: view,
            bottomInset: 8,
            actionTitle: isOwnPlaylist ? nil : L10n.telegram("MediaPlayer.SavedMusic.AddedToProfile.View"),
            undo: isOwnPlaylist ? nil : { [weak self] in self?.openMyProfile() },
        )
        updateProfileButton()
        Task {
            _ = try? await client.addProfileAudio(audio: InputAudio(
                albumCoverThumbnail: nil,
                audio: .inputFileId(InputFileId(id: fileID)),
                duration: audio.duration,
                performer: audio.performer,
                title: audio.title,
            ))
            if let ownerToReload { await ProfileMusicPlaylist.shared.reload(ownerToReload, client: client) }
        }
    }

    /// OverlayAudioPlayerControllerNode's track menu: Save to… (Profile while the file isn't there, Saved Messages for
    /// a track outside them), Show in Chat for a chat's track, and Remove for a track of the account's own playlist.
    @objc private func rowLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let indexPath = tableView.indexPathForRow(at: gesture.location(in: tableView)),
              indexPath.row < rows.count,
              let cell = tableView.cellForRow(at: indexPath),
              TDLib.shared.activeAccountID == accountID
        else { return }
        let row = rows[indexPath.row]
        let ownUserID = TDLib.shared.activeAccount?.userID
        let isOwnPlaylist = isProfile && chatID == ownUserID
        let fileID = row.audio.audio.id
        let isSaved = isOwnPlaylist || savedFiles[fileID] == true
        if !isOwnPlaylist, savedFiles[fileID] == nil { checkSaved(fileID) }
        var saveTargets = [TelegramContextMenuAction]()
        if !isSaved {
            saveTargets.append(TelegramContextMenuAction(
                title: L10n.telegram("MediaPlayer.ContextMenu.SaveTo.Profile"),
                image: UIImage(systemName: "person"),
            ) { [weak self] in self?.saveToProfile(row.audio) })
        }
        if row.message == nil || chatID != ownUserID {
            saveTargets.append(TelegramContextMenuAction(
                title: L10n.telegram("MediaPlayer.ContextMenu.SaveTo.SavedMessages"),
                image: UIImage(systemName: "bookmark"),
            ) { [weak self] in self?.sendToSavedMessages(row.audio) })
        }
        var actions = [TelegramContextMenuAction]()
        if !saveTargets.isEmpty {
            var info = TelegramContextMenuAction(
                title: L10n.telegram("MediaPlayer.ContextMenu.SaveTo.Info"),
                image: nil,
                startsNewSection: true,
            )
            info.isInformational = true
            info.usesSmallText = true
            info.isMultiline = true
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("MediaPlayer.ContextMenu.SaveTo"),
                image: UIImage(systemName: "square.and.arrow.down"),
                children: saveTargets + [info],
            ))
        }
        if let message = row.message {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("MediaPlayer.ContextMenu.ShowInChat"),
                image: UIImage(systemName: "arrow.right.circle"),
                startsNewSection: !actions.isEmpty,
            ) { [weak self] in self?.showInChat(message) })
        }
        if isOwnPlaylist {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("MediaPlayer.ContextMenu.Remove"),
                image: UIImage(systemName: "trash"),
                isDestructive: true,
                startsNewSection: true,
            ) { [weak self] in self?.removeFromOwnPlaylist(row.audio) })
        }
        guard !actions.isEmpty else { return }
        presentTelegramContextMenu(sourceView: cell, actions: actions, tracking: gesture, presentationStyle: .menuOnly)
    }

    private func saveToProfile(_ audio: Audio) {
        guard TDLib.shared.activeAccountID == accountID else { return }
        let client = TDLib.shared.activeClient
        savedFiles[audio.audio.id] = true
        updateProfileButton()
        TelegramUndoToast.show(
            text: L10n.telegram("MediaPlayer.SavedMusic.AddedToProfile"),
            in: view,
            bottomInset: 8,
            actionTitle: L10n.telegram("MediaPlayer.SavedMusic.AddedToProfile.View"),
            undo: { [weak self] in self?.openMyProfile() },
        )
        Task {
            _ = try? await client.addProfileAudio(audio: InputAudio(
                albumCoverThumbnail: nil,
                audio: .inputFileId(InputFileId(id: audio.audio.id)),
                duration: audio.duration,
                performer: audio.performer,
                title: audio.title,
            ))
        }
    }

    /// forwardToSavedMessages: the file goes to Saved Messages as a new audio message.
    private func sendToSavedMessages(_ audio: Audio) {
        guard TDLib.shared.activeAccountID == accountID, let me = TDLib.shared.activeAccount?.userID else { return }
        let client = TDLib.shared.activeClient
        TelegramUndoToast.show(
            text: L10n.telegram("MediaPlayer.AudioForwardedToSavedMesagesTooltip"),
            in: view,
            bottomInset: 8,
            undo: nil,
        )
        Task {
            _ = try? await client.send(TDNativeRequests.sendMessage(
                chatId: me,
                topicId: nil,
                replyTo: nil,
                options: nil,
                replyMarkup: nil,
                inputMessageContent: .inputMessageAudio(TDNativeInputMessageAudio(
                    audio: InputAudio(
                        albumCoverThumbnail: nil,
                        audio: .inputFileId(InputFileId(id: audio.audio.id)),
                        duration: audio.duration,
                        performer: audio.performer,
                        title: audio.title,
                    ),
                    caption: nil,
                )),
            ))
        }
    }

    /// Show in Chat: the player closes and the chat opens at the track's message.
    private func showInChat(_ message: Message) {
        guard TDLib.shared.activeAccountID == accountID else { return }
        let client = TDLib.shared.activeClient
        let chatID = message.chatId
        let messageID = message.id
        dismiss(animated: true)
        Task {
            guard let chat = await RootVM.shared.getCustomChatForNavigation(from: chatID, client: client)
            else { return }
            NavigationStorage.shared.push(.customChat(chat, targetMessageID: messageID))
        }
    }

    /// Remove from the account's own playlist: the button's removal for that track.
    private func removeFromOwnPlaylist(_ audio: Audio) {
        guard TDLib.shared.activeAccountID == accountID else { return }
        let client = TDLib.shared.activeClient
        let fileID = audio.audio.id
        savedFiles[fileID] = false
        TelegramUndoToast.show(
            text: L10n.telegram("MediaPlayer.SavedMusic.RemovedFromProfile"),
            in: view,
            bottomInset: 8,
            undo: nil,
        )
        let owner = ProfileMusicPlaylist.Owner(accountID: accountID, userID: chatID)
        Task {
            _ = try? await client.removeProfileAudio(fileId: fileID)
            await ProfileMusicPlaylist.shared.reload(owner, client: client)
        }
    }

    private func openMyProfile() {
        let accountID = accountID
        guard TDLib.shared.activeAccountID == accountID else { return }
        let client = TDLib.shared.activeClient
        dismiss(animated: true)
        Task {
            guard let me = try? await client.getMe(),
                  let chat = try? await client.createPrivateChat(force: false, userId: me.id),
                  let customChat = await RootVM.shared.getCustomChatForNavigation(from: chat.id, client: client),
                  TDLib.shared.activeAccountID == accountID
            else { return }
            let profile = PeerProfileViewController(
                customChat: customChat, topic: nil, client: client, accountID: accountID, isMyProfile: true,
            )
            NavigationStorage.shared.activeNavigationController.pushViewController(profile, animated: true)
        }
    }

    private func configureCloseButton() {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.accessibilityLabel = L10n.telegram("Common.Close")
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            closeButton.centerYAnchor.constraint(
                equalTo: view.topAnchor,
                constant: isProfile
                    ? 38
                    : headerHeight / 2 + 2,
            ),
        ])
    }

    /// The profile playlist's title: Your Playlist, or the user's name's playlist, between the header's buttons.
    private func configureTitle() {
        guard isProfile else { return }
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        view.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 70,
            ),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -16),
        ])
        let userID = chatID
        guard TDLib.shared.activeAccountID == accountID else { return }
        if TDLib.shared.activeAccount?.userID == userID {
            titleLabel.text = L10n.telegram("MediaPlayer.PlaylistYourTitle")
            return
        }
        let client = TDLib.shared.activeClient
        Task { [weak self] in
            guard let user = try? await client.getUser(userId: userID), let self, chatID == userID else { return }
            let name = user.firstName.isEmpty ? user.lastName : user.firstName
            titleLabel.text = L10n.telegram("MediaPlayer.PlaylistTitle", name)
        }
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
        ProfileMusicPlaylist.shared
            .changes
            .sink { [weak self] in
                guard let self, isProfile else { return }
                applyRows()
            }
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
            guard let row = rows.first(where: { matches(item, $0) }) else { return nil }
            return Media.NowPlayingDisplay.music(row.audio, item: item)
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
        updateProfileButton()
    }

    /// A track the playlist moved to: the list loads around it unless it already holds it; another chat's track
    /// starts the list over.
    private func follow(_ item: Media.NowPlaying) {
        if item.chatID != chatID || item.isProfileAudio != isProfile {
            chatID = item.chatID
            isProfile = item.isProfileAudio
            titleLabel.isHidden = !isProfile
            tracks = [:]
            rows = []
            tableView.reloadData()
            if isProfile {
                applyRows(scrollingTo: item.messageID)
            } else {
                loadTracks(around: item.messageID)
            }
        } else if isProfile {
            if let row = rows.firstIndex(where: { $0.id == item.messageID }) {
                tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .none, animated: true)
            }
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
    private func orderedRows() -> [TrackRow] {
        guard hasList else { return [] }
        if isProfile {
            let playlist = ProfileMusicPlaylist.shared
            guard playlist.owner == ProfileMusicPlaylist.Owner(accountID: accountID, userID: chatID) else { return [] }
            let profileRows = playlist.audios.map { TrackRow(id: Int64($0.audio.id), audio: $0, message: nil) }
            return isReversed ? profileRows.reversed() : profileRows
        }
        return orderedMessages().compactMap { message in
            guard case .messageAudio(let content) = message.content else { return nil }
            return TrackRow(id: message.id, audio: content.audio, message: message)
        }
    }

    private func orderedMessages() -> [Message] {
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
        // A paused track's audio arrives with the list, after Media last published.
        updateProfileButton()
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
        let present = isProfile ? !ProfileMusicPlaylist.shared.audios.isEmpty : tracks.count > 1
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

    /// Whether `item` plays the row's track.
    private func matches(_ item: Media.NowPlaying, _ row: TrackRow) -> Bool {
        item.accountID == accountID && item.isProfileAudio == isProfile && item.chatID == chatID
            && item.messageID == row.id
    }

    private func rowState(for row: TrackRow) -> MusicPlayerTrackCell.State {
        if let loading = VoicePlaylistContinuation.shared.loadingMusic, matches(loading, row) {
            return .loading
        }
        guard let currentItem, matches(currentItem, row) else { return .idle }
        return Media.shared.isPlaying ? .playing : .paused
    }

    /// openChatMessage from the list: the playing track pauses or resumes; another one plays and the playlist goes
    /// on from it.
    private func playTrack(_ row: TrackRow) {
        if let currentItem, matches(currentItem, row) {
            Media.shared.togglePlayback()
            return
        }
        guard TDLib.shared.activeAccountID == accountID else { return }
        let client = TDLib.shared.activeClient
        if let message = row.message {
            VoicePlaylistContinuation.shared.playMusic(message, accountID: accountID, client: client)
        } else {
            VoicePlaylistContinuation.shared.playProfileAudio(
                row.audio,
                owner: ProfileMusicPlaylist.Owner(accountID: accountID, userID: chatID),
                client: client,
            )
        }
    }

    private func loadMoreProfileTracks() {
        guard isProfile, ProfileMusicPlaylist.shared.canLoadMore, TDLib.shared.activeAccountID == accountID
        else { return }
        let client = TDLib.shared.activeClient
        Task { await ProfileMusicPlaylist.shared.loadMore(client: client) }
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

// MARK: - TrackRow

/// A row of the player's list: a chat's music message, or a track of a user's profile music by its file ID.
private struct TrackRow {
    let id: Int64
    let audio: Audio
    let message: Message?
}

// MARK: - MusicPlayerViewController + UITableViewDataSource, UITableViewDelegate

extension MusicPlayerViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: MusicPlayerTrackCell.reuseIdentifier, for: indexPath)
        guard let trackCell = cell as? MusicPlayerTrackCell, indexPath.row < rows.count else { return cell }
        let row = rows[indexPath.row]
        trackCell.configure(audio: row.audio, accountID: accountID, state: rowState(for: row))
        return trackCell
    }

    /// The list pages in more of the chat's tracks near either end: newer ones at the top in the regular order, older
    /// ones at the top otherwise.
    func tableView(_: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        if isProfile {
            if isReversed ? indexPath.row < 5 : indexPath.row >= rows.count - 5 { loadMoreProfileTracks() }
            return
        }
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

    func configure(audio: Audio, accountID: UUID, state: State) {
        artView.cancel()
        artView.image = nil
        dimView.isHidden = true
        self.state = nil
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
                DataSize.string(size)
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
