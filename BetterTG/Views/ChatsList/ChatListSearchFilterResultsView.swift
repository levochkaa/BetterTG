// ChatListSearchFilterResultsView.swift

import TDLibKit
import UIKit

// MARK: - ChatListSearchFilter

/// ChatListSearchFilter's tabs over the chat list's search: Chats, then the message kinds Telegram searches across
/// all chats, with its ids.
enum ChatListSearchFilter: Int, CaseIterable {
    case chats = 0
    case media = 5
    case links = 7
    case files = 8
    case music = 9
    case voice = 10

    var title: String {
        switch self {
        case .chats: L10n.telegram("ChatList.Search.FilterChats")
        case .media: L10n.telegram("ChatList.Search.FilterMedia")
        case .links: L10n.telegram("ChatList.Search.FilterLinks")
        case .files: L10n.telegram("ChatList.Search.FilterFiles")
        case .music: L10n.telegram("ChatList.Search.FilterMusic")
        case .voice: L10n.telegram("ChatList.Search.FilterVoice")
        }
    }

    /// ChatListSearchListPaneNode's message filter for the tab.
    var messagesFilter: SearchMessagesFilter? {
        switch self {
        case .chats: nil
        case .media: .searchMessagesFilterPhotoAndVideo
        case .links: .searchMessagesFilterUrl
        case .files: .searchMessagesFilterDocument
        case .music: .searchMessagesFilterAudio
        case .voice: .searchMessagesFilterVoiceAndVideoNote
        }
    }

    /// Telegram's empty state for the tab ("Fitler" is Telegram's own key).
    var emptyText: String {
        switch self {
        case .chats: L10n.telegram("ChatList.Search.NoResultsDescription")
        case .media: L10n.telegram("ChatList.Search.NoResultsFitlerMedia")
        case .links: L10n.telegram("ChatList.Search.NoResultsFitlerLinks")
        case .files: L10n.telegram("ChatList.Search.NoResultsFitlerFiles")
        case .music: L10n.telegram("ChatList.Search.NoResultsFitlerMusic")
        case .voice: L10n.telegram("ChatList.Search.NoResultsFitlerVoice")
        }
    }
}

// MARK: - ChatListSearchFilterResultsView

/// ChatListSearchListPaneNode for a message tab: TDLib's `searchMessages` across the account's chats with the tab's
/// filter, a page at a time, as a grid of photos and videos or a list of links, files, music and voice messages.
@MainActor final class ChatListSearchFilterResultsView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    private static let pageLimit = 60

    /// A found message was tapped.
    var onOpen: ((Message) -> Void)?

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let emptyTitle = UILabel()
    private let emptyText = UILabel()
    private var filter = ChatListSearchFilter.media
    private var query = ""
    private var client: TDLibClient?
    private var chatList: ChatList?
    private var messages = [Message]()
    private var nextOffset = ""
    private var loadTask: Task<Void, Never>?
    private var generation = UInt64.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .onDrag
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(
            ChatListSearchMediaCell.self,
            forCellWithReuseIdentifier: ChatListSearchMediaCell.reuseIdentifier,
        )
        collectionView.register(SharedMediaRowCell.self, forCellWithReuseIdentifier: SharedMediaRowCell.reuseIdentifier)
        addSubview(collectionView)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        addSubview(spinner)
        emptyTitle.font = .preferredFont(forTextStyle: .headline)
        emptyTitle.textAlignment = .center
        emptyTitle.text = L10n.telegram("ChatList.Search.NoResultsFilter")
        emptyText.font = .preferredFont(forTextStyle: .subheadline)
        emptyText.textColor = .secondaryLabel
        emptyText.textAlignment = .center
        emptyText.numberOfLines = 0
        let emptyStack = UIStackView(arrangedSubviews: [emptyTitle, emptyText])
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        emptyStack.axis = .vertical
        emptyStack.spacing = 6
        emptyStack.isHidden = true
        addSubview(emptyStack)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            emptyStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyStack.topAnchor.constraint(equalTo: topAnchor, constant: 60),
            emptyStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            emptyStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    /// Starts the tab's search over, unless it already shows this tab and query from this client.
    func show(filter: ChatListSearchFilter, query: String, client: TDLibClient, chatList: ChatList) {
        guard filter != self.filter || query != self.query || client.id != self.client?.id || messages.isEmpty
            && loadTask == nil else { return }
        let layoutChanged = (filter == .media) != (self.filter == .media)
        self.filter = filter
        self.query = query
        self.client = client
        self.chatList = chatList
        loadTask?.cancel()
        loadTask = nil
        generation &+= 1
        messages = []
        nextOffset = ""
        emptyText.text = filter.emptyText
        if layoutChanged { collectionView.setCollectionViewLayout(makeLayout(), animated: false) }
        collectionView.reloadData()
        collectionView.setContentOffset(.zero, animated: false)
        loadPage()
    }

    func reset() {
        loadTask?.cancel()
        loadTask = nil
        generation &+= 1
        messages = []
        nextOffset = ""
        client = nil
        collectionView.reloadData()
        updateState()
    }

    // MARK: UICollectionViewDataSource

    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        messages.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath,
    ) -> UICollectionViewCell {
        let message = messages[indexPath.item]
        if filter == .media {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatListSearchMediaCell.reuseIdentifier,
                for: indexPath,
            )
            if let client { (cell as? ChatListSearchMediaCell)?.configure(message: message, client: client) }
            return cell
        }
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: SharedMediaRowCell.reuseIdentifier,
            for: indexPath,
        )
        (cell as? SharedMediaRowCell)?.configure(message: message)
        return cell
    }

    func collectionView(_: UICollectionView, willDisplay _: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.item >= messages.count - 12, !nextOffset.isEmpty { loadPage() }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard messages.indices.contains(indexPath.item) else { return }
        onOpen?(messages[indexPath.item])
    }

    private func loadPage() {
        guard loadTask == nil, let client, let chatList, let messagesFilter = filter.messagesFilter else { return }
        let requestGeneration = generation
        let offset = nextOffset
        let query = query
        updateState(loading: true)
        loadTask = Task { [weak self] in
            let found = try? await client.searchMessages(
                chatList: chatList,
                query: query,
                offset: offset,
                limit: Self.pageLimit,
                filter: messagesFilter,
                chatTypeFilter: nil,
                minDate: 0,
                maxDate: 0,
            )
            guard let self, !Task.isCancelled, requestGeneration == generation else { return }
            loadTask = nil
            if let found {
                let known = Set(messages.map { "\($0.chatId)/\($0.id)" })
                let fresh = found.messages.filter { !known.contains("\($0.chatId)/\($0.id)") }
                let start = messages.count
                messages += fresh
                nextOffset = found.nextOffset
                let inserted = (start..<messages.count).map { IndexPath(item: $0, section: 0) }
                collectionView.performBatchUpdates { [collectionView] in
                    collectionView.insertItems(at: inserted)
                }
            } else {
                nextOffset = ""
            }
            updateState()
        }
    }

    private func updateState(loading: Bool = false) {
        if loading, messages.isEmpty { spinner.startAnimating() } else { spinner.stopAnimating() }
        emptyTitle.superview?.isHidden = loading || loadTask != nil || !messages.isEmpty || client == nil
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] _, environment in
            let width = environment.container.effectiveContentSize.width
            if self?.filter == .media {
                // ChatListSearchMediaNode: three or four tiles a row a point apart.
                let columns = CGFloat(width > 500 ? 4 : 3)
                let side = floor((width - (columns - 1)) / columns)
                let item = NSCollectionLayoutItem(layoutSize: .init(
                    widthDimension: .absolute(side),
                    heightDimension: .absolute(side),
                ))
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(side)),
                    subitems: [item],
                )
                group.interItemSpacing = .fixed(1)
                let section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing = 1
                return section
            }
            let item = NSCollectionLayoutItem(layoutSize: .init(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(60),
            ))
            let group = NSCollectionLayoutGroup.vertical(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(60)),
                subitems: [item],
            )
            return NSCollectionLayoutSection(group: group)
        }
    }
}

