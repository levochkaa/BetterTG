// StoryViewerAreas.swift

import TDLibKit
import UIKit

// MARK: - StoryAreaGeometry

/// Where a story's areas sit (StoryItemOverlaysView.getFrameAndRotation and StoryItemSetContainerComponent's tap
/// test): a center, size and rotation in percent of the story's size and degrees, and a corner radius in percent of
/// the area's width.
enum StoryAreaGeometry {
    struct Placement: Equatable {
        let frame: CGRect
        let rotation: CGFloat
        let cornerRadius: CGFloat
    }

    /// Taps this close to the story's sides navigate, whatever area lies under them.
    static let tapSafeInset = CGFloat(48)

    /// The area's frame before its rotation; areas under 5 pt aren't drawn.
    static func placement(of position: StoryAreaPosition, in size: CGSize, scale: CGFloat = 1) -> Placement? {
        let width = CGFloat(position.widthPercentage) / 100 * size.width * scale
        let height = CGFloat(position.heightPercentage) / 100 * size.height * scale
        let frame = CGRect(
            x: CGFloat(position.xPercentage) / 100 * size.width - width / 2,
            y: CGFloat(position.yPercentage) / 100 * size.height - height / 2,
            width: width,
            height: height,
        )
        guard frame.width >= 5, frame.height >= 5 else { return nil }
        return Placement(
            frame: frame,
            rotation: CGFloat(position.rotationAngle) * .pi / 180,
            cornerRadius: CGFloat(position.cornerRadiusPercentage) / 100 * width,
        )
    }

    /// The topmost area under a tap, turned with the area and a tenth larger than it. Telegram sends a reaction from
    /// its own button, so reactions are passed over here; BetterTG leaves upgraded gifts out.
    static func area(at point: CGPoint, in size: CGSize, areas: [StoryArea]) -> Int? {
        guard point.x > tapSafeInset, point.x < size.width - tapSafeInset else { return nil }
        for index in areas.indices.reversed() {
            switch areas[index].type {
            case .storyAreaTypeSuggestedReaction, .storyAreaTypeUpgradedGift:
                continue
            case .storyAreaTypeLink, .storyAreaTypeLocation, .storyAreaTypeMessage, .storyAreaTypeVenue,
                 .storyAreaTypeWeather:
                if contains(point, position: areas[index].position, in: size) { return index }
            }
        }
        return nil
    }

    static func contains(_ point: CGPoint, position: StoryAreaPosition, in size: CGSize) -> Bool {
        let tx = point.x - CGFloat(position.xPercentage) / 100 * size.width
        let ty = point.y - CGFloat(position.yPercentage) / 100 * size.height
        let angle = -CGFloat(position.rotationAngle) * .pi / 180
        let rotatedX = tx * cos(angle) - ty * sin(angle)
        let rotatedY = tx * sin(angle) + ty * cos(angle)
        let halfWidth = CGFloat(position.widthPercentage) / 100 * size.width / 2 * 1.1
        let halfHeight = CGFloat(position.heightPercentage) / 100 * size.height / 2 * 1.1
        return abs(rotatedX) <= halfWidth && abs(rotatedY) <= halfHeight
    }

    /// activateMediaArea's tooltip source: a 16 pt column through the area's center, a tenth taller than the area.
    static func tooltipSource(of position: StoryAreaPosition, in size: CGSize) -> CGRect {
        let height = CGFloat(position.heightPercentage) / 100 * size.height * 1.1
        return CGRect(
            x: CGFloat(position.xPercentage) / 100 * size.width - 8,
            y: CGFloat(position.yPercentage) / 100 * size.height - height / 2,
            width: 16,
            height: height,
        )
    }
}

// MARK: - StoryAreaFont

private enum StoryAreaFont {
    /// Telegram's camera font (Font.with(design: .camera)), or the system's when iOS doesn't have it.
    static func camera(size: CGFloat) -> UIFont {
        UIFont(name: "SFCamera-Semibold", size: size)
            ?? .monospacedDigitSystemFont(ofSize: size, weight: .semibold)
    }
}

// MARK: - StoryWeatherFormat

/// TelegramStringFormatting's stringForTemperature: the locale's temperature without its unit, then °C or °F.
enum StoryWeatherFormat {
    static func temperature(_ celsius: Double, locale: Locale = .current) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 0
        let value = formatter
            .string(from: Measurement(value: celsius, unit: UnitTemperature.celsius))
            .trimmingCharacters(in: CharacterSet(charactersIn: "0123456789-,.").inverted)
        return value + (usesFahrenheit(locale: locale) ? "°F" : "°C")
    }

    static func usesFahrenheit(locale: Locale) -> Bool {
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        let string = formatter.string(from: Measurement(value: 0, unit: UnitTemperature.fahrenheit))
        return string.contains("F") || string.contains("Fahrenheit")
    }
}

