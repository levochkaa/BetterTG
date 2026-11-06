// ProfileStoryGridCell.swift

import TDLibKit
import UIKit

// MARK: - ProfileStoryGridCell

/// PeerInfoStoryPaneNode's tile: the story's photo, or its video's thumbnail, filling a tile 0.81 as wide as it is
/// tall, with the view count at the bottom left when TDLib reports it (the account's own stories), a video's duration
/// at the bottom right and a pin at the top right on a story pinned to the profile's top.
final class ProfileStoryGridCell: UICollectionViewCell {
    static let reuseIdentifier = "ProfileStoryGridCell"
    /// PeerInfoStoryPaneNode's `aspectRatio: 0.81`.
    static let aspectRatio: CGFloat = 0.81

    private let imageView = TDImageLoadingView()
    private let durationLabel = UILabel()
    private let viewsLabel = UILabel()
    private let pinView = UIImageView(image: UIImage(
        systemName: "pin.fill",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold),
    ))
    private let shade = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemBackground
        contentView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(imageView)
        // A soft shade keeps the white duration and pin readable on light photos.
        shade.colors = [
            UIColor.black.withAlphaComponent(0.25).cgColor,
            UIColor.clear.cgColor,
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.35).cgColor,
        ]
        shade.locations = [0, 0.25, 0.7, 1]
        contentView.layer.addSublayer(shade)
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        durationLabel.textColor = .white
        viewsLabel.textColor = .white
        contentView.addSubview(viewsLabel)
        pinView.tintColor = .white
        contentView.addSubview(durationLabel)
        contentView.addSubview(pinView)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shade.frame = contentView.bounds
        // DurationLayer: the duration 3 pt from the right, the views 7 pt from the left, both 4 pt above the bottom.
        durationLabel.sizeToFit()
        durationLabel.frame.origin = CGPoint(
            x: contentView.bounds.width - durationLabel.bounds.width - 5,
            y: contentView.bounds.height - durationLabel.bounds.height - 5,
        )
        viewsLabel.sizeToFit()
        viewsLabel.frame.origin = CGPoint(x: 6, y: contentView.bounds.height - viewsLabel.bounds.height - 5)
        pinView.sizeToFit()
        pinView.frame.origin = CGPoint(x: contentView.bounds.width - pinView.bounds.width - 6, y: 6)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.cancel()
        imageView.image = nil
    }

    /// DurationLayer's view count: Peer Info/MediaGridViewCount's eye, then the count in thousands or millions.
    private static func viewsText(_ count: Int) -> NSAttributedString {
        let text = count > 1_000_000 ? "\(count / 1_000_000)M" : count > 1000 ? "\(count / 1000)K" : "\(count)"
        let font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let result = NSMutableAttributedString()
        if let eye = UIImage(
            systemName: "eye.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold),
        )?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            let attachment = NSTextAttachment(image: eye)
            attachment.bounds = CGRect(
                x: 0,
                y: (font.capHeight - eye.size.height) / 2,
                width: eye.size.width,
                height: eye.size.height,
            )
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: " "))
        }
        result.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.white]))
        return result
    }

    func configure(story: Story, isPinned: Bool, client: TDLibClient) {
        let origin = TDImageOrigin.captured(client: client)
        durationLabel.isHidden = true
        switch story.content {
        case .storyContentPhoto(let content):
            imageView.load(photo: content.photo, preferredSize: .mBox, maximumPixelSize: 640, origin: origin)
        case .storyContentVideo(let content):
            let video = content.video
            if let thumbnail = video.thumbnail {
                imageView.load(
                    file: thumbnail.file,
                    placeholderData: video.minithumbnail?.data,
                    maximumPixelSize: 640,
                    origin: origin,
                )
            } else {
                imageView.loadPlaceholder(data: video.minithumbnail?.data, maximumPixelSize: 640, origin: origin)
            }
            let seconds = Int(video.duration.rounded())
            durationLabel.text = String(format: "%d:%02d", seconds / 60, seconds % 60)
            durationLabel.isHidden = false
        default:
            imageView.image = nil
        }
        pinView.isHidden = !isPinned
        if let views = story.interactionInfo?.viewCount {
            viewsLabel.attributedText = Self.viewsText(views)
            viewsLabel.isHidden = false
        } else {
            viewsLabel.isHidden = true
        }
        accessibilityLabel = L10n.telegram("PeerInfo.PaneStories")
        isAccessibilityElement = true
        accessibilityTraits = .button
        setNeedsLayout()
    }
}
