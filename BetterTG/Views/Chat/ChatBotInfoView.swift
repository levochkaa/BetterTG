// ChatBotInfoView.swift

import TDLibKit
import UIKit

// MARK: - ChatBotInfoView

/// Telegram's ChatBotInfoItem in a bot chat without messages: the bot's picture, "What can this bot do?" and its
/// description.
final class ChatBotInfoView: UIView {
    private let imageView = TDImageLoadingView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()

    init(info: TDNativeBotInfo, client: TDLibClient) {
        super.init(frame: .zero)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        clipsToBounds = true

        titleLabel.text = L10n.telegram("Bot.DescriptionTitle")
        titleLabel.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        descriptionLabel.text = info.description
        descriptionLabel.font = .preferredFont(forTextStyle: .subheadline)
        descriptionLabel.adjustsFontForContentSizeCategory = true
        descriptionLabel.numberOfLines = 0

        let textStack = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.isLayoutMarginsRelativeArrangement = true
        textStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12)
        let stack = UIStackView(arrangedSubviews: [imageView, textStack])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .tertiarySystemFill
        // The description's photo, or the first frame of its animation; a picture keeps its proportions.
        var pictureSize = CGSize.zero
        if let photo = info.photo, let size = photo.sizes.last {
            pictureSize = CGSize(width: CGFloat(size.width), height: CGFloat(size.height))
            imageView.load(file: size.photo, placeholderData: photo.minithumbnail?.data, client: client)
        } else if let animation = info.animation {
            pictureSize = CGSize(width: CGFloat(animation.width), height: CGFloat(animation.height))
            if let thumbnail = animation.thumbnail, Self.isImage(thumbnail.format) {
                imageView.load(file: thumbnail.file, placeholderData: animation.minithumbnail?.data, client: client)
            } else {
                imageView.loadPlaceholder(data: animation.minithumbnail?.data, client: client)
            }
        }
        imageView.isHidden = pictureSize.width <= 0 || pictureSize.height <= 0
        if !imageView.isHidden {
            imageView.heightAnchor
                .constraint(
                    equalTo: imageView.widthAnchor,
                    multiplier: min(pictureSize.height / pictureSize.width, 1.25),
                )
                .isActive = true
        }
        isAccessibilityElement = true
        accessibilityLabel = [titleLabel.text, info.description].compactMap(\.self).joined(separator: ", ")
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func isImage(_ format: TDNativeThumbnailFormat) -> Bool {
        switch format {
        case .thumbnailFormatGif, .thumbnailFormatJpeg, .thumbnailFormatPng, .thumbnailFormatWebp: true
        default: false
        }
    }
}

// MARK: - ChatBotInfoCell

/// The bot info card as the history's top row, above the first message (ChatBotInfoItem in the history list).
final class ChatBotInfoCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatBotInfoCell"

    private var card: ChatBotInfoView?
    private var shownKey: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // The history is flipped; its rows turn back upright.
        contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(info: TDNativeBotInfo, client: TDLibClient) {
        let key = [
            info.description,
            String(info.photo?.sizes.last?.photo.id ?? 0),
            String(info.animation?.animation.id ?? 0),
        ].joined(separator: "|")
        guard key != shownKey else { return }
        shownKey = key
        card?.removeFromSuperview()
        let card = ChatBotInfoView(info: info, client: client)
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        let preferredWidth = card.widthAnchor.constraint(equalToConstant: 320)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            card.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
            preferredWidth,
        ])
        self.card = card
    }

    func resetUnavailableContent() {
        card?.removeFromSuperview()
        card = nil
        shownKey = nil
    }
}
