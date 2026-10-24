// ChecklistComposerViewController.swift

import TDLibKit
import UIKit

// MARK: - ChecklistEditorOutcome

/// What the checklist editor sends: a new checklist or an edited one in place of the published, or tasks added after
/// the published ones with the whole checklist for a chat that only takes an edit.
enum ChecklistEditorOutcome {
    case checklist(TDNativeInputChecklist)
    case addedTasks([TDNativeInputChecklistTask], checklist: TDNativeInputChecklist)
}

// MARK: - ChecklistComposerViewController

/// ComposeTodoScreen: the checklist's title, its tasks and, while the checklist may be edited, whether others may mark
/// tasks as done and add tasks. A new checklist starts with two empty tasks and both settings on. A published one
/// opens on a task to edit it (Edit Checklist), or after its tasks to add some (Add a Task), where only the new tasks
/// may change unless the checklist may be edited. Fields keep their formatting and custom emoji, a filled task moves
/// by its handle, and text pasted with line breaks becomes one task per line.
@MainActor final class ChecklistComposerViewController: UITableViewController, UITableViewDragDelegate,
    UITableViewDropDelegate, UIAdaptivePresentationControllerDelegate
{
    /// ComposeTodoScreen.InitialData for a published checklist.
    struct Existing {
        let checklist: TDNativeChecklist
        /// The task the screen opens on (`focusedId`).
        var focusedTaskID: Int?
        /// Add a Task: the screen opens on the empty task after the list (`append`).
        var appends = false
        /// Whether the checklist may be edited (`canEdit`); without it only new tasks may change and the settings
        /// hide.
        var canEdit = false
    }

    private enum Section {
        case title
        case tasks
        case settings
    }

    private enum SettingsItem {
        case othersCanMarkAsDone
        case othersCanAddTasks
    }

    private enum Field: Equatable {
        case title
        case task(Int)
    }

    private struct DraftTask {
        let id: Int
        var text = NSAttributedString()
        /// A published task the screen may not change.
        var isLocked = false

        var isEmpty: Bool {
            text.string.isEmpty
        }
    }

    private static let footerIdentifier = "ChecklistComposerFooter"

    // MARK: Internal

    /// Called once the screen has gone, whether it sent the checklist or not.
    var onDismiss: (() -> Void)?

    private let client: TDLibClient
    private let accountID: UUID?
    private let chatID: Int64
    private let existing: Existing?
    private let completion: (ChecklistEditorOutcome) -> Void
    /// ComposeTodoScreen.initialData's limits: 32 characters for the title, 64 for a task and 30 tasks, which TDLib
    /// reports as `checklist_title_length_max`, `checklist_task_text_length_max` and `checklist_task_count_max`.
    private var titleLengthLimit = 32
    private var taskLengthLimit = 64
    private var maximumTaskCount = 30
    private var checklistTitle = NSAttributedString()
    private var tasks = [DraftTask]()
    private var nextTaskID = 1
    private var editingTaskID: Int?
    private var othersCanMarkAsDone = true
    private var othersCanAddTasks = true
    /// The published checklist as the editor sends it, to tell an edit from added tasks.
    private var initialChecklist: TDNativeInputChecklist?
    /// The field the open emoji picker inserts into. A task being filled from it stays while its field is covered.
    private var emojiPickerField: Field?
    private var emojiPickerObserver: SheetDismissObserver?
    private var didFocusInitialTask = false
    private var didSend = false

    private var canEdit: Bool {
        existing?.canEdit ?? true
    }

    private var sections: [Section] {
        canEdit ? [.title, .tasks, .settings] : [.title, .tasks]
    }

    /// Allow Others to Add Tasks shows while others may mark tasks as done.
    private var settingsItems: [SettingsItem] {
        othersCanMarkAsDone ? [.othersCanMarkAsDone, .othersCanAddTasks] : [.othersCanMarkAsDone]
    }

    /// The rows a filled task may move among: the tasks that may change, but an empty last one.
    private var reorderableTaskRange: Range<Int> {
        let start = tasks.firstIndex { !$0.isLocked } ?? tasks.count
        let end = tasks.last?.isEmpty == true ? tasks.count - 1 : tasks.count
        return start..<max(start, end)
    }

    private var tasksFooterText: String {
        if tasks.count >= maximumTaskCount { return L10n.telegram("CreateTodo.TaskCountLimitReached") }
        let remaining = maximumTaskCount - tasks.count
        return L10n.telegramPlural("CreateTodo.TaskCountFooterFormat", count: remaining)
            .replacing("{count}", with: "\(remaining)")
    }

    /// ComposeTodoScreen's validatedInput: a title and at least one task with more than spaces; others may add tasks
    /// only while they may mark them as done.
    private var validatedChecklist: TDNativeInputChecklist? {
        guard !checklistTitle.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let inputTasks = tasks.compactMap { task -> TDNativeInputChecklistTask? in
            guard !task.text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return TDNativeInputChecklistTask(id: task.id, text: ComposerText.formatted(task.text))
        }
        guard !inputTasks.isEmpty else { return nil }
        return TDNativeInputChecklist(
            title: ComposerText.formatted(checklistTitle),
            tasks: inputTasks,
            othersCanAddTasks: othersCanMarkAsDone && othersCanAddTasks,
            othersCanMarkTasksAsDone: othersCanMarkAsDone,
        )
    }

    /// requestDismiss asks before a new checklist that could be sent goes; an edit closes at once.
    private var asksBeforeDiscarding: Bool {
        existing == nil && !didSend && validatedChecklist != nil
    }

    /// - Parameters:
    ///   - accountID: The account whose emoji the picker offers; without one the fields take only the keyboard's
    ///     emoji.
    ///   - chatID: The chat the checklist is in; Saved Messages takes custom emoji without Premium.
    ///   - existing: The published checklist to edit or add tasks to; nil for a new one.
    ///   - completion: Called with what to send once the screen has been dismissed.
    init(
        client: TDLibClient,
        accountID: UUID?,
        chatID: Int64,
        existing: Existing? = nil,
        completion: @escaping (ChecklistEditorOutcome) -> Void,
    ) {
        self.client = client
        self.accountID = accountID
        self.chatID = chatID
        self.existing = existing
        self.completion = completion
        super.init(style: .insetGrouped)
        if let existing {
            let list = existing.checklist
            self.checklistTitle = Self.fieldText(list.title)
            self.tasks = list.tasks.map { task in
                DraftTask(id: task.id, text: Self.fieldText(task.text), isLocked: !existing.canEdit)
            }
            self.nextTaskID = (list.tasks.map(\.id).max() ?? 0) + 1
            self.othersCanAddTasks = list.othersCanAddTasks
            self.othersCanMarkAsDone = list.othersCanMarkTasksAsDone
            self.initialChecklist = validatedChecklist
        } else {
            self.tasks = [DraftTask(id: 1), DraftTask(id: 2)]
            self.nextTaskID = 3
        }
        normalizeTasks()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let titleKey =
            if existing == nil {
                "CreateTodo.Title"
            } else {
                canEdit ? "CreateTodo.EditTitle" : "CreateTodo.AddTitle"
            }
        title = L10n.telegram(titleKey)
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"),
            style: .plain,
            target: self,
            action: #selector(cancelPressed),
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram(existing == nil ? "CreateTodo.Send" : "CreateTodo.Save"),
            style: .prominent,
            target: self,
            action: #selector(sendPressed),
        )
        tableView.backgroundColor = .systemGroupedBackground
        tableView.keyboardDismissMode = .interactive
        tableView.register(CreatePollTextCell.self, forCellReuseIdentifier: CreatePollTextCell.reuseIdentifier)
        tableView.register(CreatePollToggleCell.self, forCellReuseIdentifier: CreatePollToggleCell.reuseIdentifier)
        tableView.register(UITableViewHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: Self.footerIdentifier)
        tableView.dragDelegate = self
        tableView.dropDelegate = self
        tableView.dragInteractionEnabled = true
        updateSendButton()
        loadLimits()
    }

    /// ComposeTodoScreen activates the focused task, or with append the empty task after the list.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didFocusInitialTask else { return }
        didFocusInitialTask = true
        var row: Int?
        if let id = existing?.focusedTaskID {
            row = tasks.firstIndex { $0.id == id }
        } else if existing?.appends == true {
            row = tasks.indices.last
        }
        guard let row, let section = sections.firstIndex(of: .tasks) else { return }
        focusRow(at: IndexPath(row: row, section: section))
    }

    // MARK: Table

    override func numberOfSections(in _: UITableView) -> Int {
        sections.count
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .title: 1
        case .tasks: tasks.count
        case .settings: settingsItems.count
        }
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sections[section] {
        case .title: nil
        case .tasks: L10n.telegram("CreateTodo.TodoTitle")
        case .settings: L10n.telegram("CreatePoll.SettingsTitle")
        }
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard sections[section] == .tasks,
              let footer = tableView.dequeueReusableHeaderFooterView(withIdentifier: Self.footerIdentifier)
        else { return nil }
        configureFooter(footer)
        return footer
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section] {
        case .title:
            let cell = textCell(tableView, at: indexPath, field: .title)
            cell.configure(titleConfiguration())
            cell.onTextChange = { [weak self] in self?.titleChanged($0) }
            cell.onReturn = { [weak self] in self?.focusFirstTask() }
            return cell
        case .tasks:
            guard let task = tasks[safe: indexPath.row] else {
                return textCell(tableView, at: indexPath, field: nil)
            }
            let id = task.id
            let cell = textCell(tableView, at: indexPath, field: .task(id))
            cell.configure(taskConfiguration(at: indexPath.row))
            cell.onTextChange = { [weak self] in self?.taskTextChanged(id: id, text: $0) }
            cell.onReturn = { [weak self] in self?.taskReturnPressed(id: id) }
            cell.onDeleteBackwardWhenEmpty = { [weak self] in self?.taskDeleteBackward(id: id) }
            cell.onEditingChange = { [weak self] in self?.taskEditingChanged(id: id, isEditing: $0) }
            cell.onPasteLines = { [weak self] in self?.pasteTaskLines($0) }
            return cell
        case .settings:
            guard let item = settingsItems[safe: indexPath.row],
                  let cell = tableView.dequeueReusableCell(
                      withIdentifier: CreatePollToggleCell.reuseIdentifier,
                      for: indexPath,
                  ) as? CreatePollToggleCell
            else { return UITableViewCell() }
            configureSettingsCell(cell, item: item, animated: false)
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard fieldIsEditable(at: indexPath) else { return }
        (tableView.cellForRow(at: indexPath) as? CreatePollTextCell)?.beginEditing()
    }

    /// ListComposePollOptionComponent's revealed Delete, on every task that may change but the last.
    override func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath,
    ) -> UISwipeActionsConfiguration? {
        guard sections[safe: indexPath.section] == .tasks, indexPath.row < tasks.count - 1,
              let task = tasks[safe: indexPath.row], !task.isLocked
        else { return nil }
        let id = task.id
        let action = UIContextualAction(style: .destructive, title: L10n.telegram("Common.Delete")) {
            [weak self] _, _, completion in
            self?.deleteTask(id: id)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    override func tableView(_: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        guard sections[safe: indexPath.section] == .tasks, let task = tasks[safe: indexPath.row] else { return false }
        return !task.isEmpty && !task.isLocked
    }

    override func tableView(
        _: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath,
    ) {
        guard tasks.indices.contains(sourceIndexPath.row) else { return }
        let task = tasks.remove(at: sourceIndexPath.row)
        tasks.insert(task, at: min(destinationIndexPath.row, tasks.count))
        UISelectionFeedbackGenerator().selectionChanged()
        DispatchQueue.main.async { [weak self] in
            self?.refreshTaskCells()
        }
    }

    // MARK: Fields

    /// A field's text in the field's font, with its formatting and custom emoji.
    private static func fieldText(_ formatted: FormattedText) -> NSAttributedString {
        fieldText(ComposerText.uiKit(ComposerText.attributed(formatted)))
    }

    private static func fieldText(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        ComposerText.refresh(result)
        result.addAttribute(
            .font,
            value: UIFont.preferredFont(forTextStyle: .body),
            range: NSRange(location: 0, length: result.length),
        )
        return result
    }

    /// ComposeTodoScreen's attributedTodoItemLines: the pasted text's lines with more than spaces, each cut to a
    /// task's limit.
    private static func lines(of text: NSAttributedString, limit: Int) -> [NSAttributedString] {
        var result = [NSAttributedString]()
        let string = text.string
        string.enumerateSubstrings(in: string.startIndex..., options: [.byLines, .substringNotRequired]) {
            _, range, _, _ in
            let line = text.attributedSubstring(from: NSRange(range, in: string))
            guard !line.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let kept = String(line.string.prefix(limit))
            let length = (kept as NSString).length
            result.append(fieldText(line.attributedSubstring(from: NSRange(location: 0, length: length))))
        }
        return result
    }

    /// The screen in its sheet, which asks before a swipe discards a checklist that could be sent.
    func makeNavigationController() -> UINavigationController {
        let navigation = TelegramNavigationController(rootViewController: self)
        navigation.modalPresentationStyle = .pageSheet
        navigation.presentationController?.delegate = self
        return navigation
    }

    // MARK: Reordering

    /// A filled task that may change moves by its reorder indicator (ListComposePollOptionComponent's `canReorder`).
    func tableView(
        _ tableView: UITableView,
        itemsForBeginning session: UIDragSession,
        at indexPath: IndexPath,
    ) -> [UIDragItem] {
        guard sections[safe: indexPath.section] == .tasks,
              let task = tasks[safe: indexPath.row], !task.isEmpty, !task.isLocked,
              let cell = tableView.cellForRow(at: indexPath) as? CreatePollTextCell,
              cell.reorderHandleContains(session.location(in: cell))
        else { return [] }
        let item = UIDragItem(itemProvider: NSItemProvider())
        item.localObject = task.id
        return [item]
    }

    func tableView(_: UITableView, dragSessionIsRestrictedToDraggingApplication _: UIDragSession) -> Bool {
        true
    }

    /// ComposeTodoScreen's reorderIfPossible: a task takes the place of another filled one that may change.
    func tableView(
        _: UITableView,
        dropSessionDidUpdate session: UIDropSession,
        withDestinationIndexPath destinationIndexPath: IndexPath?,
    ) -> UITableViewDropProposal {
        guard session.localDragSession != nil, let destinationIndexPath,
              sections[safe: destinationIndexPath.section] == .tasks,
              reorderableTaskRange.contains(destinationIndexPath.row)
        else { return UITableViewDropProposal(operation: .forbidden) }
        return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func tableView(_: UITableView, performDropWith _: UITableViewDropCoordinator) {}

    // MARK: Presentation

    func presentationControllerShouldDismiss(_: UIPresentationController) -> Bool {
        !asksBeforeDiscarding
    }

    func presentationControllerDidAttemptToDismiss(_: UIPresentationController) {
        confirmDiscard()
    }

    func presentationControllerDidDismiss(_: UIPresentationController) {
        onDismiss?()
    }

    private func textCell(_ tableView: UITableView, at indexPath: IndexPath, field: Field?) -> CreatePollTextCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: CreatePollTextCell.reuseIdentifier,
            for: indexPath,
        ) as? CreatePollTextCell else { return CreatePollTextCell(style: .default, reuseIdentifier: nil) }
        cell.resetActions()
        cell.customEmojiClient = client
        cell.onHeightChange = { [weak self] in self?.updateRowHeights() }
        if let field {
            cell.onEmoji = { [weak self] in self?.presentEmojiPicker(for: field) }
        }
        return cell
    }

    /// The title, which can't change where only tasks may be added; return moves to the first task.
    private func titleConfiguration() -> CreatePollTextCell.Configuration {
        CreatePollTextCell.Configuration(
            text: checklistTitle,
            placeholder: L10n.telegram("CreateTodo.TitlePlaceholder"),
            lengthLimit: titleLengthLimit,
            allowsLineFeeds: false,
            returnKeyType: .next,
            allowsEmoji: accountID != nil,
            isEnabled: canEdit,
        )
    }

    /// ListComposePollOptionComponent for a task: the reorder indicator once it has text, the add indicator on an
    /// empty task after the first, and Add a Task as the last one's placeholder; a published task that may not change
    /// is dimmed without either.
    private func taskConfiguration(at index: Int) -> CreatePollTextCell.Configuration {
        let task = tasks[index]
        let isLast = index == tasks.count - 1
        let indicator: CreatePollTextCell.Indicator =
            if task.isLocked {
                .blank
            } else if !task.isEmpty {
                .reorder
            } else if index != 0, index < maximumTaskCount {
                .add
            } else {
                .blank
            }
        return CreatePollTextCell.Configuration(
            text: task.text,
            placeholder: L10n.telegram(isLast ? "CreateTodo.AddTaskPlaceholder" : "CreateTodo.TaskPlaceholder"),
            lengthLimit: taskLengthLimit,
            allowsLineFeeds: false,
            returnKeyType: isLast ? .done : .next,
            indicator: indicator,
            allowsEmoji: accountID != nil,
            isEnabled: !task.isLocked,
        )
    }

    private func fieldIsEditable(at indexPath: IndexPath) -> Bool {
        switch sections[safe: indexPath.section] {
        case .title: canEdit
        case .tasks: tasks[safe: indexPath.row].map { !$0.isLocked } ?? false
        case nil,
             .settings: false
        }
    }

    private func titleChanged(_ text: NSAttributedString) {
        checklistTitle = text
        updateSendButton()
    }

    private func focusFirstTask() {
        guard let section = sections.firstIndex(of: .tasks),
              let row = tasks.firstIndex(where: { !$0.isLocked }) else { return }
        focusRow(at: IndexPath(row: row, section: section))
    }

    private func taskTextChanged(id: Int, text: NSAttributedString) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].text = text
        updateTasks(from: tasks.map(\.id))
        updateSendButton()
    }

    private func taskEditingChanged(id: Int, isEditing: Bool) {
        if isEditing {
            editingTaskID = id
            return
        }
        // The emoji picker covers the field it fills: the task stays until the picker closes.
        guard emojiPickerField != .task(id) else { return }
        if editingTaskID == id { editingTaskID = nil }
        // An empty task left behind may go now; the table may be mid-update while the field resigns.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            updateTasks(from: tasks.map(\.id))
        }
    }

    /// Telegram's return key on a task: the next task, or the keyboard goes away after the last.
    private func taskReturnPressed(id: Int) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              let section = sections.firstIndex(of: .tasks) else { return }
        if index == tasks.count - 1 {
            view.endEditing(true)
        } else {
            focusRow(at: IndexPath(row: index + 1, section: section))
        }
    }

    /// Telegram's backspace in an empty task: the task before it, or the title before the first.
    private func taskDeleteBackward(id: Int) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              let section = sections.firstIndex(of: .tasks),
              let titleSection = sections.firstIndex(of: .title) else { return }
        let target = index == 0
            ? IndexPath(row: 0, section: titleSection)
            : IndexPath(row: index - 1, section: section)
        guard fieldIsEditable(at: target) else { return }
        focusRow(at: target)
    }

    private func deleteTask(id: Int) {
        let previousIDs = tasks.map(\.id)
        tasks.removeAll { $0.id == id }
        updateTasks(from: previousIDs)
        updateSendButton()
    }

    /// ComposeTodoScreen's paste: each line fills a task from the first that may change, and the rest become new tasks
    /// while there's room.
    private func pasteTaskLines(_ text: NSAttributedString) {
        let lines = Self.lines(of: text, limit: taskLengthLimit)
        guard !lines.isEmpty, let section = sections.firstIndex(of: .tasks) else { return }
        view.endEditing(true)
        editingTaskID = nil
        var index = tasks.firstIndex { !$0.isLocked } ?? tasks.count
        for line in lines {
            if index < tasks.count {
                tasks[index].text = line
            } else if tasks.count < maximumTaskCount {
                tasks.append(DraftTask(id: nextTaskID, text: line))
                nextTaskID += 1
            } else {
                break
            }
            index += 1
        }
        normalizeTasks()
        tableView.reloadSections(IndexSet(integer: section), with: .automatic)
        updateSendButton()
    }

    /// ComposeTodoScreen's task upkeep: an empty last task goes when the one before it is empty too and it isn't being
    /// edited, and a filled last task gets an empty one after it while there's room.
    private func normalizeTasks() {
        while tasks.count > 2, let last = tasks.last, last.isEmpty, last.id != editingTaskID,
              tasks[tasks.count - 2].isEmpty
        {
            tasks.removeLast()
        }
        if tasks.count < maximumTaskCount, let last = tasks.last, !last.isEmpty {
            tasks.append(DraftTask(id: nextTaskID))
            nextTaskID += 1
        }
    }

    /// Applies the task upkeep and shows the rows it added or removed, keeping the edited field and its keyboard.
    private func updateTasks(from previousIDs: [Int]) {
        normalizeTasks()
        let currentIDs = tasks.map(\.id)
        if currentIDs != previousIDs, let section = sections.firstIndex(of: .tasks) {
            let deleted = previousIDs.indices
                .filter { !currentIDs.contains(previousIDs[$0]) }
                .map { IndexPath(row: $0, section: section) }
            let inserted = currentIDs.indices
                .filter { !previousIDs.contains(currentIDs[$0]) }
                .map { IndexPath(row: $0, section: section) }
            tableView.performBatchUpdates {
                self.tableView.deleteRows(at: deleted, with: .fade)
                self.tableView.insertRows(at: inserted, with: .fade)
            }
        }
        refreshTaskCells()
        refreshFooter()
    }

    private func refreshTaskCells() {
        guard let section = sections.firstIndex(of: .tasks) else { return }
        for indexPath in tableView.indexPathsForVisibleRows ?? []
            where indexPath.section == section && indexPath.row < tasks.count
        {
            (tableView.cellForRow(at: indexPath) as? CreatePollTextCell)?
                .configure(taskConfiguration(at: indexPath.row))
        }
    }

    private func focusRow(at indexPath: IndexPath) {
        guard indexPath.section < tableView.numberOfSections,
              indexPath.row < tableView.numberOfRows(inSection: indexPath.section) else { return }
        tableView.scrollToRow(at: indexPath, at: .none, animated: false)
        tableView.layoutIfNeeded()
        (tableView.cellForRow(at: indexPath) as? CreatePollTextCell)?.beginEditing()
    }

    private func updateRowHeights() {
        UIView.performWithoutAnimation {
            tableView.performBatchUpdates(nil)
        }
    }

    // MARK: Footer

    private func configureFooter(_ footer: UITableViewHeaderFooterView) {
        var content = footer.defaultContentConfiguration()
        content.text = tasksFooterText
        footer.contentConfiguration = content
    }

    /// Updates the count of tasks left in place, so a field being edited keeps its keyboard.
    private func refreshFooter() {
        guard let section = sections.firstIndex(of: .tasks),
              let footer = tableView.footerView(forSection: section),
              (footer.contentConfiguration as? UIListContentConfiguration)?.text != tasksFooterText
        else { return }
        configureFooter(footer)
        updateRowHeights()
    }

    // MARK: Settings

    /// ComposeTodoScreen's toggles, which have no icons.
    private func configureSettingsCell(_ cell: CreatePollToggleCell, item: SettingsItem, animated: Bool) {
        let (titleKey, isOn) =
            switch item {
            case .othersCanMarkAsDone: ("CreateTodo.AllowOthersToComplete", othersCanMarkAsDone)
            case .othersCanAddTasks: ("CreateTodo.AllowOthersToAppend", othersCanAddTasks)
            }
        cell.configure(
            title: L10n.telegram(titleKey),
            subtitle: nil,
            image: nil,
            tint: .clear,
            isOn: isOn,
            isEnabled: true,
            animated: animated,
        )
        cell.onChange = { [weak self] isOn in self?.setting(item, changedTo: isOn) }
    }

    private func setting(_ item: SettingsItem, changedTo isOn: Bool) {
        switch item {
        case .othersCanMarkAsDone:
            guard othersCanMarkAsDone != isOn, let section = sections.firstIndex(of: .settings) else { return }
            othersCanMarkAsDone = isOn
            let row = IndexPath(row: 1, section: section)
            tableView.performBatchUpdates {
                if isOn {
                    self.tableView.insertRows(at: [row], with: .fade)
                } else {
                    self.tableView.deleteRows(at: [row], with: .fade)
                }
            }
        case .othersCanAddTasks:
            othersCanAddTasks = isOn
        }
        updateSendButton()
    }

    // MARK: Emoji

    /// ListComposePollOptionComponent's input mode button. Telegram swaps the keyboard for its emoji keyboard; here
    /// the composer's emoji picker opens over the screen, emoji only, and fills the field that was being edited.
    private func presentEmojiPicker(for field: Field) {
        guard let accountID, presentedViewController == nil else { return }
        let picker = ComposerMediaPickerViewController(accountID: accountID, chatID: chatID, client: client)
        picker.allowsStickersAndGIFs = false
        picker.onEmoji = { [weak self] emoji in
            self?.insertEmoji(emoji, customID: nil, in: field)
        }
        picker.onCustomEmoji = { [weak self] sticker in
            guard case .stickerFullTypeCustomEmoji(let type) = sticker.fullType else { return }
            self?.insertEmoji(sticker.emoji, customID: type.customEmojiId, in: field)
        }
        picker.onDismiss = { [weak self] in self?.emojiPickerDidDismiss() }
        emojiPickerField = field
        let observer = SheetDismissObserver { [weak self] in self?.emojiPickerDidDismiss() }
        emojiPickerObserver = observer
        let navigation = TelegramNavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .pageSheet
        navigation.sheetPresentationController?.detents = [.medium(), .large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = false
        navigation.presentationController?.delegate = observer
        present(navigation, animated: true)
    }

    private func insertEmoji(_ emoji: String, customID: Int64?, in field: Field) {
        guard let indexPath = rowIndexPath(for: field),
              let cell = tableView.cellForRow(at: indexPath) as? CreatePollTextCell else { return }
        cell.insertEmoji(emoji, customID: customID)
    }

    /// Telegram's emoji keyboard switches back to the keyboard in the same field.
    private func emojiPickerDidDismiss() {
        guard let field = emojiPickerField else { return }
        emojiPickerField = nil
        emojiPickerObserver = nil
        let indexPath = rowIndexPath(for: field)
        if let indexPath { focusRow(at: indexPath) }
        if case .task(let id) = field,
           indexPath.flatMap({ tableView.cellForRow(at: $0) as? CreatePollTextCell })?.isEditingText != true
        {
            taskEditingChanged(id: id, isEditing: false)
        }
    }

    private func rowIndexPath(for field: Field) -> IndexPath? {
        switch field {
        case .title:
            return sections.firstIndex(of: .title).map { IndexPath(row: 0, section: $0) }
        case .task(let id):
            guard let section = sections.firstIndex(of: .tasks),
                  let row = tasks.firstIndex(where: { $0.id == id }) else { return nil }
            return IndexPath(row: row, section: section)
        }
    }

    // MARK: Sending

    private func updateSendButton() {
        navigationItem.rightBarButtonItem?.isEnabled = validatedChecklist != nil
    }

    /// openTodoEditing's completion: a published checklist that may be edited and changed beyond tasks added at its
    /// end goes back whole; otherwise only the added tasks go, and nothing when none were.
    private func outcome(for checklist: TDNativeInputChecklist) -> ChecklistEditorOutcome? {
        guard let initialChecklist else { return .checklist(checklist) }
        let onlyAddsTasks = checklist.title == initialChecklist.title
            && checklist.othersCanAddTasks == initialChecklist.othersCanAddTasks
            && checklist.othersCanMarkTasksAsDone == initialChecklist.othersCanMarkTasksAsDone
            && checklist.tasks.starts(with: initialChecklist.tasks)
        if canEdit, !onlyAddsTasks { return .checklist(checklist) }
        let added = Array(checklist.tasks.dropFirst(initialChecklist.tasks.count))
        return added.isEmpty ? nil : .addedTasks(added, checklist: checklist)
    }

    @objc private func sendPressed() {
        guard !didSend, let checklist = validatedChecklist else { return }
        didSend = true
        view.endEditing(true)
        let outcome = outcome(for: checklist)
        let completion = completion
        let onDismiss = onDismiss
        dismiss(animated: true) {
            onDismiss?()
            if let outcome { completion(outcome) }
        }
    }

    @objc private func cancelPressed() {
        if asksBeforeDiscarding {
            confirmDiscard()
        } else {
            close()
        }
    }

    /// requestDismiss: Discard checklist items? with No and Yes.
    private func confirmDiscard() {
        let alert = UIAlertController(
            title: nil,
            message: L10n.telegram("Attachment.DiscardTodoAlertText"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Attachment.CancelSelectionAlertNo"), style: .cancel))
        let discard = UIAlertAction(title: L10n.telegram("Attachment.CancelSelectionAlertYes"), style: .default) {
            [weak self] _ in
            self?.close()
        }
        alert.addAction(discard)
        alert.preferredAction = discard
        present(alert, animated: true)
    }

    private func close() {
        view.endEditing(true)
        let onDismiss = onDismiss
        dismiss(animated: true) { onDismiss?() }
    }

    // MARK: Limits

    /// TDLib's limits for the title, a task and the number of tasks.
    private func loadLimits() {
        let client = client
        Task { [weak self] in
            let titleLength = try? await client.getOption(name: "checklist_title_length_max")
            let taskLength = try? await client.getOption(name: "checklist_task_text_length_max")
            let taskCount = try? await client.getOption(name: "checklist_task_count_max")
            guard let self else { return }
            if case .optionValueInteger(let value) = titleLength {
                titleLengthLimit = max(1, Int(clamping: value.value))
            }
            if case .optionValueInteger(let value) = taskLength {
                taskLengthLimit = max(1, Int(clamping: value.value))
            }
            if case .optionValueInteger(let value) = taskCount {
                setMaximumTaskCount(max(1, Int(clamping: value.value)))
            }
            if let section = sections.firstIndex(of: .title) {
                (tableView.cellForRow(at: IndexPath(row: 0, section: section)) as? CreatePollTextCell)?
                    .configure(titleConfiguration())
            }
            refreshTaskCells()
        }
    }

    private func setMaximumTaskCount(_ count: Int) {
        guard count != maximumTaskCount else { return }
        let previousIDs = tasks.map(\.id)
        maximumTaskCount = count
        while tasks.count > max(2, count), let last = tasks.last, last.isEmpty, !last.isLocked {
            tasks.removeLast()
        }
        updateTasks(from: previousIDs)
    }
}
