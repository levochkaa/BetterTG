// TelegramSpoilerView.swift

import TDLibKit
import UIKit

// MARK: - TelegramSpoilers

enum TelegramSpoilers {
    static func ranges(in text: FormattedText) -> [NSRange] {
        let count = text.text.utf16.count
        let ranges = text.entities
            .compactMap { entity -> NSRange? in
                guard case .textEntityTypeSpoiler = entity.type,
                      entity.offset >= 0, entity.length > 0, entity.offset < count else { return nil }
                return NSRange(location: entity.offset, length: min(entity.length, count - entity.offset))
            }
            .sorted { $0.location < $1.location }
        var merged = [NSRange]()
        for range in ranges {
            if let last = merged.last, NSMaxRange(last) >= range.location {
                merged[merged.count - 1] = NSUnionRange(last, range)
            } else { merged.append(range) }
        }
        return merged
    }

    static func accessibilityText(_ text: FormattedText, revealed: Bool) -> String {
        guard !revealed else { return text.text }
        let redacted = NSMutableString(string: text.text)
        for range in ranges(in: text).reversed() {
            redacted.replaceCharacters(in: range, with: L10n.betterTG("Message.Spoiler"))
        }
        return String(redacted)
    }
}

// MARK: - TelegramSpoilerView

final class TelegramSpoilerView: UIView {
    private static let dot = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
        UIColor.white.setFill()
        context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 2, height: 2))
    }

    private let particles = CAEmitterLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = UIColor.secondaryLabel.withAlphaComponent(0.08)
        layer.cornerRadius = 3
        clipsToBounds = true
        particles.emitterShape = .rectangle
        particles.emitterMode = .surface
        layer.addSublayer(particles)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        particles.frame = bounds
        particles.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
        particles.emitterSize = bounds.size
        let cell = CAEmitterCell()
        cell.contents = Self.dot.cgImage
        cell.color = UIColor.secondaryLabel.resolvedColor(with: traitCollection).cgColor
        cell.birthRate = Float(max(8, bounds.width * bounds.height / 42))
        cell.lifetime = 1.8
        cell.velocity = 3
        cell.velocityRange = 2
        cell.emissionRange = .pi * 2
        cell.alphaSpeed = -0.45
        cell.scale = 0.55
        cell.scaleRange = 0.35
        particles.emitterCells = [cell]
        particles.birthRate = UIAccessibility.isReduceMotionEnabled ? 0 : 1
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(UIColor.secondaryLabel.withAlphaComponent(0.6).cgColor)
        // Stable dust is present before the first emitter frame and in Reduce Motion.
        for y in stride(from: 2.0, to: rect.height, by: 4) {
            for x in stride(from: 2.0, to: rect.width, by: 4) {
                let offset = CGFloat((Int(x) * 17 + Int(y) * 7) % 3)
                context.fillEllipse(in: CGRect(x: x + offset, y: y + offset / 2, width: 1, height: 1))
            }
        }
    }
}
