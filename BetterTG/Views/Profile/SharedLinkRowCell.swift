// SharedLinkRowCell.swift

import TDLibKit
import UIKit

// MARK: - SharedLinkSnippet

/// ListMessageSnippetItemNode's content for a message with a link: its link preview's title, description, picture
/// and address, or else the first address in its text with the host as the title.
struct SharedLinkSnippet {
    let title: String
    let description: String?
    let address: String
    /// The host's first letter, drawn when there is no picture.
    let letter: String
    let photo: Photo?

    init?(message: Message, includesDescription: Bool) {
        // A media message's caption carries its links, and its photo stands in for the preview's.
        let formatted: FormattedText
        var ownPhoto: Photo?
        switch message.content {
        case .messageText(let content):
            if let preview = content.linkPreview {
                self.init(preview: preview, includesDescription: includesDescription)
                return
            }
            formatted = content.text
        case .messagePhoto(let content):
            formatted = content.caption
            ownPhoto = content.hasSpoiler ? nil : content.photo
        case .messageVideo(let content):
            formatted = content.caption
        case .messageDocument(let content):
            formatted = content.caption
        case .messageAnimation(let content):
            formatted = content.caption
        case .messageAudio(let content):
            formatted = content.caption
        case .messageVoiceNote(let content):
            formatted = content.caption
        default:
            return nil
        }
        guard let address = Self.firstAddress(in: formatted) else { return nil }
        let parsed = URL(string: address.contains("://") ? address : "http://" + address)
        let host = parsed?.host ?? address
        // ListMessageSnippetItemNode adds the message's own text when it says more than the address.
        let messageText = formatted.text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            title: host,
            description: includesDescription && messageText != address ? messageText : nil,
            address: Self.displayAddress(address),
            letter: host.first.map { String($0).uppercased() } ?? "",
            photo: ownPhoto,
        )
    }

    private init(preview: LinkPreview, includesDescription: Bool) {
        let host = URL(string: preview.url)?.host ?? ""
        let description = preview.description.text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            title: [preview.title, preview.siteName, host].first { !$0.isEmpty } ?? preview.url,
            description: includesDescription && !description.isEmpty ? description : nil,
            address: Self.displayAddress(preview.url),
            letter: host.first.map { String($0).uppercased() } ?? "",
            photo: Self.photo(of: preview.type),
        )
    }

    private init(title: String, description: String?, address: String, letter: String, photo: Photo?) {
        self.title = title
        self.description = description
        self.address = address
        self.letter = letter
        self.photo = photo
    }

    /// The first web or email address in the text, as ListMessageSnippetItemNode reads its entities.
    private static func firstAddress(in formatted: FormattedText) -> String? {
        let text = formatted.text as NSString
        for entity in formatted.entities {
            let range = NSRange(location: entity.offset, length: entity.length)
            guard NSMaxRange(range) <= text.length else { continue }
            switch entity.type {
            case .textEntityTypeEmailAddress,
                 .textEntityTypeUrl:
                return text.substring(with: range)
            case .textEntityTypeTextUrl(let value):
                return value.url
            default:
                continue
            }
        }
        return nil
    }

    /// The address without `https://` and its trailing slashes, as the snippet prints it.
    private static func displayAddress(_ url: String) -> String {
        url.replacing("https://", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func photo(of type: LinkPreviewType) -> Photo? {
        switch type {
        case .linkPreviewTypeArticle(let value): value.photo
        case .linkPreviewTypePhoto(let value): value.photo
        case .linkPreviewTypeEmbeddedVideoPlayer(let value): value.thumbnail
        case .linkPreviewTypeEmbeddedAnimationPlayer(let value): value.thumbnail
        case .linkPreviewTypeEmbeddedAudioPlayer(let value): value.thumbnail
        case .linkPreviewTypeApp(let value): value.photo
        default: nil
        }
    }
}

// MARK: - SharedLinkRowCell

/// ListMessageSnippetItemNode: a 40 pt picture or the host's letter on orange at the left, the title with the date
/// beside it, the description and the address in the accent colour, and the chat for a global search result.
final class SharedLinkRowCell: UICollectionViewCell {
    static let reuseIdentifier = "SharedLinkRowCell"

    private let iconImageView = TDImageLoadingView()
    private let letterLabel = UILabel()
    private let titleLabel = UILabel()
    private let dateLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let addressLabel = UILabel()
    private let authorLabel = UILabel()
    private let separator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        letterLabel.translatesAutoresizingMaskIntoConstraints = false
        letterLabel.backgroundColor = UIColor(red: 1, green: 0x95 / 255, blue: 0, alpha: 1)
        letterLabel.textColor = .white
        letterLabel.textAlignment = .center
        letterLabel.layer.cornerRadius = 6
        letterLabel.clipsToBounds = true
        let rounded = UIFont.systemFont(ofSize: 28, weight: .bold).fontDescriptor.withDesign(.rounded)
        letterLabel.font = rounded.map { UIFont(descriptor: $0, size: 28) } ?? .systemFont(ofSize: 28, weight: .bold)
        contentView.addSubview(letterLabel)
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFill
        iconImageView.clipsToBounds = true
        iconImageView.layer.cornerRadius = 6
        contentView.addSubview(iconImageView)

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingMiddle
        dateLabel.font = .systemFont(ofSize: 14)
        dateLabel.textColor = .secondaryLabel
        dateLabel.setContentHuggingPriority(.required, for: .horizontal)
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        descriptionLabel.font = .systemFont(ofSize: 14)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 3
        addressLabel.font = .systemFont(ofSize: 14)
        addressLabel.textColor = .tintColor
        addressLabel.numberOfLines = 4
        authorLabel.font = .systemFont(ofSize: 14)
        authorLabel.textColor = .secondaryLabel
        authorLabel.lineBreakMode = .byTruncatingMiddle
        let header = UIStackView(arrangedSubviews: [titleLabel, dateLabel])
        header.alignment = .firstBaseline
        header.spacing = 8
        let stack = UIStackView(arrangedSubviews: [header, descriptionLabel, addressLabel, authorLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 1
        stack.setCustomSpacing(2, after: header)
        contentView.addSubview(stack)
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        contentView.addSubview(separator)
        let scale = UITraitCollection.current.displayScale
        NSLayoutConstraint.activate([
            letterLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            letterLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            letterLabel.widthAnchor.constraint(equalToConstant: 40),
            letterLabel.heightAnchor.constraint(equalToConstant: 40),
            iconImageView.leadingAnchor.constraint(equalTo: letterLabel.leadingAnchor),
            iconImageView.topAnchor.constraint(equalTo: letterLabel.topAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 40),
            iconImageView.heightAnchor.constraint(equalToConstant: 40),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 65),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
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
        iconImageView.cancel()
        iconImageView.image = nil
    }

    /// `author` names the chat of a global search result, which also leaves the description out.
    func configure(message: Message, snippet: SharedLinkSnippet, author: String?, client: TDLibClient) {
        titleLabel.text = snippet.title
        dateLabel.text = profileDateString(message.date)
        descriptionLabel.text = snippet.description
        descriptionLabel.isHidden = snippet.description == nil
        addressLabel.text = snippet.address
        authorLabel.text = author
        authorLabel.isHidden = author == nil
        letterLabel.text = snippet.letter
        if let photo = snippet.photo {
            // ListMessageSnippetItemNode takes the representation larger than 80 px.
            let size = photo.sizes
                .sorted { $0.width * $0.height < $1.width * $1.height }
                .first { min($0.width, $0.height) >= 80 } ?? photo.sizes.last
            iconImageView.isHidden = false
            if let size {
                iconImageView.load(
                    file: size.photo,
                    placeholderData: photo.minithumbnail?.data,
                    maximumPixelSize: 160,
                    client: client,
                )
            } else {
                iconImageView.loadPlaceholder(data: photo.minithumbnail?.data, maximumPixelSize: 160, client: client)
            }
        } else {
            iconImageView.isHidden = true
        }
        accessibilityLabel = [snippet.title, snippet.description, snippet.address, author, dateLabel.text]
            .compactMap(\.self)
            .joined(separator: ", ")
    }
}