// MARK: - StoryAreaOverlayView

/// The areas a story draws over its media (StoryItemOverlaysView): suggested reactions on Telegram's outline with
/// their counts, and weather on its colour. Locations, venues, messages and links stay invisible tap targets.
final class StoryAreaOverlayView: UIView {
    private var areas = [StoryArea]()
    private var signature = [String]()
    private var itemViews = [(index: Int, view: UIView)]()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (index, view) in itemViews {
            guard areas.indices.contains(index) else { continue }
            let position = areas[index].position
            switch view {
            case let reaction as StoryReactionAreaView:
                guard let placement = StoryAreaGeometry.placement(of: position, in: bounds.size, scale: 0.97) else {
                    reaction.isHidden = true
                    continue
                }
                reaction.isHidden = false
                reaction.transform = .identity
                reaction.bounds = CGRect(origin: .zero, size: placement.frame.size)
                reaction.center = CGPoint(x: placement.frame.midX, y: placement.frame.midY)
                reaction.transform = CGAffineTransform(rotationAngle: placement.rotation)
            case let weather as StoryWeatherAreaView:
                guard let placement = StoryAreaGeometry.placement(of: position, in: bounds.size) else {
                    weather.isHidden = true
                    continue
                }
                weather.isHidden = false
                weather.transform = .identity
                let size = weather.update(height: placement.frame.height, cornerRadius: placement.cornerRadius)
                weather.bounds = CGRect(origin: .zero, size: size)
                weather.center = CGPoint(x: placement.frame.midX, y: placement.frame.midY)
                weather.transform = CGAffineTransform(rotationAngle: placement.rotation)
            default:
                break
            }
        }
    }

    private static func signature(of area: StoryArea) -> String {
        let position = area.position
        let place = [
            position.xPercentage, position.yPercentage, position.widthPercentage, position.heightPercentage,
            position.rotationAngle, position.cornerRadiusPercentage,
        ]
            .map { String($0) }
            .joined(separator: ",")
        switch area.type {
        case .storyAreaTypeSuggestedReaction(let reaction):
            let type = reaction.reactionType.standardEmoji
                ?? reaction.reactionType.customEmojiID.map { String($0) } ?? "paid"
            return "reaction:\(place):\(type):\(reaction.totalCount):\(reaction.isDark):\(reaction.isFlipped)"
        case .storyAreaTypeWeather(let weather):
            return "weather:\(place):\(weather.emoji):\(weather.temperature):\(weather.backgroundColor)"
        case .storyAreaTypeLink, .storyAreaTypeLocation, .storyAreaTypeMessage, .storyAreaTypeUpgradedGift,
             .storyAreaTypeVenue:
            return "area:\(place)"
        }
    }

    /// Shows a story's areas; the same areas again keep their views and loaded stickers.
    func update(areas: [StoryArea], client: TDLibClient, loadsStickers: Bool) {
        let signature = areas.map(Self.signature)
        self.areas = areas
        guard signature != self.signature else {
            setNeedsLayout()
            return
        }
        self.signature = signature
        itemViews.forEach { $0.view.removeFromSuperview() }
        itemViews = areas.enumerated().compactMap { index, area -> (index: Int, view: UIView)? in
            switch area.type {
            case .storyAreaTypeSuggestedReaction(let reaction):
                let view = StoryReactionAreaView(reaction: reaction, client: client, loadsSticker: loadsStickers)
                addSubview(view)
                return (index, view)
            case .storyAreaTypeWeather(let weather):
                let view = StoryWeatherAreaView(weather: weather, client: client, loadsSticker: loadsStickers)
                addSubview(view)
                return (index, view)
            case .storyAreaTypeLink, .storyAreaTypeLocation, .storyAreaTypeMessage, .storyAreaTypeUpgradedGift,
                 .storyAreaTypeVenue:
                return nil
            }
        }
        setNeedsLayout()
    }
}

// MARK: - StoryReactionAreaView

