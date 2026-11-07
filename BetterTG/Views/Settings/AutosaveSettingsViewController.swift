// AutosaveSettingsViewController.swift

import TDLibKit
import UIKit

// MARK: - AutosaveScope

/// AutomaticSaveIncomingPeerType: the three kinds of chat Save to Camera Roll is set for, and which kind a chat is.
enum AutosaveScope: CaseIterable {
    case privateChats
    case groups
    case channels

    var title: String {
        switch self {
        case .privateChats: L10n.telegram("Notifications.PrivateChats")
        case .groups: L10n.telegram("Notifications.GroupChats")
        case .channels: L10n.telegram("Notifications.Channels")
        }
    }

    var symbol: String {
        switch self {
        case .privateChats: "person.fill"
        case .groups: "person.2.fill"
        case .channels: "megaphone.fill"
        }
    }

    var tint: UIColor {
        switch self {
        case .privateChats: .systemBlue
        case .groups: .systemGreen
        case .channels: .systemOrange
        }
    }

    var tdScope: TDNativeAutosaveSettingsScope {
        switch self {
        case .privateChats: .autosaveSettingsScopePrivateChats
        case .groups: .autosaveSettingsScopeGroupChats
        case .channels: .autosaveSettingsScopeChannelChats
        }
    }

    /// A person or a secret chat is a private chat, a channel a channel, and any other group a group.
    init(chatType: TDNativeChatType) {
        self =
            switch chatType {
            case .chatTypePrivate,
                 .chatTypeSecret: .privateChats
            case .chatTypeBasicGroup: .groups
            case .chatTypeSupergroup(let group): group.isChannel ? .channels : .groups
            }
    }

    /// autosaveLabelAndValue's label: All Media (size), Photos, or Videos up to size, then the exceptions' count.
    static func label(for settings: TDNativeScopeAutosaveSettings, exceptions: Int) -> String {
        var parts = [String]()
        let size = DataSize.string(settings.maxVideoFileSize)
        if settings.autosavePhotos, settings.autosaveVideos {
            parts.append(L10n.telegram("Settings.AutosaveMediaAllMedia", size))
        } else if settings.autosavePhotos {
            parts.append(L10n.telegram("Settings.AutosaveMediaPhoto"))
        } else if settings.autosaveVideos {
            parts.append(L10n.telegram("Settings.AutosaveMediaVideo", size))
        }
        if exceptions > 0 {
            parts.append(L10n.telegramPlural("Notifications.CategoryExceptions", count: exceptions))
        }
        return parts.joined(separator: ", ")
    }

    /// The exception row's label: Photos or No Photos, then Videos up to size or No Videos.
    static func exceptionLabel(for settings: TDNativeScopeAutosaveSettings) -> String {
        [
            L10n.telegram(settings.autosavePhotos ? "Settings.AutosaveMediaPhoto" : "Settings.AutosaveMediaNoPhoto"),
            settings.autosaveVideos
                ? L10n.telegram("Settings.AutosaveMediaVideo", DataSize.string(settings.maxVideoFileSize))
                : L10n.telegram("Settings.AutosaveMediaNoVideo"),
        ].joined(separator: ", ")
    }

    func settings(in all: TDNativeAutosaveSettings) -> TDNativeScopeAutosaveSettings {
        switch self {
        case .privateChats: all.privateChatSettings
        case .groups: all.groupSettings
        case .channels: all.channelSettings
        }
    }
}

// MARK: - AutosaveSettingsViewController

/// SaveIncomingMediaController for a kind of chat, or for one chat as its exception: Photos and Videos under SAVE TO
/// CAMERA ROLL, MAXIMUM VIDEO SIZE's slider while videos are on, and for a kind its EXCEPTIONS (each opens its own
/// settings and can be removed, with Delete All Exceptions). Changes go to TDLib's autosave settings at once.
final class AutosaveSettingsViewController: SettingsListViewController {
    enum Target {
        case scope(AutosaveScope)
        case chat(id: Int64, peer: SettingsPeer)
    }

    private let target: Target
    private var settings: TDNativeScopeAutosaveSettings?
    private var exceptions = [(peer: SettingsPeer, chatID: Int64, settings: TDNativeScopeAutosaveSettings)]()

    private var tdScope: TDNativeAutosaveSettingsScope {
        switch target {
        case .scope(let scope): scope.tdScope
        case .chat(let id, _): .autosaveSettingsScopeChat(.init(chatId: id))
        }
    }

    /// The slider's section: after the chat's row for an exception.
    private var sliderSectionIndex: Int {
        if case .chat = target { return 2 }
        return 1
    }

