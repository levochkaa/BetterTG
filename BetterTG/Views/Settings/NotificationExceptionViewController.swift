// NotificationExceptionViewController.swift

import AVFoundation
import TDLibKit
import UIKit
import UniformTypeIdentifiers

// MARK: - NotificationExceptionViewController

/// Telegram's notificationPeerExceptionController, opened by Customize in a chat's or a topic's Mute menu: Always On
/// or Always Off, the message preview, a private chat's story notifications, and the sound. The sounds are the
/// account's saved notification sounds: its own tones with Upload Sound, then Telegram's alert and classic tones,
/// which Telegram tells apart by their file ids. Picking a sound plays it. Done hands the result to `onApply`.
final class NotificationExceptionViewController: SettingsListViewController, UIDocumentPickerDelegate {
    // MARK: Private

    private enum Sound: Equatable {
        case `default`
        case none
        case cloud(Int64)
    }

    /// TDLib reads a mute longer than this as forever (DialogNotificationSettings, MAX_PRECISE_MUTE_FOR).
    private static let preciseMuteLimit = 366 * 24 * 60 * 60

    /// TelegramCore's cloudSoundMapping: the file ids of Telegram's built-in tones. Keys below 50 are the classic
    /// tones from index 2, the others the alert tones from index 100.
    private static let builtinSoundKeys: [Int64: Int] = [
        5_078_299_559_046_677_200: 2, 5_078_299_559_046_677_201: 3, 5_078_299_559_046_677_202: 4,
        5_078_299_559_046_677_203: 5, 5_078_299_559_046_677_204: 6, 5_078_299_559_046_677_205: 7,
        5_078_299_559_046_677_206: 8, 5_078_299_559_046_677_207: 9,
        5_078_299_559_046_677_208: 100, 5_078_299_559_046_677_209: 101, 5_078_299_559_046_677_210: 102,
        5_078_299_559_046_677_211: 103, 5_078_299_559_046_677_212: 104, 5_078_299_559_046_677_213: 105,
        5_078_299_559_046_677_214: 106, 5_078_299_559_046_677_215: 107, 5_078_299_559_046_677_216: 108,
        5_078_299_559_046_677_217: 109, 5_078_299_559_046_677_218: 110, 5_078_299_559_046_677_219: 111,
        5_032_932_652_722_685_163: 200, 5_032_932_652_722_685_160: 201, 5_032_932_652_722_685_159: 202,
        5_032_932_652_722_685_158: 203, 5_032_932_652_722_685_168: 204, 5_032_932_652_722_685_167: 205,
        5_032_932_652_722_685_166: 206, 5_032_932_652_722_685_165: 207, 5_032_932_652_722_685_164: 208,
        5_032_932_652_722_685_162: 209, 5_032_932_652_722_685_161: 210,
    ]

    /// Telegram's defaultCloudPeerNotificationSound (cloudSoundMapping[200]).
    private static let defaultCloudSoundID: Int64 = 5_032_932_652_722_685_163

    private static let modernSoundNames = [
        "Note", "Aurora", "Bamboo", "Chord", "Circles", "Complete", "Hello", "Input", "Keys", "Popcorn", "Pulse",
        "Synth", "Rebound", "Antic", "Cheers", "Droplet", "Handoff", "Milestone", "Passage", "Portal", "Rattle",
        "Slide", "Welcome",
    ]

    private static let classicSoundNames = [
        "Tritone", "Tremolo", "Alert", "Bell", "Calypso", "Chime", "Glass", "Telegraph",
    ]

    private let screenTitle: String
    private let scope: NotificationSettingsScope
    private let initialSettings: ChatNotificationSettings
    private let offersStories: Bool
    private let onApply: (ChatNotificationSettings) -> Void

