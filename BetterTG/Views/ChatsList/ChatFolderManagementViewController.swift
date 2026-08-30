// ChatFolderManagementViewController.swift

import Combine
import TDLibKitDynamic
import UIKit

// MARK: - ChatFoldersViewController

final class ChatFoldersViewController: UITableViewController {
    // MARK: Private

    private let rootVM: RootVM
    private var cancellables = Set<AnyCancellable>()

    private var customFolders: [CustomFolder] {
        rootVM.folders.filter {
            if case .folder = $0.type {
                return true
            }
            return false
        }
    }

    init(rootVM: RootVM) {
        self.rootVM = rootVM
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Chat Folders"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addFolder),
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FolderCell")
        rootVM.$folders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.tableView.reloadData() }
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func numberOfSections(in _: UITableView) -> Int { 1 }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        customFolders.count
    }

    override func tableView(_: UITableView, titleForFooterInSection _: Int) -> String? {
        customFolders.isEmpty ? "Create folders to keep different kinds of chats together." : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FolderCell", for: indexPath)
        let folder = customFolders[indexPath.row]
        var configuration = cell.defaultContentConfiguration()
        configuration.text = folder.name
        configuration.secondaryText = "\(folder.chats.count) chats"
        configuration.image = UIImage(systemName: "folder.fill")
        configuration.imageProperties.tintColor = .systemBlue
        cell.contentConfiguration = configuration
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(
            ChatFolderEditorViewController(rootVM: rootVM, folder: customFolders[indexPath.row]),
            animated: true,
        )
    }

    override func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath,
    ) -> UISwipeActionsConfiguration? {
        let folder = customFolders[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, complete in
            self?.confirmRemoval(of: folder)
            complete(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }

    @objc private func addFolder() {
        navigationController?.pushViewController(ChatFolderEditorViewController(rootVM: rootVM), animated: true)
    }

    private func confirmRemoval(of folder: CustomFolder) {
        guard case .folder(let info, _) = folder.type else { return }
        let alert = UIAlertController(
            title: "Remove \(folder.name)?",
            message: "The folder will be removed from your account. Its chats won't be deleted or left.",
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            Task { @MainActor [weak self] in
                do {
                    _ = try await td.deleteChatFolder(chatFolderId: info.id, leaveChatIds: [])
                } catch {
                    self?.presentFolderError(error)
                }
            }
        })
        present(alert, animated: true)
    }
}

// MARK: - ChatFolderOrderViewController

final class ChatFolderOrderViewController: UITableViewController {
    // MARK: Private

    private var folders: [CustomFolder]

    init(rootVM: RootVM) {
        self.folders = rootVM.folders
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Reorder Tabs"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(saveOrder),
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FolderOrderCell")
        tableView.setEditing(true, animated: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int { folders.count }

    override func tableView(_: UITableView, titleForFooterInSection _: Int) -> String? {
        "Drag the folders into the order you want to see in the tab bar."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FolderOrderCell", for: indexPath)
        let folder = folders[indexPath.row]
        var configuration = cell.defaultContentConfiguration()
        configuration.text = folder.name
        configuration.image = UIImage(systemName: folder.id == 0 ? "tray.full.fill" : "folder.fill")
        configuration.imageProperties.tintColor = .systemBlue
        cell.contentConfiguration = configuration
        cell.showsReorderControl = true
        cell.selectionStyle = .none
        return cell
    }

    override func tableView(_: UITableView, canMoveRowAt _: IndexPath) -> Bool { true }

    override func tableView(_: UITableView, editingStyleForRowAt _: IndexPath) -> UITableViewCell.EditingStyle {
        .none
    }

    override func tableView(
        _: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath,
    ) {
        let folder = folders.remove(at: sourceIndexPath.row)
        folders.insert(folder, at: destinationIndexPath.row)
    }

    @objc private func saveOrder() {
        navigationItem.rightBarButtonItem?.isEnabled = false
        let folderIDs = folders.compactMap { folder -> Int? in
            if case .folder(let info, _) = folder.type {
                return info.id
            }
            return nil
        }
        let mainPosition = folders.firstIndex(where: { $0.id == 0 }) ?? 0
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await td.reorderChatFolders(
                    chatFolderIds: folderIDs,
                    mainChatListPosition: mainPosition,
                )
                navigationController?.popViewController(animated: true)
            } catch {
                navigationItem.rightBarButtonItem?.isEnabled = true
                presentFolderError(error)
            }
        }
    }
}

