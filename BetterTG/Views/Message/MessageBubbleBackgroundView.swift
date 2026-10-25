// MessageBubbleBackgroundView.swift

import UIKit

// MARK: - MessageBubbleMerge

/// ChatMessageBackgroundMergeType's neighbours: whether the same author's bubble continues right above (older) and
/// right below (newer), fully merged.
struct MessageBubbleMerge: Equatable {
    var withOlder = false
    var withNewer = false
}

// MARK: - MessageBubbleBackgroundView

/// messageBubbleImage as a view: the bubble's fill with Telegram's default corners (16 pt, 8 pt on the tail side next
/// to a merged neighbour) and, on a bubble no newer one continues, the tail curving out of its bottom corner on the
/// author's side. It sits under the bubble's content, pinned to its edges, and masks the bubble to the same shape,
/// so the tail goes with the bubble wherever it moves, a context menu's lift included.
final class MessageBubbleBackgroundView: UIView {
    private static let mainRadius: CGFloat = 16
    private static let auxiliaryRadius: CGFloat = 8

    /// The bubble's colour; clear draws nothing and leaves the bubble's corners alone.
    var fillColor = UIColor.clear {
        didSet { if fillColor != oldValue { setNeedsLayout() } }
    }

    /// ChatMessageBackgroundMergeType's `.Extracted`: lifted into a context menu, the bubble has whole corners and
    /// no tail.
    var isExtracted = false {
        didSet { if isExtracted != oldValue { setNeedsLayout() } }
    }

    private var outgoing = false
    private var merge = MessageBubbleMerge()
    private var drawsTail = false

    private let shapeLayer = CAShapeLayer()
    private let maskLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(shapeLayer)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.setNeedsLayout()
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = shapePath(in: bounds.size)
        shapeLayer.frame = bounds
        shapeLayer.path = path
        shapeLayer.fillColor = fillColor.resolvedColor(with: traitCollection).cgColor
        maskLayer.frame = bounds
        maskLayer.path = path
        superview?.layer.mask = maskLayer
        CATransaction.commit()
    }

    /// messageBubbleImage's tail in its 33 pt square, whose right and bottom edges are the bubble's: the corner's
    /// lower half filled down to the bottom ellipse's half, less the top ellipse that hollows its outer edge.
    private static func tailPath(width: CGFloat, height: CGFloat, outgoing: Bool) -> CGPath {
        let bottomEllipse = CGRect(x: 24, y: 16, width: 27, height: 17)
        let topEllipse = CGRect(x: 33, y: 14, width: 23, height: 21)
        let fill = CGMutablePath()
        fill.move(to: CGPoint(x: bottomEllipse.minX, y: bottomEllipse.midY))
        fill.addQuadCurve(
            to: CGPoint(x: bottomEllipse.midX, y: bottomEllipse.maxY),
            control: CGPoint(x: bottomEllipse.minX, y: bottomEllipse.maxY),
        )
        fill.addQuadCurve(
            to: CGPoint(x: bottomEllipse.maxX, y: bottomEllipse.midY),
            control: CGPoint(x: bottomEllipse.maxX, y: bottomEllipse.maxY),
        )
        fill.closeSubpath()
        fill.addRect(CGRect(x: 16.5, y: 16, width: 16.5, height: bottomEllipse.midY - 16))
        let tail = fill.subtracting(CGPath(ellipseIn: topEllipse, transform: nil))
        // The square's bottom right is the bubble's bottom corner on the author's side.
        var transform = outgoing
            ? CGAffineTransform(translationX: width - 33, y: height - 33)
            : CGAffineTransform(translationX: 33, y: height - 33).scaledBy(x: -1, y: 1)
        return tail.copy(using: &transform) ?? tail
    }

    /// `tail` is false for a bubble that never carries one, such as a centred service message.
    func configure(outgoing: Bool, merge: MessageBubbleMerge, tail: Bool) {
        let drawsTail = tail && !merge.withNewer
        guard outgoing != self.outgoing || merge != self.merge || drawsTail != self.drawsTail else { return }
        self.outgoing = outgoing
        self.merge = merge
        self.drawsTail = drawsTail
        setNeedsLayout()
    }

    /// The body's corners, then the tail united with it.
    private func shapePath(in size: CGSize) -> CGPath {
        let main = Self.mainRadius
        let tailTop = merge.withOlder && !isExtracted ? Self.auxiliaryRadius : main
        let tailBottom = merge.withNewer && !isExtracted ? Self.auxiliaryRadius : main
        let maxRadius = min(size.width, size.height) / 2
        let radii = (
            topLeft: min(outgoing ? main : tailTop, maxRadius),
            topRight: min(outgoing ? tailTop : main, maxRadius),
            bottomLeft: min(outgoing ? main : tailBottom, maxRadius),
            bottomRight: min(outgoing ? tailBottom : main, maxRadius),
        )
        let body = CGMutablePath()
        let width = size.width
        let height = size.height
        body.move(to: CGPoint(x: 0, y: radii.topLeft))
        body.addArc(
            tangent1End: CGPoint(x: 0, y: 0),
            tangent2End: CGPoint(x: radii.topLeft, y: 0),
            radius: radii.topLeft,
        )
        body.addLine(to: CGPoint(x: width - radii.topRight, y: 0))
        body.addArc(
            tangent1End: CGPoint(x: width, y: 0),
            tangent2End: CGPoint(x: width, y: radii.topRight),
            radius: radii.topRight,
        )
        body.addLine(to: CGPoint(x: width, y: height - radii.bottomRight))
        body.addArc(
            tangent1End: CGPoint(x: width, y: height),
            tangent2End: CGPoint(x: width - radii.bottomRight, y: height),
            radius: radii.bottomRight,
        )
        body.addLine(to: CGPoint(x: radii.bottomLeft, y: height))
        body.addArc(
            tangent1End: CGPoint(x: 0, y: height),
            tangent2End: CGPoint(x: 0, y: height - radii.bottomLeft),
            radius: radii.bottomLeft,
        )
        body.closeSubpath()
        guard drawsTail, !isExtracted, width >= 33, height >= 33 else { return body }
        return body.union(Self.tailPath(width: width, height: height, outgoing: outgoing))
    }
}
