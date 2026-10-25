// ChatListDownloadsView.swift

import Combine
import TDLibKit
import UIKit

// MARK: - ChatListDownloadsView

/// ChatListSearchListPaneNode's Downloads pane over TDLib's download list (searchFileDownloads): the files still
/// downloading under Downloading, with Pause All or Resume All, then the finished ones under Recently Downloaded,
/// with Clear. A row shows the file's icon, name and size, or "x MB / y MB" over a 3 pt bar while it isn't done; a
/// tap pauses or resumes it, or opens a finished one's message, and a long press offers Delete from Cache or Cancel
/// Downloading and View in Chat. Telegram's Raise Priority, Increase Speed and selection aren't ported.
@MainActor final class ChatListDownloadsView: UIView, UITableViewDataSource, UITableViewDelegate {
    private enum Section: Int, CaseIterable {
        case downloading
        case downloaded
    }

    /// A finished file's message, or View in Chat.
    var onOpen: ((Message) -> Void)?
    /// Clear's Manage Device Storage.
    var onManageStorage: (() -> Void)?
    /// The controller the menus and the sheet present over.
    var presenter: (() -> UIViewController?)?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private var client: TDLibClient?
    private var query = ""
    private var downloading = [FileDownload]()
    private var downloaded = [FileDownload]()
    /// The files as their updates leave them, by ID.
    private var files = [Int: File]()
    private var loadTask: Task<Void, Never>?
    private var reloadWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemBackground
        tableView.separatorStyle = .none
        tableView.sectionHeaderTopPadding = 0
        tableView.keyboardDismissMode = .onDrag
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ChatListDownloadCell.self, forCellReuseIdentifier: ChatListDownloadCell.reuseIdentifier)
        tableView.register(
            ChatListSearchSectionHeaderView.self,
            forHeaderFooterViewReuseIdentifier: ChatListSearchSectionHeaderView.reuseIdentifier,
        )
        addSubview(tableView)
        let pressGesture = ContextMenuPressGestureRecognizer(target: self, action: #selector(rowLongPressed(_:)))
        pressGesture.pressedViewProvider = { [weak self] gesture in
            guard let self, let indexPath = tableView.indexPathForRow(at: gesture.location(in: tableView)) else {
                return nil
            }
            return tableView.cellForRow(at: indexPath)
        }
        tableView.addGestureRecognizer(pressGesture)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .preferredFont(forTextStyle: .subheadline)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.text = L10n.telegram("ChatList.Search.NoResultsDescription")
        emptyLabel.isHidden = true
        addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyLabel.topAnchor.constraint(equalTo: topAnchor, constant: 60),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
        ])
        observeUpdates()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        reloadWork?.cancel()
    }

    /// The downloaded file among the message's media.
    private static func file(of download: FileDownload) -> File? {
        let candidates: [File] =
            switch download.message.content {
            case .messageDocument(let value): [value.document.document]
            case .messageAudio(let value): [value.audio.audio]
            case .messageVideo(let value): [value.video.video]
            case .messageAnimation(let value): [value.animation.animation]
            case .messageVoiceNote(let value): [value.voiceNote.voice]
            case .messageVideoNote(let value): [value.videoNote.video]
            case .messagePhoto(let value): value.photo.sizes.map(\.photo)
            default: []
            }
        return candidates.first { $0.id == download.fileId }
    }

    /// The list for the query, the files whose names match it.
    func show(query: String, client: TDLibClient) {
        let changed = query != self.query || client.id != self.client?.id
        self.query = query
        self.client = client
        if changed { tableView.setContentOffset(.zero, animated: false) }
        reload()
    }

    func reset() {
        loadTask?.cancel()
        loadTask = nil
        client = nil
        downloading = []
        downloaded = []
        tableView.reloadData()
    }

    // MARK: UITableViewDataSource

    func numberOfSections(in _: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        list(Section(rawValue: section)).count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChatListDownloadCell.reuseIdentifier, for: indexPath)
        if let cell = cell as? ChatListDownloadCell, let download = download(at: indexPath) {
            configure(cell, with: download)
        }
        return cell
    }

    // MARK: UITableViewDelegate

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let section = Section(rawValue: section), !list(section).isEmpty,
              let header = tableView.dequeueReusableHeaderFooterView(
                  withIdentifier: ChatListSearchSectionHeaderView.reuseIdentifier,
              ) as? ChatListSearchSectionHeaderView else { return nil }
        switch section {
        case .downloading:
            // A list with every download paused offers to resume them all.
            let allPaused = downloading.allSatisfy(\.isPaused)
            header.configure(
                title: L10n.telegram("DownloadList.DownloadingHeader"),
                actionTitle: L10n.telegram(allPaused ? "DownloadList.ResumeAll" : "DownloadList.PauseAll"),
            ) { [weak self] in self?.setAllPaused(!allPaused) }
        case .downloaded:
            header.configure(
                title: L10n.telegram("DownloadList.DownloadedHeader"),
                actionTitle: L10n.telegram("DownloadList.Clear"),
            ) { [weak self] in self?.confirmClear() }
        }
        return header
    }

    func tableView(_: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        list(Section(rawValue: section)).isEmpty ? 0 : ChatListSearchSectionHeaderView.height
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let download = download(at: indexPath), let client else { return }
        guard download.completeDate == 0 else {
            onOpen?(download.message)
            return
        }
        // progressPressed: a tap pauses a download or resumes it.
        let fileID = download.fileId
        let pauses = !download.isPaused
        Task {
            _ = try? await client.send(TDNativeRequests.toggleDownloadIsPaused(fileId: fileID, isPaused: pauses))
        }
    }

    // MARK: Loading

    private func reload() {
        guard let client else { return }
        let query = query
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let found = try? await client.send(TDNativeRequests.searchFileDownloads(
                query: query,
                onlyActive: false,
                onlyCompleted: false,
                offset: "",
                limit: 100,
            ))
            guard let self, !Task.isCancelled, client.id == self.client?.id, let found else { return }
            loadTask = nil
            downloading = found.files.filter { $0.completeDate == 0 }
            // Recently Downloaded: the latest finished first.
            downloaded = found.files.filter { $0.completeDate != 0 }.sorted { $0.completeDate > $1.completeDate }
            for download in found.files {
                if let file = Self.file(of: download), files[file.id] == nil { files[file.id] = file }
            }
            tableView.reloadData()
            emptyLabel.isHidden = !(downloading.isEmpty && downloaded.isEmpty)
        }
    }

    /// The list changes in bursts (a file added, paused or finished); one reload follows each burst.
    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func observeUpdates() {
        nc.scopedPublisher(&cancellables, for: .updateFileAddedToDownloads) { [weak self] event in
            guard let self, event.source.clientID == client?.id else { return }
            scheduleReload()
        }
        nc.scopedPublisher(&cancellables, for: .updateFileDownload) { [weak self] event in
            guard let self, event.source.clientID == client?.id else { return }
            scheduleReload()
        }
        nc.scopedPublisher(&cancellables, for: .updateFileRemovedFromDownloads) { [weak self] event in
            guard let self, event.source.clientID == client?.id else { return }
            scheduleReload()
        }
        nc.scopedPublisher(&cancellables, for: .updateFile) { [weak self] event in
            let file = event.value.file
            guard let self, event.source.clientID == client?.id, files[file.id] != nil else { return }
            files[file.id] = file
            refreshRow(fileID: file.id)
        }
    }

    private func refreshRow(fileID: Int) {
        for (section, list) in [(Section.downloading, downloading), (.downloaded, downloaded)] {
            guard let row = list.firstIndex(where: { $0.fileId == fileID }),
                  let cell = tableView.cellForRow(at: IndexPath(row: row, section: section.rawValue))
                  as? ChatListDownloadCell else { continue }
            configure(cell, with: list[row])
        }
    }

    private func configure(_ cell: ChatListDownloadCell, with download: FileDownload) {
        guard let client else { return }
        let file = files[download.fileId] ?? Self.file(of: download)
        cell.configure(download: download, file: file, client: client)
    }

    private func list(_ section: Section?) -> [FileDownload] {
        switch section {
        case .downloading: downloading
        case .downloaded: downloaded
        case nil: []
        }
    }

    private func download(at indexPath: IndexPath) -> FileDownload? {
        let list = list(Section(rawValue: indexPath.section))
        return list.indices.contains(indexPath.row) ? list[indexPath.row] : nil
    }

    private func setAllPaused(_ paused: Bool) {
        guard let client else { return }
        Task {
            _ = try? await client.send(TDNativeRequests.toggleAllDownloadsArePaused(arePaused: paused))
        }
    }

    /// Clear's sheet: Downloaded Files with its note, Manage Device Storage, and Clear Download List, which empties
    /// Recently Downloaded and keeps the files.
    private func confirmClear() {
        guard let presenter = presenter?(), let client else { return }
        let sheet = UIAlertController(
            title: L10n.telegram("DownloadList.ClearAlertTitle"),
            // The text's line breaks fit Telegram's centred sheet; the alert wraps it itself.
            message: L10n.telegram("DownloadList.ClearAlertText").replacing("\n", with: " "),
            preferredStyle: .actionSheet,
        )
        sheet.addAction(UIAlertAction(title: L10n.telegram("DownloadList.OptionManageDeviceStorage"), style: .default) {
            [weak self] _ in self?.onManageStorage?()
        })
        sheet.addAction(UIAlertAction(title: L10n.telegram("DownloadList.ClearDownloadList"), style: .destructive) {
            _ in
            Task {
                _ = try? await client.send(TDNativeRequests.removeAllFilesFromDownloads(
                    onlyActive: false,
                    onlyCompleted: true,
                    deleteFromCache: false,
                ))
            }
        })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        // Telegram's ActionSheetController rises from the bottom; only a regular width anchors it.
        if traitCollection.horizontalSizeClass == .regular {
            sheet.popoverPresentationController?.sourceView = self
        }
        presenter.present(sheet, animated: true)
    }

    @objc private func rowLongPressed(_ gesture: ContextMenuPressGestureRecognizer) {
        guard gesture.state == .began, let client,
              let indexPath = tableView.indexPathForRow(at: gesture.location(in: tableView)),
              let download = download(at: indexPath), let cell = tableView.cellForRow(at: indexPath),
              let presenter = presenter?() else { return }
        let fileID = download.fileId
        var actions = [TelegramContextMenuAction]()
        if download.completeDate != 0 {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("DownloadList.DeleteFromCache"),
                image: UIImage(systemName: "trash"),
            ) {
                Task {
                    _ = try? await client.send(TDNativeRequests.removeFileFromDownloads(
                        fileId: fileID,
                        deleteFromCache: true,
                    ))
                }
            })
        } else {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("DownloadList.CancelDownloading"),
                image: UIImage(systemName: "xmark.circle"),
            ) {
                Task {
                    _ = try? await client.cancelDownloadFile(fileId: fileID, onlyIfPending: false)
                    _ = try? await client.send(TDNativeRequests.removeFileFromDownloads(
                        fileId: fileID,
                        deleteFromCache: true,
                    ))
                }
            })
        }
        let message = download.message
        actions.append(TelegramContextMenuAction(
            title: L10n.telegram("SharedMedia.ViewInChat"),
            image: UIImage(systemName: "bubble.left"),
        ) { [weak self] in self?.onOpen?(message) })
        presenter.presentTelegramContextMenu(
            sourceView: cell,
            actions: actions,
            tracking: gesture,
            presentationStyle: .message,
        )
    }
}