// MARK: - ChatFolderEditorViewController

final class ChatFolderEditorViewController: UITableViewController, UITextFieldDelegate {
    // MARK: Private

    private let rootVM: RootVM
    private let folderInfo: ChatFolderInfo?
    private let originalName: ChatFolderName?
    private var draft: ChatFolder
    private lazy var nameField: UITextField = {
        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 190, height: 36))
        field.placeholder = "Folder Name"
        field.textAlignment = .right
        field.returnKeyType = .done
        field.clearButtonMode = .whileEditing
        field.delegate = self
        return field
    }()

    init(rootVM: RootVM, folder: CustomFolder? = nil) {
        self.rootVM = rootVM
        if let folder, case .folder(let info, let definition) = folder.type {
            self.folderInfo = info
            self.originalName = definition.name
            self.draft = definition
        } else {
            self.folderInfo = nil
            self.originalName = nil
            self.draft = ChatFolder.empty
        }
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        title = folderInfo == nil ? "New Folder" : "Edit Folder"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(save),
        )
        nameField.text = draft.name.text.text
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FolderEditorCell")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        tableView.reloadData()
    }

    override func numberOfSections(in _: UITableView) -> Int { Section.allCases.count }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        Section(rawValue: section)?.rows.count ?? 0
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    override func tableView(_: UITableView, titleForFooterInSection section: Int) -> String? {
        guard Section(rawValue: section) == .includedTypes else { return nil }
        return "A chat is included when it matches any selected type or is selected explicitly."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FolderEditorCell", for: indexPath)
        guard let row = Section(rawValue: indexPath.section)?.rows[indexPath.row] else { return cell }
        var configuration = cell.defaultContentConfiguration()
        configuration.text = row.title
        configuration.secondaryText = row.subtitle(for: draft)
        configuration.textProperties.color = .label
        cell.contentConfiguration = configuration
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default

        switch row {
        case .name:
            cell.accessoryView = nameField
            cell.selectionStyle = .none
        case .excludedChats, .includedChats:
            cell.accessoryType = .disclosureIndicator
        case .include(let type):
            cell.accessoryType = draft.includes(type) ? .checkmark : .none
        case .exclude(let type):
            cell.accessoryType = draft.excludes(type) ? .checkmark : .none
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = Section(rawValue: indexPath.section)?.rows[indexPath.row] else { return }
        switch row {
        case .name:
            nameField.becomeFirstResponder()
        case .include(let type):
            draft = draft.replacing(type, included: !draft.includes(type))
            tableView.reloadRows(at: [indexPath], with: .none)
        case .exclude(let type):
            draft = draft.replacing(type, excluded: !draft.excludes(type))
            tableView.reloadRows(at: [indexPath], with: .none)
        case .includedChats:
            selectChats(excluded: false)
        case .excludedChats:
            selectChats(excluded: true)
        }
    }

    func textFieldShouldReturn(_: UITextField) -> Bool {
        save()
        return true
    }

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String,
    ) -> Bool {
        guard !string.contains(where: \.isNewline),
              let current = textField.text,
              let swiftRange = Range(range, in: current)
        else { return false }
        return current.replacingCharacters(in: swiftRange, with: string).count <= 12
    }

    private func selectChats(excluded: Bool) {
        let selected = Set(excluded ? draft.excludedChatIds : draft.includedChatIds)
        let controller = ChatFolderChatSelectionViewController(
            rootVM: rootVM,
            title: excluded ? "Excluded Chats" : "Included Chats",
            selectedChatIDs: selected,
        ) { [weak self] selectedChatIDs in
            guard let self else { return }
            draft = excluded
                ? draft.replacingExcludedChatIDs(selectedChatIDs)
                : draft.replacingIncludedChatIDs(selectedChatIDs)
            tableView.reloadSections(IndexSet(integer: Section.chats.rawValue), with: .none)
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func save() {
        nameField.resignFirstResponder()
        let name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            presentFolderError(message: "Enter a folder name.")
            return
        }
        guard draft.hasIncludedRule else {
            presentFolderError(message: "Choose at least one chat or chat type to include.")
            return
        }

        let updated = draft.replacingName(name, preserving: originalName)
        navigationItem.rightBarButtonItem?.isEnabled = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ =
                    if let folderInfo {
                        try await td.editChatFolder(chatFolderId: folderInfo.id, folder: updated)
                    } else {
                        try await td.createChatFolder(folder: updated)
                    }
                navigationController?.popViewController(animated: true)
            } catch {
                navigationItem.rightBarButtonItem?.isEnabled = true
                presentFolderError(error)
            }
        }
    }
}

