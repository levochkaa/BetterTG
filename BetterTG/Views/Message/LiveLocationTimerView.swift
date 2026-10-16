// LiveLocationTimerView.swift

import UIKit

/// Telegram's ChatMessageLiveLocationTimerNode: a ring in the tint color that empties as a live location's period
/// runs out, around the remaining minutes, the rounded hours, or ∞ for a location shared until it is stopped. The
/// owner redraws it; Telegram does so every 10 seconds.
final class LiveLocationTimerView: UIView {
    private static let infinityFont = roundedBoldFont(size: 15)
    private static let textFont = roundedBoldFont(size: 13)
    private static let smallTextFont = roundedBoldFont(size: 11)

    private var deadline: Foundation.Date?
    private var period: TimeInterval = 0
    private var isIndefinite = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        setNeedsDisplay()
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let (value, string) = displayState()
        let lineWidth: CGFloat = 1.5
        let foregroundColor: UIColor = tintColor

        context.setBlendMode(.copy)
        context.setFillColor(foregroundColor.withAlphaComponent(0.4).cgColor)
        context.fillEllipse(in: bounds)
        context.setFillColor(UIColor.clear.cgColor)
        context.fillEllipse(in: bounds.insetBy(dx: lineWidth, dy: lineWidth))
        context.setBlendMode(.normal)

        let progress: CGFloat = 1 - value
        let startAngle: CGFloat = -progress * 2 * CGFloat.pi - CGFloat.pi / 2
        let endAngle: CGFloat = progress * 2 * CGFloat.pi + startAngle
        let path = UIBezierPath(
            arcCenter: CGPoint(x: bounds.width / 2, y: bounds.height / 2),
            radius: (bounds.width - lineWidth) / 2,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true,
        )
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        foregroundColor.setStroke()
        path.stroke()

        let font: UIFont =
            if string == "∞" {
                Self.infinityFont
            } else if string.count > 2 {
                Self.smallTextFont
            } else {
                Self.textFont
            }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foregroundColor]
        let label = string as NSString
        let size = label.size(withAttributes: attributes)
        let offset: CGPoint =
            if string == "∞" {
                CGPoint(x: 1, y: -1)
            } else if string.count > 2 {
                CGPoint(x: 0, y: 1 / max(1, traitCollection.displayScale))
            } else {
                .zero
            }
        label.draw(
            at: CGPoint(
                x: floor((bounds.width - size.width) / 2) + offset.x,
                y: floor((bounds.height - size.height) / 2) + offset.y,
            ),
            withAttributes: attributes,
        )
    }

    private nonisolated static func roundedBoldFont(size: CGFloat) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = font.fontDescriptor.withDesign(.rounded) else { return font }
        return UIFont(descriptor: descriptor, size: size)
    }

    func configure(deadline: Foundation.Date?, period: TimeInterval, isIndefinite: Bool) {
        self.deadline = deadline
        self.period = period
        self.isIndefinite = isIndefinite
        setNeedsDisplay()
    }

    /// The emptied fraction of the ring and its label, as the node's drawParameters computes them.
    private func displayState() -> (value: CGFloat, string: String) {
        if isIndefinite {
            return (0, "∞")
        }
        let remaining = max(0, deadline?.timeIntervalSinceNow ?? 0)
        let value = CGFloat(max(0, 1 - min(1, remaining / max(1, period))))
        if Int(remaining) > 60 * 60 {
            let hours = Int((remaining / (60 * 60)).rounded())
            return (value, hours > 99 ? "99+" : L10n.telegram("Map.LiveLocationShortHour", "\(hours)"))
        }
        return (value, "\(Int((remaining / 60).rounded()))")
    }
}