/// StoryItemOverlaysView.ReactionView: the reaction's sticker on Telegram's speech-bubble outline, white or a dark
/// glass, mirrored when the poster flipped it, with the count under the sticker once anyone reacted.
private final class StoryReactionAreaView: UIView {
    private let reaction: TDNativeStoryAreaTypeSuggestedReaction
    private let shadowView = UIImageView(image: UIImage(named: "Stories/ReactionShadow"))
    private let coverView = UIImageView(
        image: UIImage(named: "Stories/ReactionOutline")?.withRenderingMode(.alwaysTemplate),
    )
    private let emojiLabel = UILabel()
    private let stickerView = CustomEmojiInlineView()
    private let counterLabel = UILabel()
    private var stickerTask: Task<Void, Never>?

    init(reaction: TDNativeStoryAreaTypeSuggestedReaction, client: TDLibClient, loadsSticker: Bool) {
        self.reaction = reaction
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        addSubview(shadowView)
        coverView.tintColor = reaction.isDark ? UIColor.black.withAlphaComponent(0.5) : .white
        addSubview(coverView)
        if reaction.isFlipped {
            shadowView.transform = CGAffineTransform(scaleX: -1, y: 1)
            coverView.transform = CGAffineTransform(scaleX: -1, y: 1)
        }
        emojiLabel.text = reaction.reactionType
            .standardEmoji ?? (reaction.reactionType.customEmojiID == nil ? "⭐" : nil)
        emojiLabel.textAlignment = .center
        addSubview(emojiLabel)
        stickerView.isHidden = true
        stickerView.clipsToBounds = true
        stickerView.onFirstFrameReady = { [weak self] in
            self?.stickerView.isHidden = false
            self?.emojiLabel.isHidden = true
        }
        addSubview(stickerView)
        counterLabel.font = StoryAreaFont.camera(size: 17)
        counterLabel.textColor = reaction.isDark ? .white : .black
        counterLabel.text = reaction.totalCount == 0 ? nil : "\(reaction.totalCount)"
        counterLabel.isHidden = reaction.totalCount == 0
        addSubview(counterLabel)
        if loadsSticker { loadSticker(client: client) }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stickerTask?.cancel()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        stickerView.setPlaybackVisible(window != nil)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        // The outline reaches past the area: 5% left, 8% up, 2% right and 1% down.
        let coverFrame = CGRect(
            x: size.width * -0.05,
            y: size.height * -0.08,
            width: size.width * 1.07,
            height: size.height * 1.09,
        )
        for view in [shadowView, coverView] {
            view.bounds = CGRect(origin: .zero, size: coverFrame.size)
            view.center = CGPoint(x: coverFrame.midX, y: coverFrame.midY)
        }
        let hasCounter = reaction.totalCount != 0
        let side = floor(min(200, min(size.width, size.height)) * 0.65)
        let stickerCenter = CGPoint(x: size.width * 0.49, y: size.height * (0.47 + (hasCounter ? -0.05 : 0)))
        let stickerScale: CGFloat = hasCounter ? 0.8 : 1
        for view in [emojiLabel, stickerView] as [UIView] {
            view.transform = .identity
            view.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            view.center = stickerCenter
            view.transform = CGAffineTransform(scaleX: stickerScale, y: stickerScale)
        }
        emojiLabel.font = .systemFont(ofSize: side * 0.8)
        stickerView.layer.cornerRadius = reaction.reactionType.customEmojiID == nil ? 0 : side * 0.1
        counterLabel.transform = .identity
        counterLabel.sizeToFit()
        counterLabel.center = CGPoint(x: size.width * 0.5, y: size.height * 0.765)
        let counterScale = max(0.01, min(1.8, size.width / 140))
        counterLabel.transform = CGAffineTransform(scaleX: counterScale, y: counterScale)
    }

    /// A standard reaction's select animation (the still animation Telegram's available reactions give it), or the
    /// custom emoji's sticker.
    private func loadSticker(client: TDLibClient) {
        let type = reaction.reactionType
        stickerTask = Task { [weak self] in
            let sticker: Sticker? =
                if let emoji = type.standardEmoji {
                    try? await client.send(TDNativeRequests.getEmojiReaction(emoji: emoji)).selectAnimation
                } else if let customEmojiID = type.customEmojiID {
                    await CustomEmojiStickerRepository.shared
                        .stickers(for: [customEmojiID], client: client)[customEmojiID]
                } else {
                    nil
                }
            guard let self, !Task.isCancelled, let sticker else { return }
            if emojiLabel.text == nil { emojiLabel.text = sticker.emoji }
            stickerView.configure(sticker: sticker, client: client)
            stickerView.setPlaybackVisible(window != nil)
        }
    }
}