// MARK: - ChatFolderChatSelectionViewController

final class ChatFolderChatSelectionViewController: UITableViewController, UISearchResultsUpdating {
    // MARK: Private

    private let rootVM: RootVM
    private let onDone: (Set<Int64>) -> Void
    private let searchController = UISearchController(searchResultsController: nil)
    private var selectedChatIDs: Set<Int64>
    private var chats = [CustomChat]()
    private var visibleChats = [CustomChat]()
    private var query = ""

    init(
        rootVM: RootVM,
        title: String,
        selectedChatIDs: Set<Int64>,
        onDone: @escaping (Set<Int64>) -> Void,
    ) {
        self.rootVM = rootVM
        self.selectedChatIDs = selectedChatIDs
        self.onDone = onDone
        super.init(style: .insetGrouped)
        self.title = title
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(done),
        )
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search Chats"
        navigationItem.searchController = searchController
        definesPresentationContext = true
        reloadCandidates()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int { visibleChats.count }

    override func tableView(_: UITableView, titleForFooterInSection _: Int) -> String? {
        visibleChats.isEmpty ? "No loaded chats match this search." : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "FolderChatCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        let chat = visibleChats[indexPath.row]
        cell.textLabel?.text = chat.displayTitle
        cell.detailTextLabel?.text = chat.folderPickerSubtitle
        cell.accessoryType = selectedChatIDs.contains(chat.id) ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let chatID = visibleChats[indexPath.row].id
        if selectedChatIDs.contains(chatID) {
            selectedChatIDs.remove(chatID)
        } else {
            selectedChatIDs.insert(chatID)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        applyFilter()
    }

    private func reloadCandidates() {
        var seen = Set<Int64>()
        chats = rootVM.allFolders
            .flatMap(\.chats)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        applyFilter()
    }

    private func applyFilter() {
        visibleChats = query.isEmpty
            ? chats
            : chats.filter {
                $0.displayTitle.localizedCaseInsensitiveContains(query)
            }
        tableView.reloadData()
    }

    @objc private func done() {
        onDone(selectedChatIDs)
        navigationController?.popViewController(animated: true)
    }
}

// MARK: - ChatFolderInclusion

enum ChatFolderInclusion: CaseIterable {
    case contacts
    case nonContacts
    case groups
    case channels
    case bots

    // MARK: Internal

    var title: String {
        switch self {
        case .contacts: "Contacts"
        case .nonContacts: "Non-Contacts"
        case .groups: "Groups"
        case .channels: "Channels"
        case .bots: "Bots"
        }
    }
}

// MARK: - ChatFolderExclusion

enum ChatFolderExclusion: CaseIterable {
    case muted
    case read
    case archived

    // MARK: Internal

