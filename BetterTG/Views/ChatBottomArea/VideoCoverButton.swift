// VideoCoverButton.swift

import UIKit

// MARK: - VideoCoverButton

/// TGMediaPickerCoverButton: Edit Cover in bold white on a dark 26 pt pill with a faint chevron, led by the saved
/// cover in a 24 pt circle once there is one, shrinking while held.
final class VideoCoverButton: UIControl {
    // MARK: Private

    private static let height: CGFloat = 26
    /// `setImage:` widens the pill by the cover's circle.
    private static let imageInset: CGFloat = 22

    // MARK: Internal

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            // `setWrapperScale:animated:`.
            let scale: CGFloat = isHighlighted ? 0.85 : 1
            UIView.animate(withDuration: 0.12, delay: 0, options: .allowAnimatedContent) {
                self.wrapperView.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: pillWidth, height: Self.height)
    }

    private let wrapperView = UIView()
    private let backgroundView = UIView()
    private let thumbnailView = UIImageView()
    private let label = UILabel()
    private let chevronView = UIImageView()

    private var hasImage: Bool {
        thumbnailView.image != nil
    }

    /// The label's width and 28 pt, and the circle's room with a cover.
    private var pillWidth: CGFloat {
        floor(label.intrinsicContentSize.width) + 28 + (hasImage ? Self.imageInset : 0)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isExclusiveTouch = true
        wrapperView.isUserInteractionEnabled = false
        addSubview(wrapperView)
        backgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        backgroundView.layer.cornerRadius = Self.height / 2
        backgroundView.clipsToBounds = true
        wrapperView.addSubview(backgroundView)
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.cornerRadius = 12
        thumbnailView.isHidden = true
        wrapperView.addSubview(thumbnailView)
        label.font = .boldSystemFont(ofSize: 14)
        label.textColor = .white
        label.text = L10n.telegram("Media.EditCover")
        wrapperView.addSubview(label)
        chevronView.image = UIImage(
            systemName: "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold),
        )
        chevronView.tintColor = .white
        chevronView.alpha = 0.3
        chevronView.contentMode = .center
        wrapperView.addSubview(chevronView)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = label.text
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = pillWidth
        wrapperView.bounds = CGRect(x: 0, y: 0, width: width, height: Self.height)
        wrapperView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        backgroundView.frame = wrapperView.bounds
        thumbnailView.frame = CGRect(x: 1, y: 1, width: 24, height: 24)
        let labelSize = label.intrinsicContentSize
        label.frame = CGRect(
            x: 10 + (hasImage ? Self.imageInset : 0),
            y: (Self.height - labelSize.height) / 2,
            width: labelSize.width,
            height: labelSize.height,
        )
        chevronView.frame = CGRect(x: label.frame.maxX + 4, y: 7, width: 8, height: 12)
    }

    /// `setImage:`: the saved cover in its circle, or none.
    func setImage(_ image: UIImage?) {
        thumbnailView.image = image
        thumbnailView.isHidden = image == nil
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}