    init(target: Target) {
        self.target = target
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(
            AutoDownloadSizeLimitCell.self,
            forCellReuseIdentifier: AutoDownloadSizeLimitCell.reuseIdentifier,
        )
        title =
            switch target {
            case .scope(let scope): scope.title
            case .chat: L10n.telegram("Autosave.Exception")
            }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        load()
    }

    override func makeSections() -> [SettingsSection] {
        guard let settings else {
            return [SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("Channel.NotificationLoading"),
                style: .status(.secondaryLabel),
                accessory: .activity,
            )])]
        }
        var sections = [SettingsSection]()
        if case .chat(_, let peer) = target {
            sections.append(SettingsSection(rows: [SettingsRow(title: peer.title, style: .peer(peer))]))
        }
        sections.append(SettingsSection(
            header: L10n.telegram("Autosave.TypesSection"),
            footer: L10n.telegram("Autosave.TypesInfo"),
            rows: [
                SettingsRow(
                    title: L10n.telegram("Autosave.TypePhoto"),
                    accessory: .toggle(isOn: settings.autosavePhotos) { [weak self] isOn in
                        self?.update(photos: isOn)
                    },
                ),
                SettingsRow(
                    title: L10n.telegram("Autosave.TypeVideo"),
                    accessory: .toggle(isOn: settings.autosaveVideos) { [weak self] isOn in
                        self?.update(videos: isOn)
                    },
                ),
            ],
        ))
        if settings.autosaveVideos {
            // The size slider's cell stands in for this row.
            sections.append(SettingsSection(
                header: L10n.telegram("Autosave.VideoSizeSection"),
                footer: L10n.telegram(
                    "Autosave.VideoInfo", MediaAutoDownload.sizeString(settings.maxVideoFileSize),
                ),
                rows: [SettingsRow(title: "")],
            ))
        }
        if case .scope = target {
            sections.append(SettingsSection(
                header: exceptions.isEmpty
                    ? L10n.telegram("Autosave.ExceptionsSection")
                    : L10n.telegramPlural("Notifications.CategoryExceptions", count: exceptions.count).uppercased(),
                rows: [SettingsRow(
                    title: L10n.telegram("Autosave.AddException"),
                    style: .action(destructive: false),
                    symbol: "plus",
                ) { [weak self] in self?.addException() }] + exceptions.map { exception in
                    var row = SettingsRow(
                        title: exception.peer.title,
                        detail: AutosaveScope.exceptionLabel(for: exception.settings),
                        style: .peer(exception.peer),
                        accessory: .disclosure,
                    ) { [weak self] in
                        self?.navigationController?.pushViewController(
                            AutosaveSettingsViewController(
                                target: .chat(id: exception.chatID, peer: exception.peer),
                            ),
                            animated: true,
                        )
                    }
                    row.swipeAction = (L10n.telegram("Common.Delete"), { [weak self] in
                        self?.removeException(exception.chatID)
                    })
                    return row
                },
            ))
            if !exceptions.isEmpty {
                sections.append(SettingsSection(rows: [SettingsRow(
                    title: L10n.telegram("Autosave.DeleteAllExceptions"),
                    style: .action(destructive: true),
                ) { [weak self] in self?.confirmDeleteAll() }]))
            }
        }
        return sections
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let settings, settings.autosaveVideos, indexPath.section == sliderSectionIndex else {
            return super.tableView(tableView, cellForRowAt: indexPath)
        }
        let cell = tableView.dequeueReusableCell(
            withIdentifier: AutoDownloadSizeLimitCell.reuseIdentifier, for: indexPath,
        )
        (cell as? AutoDownloadSizeLimitCell)?.configure(size: settings.maxVideoFileSize) { [weak self] size in
            self?.update(maxVideoSize: size)
        }
        return cell
    }

    // MARK: Changes

    private func update(photos: Bool? = nil, videos: Bool? = nil, maxVideoSize: Int64? = nil) {
        guard let current = settings else { return }
        let updated = TDNativeScopeAutosaveSettings(
            autosavePhotos: photos ?? current.autosavePhotos,
            autosaveVideos: videos ?? current.autosaveVideos,
            maxVideoFileSize: maxVideoSize ?? current.maxVideoFileSize,
        )
        settings = updated
        if photos != nil || videos != nil { reload() } else { updateVideoFooter() }
        let scope = tdScope
        perform { client in
            _ = try await client.send(TDNativeRequests.setAutosaveSettings(scope: scope, settings: updated))
        }
    }

    /// The slider moves without a reload, which would take the finger off it; only the footer follows.
    private func updateVideoFooter() {
        guard let settings, let footer = tableView.footerView(forSection: sliderSectionIndex) else { return }
        var content = footer.defaultContentConfiguration()
        content.text = L10n.telegram("Autosave.VideoInfo", MediaAutoDownload.sizeString(settings.maxVideoFileSize))
        footer.contentConfiguration = content
    }

    /// Add Exception: a chat of this kind, then its own settings, which become the exception once changed.
    private func addException() {
        guard case .scope(let scope) = target else { return }
        let picker = AutosaveChatPickerViewController(scope: scope, excluded: Set(exceptions.map(\.chatID)))
        picker.onPick = { [weak self, weak picker] chatID, peer in
            guard let self, let picker else { return }
            var controllers = navigationController?.viewControllers ?? []
            controllers.removeAll { $0 === picker }
            controllers.append(AutosaveSettingsViewController(target: .chat(id: chatID, peer: peer)))
            navigationController?.setViewControllers(controllers, animated: true)
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    private func removeException(_ chatID: Int64) {
        exceptions.removeAll { $0.chatID == chatID }
        reload()
        perform { client in
            _ = try await client.send(TDNativeRequests.setAutosaveSettings(
                scope: .autosaveSettingsScopeChat(.init(chatId: chatID)), settings: nil,
            ))
        }
    }

    private func confirmDeleteAll() {
        confirm(message: nil, actionTitle: L10n.telegram("Autosave.DeleteAllExceptions")) { [weak self] in
            guard let self else { return }
            let ids = exceptions.map(\.chatID)
            exceptions = []
            reload()
            perform { client in
                for id in ids {
                    _ = try await client.send(TDNativeRequests.setAutosaveSettings(
                        scope: .autosaveSettingsScopeChat(.init(chatId: id)), settings: nil,
                    ))
                }
            }
        }
    }

    // MARK: Loading

    private func load() {
        guard contextIsCurrent else { return }
        let client = client
        let target = target
        Task { [weak self] in
            guard let all = try? await client.send(TDNativeRequests.getAutosaveSettings()) else { return }
            var settings: TDNativeScopeAutosaveSettings
            var exceptions = [(peer: SettingsPeer, chatID: Int64, settings: TDNativeScopeAutosaveSettings)]()
            switch target {
            case .scope(let scope):
                settings = scope.settings(in: all)
                for exception in all.exceptions {
                    guard let chat = try? await client.getChat(chatId: exception.chatId),
                          AutosaveScope(chatType: chat.type) == scope else { continue }
                    exceptions.append((SettingsPeer(chat: chat), exception.chatId, exception.settings))
                }
            case .chat(let id, _):
                if let exception = all.exceptions.first(where: { $0.chatId == id }) {
                    settings = exception.settings
                } else {
                    // A new exception starts from its kind's settings.
                    let chat = try? await client.getChat(chatId: id)
                    settings = chat.map { AutosaveScope(chatType: $0.type).settings(in: all) } ?? all
                        .privateChatSettings
                }
            }
            guard let self, contextIsCurrent else { return }
            self.settings = settings
            self.exceptions = exceptions
            reload()
        }
    }
}

// MARK: - AutosaveChatPickerViewController

/// Notifications.AddExceptionTitle's chat list for an autosave exception: the main list's chats of the kind, the ones
/// already excepted left out, filtered by the search field.
final class AutosaveChatPickerViewController: SettingsListViewController, UISearchResultsUpdating {
    var onPick: ((Int64, SettingsPeer) -> Void)?

    private let scope: AutosaveScope
    private let excluded: Set<Int64>
    private var chats = [SettingsPeer]()
    private var query = ""
    private let searchController = UISearchController(searchResultsController: nil)

    init(scope: AutosaveScope, excluded: Set<Int64>) {
        self.scope = scope
        self.excluded = excluded
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Notifications.AddExceptionTitle")
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        let mainChats = RootVM.shared
            .folders
            .first { folder in
                if case .main = folder.type {
                    true
                } else {
                    false
                }
            }?.chats ?? []
        chats = mainChats
            .filter {
                !excluded.contains($0.id) && !$0.isSavedMessages && AutosaveScope(chatType: $0.chat.type) == scope
            }
            .map { SettingsPeer(chat: $0.chat) }
        reload()
    }

    override func makeSections() -> [SettingsSection] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = normalized.isEmpty
            ? chats
            : chats.filter { $0.title.localizedCaseInsensitiveContains(normalized) }
        return [SettingsSection(rows: visible.map { peer in
            SettingsRow(title: peer.title, style: .peer(peer)) { [weak self] in self?.onPick?(peer.id, peer) }
        })]
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        reload()
    }
}
