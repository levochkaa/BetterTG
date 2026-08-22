// ChatView.swift

import Combine
import PhotosUI
import TDLibKit
import UIKit

final class ChatViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching,
    PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate
{
    // MARK: Lifecycle

    init(customChat: CustomChat) {
        self.chatVM = ChatVM(customChat: customChat)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        prefetchTasks.values.forEach { $0.cancel() }
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureNavigationItem()
        configureCollectionView()
        configureDataSource()
        observeState()
        updateSnapshot(animated: false)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isMovingFromParent || navigationController?.isBeingDismissed == true else { return }
        Task { [chatVM] in await chatVM.updateDraft() }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        let isAwayFromLatest = scrollView.contentOffset.y + scrollView.adjustedContentInset.top > 160
        let targetAlpha = isAwayFromLatest ? CGFloat(1) : 0
        guard scrollToLatestButton.alpha != targetAlpha else { return }
        UIView.animate(withDuration: 0.2) { self.scrollToLatestButton.alpha = targetAlpha }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }
        PhotoPickerSelectionLoader.load(results) { [weak self] images in
            self?.chatVM.displayedImages = images
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any],
    ) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        Task { [weak self] in
            let selected = await Task.detached(priority: .userInitiated) { writeImage(image) }.value
            guard let selected else { return }
            self?.chatVM.displayedImages = [selected]
        }
    }

    func collectionView(_: UICollectionView, willDisplay _: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let messageID = dataSource.itemIdentifier(for: indexPath) else { return }
        chatVM.viewMessage(id: messageID)
        if indexPath.item >= max(chatVM.messages.count - 5, 0) {
            chatVM.loadMessages()
        }
    }

    func collectionView(
        _: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard let messageID = dataSource.itemIdentifier(for: indexPath),
              let message = message(for: messageID) else { return nil }
        return UIContextMenuConfiguration(
            identifier: NSNumber(value: messageID),
            previewProvider: nil,
        ) { [weak self] _ in
            self?.menu(for: message)
        }
    }

    func collectionView(_: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard let messageID = dataSource.itemIdentifier(for: indexPath),
                  let message = message(for: messageID),
                  prefetchTasks[messageID] == nil
            else { continue }
            prefetchTasks[messageID] = Task { [weak self] in
                await TDMediaPrefetcher.prefetch(message: message.message)
                await MainActor.run { self?.prefetchTasks[messageID] = nil }
            }
        }
    }

    func collectionView(_: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard let id = dataSource.itemIdentifier(for: indexPath) else { continue }
            prefetchTasks[id]?.cancel()
            prefetchTasks[id] = nil
        }
    }

    // MARK: Private

    private enum Section {
        case messages
    }

    private let chatVM: ChatVM
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Int64>!
    private var cancellables = Set<AnyCancellable>()
    private var messageCancellables = Set<AnyCancellable>()
    private var prefetchTasks = [Int64: Task<Void, Never>]()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let avatarView = ProfileAvatarView()
    private lazy var composerView = ChatComposerView(chatVM: chatVM)
    private let scrollToLatestButton = UIButton(type: .system)
    private let unreadBadgeLabel = UILabel()
    private var didPresentMicrophoneError = false
    private var lastHighlightedMessageID: Int64?

    private func makeLayout() -> UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(80),
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 5
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        return UICollectionViewCompositionalLayout(section: section)
    }

    private func configureNavigationItem() {
        let titleStack = UIStackView(arrangedSubviews: [titleLabel, statusLabel])
        titleStack.axis = .vertical
        titleStack.alignment = .center
        titleStack.spacing = 0
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.textColor = .secondaryLabel
        navigationItem.titleView = titleStack

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 32),
            avatarView.heightAnchor.constraint(equalToConstant: 32),
        ])
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: avatarView)
        updateChatHeader()
        updateStatus()
    }

    private func configureCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .black
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.showsVerticalScrollIndicator = false
        collectionView.transform = CGAffineTransform(scaleX: 1, y: -1)
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.register(MessageCell.self, forCellWithReuseIdentifier: MessageCell.reuseIdentifier)
        view.addSubview(collectionView)
        var constraints = [
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ]
        if chatVM.customChat.canPostMessages {
            view.keyboardLayoutGuide.usesBottomSafeArea = true
            composerView.onPickPhotos = { [weak self] in self?.showPhotoPicker() }
            composerView.onTakePhoto = { [weak self] in self?.showCamera() }
            composerView.onScrollToMessage = { [weak self] id in self?.scrollToMessage(id: id) }
            view.addSubview(composerView)
            constraints.append(contentsOf: [
                composerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5),
                composerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -5),
                composerView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -5),
                collectionView.bottomAnchor.constraint(equalTo: composerView.topAnchor, constant: -5),
            ])
        } else {
            constraints.append(collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor))
        }
        configureScrollToLatestButton(bottomAnchor: chatVM.customChat.canPostMessages
            ? composerView.topAnchor
            : view.safeAreaLayoutGuide.bottomAnchor)
        NSLayoutConstraint.activate(constraints)
    }

    private func configureScrollToLatestButton(bottomAnchor: NSLayoutYAxisAnchor) {
        scrollToLatestButton.translatesAutoresizingMaskIntoConstraints = false
        scrollToLatestButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        scrollToLatestButton.backgroundColor = .secondarySystemBackground
        scrollToLatestButton.tintColor = .systemBlue
        scrollToLatestButton.layer.cornerRadius = 22
        scrollToLatestButton.layer.borderWidth = 1
        scrollToLatestButton.layer.borderColor = UIColor.systemBlue.cgColor
        scrollToLatestButton.alpha = 0
        scrollToLatestButton.accessibilityLabel = "Scroll to latest message"
        scrollToLatestButton.addTarget(self, action: #selector(scrollToLatest), for: .touchUpInside)
        unreadBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        unreadBadgeLabel.backgroundColor = .systemBlue
        unreadBadgeLabel.textColor = .white
        unreadBadgeLabel.font = .preferredFont(forTextStyle: .caption2)
        unreadBadgeLabel.textAlignment = .center
        unreadBadgeLabel.layer.cornerRadius = 9
        unreadBadgeLabel.clipsToBounds = true
        scrollToLatestButton.addSubview(unreadBadgeLabel)
        view.addSubview(scrollToLatestButton)
        NSLayoutConstraint.activate([
            scrollToLatestButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            scrollToLatestButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            scrollToLatestButton.widthAnchor.constraint(equalToConstant: 44),
            scrollToLatestButton.heightAnchor.constraint(equalToConstant: 44),
            unreadBadgeLabel.topAnchor.constraint(equalTo: scrollToLatestButton.topAnchor, constant: -5),
            unreadBadgeLabel.centerXAnchor.constraint(equalTo: scrollToLatestButton.centerXAnchor),
            unreadBadgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
            unreadBadgeLabel.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, Int64>(
            collectionView: collectionView,
        ) { [weak self] collectionView, indexPath, messageID in
            guard let self,
                  let cell = collectionView.dequeueReusableCell(
                      withReuseIdentifier: MessageCell.reuseIdentifier,
                      for: indexPath,
                  ) as? MessageCell,
                  let message = message(for: messageID)
            else { return UICollectionViewCell() }
            cell.configure(
                message: message,
                chat: chatVM.customChat,
                highlighted: chatVM.highlightedMessageId == messageID,
                onReplyTap: { [weak self] id in self?.scrollToMessage(id: id) },
                onMediaTap: { [weak self] messages, selection in self?.showMedia(messages, selection: selection) },
            )
            return cell
        }
    }

    private func observeState() {
        chatVM.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    updateStatus()
                    composerView.update(from: chatVM)
                    updateHighlightState()
                    presentMicrophoneErrorIfNeeded()
                }
            }
            .store(in: &cancellables)
        chatVM.messagesDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.updateSnapshot(animated: true) }
            }
            .store(in: &cancellables)
        chatVM.customChat
            .$chat
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateChatHeader() }
            }
            .store(in: &cancellables)
        chatVM.customChat
            .$unreadCount
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatus() } }
            .store(in: &cancellables)
        subscribeToMessages()
    }

    private func updateChatHeader() {
        let chat = chatVM.customChat.chat
        titleLabel.text = chat.title
        avatarView.configure(
            file: chat.photo?.big,
            minithumbnail: chat.photo?.minithumbnail,
            title: chat.title,
            id: chat.id,
        )
    }

    private func subscribeToMessages() {
        messageCancellables.removeAll()
        for message in chatVM.messages {
            message.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self, messageID = message.id] in
                    DispatchQueue.main.async { self?.reconfigureMessage(id: messageID) }
                }
                .store(in: &messageCancellables)
        }
    }

    private func updateStatus() {
        let status = chatVM.actionStatus.isEmpty ? chatVM.onlineStatus : chatVM.actionStatus
        statusLabel.text = status
        statusLabel.isHidden = status.isEmpty
        statusLabel.textColor = !chatVM.actionStatus.isEmpty || status == "online" ? .systemBlue : .secondaryLabel
        let unreadCount = chatVM.customChat.unreadCount
        unreadBadgeLabel.text = unreadCount > 99 ? "99+" : "\(unreadCount)"
        unreadBadgeLabel.isHidden = unreadCount == 0
        scrollToLatestButton.accessibilityValue = unreadCount == 0 ? nil : "\(unreadCount) unread"
    }

    private func updateSnapshot(animated: Bool) {
        guard isViewLoaded else { return }
        subscribeToMessages()
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int64>()
        snapshot.appendSections([.messages])
        snapshot.appendItems(chatVM.messages.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: animated)
        collectionView.backgroundView = chatVM.messages.isEmpty ? emptyLabel() : nil
    }

    private func reconfigureMessage(id: Int64) {
        var snapshot = dataSource.snapshot()
        guard snapshot.indexOfItem(id) != nil else { return }
        snapshot.reconfigureItems([id])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func updateHighlightState() {
        let changed = [lastHighlightedMessageID, chatVM.highlightedMessageId].compactMap(\.self)
        lastHighlightedMessageID = chatVM.highlightedMessageId
        guard !changed.isEmpty else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(changed.filter { snapshot.indexOfItem($0) != nil })
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func emptyLabel() -> UIView {
        let label = UILabel()
        label.text = "No messages"
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.transform = CGAffineTransform(scaleX: 1, y: -1)
        return label
    }

    private func message(for id: Int64) -> CustomMessage? {
        chatVM.messages.first(where: { $0.id == id })
    }

    private func scrollToMessage(id: Int64) {
        guard let index = dataSource.snapshot().indexOfItem(id) else { return }
        collectionView.scrollToItem(at: IndexPath(item: index, section: 0), at: .centeredVertically, animated: true)
        chatVM.highlightedMessageId = id
        Task.main(delay: 0.7) { [weak chatVM] in chatVM?.highlightedMessageId = nil }
    }

    private func showMedia(_ messages: [Message], selection: Int64) {
        present(MediaGalleryViewController(messages: messages, selection: selection), animated: true)
    }

    @objc private func scrollToLatest() {
        guard !chatVM.messages.isEmpty else { return }
        collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .bottom, animated: true)
    }

    private func showPhotoPicker() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 10
        configuration.selection = .ordered
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func showCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            let alert = UIAlertController(title: "Camera unavailable", message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentMicrophoneErrorIfNeeded() {
        guard chatVM.errorShown, !didPresentMicrophoneError else { return }
        didPresentMicrophoneError = true
        chatVM.errorShown = false
        let alert = UIAlertController(
            title: "Microphone Access Required",
            message: "Enable Microphone in Settings → BetterTG to record voice messages.",
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.didPresentMicrophoneError = false
        })
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { [weak self] _ in
            self?.didPresentMicrophoneError = false
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }

    private func menu(for message: CustomMessage) -> UIMenu {
        var elements = [UIMenuElement]()
        if message.properties.canBeReplied {
            elements
                .append(UIAction(
                    title: "Reply",
                    image: UIImage(systemName: "arrowshape.turn.up.left"),
                ) { [weak self] _ in
                    self?.chatVM.replyMessage = message
                })
        }
        if message.properties.canBeEdited {
            elements.append(UIAction(title: "Edit", image: UIImage(systemName: "square.and.pencil")) { [weak self] _ in
                self?.chatVM.editCustomMessage = message
                self?.chatVM.setEditMessageText(from: message.message)
            })
        }
        if let text = formattedText(from: message.message.content) {
            elements.append(UIAction(
                title: "Copy",
                image: UIImage(systemName: "rectangle.portrait.on.rectangle.portrait"),
            ) { _ in UIPasteboard.setFormattedText(text) })
        }

        let deleteSelf = UIAction(
            title: "Delete only for me",
            image: UIImage(systemName: "trash"),
            attributes: .destructive,
        ) { [weak self] _ in self?.chatVM.deleteMessage(id: message.id, deleteForBoth: false) }
        let deleteAll = UIAction(
            title: "Delete for both",
            image: UIImage(systemName: "trash.fill"),
            attributes: .destructive,
        ) { [weak self] _ in self?.chatVM.deleteMessage(id: message.id, deleteForBoth: true) }
        if message.properties.canBeDeletedOnlyForSelf, message.properties.canBeDeletedForAllUsers {
            elements.append(UIMenu(
                title: "Delete",
                image: UIImage(systemName: "trash"),
                children: [deleteSelf, deleteAll],
            ))
        } else if message.properties.canBeDeletedForAllUsers {
            elements.append(deleteAll)
        } else if message.properties.canBeDeletedOnlyForSelf {
            elements.append(deleteSelf)
        }
        return UIMenu(children: elements)
    }

    private func formattedText(from content: MessageContent) -> FormattedText? {
        switch content {
        case .messageText(let text):
            text.text.text.isEmpty ? nil : text.text
        case .messagePhoto(let photo):
            photo.caption.text.isEmpty ? nil : photo.caption
        case .messageVoiceNote(let voice):
            voice.caption.text.isEmpty ? nil : voice.caption
        case .messageAnimation(let animation):
            animation.caption.text.isEmpty ? nil : animation.caption
        case .messageVideo(let video):
            video.caption.text.isEmpty ? nil : video.caption
        default:
            nil
        }
    }
}
