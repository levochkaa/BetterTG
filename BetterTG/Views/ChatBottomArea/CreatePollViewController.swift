// CreatePollViewController.swift

import TDLibKit
import UIKit

// MARK: - CreatePollViewController

/// Telegram's ComposePollScreen: the question with an optional description; options that grow as they're filled, up
/// to TDLib's `poll_answer_count_max`, reordered by their handle and deleted with a swipe; the settings (Show Who
/// Voted, Allow Multiple Answers, Allow Adding Options, Allow Revoting, Shuffle Options, Set Correct Answer, Limit
/// Duration with Hide Results, and a channel's Restrict to Subscribers); and a quiz's explanation. Send checks the poll
/// as Telegram's validatedInput does and hands it over as `inputMessagePoll` once the screen has been dismissed.
/// Every field takes custom emoji from the emoji picker, the way ListComposePollOptionComponent's input mode button
/// swaps in Telegram's emoji keyboard, and the poll keeps only their entities.
@MainActor final class CreatePollViewController: UITableViewController, UITableViewDragDelegate,
    UITableViewDropDelegate, UIAdaptivePresentationControllerDelegate
{
    // MARK: Private

    private enum Section {
        case text
        case options
        case settings
        case explanation
    }

    private enum SettingsItem {
        case showWhoVoted
        case multipleAnswers
        case addingOptions
        case revoting
        case shuffle
        case quiz
        case limitDuration
        case duration
        case hideResults
        case restrictToSubscribers
    }

    private enum TimeLimit {
        case duration(Int)
        /// A Unix time.
        case deadline(Int)
    }

    private enum Validation {
        case ready(InputMessageContent)
        case failed(String)
    }

    /// A field the emoji picker inserts into.
    private enum TextField: Equatable {
        case question
        case description
        case option(Int)
        case explanation
    }

    private struct DraftOption {
        let id: Int
        var text = NSAttributedString()

        var isEmpty: Bool {
            text.string.isEmpty
        }
    }

    /// ComposePollScreen's limits: 200 characters for the question and the explanation, 1024 for the description and
    /// 100 for an option.
    private static let questionLengthLimit = 200
    private static let descriptionLengthLimit = 1024
    private static let optionLengthLimit = 100
    private static let explanationLengthLimit = 200
    /// TDLib's limit on an explanation's line feeds.
    private static let explanationLineFeedLimit = 2
    /// presentTimeLimitOptions: 1, 3, 8, 24 and 72 hours.
    private static let durationPresets = [1, 3, 8, 24, 72].map { $0 * 60 * 60 }
    private static let durationIdentifier = "CreatePollDuration"
    private static let footerIdentifier = "CreatePollFooter"
    /// Telegram's cachedEmptyIcon: the rows under Limit Duration line up with the titles above them.
    private static let emptyIcon = UIGraphicsImageRenderer(size: CGSize(width: 25, height: 25)).image { _ in }

    // MARK: Internal

    /// Called once the screen has gone, whether it sent the poll or not.
    var onDismiss: (() -> Void)?

    private let isChannel: Bool
    private let client: TDLibClient
    /// The account and chat the emoji picker loads the user's emoji for; without an account the fields take only the
    /// keyboard's emoji.
    private let accountID: UUID?
    private let chatID: Int64
    private let send: (InputMessageContent) -> Void
    private var maximumOptionCount = 10
    private var maximumOpenPeriod: Int?
    private var question = NSAttributedString()
    private var pollDescription = NSAttributedString()
    private var explanation = NSAttributedString()
    private var options = [DraftOption]()
    private var nextOptionID = 0
    private var editingOptionID: Int?
    /// The field the open emoji picker inserts into. An option being filled from it stays while its field is covered.
    private var emojiPickerField: TextField?
    private var emojiPickerObserver: SheetDismissObserver?
    private var isAnonymous = true
    private var allowsMultipleAnswers = true
    private var canAddOptions = false
    private var canRevote = true
    private var shuffleOptions = false
    private var isQuiz = false
    /// A bot's poll request button fixes the kind (`keyboardButtonTypeRequestPoll`'s force_quiz or force_regular),
    /// which locks the quiz toggle; nil lets the user choose.
    private let forcedQuiz: Bool?
    private var correctOptionIDs = Set<Int>()
    private var limitsDuration = false
    private var timeLimit = TimeLimit.duration(24 * 60 * 60)
    private var hidesResults = false
    private var restrictsToSubscribers = false
    private var didSend = false

    private var sections: [Section] {
        isQuiz ? [.text, .options, .settings, .explanation] : [.text, .options, .settings]
    }

    private var settingsItems: [SettingsItem] {
        var items = [SettingsItem]()
        if !isChannel { items.append(.showWhoVoted) }
        items.append(.multipleAnswers)
        if !isChannel { items.append(.addingOptions) }
        items += [.revoting, .shuffle, .quiz, .limitDuration]
        if limitsDuration { items += [.duration, .hideResults] }
        if isChannel { items.append(.restrictToSubscribers) }
        return items
    }

    /// The options a filled one can be moved among: all but an empty last one.
    private var reorderableOptionCount: Int {
        options.last?.isEmpty == true ? options.count - 1 : options.count
    }

    /// ComposePollScreen's hasAnyData, which asks before the poll is discarded.
    private var hasAnyData: Bool {
        !question.string.isEmpty || !pollDescription.string.isEmpty || !explanation.string.isEmpty
            || options.contains { !$0.isEmpty }
    }

    private var optionsFooterText: String {
        if options.count >= maximumOptionCount { return L10n.telegram("CreatePoll.AllOptionsAdded") }
        let remaining = maximumOptionCount - options.count(where: { !$0.isEmpty })
        return L10n.telegramPlural("CreatePoll.OptionCountFooterFormat", count: remaining)
            .replacingOccurrences(of: "{count}", with: "\(remaining)")
    }

    /// - Parameters:
    ///   - isChannel: A channel's polls are anonymous and shuffled by default, and offer Restrict to Subscribers in
    ///     place of Show Who Voted and Allow Adding Options.
    ///   - forcedQuiz: A bot's poll request (`setupPoll(isQuiz:)`): true for a quiz, false for a regular poll.
    ///   - accountID: The account whose emoji the picker offers.
    ///   - chatID: The chat the poll goes to; Saved Messages takes custom emoji without Premium.
    ///   - send: Called with the poll once the screen has been dismissed.
    init(
        isChannel: Bool,
        client: TDLibClient,
        forcedQuiz: Bool? = nil,
        accountID: UUID?,
        chatID: Int64,
        send: @escaping (InputMessageContent) -> Void,
    ) {
        self.isChannel = isChannel
        self.client = client
        self.forcedQuiz = forcedQuiz
        self.accountID = accountID
        self.chatID = chatID
        self.send = send
        super.init(style: .insetGrouped)
        // ComposePollScreen's initial state: two empty options, multiple answers and revoting allowed, and outside
        // channels public votes that may add options; a quiz starts with one answer, no added options or revotes.
        let startsAsQuiz = forcedQuiz == true
        self.isQuiz = startsAsQuiz
        if startsAsQuiz {
            self.allowsMultipleAnswers = false
            self.canRevote = false
        }
        if isChannel {
            self.shuffleOptions = true
        } else {
            self.isAnonymous = false
            self.canAddOptions = !startsAsQuiz
        }
        self.options = [DraftOption(id: 0), DraftOption(id: 1)]
        self.nextOptionID = 2
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateTitle()
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"),
            style: .plain,
            target: self,
            action: #selector(cancelPressed),
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("CreatePoll.Create"),
            style: .prominent,
            target: self,
            action: #selector(sendPressed),
        )
        tableView.backgroundColor = .systemGroupedBackground
        tableView.keyboardDismissMode = .interactive
        tableView.register(CreatePollTextCell.self, forCellReuseIdentifier: CreatePollTextCell.reuseIdentifier)
        tableView.register(CreatePollToggleCell.self, forCellReuseIdentifier: CreatePollToggleCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.durationIdentifier)
        tableView.register(UITableViewHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: Self.footerIdentifier)
        tableView.dragDelegate = self
        tableView.dropDelegate = self
        tableView.dragInteractionEnabled = true
        loadLimits()
    }

    // MARK: Table

    override func numberOfSections(in _: UITableView) -> Int {
        sections.count
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .text: 2
        case .options: options.count
        case .settings: settingsItems.count
        case .explanation: 1
        }
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sections[section] {
        case .text: L10n.telegram("CreatePoll.TextHeader")
        case .options: L10n.telegram("CreatePoll.OptionsTitle")
        case .settings: L10n.telegram("CreatePoll.SettingsTitle")
        case .explanation: L10n.telegram("CreatePoll.ExplanationHeader")
        }
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let kind = sections[section]
        guard kind != .text,
              let footer = tableView.dequeueReusableHeaderFooterView(withIdentifier: Self.footerIdentifier)
        else { return nil }
        configureFooter(footer, text: footerText(for: kind))
        return footer
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section] {
        case .text:
            if indexPath.row == 0 {
                let cell = textCell(tableView, at: indexPath, field: .question)
                cell.configure(CreatePollTextCell.Configuration(
                    text: question,
                    placeholder: L10n.telegram("CreatePoll.TextPlaceholder"),
                    lengthLimit: Self.questionLengthLimit,
                    allowsEmoji: accountID != nil,
                ))
                cell.onTextChange = { [weak self] in self?.question = $0 }
                return cell
            }
            let cell = textCell(tableView, at: indexPath, field: .description)
            cell.configure(CreatePollTextCell.Configuration(
                text: pollDescription,
                placeholder: L10n.telegram("CreatePoll.DescriptionPlaceholder"),
                lengthLimit: Self.descriptionLengthLimit,
                allowsEmoji: accountID != nil,
            ))
            cell.onTextChange = { [weak self] in self?.pollDescription = $0 }
            return cell
        case .options:
            guard let option = options[safe: indexPath.row] else {
                return textCell(tableView, at: indexPath, field: nil)
            }
            let id = option.id
            let cell = textCell(tableView, at: indexPath, field: .option(id))
            cell.configure(optionConfiguration(at: indexPath.row))
            cell.onTextChange = { [weak self] in self?.optionTextChanged(id: id, text: $0) }
            cell.onReturn = { [weak self] in self?.optionReturnPressed(id: id) }
            cell.onDeleteBackwardWhenEmpty = { [weak self] in self?.optionDeleteBackward(id: id) }
            cell.onEditingChange = { [weak self] in self?.optionEditingChanged(id: id, isEditing: $0) }
            cell.onToggleCheck = { [weak self] in self?.toggleCorrectOption(id: id) }
            return cell
        case .settings:
            guard let item = settingsItems[safe: indexPath.row] else { return UITableViewCell() }
            let identifier = item == .duration ? Self.durationIdentifier : CreatePollToggleCell.reuseIdentifier
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
            configureSettingsCell(cell, item: item, animated: false)
            return cell
        case .explanation:
            let cell = textCell(tableView, at: indexPath, field: .explanation)
            cell.configure(CreatePollTextCell.Configuration(
                text: explanation,
                placeholder: L10n.telegram("CreatePoll.Explanation"),
                lengthLimit: Self.explanationLengthLimit,
                lineFeedLimit: Self.explanationLineFeedLimit,
                allowsEmoji: accountID != nil,
            ))
            cell.onTextChange = { [weak self] in self?.explanation = $0 }
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let cell = tableView.cellForRow(at: indexPath) else { return }
        if let textCell = cell as? CreatePollTextCell {
            textCell.beginEditing()
        } else if sections[safe: indexPath.section] == .settings, settingsItems[safe: indexPath.row] == .duration {
            presentTimeLimitOptions(from: cell)
        }
    }

    /// ListComposePollOptionComponent's revealed Delete, on every option but the last.
    override func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath,
    ) -> UISwipeActionsConfiguration? {
        guard sections[safe: indexPath.section] == .options, indexPath.row < options.count - 1 else { return nil }
        let id = options[indexPath.row].id
        let action = UIContextualAction(style: .destructive, title: L10n.telegram("Common.Delete")) {
            [weak self] _, _, completion in
            self?.deleteOption(id: id)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    override func tableView(_: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        sections[safe: indexPath.section] == .options && options[safe: indexPath.row]?.isEmpty == false
    }

    override func tableView(
        _: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath,
    ) {
        guard options.indices.contains(sourceIndexPath.row) else { return }
        let option = options.remove(at: sourceIndexPath.row)
        options.insert(option, at: min(destinationIndexPath.row, options.count))
        DispatchQueue.main.async { [weak self] in
            self?.refreshOptionCells()
        }
    }

    // MARK: Sending

    /// ComposePollScreen's validatedInput keeps only a field's custom emoji entities.
    private static func pollText(_ value: NSAttributedString) -> FormattedText {
        let formatted = ComposerText.formatted(value)
        let entities = formatted.entities.filter { entity in
            if case .textEntityTypeCustomEmoji = entity.type { return true }
            return false
        }
        return FormattedText(entities: entities, text: formatted.text)
    }

    /// The screen in its sheet, which asks before a swipe discards an unsent poll.
    func makeNavigationController() -> UINavigationController {
        let navigation = TelegramNavigationController(rootViewController: self)
        navigation.modalPresentationStyle = .pageSheet
        navigation.presentationController?.delegate = self
        return navigation
    }

    // MARK: Reordering

    /// A filled option moves by its reorder indicator, as ListComposePollOptionComponent's `canReorder` does.
    func tableView(
        _ tableView: UITableView,
        itemsForBeginning session: UIDragSession,
        at indexPath: IndexPath,
    ) -> [UIDragItem] {
        guard sections[safe: indexPath.section] == .options,
              let option = options[safe: indexPath.row], !option.isEmpty,
              let cell = tableView.cellForRow(at: indexPath) as? CreatePollTextCell,
              cell.reorderHandleContains(session.location(in: cell))
        else { return [] }
        let item = UIDragItem(itemProvider: NSItemProvider())
        item.localObject = option.id
        return [item]
    }

    func tableView(_: UITableView, dragSessionIsRestrictedToDraggingApplication _: UIDragSession) -> Bool {
        true
    }

    func tableView(
        _: UITableView,
        dropSessionDidUpdate session: UIDropSession,
        withDestinationIndexPath destinationIndexPath: IndexPath?,
    ) -> UITableViewDropProposal {
        guard session.localDragSession != nil, let destinationIndexPath,
              sections[safe: destinationIndexPath.section] == .options,
              destinationIndexPath.row < reorderableOptionCount
        else { return UITableViewDropProposal(operation: .forbidden) }
        return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func tableView(_: UITableView, performDropWith _: UITableViewDropCoordinator) {}

    // MARK: Presentation

    func presentationControllerShouldDismiss(_: UIPresentationController) -> Bool {
        !hasAnyData
    }

    func presentationControllerDidAttemptToDismiss(_: UIPresentationController) {
        confirmDiscard()
    }

    func presentationControllerDidDismiss(_: UIPresentationController) {
        onDismiss?()
    }

    // MARK: Options

    private func textCell(_ tableView: UITableView, at indexPath: IndexPath, field: TextField?) -> CreatePollTextCell {
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

    /// ListComposePollOptionComponent for an option: the reorder indicator once it has text, the add indicator on an
    /// empty option after the first, Add an Option as the last one's placeholder, and a quiz's correct answer check.
    private func optionConfiguration(at index: Int) -> CreatePollTextCell.Configuration {
        let option = options[index]
        let isLast = index == options.count - 1
        let indicator: CreatePollTextCell.Indicator =
            if !option.isEmpty {
                .reorder
            } else if index != 0, index < maximumOptionCount {
                .add
            } else {
                .blank
            }
        return CreatePollTextCell.Configuration(
            text: option.text,
            placeholder: L10n.telegram(isLast ? "CreatePoll.AddOption" : "CreatePoll.OptionPlaceholder"),
            lengthLimit: Self.optionLengthLimit,
            allowsLineFeeds: false,
            returnKeyType: isLast ? .done : .next,
            indicator: indicator,
            check: isQuiz
                ? CreatePollTextCell.Check(
                    isSelected: correctOptionIDs.contains(option.id),
                    allowsMultiple: allowsMultipleAnswers,
                )
                : nil,
            allowsEmoji: accountID != nil,
        )
    }

    private func optionTextChanged(id: Int, text: NSAttributedString) {
        guard let index = options.firstIndex(where: { $0.id == id }) else { return }
        options[index].text = text
        updateOptions(from: options.map(\.id))
    }

    private func optionEditingChanged(id: Int, isEditing: Bool) {
        if isEditing {
            editingOptionID = id
            return
        }
        // The emoji picker covers the field it fills: the option stays until the picker closes.
        guard emojiPickerField != .option(id) else { return }
        if editingOptionID == id { editingOptionID = nil }
        // An empty option left behind may go now; the table may be mid-update while the field resigns.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            updateOptions(from: options.map(\.id))
        }
    }

    /// Telegram's return key on an option: the next option, or the keyboard goes away after the last.
    private func optionReturnPressed(id: Int) {
        guard let index = options.firstIndex(where: { $0.id == id }),
              let section = sections.firstIndex(of: .options) else { return }
        if index == options.count - 1 {
            view.endEditing(true)
        } else {
            focusRow(at: IndexPath(row: index + 1, section: section))
        }
    }

    /// Telegram's backspace in an empty option: the option before it, or the question before the first.
    private func optionDeleteBackward(id: Int) {
        guard let index = options.firstIndex(where: { $0.id == id }),
              let section = sections.firstIndex(of: .options),
              let textSection = sections.firstIndex(of: .text) else { return }
        focusRow(at: index == 0
            ? IndexPath(row: 0, section: textSection)
            : IndexPath(row: index - 1, section: section))
    }

    private func deleteOption(id: Int) {
        let previousIDs = options.map(\.id)
        options.removeAll { $0.id == id }
        correctOptionIDs.remove(id)
        updateOptions(from: previousIDs)
    }

    /// The quiz's correct answers: one option at a time unless multiple answers are allowed.
    private func toggleCorrectOption(id: Int) {
        if correctOptionIDs.contains(id) {
            correctOptionIDs.remove(id)
        } else {
            if !allowsMultipleAnswers { correctOptionIDs.removeAll() }
            correctOptionIDs.insert(id)
        }
        refreshOptionCells()
    }

    /// ComposePollScreen's option upkeep: an empty last option goes when the one before it is empty too and it isn't
    /// being edited, and a filled last option gets an empty one after it while there's room.
    private func normalizeOptions() {
        while options.count > 2, let last = options.last, last.isEmpty, last.id != editingOptionID,
              options[options.count - 2].isEmpty
        {
            options.removeLast()
            correctOptionIDs.remove(last.id)
        }
        if options.count < maximumOptionCount, let last = options.last, !last.isEmpty {
            options.append(DraftOption(id: nextOptionID))
            nextOptionID += 1
        }
    }

    /// Applies the option upkeep and shows the rows it added or removed, keeping the edited field and its keyboard.
    private func updateOptions(from previousIDs: [Int]) {
        normalizeOptions()
        let currentIDs = options.map(\.id)
        if currentIDs != previousIDs, let section = sections.firstIndex(of: .options) {
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
        refreshOptionCells()
        refreshFooter(of: .options)
    }

    private func refreshOptionCells() {
        guard let section = sections.firstIndex(of: .options) else { return }
        for indexPath in tableView.indexPathsForVisibleRows ?? []
            where indexPath.section == section && indexPath.row < options.count
        {
            (tableView.cellForRow(at: indexPath) as? CreatePollTextCell)?
                .configure(optionConfiguration(at: indexPath.row))
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

    // MARK: Emoji

    /// ListComposePollOptionComponent's input mode button. Telegram swaps the keyboard for its emoji keyboard; here
    /// the composer's emoji picker opens over the screen, emoji only, and fills the field that was being edited.
    private func presentEmojiPicker(for field: TextField) {
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

    private func insertEmoji(_ emoji: String, customID: Int64?, in field: TextField) {
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
        if case .option(let id) = field,
           indexPath.flatMap({ tableView.cellForRow(at: $0) as? CreatePollTextCell })?.isEditingText != true
        {
            optionEditingChanged(id: id, isEditing: false)
        }
    }

    private func rowIndexPath(for field: TextField) -> IndexPath? {
        switch field {
        case .question:
            return sections.firstIndex(of: .text).map { IndexPath(row: 0, section: $0) }
        case .description:
            return sections.firstIndex(of: .text).map { IndexPath(row: 1, section: $0) }
        case .option(let id):
            guard let section = sections.firstIndex(of: .options),
                  let row = options.firstIndex(where: { $0.id == id }) else { return nil }
            return IndexPath(row: row, section: section)
        case .explanation:
            return sections.firstIndex(of: .explanation).map { IndexPath(row: 0, section: $0) }
        }
    }

    // MARK: Footers

    private func footerText(for section: Section) -> String? {
        switch section {
        case .text: nil
        case .options: optionsFooterText
        case .settings: limitsDuration ? L10n.telegram("CreatePoll.LimitDuration.HideResultsInfo") : nil
        case .explanation: L10n.telegram("CreatePoll.ExplanationInfo")
        }
    }

    private func configureFooter(_ footer: UITableViewHeaderFooterView, text: String?) {
        var content = footer.defaultContentConfiguration()
        content.text = text
        footer.contentConfiguration = content
    }

    /// Updates a footer in place, such as the count of options left, so a field being edited keeps its keyboard.
    private func refreshFooter(of kind: Section) {
        guard let section = sections.firstIndex(of: kind),
              let footer = tableView.footerView(forSection: section) else { return }
        let text = footerText(for: kind)
        guard (footer.contentConfiguration as? UIListContentConfiguration)?.text != text else { return }
        configureFooter(footer, text: text)
        updateRowHeights()
    }

    // MARK: Settings

    private func configureSettingsCell(_ cell: UITableViewCell, item: SettingsItem, animated: Bool) {
        if item == .duration {
            configureDurationCell(cell)
            return
        }
        guard let cell = cell as? CreatePollToggleCell else { return }
        let symbol: String?
        let tint: UIColor
        let titleKey: String
        let subtitleKey: String?
        let isOn: Bool
        var isEnabled = true
        // ComposePollScreen's settings with their icon colours.
        switch item {
        case .showWhoVoted:
            (symbol, tint, titleKey, subtitleKey) = (
                "eye.fill",
                UIColor(rgb: 0x0A84FF),
                "CreatePoll.ShowWhoVoted",
                "CreatePoll.ShowWhoVotedInfo",
            )
            isOn = !isAnonymous
        case .multipleAnswers:
            (symbol, tint, titleKey, subtitleKey) = (
                "checklist",
                UIColor(rgb: 0xFF9F0A),
                "CreatePoll.MultiAnswer",
                "CreatePoll.MultiAnswerInfo",
            )
            isOn = allowsMultipleAnswers
        case .addingOptions:
            (symbol, tint, titleKey, subtitleKey) = (
                "plus",
                UIColor(rgb: 0x32ADE6),
                "CreatePoll.AddingOptions",
                "CreatePoll.AddingOptionsInfo",
            )
            isOn = canAddOptions
            // A quiz's options are fixed: the toggle is locked.
            isEnabled = !isQuiz
        case .revoting:
            (symbol, tint, titleKey, subtitleKey) = (
                "arrow.triangle.2.circlepath",
                UIColor(rgb: 0x5E5CE6),
                "CreatePoll.Revoting",
                "CreatePoll.RevotingInfo",
            )
            isOn = canRevote
        case .shuffle:
            (symbol, tint, titleKey, subtitleKey) = (
                "shuffle",
                UIColor(rgb: 0xAF52DE),
                "CreatePoll.ShuffleOptions",
                "CreatePoll.ShuffleOptionsInfo",
            )
            isOn = shuffleOptions
        case .quiz:
            (symbol, tint, titleKey) = ("checkmark.square.fill", UIColor(rgb: 0x34C759), "CreatePoll.EnableQuiz")
            subtitleKey = allowsMultipleAnswers ? "CreatePoll.EnableQuizMultiInfo" : "CreatePoll.EnableQuizInfo"
            isOn = isQuiz
            isEnabled = forcedQuiz == nil
        case .limitDuration:
            (symbol, tint, titleKey, subtitleKey) = (
                "timer",
                UIColor(rgb: 0xFF453A),
                "CreatePoll.LimitDuration",
                "CreatePoll.LimitDurationInfo",
            )
            isOn = limitsDuration
        case .hideResults:
            (symbol, tint, titleKey, subtitleKey) = (nil, .clear, "CreatePoll.LimitDuration.HideResults", nil)
            isOn = hidesResults
        case .restrictToSubscribers:
            (symbol, tint, titleKey, subtitleKey) = (
                "person.fill",
                UIColor(rgb: 0x0A84FF),
                "CreatePoll.RestrictToSubscribers",
                "CreatePoll.RestrictToSubscribersInfo",
            )
            isOn = restrictsToSubscribers
        case .duration:
            return
        }
        cell.configure(
            title: L10n.telegram(titleKey),
            subtitle: subtitleKey.map { L10n.telegram($0) },
            image: symbol.flatMap { UIImage(systemName: $0) } ?? Self.emptyIcon,
            tint: tint,
            isOn: isOn,
            isEnabled: isEnabled,
            animated: animated,
        )
        cell.onChange = { [weak self] in self?.setToggle(item, isOn: $0) }
    }

    private func configureDurationCell(_ cell: UITableViewCell) {
        var content = UIListContentConfiguration.valueCell()
        switch timeLimit {
        case .duration(let seconds):
            content.text = L10n.telegram("CreatePoll.LimitDuration.Duration")
            content.secondaryText = SettingsFormatting.timeInterval(seconds: seconds)
        case .deadline(let time):
            content.text = L10n.telegram("CreatePoll.LimitDuration.PollEnds")
            content.secondaryText = Date(timeIntervalSince1970: TimeInterval(time))
                .formatted(date: .abbreviated, time: .shortened)
        }
        content.secondaryTextProperties.color = .secondaryLabel
        content.image = Self.emptyIcon
        content.imageProperties.maximumSize = CGSize(width: 25, height: 25)
        content.imageProperties.reservedLayoutSize = CGSize(width: 25, height: 0)
        cell.contentConfiguration = content
        cell.backgroundColor = .secondarySystemGroupedBackground
        let arrows = UIImageView(image: UIImage(systemName: "chevron.up.chevron.down"))
        arrows.tintColor = .tertiaryLabel
        cell.accessoryView = arrows
        cell.selectionStyle = .default
    }

    private func refreshSettingsCells() {
        guard let section = sections.firstIndex(of: .settings) else { return }
        let items = settingsItems
        for indexPath in tableView.indexPathsForVisibleRows ?? [] where indexPath.section == section {
            guard let item = items[safe: indexPath.row],
                  let cell = tableView.cellForRow(at: indexPath) else { continue }
            configureSettingsCell(cell, item: item, animated: true)
        }
    }

    /// ComposePollScreen's toggle actions with their side effects.
    private func setToggle(_ item: SettingsItem, isOn: Bool) {
        switch item {
        case .showWhoVoted:
            isAnonymous = !isOn
            if isAnonymous { canAddOptions = false }
        case .multipleAnswers:
            allowsMultipleAnswers = isOn
            // A single answer quiz keeps the first of its correct options.
            if !isOn, let first = options.first(where: { correctOptionIDs.contains($0.id) }) {
                correctOptionIDs = [first.id]
            }
            refreshOptionCells()
        case .addingOptions:
            guard !isQuiz else { break }
            if isOn, isAnonymous { isAnonymous = false }
            canAddOptions = isOn
        case .revoting:
            canRevote = isOn
        case .shuffle:
            shuffleOptions = isOn
        case .quiz:
            if forcedQuiz == nil { setQuiz(isOn) }
            return
        case .limitDuration:
            setLimitsDuration(isOn)
            return
        case .hideResults:
            hidesResults = isOn
        case .restrictToSubscribers:
            restrictsToSubscribers = isOn
        case .duration:
            break
        }
        refreshSettingsCells()
    }

    /// Set Correct Answer: a quiz takes no added options or revotes, checks its correct answers and has an explanation.
    private func setQuiz(_ isOn: Bool) {
        guard isQuiz != isOn else { return }
        let previousIndex = sections.firstIndex(of: .explanation)
        isQuiz = isOn
        if isOn {
            canAddOptions = false
            canRevote = false
        }
        let currentIndex = sections.firstIndex(of: .explanation)
        tableView.performBatchUpdates {
            if let previousIndex { self.tableView.deleteSections(IndexSet(integer: previousIndex), with: .fade) }
            if let currentIndex { self.tableView.insertSections(IndexSet(integer: currentIndex), with: .fade) }
        }
        updateTitle()
        refreshSettingsCells()
        refreshOptionCells()
    }

    /// Limit Duration shows the duration and Hide Results under it, and scrolls to them as Telegram does.
    private func setLimitsDuration(_ isOn: Bool) {
        guard limitsDuration != isOn, let section = sections.firstIndex(of: .settings) else { return }
        let previousItems = settingsItems
        limitsDuration = isOn
        let currentItems = settingsItems
        let deleted = previousItems.indices
            .filter { !currentItems.contains(previousItems[$0]) }
            .map { IndexPath(row: $0, section: section) }
        let inserted = currentItems.indices
            .filter { !previousItems.contains(currentItems[$0]) }
            .map { IndexPath(row: $0, section: section) }
        tableView.performBatchUpdates {
            self.tableView.deleteRows(at: deleted, with: .fade)
            self.tableView.insertRows(at: inserted, with: .fade)
        }
        refreshSettingsCells()
        refreshFooter(of: .settings)
        if let last = inserted.last {
            tableView.scrollToRow(at: last, at: .none, animated: true)
        }
    }

    /// presentTimeLimitOptions: the preset durations and Custom, which picks a deadline.
    private func presentTimeLimitOptions(from sourceView: UIView) {
        var actions = Self.durationPresets.map { seconds in
            TelegramContextMenuAction(title: SettingsFormatting.timeInterval(seconds: seconds)) { [weak self] in
                self?.setTimeLimit(.duration(seconds))
            }
        }
        actions.append(TelegramContextMenuAction(title: L10n.telegram("CreatePoll.TimeLimit.Custom")) { [weak self] in
            self?.presentDeadlinePicker()
        })
        presentTelegramContextMenu(sourceView: sourceView, actions: actions, presentationStyle: .menuOnly)
    }

    /// openCustomTimePicker: the deadline starts at the current duration's end.
    private func presentDeadlinePicker() {
        let now = Int(Date().timeIntervalSince1970)
        let initialTime: Int =
            switch timeLimit {
            case .duration(let seconds): now + seconds
            case .deadline(let time): time
            }
        let picker = PollDeadlinePickerViewController(
            initialTime: initialTime,
            maximumPeriod: maximumOpenPeriod,
        ) { [weak self] time in
            self?.setTimeLimit(.deadline(time))
        }
        let navigation = UINavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(navigation, animated: true)
    }

    private func setTimeLimit(_ limit: TimeLimit) {
        timeLimit = limit
        refreshSettingsCells()
    }

    /// ComposePollScreen's validatedInput: a question, at least one option and, in a quiz, a correct answer.
    private func validatedPoll() -> Validation {
        guard !question.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failed(L10n.telegram("CreatePoll.QuestionNeeded"))
        }
        let filled = options.filter { !$0.text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !filled.isEmpty else {
            return .failed(L10n.telegram(isQuiz ? "CreatePoll.OptionsNeeded" : "CreatePoll.OptionsNeededOne"))
        }
        let correctIndices = filled.indices.filter { correctOptionIDs.contains(filled[$0].id) }
        if isQuiz, correctIndices.isEmpty {
            return .failed(L10n.telegram(allowsMultipleAnswers
                    ? "CreatePoll.QuizCorrectOptionNeededMultiple"
                    : "CreatePoll.QuizCorrectOptionNeeded"))
        }
        let type: TDNativeInputPollType =
            if isQuiz {
                .inputPollTypeQuiz(TDNativeInputPollTypeQuiz(
                    correctOptionIds: correctIndices,
                    explanation: Self.pollText(explanation),
                    explanationMedia: nil,
                ))
            } else {
                .inputPollTypeRegular(TDNativeInputPollTypeRegular(allowAddingOptions: canAddOptions))
            }
        var openPeriod = 0
        var closeDate = 0
        if limitsDuration {
            switch timeLimit {
            case .duration(let seconds): openPeriod = seconds
            case .deadline(let time): closeDate = time
            }
        }
        return .ready(.inputMessagePoll(TDNativeInputMessagePoll(
            question: Self.pollText(question),
            options: filled.map { TDNativeInputPollOption(text: Self.pollText($0.text), media: nil) },
            description: Self.pollText(pollDescription),
            media: nil,
            isAnonymous: isAnonymous,
            // A poll with one option takes a single answer (`.poll(multipleAnswers: isMultiAnswer && count > 1)`).
            allowsMultipleAnswers: isQuiz ? allowsMultipleAnswers : allowsMultipleAnswers && filled.count > 1,
            allowsRevoting: canRevote,
            membersOnly: isChannel && restrictsToSubscribers,
            countryCodes: [],
            shuffleOptions: shuffleOptions,
            hideResultsUntilCloses: limitsDuration && hidesResults,
            type: type,
            openPeriod: openPeriod,
            closeDate: closeDate,
            isClosed: false,
        )))
    }

    @objc private func sendPressed() {
        switch validatedPoll() {
        case .ready(let content):
            guard !didSend else { return }
            didSend = true
            view.endEditing(true)
            let send = send
            let onDismiss = onDismiss
            dismiss(animated: true) {
                onDismiss?()
                send(content)
            }
        case .failed(let text):
            showToast(text)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    @objc private func cancelPressed() {
        if hasAnyData {
            confirmDiscard()
        } else {
            close()
        }
    }

    /// requestDismiss: Discard Poll? with No and Yes.
    private func confirmDiscard() {
        let alert = UIAlertController(
            title: nil,
            message: L10n.telegram("CreatePoll.DiscardPoll"),
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

    private func showToast(_ text: String) {
        let host: UIView = navigationController?.view ?? view
        let keyboardOverlap = max(0, host.keyboardLayoutGuide.layoutFrame.height - host.safeAreaInsets.bottom)
        TelegramUndoToast.show(text: text, in: host, bottomInset: 12 + keyboardOverlap, undo: nil)
    }

    private func updateTitle() {
        title = L10n.telegram(isQuiz ? "CreatePoll.QuizTitle" : "CreatePoll.Title")
    }

    /// TDLib's limits for the number of options and how long a poll may stay open.
    private func loadLimits() {
        let client = client
        Task { [weak self] in
            let answerCount = try? await client.getOption(name: "poll_answer_count_max")
            let openPeriod = try? await client.getOption(name: "poll_open_period_max")
            guard let self else { return }
            if case .optionValueInteger(let value) = openPeriod {
                maximumOpenPeriod = Int(clamping: value.value)
            }
            if case .optionValueInteger(let value) = answerCount {
                setMaximumOptionCount(max(1, Int(clamping: value.value)))
            }
        }
    }

    private func setMaximumOptionCount(_ count: Int) {
        guard count != maximumOptionCount else { return }
        let previousIDs = options.map(\.id)
        maximumOptionCount = count
        while options.count > max(2, count), options.last?.isEmpty == true {
            options.removeLast()
        }
        updateOptions(from: previousIDs)
    }
}

// MARK: - SheetDismissObserver

/// Reports a sheet the user swiped away.
@MainActor private final class SheetDismissObserver: NSObject, UIAdaptivePresentationControllerDelegate {
    private let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    func presentationControllerDidDismiss(_: UIPresentationController) {
        onDismiss()
    }
}

// MARK: - CreatePollTextCell

/// ListComposePollOptionComponent as a table row: a growing field with a hard character limit and, for an option, the
/// reorder or add indicator before it and a quiz's correct answer check, and the emoji button while it's edited.
/// Custom emoji stay whole: an edit that touches one replaces all of it.
private final class CreatePollTextCell: UITableViewCell, UITextViewDelegate {
    enum Indicator {
        /// The indicator's space without one, as the first empty option has.
        case blank
        case reorder
        case add
    }

    struct Check {
        var isSelected: Bool
        var allowsMultiple: Bool
    }

    struct Configuration {
        var text: NSAttributedString
        var placeholder: String
        var lengthLimit: Int
        var allowsLineFeeds = true
        var lineFeedLimit: Int?
        var returnKeyType = UIReturnKeyType.default
        var indicator: Indicator?
        var check: Check?
        /// ListComposePollOptionComponent's input mode button.
        var allowsEmoji = false
    }

    static let reuseIdentifier = "CreatePollTextCell"

    private static var font: UIFont {
        .preferredFont(forTextStyle: .body)
    }

    var onTextChange: ((NSAttributedString) -> Void)?
    var onReturn: (() -> Void)?
    var onDeleteBackwardWhenEmpty: (() -> Void)?
    var onEditingChange: ((Bool) -> Void)?
    var onHeightChange: (() -> Void)?
    var onToggleCheck: (() -> Void)?
    var onEmoji: (() -> Void)?

    private let textView = CreatePollTextView()
    private let placeholderLabel = UILabel()
    private let indicatorView = UIImageView()
    private let checkButton = UIButton(type: .system)
    private let emojiButton = UIButton(type: .system)
    private var configuration: Configuration?
    private var indicator: Indicator?

    /// The client whose account owns the field's custom emoji.
    var customEmojiClient: TDLibClient? {
        get { textView.customEmojiClient }
        set { textView.customEmojiClient = newValue }
    }

    var isEditingText: Bool {
        textView.isFirstResponder
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .secondarySystemGroupedBackground
        textView.font = Self.font
        textView.typingAttributes = typingAttributes(at: 0)
        textView.delegate = self
        textView.onDeleteBackwardWhenEmpty = { [weak self] in self?.onDeleteBackwardWhenEmpty?() }
        textView.onPasteTelegramText = { [weak self] in self?.insert($0) ?? false }
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        indicatorView.contentMode = .center
        indicatorView.tintColor = .placeholderText
        indicatorView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        checkButton.addTarget(self, action: #selector(checkPressed), for: .touchUpInside)
        emojiButton.setImage(
            UIImage(systemName: "face.smiling", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19)),
            for: .normal,
        )
        emojiButton.tintColor = .secondaryLabel
        emojiButton.accessibilityLabel = L10n.telegram("EmojiInput.TabEmoji")
        emojiButton.addTarget(self, action: #selector(emojiPressed), for: .touchUpInside)
        setEmojiButtonVisible(false, animated: false)
        let stack = UIStackView(arrangedSubviews: [indicatorView, checkButton, textView, emojiButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        contentView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            indicatorView.widthAnchor.constraint(equalToConstant: 22),
            checkButton.widthAnchor.constraint(equalToConstant: 26),
            checkButton.heightAnchor.constraint(equalToConstant: 26),
            emojiButton.widthAnchor.constraint(equalToConstant: 28),
            emojiButton.heightAnchor.constraint(equalToConstant: 28),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -11),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        resetActions()
    }

    func resetActions() {
        onTextChange = nil
        onReturn = nil
        onDeleteBackwardWhenEmpty = nil
        onEditingChange = nil
        onHeightChange = nil
        onToggleCheck = nil
        onEmoji = nil
    }

    func configure(_ configuration: Configuration) {
        self.configuration = configuration
        if textView.markedTextRange == nil, !textView.attributedText.isEqual(to: configuration.text) {
            textView.attributedText = configuration.text
            textView.typingAttributes = typingAttributes(at: textView.selectedRange.location)
            textView.updateCustomEmoji()
        }
        placeholderLabel.text = configuration.placeholder
        placeholderLabel.isHidden = !configuration.text.string.isEmpty
        if textView.returnKeyType != configuration.returnKeyType {
            textView.returnKeyType = configuration.returnKeyType
            if textView.isFirstResponder { textView.reloadInputViews() }
        }
        indicator = configuration.indicator
        setHidden(indicatorView, configuration.indicator == nil)
        indicatorView.image =
            switch configuration.indicator {
            case .reorder: UIImage(systemName: "line.3.horizontal")
            case .add: UIImage(systemName: "plus")
            case .blank, nil: nil
            }
        setHidden(checkButton, configuration.check == nil)
        if let check = configuration.check {
            let symbol =
                if check.allowsMultiple {
                    check.isSelected ? "checkmark.square.fill" : "square"
                } else {
                    check.isSelected ? "checkmark.circle.fill" : "circle"
                }
            checkButton.setImage(
                UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)),
                for: .normal,
            )
            checkButton.tintColor = check.isSelected ? .systemGreen : .tertiaryLabel
            checkButton.accessibilityTraits = check.isSelected ? [.button, .selected] : .button
        }
        setHidden(emojiButton, !configuration.allowsEmoji)
    }

    func beginEditing() {
        textView.becomeFirstResponder()
    }

    /// Inserts a picked emoji at the caret as one run, if it fits the field's limit.
    func insertEmoji(_ emoji: String, customID: Int64?) {
        guard !emoji.isEmpty else { return }
        let value = NSMutableAttributedString(attributedString: ComposerText
            .importing(NSAttributedString(string: emoji)))
        if let customID {
            ComposerText.setCustomEmoji(
                [TelegramCustomEmojiRun(id: customID, range: NSRange(location: 0, length: value.length))],
                in: value,
            )
        }
        _ = insert(value)
    }

    /// Whether a drag starting here is on the reorder indicator.
    func reorderHandleContains(_ point: CGPoint) -> Bool {
        guard indicator == .reorder, !indicatorView.isHidden else { return false }
        return indicatorView.convert(indicatorView.bounds, to: self).insetBy(dx: -14, dy: -14).contains(point)
    }

    func textViewDidBeginEditing(_: UITextView) {
        setEmojiButtonVisible(true, animated: true)
        onEditingChange?(true)
    }

    func textViewDidEndEditing(_: UITextView) {
        setEmojiButtonVisible(false, animated: true)
        onEditingChange?(false)
    }

    /// TextFieldComponent's character limit, which cuts what doesn't fit; in an option the return key moves on and
    /// pasted line breaks become spaces. A custom emoji is one glyph: a partial edit replaces the whole emoji.
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard let configuration else { return true }
        if !configuration.allowsLineFeeds, text == "\n" {
            onReturn?()
            return false
        }
        let current = textView.textStorage.string
        guard ComposerText.isValid(range, in: current as NSString) else { return false }
        textView.typingAttributes = typingAttributes(at: range.location)
        var editedRange = range
        for emoji in TelegramCustomEmojiRun.extract(from: textView.textStorage)
            where range.length > 0 && NSIntersectionRange(range, emoji.range).length > 0
        {
            editedRange = NSUnionRange(editedRange, emoji.range)
        }
        guard let bounds = Range(editedRange, in: current) else { return false }
        let kept = current.replacingCharacters(in: bounds, with: "")
        var replacement = configuration.allowsLineFeeds
            ? text
            : String(text.map { $0.isNewline ? " " : $0 })
        if let lineFeedLimit = configuration.lineFeedLimit {
            var allowed = max(0, lineFeedLimit - kept.filter(\.isNewline).count)
            replacement = String(replacement.compactMap { character -> Character? in
                guard character.isNewline else { return character }
                guard allowed > 0 else { return nil }
                allowed -= 1
                return character
            })
        }
        let available = max(0, configuration.lengthLimit - kept.count)
        if replacement.count > available { replacement = String(replacement.prefix(available)) }
        if replacement == text, editedRange == range { return true }
        guard let start = textView.position(from: textView.beginningOfDocument, offset: editedRange.location),
              let end = textView.position(from: start, offset: editedRange.length),
              let textRange = textView.textRange(from: start, to: end)
        else { return false }
        textView.replace(textRange, withText: replacement)
        textDidChange()
        return false
    }

    func textViewDidChange(_: UITextView) {
        textDidChange()
    }

    /// Puts `value` in place of the selection as the user's edit, if it fits the field's limits; pasted custom emoji
    /// come here too, and fall back to plain text when they don't fit.
    private func insert(_ value: NSAttributedString) -> Bool {
        guard let configuration else { return false }
        if value.string.contains(where: \.isNewline),
           !configuration.allowsLineFeeds || configuration.lineFeedLimit != nil
        {
            return false
        }
        if textView.markedTextRange != nil { textView.unmarkText() }
        let storage = textView.textStorage
        var range = textView.selectedRange
        if !ComposerText.isValid(range, in: storage.string as NSString) {
            range = NSRange(location: storage.length, length: 0)
        }
        var editedRange = range
        for emoji in TelegramCustomEmojiRun.extract(from: storage)
            where range.length > 0 && NSIntersectionRange(range, emoji.range).length > 0
        {
            editedRange = NSUnionRange(editedRange, emoji.range)
        }
        guard let bounds = Range(editedRange, in: storage.string) else { return false }
        let kept = storage.string.replacingCharacters(in: bounds, with: "")
        guard kept.count + value.string.count <= configuration.lengthLimit else { return false }
        storage.replaceCharacters(in: editedRange, with: value)
        textView.selectedRange = NSRange(location: editedRange.location + value.length, length: 0)
        textDidChange()
        return true
    }

    /// Keeps the custom emoji entities that still match their text, as the composer does, in the field's font.
    private func textDidChange() {
        let storage = textView.textStorage
        if textView.markedTextRange == nil {
            storage.beginEditing()
            ComposerText.refresh(storage)
            storage.addAttribute(.font, value: Self.font, range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
            textView.typingAttributes = typingAttributes(at: textView.selectedRange.location)
        }
        textView.updateCustomEmoji()
        reportChange()
    }

    /// The composer's typing attributes, which never carry a custom emoji on, in the field's font.
    private func typingAttributes(at location: Int) -> [NSAttributedString.Key: Any] {
        var attributes = ComposerText.typingAttributes(in: textView.textStorage, at: location)
        attributes[.font] = Self.font
        return attributes
    }

    private func reportChange() {
        let text = NSAttributedString(attributedString: textView.textStorage)
        guard configuration?.text.isEqual(to: text) != true else { return }
        configuration?.text = text
        placeholderLabel.isHidden = !text.string.isEmpty
        onTextChange?(text)
        let fitting = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
        if abs(fitting.height - textView.bounds.height) > 0.5 { onHeightChange?() }
    }

    private func setHidden(_ view: UIView, _ hidden: Bool) {
        if view.isHidden != hidden { view.isHidden = hidden }
    }

    /// The input mode button shows while the field is edited (ListComposePollOptionComponent's displaySelector).
    private func setEmojiButtonVisible(_ visible: Bool, animated: Bool) {
        emojiButton.isUserInteractionEnabled = visible
        let changes = { [emojiButton] in
            emojiButton.alpha = visible ? 1 : 0
            emojiButton.transform = visible ? .identity : CGAffineTransform(scaleX: 0.001, y: 0.001)
        }
        if animated {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState],
                animations: changes,
            )
        } else {
            changes()
        }
    }

    @objc private func checkPressed() {
        onToggleCheck?()
    }

    @objc private func emojiPressed() {
        onEmoji?()
    }
}

// MARK: - CreatePollTextView

/// Reports backspace in an empty field, which moves to the field before it (TextFieldComponent's backspaceKeyAction),
/// and pastes BetterTG's copied custom emoji.
private final class CreatePollTextView: CustomEmojiTextView {
    var onDeleteBackwardWhenEmpty: (() -> Void)?
    /// Takes pasted text with custom emoji; false pastes it as plain text.
    var onPasteTelegramText: ((NSAttributedString) -> Bool)?

    override func deleteBackward() {
        let wasEmpty = text.isEmpty
        super.deleteBackward()
        if wasEmpty { onDeleteBackwardWhenEmpty?() }
    }

    /// BetterTG's own pasteboard payload is the only trusted source of custom emoji, as in the composer.
    override func paste(_ sender: Any?) {
        if let data = UIPasteboard.general.data(forPasteboardType: TelegramEmojiPasteboardPayload.type),
           let payload = try? JSONDecoder().decode(TelegramEmojiPasteboardPayload.self, from: data),
           !payload.emojis.isEmpty
        {
            let value = NSMutableAttributedString(
                attributedString: ComposerText.importing(NSAttributedString(string: payload.text)),
            )
            payload.apply(to: value)
            ComposerText.setCustomEmoji(TelegramCustomEmojiRun.extract(from: value), in: value)
            if onPasteTelegramText?(value) == true { return }
        }
        super.paste(sender)
    }
}

// MARK: - CreatePollToggleCell

/// ComposePollScreen's ListActionItemComponent with a toggle: a tinted icon, the title with its description, and
/// the switch, locked when the setting doesn't apply.
private final class CreatePollToggleCell: UITableViewCell {
    static let reuseIdentifier = "CreatePollToggleCell"

    var onChange: ((Bool) -> Void)?

    private let toggle = UISwitch()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .secondarySystemGroupedBackground
        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        accessoryView = toggle
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onChange = nil
    }

    func configure(
        title: String,
        subtitle: String?,
        image: UIImage?,
        tint: UIColor,
        isOn: Bool,
        isEnabled: Bool,
        animated: Bool,
    ) {
        var content = subtitle == nil ? UIListContentConfiguration.cell() : .subtitleCell()
        content.text = title
        content.secondaryText = subtitle
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0
        content.textToSecondaryTextVerticalPadding = 3
        content.image = image
        content.imageProperties.tintColor = tint
        content.imageProperties.maximumSize = CGSize(width: 25, height: 25)
        content.imageProperties.reservedLayoutSize = CGSize(width: 25, height: 0)
        contentConfiguration = content
        if toggle.isOn != isOn { toggle.setOn(isOn, animated: animated) }
        toggle.isEnabled = isEnabled
    }

    @objc private func toggleChanged() {
        onChange?(toggle.isOn)
    }
}

// MARK: - PollDeadlinePickerViewController

/// ChatScheduleTimeScreen in its poll mode: a date and time wheel from the next minute on, up to TDLib's
/// `poll_open_period_max`, and Set Deadline.
private final class PollDeadlinePickerViewController: UIViewController {
    private let initialTime: Int
    private let maximumPeriod: Int?
    private let onSet: (Int) -> Void
    private let picker = UIDatePicker()
    private let setButton = UIButton(configuration: .filled())

    init(initialTime: Int, maximumPeriod: Int?, onSet: @escaping (Int) -> Void) {
        self.initialTime = initialTime
        self.maximumPeriod = maximumPeriod
        self.onSet = onSet
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("CreatePoll.Deadline.Title")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"),
            style: .plain,
            target: self,
            action: #selector(cancelPressed),
        )
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = 1
        let now = Date()
        let minuteStart = Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now
        let minimumDate = minuteStart.addingTimeInterval(60)
        picker.minimumDate = minimumDate
        if let maximumPeriod { picker.maximumDate = now.addingTimeInterval(TimeInterval(maximumPeriod)) }
        picker.date = max(minimumDate, Date(timeIntervalSince1970: TimeInterval(initialTime)))

        setButton.configuration?.title = L10n.telegram("CreatePoll.Deadline.SetDeadline")
        setButton.configuration?.cornerStyle = .large
        setButton.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = .systemFont(ofSize: 17, weight: .semibold)
            return attributes
        }
        setButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        setButton.addTarget(self, action: #selector(setPressed), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [picker, setButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    @objc private func cancelPressed() {
        dismiss(animated: true)
    }

    @objc private func setPressed() {
        let time = Int(picker.date.timeIntervalSince1970)
        let onSet = onSet
        dismiss(animated: true) { onSet(time) }
    }
}
