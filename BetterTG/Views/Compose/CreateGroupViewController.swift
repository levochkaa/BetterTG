// CreateGroupViewController.swift

import TDLibKit
import UIKit

// MARK: - CreateGroupViewController

/// Telegram's CreateGroupController in `.generic` mode: the group's photo and name, its auto-delete timer and the
/// chosen members. Create (on its tap only) makes the basic group (createNewBasicGroupChat), sets the photo and opens
/// the group in place of the compose screens.
final class CreateGroupViewController: SettingsListViewController, ComposeFlowScreen {
    private static let autoDeleteSection = 1

    private let members: [ComposeContact]
    private let photoHeader = ComposePhotoHeaderView(buttonTitle: L10n.telegram("GroupInfo.SetGroupPhoto"))
    private lazy var photoPicker = ComposePhotoPicker(host: self)
    private var groupTitle = ""
    private var titleWasEdited = false
    private var photo: UIImage?
    /// The chosen timer; nil keeps the account's default (getDefaultMessageAutoDeleteTime).
    private var autoDeleteTime: Int?
    private var defaultAutoDeleteTime = 0
    private var isCreating = false
    private var createTask: Task<Void, Never>?

    private var effectiveAutoDeleteTime: Int {
        autoDeleteTime ?? defaultAutoDeleteTime
    }

