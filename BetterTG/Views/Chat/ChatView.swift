// ChatView.swift

import Combine
import PhotosUI
import TDLibKit
import UIKit

final class ChatViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching,
    PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate,
    UIGestureRecognizerDelegate
{
    enum PresentationMode {
        case full
        case contextPreview
    }

    // MARK: Lifecycle

    init(
        customChat: CustomChat,
        presentationMode: PresentationMode = .full,
        targetMessageID: Int64? = nil,
    ) {
        self.presentationMode = presentationMode
        self.chatVM = ChatVM(customChat: customChat, previewing: presentationMode == .contextPreview)
        self.targetMessageID = targetMessageID
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
        view.backgroundColor = .systemBackground
        configureCollectionView()
        configureNavigationBar()
        configureDataSource()
        observeState()
        updateSnapshot(animated: false)
        if let targetMessageID {
            scrollToMessage(id: targetMessageID)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard presentationMode == .full else { return }
        guard isMovingFromParent || navigationController?.isBeingDismissed == true else { return }
        Task { [chatVM] in await chatVM.updateDraft() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if presentationMode == .full {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG
        guard presentationMode == .full,
              ProcessInfo.processInfo.arguments.contains("-ui-smoke-keyboard")
        else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.composerView.focusInput()
        }
        #endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollToLatestButton.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
        if showsComposer {
            let keyboardAttached = view.keyboardLayoutGuide.layoutFrame.minY
                < view.bounds.maxY - view.safeAreaInsets.bottom - 1
            composerView.setKeyboardAttached(keyboardAttached)
            updateComposerFloatingState(keyboardAttached)
        }
        updateHistoryInsets()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        navigationBarHeightConstraint?.constant = view.safeAreaInsets.top + TelegramChatNavigationBar.contentHeight
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        updateScrollToLatestButtonVisibility(animated: true)
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
        if presentationMode == .full {
            chatVM.viewMessage(id: messageID)
        }
        if indexPath.item >= max(chatVM.messages.count - 5, 0) {
            chatVM.loadMessages()
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

    private let presentationMode: PresentationMode
    private let targetMessageID: Int64?
    private let chatVM: ChatVM
    private let historyContainerView = UIView()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Int64>!
    private var cancellables = Set<AnyCancellable>()
    private var messageCancellables = Set<AnyCancellable>()
    private var prefetchTasks = [Int64: Task<Void, Never>]()
    private let customNavigationBar = TelegramChatNavigationBar()
    private var navigationBarHeightConstraint: NSLayoutConstraint!
    private lazy var composerView = ChatComposerView(chatVM: chatVM)
    private let scrollToLatestButton = UIButton(type: .system)
    private let unreadBadgeLabel = UILabel()
    private var scrollToLatestButtonVisible = false
    private var didPresentMicrophoneError = false
    private var lastHighlightedMessageID: Int64?
    private var didPerformInitialScroll = false
    private var pendingScrollMessageID: Int64?
    private var searchTask: Task<Void, Never>?
    private var messageSearchActive = false
    private var composerLeadingConstraint: NSLayoutConstraint?
    private var composerTrailingConstraint: NSLayoutConstraint?
    private var composerBottomConstraint: NSLayoutConstraint?
    private var composerKeyboardAttached = false

    private var showsComposer: Bool {
        presentationMode == .full && chatVM.customChat.canPostMessages
    }

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

    private func configureNavigationBar() {
        customNavigationBar.translatesAutoresizingMaskIntoConstraints = false
        customNavigationBar.onBack = presentationMode == .full ? { NavigationStorage.shared.pop() } : nil
        customNavigationBar.onSearchQueryChange = { [weak self] query in
            self?.searchMessages(query: query)
        }
        customNavigationBar.onSearchActiveChange = { [weak self] active in
            guard let self else { return }
            messageSearchActive = active
            composerView.setHiddenForSearch(active)
            updateScrollToLatestButtonVisibility(animated: true)
            if !active {
                searchTask?.cancel()
                customNavigationBar.setSearchResultFound(nil)
            }
            view.setNeedsLayout()
        }
        if presentationMode == .contextPreview {
            customNavigationBar.isUserInteractionEnabled = false
            customNavigationBar.setBackButtonHidden(true)
        }
        view.addSubview(customNavigationBar)
        navigationBarHeightConstraint = customNavigationBar.heightAnchor.constraint(
            equalToConstant: view.safeAreaInsets.top + TelegramChatNavigationBar.contentHeight,
        )
        NSLayoutConstraint.activate([
            customNavigationBar.topAnchor.constraint(equalTo: view.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationBarHeightConstraint,
        ])
        updateChatHeader()
        updateStatus()
    }

    private func configureCollectionView() {
        historyContainerView.translatesAutoresizingMaskIntoConstraints = false
        historyContainerView.transform = CGAffineTransform(scaleX: 1, y: -1)
        view.addSubview(historyContainerView)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = presentationMode == .full ? .interactive : .none
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.showsVerticalScrollIndicator = false
        collectionView.topEdgeEffect.isHidden = true
        collectionView.bottomEdgeEffect.isHidden = true
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.register(MessageCell.self, forCellWithReuseIdentifier: MessageCell.reuseIdentifier)
        if presentationMode == .full {
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(historyTapped))
            tapGesture.cancelsTouchesInView = false
            tapGesture.delegate = self
            collectionView.addGestureRecognizer(tapGesture)
            messageContextGesture.delegate = self
            collectionView.addGestureRecognizer(messageContextGesture)
        }
        historyContainerView.addSubview(collectionView)
        var constraints = [
            historyContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            historyContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            historyContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            historyContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.topAnchor.constraint(equalTo: historyContainerView.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: historyContainerView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: historyContainerView.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: historyContainerView.bottomAnchor),
        ]
        if showsComposer {
            view.keyboardLayoutGuide.usesBottomSafeArea = false
            composerView.onPickPhotos = { [weak self] in self?.showPhotoPicker() }
            composerView.onTakePhoto = { [weak self] in self?.showCamera() }
            composerView.onScrollToMessage = { [weak self] id in self?.scrollToMessage(id: id) }
            view.addSubview(composerView)
            let leadingConstraint = composerView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
            let trailingConstraint = composerView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            let bottomConstraint = composerView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
            composerLeadingConstraint = leadingConstraint
            composerTrailingConstraint = trailingConstraint
            composerBottomConstraint = bottomConstraint
            constraints.append(contentsOf: [
                leadingConstraint,
                trailingConstraint,
                bottomConstraint,
            ])
        }
        if presentationMode == .full {
            configureScrollToLatestButton(bottomAnchor: showsComposer
                ? composerView.topAnchor
                : view.safeAreaLayoutGuide.bottomAnchor)
        }
        NSLayoutConstraint.activate(constraints)
    }

    private func configureScrollToLatestButton(bottomAnchor: NSLayoutYAxisAnchor) {
        scrollToLatestButton.translatesAutoresizingMaskIntoConstraints = false
        scrollToLatestButton.setImage(UIImage(systemName: "arrow.down"), for: .normal)
        scrollToLatestButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 15, weight: .bold),
            forImageIn: .normal,
        )
        scrollToLatestButton.tintColor = .label
        scrollToLatestButton.backgroundColor = .secondarySystemBackground
        scrollToLatestButton.layer.cornerRadius = 18
        scrollToLatestButton.layer.borderWidth = 1 / view.traitCollection.displayScale
        scrollToLatestButton.layer.borderColor = UIColor.separator.cgColor
        scrollToLatestButton.layer.shadowColor = UIColor.black.cgColor
        scrollToLatestButton.layer.shadowOpacity = 0.2
        scrollToLatestButton.layer.shadowRadius = 7
        scrollToLatestButton.layer.shadowOffset = CGSize(width: 0, height: 3)
        scrollToLatestButton.alpha = 0
        scrollToLatestButton.transform = CGAffineTransform(translationX: 0, y: 18).scaledBy(x: 0.72, y: 0.72)
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
            scrollToLatestButton.widthAnchor.constraint(equalToConstant: 36),
            scrollToLatestButton.heightAnchor.constraint(equalToConstant: 36),
            unreadBadgeLabel.topAnchor.constraint(equalTo: scrollToLatestButton.topAnchor, constant: -5),
            unreadBadgeLabel.centerXAnchor.constraint(equalTo: scrollToLatestButton.centerXAnchor),
            unreadBadgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
            unreadBadgeLabel.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    private func updateScrollToLatestButtonVisibility(animated: Bool) {
        let isAwayFromLatest = collectionView.contentOffset.y + collectionView.adjustedContentInset.top > 160
        let visible = isAwayFromLatest && !messageSearchActive
        guard scrollToLatestButtonVisible != visible else { return }
        scrollToLatestButtonVisible = visible
        let changes = {
            self.scrollToLatestButton.alpha = visible ? 1 : 0
            self.scrollToLatestButton.transform = visible
                ? .identity
                : CGAffineTransform(translationX: 0, y: 18).scaledBy(x: 0.72, y: 0.72)
        }
        guard animated else {
            changes()
            return
        }
        UIView.animate(
            withDuration: visible ? 0.38 : 0.2,
            delay: 0,
            usingSpringWithDamping: 0.78,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: changes,
        )
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
                onReplyTap: { [weak self] id in
                    guard self?.presentationMode == .full else { return }
                    self?.scrollToMessage(id: id)
                },
                onMediaTap: { [weak self] messages, selection in
                    guard self?.presentationMode == .full else { return }
                    self?.showMedia(messages, selection: selection)
                },
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
        let status = chatVM.actionStatus.isEmpty ? chatVM.onlineStatus : chatVM.actionStatus
        let statusColor: UIColor = !chatVM.actionStatus.isEmpty || status == "online" ? .systemBlue : .secondaryLabel
        customNavigationBar.configure(title: chat.title, status: status, statusColor: statusColor)
        customNavigationBar.configureAvatar(
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
        let statusColor: UIColor = !chatVM.actionStatus.isEmpty || status == "online" ? .systemBlue : .secondaryLabel
        customNavigationBar.configure(
            title: chatVM.customChat.chat.title,
            status: status,
            statusColor: statusColor,
        )
        let unreadCount = chatVM.customChat.unreadCount
        unreadBadgeLabel.text = unreadCount > 99 ? "99+" : "\(unreadCount)"
        unreadBadgeLabel.isHidden = unreadCount == 0
        scrollToLatestButton.accessibilityValue = unreadCount == 0 ? nil : "\(unreadCount) unread"
    }

    private func updateSnapshot(animated: Bool) {
        guard isViewLoaded else { return }
        subscribeToMessages()
        let shouldKeepLatestVisible = !didPerformInitialScroll || isNearLatest
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int64>()
        snapshot.appendSections([.messages])
        snapshot.appendItems(chatVM.messages.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
            guard let self, !snapshot.itemIdentifiers.isEmpty else { return }
            if let pendingScrollMessageID {
                self.pendingScrollMessageID = nil
                scrollToLoadedMessage(id: pendingScrollMessageID)
            } else if shouldKeepLatestVisible {
                scrollToLatestMessage(animated: false)
            }
            didPerformInitialScroll = true
        }
        collectionView.backgroundView = chatVM.messages.isEmpty ? emptyLabel() : nil
    }

    private func reconfigureMessage(id: Int64) {
        var snapshot = dataSource.snapshot()
        guard snapshot.indexOfItem(id) != nil else { return }
        snapshot.reconfigureItems([id])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func updateHighlightState() {
        let changed = Array(Set([lastHighlightedMessageID, chatVM.highlightedMessageId].compactMap(\.self)))
        lastHighlightedMessageID = chatVM.highlightedMessageId
        guard !changed.isEmpty else { return }
        var snapshot = dataSource.snapshot()
        let presentIdentifiers = changed.filter { snapshot.indexOfItem($0) != nil }
        guard !presentIdentifiers.isEmpty else { return }
        snapshot.reconfigureItems(presentIdentifiers)
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

    private var isNearLatest: Bool {
        collectionView.contentOffset.y + collectionView.adjustedContentInset.top < 100
    }

    private func updateHistoryInsets() {
        let visualBottomInset: CGFloat
        if messageSearchActive {
            visualBottomInset = max(
                view.safeAreaInsets.bottom,
                view.bounds.maxY - view.keyboardLayoutGuide.layoutFrame.minY,
            ) + 8
        } else if showsComposer, composerView.frame.minY > 0 {
            visualBottomInset = max(view.safeAreaInsets.bottom, view.bounds.maxY - composerView.frame.minY) + 10
        } else {
            visualBottomInset = view.safeAreaInsets.bottom + 8
        }
        let visualTopInset = customNavigationBar.frame.maxY + 8
        let updatedInsets = UIEdgeInsets(top: visualBottomInset, left: 0, bottom: visualTopInset, right: 0)
        guard abs(collectionView.contentInset.top - updatedInsets.top) > 0.5
            || abs(collectionView.contentInset.bottom - updatedInsets.bottom) > 0.5
        else { return }

        let userIsScrolling = collectionView.isTracking || collectionView.isDragging || collectionView.isDecelerating
        let keepLatestVisible = !didPerformInitialScroll || (!userIsScrolling && isNearLatest)
        let previousOffset = collectionView.contentOffset
        let previousVisualBottomInset = collectionView.contentInset.top
        collectionView.contentInset = updatedInsets
        collectionView.verticalScrollIndicatorInsets = updatedInsets
        if keepLatestVisible {
            pinToLatestEdge(animated: false)
        } else if !userIsScrolling {
            collectionView.setContentOffset(
                CGPoint(
                    x: previousOffset.x,
                    y: previousOffset.y - (updatedInsets.top - previousVisualBottomInset),
                ),
                animated: false,
            )
        } else {
            collectionView.setContentOffset(previousOffset, animated: false)
        }
    }

    private func updateComposerFloatingState(_ keyboardAttached: Bool) {
        guard composerKeyboardAttached != keyboardAttached else { return }
        composerKeyboardAttached = keyboardAttached
        composerLeadingConstraint?.constant = keyboardAttached ? 8 : 0
        composerTrailingConstraint?.constant = keyboardAttached ? -8 : 0
        composerBottomConstraint?.constant = keyboardAttached ? -8 : 0
    }

    private func message(for id: Int64) -> CustomMessage? {
        chatVM.messages.first(where: { $0.id == id })
    }

    private func scrollToMessage(id: Int64) {
        if let displayedID = chatVM.displayedMessageID(containing: id) {
            scrollToLoadedMessage(id: displayedID)
            return
        }
        Task { [weak self] in
            guard let self, let displayedID = await chatVM.ensureMessageLoaded(id: id) else { return }
            pendingScrollMessageID = displayedID
            updateSnapshot(animated: false)
        }
    }

    private func scrollToLoadedMessage(id: Int64) {
        guard let index = dataSource.snapshot().indexOfItem(id) else { return }
        collectionView.scrollToItem(at: IndexPath(item: index, section: 0), at: .centeredVertically, animated: true)
        chatVM.highlightedMessageId = id
        Task.main(delay: 0.7) { [weak chatVM] in chatVM?.highlightedMessageId = nil }
    }

    private func showMedia(_ messages: [Message], selection: Int64) {
        present(MediaGalleryViewController(messages: messages, selection: selection), animated: true)
    }

    @objc private func scrollToLatest() {
        scrollToLatestMessage(animated: true)
    }

    private func scrollToLatestMessage(animated: Bool) {
        guard dataSource.snapshot().numberOfItems > 0 else { return }
        pinToLatestEdge(animated: animated)
    }

    private func pinToLatestEdge(animated: Bool) {
        collectionView.layoutIfNeeded()
        collectionView.setContentOffset(
            CGPoint(x: 0, y: -collectionView.adjustedContentInset.top),
            animated: animated,
        )
    }

    private func searchMessages(query: String) {
        searchTask?.cancel()
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            customNavigationBar.setSearchResultFound(nil)
            return
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            let result = try? await td.searchChatMessages(
                chatId: chatVM.customChat.id,
                filter: nil,
                fromMessageId: 0,
                limit: 50,
                offset: 0,
                query: normalizedQuery,
                senderId: nil,
                topicId: nil,
            )
            guard !Task.isCancelled else { return }
            let firstID = result?.messages.first?.id
            customNavigationBar.setSearchResultFound(firstID != nil)
            if let firstID {
                scrollToMessage(id: firstID)
            }
        }
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

    @objc private func messageLongPressed(_ gesture: TelegramContextGestureRecognizer) {
        guard gesture.state == .began else { return }
        cancelHistoryPanGesture()
        let point = gesture.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point),
              let messageID = dataSource.itemIdentifier(for: indexPath),
              let message = message(for: messageID),
              let cell = collectionView.cellForItem(at: indexPath) as? MessageCell
        else { return }
        let baseTransform = pressedMessageSourceView === cell.contextPreviewView
            ? pressedMessageSourceTransform
            : cell.contextPreviewView.transform
        let presented = presentTelegramContextMenu(
            sourceView: cell.contextPreviewView,
            actions: menu(for: message),
            tracking: gesture,
            sourceBaseTransform: baseTransform,
            performsInitialFeedback: false,
        )
        if !presented {
            restorePressedMessageSource()
        }
    }

    @objc private func historyTapped() {
        view.endEditing(true)
    }

    func beginMessageSearch() {
        guard presentationMode == .full else { return }
        customNavigationBar.beginSearch()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer,
    ) -> Bool {
        if gestureRecognizer === messageContextGesture || otherGestureRecognizer === messageContextGesture {
            if gestureRecognizer is UIPanGestureRecognizer || otherGestureRecognizer is UIPanGestureRecognizer {
                return false
            }
        }
        return true
    }

    private lazy var messageContextGesture: TelegramContextGestureRecognizer = {
        let gesture = TelegramContextGestureRecognizer(target: self, action: #selector(messageLongPressed(_:)))
        gesture.onPressingChanged = { [weak self, weak gesture] pressing in
            guard let self, let gesture else { return }
            if pressing {
                let point = gesture.location(in: collectionView)
                guard let indexPath = collectionView.indexPathForItem(at: point),
                      let cell = collectionView.cellForItem(at: indexPath) as? MessageCell
                else { return }
                pressedMessageSourceView = cell.contextPreviewView
                pressedMessageSourceTransform = cell.contextPreviewView.transform
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.72)
                UIView.animate(
                    withDuration: 0.16,
                    delay: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
                ) {
                    cell.contextPreviewView.transform = self.pressedMessageSourceTransform.scaledBy(x: 0.98, y: 0.98)
                }
            } else {
                restorePressedMessageSource()
            }
        }
        return gesture
    }()
    private weak var pressedMessageSourceView: UIView?
    private var pressedMessageSourceTransform = CGAffineTransform.identity

    private func cancelHistoryPanGesture() {
        let panGesture = collectionView.panGestureRecognizer
        guard panGesture.state == .began || panGesture.state == .changed else { return }
        panGesture.isEnabled = false
        panGesture.isEnabled = true
    }

    private func restorePressedMessageSource() {
        guard let sourceView = pressedMessageSourceView else { return }
        let transform = pressedMessageSourceTransform
        pressedMessageSourceView = nil
        UIView.animate(
            withDuration: 0.16,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
        ) {
            sourceView.transform = transform
        }
    }

    private func menu(for message: CustomMessage) -> [TelegramContextMenuAction] {
        var elements = [TelegramContextMenuAction]()
        if message.properties.canBeReplied {
            elements
                .append(TelegramContextMenuAction(
                    title: "Reply",
                    image: UIImage(systemName: "arrowshape.turn.up.left"),
                ) { [weak self] in
                    self?.chatVM.replyMessage = message
                })
        }
        if message.properties.canBeEdited {
            elements.append(TelegramContextMenuAction(
                title: "Edit",
                image: UIImage(systemName: "square.and.pencil"),
            ) { [weak self] in
                self?.chatVM.editCustomMessage = message
                self?.chatVM.setEditMessageText(from: message.message)
            })
        }
        if let text = formattedText(from: message.message.content) {
            elements.append(TelegramContextMenuAction(
                title: "Copy",
                image: UIImage(systemName: "rectangle.portrait.on.rectangle.portrait"),
            ) { UIPasteboard.setFormattedText(text) })
        }

        let deleteSelf = TelegramContextMenuAction(
            title: "Delete only for me",
            image: UIImage(systemName: "trash"),
            isDestructive: true,
            startsNewSection: true,
        ) { [weak self] in self?.chatVM.deleteMessage(id: message.id, deleteForBoth: false) }
        let deleteAll = TelegramContextMenuAction(
            title: "Delete for both",
            image: UIImage(systemName: "trash.fill"),
            isDestructive: true,
            startsNewSection: true,
        ) { [weak self] in self?.chatVM.deleteMessage(id: message.id, deleteForBoth: true) }
        if message.properties.canBeDeletedOnlyForSelf, message.properties.canBeDeletedForAllUsers {
            elements.append(deleteSelf)
            elements.append(TelegramContextMenuAction(
                title: deleteAll.title,
                image: deleteAll.image,
                isDestructive: true,
            ) { [weak self] in self?.chatVM.deleteMessage(id: message.id, deleteForBoth: true) })
        } else if message.properties.canBeDeletedForAllUsers {
            elements.append(deleteAll)
        } else if message.properties.canBeDeletedOnlyForSelf {
            elements.append(deleteSelf)
        }
        return elements
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