// MARK: - ChatListDownloadCell

/// ListMessageFileItemNode in the download list: the file's preview or extension icon, its name, the size, or
/// "x MB / y MB" in monospaced digits with a 3 pt bar from the text's edge while it isn't done.
final class ChatListDownloadCell: UITableViewCell {
    static let reuseIdentifier = "ChatListDownloadCell"

    private let iconView = UIImageView()
    private let extensionLabel = UILabel()
    private let previewView = TDImageLoadingView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let separator = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        for subview in [iconView, extensionLabel, previewView, titleLabel, descriptionLabel, progressView, separator] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        extensionLabel.textColor = .white
        extensionLabel.textAlignment = .center
        extensionLabel.adjustsFontSizeToFitWidth = true
        extensionLabel.minimumScaleFactor = 0.8
        previewView.contentMode = .scaleAspectFill
        previewView.clipsToBounds = true
        previewView.layer.cornerRadius = 6
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        descriptionLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        descriptionLabel.textColor = .secondaryLabel
        progressView.trackTintColor = .clear
        separator.backgroundColor = .separator
        let scale = max(1, UITraitCollection.current.displayScale)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),
            extensionLabel.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
            extensionLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor, constant: 5),
            extensionLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 36),
            previewView.leadingAnchor.constraint(equalTo: iconView.leadingAnchor),
            previewView.topAnchor.constraint(equalTo: iconView.topAnchor),
            previewView.widthAnchor.constraint(equalToConstant: 40),
            previewView.heightAnchor.constraint(equalToConstant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 65),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
            descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            descriptionLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -9),
            progressView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 3),
            separator.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / scale),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        previewView.cancel()
        previewView.image = nil
    }

    private static func extensionFont(size: CGFloat) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        return font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? font
    }

    /// The name, preview and placeholder ListMessageFileItemNode takes from the message's file.
    private static func presentation(of message: Message) -> (String, Thumbnail?, Minithumbnail?) {
        switch message.content {
        case .messageDocument(let value):
            let name = value.document.fileName.isEmpty ? L10n.telegram("Message.File") : value.document.fileName
            return (name, value.document.thumbnail, value.document.minithumbnail)
        case .messageAudio(let value):
            let title = [value.audio.performer, value.audio.title]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " – ")
            let name = title.isEmpty ? value.audio.fileName : title
            return (
                name.isEmpty ? L10n.telegram("Message.Audio") : name,
                value.audio.albumCoverThumbnail,
                value.audio.albumCoverMinithumbnail,
            )
        case .messageVideo(let value):
            let name = value.video.fileName.isEmpty ? L10n.telegram("Message.Video") : value.video.fileName
            return (name, value.video.thumbnail, value.video.minithumbnail)
        default:
            return (MessageContentPresentation.make(message).summary, nil, nil)
        }
    }

    func configure(download: FileDownload, file: File?, client: TDLibClient) {
        let (name, thumbnail, minithumbnail) = Self.presentation(of: download.message)
        titleLabel.text = name
        let fileExtension = FileExtensionIcon.fileExtension(of: name)
        iconView.image = FileExtensionIcon.image(for: fileExtension)
        extensionLabel.text = fileExtension
        extensionLabel.font = Self.extensionFont(size: (fileExtension?.count ?? 0) > 3 ? 14 : 15)
        if let thumbnail, case .thumbnailFormatJpeg = thumbnail.format {
            previewView.isHidden = false
            previewView.load(
                file: thumbnail.file,
                placeholderData: minithumbnail?.data,
                maximumPixelSize: 120,
                client: client,
            )
        } else {
            previewView.isHidden = true
        }
        let total = Int64(max(file?.size ?? 0, file?.expectedSize ?? 0))
        let downloaded = Int64(file?.local.downloadedSize ?? 0)
        let format: (Int64) -> String = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        let isDone = download.completeDate != 0 || file?.local.isDownloadingCompleted == true
        if isDone {
            descriptionLabel.text = total > 0 ? format(total) : nil
            progressView.isHidden = true
        } else {
            descriptionLabel.text = total > 0 ? "\(format(downloaded)) / \(format(total))" : nil
            progressView.isHidden = false
            progressView.progress = total > 0 ? Float(downloaded) / Float(total) : 0
        }
        accessibilityLabel = [name, descriptionLabel.text].compactMap(\.self).joined(separator: ", ")
    }
}
