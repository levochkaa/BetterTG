// StoryAvatarRingView.swift

import TDLibKit
import UIKit

// MARK: - StoryAvatarRingView

/// Telegram's story ring around an avatar (AvatarStoryIndicatorComponent): the green-to-blue gradient while the poster
/// has unseen stories, red for a live story, and a thin gray ring once every story was seen. The avatar inside shrinks
/// so one line width separates it from the ring (AvatarNode.updateStoryIndicator).
final class StoryAvatarRingView: UIView {
    enum Style: Equatable {
        case unseen
        case seen
        case live
    }

    /// Telegram's storyUnseenColors, storySeenColors and live colors.
    private static let unseenColors = [UIColor(rgb: 0x34C76F), UIColor(rgb: 0x3DA1FD)]
    private static let liveColors = [UIColor(rgb: 0xFF3777), UIColor(rgb: 0xFF2D55)]
    private static let seenColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(rgb: 0x48484A) : UIColor(rgb: 0xD8D8E1)
    }

    var style: Style? {
        didSet {
            guard style != oldValue else { return }
            update()
        }
    }

    private let activeLineWidth: CGFloat
    private let inactiveLineWidth: CGFloat
    private let gradientLayer = CAGradientLayer()
    private let maskLayer = CAShapeLayer()

    init(activeLineWidth: CGFloat, inactiveLineWidth: CGFloat) {
        self.activeLineWidth = activeLineWidth
        self.inactiveLineWidth = inactiveLineWidth
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        maskLayer.fillColor = UIColor.clear.cgColor
        maskLayer.strokeColor = UIColor.black.cgColor
        gradientLayer.mask = maskLayer
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(gradientLayer)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: StoryAvatarRingView, _) in
            view.update()
        }
        update()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        updatePath()
    }

    /// The avatar's scale inside a ring drawn with `lineWidth` around `diameter`.
    static func avatarScale(diameter: CGFloat, lineWidth: CGFloat) -> CGFloat {
        guard diameter > 0 else { return 1 }
        return (diameter - lineWidth * 4) / diameter
    }

    private func update() {
        isHidden = style == nil
        let colors: [UIColor] =
            switch style {
            case nil, .unseen: Self.unseenColors
            case .live: Self.liveColors
            case .seen: [Self.seenColor, Self.seenColor]
            }
        gradientLayer.colors = colors.map { $0.resolvedColor(with: traitCollection).cgColor }
        updatePath()
    }

    /// The ring's middle sits half an active line inside the bounds, for either width, as Telegram draws it.
    private func updatePath() {
        let diameter = min(bounds.width, bounds.height)
        guard diameter > 0 else { return }
        let radius = (diameter - activeLineWidth) / 2
        maskLayer.lineWidth = style == .seen ? inactiveLineWidth : activeLineWidth
        maskLayer.path = UIBezierPath(
            arcCenter: CGPoint(x: bounds.midX, y: bounds.midY),
            radius: radius,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true,
        ).cgPath
    }
}

extension ActiveStoryState {
    var ringStyle: StoryAvatarRingView.Style {
        switch self {
        case .activeStoryStateLive: .live
        case .activeStoryStateUnread: .unseen
        case .activeStoryStateRead: .seen
        }
    }
}

extension CustomChat {
    /// The active stories of a chat that posts them: a user or bot, a channel or a supergroup. Saved Messages and
    /// secret chats show none.
    var activeStoryState: ActiveStoryState? {
        guard !isSavedMessages, secretChatID == nil else { return nil }
        switch type {
        case .bot(let user), .user(let user):
            return user.activeStoryState
        case .supergroup(let supergroup):
            return supergroup.activeStoryState
        case .group:
            return nil
        }
    }
}
