// ChatView.swift

import Combine
import TDLibKit
import UIKit

final class ChatViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
    init(customChat: CustomChat) {
        chatVM = ChatVM(customChat: customChat)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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
        titleLabel.text = chatVM.customChat.chat.title
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.textColor = .secondaryLabel
        navigationItem.titleView = titleStack

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.configure(
            file: chatVM.customChat.chat.photo?.big,
            minithumbnail: chatVM.customChat.chat.photo?.minithumbnail,
            title: chatVM.customChat.chat.title,
            id: chatVM.customChat.id,
        )
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 32),
            avatarView.heightAnchor.constraint(equalToConstant: 32),
        ])
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: avatarView)
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
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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
            cell.transform = CGAffineTransform(scaleX: 1, y: -1)
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
                DispatchQueue.main.async {
                    self?.updateStatus()
                    self?.updateSnapshot(animated: true, reconfigureExisting: true)
                }
            }
            .store(in: &cancellables)
        subscribeToMessages()
    }

    private func subscribeToMessages() {
        messageCancellables.removeAll()
        for message in chatVM.messages {
            message.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in
                    DispatchQueue.main.async { self?.updateSnapshot(animated: true, reconfigureExisting: true) }
                }
                .store(in: &messageCancellables)
        }
    }

    private func updateStatus() {
        let status = chatVM.actionStatus.isEmpty ? chatVM.onlineStatus : chatVM.actionStatus
        statusLabel.text = status
        statusLabel.isHidden = status.isEmpty
        statusLabel.textColor = !chatVM.actionStatus.isEmpty || status == "online" ? .systemBlue : .secondaryLabel
    }

    private func updateSnapshot(animated: Bool, reconfigureExisting: Bool = false) {
        guard isViewLoaded else { return }
        subscribeToMessages()
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int64>()
        snapshot.appendSections([.messages])
        snapshot.appendItems(chatVM.messages.map(\.id))
        if reconfigureExisting {
            let existing = Set(dataSource.snapshot().itemIdentifiers)
            snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { existing.contains($0) })
        }
        dataSource.apply(snapshot, animatingDifferences: animated)
        collectionView.backgroundView = chatVM.messages.isEmpty ? emptyLabel() : nil
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
        guard let messageID = dataSource.itemIdentifier(for: indexPath), let message = message(for: messageID) else { return nil }
        return UIContextMenuConfiguration(identifier: NSNumber(value: messageID), previewProvider: nil) { [weak self] _ in
            self?.menu(for: message)
        }
    }

    func collectionView(_: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard let messageID = dataSource.itemIdentifier(for: indexPath),
                  let message = message(for: messageID),
                  prefetchTasks[messageID] == nil
            else { continue }
            prefetchTasks[messageID] = Task {
                await TDMediaPrefetcher.prefetch(message: message.message)
                await MainActor.run { self.prefetchTasks[messageID] = nil }
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

    private func menu(for message: CustomMessage) -> UIMenu {
        var elements = [UIMenuElement]()
        if message.properties.canBeReplied {
            elements.append(UIAction(title: "Reply", image: UIImage(systemName: "arrowshape.turn.up.left")) { [weak self] _ in
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
            elements.append(UIMenu(title: "Delete", image: UIImage(systemName: "trash"), children: [deleteSelf, deleteAll]))
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
