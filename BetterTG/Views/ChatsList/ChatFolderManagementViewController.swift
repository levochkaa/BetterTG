// ChatFolderManagementViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - ChatFoldersViewController

final class ChatFoldersViewController: UITableViewController {
    // MARK: Private

    private let session: FolderFlowSession
    private var folders: [CustomFolder]
    private var cancellables = Set<AnyCancellable>()
    /// TDLib's chat count for each folder, with the definition it was counted for.
    private var chatCounts = [Int: (definition: ChatFolder, chats: Int)]()
    private var chatCountTasks = [Int: Task<Void, Never>]()

    private var customFolders: [CustomFolder] {
        folders.filter {
            if case .folder = $0.type {
                return true
            }
            return false
        }
    }

    convenience init(rootVM: RootVM, actionAuthority: ChatListActionAuthority? = nil) {
        self.init(session: .live(rootVM: rootVM, authority: actionAuthority))
    }

    init(session: FolderFlowSession) {
        self.session = session
        self.folders = session.folders
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Settings.ChatFolders")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"), style: .plain,
            target: self,
            action: #selector(addFolder),
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = L10n.telegram("ChatListFolder.TitleCreate")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FolderCell")
        session.bind(self) { [weak self] in
            guard let self else { return }
            folders = session.folders
            tableView.reloadData()
            refreshChatCounts()
        }.store(in: &cancellables)
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
        customFolders.isEmpty ? L10n.telegram("ChatListFolderSettings.Info") : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FolderCell", for: indexPath)
        let folder = customFolders[indexPath.row]
        var configuration = cell.defaultContentConfiguration()
        configuration.text = folder.name
        // The loaded rows are only the list's first pages; Telegram shows the folder's whole count, or none for 0.
        configuration.secondaryText = chatCounts[folder.id].flatMap { entry in
            entry.chats > 0
                ? L10n.telegramPlural("GlobalAutodeleteSettings.ApplyChatsSubject", count: entry.chats)
                : nil
        }
        configuration.image = UIImage(systemName: "folder.fill")
        configuration.imageProperties.tintColor = .systemBlue
        cell.contentConfiguration = configuration
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard session.scope(owner: self).isCurrent else { return }
        navigationController?.pushViewController(
            ChatFolderEditorViewController(
                session: session, folder: customFolders[indexPath.row],
            ),
            animated: true,
        )
    }

    override func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath,
    ) -> UISwipeActionsConfiguration? {
        let scope = session.scope(owner: self)
        guard scope.isCurrent else { return nil }
        let folder = customFolders[indexPath.row]
        let delete = UIContextualAction(
            style: .destructive,
            title: L10n.telegram("ChatList.RemoveFolderAction"),
        ) { [weak self] _, _, complete in
            guard scope.isCurrent else {
                complete(false)
                return
            }
            self?.confirmRemoval(of: folder)
            complete(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }

    /// Counts each folder whose definition changed since it was last counted.
    private func refreshChatCounts() {
        guard let reader = session.reader, session.isCurrent else { return }
        for folder in customFolders {
            guard case .folder(_, let definition) = folder.type else { continue }
            let id = folder.id
            if chatCountTasks[id] != nil { continue }
            if let known = chatCounts[id], known.definition.hasSameEditableContent(as: definition) { continue }
            chatCountTasks[id] = Task { [weak self] in
                let count = await reader.chatCount(definition)
                guard let self else { return }
                chatCountTasks[id] = nil
                guard session.isCurrent else { return }
                // A failed count shows none, like an empty folder, until the definition changes.
                chatCounts[id] = (definition, count ?? 0)
                if let row = customFolders.firstIndex(where: { $0.id == id }) {
                    tableView.reloadRows(at: [IndexPath(row: row, section: 0)], with: .none)
                }
                // A definition that changed while it was counted is counted again.
                refreshChatCounts()
            }
        }
    }

    @objc private func addFolder() {
        guard session.scope(owner: self).isCurrent else { return }
        navigationController?.pushViewController(
            ChatFolderEditorViewController(session: session), animated: true,
        )
    }

    private func confirmRemoval(of folder: CustomFolder) {
        let scope = session.scope(owner: self)
        guard scope.isCurrent, case .folder(let info, let definition) = folder.type else { return }
        // The session's endpoint writes on the active client; its scope is current only while that client is.
        ChatFolderRemoval.confirm(
            info: info,
            folder: definition,
            from: self,
            scope: scope,
            client: TDLib.shared.activeClient,
            remove: { [weak self] leaveChatIDs in
                guard let self, scope.isCurrent else { return }
                session.mutate(.delete(info.id, leaveChatIDs: leaveChatIDs), owner: self) { [weak self] result in
                    if case .failure(let error) = result { self?.presentFolderError(error) }
                }
            },
            failure: { [weak self] error in self?.presentFolderError(error) },
        )
    }
}

// MARK: - ChatFolderOrderViewController

final class ChatFolderOrderViewController: UITableViewController {
    // MARK: Private

    private var folders: [CustomFolder]
    private let session: FolderFlowSession
    private var sessionObservation: AnyCancellable?

    convenience init(rootVM: RootVM, actionAuthority: ChatListActionAuthority? = nil) {
        self.init(session: .live(rootVM: rootVM, authority: actionAuthority))
    }

    init(session: FolderFlowSession) {
        self.folders = session.folders
        self.session = session
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("ChatList.ReorderTabs")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Done"), style: .plain,
            target: self,
            action: #selector(saveOrder),
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = L10n.telegram("Common.Done")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FolderOrderCell")
        tableView.setEditing(true, animated: false)
        sessionObservation = session.bind(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int { folders.count }

    override func tableView(_: UITableView, titleForFooterInSection _: Int) -> String? {
        L10n.betterTG("Folders.ReorderInfo")
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

    override func tableView(_: UITableView, canMoveRowAt _: IndexPath) -> Bool { session.isCurrent }

    override func tableView(_: UITableView, editingStyleForRowAt _: IndexPath) -> UITableViewCell.EditingStyle {
        .none
    }

    override func tableView(_: UITableView, shouldIndentWhileEditingRowAt _: IndexPath) -> Bool {
        false
    }

    override func tableView(
        _: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath,
    ) {
        guard session.scope(owner: self).isCurrent else { return }
        let folder = folders.remove(at: sourceIndexPath.row)
        folders.insert(folder, at: destinationIndexPath.row)
    }

    @objc private func saveOrder() {
        let scope = session.scope(owner: self)
        guard scope.isCurrent else { return }
        let folderIDs = folders.compactMap { folder -> Int? in
            if case .folder(let info, _) = folder.type {
                return info.id
            }
            return nil
        }
        let mainPosition = folders.firstIndex(where: { $0.id == 0 }) ?? 0
        session.mutate(.reorder(folderIDs, mainPosition), owner: self) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                navigationController?.popViewController(animated: true)
            case .failure(let error):
                presentFolderError(error)
            }
        }
    }
}

// MARK: - ChatFolderEditorViewController

final class ChatFolderEditorViewController: UITableViewController, UITextFieldDelegate,
    TelegramNavigationAttemptHandling
{
    // MARK: Private

    private let session: FolderFlowSession
    private var sessionObservation: AnyCancellable?
    private weak var activeSelection: ChatFolderChatSelectionViewController?
    private let folderInfo: ChatFolderInfo?
    private let originalName: ChatFolderName?
    private var draft: ChatFolder
    /// The name this new folder was last given automatically; the user's own text in the field stops the naming.
    private var automaticName = ""
    private lazy var nameField: UITextField = {
        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 190, height: 36))
        field.placeholder = L10n.telegram("ChatListFolder.NamePlaceholder")
        field.textAlignment = .right
        field.returnKeyType = .done
        field.clearButtonMode = .whileEditing
        field.delegate = self
        return field
    }()

    /// ChatListFilterPresetController: a folder shared by link has no chat types or exclusions, so it shows only
    /// its name and chosen chats.
    private var sections: [Section] {
        draft.isShareable ? [.name, .chats] : Section.allCases
    }

    convenience init(rootVM: RootVM, folder: CustomFolder? = nil, actionAuthority: ChatListActionAuthority? = nil) {
        self.init(session: .live(rootVM: rootVM, authority: actionAuthority), folder: folder)
    }

    init(session: FolderFlowSession, folder: CustomFolder? = nil) {
        self.session = session
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
        title = folderInfo == nil
            ? L10n.telegram("ChatListFolder.TitleCreate")
            : L10n.telegram("ChatListFolder.TitleEdit")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Save"), style: .plain,
            target: self,
            action: #selector(save),
        )
        nameField.text = draft.name.text.text
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FolderEditorCell")
        sessionObservation = session.bind(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        tableView.reloadData()
    }

    override func numberOfSections(in _: UITableView) -> Int { sections.count }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows(shareable: draft.isShareable).count
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(_: UITableView, titleForFooterInSection section: Int) -> String? {
        guard sections[section] == (draft.isShareable ? .chats : .includedTypes) else { return nil }
        return L10n.telegram("ChatListFolder.IncludeSectionInfo")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FolderEditorCell", for: indexPath)
        let row = editorRow(at: indexPath)
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
        guard session.scope(owner: self).isCurrent else { return }
        switch editorRow(at: indexPath) {
        case .name:
            nameField.becomeFirstResponder()
        case .include(let type):
            draft = draft.replacing(type, included: !draft.includes(type))
            tableView.reloadRows(at: [indexPath], with: .none)
            updateAutomaticName()
        case .exclude(let type):
            draft = draft.replacing(type, excluded: !draft.excludes(type))
            tableView.reloadRows(at: [indexPath], with: .none)
            updateAutomaticName()
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

    /// ChatListFilterPresetController's attemptNavigation: Back from an existing folder whose draft differs from the
    /// folder as it is now asks to save or discard. A new folder leaves without asking, as in Telegram.
    func attemptNavigation() -> Bool {
        guard let folderInfo,
              case .folder(_, let current) = session.folders.first(where: { $0.id == Int(folderInfo.id) })?.type
        else { return true }
        let name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !draft.replacingName(name, preserving: originalName).hasSameEditableContent(as: current) else {
            return true
        }
        guard presentedViewController == nil else { return false }
        nameField.resignFirstResponder()
        let alert = UIAlertController(
            title: nil,
            message: L10n.telegram("ChatListFolder.DiscardConfirmation"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("ChatListFolder.DiscardDiscard"), style: .default) {
            [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        let saveAction = UIAlertAction(title: L10n.telegram("ChatListFilter.SaveAlertActionSave"), style: .default) {
            [weak self] _ in
            self?.save()
        }
        alert.addAction(saveAction)
        alert.preferredAction = saveAction
        present(alert, animated: true)
        return false
    }

    private func editorRow(at indexPath: IndexPath) -> Row {
        sections[indexPath.section].rows(shareable: draft.isShareable)[indexPath.row]
    }

    /// ChatListFilterPresetController: until the user edits it, a new folder is named after its one chosen chat
    /// type, or Unread or Not Muted for all chats without read or muted ones (chatListFilterType).
    private func updateAutomaticName() {
        guard folderInfo == nil, (nameField.text ?? "") == automaticName else { return }
        automaticName = draft.automaticName ?? ""
        nameField.text = automaticName
    }

    private func selectChats(excluded: Bool) {
        let scope = session.scope(owner: self)
        guard scope.isCurrent else { return }
        let selected = Set(excluded ? draft.excludedChatIds : draft.alwaysIncludedChatIDs)
        let controller = ChatFolderChatSelectionViewController(
            session: session,
            title: excluded
                ? L10n.telegram("ChatListFolder.ExcludeChatsTitle")
                : L10n.telegram("ChatListFolder.IncludeChatsTitle"),
            selectedChatIDs: selected,
        ) { [weak self] selection, selectedChatIDs in
            guard let self, activeSelection === selection, session.scope(owner: self).isCurrent else { return false }
            draft = excluded
                ? draft.replacingExcludedChatIDs(selectedChatIDs)
                : draft.replacingIncludedChatIDs(selectedChatIDs)
            if let section = sections.firstIndex(of: .chats) {
                tableView.reloadSections(IndexSet(integer: section), with: .none)
            }
            return true
        }
        activeSelection = controller
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func save() {
        let scope = session.scope(owner: self)
        guard scope.isCurrent else { return }
        nameField.resignFirstResponder()
        let name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            presentFolderError(message: L10n.betterTG("Folders.EnterNameError"))
            return
        }
        // ChatListFilterPresetControllerState.isComplete: an existing folder needs only its name.
        guard folderInfo != nil || draft.hasIncludedRule else {
            presentFolderError(message: L10n.betterTG("Folders.SelectIncludeError"))
            return
        }

        let updated = draft.replacingName(name, preserving: originalName)
        let folderID = folderInfo?.id
        let mutation: FolderFlowSession.Mutation = folderID.map { .edit($0, updated) } ?? .create(updated)
        session.mutate(mutation, owner: self) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                navigationController?.popViewController(animated: true)
            case .failure(let error):
                presentFolderError(error)
            }
        }
    }
}

// MARK: - ChatFolderChatSelectionViewController

final class ChatFolderChatSelectionViewController: UITableViewController, UISearchResultsUpdating,
TelegramNavigationSearchProvider {
    private struct CandidatePresentation: Equatable {
        let title: String
        let subtitle: String?
    }

    #if DEBUG
        private(set) var candidatePresentationReloadsForProbe = 0
    #endif

    // MARK: Private

    private let session: FolderFlowSession
    private var sessionObservation: AnyCancellable?
    private let onDone: (ChatFolderChatSelectionViewController, Set<Int64>) -> Bool
    private var candidateObservation: AnyCancellable?
    private var candidateFolderObservation: AnyCancellable?
    private var candidateGeneration = UUID()
    private var candidatePresentation = [Int64: CandidatePresentation]()
    private var candidateOrder = [Int64]()
    /// Which chat list each candidate was taken from: main list, other folders, then archive.
    private var candidateListRanks = [Int64: Int]()
    private let searchController = UISearchController(searchResultsController: nil)
    private var selectedChatIDs: Set<Int64>
    /// TDLib's per-folder limit for the chats this picker chooses; unknown until the option is read.
    private var chosenChatLimit: Int?
    private var chats = [CustomChat]()
    private var visibleChats = [CustomChat]()
    private var query = ""

    var telegramNavigationSearch: UISearchController { searchController }

    init(
        session: FolderFlowSession,
        title: String,
        selectedChatIDs: Set<Int64>,
        onDone: @escaping (ChatFolderChatSelectionViewController, Set<Int64>) -> Bool,
    ) {
        self.session = session
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
            title: L10n.telegram("Common.Done"), style: .plain,
            target: self,
            action: #selector(done),
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = L10n.telegram("Common.Done")
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = L10n.telegram("ChatListFilter.AddChatsSearchPlaceholder")
        definesPresentationContext = true
        sessionObservation = session.bind(self) { [weak self] in self?.reloadCandidates() }
        loadChosenChatLimit()
    }

    #if DEBUG
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-folder-selector-content"),
                  view.window != nil, session.isCurrent else { return }
            let empty = visibleChats.filter(\.chat.title.isEmpty)
            let cells = tableView.visibleCells
            let mismatches = cells.filter { cell in
                guard let index = tableView.indexPath(for: cell), visibleChats.indices.contains(index.row)
                else { return true }
                return (cell.textLabel?.text ?? "") != visibleChats[index.row].folderPickerTitle
            }
.count
            let result = "Folder selector diagnostic: candidates=\(chats.count); filtered=\(visibleChats.count); "
                + "empty-raw-title=\(empty.count); empty-deleted=\(empty.filter { $0.user?.type == .userTypeDeleted }.count); "
                + "empty-unknown=\(empty.filter { $0.user?.type == .userTypeUnknown }.count); "
                + "empty-non-contact=\(empty.filter { $0.user?.isContact == false }.count); "
                + "visible-cells=\(cells.count); empty-cell-text=\(cells.filter { $0.textLabel?.text?.isEmpty != false }.count); "
                + "cell-display-mismatches=\(mismatches); names/IDs/query/payload-logged=false"
            log(result)
            if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: documents.appendingPathComponent("folder-selector-content-probe.txt"), options: .atomic,
                )
            }
        }
    #endif

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        reloadCandidates()
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int { visibleChats.count }

    override func tableView(_: UITableView, titleForFooterInSection _: Int) -> String? {
        visibleChats.isEmpty ? L10n.betterTG("Folders.EmptySearch") : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "FolderChatCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        configurePickerCell(cell, chat: visibleChats[indexPath.row])
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard session.scope(owner: self).isCurrent else { return }
        let chat = visibleChats[indexPath.row]
        let chatID = chat.id
        if selectedChatIDs.contains(chatID) {
            selectedChatIDs.remove(chatID)
        } else {
            if let limit = chosenChatLimit, chosenCount(secret: chat.secretChatID != nil) >= limit {
                presentChosenChatLimit(limit)
                return
            }
            selectedChatIDs.insert(chatID)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    func configurePickerCell(_ cell: UITableViewCell, chat: CustomChat) {
        cell.textLabel?.text = chat.folderPickerTitle
        cell.detailTextLabel?.text = chat.folderPickerSubtitle
        cell.accessoryType = selectedChatIDs.contains(chat.id) ? .checkmark : .none
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        applyFilter()
    }

    func submitFolderEdit(id: Int, folder: ChatFolder) {
        session.mutate(.edit(id, folder), owner: self) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success: navigationController?.popViewController(animated: true)
            case .failure(let error): presentFolderError(error)
            }
        }
    }

    private func loadChosenChatLimit() {
        guard let reader = session.reader else { return }
        Task { [weak self] in
            let limit = await reader.chosenChatLimit()
            guard let self, session.isCurrent else { return }
            chosenChatLimit = limit
        }
    }

    /// TDLib counts non-secret and secret chats against the limit separately. A selected chat the picker has not
    /// loaded counts as non-secret.
    private func chosenCount(secret: Bool) -> Int {
        let secretIDs = Set(chats.lazy.filter { $0.secretChatID != nil }.map(\.id))
        return selectedChatIDs.filter { secretIDs.contains($0) == secret }.count
    }

    /// Telegram's limit screen without its Premium offer: the selection stops at TDLib's limit.
    private func presentChosenChatLimit(_ limit: Int) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: L10n.telegram("Premium.LimitReached"),
            message: L10n.telegram("Premium.MaxChatsInFolderFinalText", "\(limit)").withoutTelegramMarkup,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        present(alert, animated: true)
    }

    private func reloadCandidates() {
        guard session.isCurrent else { return }
        let folders = session.allFolders
        // Telegram's add-chats picker is the root chat list (ChatListNode, groupId .root), so candidates follow
        // the main list first. Chats reachable only through other folders or the archive come after it.
        let ranked = folders.enumerated().sorted { lhs, rhs in
            lhs.element.candidateListRank == rhs.element.candidateListRank
                ? lhs.offset < rhs.offset
                : lhs.element.candidateListRank < rhs.element.candidateListRank
        }
        var seen = Set<Int64>()
        var ranks = [Int64: Int]()
        chats = ranked.flatMap { _, folder in
            folder.chats.filter { chat in
                guard seen.insert(chat.id).inserted else { return false }
                ranks[chat.id] = folder.candidateListRank
                return true
            }
        }
        candidateListRanks = ranks
        let generation = UUID()
        candidateGeneration = generation
        let scope = session.scope(owner: self)
        candidateFolderObservation = Publishers.MergeMany(folders.map(\.objectWillChange))
            .receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] in
                guard let self, candidateGeneration == generation, scope.isCurrent else { return }
                reloadCandidates()
            }
        candidateObservation = Publishers.MergeMany(chats.map(\.objectWillChange))
            .receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] in
                guard let self, candidateGeneration == generation, scope.isCurrent else { return }
                sortAndFilterCandidates()
            }
        sortAndFilterCandidates()
    }

    private func sortAndFilterCandidates() {
        let presentation = Dictionary(uniqueKeysWithValues: chats.map {
            ($0.id, CandidatePresentation(title: $0.folderPickerTitle, subtitle: $0.folderPickerSubtitle))
        })
        guard presentation != candidatePresentation else {
            // Position-only changes keep the open selector's rows in place while chats are being picked.
            let byID = Dictionary(uniqueKeysWithValues: chats.map { ($0.id, $0) })
            chats = candidateOrder.compactMap { byID[$0] }
            applyFilter(reload: false)
            return
        }
        let ranks = candidateListRanks
        chats.sort { lhs, rhs in
            let lhsRank = ranks[lhs.id] ?? .max
            let rhsRank = ranks[rhs.id] ?? .max
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.position.order != rhs.position.order { return lhs.position.order > rhs.position.order }
            return lhs.id < rhs.id
        }
        candidatePresentation = presentation
        candidateOrder = chats.map(\.id)
        #if DEBUG
            candidatePresentationReloadsForProbe += 1
        #endif
        applyFilter()
    }

    private func applyFilter(reload: Bool = true) {
        visibleChats = query.isEmpty
            ? chats
            : chats.filter {
                $0.folderPickerTitle.localizedCaseInsensitiveContains(query)
            }
        if reload { tableView.reloadData() }
    }

    @objc private func done() {
        let scope = session.scope(owner: self)
        guard scope.isCurrent else { return }
        guard onDone(self, selectedChatIDs), scope.isCurrent else { return }
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
        case .contacts: L10n.telegram("ChatListFolder.CategoryContacts")
        case .nonContacts: L10n.telegram("ChatListFolder.CategoryNonContacts")
        case .groups: L10n.telegram("ChatListFolder.CategoryGroups")
        case .channels: L10n.telegram("ChatListFolder.CategoryChannels")
        case .bots: L10n.telegram("ChatListFolder.CategoryBots")
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
        case .muted: L10n.telegram("ChatListFolder.CategoryMuted")
        case .read: L10n.telegram("ChatListFolder.CategoryRead")
        case .archived: L10n.telegram("ChatListFolder.CategoryArchived")
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
        includeBots || includeChannels || includeContacts || includeGroups || includeNonContacts
            || !alwaysIncludedChatIDs.isEmpty
    }

    /// Telegram's includePeers.peers: the folder's pinned chats, then its other always included chats.
    var alwaysIncludedChatIDs: [Int64] {
        pinnedChatIds + includedChatIds.filter { !pinnedChatIds.contains($0) }
    }

    /// The fields the folder editor changes. Pinned and included chats compare as one list, as Telegram's
    /// attemptNavigation compares includePeers.peers.
    func hasSameEditableContent(as other: ChatFolder) -> Bool {
        name.text == other.name.text && name.animateCustomEmoji == other.name.animateCustomEmoji
            && includeContacts == other.includeContacts && includeNonContacts == other.includeNonContacts
            && includeGroups == other.includeGroups && includeChannels == other.includeChannels
            && includeBots == other.includeBots && excludeMuted == other.excludeMuted
            && excludeRead == other.excludeRead && excludeArchived == other.excludeArchived
            && alwaysIncludedChatIDs == other.alwaysIncludedChatIDs && excludedChatIds == other.excludedChatIds
    }

    /// Telegram's chatListFilterType names: one chat type, or all types without read or muted chats; nil otherwise.
    var automaticName: String? {
        let types = ChatFolderInclusion.allCases.filter(includes)
        if types.count == ChatFolderInclusion.allCases.count {
            if excludeRead { return L10n.telegram("ChatListFolder.NameUnread") }
            if excludeMuted { return L10n.telegram("ChatListFolder.NameNonMuted") }
            return nil
        }
        guard types.count == 1, let type = types.first else { return nil }
        return switch type {
        case .contacts: L10n.telegram("ChatListFolder.NameContacts")
        case .nonContacts: L10n.telegram("ChatListFolder.NameNonContacts")
        case .groups: L10n.telegram("ChatListFolder.NameGroups")
        case .channels: L10n.telegram("ChatListFolder.NameChannels")
        case .bots: L10n.telegram("ChatListFolder.NameBots")
        }
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
        // A chat that stays selected keeps its pin and place; a deselected pinned chat leaves the folder.
        let pinned = pinnedChatIds.filter(selected.contains)
        let retained = includedChatIds.filter { selected.contains($0) && !pinned.contains($0) }
        let added = selected.subtracting(pinnedChatIds).subtracting(includedChatIds).sorted()
        return replacing(
            excludedChatIds: excludedChatIds.filter { !selected.contains($0) },
            includedChatIds: retained + added,
            pinnedChatIds: pinned,
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

    /// The renamed folder keeps the custom emoji its edited name still contains: emoji in the unchanged start or end
    /// of the text keep their place, those in the edited part go. The name's animation flag stays.
    func replacingName(_ name: String, preserving originalName: ChatFolderName?) -> ChatFolder {
        guard let originalName else {
            return replacing(name: ChatFolderName(
                animateCustomEmoji: self.name.animateCustomEmoji,
                text: FormattedText(entities: [], text: name),
            ))
        }
        let old = originalName.text.text as NSString
        let new = name as NSString
        let shorter = min(old.length, new.length)
        var prefix = 0
        while prefix < shorter, old.character(at: prefix) == new.character(at: prefix) {
            prefix += 1
        }
        var suffix = 0
        while suffix < shorter - prefix,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix)
        {
            suffix += 1
        }
        let shift = new.length - old.length
        let entities = originalName.text.entities.compactMap { entity -> TextEntity? in
            if entity.offset + entity.length <= prefix { return entity }
            guard entity.offset >= old.length - suffix else { return nil }
            return TextEntity(length: entity.length, offset: entity.offset + shift, type: entity.type)
        }
        return replacing(name: ChatFolderName(
            animateCustomEmoji: originalName.animateCustomEmoji,
            text: FormattedText(entities: entities, text: name),
        ))
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
            case .includedTypes: L10n.betterTG("Folders.IncludedTypes")
            case .chats: L10n.betterTG("Folders.SelectedChats")
            case .excludedTypes: L10n.betterTG("Folders.Exclude")
            }
        }

        func rows(shareable: Bool) -> [Row] {
            switch self {
            case .name: [.name]
            case .includedTypes: ChatFolderInclusion.allCases.map(Row.include)
            case .chats: shareable ? [.includedChats] : [.includedChats, .excludedChats]
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
            case .name: L10n.telegram("ChatListFolder.NameSectionHeader")
            case .include(let type): type.title
            case .includedChats: L10n.betterTG("Folders.AlwaysInclude")
            case .excludedChats: L10n.betterTG("Folders.NeverInclude")
            case .exclude(let type): type.title
            }
        }

        func subtitle(for folder: ChatFolder) -> String? {
            switch self {
            case .includedChats:
                L10n.telegramPlural(
                    "GlobalAutodeleteSettings.ApplyChatsSubject",
                    count: folder.alwaysIncludedChatIDs.count,
                )
            case .excludedChats:
                L10n.telegramPlural(
                    "GlobalAutodeleteSettings.ApplyChatsSubject",
                    count: folder.excludedChatIds.count,
                )
            default: nil
            }
        }
    }
}

