// ChatsListItemView.swift

import Combine
import TDLibKit
import UIKit

final class ChatListCell: UITableViewCell {
    static let reuseIdentifier = "ChatListCell"

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .black
        selectionStyle = .none
        configureViews()
        configureConstraints()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancellables.removeAll()
        avatarView.prepareForReuse()
    }

    private let cardView = UIView()
    private let pinView = UIImageView(image: UIImage(systemName: "pin.fill"))
    private let avatarView = ProfileAvatarView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let unreadLabel = UILabel()
    private var cancellables = Set<AnyCancellable>()

    func configure(chat: CustomChat, folder _: CustomFolder) {
        pinView.isHidden = !chat.position.isPinned
        titleLabel.text = chat.chat.title
        messageLabel.attributedText = ChatSummary.attributedText(for: chat)
        unreadLabel.text = "\(chat.unreadCount)"
        unreadLabel.isHidden = chat.unreadCount == 0
        avatarView.configure(
            file: chat.chat.photo?.big,
            minithumbnail: chat.chat.photo?.minithumbnail,
            title: chat.chat.title,
            id: chat.id,
        )
        accessibilityLabel = [chat.chat.title, messageLabel.text, chat.unreadCount > 0 ? "\(chat.unreadCount) unread" : nil]
            .compactMap(\.self)
            .joined(separator: ", ")
        accessibilityTraits = .button
    }

    private func configureViews() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = .secondarySystemBackground
        cardView.layer.cornerRadius = 20
        cardView.clipsToBounds = true
        contentView.addSubview(cardView)

        [pinView, avatarView, titleLabel, messageLabel, unreadLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            cardView.addSubview($0)
        }
        pinView.tintColor = .white
        pinView.contentMode = .scaleAspectFit
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .title3)
        titleLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .secondaryLabel
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.lineBreakMode = .byTruncatingTail
        unreadLabel.backgroundColor = .systemGray
        unreadLabel.textColor = .white
        unreadLabel.textAlignment = .center
        unreadLabel.font = .preferredFont(forTextStyle: .caption1)
        unreadLabel.layer.cornerRadius = 16
        unreadLabel.clipsToBounds = true
        unreadLabel.adjustsFontSizeToFitWidth = true
    }

    private func configureConstraints() {
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            pinView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10),
            pinView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            pinView.widthAnchor.constraint(equalToConstant: 22),
            pinView.heightAnchor.constraint(equalToConstant: 22),
            avatarView.leadingAnchor.constraint(equalTo: pinView.trailingAnchor, constant: 8),
            avatarView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 60),
            avatarView.heightAnchor.constraint(equalToConstant: 60),
            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: unreadLabel.leadingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: cardView.centerYAnchor, constant: -2),
            messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: unreadLabel.leadingAnchor, constant: -8),
            messageLabel.topAnchor.constraint(equalTo: cardView.centerYAnchor, constant: 2),
            unreadLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            unreadLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            unreadLabel.widthAnchor.constraint(equalToConstant: 32),
            unreadLabel.heightAnchor.constraint(equalToConstant: 32),
        ])
    }
}

final class ProfileAvatarView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .title2)
        addSubview(label)
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
    }

    private let imageView = UIImageView()
    private let label = UILabel()
    private var representedFileID: Int?
    private var downloadTask: Task<Void, Never>?
    private var cancellable: AnyCancellable?

    func configure(file: File?, minithumbnail: Minithumbnail?, title: String, id: Int64) {
        prepareForReuse()
        label.text = String(title.prefix(1)).uppercased()
        backgroundColor = UIColor(userID: id)
        imageView.image = minithumbnail.flatMap { UIImage(data: $0.data) }
        imageView.isHidden = imageView.image == nil
        guard let file else { return }
        representedFileID = file.id
        update(file: file)
        cancellable = nc.publisher(for: .updateFile)
            .receive(on: DispatchQueue.main)
            .filter { $0.file.id == file.id }
            .sink { [weak self] in self?.update(file: $0.file) }
        downloadTask = Task { [weak self] in
            guard let self else { return }
            let downloaded = try? await td.downloadFile(
                fileId: file.id,
                limit: 0,
                offset: 0,
                priority: 1,
                synchronous: false,
            )
            guard let downloaded else { return }
            await MainActor.run { self.update(file: downloaded) }
        }
    }

    func prepareForReuse() {
        downloadTask?.cancel()
        downloadTask = nil
        cancellable?.cancel()
        cancellable = nil
        representedFileID = nil
        imageView.image = nil
        imageView.isHidden = true
    }

    private func update(file: File) {
        guard representedFileID == file.id, file.local.isDownloadingCompleted else { return }
        let path = file.local.path
        Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) { UIImage(contentsOfFile: path) }.value
            await MainActor.run {
                guard let self, self.representedFileID == file.id, let image else { return }
                self.imageView.image = image
                self.imageView.isHidden = false
            }
        }
    }
}
