// ChatListSearchTopPeersCell.swift

import TDLibKit
import UIKit

// MARK: - ChatListSearchTopPeersCell

/// ChatListRecentPeersListItem: the search's People row, a horizontal strip of the people the account talks to most
/// (TDLib's top chats), each a 60 pt avatar with its unread count and online marker over the first name.
final class ChatListSearchTopPeersCell: UITableViewCell, UICollectionViewDataSource, UICollectionViewDelegate {
    static let reuseIdentifier = "ChatListSearchTopPeersCell"
    /// ChatListRecentPeersListItem's height.
    static let height = CGFloat(96)

    var onSelect: ((CustomChat) -> Void)?

    private let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 80, height: 92)
        layout.minimumLineSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()

    private var chats = [CustomChat]()
    private var client: TDLibClient?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .systemBackground
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(TopPeerCell.self, forCellWithReuseIdentifier: TopPeerCell.reuseIdentifier)
        contentView.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            collectionView.heightAnchor.constraint(equalToConstant: 92),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(chats: [CustomChat], client: TDLibClient) {
        self.chats = chats
        self.client = client
        collectionView.reloadData()
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        chats.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath,
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TopPeerCell.reuseIdentifier, for: indexPath)
        if let client { (cell as? TopPeerCell)?.configure(chat: chats[indexPath.item], client: client) }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard chats.indices.contains(indexPath.item) else { return }
        onSelect?(chats[indexPath.item])
    }
}

// MARK: - TopPeerCell

/// HorizontalPeerItem with SelectablePeerNode: the avatar 4 pt from the top, the 11 pt name 4 pt under it.
private final class TopPeerCell: UICollectionViewCell {
    static let reuseIdentifier = "TopPeerCell"

    private let avatarView = ProfileAvatarView()
    private let nameLabel = UILabel()
    private let badgeLabel = TelegramUnreadBadgeLabel(minimumDiameter: 20, horizontalPadding: 10)
    private let onlineMarker = ChatListOnlineMarkerView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.showsContextMenu = false
        avatarView.isUserInteractionEnabled = false
        contentView.addSubview(avatarView)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        contentView.addSubview(nameLabel)
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(badgeLabel)
        onlineMarker.ringColor = .systemBackground
        contentView.addSubview(onlineMarker)
        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            avatarView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 60),
            avatarView.heightAnchor.constraint(equalToConstant: 60),
            nameLabel.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            badgeLabel.topAnchor.constraint(equalTo: avatarView.topAnchor, constant: -2),
            badgeLabel.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 4),
            onlineMarker.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: -2),
            onlineMarker.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: -2),
            onlineMarker.widthAnchor.constraint(equalToConstant: ChatListOnlineMarkerView.Kind.person.size),
            onlineMarker.heightAnchor.constraint(equalToConstant: ChatListOnlineMarkerView.Kind.person.size),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    func configure(chat: CustomChat, client: TDLibClient) {
        avatarView.configure(
            file: chat.chat.photo?.small,
            largeFile: chat.chat.photo?.big,
            minithumbnail: chat.chat.photo?.minithumbnail,
            placeholder: chat.telegramAvatarPlaceholder,
            client: client,
        )
        let name = chat.user.map(ChatListSenderNames.compactName) ?? chat.displayTitle
        nameLabel.text = name
        let unread = chat.unreadCount
        badgeLabel.text = unread > 0 ? compactNumericCountString(unread) : nil
        badgeLabel.isHidden = unread == 0
        badgeLabel.backgroundColor = RootVM.shared.isMuted(chat) ? .systemGray : .systemBlue
        onlineMarker.setVisible(chat.user?.showsOnlineMarker == true, kind: .person, animated: false)
        accessibilityLabel = unread > 0
            ? "\(name), \(L10n.telegramPlural("VoiceOver.Chat.UnreadMessages", count: unread))"
            : name
    }
}