    private var notificationsOn: Bool
    private var previewsOn: Bool
    private var storiesOn: Bool
    private var storyPosterShown: Bool
    private var selectedSound: Sound
    /// The saved notification sounds; nil until they load.
    private var sounds: [TDNativeNotificationSound]?
    private var isUploading = false
    private var player: AVAudioPlayer?
    private var playTask: Task<Void, Never>?

    /// The scope's own sound: TDLib's -1 is the default one, 0 none.
    private var scopeSoundID: Int64 {
        RootVM.shared.scopeNotificationSettings[scope]?.soundId ?? -1
    }

    /// resolvedNotificationSound: a tone that is no longer saved shows Telegram's default tone as picked.
    private var displayedSound: Sound {
        guard case .cloud(let id) = selectedSound, let sounds, !sounds.contains(where: { $0.id == id }) else {
            return selectedSound
        }
        return .cloud(Self.defaultCloudSoundID)
    }

    init(
        title: String,
        scope: NotificationSettingsScope,
        settings: ChatNotificationSettings,
        offersStories: Bool,
        onApply: @escaping (ChatNotificationSettings) -> Void,
    ) {
        self.screenTitle = title
        self.scope = scope
        self.initialSettings = settings
        self.offersStories = offersStories
        self.onApply = onApply
        // NotificationExceptionPeerState: only a mute forever reads as Always Off, and a default reads as on.
        self.notificationsOn = settings.useDefaultMuteFor || settings.muteFor <= Self.preciseMuteLimit
        self.previewsOn = settings.useDefaultShowPreview || settings.showPreview
        self.storiesOn = settings.useDefaultMuteStories || !settings.muteStories
        self.storyPosterShown = settings.useDefaultShowStoryPoster || settings.showStoryPoster
        self.selectedSound =
            if settings.useDefaultSound || settings.soundId < 0 {
                .default
            } else if settings.soundId == 0 {
                .none
            } else {
                .cloud(settings.soundId)
            }
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        title = screenTitle
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) },
        )
        let done = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.donePressed() })
        done.style = .prominent
        navigationItem.rightBarButtonItem = done
        loadSounds()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        playTask?.cancel()
        player?.stop()
        player = nil
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [SettingsSection(
            header: L10n.telegram("Notification.Exceptions.NewException.NotificationHeader"),
            rows: [
                choiceRow("Notification.Exceptions.AlwaysOn", selected: notificationsOn) { $0.notificationsOn = true },
                choiceRow("Notification.Exceptions.AlwaysOff", selected: !notificationsOn) { $0.notificationsOn = false
                },
            ],
        )]
        if notificationsOn {
            sections.append(SettingsSection(
                header: L10n.telegram("Notification.Exceptions.NewException.MessagePreviewHeader"),
                rows: [
                    choiceRow("Notification.Exceptions.MessagePreviewAlwaysOn", selected: previewsOn) {
                        $0.previewsOn = true
                    },
                    choiceRow("Notification.Exceptions.MessagePreviewAlwaysOff", selected: !previewsOn) {
                        $0.previewsOn = false
                    },
                ],
            ))
        }
        if offersStories {
            sections.append(SettingsSection(
                header: L10n.telegram("Notification.Exceptions.StoriesHeader"),
                rows: [
                    choiceRow("Notification.Exceptions.MessagePreviewAlwaysOn", selected: storiesOn) {
                        $0.storiesOn = true
                    },
                    choiceRow("Notification.Exceptions.MessagePreviewAlwaysOff", selected: !storiesOn) {
                        $0.storiesOn = false
                    },
                ],
            ))
            if storiesOn {
                sections.append(SettingsSection(
                    header: L10n.telegram("Notification.Exceptions.StoriesDisplayAuthorName"),
                    rows: [
                        choiceRow("Notification.Exceptions.MessagePreviewAlwaysOn", selected: storyPosterShown) {
                            $0.storyPosterShown = true
                        },
                        choiceRow("Notification.Exceptions.MessagePreviewAlwaysOff", selected: !storyPosterShown) {
                            $0.storyPosterShown = false
                        },
                    ],
                ))
            }
        }
        sections += soundSections()
        return sections
    }

    func present(from host: UIViewController) {
        host.present(UINavigationController(rootViewController: self), animated: true)
    }

    // MARK: UIDocumentPickerDelegate

    func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        upload(url)
    }

    private func choiceRow(
        _ key: String,
        selected: Bool,
        select: @escaping (NotificationExceptionViewController) -> Void,
    ) -> SettingsRow {
        SettingsRow(title: L10n.telegram(key), accessory: selected ? .checkmark : .none) { [weak self] in
            guard let self else { return }
            select(self)
            reload()
        }
    }

    /// Telegram Tones (the account's own, deletable, with Upload Sound), Alert Tones (Default, None and the modern
    /// tones) and Classic.
    private func soundSections() -> [SettingsSection] {
        let tonesHeader = L10n.telegram("Notifications.TelegramTones")
        guard let sounds else {
            return [SettingsSection(header: tonesHeader, rows: [SettingsRow(
                title: L10n.telegram("Channel.NotificationLoading"),
                style: .status(.secondaryLabel),
                accessory: .activity,
            )])]
        }
        let picked = displayedSound
        var ownRows = sounds.filter { Self.builtinSoundKeys[$0.id] == nil }.map {
            soundRow(.cloud($0.id), picked: picked, deletable: true)
        }
        ownRows.append(SettingsRow(
            title: L10n.telegram("Notifications.UploadSound"),
            style: .action(destructive: false),
            symbol: "plus",
            accessory: isUploading ? .activity : .none,
            isEnabled: !isUploading,
        ) { [weak self] in self?.pickSoundFile() })
        let alertRows = [soundRow(.default, picked: picked), soundRow(.none, picked: picked)]
            + sounds.filter { (Self.builtinSoundKeys[$0.id] ?? 0) >= 50 }
            .map { soundRow(.cloud($0.id), picked: picked) }
        let classicRows = sounds.filter { (Self.builtinSoundKeys[$0.id] ?? 50) < 50 }.map {
            soundRow(.cloud($0.id), picked: picked)
        }
        var sections = [
            SettingsSection(
                header: tonesHeader,
                footer: L10n.telegram("Notifications.MessageSoundInfo"),
                rows: ownRows,
            ),
            SettingsSection(header: L10n.telegram("Notifications.AlertTones"), rows: alertRows),
        ]
        if !classicRows.isEmpty {
            sections.append(SettingsSection(header: L10n.telegram("Notifications.ClassicTones"), rows: classicRows))
        }
        return sections
    }

    private func soundRow(_ sound: Sound, picked: Sound, deletable: Bool = false) -> SettingsRow {
        let title = name(of: sound)
        var row = SettingsRow(title: title, accessory: sound == picked ? .checkmark : .none) { [weak self] in
            self?.select(sound)
        }
        if deletable, case .cloud(let id) = sound {
            row.swipeAction = (
                title: L10n.telegram("Common.Delete"),
                handler: { [weak self] in self?.confirmDelete(soundID: id, title: title) },
            )
        }
        return row
    }

    /// localizedPeerNotificationSoundString: Default names the scope's sound, and a tone without a name reads as
    /// Default. Telegram always has its default tone in the list; TDLib may not, and then Default has no name.
    private func name(of sound: Sound) -> String {
        switch sound {
        case .none:
            return L10n.telegram("NotificationsSound.None")
        case .default:
            let scopeSound = scopeSoundID
            var name =
                if scopeSound == 0 {
                    L10n.telegram("NotificationsSound.None")
                } else if scopeSound > 0 {
                    cloudName(scopeSound)
                } else {
                    ""
                }
            if name.isEmpty {
                name = cloudName(Self.defaultCloudSoundID)
            }
            return name.isEmpty
                ? L10n.telegram("UserInfo.NotificationsDefault")
                : L10n.telegram("UserInfo.NotificationsDefaultSound", name)
        case .cloud(let id):
            let name = cloudName(id)
            return name.isEmpty ? self.name(of: .default) : name
        }
    }

    private func cloudName(_ id: Int64) -> String {
        if let key = Self.builtinSoundKeys[id] {
            let names = key < 50 ? Self.classicSoundNames : Self.modernSoundNames
            let index = key < 50 ? key - 2 : key - 100
            if names.indices.contains(index) {
                return L10n.telegram("NotificationsSound." + names[index])
            }
        }
        guard let sounds else { return L10n.telegram("Channel.NotificationLoading") }
        guard let sound = sounds.first(where: { $0.id == id }) else { return "" }
        return sound.title.isEmpty ? "Cloud Tone" : sound.title
    }

    private func select(_ sound: Sound) {
        selectedSound = sound
        reload()
        play(sound)
    }

    // MARK: Sounds

    private func loadSounds() {
        guard contextIsCurrent else { return }
        let client = client
        Task { [weak self] in
            let result = try? await client.send(TDNativeRequests.getSavedNotificationSounds())
            guard let self, contextIsCurrent else { return }
            sounds = result?.notificationSounds ?? []
            reload()
        }
    }

    /// playSound: the picked tone, or for Default the scope's tone.
    private func play(_ sound: Sound) {
        playTask?.cancel()
        player?.stop()
        player = nil
        let id: Int64
        switch sound {
        case .none:
            return
        case .cloud(let value):
            id = value
        case .default:
            let scopeSound = scopeSoundID
            guard scopeSound != 0 else { return }
            id = scopeSound > 0 ? scopeSound : Self.defaultCloudSoundID
        }
        guard let file = sounds?.first(where: { $0.id == id })?.sound else { return }
        let client = client
        playTask = Task { [weak self] in
            var path = file.local.isDownloadingCompleted ? file.local.path : ""
            if path.isEmpty,
               let downloaded = try? await client.downloadFile(
                   fileId: file.id,
                   limit: 0,
                   offset: 0,
                   priority: 32,
                   synchronous: true,
               ),
               downloaded.local.isDownloadingCompleted
            {
                path = downloaded.local.path
            }
            guard !path.isEmpty, !Task.isCancelled else { return }
            let url = await FFmpegAudioPlaybackCache.shared.playableURL(for: URL(fileURLWithPath: path))
            guard let self, !Task.isCancelled, let player = try? AVAudioPlayer(contentsOf: url) else { return }
            self.player = player
            player.play()
        }
    }

    private func confirmDelete(soundID: Int64, title: String) {
        confirm(
            title: L10n.telegram("PeerInfo.DeleteToneTitle"),
            message: L10n.telegram("PeerInfo.DeleteToneText", title).replacingOccurrences(of: "**", with: ""),
            actionTitle: L10n.telegram("Common.Delete"),
        ) { [weak self] in
            guard let self else { return }
            sounds?.removeAll { $0.id == soundID }
            if selectedSound == .cloud(soundID) {
                selectedSound = .cloud(Self.defaultCloudSoundID)
            }
            reload()
            perform { client in
                _ = try await client.send(TDNativeRequests.removeSavedNotificationSound(notificationSoundId: soundID))
            }
        }
    }

    private func pickSoundFile() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.mp3], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    /// presentCustomNotificationSoundFilePicker: an mp3 within the account's size and duration limits becomes a
    /// saved tone, with Telegram's "Sound Added" toast; otherwise its "too large" or "too long" toast.
    private func upload(_ url: URL) {
        guard contextIsCurrent, !isUploading else { return }
        let client = client
        isUploading = true
        reload()
        Task { [weak self] in
            let limits = await NotificationSoundLimits.load(client: client)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let duration = await (try? AVURLAsset(url: url).load(.duration)).map(CMTimeGetSeconds) ?? 0
            var toast: (title: String, text: String)?
            var added: TDNativeNotificationSound?
            if let failure = limits.failure(size: Int64(size), duration: duration, name: url.lastPathComponent) {
                toast = failure
            } else {
                added = try? await client.send(TDNativeRequests.addSavedNotificationSound(
                    sound: .inputFileLocal(InputFileLocal(path: url.path(percentEncoded: false))),
                ))
            }
            guard let self, contextIsCurrent else { return }
            isUploading = false
            if let added {
                if sounds?.contains(where: { $0.id == added.id }) == false {
                    sounds?.insert(added, at: 0)
                }
                toast = (
                    L10n.telegram("Notifications.UploadSuccess.Title"),
                    L10n.telegram("Notifications.UploadSuccess.Text", added.title)
                        .replacingOccurrences(of: "**", with: ""),
                )
            } else if toast == nil {
                presentChatListActionFailure()
            }
            reload()
            if let toast {
                TelegramUndoToast.show(title: toast.title, text: toast.text, in: view, bottomInset: 12, undo: nil)
            }
        }
    }

    private func donePressed() {
        let settings = initialSettings
        let soundID: Int64 =
            switch selectedSound {
            case .default: settings.soundId
            case .none: 0
            case .cloud(let id): id
            }
        let updated = ChatNotificationSettings(
            disableMentionNotifications: settings.disableMentionNotifications,
            disablePinnedMessageNotifications: settings.disablePinnedMessageNotifications,
            muteFor: notificationsOn ? 0 : Int(Int32.max),
            muteStories: offersStories ? !storiesOn : settings.muteStories,
            showPreview: previewsOn,
            showStoryPoster: offersStories ? storyPosterShown : settings.showStoryPoster,
            soundId: soundID,
            storySoundId: settings.storySoundId,
            useDefaultDisableMentionNotifications: settings.useDefaultDisableMentionNotifications,
            useDefaultDisablePinnedMessageNotifications: settings.useDefaultDisablePinnedMessageNotifications,
            useDefaultMuteFor: false,
            useDefaultMuteStories: offersStories ? false : settings.useDefaultMuteStories,
            useDefaultShowPreview: false,
            useDefaultShowStoryPoster: offersStories ? false : settings.useDefaultShowStoryPoster,
            useDefaultSound: selectedSound == .default,
            useDefaultStorySound: settings.useDefaultStorySound,
        )
        onApply(updated)
        dismiss(animated: true)
    }
}