private extension CustomFolder {
    var candidateListRank: Int {
        switch type {
        case .main: 0
        case .folder: 1
        case .archive: 2
        }
    }
}

private extension CustomChat {
    var folderPickerTitle: String {
        // displayTitle already turns an empty title into Deleted Account; check TDLib's raw title so the
        // username, phone and type fallbacks below stay reachable.
        if isSavedMessages || !chat.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty { return displayTitle }
        switch type {
        case .bot(let user), .user(let user):
            switch user.type {
            case .userTypeDeleted: return L10n.telegram("User.DeletedAccount")
            case .userTypeUnknown: return L10n.betterTG("Folders.UnknownUser")
            default: break
            }
            let name = [user.firstName, user.lastName]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !name.isEmpty { return name }
            if let username = user.usernames?.activeUsernames.first, !username.isEmpty { return "@" + username }
            if !user.phoneNumber.isEmpty { return user.phoneNumber }
            if case .bot = type { return L10n.betterTG("Folders.UntitledBot") }
            return L10n.betterTG("Folders.UntitledUser")
        case .group: return L10n.betterTG("Folders.UntitledGroup")
        case .supergroup(let group): return group.isChannel
            ? L10n.betterTG("Folders.UntitledChannel")
            : L10n.betterTG("Folders.UntitledGroup")
        }
    }

    var folderPickerSubtitle: String? {
        switch type {
        case .user(let user):
            switch user.type {
            case .userTypeDeleted, .userTypeUnknown: nil
            default: user.isContact
                ? L10n.telegram("ChatList.PeerTypeContact")
                : L10n.telegram("ChatList.PeerTypeNonContact")
            }
        case .bot: L10n.telegram("ChatList.PeerTypeBot")
        case .group: L10n.telegram("ChatList.PeerTypeGroup")
        case .supergroup(let group):
            group.isChannel
                ? L10n.telegram("ChatList.PeerTypeChannel")
                : L10n.telegram("ChatList.PeerTypeGroup")
        }
    }
}

private extension UIViewController {
    func presentFolderError(_ error: any Swift.Error) {
        presentFolderError(message: error.localizedDescription)
    }

    func presentFolderError(message: String) {
        let alert = UIAlertController(
            title: L10n.betterTG("Folders.UpdateError"),
            message: message,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        present(alert, animated: true)
    }
}