// MARK: - ChatListSearchMediaCell

/// ChatListSearchMediaNode's tile: the photo or the video's thumbnail filling the square, TDLib's blurred
/// minithumbnail alone under a spoiler, and a video's length at the bottom right.
private final class ChatListSearchMediaCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatListSearchMediaCell"

    private let imageView = TDImageLoadingView()
    private let durationLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemBackground
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        durationLabel.textColor = .white
        durationLabel.shadowColor = UIColor.black.withAlphaComponent(0.5)
        durationLabel.shadowOffset = CGSize(width: 0, height: 0.5)
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(durationLabel)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            durationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            durationLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.cancel()
        imageView.image = nil
        durationLabel.text = nil
    }

    func configure(message: Message, client: TDLibClient) {
        let pixels = Int(ceil(max(bounds.width, 100) * (window?.screen.scale ?? 3)))
        switch message.content {
        case .messagePhoto(let content):
            durationLabel.text = nil
            accessibilityLabel = L10n.telegram("Message.Photo")
            if content.hasSpoiler || content.isSecret {
                imageView.loadPlaceholder(
                    data: content.photo.minithumbnail?.data,
                    maximumPixelSize: pixels,
                    client: client,
                )
            } else {
                let size = content.photo
                    .sizes
                    .sorted { $0.width * $0.height < $1.width * $1.height }
                    .first { min($0.width, $0.height) >= pixels / 2 } ?? content.photo.sizes.last
                if let size {
                    imageView.load(
                        file: size.photo,
                        placeholderData: content.photo.minithumbnail?.data,
                        maximumPixelSize: pixels,
                        client: client,
                    )
                } else {
                    imageView.loadPlaceholder(
                        data: content.photo.minithumbnail?.data,
                        maximumPixelSize: pixels,
                        client: client,
                    )
                }
            }
        case .messageVideo(let content):
            let duration = content.video.duration
            durationLabel.text = String(format: "%d:%02d", duration / 60, duration % 60)
            accessibilityLabel = L10n.telegram("Message.Video")
            let minithumbnail = content.video.minithumbnail?.data
            if !content.hasSpoiler, !content.isSecret, let thumbnail = content.video.thumbnail,
               case .thumbnailFormatJpeg = thumbnail.format
            {
                imageView.load(
                    file: thumbnail.file,
                    placeholderData: minithumbnail,
                    maximumPixelSize: pixels,
                    client: client,
                )
            } else {
                imageView.loadPlaceholder(data: minithumbnail, maximumPixelSize: pixels, client: client)
            }
        default:
            durationLabel.text = nil
            accessibilityLabel = MessageContentPresentation.make(message).summary
            imageView.image = nil
        }
    }
}