// MARK: - NotificationSoundLimits

/// TDLib's notification_sound_size_max and notification_sound_duration_max (Telegram's NotificationSoundSettings),
/// with Telegram's toasts for a file over them.
struct NotificationSoundLimits {
    let maxSize: Int64
    let maxDuration: Int

    static func load(client: TDLibClient) async -> NotificationSoundLimits {
        var maxSize: Int64 = 307_200
        var maxDuration = 5
        if case .optionValueInteger(let value) = try? await client.getOption(name: "notification_sound_size_max") {
            maxSize = value.value
        }
        if case .optionValueInteger(let value) = try? await client.getOption(name: "notification_sound_duration_max") {
            maxDuration = Int(clamping: value.value)
        }
        return NotificationSoundLimits(maxSize: maxSize, maxDuration: maxDuration)
    }

    func failure(size: Int64, duration: Double, name: String) -> (title: String, text: String)? {
        if size > maxSize {
            return (
                L10n.telegram("Notifications.UploadError.TooLarge.Title"),
                L10n.telegram(
                    "Notifications.UploadError.TooLarge.Text",
                    ByteCountFormatter.string(fromByteCount: maxSize, countStyle: .binary),
                ),
            )
        }
        if duration > Double(maxDuration) {
            return (
                L10n.telegram("Notifications.UploadError.TooLong.Title", name),
                L10n.telegram(
                    "Notifications.UploadError.TooLong.Text",
                    String(format: "%d:%02d", maxDuration / 60, maxDuration % 60),
                ),
            )
        }
        return nil
    }
}
