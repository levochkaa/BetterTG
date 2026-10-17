// PollFileAttachmentViewController.swift

import TDLibKit
import UIKit

// MARK: - PollFileAttachmentViewController

/// AttachmentFileController in its `.recent` mode with a poll source: File with the subject's subtitle, Select from
/// Gallery and Select from Files, then RECENTLY SENT FILES (`searchMessages(location: .sentMedia(tags: [.file]))`,
/// TDLib's `searchOutgoingDocumentMessages`), or the files intro while there are none. A recent file is attached as
/// it was sent. A plain controller around the table: AttachmentPanelView pins to the view's edges, which a table view
/// as the root view would resolve against its scrolling content.
@MainActor final class PollFileAttachmentViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
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

    // MARK: Internal

    var onSelectFromGallery: (() -> Void)?
    var onSelectFromFiles: (() -> Void)?
    var onPick: ((Document) -> Void)?
    /// Called once the sheet has gone after Cancel.
    var onDismiss: (() -> Void)?

    private let client: TDLibClient
    private let subtitle: String?
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    /// nil until the search returns.
    private var recentFiles: [RecentFile]?

    private var showsRecentFiles: Bool {
        recentFiles?.isEmpty == false
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
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
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

    // MARK: Table

    func numberOfSections(in _: UITableView) -> Int {
        showsRecentFiles ? 2 : 1
    }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? Action.allCases.count : recentFiles?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
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
        var content = UIListContentConfiguration.subtitleCell()
        content.text = file.document.fileName.isEmpty ? L10n.telegram("Message.File") : file.document.fileName
        content.textProperties.lineBreakMode = .byTruncatingMiddle
        content.secondaryText = Self.details(of: file)
        content.secondaryTextProperties.color = .secondaryLabel
        content.image = UIImage(systemName: "doc.fill")
        content.imageProperties.tintColor = .tintColor
        cell.contentConfiguration = content
        cell.accessibilityTraits = .button
        return cell
    }

    func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 ? L10n.telegram("Attachment.RecentlySentFiles").uppercased() : nil
    }

    /// AttachmentFileEmptyStateItem's intro, on one line per paragraph, once the search found no files.
    func tableView(_: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section == 0, recentFiles?.isEmpty == true else { return nil }
        let label = UILabel()
        label.text = L10n.telegram("Attachment.FilesIntro").replacingOccurrences(of: "\n", with: " ")
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        let footer = UIView()
        footer.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: footer.topAnchor, constant: 40),
            label.leadingAnchor.constraint(equalTo: footer.layoutMarginsGuide.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: footer.layoutMarginsGuide.trailingAnchor, constant: -4),
            label.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -16),
        ])
        return footer
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
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

    private func loadRecentFiles() {
        let client = client
        Task { [weak self] in
            let found = try? await client.send(TDNativeRequests.searchOutgoingDocumentMessages(
                query: "",
                limit: Self.recentLimit,
            ))
            guard let self else { return }
            recentFiles = (found?.messages ?? []).compactMap { message in
                guard case .messageDocument(let value) = message.content else { return nil }
                return RecentFile(date: message.date, document: value.document)
            }
            tableView.reloadData()
        }
    }

    @objc private func cancelPressed() {
        let onDismiss = onDismiss
        dismiss(animated: true) { onDismiss?() }
    }
}
