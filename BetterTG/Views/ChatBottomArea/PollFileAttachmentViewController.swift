// PollFileAttachmentViewController.swift

import TDLibKit
import UIKit

// MARK: - PollFileAttachmentViewController

/// AttachmentFileController in its `.recent` mode with a poll source: File with the subject's subtitle, Select from
/// Gallery and Select from Files, then RECENTLY SENT FILES (`searchMessages(location: .sentMedia(tags: [.file]))`,
/// TDLib's `searchOutgoingDocumentMessages`), or the files intro while there are none. A recent file is attached as
/// it was sent. Past ten recent files the search shows (AttachmentFileSearchItem): the same search with the query
/// after 0.6 s, YOUR CHATS with three files and Show More past four, No Results otherwise. A plain controller around
/// the table: AttachmentPanelView pins to the view's edges, which a table view as the root view would resolve against
/// its scrolling content.
@MainActor final class PollFileAttachmentViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,
UISearchResultsUpdating, TelegramConditionalNavigationSearchProvider {
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

    private struct RecentFile {
        let date: Int
        let document: Document
    }

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
    /// Called once the sheet has gone after Cancel.
    var onDismiss: (() -> Void)?

    private let client: TDLibClient
    private let subtitle: String?
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
        (recentFiles?.count ?? 0) > Self.searchThreshold ? search : nil
    }

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

    init(client: TDLibClient, subtitle: String?) {
        self.client = client
        self.subtitle = subtitle
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Attachment.File")
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
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        search.obscuresBackgroundDuringPresentation = false
        search.searchResultsUpdater = self
        search.searchBar.placeholder = L10n.telegram("Attachment.FilesSearchPlaceholder")
        loadRecentFiles()
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
        messages.compactMap { message in
            guard case .messageDocument(let value) = message.content else { return nil }
            return RecentFile(date: message.date, document: value.document)
        }
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
            text: L10n.telegram("Attachment.FilesIntro").replacingOccurrences(of: "\n", with: " "),
            top: 40,
        )
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if isSearching {
            guard let file = shownFoundFiles[safe: indexPath.row] else {
                expandsFoundFiles = true
                tableView.reloadData()
                return
            }
            onPick?(file.document)
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
        onPick?(file.document)
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
        let client = client
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.searchDelay)
            guard !Task.isCancelled else { return }
            let found = try? await client.send(TDNativeRequests.searchOutgoingDocumentMessages(
                query: trimmed,
                limit: Self.recentLimit,
            ))
            guard let self, !Task.isCancelled, trimmedQuery == trimmed else { return }
            foundFiles = Self.files(in: found?.messages ?? [])
            tableView.reloadData()
        }
    }

    private func configureFileCell(_ cell: UITableViewCell, file: RecentFile) {
        var content = UIListContentConfiguration.subtitleCell()
        content.text = file.document.fileName.isEmpty ? L10n.telegram("Message.File") : file.document.fileName
        content.textProperties.lineBreakMode = .byTruncatingMiddle
        content.secondaryText = Self.details(of: file)
        content.secondaryTextProperties.color = .secondaryLabel
        content.image = UIImage(systemName: "doc.fill")
        content.imageProperties.tintColor = .tintColor
        cell.contentConfiguration = content
        cell.accessibilityTraits = .button
    }

    /// AttachmentFileController hides the attachment panel while it searches.
    private func setPanelHidden(_ hidden: Bool) {
        for panel in view.subviews where panel is AttachmentPanelView {
            panel.isHidden = hidden
        }
    }

    private func loadRecentFiles() {
        let client = client
        Task { [weak self] in
            let found = try? await client.send(TDNativeRequests.searchOutgoingDocumentMessages(
                query: "",
                limit: Self.recentLimit,
            ))
            guard let self else { return }
            recentFiles = Self.files(in: found?.messages ?? [])
            tableView.reloadData()
            (navigationController as? TelegramNavigationController)?.refreshChrome(of: self)
        }
    }

    @objc private func cancelPressed() {
        let onDismiss = onDismiss
        dismiss(animated: true) { onDismiss?() }
    }
}