// MARK: - StoryWeatherAreaView

/// StoryItemOverlaysView.WeatherView: the weather's animated emoji and temperature on the poster's colour, black text
/// on a light one.
private final class StoryWeatherAreaView: UIView {
    private let weather: TDNativeStoryAreaTypeWeather
    private let backgroundView = UIView()
    private let emojiLabel = UILabel()
    private let stickerView = CustomEmojiInlineView()
    private let temperatureLabel = UILabel()
    private var stickerTask: Task<Void, Never>?

    init(weather: TDNativeStoryAreaTypeWeather, client: TDLibClient, loadsSticker: Bool) {
        self.weather = weather
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        let background = Self.color(argb: weather.backgroundColor)
        backgroundView.backgroundColor = background
        backgroundView.clipsToBounds = true
        backgroundView.layer.cornerCurve = .continuous
        addSubview(backgroundView)
        emojiLabel.text = weather.emoji
        emojiLabel.textAlignment = .center
        addSubview(emojiLabel)
        stickerView.isHidden = true
        stickerView.onFirstFrameReady = { [weak self] in
            self?.stickerView.isHidden = false
            self?.emojiLabel.isHidden = true
        }
        addSubview(stickerView)
        addSubview(temperatureLabel)
        if loadsSticker { loadSticker(client: client) }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stickerTask?.cancel()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        stickerView.setPlaybackVisible(window != nil)
    }

    /// TDLib's ARGB colour (UIColor(argb:)).
    private static func color(argb: Int) -> UIColor {
        let value = UInt32(truncatingIfNeeded: argb)
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: CGFloat((value >> 24) & 0xFF) / 255,
        )
    }

    /// Display's UIColor.lightness: the Rec. 709 luma.
    private static func lightness(of color: UIColor) -> CGFloat {
        var red = CGFloat(0)
        var green = CGFloat(0)
        var blue = CGFloat(0)
        if color.getRed(&red, green: &green, blue: &blue, alpha: nil) {
            return 0.2126 * red + 0.7152 * green + 0.0722 * blue
        }
        var white = CGFloat(0)
        return color.getWhite(&white, alpha: nil) ? white : 0
    }

    /// Lays the weather out at the area's height and returns its width, which follows the temperature's text.
    func update(height: CGFloat, cornerRadius: CGFloat) -> CGSize {
        let scale = max(1, traitCollection.displayScale)
        let itemSide = floor(height * 0.71)
        let textColor: UIColor = Self.lightness(of: backgroundView.backgroundColor ?? .black) > 0.705 ? .black : .white
        let font = StoryAreaFont.camera(size: floor(height * 0.69 * scale) / scale)
        temperatureLabel.attributedText = NSAttributedString(
            string: StoryWeatherFormat.temperature(weather.temperature),
            attributes: [.font: font, .foregroundColor: textColor, .kern: -(height / 38)],
        )
        let textSize = temperatureLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: height))
        let leftInset = height * 0.058
        let rightInset = height * 0.2
        let spacing = height * 0.205
        let contentWidth = leftInset + itemSide + spacing + textSize.width + rightInset
        temperatureLabel.frame = CGRect(
            x: contentWidth - textSize.width - rightInset,
            y: floor((height - textSize.height) / 2 * scale) / scale,
            width: textSize.width,
            height: textSize.height,
        )
        let stickerFrame = CGRect(
            x: height * 0.5 + leftInset - itemSide / 2,
            y: height * 0.5 - itemSide / 2,
            width: itemSide,
            height: itemSide,
        )
        stickerView.frame = stickerFrame
        emojiLabel.frame = stickerFrame
        emojiLabel.font = .systemFont(ofSize: itemSide * 0.8)
        backgroundView.frame = CGRect(x: 0, y: 0, width: contentWidth, height: height)
        backgroundView.layer.cornerRadius = cornerRadius
        return CGSize(width: contentWidth, height: height)
    }

    /// The weather's emoji as Telegram's animated emoji (animatedEmojiStickers), looping.
    private func loadSticker(client: TDLibClient) {
        let emoji = weather.emoji
        stickerTask = Task { [weak self] in
            let sticker = try? await client.send(TDNativeRequests.getAnimatedEmoji(emoji: emoji)).sticker
            guard let self, !Task.isCancelled, let sticker else { return }
            stickerView.configure(sticker: sticker, client: client)
            stickerView.setPlaybackVisible(window != nil)
        }
    }
}

// MARK: - StoryAreaTooltipView