    var title: String {
        switch self {
        case .muted: "Muted"
        case .read: "Read"
        case .archived: "Archived"
        }
    }
}

extension CustomFolder {
    var hasUnreadChats: Bool {
        chats.contains { $0.unreadCount > 0 || $0.chat.isMarkedAsUnread }
    }

    var areAllChatsMuted: Bool {
        !chats.isEmpty && chats.allSatisfy { $0.chat.notificationSettings.muteFor > 0 }
    }
}

extension ChatFolder {
    static var empty: ChatFolder {
        ChatFolder(
            colorId: -1,
            excludeArchived: false,
            excludeMuted: false,
            excludeRead: false,
            excludedChatIds: [],
            icon: nil,
            includeBots: false,
            includeChannels: false,
            includeContacts: false,
            includeGroups: false,
            includeNonContacts: false,
            includedChatIds: [],
            isShareable: false,
            name: ChatFolderName(
                animateCustomEmoji: false,
                text: FormattedText(entities: [], text: ""),
            ),
            pinnedChatIds: [],
        )
    }

    var hasIncludedRule: Bool {
        includeBots || includeChannels || includeContacts || includeGroups || includeNonContacts || !includedChatIds
            .isEmpty
    }

    func includes(_ type: ChatFolderInclusion) -> Bool {
        switch type {
        case .contacts: includeContacts
        case .nonContacts: includeNonContacts
        case .groups: includeGroups
        case .channels: includeChannels
        case .bots: includeBots
        }
    }

    func excludes(_ type: ChatFolderExclusion) -> Bool {
        switch type {
        case .muted: excludeMuted
        case .read: excludeRead
        case .archived: excludeArchived
        }
    }

    func replacing(_ type: ChatFolderInclusion, included: Bool) -> ChatFolder {
        replacing(
            includeBots: type == .bots ? included : includeBots,
            includeChannels: type == .channels ? included : includeChannels,
            includeContacts: type == .contacts ? included : includeContacts,
            includeGroups: type == .groups ? included : includeGroups,
            includeNonContacts: type == .nonContacts ? included : includeNonContacts,
        )
    }

    func replacing(_ type: ChatFolderExclusion, excluded: Bool) -> ChatFolder {
        replacing(
            excludeArchived: type == .archived ? excluded : excludeArchived,
            excludeMuted: type == .muted ? excluded : excludeMuted,
            excludeRead: type == .read ? excluded : excludeRead,
        )
    }

    func replacingIncludedChatIDs(_ selected: Set<Int64>) -> ChatFolder {
        let retained = includedChatIds.filter(selected.contains)
        let added = selected.subtracting(includedChatIds).sorted()
        return replacing(
            excludedChatIds: excludedChatIds.filter { !selected.contains($0) },
            includedChatIds: retained + added,
        )
    }

    func replacingExcludedChatIDs(_ selected: Set<Int64>) -> ChatFolder {
        let retained = excludedChatIds.filter(selected.contains)
        let added = selected.subtracting(excludedChatIds).sorted()
        return replacing(
            excludedChatIds: retained + added,
            includedChatIds: includedChatIds.filter { !selected.contains($0) },
            pinnedChatIds: pinnedChatIds.filter { !selected.contains($0) },
        )
    }

    func replacingName(_ name: String, preserving originalName: ChatFolderName?) -> ChatFolder {
        let folderName: ChatFolderName =
            if originalName?.text.text == name, let originalName {
                originalName
            } else {
                ChatFolderName(
                    animateCustomEmoji: false,
                    text: FormattedText(entities: [], text: name),
                )
            }
        return replacing(name: folderName)
    }

