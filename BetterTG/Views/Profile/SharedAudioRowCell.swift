// SharedAudioRowCell.swift

import TDLibKit
import UIKit

// MARK: - SharedAudioRowCell

/// ListMessageFileItemNode for music, voice and round videos: the album cover, the round video's frame or the play
/// button on the accent colour at the left; a track's title with its length and performer, or a voice message's
/// sender with its length and date. A global search result moves the date to the right.
final class SharedAudioRowCell: UICollectionViewCell {
    static let reuseIdentifier = "SharedAudioRowCell"

    private let playBackground = UIView()
    private let playGlyph = UIImageView(image: UIImage(
        systemName: "play.fill",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold),
    ))
    private let coverView = TDImageLoadingView()
    private let titleLabel = UILabel()
    private let dateLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let separator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        playBackground.translatesAutoresizingMaskIntoConstraints = false
        playBackground.backgroundColor = .tintColor
        playBackground.layer.cornerRadius = 20
        contentView.addSubview(playBackground)
        coverView.translatesAutoresizingMaskIntoConstraints = false
        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        contentView.addSubview(coverView)
        playGlyph.translatesAutoresizingMaskIntoConstraints = false
        playGlyph.tintColor = .white
        contentView.addSubview(playGlyph)
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        dateLabel.font = .systemFont(ofSize: 14)
        dateLabel.textColor = .secondaryLabel
        dateLabel.setContentHuggingPriority(.required, for: .horizontal)
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        descriptionLabel.font = .systemFont(ofSize: 14)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.lineBreakMode = .byTruncatingMiddle
        progressView.isHidden = true
        let header = UIStackView(arrangedSubviews: [titleLabel, dateLabel])
        header.alignment = .firstBaseline
        header.spacing = 4
        let stack = UIStackView(arrangedSubviews: [header, descriptionLabel, progressView])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 2
        contentView.addSubview(stack)
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        contentView.addSubview(separator)
        let scale = UITraitCollection.current.displayScale
        NSLayoutConstraint.activate([
            playBackground.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            playBackground.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            playBackground.widthAnchor.constraint(equalToConstant: 40),
            playBackground.heightAnchor.constraint(equalToConstant: 40),
            coverView.leadingAnchor.constraint(equalTo: playBackground.leadingAnchor),
            coverView.topAnchor.constraint(equalTo: playBackground.topAnchor),
            coverView.widthAnchor.constraint(equalToConstant: 40),
            coverView.heightAnchor.constraint(equalToConstant: 40),
            playGlyph.centerXAnchor.constraint(equalTo: playBackground.centerXAnchor, constant: 1.5),
            playGlyph.centerYAnchor.constraint(equalTo: playBackground.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 65),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 65),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / max(scale, 1)),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        coverView.cancel()
        coverView.image = nil
    }

    /// ListMessageFileItemNode's author: You for the account, else the sender's name once TDLib gives it.
    private static func sender(
        of message: Message,
        client: TDLibClient,
        onNameResolved: @escaping () -> Void,
    ) -> String {
        if message.isOutgoing { return L10n.telegram("DialogList.You") }
        guard case .messageSenderUser(let sender) = message.senderId else {
            return L10n.telegram("Message.Audio")
        }
        if let user = ChatListSenderNames.shared.user(userID: sender.userId, client: client) {
            return ServiceMessageText.displayTitle(user)
        }
        ChatListSenderNames.shared.resolve(userID: sender.userId, client: client, completion: onNameResolved)
        return " "
    }

    private static func duration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Returns false for a message that is not music, a voice message or a round video. `onNameResolved` runs once a
    /// voice message's sender, unknown so far, is named.
    @discardableResult func configure(
        message: Message,
        isGlobalSearch: Bool,
        client: TDLibClient,
        onNameResolved: @escaping () -> Void,
    ) -> Bool {
        let date = Date(timeIntervalSince1970: TimeInterval(message.date))
        let title: String
        var details = [String]()
        switch message.content {
        case .messageAudio(let content):
            let audio = content.audio
            title = [audio.title, audio.fileName].first { !$0.isEmpty } ?? L10n.telegram("MediaPlayer.UnknownTrack")
            let performer = audio.performer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !performer.isEmpty {
                if !isGlobalSearch { details.append(Self.duration(audio.duration)) }
                details.append(performer)
            } else {
                let bytes = Int64(max(audio.audio.size, audio.audio.expectedSize))
                if bytes > 0 { details.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
            }
            showIcon(
                cover: audio.albumCoverThumbnail,
                minithumbnail: audio.albumCoverMinithumbnail,
                round: false,
                client: client,
            )
        case .messageVoiceNote(let content):
            title = Self.sender(of: message, client: client, onNameResolved: onNameResolved)
            details.append(Self.duration(content.voiceNote.duration))
            if !isGlobalSearch { details.append(ChatVM.fullDateString(date)) }
            showIcon(cover: nil, minithumbnail: nil, round: false, client: client)
        case .messageVideoNote(let content):
            title = Self.sender(of: message, client: client, onNameResolved: onNameResolved)
            details.append(Self.duration(content.videoNote.duration))
            if !isGlobalSearch { details.append(ChatVM.fullDateString(date)) }
            showIcon(
                cover: content.videoNote.thumbnail,
                minithumbnail: content.videoNote.minithumbnail,
                round: true,
                client: client,
            )
        default:
            return false
        }
        titleLabel.text = title
        descriptionLabel.text = details.joined(separator: " • ")
        dateLabel.text = isGlobalSearch ? profileDateString(message.date) : nil
        dateLabel.isHidden = !isGlobalSearch
        accessibilityLabel = [title, descriptionLabel.text, dateLabel.text]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        setDownloadProgress(nil)
        return true
    }

    /// A file downloading to play; nil hides the bar.
    func setDownloadProgress(_ progress: Float?) {
        progressView.isHidden = progress == nil
        progressView.progress = progress ?? 0
        accessibilityValue = progress.map { L10n.betterTG("Accessibility.PercentDownloaded", Int($0 * 100)) }
    }

    /// A cover or a round video's frame under a dimmed play mark, else the accent button.
    private func showIcon(cover: Thumbnail?, minithumbnail: Minithumbnail?, round: Bool, client: TDLibClient) {
        coverView.layer.cornerRadius = round ? 20 : 6
        if let cover, case .thumbnailFormatJpeg = cover.format {
            coverView.isHidden = false
            coverView.load(
                file: cover.file,
                placeholderData: minithumbnail?.data,
                maximumPixelSize: 120,
                client: client,
            )
        } else if let minithumbnail {
            coverView.isHidden = false
            coverView.loadPlaceholder(data: minithumbnail.data, maximumPixelSize: 120, client: client)
        } else {
            coverView.isHidden = true
        }
        playBackground.isHidden = !coverView.isHidden
        playGlyph.layer.shadowOpacity = coverView.isHidden ? 0 : 0.35
        playGlyph.layer.shadowRadius = 2
        playGlyph.layer.shadowOffset = .zero
    }
}
