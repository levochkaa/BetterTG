// TelegramUnreadBadgeLabel.swift

import UIKit

func compactNumericCountString(
    _ count: Int,
    decimalSeparator: String = Locale.current.decimalSeparator ?? ".",
    showDecimalPart: Bool = true,
) -> String {
    if count >= 1_000_000 {
        let remainder = count % 1_000_000 / 100_000
        if remainder != 0, showDecimalPart {
            return "\(count / 1_000_000)\(decimalSeparator)\(remainder)M"
        }
        return "\(count / 1_000_000)M"
    }
    if count >= 1000 {
        let remainder = count % 1000 / 100
        if remainder != 0, showDecimalPart {
            return "\(count / 1000)\(decimalSeparator)\(remainder)K"
        }
        return "\(count / 1000)K"
    }
    return "\(count)"
}

// MARK: - TelegramUnreadBadgeLabel

final class TelegramUnreadBadgeLabel: UILabel {
    override var intrinsicContentSize: CGSize {
        guard let font else { return CGSize(width: minimumDiameter, height: minimumDiameter) }
        let measuredText = usesStableChatListWidth ? stableMeasurementText : text ?? ""
        let textWidth = (measuredText as NSString).size(withAttributes: [.font: font]).width
        return CGSize(width: max(minimumDiameter, ceil(textWidth + horizontalPadding)), height: minimumDiameter)
    }

    private let minimumDiameter: CGFloat
    private let horizontalPadding: CGFloat
    private let usesStableChatListWidth: Bool

    private var stableMeasurementText: String {
        guard let text, !text.isEmpty else { return "" }
        guard text.count > 1 else { return "8" }
        return String(text.dropLast()) + "8"
    }

    init(minimumDiameter: CGFloat, horizontalPadding: CGFloat, usesStableChatListWidth: Bool = false) {
        self.minimumDiameter = minimumDiameter
        self.horizontalPadding = horizontalPadding
        self.usesStableChatListWidth = usesStableChatListWidth
        super.init(frame: .zero)
        textAlignment = .center
        clipsToBounds = true
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}
