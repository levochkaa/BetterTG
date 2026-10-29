// PollFileAttachmentViewController.swift

import TDLibKit
import UIKit

// MARK: - PollFileAttachmentViewController

/// AttachmentFileController in its `.recent` mode. Chat enables ordered selection and captions; Poll keeps its
/// immediate single pick. File with the subject's subtitle, Select from
/// Gallery and Select from Files, then RECENTLY SENT FILES (`searchMessages(location: .sentMedia(tags: [.file]))`,
/// TDLib's `searchOutgoingDocumentMessages`), or the files intro while there are none. A recent file is attached as
/// it was sent. Past ten recent files the search shows (AttachmentFileSearchItem): the same search with the query
/// after 0.6 s, YOUR CHATS with three files and Show More past four, No Results otherwise. A plain controller around
/// the table: AttachmentPanelView pins to the view's edges, which a table view as the root view would resolve against
/// its scrolling content.
@MainActor final class PollFileAttachmentViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,
UISearchResultsUpdating, TelegramConditionalNavigationSearchProvider, AttachmentPanelContent {
    // MARK: Private

    private enum Action: CaseIterable {
        case gallery
        case files

        var title: String {
            switch self {
            case .gallery: L10n.telegram("Attachment.SelectFromGallery")
            case .files: L10n.telegram("Attachment.SelectFromFiles")
            }
        }

        var symbolName: String {
            switch self {
            case .gallery: "photo"
            case .files: "icloud"
            }
        }
    }

    private typealias RecentFile = AttachmentRecentFile

    private static let cellIdentifier = "PollFileAttachmentCell"
    /// The search's page, as many as TDLib returns at once.
    private static let recentLimit = 100
    /// AttachmentFileController shows its search button past ten recent files.
    private static let searchThreshold = 10
    /// AttachmentFileSearchItem delays each query's search by 0.6 s.
    private static let searchDelay = Duration.milliseconds(600)
    /// AttachmentFileSearchItem's sections show three files and Show More past four until expanded.
    private static let collapsedLimit = 4
    private static let collapsedCount = 3

    // MARK: Internal

    var onSelectFromGallery: (() -> Void)?
    var onSelectFromFiles: (() -> Void)?
    var onPick: ((Document) -> Void)?
    var onBecomeVisible: (() -> Void)?
    /// Called once the sheet has gone after Cancel.
    var onDismiss: (() -> Void)?

    private(set) var replacementMessage: String?

    private var client: TDLibClient
    private let subtitle: String?
    private var sendCapabilities: AttachmentSendCapabilities?
    private var send: ((AttachmentFileSendRequest) async -> AttachmentFileSendResult)?
    private weak var attachmentPanel: AttachmentPanelView?
    /// nil is immediate single pick; an empty array is selection mode with no checked files.
    private var selected: [RecentFile]?
    private var comment = AttributedString()
    private var isSending = false
    private var isAwaitingClientReplacement = false
    private var replacementReady: (() -> Void)?
    private var clientGeneration = UUID()
    private var loadTask: Task<Void, Never>?

    private var canRetry = true
    private var retryOptions: TDNativeMessageSendOptions?
    #if DEBUG
        private var probeFiles: [RecentFile]?

        convenience init(
            probeFiles: [AttachmentRecentFile], sendCapabilities: AttachmentSendCapabilities? = nil,
            send: ((AttachmentFileSendRequest) async -> AttachmentFileSendResult)? = nil,
        ) {
            self.init(client: TDLib.shared.activeClient, subtitle: nil, sendCapabilities: sendCapabilities, send: send)
            self.probeFiles = probeFiles
        }
    #endif
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let search = UISearchController(searchResultsController: nil)
    /// nil until the search returns.
    private var recentFiles: [RecentFile]?
    private var query = ""
    private var searchTask: Task<Void, Never>?
    /// nil while the query's search runs; empty once it found nothing.
    private var foundFiles: [RecentFile]?
    private var expandsFoundFiles = false

    var shownTelegramNavigationSearch: UISearchController? {
        !isBusy && selected == nil && (recentFiles?.count ?? 0) > Self.searchThreshold ? search : nil
    }

    private var isBusy: Bool { isSending || isAwaitingClientReplacement }
    private var showsRecentFiles: Bool {
        recentFiles?.isEmpty == false
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedQuery.isEmpty
    }

    /// The found files shown, three of them until Show More while there are more than four.
    private var shownFoundFiles: [RecentFile] {
        guard let foundFiles else { return [] }
        guard !expandsFoundFiles, foundFiles.count > Self.collapsedLimit else { return foundFiles }
        return Array(foundFiles.prefix(Self.collapsedCount))
    }

    private var showsShowMore: Bool {
        !expandsFoundFiles && (foundFiles?.count ?? 0) > Self.collapsedLimit
    }

    init(
        client: TDLibClient, subtitle: String?, sendCapabilities: AttachmentSendCapabilities? = nil,
        send: ((AttachmentFileSendRequest) async -> AttachmentFileSendResult)? = nil,
    ) {
        self.client = client
        self.subtitle = subtitle
        self.sendCapabilities = sendCapabilities
        self.send = send
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Attachment.File")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.subtitle = subtitle
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"),
            style: .plain,
            target: self,
            action: #selector(cancelPressed),
        )
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        view.addSubview(tableView)
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        let press = ContextMenuPressGestureRecognizer(target: self, action: #selector(fileLongPressed(_:)))
        press.pressedViewProvider = { [weak self] gesture in
            guard let self, send != nil, !isBusy,
                  let path = tableView.indexPathForRow(at: gesture.location(in: tableView)), file(at: path) != nil
            else { return nil }
            return tableView.cellForRow(at: path)
        }
        tableView.addGestureRecognizer(press)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
        tableView.register(FileAttachmentCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        search.obscuresBackgroundDuringPresentation = false
        search.searchResultsUpdater = self
        search.searchBar.placeholder = L10n.telegram("Attachment.FilesSearchPlaceholder")
        loadRecentFiles()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onBecomeVisible?()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let panel = attachmentPanel, !panel.isHidden else { return }
        let panelTop = panel.convert(CGPoint.zero, to: view).y
        let tableBottom = tableView.convert(CGPoint(x: 0, y: tableView.bounds.maxY), to: view).y
        let automaticInset = tableView.adjustedContentInset.bottom - tableView.contentInset.bottom
        let inset = max(0, tableBottom - panelTop - automaticInset)
        if abs(tableView.contentInset.bottom - inset) > 0.5 {
            tableView.contentInset.bottom = inset
            tableView.verticalScrollIndicatorInsets.bottom = inset
        }
    }

    // MARK: Private

    /// ListMessageFileItemNode's file info: the size and the date it was sent.
    private static func details(of file: RecentFile) -> String {
        let size = max(file.document.document.size, file.document.document.expectedSize)
        let date = Foundation.Date(timeIntervalSince1970: TimeInterval(file.date))
            .formatted(date: .abbreviated, time: .omitted)
        guard size > 0 else { return date }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) • \(date)"
    }

    private static func emptyFooter(title: String?, text: String, top: CGFloat) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let title {
            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
            titleLabel.textColor = .secondaryLabel
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 0
            stack.addArrangedSubview(titleLabel)
        }
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        stack.addArrangedSubview(label)
        let footer = UIView()
        footer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: footer.topAnchor, constant: top),
            stack.leadingAnchor.constraint(equalTo: footer.layoutMarginsGuide.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: footer.layoutMarginsGuide.trailingAnchor, constant: -4),
            stack.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -16),
        ])
        return footer
    }

    private static func files(in messages: [Message]) -> [RecentFile] {
        messages.compactMap(RecentFile.init)
    }

    /// Wait for the old receipt before moving the picker. No new send may begin once replacement is requested.
    func prepareForClientReplacement(whenReady: @escaping () -> Void) {
        guard !isAwaitingClientReplacement else { return }
        isAwaitingClientReplacement = true
        replacementReady = whenReady
        if let text = attachmentPanel?.finishCommentEditing() { comment = text }
        updateBusyAppearance()
        finishClientReplacementPreparation()
    }

    func cancelClientReplacement() {
        isAwaitingClientReplacement = false
        replacementReady = nil
        updateBusyAppearance()
    }

    /// Rebind only after the old send and presentation have finished; stale search responses cannot repaint this UI.
    func resumeAfterClientReplacement(
        client: TDLibClient, capabilities: AttachmentSendCapabilities,
        onSelectTab: @escaping (AttachmentSheetTab) -> Void,
        send: @escaping (AttachmentFileSendRequest) async -> AttachmentFileSendResult,
    ) {
        precondition(!isSending && isAwaitingClientReplacement)
        clientGeneration = UUID()
        loadTask?.cancel()
        searchTask?.cancel()
        self.client = client
        sendCapabilities = capabilities
        self.send = send
        attachmentPanel?.updateCommentClient(client)
        attachmentPanel?.onSelectTab = onSelectTab
        isAwaitingClientReplacement = false
        replacementReady = nil
        updateBusyAppearance()
        loadRecentFiles()
        if !query.isEmpty {
            query = ""
            updateSearchResults(for: search)
        }
    }

    func configureAttachmentPanel(_ panel: AttachmentPanelView) {
        guard send != nil else { return }
        attachmentPanel = panel
        panel.configureCommentInput(comment, client: client) { [weak self] in self?.comment = $0 }
        panel.onBeginCommentEditing = { [weak self] in
            guard let sheet = self?.navigationController?.sheetPresentationController else { return }
            sheet.animateChanges { sheet.selectedDetentIdentifier = .large }
        }
        panel.onSend = { [weak self] in self?.sendSelected() }
        panel.onSendOptions = { [weak self] source, gesture in
            self?.showSendOptions(from: source, tracking: gesture)
        }
        updateSelection()
    }

    // MARK: Table

    func numberOfSections(in _: UITableView) -> Int {
        if isSearching { return 1 }
        return showsRecentFiles ? 2 : 1
    }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isSearching { return shownFoundFiles.count + (showsShowMore ? 1 : 0) }
        return section == 0 ? Action.allCases.count : recentFiles?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
        (cell as? FileAttachmentCell)?.setSelection(number: nil, visible: false)
        cell.accessibilityLabel = nil
        cell.accessibilityValue = nil
        cell.accessibilityCustomActions = nil
        if isSearching {
            if let file = shownFoundFiles[safe: indexPath.row] {
                configureFileCell(cell, file: file)
            } else {
                var content = UIListContentConfiguration.cell()
                content.text = L10n.telegram("MediaEditor.Audio.ShowMore")
                content.textProperties.color = .tintColor
                content.image = UIImage(systemName: "chevron.down")
                content.imageProperties.tintColor = .tintColor
                cell.contentConfiguration = content
                cell.accessibilityTraits = .button
            }
            return cell
        }
        if indexPath.section == 0 {
            let action = Action.allCases[indexPath.row]
            var content = UIListContentConfiguration.cell()
            content.text = action.title
            content.textProperties.color = .tintColor
            content.image = UIImage(systemName: action.symbolName)
            content.imageProperties.tintColor = .tintColor
            cell.contentConfiguration = content
            cell.accessibilityTraits = .button
            return cell
        }
        guard let file = recentFiles?[safe: indexPath.row] else { return cell }
        configureFileCell(cell, file: file)
        return cell
    }

    func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        if isSearching {
            return shownFoundFiles.isEmpty ? nil : L10n.telegram("Attachment.ChatsMusic")
        }
        return section == 1 ? L10n.telegram("Attachment.RecentlySentFiles").uppercased() : nil
    }

    /// AttachmentFileEmptyStateItem's intro, on one line per paragraph, once the search found no files; while
    /// searching, AttachmentFileSearchContainerNode's No Results and the query's description.
    func tableView(_: UITableView, viewForFooterInSection section: Int) -> UIView? {
        if isSearching {
            guard foundFiles?.isEmpty == true else { return nil }
            return Self.emptyFooter(
                title: L10n.telegram("ChatList.Search.NoResults"),
                text: L10n.telegram("ChatList.Search.NoResultsQueryDescription", trimmedQuery),
                top: 60,
            )
        }
        guard section == 0, recentFiles?.isEmpty == true else { return nil }
        return Self.emptyFooter(
            title: nil,
            text: L10n.telegram("Attachment.FilesIntro").replacing("\n", with: " "),
            top: 40,
        )
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !isBusy else { return }
        if isSearching {
            guard let file = shownFoundFiles[safe: indexPath.row] else {
                expandsFoundFiles = true
                tableView.reloadData()
                return
            }
            pick(file)
            return
        }
        guard indexPath.section != 0 else {
            switch Action.allCases[indexPath.row] {
            case .gallery: onSelectFromGallery?()
            case .files: onSelectFromFiles?()
            }
            return
        }
        guard let file = recentFiles?[safe: indexPath.row] else { return }
        pick(file)
    }

    // MARK: Search

    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text ?? ""
        guard text != query else { return }
        let previous = trimmedQuery
        query = text
        let trimmed = trimmedQuery
        guard trimmed != previous else { return }
        searchTask?.cancel()
        foundFiles = nil
        expandsFoundFiles = false
        setPanelHidden(!trimmed.isEmpty)
        tableView.reloadData()
        guard !trimmed.isEmpty else { return }
        #if DEBUG
            if let probeFiles {
                foundFiles = probeFiles.filter { $0.document.fileName.localizedCaseInsensitiveContains(trimmed) }
                tableView.reloadData()
                return
            }
        #endif
        let client = client
        let generation = clientGeneration
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.searchDelay)
            guard !Task.isCancelled else { return }
            let found = try? await client.send(TDNativeRequests.searchOutgoingDocumentMessages(
                query: trimmed,
                limit: Self.recentLimit,
            ))
            guard let self, !Task.isCancelled, clientGeneration == generation, trimmedQuery == trimmed else { return }
            foundFiles = Self.files(in: found?.messages ?? [])
            tableView.reloadData()
        }
    }

    private func finishClientReplacementPreparation() {
        guard isAwaitingClientReplacement, !isSending, !isPresentingTelegramContextMenu,
              let ready = replacementReady else { return }
        replacementReady = nil
        searchTask?.cancel()
        loadTask?.cancel()
        ready()
    }

    private func file(at indexPath: IndexPath) -> RecentFile? {
        if isSearching { return shownFoundFiles[safe: indexPath.row] }
        return indexPath.section == 1 ? recentFiles?[safe: indexPath.row] : nil
    }

    private func pick(_ file: RecentFile) {
        if selected != nil { select(file) }
        else if send != nil { sendFiles([file], caption: AttributedString(), options: nil) }
        else { onPick?(file.document) }
    }

    private func select(_ file: RecentFile) {
        guard !isBusy else { return }
        if selected == nil { selected = [] }
        if let index = selected?.firstIndex(where: { $0.id == file.id }) { selected?.remove(at: index) }
        else { selected?.append(file) }
        if isSearching || search.isActive {
            search.endTelegramNavigationSearch()
            updateSearchResults(for: search)
        }
        updateSelection()
    }

    private func updateSelection() {
        tableView.reloadData()
        attachmentPanel?.update(selectionCount: selected?.count ?? 0, caption: "")
        (navigationController as? TelegramNavigationController)?.refreshChrome(of: self)
    }

    @objc private func fileLongPressed(_ gesture: ContextMenuPressGestureRecognizer) {
        guard gesture.state == .began, send != nil, !isBusy,
              let path = tableView.indexPathForRow(at: gesture.location(in: tableView)),
              let file = file(at: path), let cell = tableView.cellForRow(at: path) else { return }
        presentTelegramContextMenu(
            sourceView: cell,
            actions: [TelegramContextMenuAction(
                title: L10n.telegram("Common.Select"), image: UIImage(systemName: "checkmark.circle"),
            ) { [weak self] in self?.select(file) }],
            tracking: gesture,
            presentationStyle: .menuOnly,
            onDismiss: { [weak self] in self?.finishClientReplacementPreparation() },
        )
    }

    private func showSendOptions(from source: UIView, tracking gesture: UIGestureRecognizer) {
        guard !isBusy, canRetry, selected?.isEmpty == false, let sendCapabilities else { return }
        let generation = clientGeneration
        let actions = sendCapabilities.menuActions { [weak self] timing in
            guard let self, !isBusy, clientGeneration == generation else { return }
            switch timing {
            case .now: sendSelected()
            case .silently: sendSelected(options: ChatVM.sendOptions(silent: true))
            case .whenOnline:
                sendSelected(options: ChatVM.sendOptions(schedulingState: .messageSchedulingStateSendWhenOnline))
            case .schedule:
                ScheduleMessagePickerViewController.present(
                    from: self, isReminder: sendCapabilities.isReminders,
                    showsSendWhenOnline: !sendCapabilities.isReminders && sendCapabilities.canSendWhenOnline,
                ) { [weak self] state in
                    guard let self, clientGeneration == generation else { return }
                    sendSelected(options: ChatVM.sendOptions(schedulingState: state))
                }
            }
        }
        guard !actions.isEmpty else { return }
        presentTelegramContextMenu(
            sourceView: source, actions: actions, tracking: gesture, presentationStyle: .sourceMorph,
            onDismiss: { [weak self] in self?.finishClientReplacementPreparation() },
        )
    }

    private func sendSelected(options: TDNativeMessageSendOptions? = nil) {
        guard !isBusy, let selected, !selected.isEmpty else { return }
        if let text = attachmentPanel?.finishCommentEditing() { comment = text }
        sendFiles(selected, caption: comment, options: options ?? retryOptions)
    }

    private func sendFiles(_ files: [RecentFile], caption: AttributedString, options: TDNativeMessageSendOptions?) {
        guard !isBusy, canRetry, let send else { return }
        let request = AttachmentFileSendRequest(files: files, caption: caption, options: options)
        setSending(true)
        Task { [weak self] in
            let result = await send(request)
            guard let self else { return }
            setSending(false)
            canRetry = result.canRetry
            attachmentPanel?.isUserInteractionEnabled = canRetry
            if result.error == nil, result.acceptedIDs == Set(files.map(\.id)) {
                setSending(true)
                let onDismiss = onDismiss
                dismiss(animated: true) { onDismiss?() }
            } else {
                retryOptions = options
                selected = files.filter { !result.acceptedIDs.contains($0.id) }
                // The caption belongs to the last item, which need not be the last receipt in a partial album.
                comment =
                    if let last = files.last, result.acceptedIDs.contains(last.id) {
                        AttributedString()
                    } else {
                        caption
                    }
                attachmentPanel?.setCommentText(comment)
                updateSelection()
                replacementMessage = result.acceptedIDs.isEmpty
                    ? nil
                    : ChatSendContextError.partialAlbum(sent: result.acceptedIDs.count, expected: files.count)
                        .localizedDescription
                if !result.canRetry { replacementMessage = result.error }
                if isAwaitingClientReplacement {
                    finishClientReplacementPreparation()
                    return
                }
                let alert = UIAlertController(
                    title: nil, message: result.error ?? L10n.telegram("Login.UnknownError"), preferredStyle: .alert,
                )
                alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    private func setSending(_ sending: Bool) {
        isSending = sending
        updateBusyAppearance()
    }

    private func updateBusyAppearance() {
        view.isUserInteractionEnabled = !isBusy
        navigationItem.leftBarButtonItem?.isEnabled = !isBusy
        navigationController?.isModalInPresentation = isBusy
        if isBusy {
            let progress = UIActivityIndicatorView(style: .medium)
            progress.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: progress)
        } else {
            navigationItem.rightBarButtonItem = nil
        }
        (navigationController as? TelegramNavigationController)?.refreshChrome(of: self)
    }

    private func configureFileCell(_ cell: UITableViewCell, file: RecentFile) {
        var content = UIListContentConfiguration.subtitleCell()
        content.text = file.document.fileName.isEmpty ? L10n.telegram("Message.File") : file.document.fileName
        content.textProperties.lineBreakMode = .byTruncatingMiddle
        content.secondaryText = Self.details(of: file)
        content.secondaryTextProperties.color = .secondaryLabel
        content.image = UIImage(systemName: "doc.fill")
        content.imageProperties.tintColor = .tintColor
        if selected != nil { content.directionalLayoutMargins.leading = 54 }
        cell.contentConfiguration = content
        let number = selected?.firstIndex(where: { $0.id == file.id }).map { $0 + 1 }
        (cell as? FileAttachmentCell)?.setSelection(number: number, visible: selected != nil)
        cell.accessibilityLabel = content.text
        cell.accessibilityTraits = number == nil ? .button : [.button, .selected]
        cell.accessibilityValue = number.map(String.init)
        if send != nil, selected == nil {
            cell.accessibilityCustomActions = [UIAccessibilityCustomAction(name: L10n.telegram("Common.Select")) {
                [weak self] _ in
                self?.select(file)
                return true
            }]
        }
    }

    /// AttachmentFileController hides the attachment panel while it searches.
    private func setPanelHidden(_ hidden: Bool) {
        for panel in view.subviews where panel is AttachmentPanelView {
            panel.isHidden = hidden
        }
    }

    private func loadRecentFiles() {
        #if DEBUG
            if let probeFiles {
                recentFiles = probeFiles
                tableView.reloadData()
                return
            }
        #endif
        loadTask?.cancel()
        let client = client
        let generation = clientGeneration
        loadTask = Task { [weak self] in
            let found = try? await client.send(TDNativeRequests.searchOutgoingDocumentMessages(
                query: "",
                limit: Self.recentLimit,
            ))
            guard let self, !Task.isCancelled, clientGeneration == generation else { return }
            recentFiles = Self.files(in: found?.messages ?? [])
            tableView.reloadData()
            (navigationController as? TelegramNavigationController)?.refreshChrome(of: self)
        }
    }

    @objc private func cancelPressed() {
        guard !isBusy else { return }
        let onDismiss = onDismiss
        dismiss(animated: true) { onDismiss?() }
    }
}

// MARK: - FileAttachmentCell

/// ListMessageFileItem's numbered selection lives before the file icon and leaves the label's width available.
private final class FileAttachmentCell: UITableViewCell {
    private let selectionBadge = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionBadge.translatesAutoresizingMaskIntoConstraints = false
        selectionBadge.font = .systemFont(ofSize: 14, weight: .semibold)
        selectionBadge.textAlignment = .center
        selectionBadge.layer.cornerRadius = 12
        selectionBadge.layer.borderWidth = 1.5
        selectionBadge.clipsToBounds = true
        selectionBadge.isAccessibilityElement = false
        addSubview(selectionBadge)
        NSLayoutConstraint.activate([
            selectionBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            selectionBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            selectionBadge.widthAnchor.constraint(equalToConstant: 24),
            selectionBadge.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        // UIKit replaces the cell's content view when applying a list content configuration.
        bringSubviewToFront(selectionBadge)
    }

    func setSelection(number: Int?, visible: Bool) {
        selectionBadge.isHidden = !visible
        selectionBadge.text = number.map(String.init)
        selectionBadge.backgroundColor = number == nil ? .clear : .tintColor
        selectionBadge.textColor = .white
        selectionBadge.layer.borderColor = (number == nil ? UIColor.separator : tintColor).cgColor
        bringSubviewToFront(selectionBadge)
    }
}