/// The tooltip a story area opens (makeContextMenuController with one blurred dark action): Telegram's ContextMenuNode
/// bubble, 10 pt corners and an 18 by 9 pt arrow towards the area, above it when it fits, with the action's title, an
/// optional grey subtitle and a chevron. A tap on it runs the action; a touch anywhere else dismisses it and goes on
/// to the story, as the menu doesn't catch outside taps.
final class StoryAreaTooltipView: UIView {
    private static let cornerRadius = CGFloat(10)
    private static let arrowWidth = CGFloat(18)
    private static let verticalInset = CGFloat(9)

    /// Runs as the tooltip starts to leave, whether it was used or dismissed.
    var onDismiss: (() -> Void)?

    private let bubble = UIControl()
    private let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let highlightView = UIView()
    private let maskLayer = CAShapeLayer()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let iconView = UIImageView()
    private let action: () -> Void
    private var isDismissing = false

    init(title: String, subtitle: String?, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        bubble.layer.shadowColor = UIColor.black.cgColor
        bubble.layer.shadowRadius = 10
        bubble.layer.shadowOpacity = 0.2
        bubble.layer.shadowOffset = CGSize(width: 0, height: 5)
        bubble.accessibilityTraits = .button
        bubble.isAccessibilityElement = true
        bubble.accessibilityLabel = [title, subtitle].compactMap(\.self).joined(separator: ", ")
        bubble.addTarget(self, action: #selector(pressed), for: .touchUpInside)
        bubble.addTarget(self, action: #selector(highlightChanged), for: [.touchDown, .touchDragEnter])
        bubble.addTarget(self, action: #selector(highlightChanged), for: [.touchDragExit, .touchCancel])
        addSubview(bubble)

        effectView.isUserInteractionEnabled = false
        effectView.layer.mask = maskLayer
        bubble.addSubview(effectView)
        highlightView.isUserInteractionEnabled = false
        effectView.contentView.addSubview(highlightView)

        titleLabel.font = .systemFont(ofSize: 17)
        titleLabel.textColor = .white
        titleLabel.text = title
        bubble.addSubview(titleLabel)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        bubble.addSubview(subtitleLabel)
        // Telegram's Settings/TextArrowRight is the 7 by 13 pt chevron.right glyph.
        iconView.image = UIImage(
            systemName: "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold),
        )
        iconView.tintColor = .white
        bubble.addSubview(iconView)
        for label in [titleLabel, subtitleLabel] {
            label.isUserInteractionEnabled = false
        }
        iconView.isUserInteractionEnabled = false
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !isDismissing, bubble.frame.contains(point) { return bubble }
        if event?.type == .touches, !isDismissing { dismiss() }
        return nil
    }

    /// ContextMenuContainerNode's mask: a rounded rectangle 9 pt in from the top and bottom, with the arrow in the
    /// inset on the source's side, kept clear of the corners.
    private static func path(size: CGSize, arrowPosition: CGFloat, arrowOnBottom: Bool) -> UIBezierPath {
        let radius = cornerRadius
        let inset = verticalInset
        let arrow = max(radius + arrowWidth / 2, min(size.width - radius - arrowWidth / 2, arrowPosition))
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: inset + radius))
        path.addArc(
            withCenter: CGPoint(x: radius, y: inset + radius),
            radius: radius,
            startAngle: .pi,
            endAngle: 3 * .pi / 2,
            clockwise: true,
        )
        if !arrowOnBottom {
            path.addLine(to: CGPoint(x: arrow - arrowWidth / 2, y: inset))
            path.addLine(to: CGPoint(x: arrow, y: 0))
            path.addLine(to: CGPoint(x: arrow + arrowWidth / 2, y: inset))
        }
        path.addLine(to: CGPoint(x: size.width - radius, y: inset))
        path.addArc(
            withCenter: CGPoint(x: size.width - radius, y: inset + radius),
            radius: radius,
            startAngle: 3 * .pi / 2,
            endAngle: 0,
            clockwise: true,
        )
        path.addLine(to: CGPoint(x: size.width, y: size.height - radius - inset))
        path.addArc(
            withCenter: CGPoint(x: size.width - radius, y: size.height - radius - inset),
            radius: radius,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: true,
        )
        if arrowOnBottom {
            path.addLine(to: CGPoint(x: arrow + arrowWidth / 2, y: size.height - inset))
            path.addLine(to: CGPoint(x: arrow, y: size.height))
            path.addLine(to: CGPoint(x: arrow - arrowWidth / 2, y: size.height - inset))
        }
        path.addLine(to: CGPoint(x: radius, y: size.height - inset))
        path.addArc(
            withCenter: CGPoint(x: radius, y: size.height - radius - inset),
            radius: radius,
            startAngle: .pi / 2,
            endAngle: .pi,
            clockwise: true,
        )
        path.close()
        return path
    }

    /// Lays the tooltip out against `source` inside `container` (ContextMenuNode.containerLayoutUpdated with
    /// centerHorizontally) and springs it in from the arrow.
    func show(in host: UIView, source: CGRect, container: CGRect) {
        frame = host.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(self)

        let maxTextWidth = max(0, bounds.width - 36 - 24)
        let titleSize = titleLabel.sizeThatFits(CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude))
        let textSize = CGSize(width: min(maxTextWidth, ceil(titleSize.width)), height: ceil(titleSize.height))
        var subtitleSize = CGSize.zero
        var height = CGFloat(54)
        var contentWidth = textSize.width
        if subtitleLabel.text != nil {
            let fitted = subtitleLabel.sizeThatFits(CGSize(
                width: maxTextWidth * 0.75,
                height: .greatestFiniteMagnitude,
            ))
            subtitleSize = CGSize(width: min(maxTextWidth * 0.75, ceil(fitted.width)), height: ceil(fitted.height))
            contentWidth = max(contentWidth, subtitleSize.width)
            height += 14
        }
        let iconSize = iconView.image?.size ?? .zero
        let innerWidth = contentWidth + 11 + iconSize.width
        let width = innerWidth + 24

        let arrowOnBottom = source.minY - height > container.minY
        let y = arrowOnBottom ? source.minY - height : min(container.maxY - height, source.maxY)
        let x = floor(max(8, min(source.midX - width / 2, bounds.width - width - 8)))
        bubble.frame = CGRect(x: x, y: y, width: width, height: height)
        effectView.frame = bubble.bounds
        highlightView.frame = bubble.bounds

        let textHeight = textSize.height + subtitleSize.height
        let textX = floor((width - innerWidth) / 2)
        let textY = floor((height - textHeight) / 2)
        titleLabel.frame = CGRect(x: textX, y: textY, width: textSize.width, height: textSize.height)
        subtitleLabel.frame = CGRect(
            x: textX,
            y: textY + textHeight - subtitleSize.height,
            width: subtitleSize.width,
            height: subtitleSize.height,
        )
        iconView.frame = CGRect(
            x: textX + innerWidth - iconSize.width,
            y: floor((height - iconSize.height) / 2),
            width: iconSize.width,
            height: iconSize.height,
        )

        let path = Self.path(size: bubble.bounds.size, arrowPosition: source.midX - x, arrowOnBottom: arrowOnBottom)
        maskLayer.path = path.cgPath
        bubble.layer.shadowPath = path.cgPath

        guard !UIAccessibility.isReduceMotionEnabled else {
            bubble.layer.addTooltipAlpha(from: 0, to: 1, duration: 0.1)
            return
        }
        bubble.layer.addTooltipSpring(keyPath: "transform.scale", from: 0.2, to: 1)
        let position = bubble.layer.position
        let start = CGPoint(x: position.x, y: position.y + (arrowOnBottom ? 1 : -1) * height / 2)
        bubble.layer.addTooltipSpring(
            keyPath: "position",
            from: NSValue(cgPoint: start),
            to: NSValue(cgPoint: position),
        )
        bubble.layer.addTooltipAlpha(from: 0, to: 1, duration: 0.1)
    }

    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        onDismiss?()
        onDismiss = nil
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState]) {
            self.bubble.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }

    @objc private func highlightChanged() {
        highlightView.backgroundColor = bubble.isHighlighted ? UIColor.white.withAlphaComponent(0.5) : .clear
    }

    @objc private func pressed() {
        guard !isDismissing else { return }
        highlightView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        action()
        dismiss()
    }
}

private extension CALayer {
    /// Display's animateSpring: a mass-5, stiffness-900, damping-88 spring sped up to settle in 0.4 s.
    func addTooltipSpring(keyPath: String, from: Any, to: Any) {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = 5
        animation.stiffness = 900
        animation.damping = 88
        animation.duration = animation.settlingDuration
        animation.speed = Float(animation.duration / 0.4)
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.fromValue = from
        animation.toValue = to
        add(animation, forKey: keyPath)
    }

    func addTooltipAlpha(from: CGFloat, to: CGFloat, duration: CFTimeInterval) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        add(animation, forKey: "opacity")
    }
}