    init(members: [ComposeContact]) {
        // CreateGroupController lists the members by presence.
        self.members = members.sorted { UserPresenceText.rank($0.status) > UserPresenceText.rank($1.status) }
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        createTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Compose.NewGroupTitle")
        photoHeader.onSetPhoto = { [weak self] source in
            guard let self else { return }
            photoPicker.presentMenu(from: source, hasPhoto: photo != nil)
        }
        photoPicker.onChange = { [weak self] image in
            self?.photo = image
            self?.photoHeader.setPhoto(image)
        }
        photoHeader.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: ComposePhotoHeaderView.height)
        tableView.tableHeaderView = photoHeader
        updateCreateButton()
        loadDefaults()
    }

    override func makeSections() -> [SettingsSection] {
        let autoDelete = effectiveAutoDeleteTime
        var sections = [
            SettingsSection(rows: [SettingsRow(title: "", style: .input(SettingsTextInput(
                text: groupTitle,
                placeholder: L10n.telegram("GroupInfo.GroupNamePlaceholder"),
                maxLength: 128,
            ) { [weak self] text in
                self?.groupTitle = text
                self?.titleWasEdited = true
                self?.updateCreateButton()
            }))]),
            SettingsSection(footer: L10n.telegram("CreateGroup.AutoDeleteText"), rows: [SettingsRow(
                title: L10n.telegram("CreateGroup.AutoDeleteTitle"),
                detail: autoDelete == 0
                    ? L10n.telegram("Autoremove.OptionOff")
                    : SettingsFormatting.timeInterval(seconds: autoDelete),
                accessory: .disclosure,
            ) { [weak self] in self?.presentAutoDeleteMenu() }]),
        ]
        if !members.isEmpty {
            sections.append(SettingsSection(rows: members.map { $0.row(action: nil) }))
        }
        return sections
    }

    /// The errors Telegram names when a group can't be created.
    private static func failureText(_ error: Error) -> String {
        let message = (error as? TDLibError)?.message ?? ""
        if message.contains("USER_PRIVACY_RESTRICTED") || message.contains("USERS_TOO_FEW") {
            return L10n.telegram("Privacy.GroupsAndChannels.InviteToChannelMultipleError")
        }
        if message.contains("RESTRICTED") {
            return L10n.telegram("Common.ActionNotAllowedError")
        }
        return L10n.telegram("Login.UnknownError")
    }

    /// CreateGroup.PeersTitleDelimeter between the names and PeersTitleLastDelimeter before the last.
    private static func joinedNames(_ names: [String]) -> String {
        var title = ""
        for (index, name) in names.enumerated() {
            if index > 0 {
                title += L10n.telegram(
                    index < names.count - 1 ? "CreateGroup.PeersTitleDelimeter" : "CreateGroup.PeersTitleLastDelimeter",
                )
            }
            title += name
        }
        return title
    }

    /// The account's default timer, and Telegram's name from the first names when two to four people are chosen.
    private func loadDefaults() {
        guard contextIsCurrent else { return }
        let client = client
        let members = members
        Task { [weak self] in
            let defaultTime = await (try? client.send(TDNativeRequests.getDefaultMessageAutoDeleteTime()))?.time
            let me = try? await client.getMe()
            guard let self, contextIsCurrent else { return }
            if let defaultTime { defaultAutoDeleteTime = defaultTime }
            if !titleWasEdited, (1...4).contains(members.count) {
                let names = ([me?.firstName ?? ""] + members.map(\.firstName)).filter { !$0.isEmpty }
                if names.count > 1 { groupTitle = Self.joinedNames(names) }
            }
            reload()
            updateCreateButton()
        }
    }

    private func updateCreateButton() {
        guard !isCreating else {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: indicator)
            return
        }
        let button = navigationItem.rightBarButtonItem?.action == #selector(createPressed)
            ? navigationItem.rightBarButtonItem
            : UIBarButtonItem(
                title: L10n.telegram("Compose.Create"),
                style: .prominent,
                target: self,
                action: #selector(createPressed),
            )
        button?.isEnabled = !groupTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        navigationItem.rightBarButtonItem = button
    }

    /// CreateGroupController.updateAutoDelete: Off, a day, a week, a month (and a custom value), or Set Custom Time.
    private func presentAutoDeleteMenu() {
        guard contextIsCurrent,
              let cell = tableView.cellForRow(at: IndexPath(row: 0, section: Self.autoDeleteSection))
        else { return }
        view.endEditing(true)
        let current = effectiveAutoDeleteTime
        let day = 24 * 60 * 60
        var presets = [day, 7 * day, 31 * day]
        if current != 0, !presets.contains(current) {
            presets.append(current)
            presets.sort()
        }
        let check = UIImage(systemName: "checkmark")
        var actions = [TelegramContextMenuAction(
            title: L10n.telegram("Autoremove.OptionOff"),
            image: current == 0 ? check : nil,
        ) { [weak self] in self?.setAutoDelete(0) }]
        for (index, value) in presets.enumerated() {
            actions.append(TelegramContextMenuAction(
                title: SettingsFormatting.timeInterval(seconds: value),
                image: current == value ? check : nil,
                startsNewSection: index == 0,
            ) { [weak self] in self?.setAutoDelete(value) })
        }
        actions.append(TelegramContextMenuAction(title: L10n.telegram("Autoremove.SetCustomTime")) { [weak self] in
            self?.presentCustomAutoDelete(current: current)
        })
        presentTelegramContextMenu(sourceView: cell, actions: actions, presentationStyle: .menuOnly)
    }

    /// ChatTimerScreen in `.autoremove` mode.
    private func presentCustomAutoDelete(current: Int) {
        guard contextIsCurrent, presentedViewController == nil else { return }
        PeerProfileTimerPickerViewController(mode: .autoDelete(
            current: current,
            format: { SettingsFormatting.timeInterval(seconds: $0) },
            onApply: { [weak self] seconds in self?.setAutoDelete(seconds) },
        )).present(from: self)
    }

    private func setAutoDelete(_ seconds: Int) {
        autoDeleteTime = seconds
        reload(sections: IndexSet(integer: Self.autoDeleteSection))
    }

    /// CreateGroupController's done: the group, then its photo, then the chat.
    @objc private func createPressed() {
        let title = groupTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isCreating, contextIsCurrent else { return }
        view.endEditing(true)
        isCreating = true
        photoHeader.setEnabled(false)
        updateCreateButton()
        let client = client
        let userIDs = members.map(\.userID)
        let autoDelete = effectiveAutoDeleteTime
        let photo = photo
        createTask = Task { [weak self] in
            do {
                let created = try await client.send(TDNativeRequests.createNewBasicGroupChat(
                    userIds: userIDs, title: title, messageAutoDeleteTime: autoDelete,
                ))
                if let photo {
                    _ = await ComposePhotoPicker.upload(photo, chatID: created.chatId, client: client)
                }
                let opened = await ComposeContacts.open(chatID: created.chatId, client: client) {
                    self?.contextIsCurrent == true
                }
                guard let self else { return }
                createTask = nil
                // The group exists; without its chat this screen stays, and Create would make another.
                if !opened, contextIsCurrent {
                    NavigationStorage.shared.popToRoot()
                }
            } catch {
                guard let self else { return }
                createTask = nil
                isCreating = false
                photoHeader.setEnabled(true)
                updateCreateButton()
                guard contextIsCurrent else { return }
                presentAlert(title: nil, message: Self.failureText(error))
            }
        }
    }
}
