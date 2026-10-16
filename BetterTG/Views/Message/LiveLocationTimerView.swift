// LiveLocationTimerView.swift

import UIKit

// MARK: - LiveLocationUpdateText

/// Telegram's stringForRelativeLiveLocationTimestamp, with stringForFullDate for an update before today: when a
/// live location last moved.
enum LiveLocationUpdateText {
    static func string(since updateDate: Foundation.Date) -> String {
        let now = Foundation.Date()
        let difference = Int(now.timeIntervalSince(updateDate))
        if difference < 60 {
            return L10n.telegram("LiveLocationUpdated.JustNow")
        }
        if difference < 60 * 60 {
            return L10n.telegramPlural("LiveLocationUpdated.MinutesAgo", count: difference / 60)
        }
        let time = updateDate.formatted(date: .omitted, time: .shortened)
        let calendar = Foundation.Calendar.current
        if calendar.isDate(updateDate, inSameDayAs: now) {
            return L10n.telegram("LiveLocationUpdated.TodayAt", time)
        }
        let components = calendar.dateComponents([.day, .month, .year], from: updateDate)
        guard let day = components.day, let month = components.month, let year = components.year else { return time }
        return L10n.telegram("Time.PreciseDate_m\(month)", "\(day)", "\(year)", time)
    }
}

// MARK: - LiveLocationTimerView

/// Telegram's ChatMessageLiveLocationTimerNode: a ring in the tint color that empties as a live location's period
/// runs out, around the remaining minutes, the rounded hours, or ∞ for a location shared until it is stopped. The
/// owner redraws it; Telegram does so every 10 seconds. A ring under 28 points, as in the location viewer's lists,
/// uses the node's compact fonts.
final class LiveLocationTimerView: UIView {
    private static let infinityFont = roundedBoldFont(size: 15)
    private static let textFont = roundedBoldFont(size: 13)
    private static let smallTextFont = roundedBoldFont(size: 11)
    private static let compactInfinityFont = roundedBoldFont(size: 14)
    private static let compactTextFont = roundedBoldFont(size: 12)
    private static let compactSmallTextFont = roundedBoldFont(size: 10)

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

        let isCompact = bounds.width < 28
        let font: UIFont =
            if string == "∞" {
                isCompact ? Self.compactInfinityFont : Self.infinityFont
            } else if string.count > 2 {
                isCompact ? Self.compactSmallTextFont : Self.smallTextFont
            } else {
                isCompact ? Self.compactTextFont : Self.textFont
            }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foregroundColor]
        let label = string as NSString
        let size = label.size(withAttributes: attributes)
        let pixel = 1 / max(1, traitCollection.displayScale)
        let offset: CGPoint =
            if string == "∞" {
                isCompact ? CGPoint(x: 1 - pixel, y: 0) : CGPoint(x: 1, y: -1)
            } else if string.count > 2 {
                CGPoint(x: 0, y: pixel)
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