    private func replacing(
        name: ChatFolderName? = nil,
        excludeArchived: Bool? = nil,
        excludeMuted: Bool? = nil,
        excludeRead: Bool? = nil,
        excludedChatIds: [Int64]? = nil,
        includeBots: Bool? = nil,
        includeChannels: Bool? = nil,
        includeContacts: Bool? = nil,
        includeGroups: Bool? = nil,
        includeNonContacts: Bool? = nil,
        includedChatIds: [Int64]? = nil,
        pinnedChatIds: [Int64]? = nil,
    ) -> ChatFolder {
        ChatFolder(
            colorId: colorId,
            excludeArchived: excludeArchived ?? self.excludeArchived,
            excludeMuted: excludeMuted ?? self.excludeMuted,
            excludeRead: excludeRead ?? self.excludeRead,
            excludedChatIds: excludedChatIds ?? self.excludedChatIds,
            icon: icon,
            includeBots: includeBots ?? self.includeBots,
            includeChannels: includeChannels ?? self.includeChannels,
            includeContacts: includeContacts ?? self.includeContacts,
            includeGroups: includeGroups ?? self.includeGroups,
            includeNonContacts: includeNonContacts ?? self.includeNonContacts,
            includedChatIds: includedChatIds ?? self.includedChatIds,
            isShareable: isShareable,
            name: name ?? self.name,
            pinnedChatIds: pinnedChatIds ?? self.pinnedChatIds,
        )
    }
}

extension ChatNotificationSettings {
    func replacingMuteFor(_ muteFor: Int) -> ChatNotificationSettings {
        ChatNotificationSettings(
            disableMentionNotifications: disableMentionNotifications,
            disablePinnedMessageNotifications: disablePinnedMessageNotifications,
            muteFor: muteFor,
            muteStories: muteStories,
            showPreview: showPreview,
            showStoryPoster: showStoryPoster,
            soundId: soundId,
            storySoundId: storySoundId,
            useDefaultDisableMentionNotifications: useDefaultDisableMentionNotifications,
            useDefaultDisablePinnedMessageNotifications: useDefaultDisablePinnedMessageNotifications,
            useDefaultMuteFor: false,
            useDefaultMuteStories: useDefaultMuteStories,
            useDefaultShowPreview: useDefaultShowPreview,
            useDefaultShowStoryPoster: useDefaultShowStoryPoster,
            useDefaultSound: useDefaultSound,
            useDefaultStorySound: useDefaultStorySound,
        )
    }
}

private extension ChatFolderEditorViewController {
    enum Section: Int, CaseIterable {
        case name
        case includedTypes
        case chats
        case excludedTypes

        // MARK: Internal

        var title: String? {
            switch self {
            case .name: nil
            case .includedTypes: "Included Chat Types"
            case .chats: "Selected Chats"
            case .excludedTypes: "Exclude"
            }
        }

        var rows: [Row] {
            switch self {
            case .name: [.name]
            case .includedTypes: ChatFolderInclusion.allCases.map(Row.include)
            case .chats: [.includedChats, .excludedChats]
            case .excludedTypes: ChatFolderExclusion.allCases.map(Row.exclude)
            }
        }
    }

    enum Row {
        case name
        case include(ChatFolderInclusion)
        case includedChats
        case excludedChats
        case exclude(ChatFolderExclusion)

        // MARK: Internal

        var title: String {
            switch self {
            case .name: "Name"
            case .include(let type): type.title
            case .includedChats: "Always Include"
            case .excludedChats: "Never Include"
            case .exclude(let type): type.title
            }
        }

        func subtitle(for folder: ChatFolder) -> String? {
            switch self {
            case .includedChats: "\(folder.includedChatIds.count) chats"
            case .excludedChats: "\(folder.excludedChatIds.count) chats"
            default: nil
            }
        }
    }
}

private extension CustomChat {
    var folderPickerSubtitle: String {
        switch type {
        case .user: "Contact"
        case .bot: "Bot"
        case .group: "Group"
        case .supergroup(let group): group.isChannel ? "Channel" : "Group"
        }
    }
}

private extension UIViewController {
    func presentFolderError(_ error: any Swift.Error) {
        presentFolderError(message: error.localizedDescription)
    }

    func presentFolderError(message: String) {
        let alert = UIAlertController(title: "Couldn't Update Folder", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
