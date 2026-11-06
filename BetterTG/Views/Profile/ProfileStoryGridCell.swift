// ProfileStoryGridCell.swift

import TDLibKit
import UIKit

// MARK: - ProfileStoryGridCell

/// PeerInfoStoryPaneNode's tile: the story's photo, or its video's thumbnail, filling a tile 0.81 as wide as it is
/// tall, with a video's duration at the bottom left and a pin at the top right on a story pinned to the profile's top.
final class ProfileStoryGridCell: UICollectionViewCell {
    static let reuseIdentifier = "ProfileStoryGridCell"
    /// PeerInfoStoryPaneNode's `aspectRatio: 0.81`.
    static let aspectRatio: CGFloat = 0.81

    private let imageView = TDImageLoadingView()
    private let durationLabel = UILabel()
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
        durationLabel.sizeToFit()
        durationLabel.frame.origin = CGPoint(x: 6, y: contentView.bounds.height - durationLabel.bounds.height - 5)
        pinView.sizeToFit()
        pinView.frame.origin = CGPoint(x: contentView.bounds.width - pinView.bounds.width - 6, y: 6)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.cancel()
        imageView.image = nil
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
        accessibilityLabel = L10n.telegram("PeerInfo.PaneStories")
        isAccessibilityElement = true
        accessibilityTraits = .button
        setNeedsLayout()
    }
}
