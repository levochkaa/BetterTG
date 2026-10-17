// StoryViewerViews.swift

import UIKit

// MARK: - StoryChromeLayout

/// The story's header (StoryItemSetContainerComponent): the progress strip 8 pt from the top and sides, the 32 pt
/// avatar with the title and time beside it, and the close button at the trailing edge with the More button before
/// it. The viewer and the cube's side faces share it, so a turn lands on the same layout.
enum StoryChromeLayout {
    static let cornerRadius = CGFloat(12)
    static let avatarFrame = CGRect(x: 12, y: 22, width: 32, height: 32)

    /// Telegram's anim_story_more dots as the plain glyph BetterTG's header uses.
    static var moreImage: UIImage? {
        UIImage(
            systemName: "ellipsis",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
        )
    }

    static func progressFrame(in bounds: CGRect) -> CGRect {
        CGRect(x: 8, y: 8, width: bounds.width - 16, height: 2)
    }

    static func closeFrame(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.width - 48, y: 16, width: 44, height: 44)
    }

    /// Telegram's 33 pt More button, ending 51 pt from the trailing edge beside the close button.
    static func moreFrame(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.width - 84, y: 16, width: 33, height: 44)
    }

    /// The title ends 12 pt before the More button (headerRightOffset), or at the close button without it.
    static func textTrailingLimit(in bounds: CGRect, showsMore: Bool) -> CGFloat {
        showsMore ? moreFrame(in: bounds).minX - 12 : closeFrame(in: bounds).minX
    }

    static func textFrames(in _: CGRect, trailingLimit: CGFloat) -> (title: CGRect, subtitle: CGRect) {
        let x = avatarFrame.maxX + 10
        let width = max(0, trailingLimit - x - 4)
        return (CGRect(x: x, y: 21, width: width, height: 18), CGRect(x: x, y: 39, width: width, height: 14))
    }
}

// MARK: - StoryProgressStripView

/// Telegram's story progress strip (MediaNavigationStripComponent): one 2 pt segment per story, 3 pt apart, white at
/// half opacity, the shown story filling with its progress and the earlier ones full.
final class StoryProgressStripView: UIView {
    private static let spacing = CGFloat(3)
    private static let height = CGFloat(2)
    private static let minimumWidth = CGFloat(2)

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.height)
    }

    private var tracks = [UIView]()
    private var fills = [UIView]()
    private var index = 0
    private var progress = CGFloat(0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !tracks.isEmpty else { return }
        let count = CGFloat(tracks.count)
        let width = max(Self.minimumWidth, (bounds.width - (count - 1) * Self.spacing) / count)
        // Too many stories to fit keep the shown one in view, as Telegram's strip scrolls to it.
        let total = count * width + (count - 1) * Self.spacing
        let shownMidX = CGFloat(index) * (width + Self.spacing) + width / 2
        let offset = total <= bounds.width ? 0 : min(max(0, shownMidX - bounds.width / 2), total - bounds.width)
        for (position, track) in tracks.enumerated() {
            let frame = CGRect(
                x: CGFloat(position) * (width + Self.spacing) - offset,
                y: (bounds.height - Self.height) / 2,
                width: width,
                height: Self.height,
            )
            track.frame = frame
            let fraction: CGFloat = position < index ? 1 : (position == index ? progress : 0)
            fills[position].frame = CGRect(x: 0, y: 0, width: frame.width * fraction, height: Self.height)
        }
    }

    func configure(count: Int, index: Int) {
        let count = max(1, count)
        if tracks.count != count {
            tracks.forEach { $0.removeFromSuperview() }
            tracks = (0..<count).map { _ in
                let track = UIView()
                track.backgroundColor = UIColor.white.withAlphaComponent(0.5)
                track.layer.cornerRadius = Self.height / 2
                track.clipsToBounds = true
                addSubview(track)
                return track
            }
            fills = tracks.map { track in
                let fill = UIView()
                fill.backgroundColor = .white
                track.addSubview(fill)
                return fill
            }
        }
        self.index = min(max(0, index), count - 1)
        progress = 0
        setNeedsLayout()
    }

    func setProgress(_ progress: CGFloat) {
        let clamped = min(1, max(0, progress))
        guard abs(clamped - self.progress) > 0.0005 || clamped == 0 || clamped == 1 else { return }
        self.progress = clamped
        setNeedsLayout()
    }
}

// MARK: - StoryShadeView

/// The dark gradient under the story's header or caption, which keeps white text readable on light media.
final class StoryShadeView: UIView {
    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    init(fromTop: Bool) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.colors = [UIColor.black.withAlphaComponent(0.45).cgColor, UIColor.black.withAlphaComponent(0).cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: fromTop ? 0 : 1)
        gradient.endPoint = CGPoint(x: 0.5, y: fromTop ? 1 : 0)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
