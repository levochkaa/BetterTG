// PhotoDrawing.swift

import UIKit

// MARK: - PhotoDrawingColor

/// DrawingColor: a painting color with its opacity.
struct PhotoDrawingColor: Equatable {
    static let white = PhotoDrawingColor(rgb: 0xFFFFFF)
    static let black = PhotoDrawingColor(rgb: 0x000000)

    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var cgColor: CGColor {
        uiColor.cgColor
    }

    /// UIColor's `lightness` in Telegram's Display.
    var lightness: CGFloat {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    /// The color as 0xRRGGBB.
    var rgb: Int {
        let component = { (value: CGFloat) in Int((min(max(value, 0), 1) * 255).rounded()) }
        return component(red) << 16 | component(green) << 8 | component(blue)
    }

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(rgb: Int, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha,
        )
    }

    init(_ color: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let clamp = { (value: CGFloat) in min(max(value, 0), 1) }
        self.init(red: clamp(red), green: clamp(green), blue: clamp(blue), alpha: clamp(alpha))
    }

    func withAlpha(_ value: CGFloat) -> PhotoDrawingColor {
        var color = self
        color.alpha = min(max(value, 0), 1)
        return color
    }

    /// UIColor's `mixedWith(_:alpha:)`.
    func mixed(with other: PhotoDrawingColor, alpha fraction: CGFloat) -> PhotoDrawingColor {
        let amount = min(max(fraction, 0), 1)
        let keep = 1 - amount
        return PhotoDrawingColor(
            red: red * keep + other.red * amount,
            green: green * keep + other.green * amount,
            blue: blue * keep + other.blue * amount,
            alpha: alpha * keep + other.alpha * amount,
        )
    }
}

// MARK: - PhotoDrawingTextStyle

/// DrawingTextEntity.Style without the story editor's blur.
enum PhotoDrawingTextStyle: CaseIterable {
    case regular
    case filled
    case semi
    case stroke

    /// TextSettingsComponent's style button: Regular, Filled, Semi and back, with the outlined style after Semi.
    var next: PhotoDrawingTextStyle {
        switch self {
        case .regular: .filled
        case .filled: .semi
        case .semi: .stroke
        case .stroke: .regular
        }
    }
}

// MARK: - PhotoDrawingTextAlignment

/// DrawingTextEntity.Alignment.
enum PhotoDrawingTextAlignment: CaseIterable {
    case left
    case center
    case right

    var next: PhotoDrawingTextAlignment {
        switch self {
        case .left: .center
        case .center: .right
        case .right: .left
        }
    }

    var textAlignment: NSTextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        }
    }
}

// MARK: - PhotoDrawingTextFont

/// DrawingTextFont: San Francisco and DrawingScreen's other fonts.
enum PhotoDrawingTextFont: CaseIterable {
    case sanFrancisco
    case typewriter
    case avenirNext
    case courierNew
    case noteworthy
    case georgia
    case papyrus
    case snellRoundhand

    var title: String {
        switch self {
        case .sanFrancisco: "San Francisco"
        case .typewriter: "Typewriter"
        case .avenirNext: "Avenir Next"
        case .courierNew: "Courier New"
        case .noteworthy: "Noteworthy"
        case .georgia: "Georgia"
        case .papyrus: "Papyrus"
        case .snellRoundhand: "Snell Roundhand"
        }
    }

    private var fontName: String? {
        switch self {
        case .sanFrancisco: nil
        case .typewriter: "AmericanTypewriter"
        case .avenirNext: "AvenirNext-DemiBoldItalic"
        case .courierNew: "CourierNewPS-BoldMT"
        case .noteworthy: "Noteworthy-Bold"
        case .georgia: "Georgia-Bold"
        case .papyrus: "Papyrus"
        case .snellRoundhand: "SnellRoundhand-Bold"
        }
    }

    /// `uiFont(size:)`: the named font, or San Francisco semibold.
    func font(size: CGFloat) -> UIFont {
        if let fontName, let font = UIFont(name: fontName, size: size) {
            return font
        }
        return .systemFont(ofSize: size, weight: .semibold)
    }
}

// MARK: - PhotoDrawingTextEntity

/// DrawingTextEntity.
struct PhotoDrawingTextEntity: Equatable {
    var string: String
    var style = PhotoDrawingTextStyle.filled
    var font = PhotoDrawingTextFont.sanFrancisco
    var alignment = PhotoDrawingTextAlignment.center
    /// The size between DrawingTextEntityView's smallest and largest font, 0 to 1.
    var fontSize: CGFloat = 0.08
    /// The width the text wraps at.
    var width: CGFloat
    var scale: CGFloat = 1
}

// MARK: - PhotoDrawingShapeKind

/// DrawingSimpleShapeEntity's shapes and DrawingBubbleEntity.
enum PhotoDrawingShapeKind {
    case rectangle
    case ellipse
    case bubble
    case star
}

// MARK: - PhotoDrawingDrawType

/// DrawingSimpleShapeEntity.DrawType.
enum PhotoDrawingDrawType {
    case fill
    case stroke
}

// MARK: - PhotoDrawingShapeEntity

/// DrawingSimpleShapeEntity and DrawingBubbleEntity.
struct PhotoDrawingShapeEntity: Equatable {
    var kind: PhotoDrawingShapeKind
    var size: CGSize
    var drawType = PhotoDrawingDrawType.stroke
    /// The stroke between the thinnest and the thickest, 0 to 1.
    var lineWidth: CGFloat = 0.15
    /// The bubble's tail: across as a fraction of the width, down in points below the bubble.
    var tailPosition = CGPoint(x: 0.16, y: 0)
}

// MARK: - PhotoDrawingVectorKind

/// DrawingVectorEntity.VectorType.
enum PhotoDrawingVectorKind {
    case line
    case oneSidedArrow
    case twoSidedArrow

    /// DrawingScreen's toggle for a selected arrow.
    var next: PhotoDrawingVectorKind {
        switch self {
        case .oneSidedArrow: .twoSidedArrow
        case .twoSidedArrow: .line
        case .line: .oneSidedArrow
        }
    }
}

// MARK: - PhotoDrawingVectorEntity

/// DrawingVectorEntity: a curved line through its middle point, in the painting's coordinates.
struct PhotoDrawingVectorEntity: Equatable {
    var kind = PhotoDrawingVectorKind.oneSidedArrow
    var start: CGPoint
    var end: CGPoint
    /// `mid`: the bend along the line and away from it, as fractions of its length.
    var midLength: CGFloat = 0.5
    var midHeight: CGFloat = 0
    var lineWidth: CGFloat = 0.3

    var midPoint: CGPoint {
        PhotoDrawingGeometry.midPoint(start: start, end: end, length: midLength, height: midHeight)
    }
}

// MARK: - PhotoDrawingEntity

/// A DrawingEntity over the painting.
struct PhotoDrawingEntity: Equatable {
    enum Content: Equatable {
        case text(PhotoDrawingTextEntity)
        case shape(PhotoDrawingShapeEntity)
        case vector(PhotoDrawingVectorEntity)
    }

    var id = UUID()
    var content: Content
    var color: PhotoDrawingColor
    /// The center in the painting; a vector keeps its points instead.
    var position = CGPoint.zero
    var rotation: CGFloat = 0

    /// `entity.center`.
    var center: CGPoint {
        if case .vector(let vector) = content {
            return CGPoint(x: (vector.start.x + vector.end.x) / 2, y: (vector.start.y + vector.end.y) / 2)
        }
        return position
    }

    /// `duplicate`: the same entity under a new identity.
    func duplicated(offset: CGPoint) -> PhotoDrawingEntity {
        var copy = self
        copy.id = UUID()
        copy.position = CGPoint(x: position.x + offset.x, y: position.y + offset.y)
        if case .vector(var vector) = content {
            vector.start = CGPoint(x: vector.start.x + offset.x, y: vector.start.y + offset.y)
            vector.end = CGPoint(x: vector.end.x + offset.x, y: vector.end.y + offset.y)
            copy.content = .vector(vector)
        }
        return copy
    }
}

// MARK: - PhotoDrawing

/// TGPhotoDrawingController's result kept with the edit (PGPhotoEditorValues' `paintingData`): the brush strokes as
/// an image over the whole uncropped photo fitted to `TGPhotoPaintingMaxSize`, and the entities over them in the
/// same space, so both stay editable when the editor opens again.
struct PhotoDrawing: Equatable {
    /// `TGPhotoPaintingMaxSize`.
    static let maximumSide: CGFloat = 1920

    /// The painting's size in pixels.
    let size: CGSize
    var strokes: CGImage?
    var entities = [PhotoDrawingEntity]()

    var isEmpty: Bool {
        strokes == nil && entities.isEmpty
    }

    init(size: CGSize, strokes: CGImage? = nil, entities: [PhotoDrawingEntity] = []) {
        self.size = size
        self.strokes = strokes
        self.entities = entities
    }

    /// `TGFitSize(originalSize, TGPhotoPaintingMaxSize)`.
    static func paintingSize(for originalSize: CGSize) -> CGSize {
        guard originalSize.width > 0, originalSize.height > 0 else { return CGSize(width: 1, height: 1) }
        let factor = min(1, maximumSide / max(originalSize.width, originalSize.height))
        return CGSize(
            width: max(1, (originalSize.width * factor).rounded(.down)),
            height: max(1, (originalSize.height * factor).rounded(.down)),
        )
    }

    static func == (lhs: PhotoDrawing, rhs: PhotoDrawing) -> Bool {
        lhs.size == rhs.size && lhs.strokes === rhs.strokes && lhs.entities == rhs.entities
    }

    /// A transparent BGRA context of `width` by `height` pixels in UIKit's coordinates.
    static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
        ) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        return context
    }

    /// The strokes, then the entities in order, into a context in UIKit's coordinates; `transform` takes the
    /// painting there.
    func draw(in context: CGContext, transform: CGAffineTransform) {
        context.saveGState()
        context.concatenate(transform)
        UIGraphicsPushContext(context)
        if let strokes {
            UIImage(cgImage: strokes).draw(in: CGRect(origin: .zero, size: size))
        }
        for entity in entities {
            PhotoDrawingRenderer.draw(entity, paintingSize: size, in: context)
        }
        UIGraphicsPopContext()
        context.restoreGState()
    }

    /// The painting alone over a frame of `size` pixels, as TGMediaVideoConverter lays it over every frame.
    func overlayImage(size outputSize: CGSize, transform: CGAffineTransform) -> CGImage? {
        guard let context = Self.makeContext(
            width: Int(outputSize.width.rounded()),
            height: Int(outputSize.height.rounded()),
        ) else { return nil }
        draw(in: context, transform: transform)
        return context.makeImage()
    }

    /// TGPhotoEditorController's result: the edited photo with the painting over it.
    func composited(over image: CGImage, transform: CGAffineTransform) -> CGImage? {
        guard let context = Self.makeContext(width: image.width, height: image.height) else { return nil }
        UIGraphicsPushContext(context)
        UIImage(cgImage: image).draw(in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        UIGraphicsPopContext()
        draw(in: context, transform: transform)
        return context.makeImage()
    }
}

// MARK: - PhotoCropAdjustments + Painting

extension PhotoCropAdjustments {
    /// TGPhotoEditorVideoExtCrop's painting transform: the painting over the whole photo, straightened, cut to the
    /// crop, turned and scaled into an output of `outputSize` as `render` draws the photo, without the mirroring.
    func paintingTransform(paintingSize: CGSize, outputSize: CGSize) -> CGAffineTransform {
        let crop = cropRect.standardized
        let turned = orientation.isSideward ? CGSize(width: crop.height, height: crop.width) : crop.size
        guard paintingSize.width > 0, turned.width > 0, originalSize.width > 0 else { return .identity }
        let scale = outputSize.width / turned.width
        let paintingScale = originalSize.width / paintingSize.width
        let content = rotatedContentSize
        return CGAffineTransform(scaleX: paintingScale, y: paintingScale)
            .concatenating(CGAffineTransform(translationX: -originalSize.width / 2, y: -originalSize.height / 2))
            .concatenating(CGAffineTransform(rotationAngle: rotation))
            .concatenating(CGAffineTransform(
                translationX: content.width / 2 - crop.midX,
                y: content.height / 2 - crop.midY,
            ))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(rotationAngle: orientation.angle))
            .concatenating(CGAffineTransform(translationX: outputSize.width / 2, y: outputSize.height / 2))
    }
}

// MARK: - PhotoDrawingRenderer

/// The entity views' drawing for the result: DrawingSimpleShapeEntityView's, DrawingBubbleEntityView's and
/// DrawingVectorEntityView's shape layers, and DrawingTextEntityView's text.
enum PhotoDrawingRenderer {
    static func draw(_ entity: PhotoDrawingEntity, paintingSize: CGSize, in context: CGContext) {
        switch entity.content {
        case .shape(let shape):
            context.saveGState()
            context.translateBy(x: entity.position.x, y: entity.position.y)
            context.rotate(by: entity.rotation)
            context.translateBy(x: -shape.size.width / 2, y: -shape.size.height / 2)
            context.addPath(PhotoDrawingGeometry.shapePath(shape, paintingSize: paintingSize))
            switch shape.drawType {
            case .fill:
                context.setFillColor(entity.color.cgColor)
                context.fillPath()
            case .stroke:
                context.setStrokeColor(entity.color.cgColor)
                context.setLineWidth(PhotoDrawingGeometry.shapeLineWidth(shape.lineWidth, paintingSize: paintingSize))
                context.strokePath()
            }
            context.restoreGState()
        case .vector(let vector):
            context.saveGState()
            context.addPath(PhotoDrawingGeometry.vectorPath(vector, paintingSize: paintingSize))
            context.setFillColor(entity.color.cgColor)
            context.fillPath()
            context.restoreGState()
        case .text(let text):
            guard !text.string.isEmpty else { return }
            let size = PhotoDrawingTextLayout.size(of: text, paintingSize: paintingSize)
            context.saveGState()
            context.translateBy(x: entity.position.x, y: entity.position.y)
            context.rotate(by: entity.rotation)
            context.scaleBy(x: text.scale, y: text.scale)
            context.translateBy(x: -size.width / 2, y: -size.height / 2)
            PhotoDrawingTextLayout.draw(text, color: entity.color, paintingSize: paintingSize, size: size, in: context)
            context.restoreGState()
        }
    }
}

// MARK: - PhotoDrawingTextLayout

/// DrawingTextEntityView's text: the font, colors and size, and its drawing with DrawingTextLayoutManager.
enum PhotoDrawingTextLayout {
    /// The text's TextKit objects, kept together while they lay the text out.
    struct Stack {
        let storage: NSTextStorage
        let layoutManager: PhotoDrawingTextLayoutManager
        let container: NSTextContainer
    }

    struct Colors {
        let text: UIColor
        let frame: UIColor?
        let stroke: UIColor?
    }

    /// UITextView's default `textContainerInset` above and below the text.
    static let verticalInset: CGFloat = 8

    /// `displayFontSize`.
    static func fontSize(_ text: PhotoDrawingTextEntity, paintingSize: CGSize) -> CGFloat {
        let side = max(paintingSize.width, paintingSize.height)
        let minimum = max(10, side * 0.025)
        let maximum = max(10, side * 0.25)
        return minimum + (maximum - minimum) * text.fontSize
    }

    /// `update`: the text's own color, and the frame or outline the style adds.
    static func colors(style: PhotoDrawingTextStyle, color: PhotoDrawingColor) -> Colors {
        let base = color.uiColor
        switch style {
        case .regular:
            return Colors(text: base, frame: nil, stroke: nil)
        case .filled:
            return Colors(text: color.lightness > 0.99 ? .black : .white, frame: base, stroke: nil)
        case .semi:
            let frame = color.lightness > 0.7 ? UIColor(white: 0, alpha: 0.75) : UIColor(white: 1, alpha: 0.75)
            return Colors(text: base, frame: frame, stroke: nil)
        case .stroke:
            return Colors(text: color.lightness > 0.99 ? .black : .white, frame: nil, stroke: base)
        }
    }

    static func attributes(
        _ text: PhotoDrawingTextEntity,
        color: PhotoDrawingColor,
        paintingSize: CGSize,
    ) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = text.alignment.textAlignment
        return [
            .font: text.font.font(size: fontSize(text, paintingSize: paintingSize)),
            .foregroundColor: colors(style: text.style, color: color).text,
            .paragraphStyle: paragraphStyle,
        ]
    }

    /// The layout manager's settings for the style: the outline, the line frames and the line padding.
    static func configure(
        _ layoutManager: PhotoDrawingTextLayoutManager,
        container: NSTextContainer,
        text: PhotoDrawingTextEntity,
        color: PhotoDrawingColor,
        paintingSize: CGSize,
    ) {
        let styleColors = Self.colors(style: text.style, color: color)
        layoutManager.strokeColor = styleColors.stroke
        layoutManager.frameColor = styleColors.frame
        layoutManager.textAlignment = text.alignment.textAlignment
        container.lineFragmentPadding = floor(fontSize(text, paintingSize: paintingSize) * 0.24)
    }

    static func makeStack(
        _ text: PhotoDrawingTextEntity,
        color: PhotoDrawingColor,
        paintingSize: CGSize,
        width: CGFloat,
    ) -> Stack {
        let attributed = NSAttributedString(
            string: text.string,
            attributes: attributes(text, color: color, paintingSize: paintingSize),
        )
        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = PhotoDrawingTextLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        configure(layoutManager, container: container, text: text, color: color, paintingSize: paintingSize)
        layoutManager.ensureLayout(for: container)
        return Stack(storage: storage, layoutManager: layoutManager, container: container)
    }

    /// `sizeThatFits`: the text's width with 20 points more and at least 224, and its height with the insets.
    static func size(of text: PhotoDrawingTextEntity, paintingSize: CGSize) -> CGSize {
        let stack = makeStack(text, color: .white, paintingSize: paintingSize, width: max(1, text.width))
        let used = stack.layoutManager.usedRect(for: stack.container)
        return CGSize(
            width: max(224, ceil(used.width) + 20),
            height: ceil(used.height + verticalInset * 2),
        )
    }

    /// The text laid out in a view of `size`, its regular style with the text view's shadow, drawn at the origin.
    static func draw(
        _ text: PhotoDrawingTextEntity,
        color: PhotoDrawingColor,
        paintingSize: CGSize,
        size: CGSize,
        in context: CGContext,
    ) {
        let stack = makeStack(text, color: color, paintingSize: paintingSize, width: size.width)
        let range = stack.layoutManager.glyphRange(for: stack.container)
        let origin = CGPoint(x: 0, y: verticalInset)
        context.saveGState()
        if text.style == .regular {
            // The text view's layer shadow (black at 0.4, 4 points down, radius 4) in the context's device space.
            let transform = context.ctm
            let start = CGPoint.zero.applying(transform)
            let end = CGPoint(x: 0, y: 4).applying(transform)
            let scale = sqrt(abs(transform.a * transform.d - transform.b * transform.c))
            context.setShadow(
                offset: CGSize(width: end.x - start.x, height: end.y - start.y),
                blur: 8 * scale,
                color: UIColor(white: 0, alpha: 0.4).cgColor,
            )
        }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        stack.layoutManager.drawBackground(forGlyphRange: range, at: origin)
        stack.layoutManager.drawGlyphs(forGlyphRange: range, at: origin)
        context.endTransparencyLayer()
        context.restoreGState()
    }
}

// MARK: - PhotoDrawingTextLayoutManager

/// DrawingTextLayoutManager: the outlined style's stroke around the glyphs, and the framed styles' rounded box
/// behind every line, joined where the lines meet.
final class PhotoDrawingTextLayoutManager: NSLayoutManager {
    var strokeColor: UIColor?
    var frameColor: UIColor?
    var textAlignment = NSTextAlignment.natural

    private var rectArray = [CGRect]()
    private var maxIndex = 0
    private var radius: CGFloat = 8

    override func showCGGlyphs(
        _ glyphs: UnsafePointer<CGGlyph>,
        positions: UnsafePointer<CGPoint>,
        count glyphCount: Int,
        font: UIFont,
        textMatrix: CGAffineTransform,
        attributes: [NSAttributedString.Key: Any] = [:],
        in graphicsContext: CGContext,
    ) {
        if let strokeColor {
            graphicsContext.setStrokeColor(strokeColor.cgColor)
            graphicsContext.setLineJoin(.round)
            graphicsContext.setLineWidth(font.pointSize / 9)
            graphicsContext.setTextDrawingMode(.stroke)
            super.showCGGlyphs(
                glyphs,
                positions: positions,
                count: glyphCount,
                font: font,
                textMatrix: textMatrix,
                attributes: attributes,
                in: graphicsContext,
            )
            let textColor = attributes[.foregroundColor] as? UIColor ?? .white
            graphicsContext.setFillColor(textColor.cgColor)
            graphicsContext.setTextDrawingMode(.fill)
        }
        super.showCGGlyphs(
            glyphs,
            positions: positions,
            count: glyphCount,
            font: font,
            textMatrix: textMatrix,
            attributes: attributes,
            in: graphicsContext,
        )
    }

    override func drawBackground(forGlyphRange _: NSRange, at origin: CGPoint) {
        guard let frameColor, let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.setBlendMode(.copy)
        context.setFillColor(frameColor.cgColor)
        context.setStrokeColor(frameColor.cgColor)
        prepare()
        let path = framePath()
        path.fill()
        path.stroke()
        context.restoreGState()
    }

    /// `prepare`: the used rectangle of every line with text, narrowed by a trailing space.
    private func prepare() {
        rectArray.removeAll()
        let string = (textStorage?.string ?? "") as NSString
        enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: string.length)) { _, usedRect, _, range, _ in
            let characterRange = self.characterRange(forGlyphRange: range, actualGlyphRange: nil)
            let substring = string.substring(with: characterRange)
            guard !substring.trimmingCharacters(in: .newlines).isEmpty else { return }
            var rect = usedRect
            if substring.hasSuffix(" "), self.textAlignment != .right {
                rect.size.width -= floor(rect.height * 0.145)
            }
            self.rectArray.append(rect)
        }
        preprocess()
    }

    private func preprocess() {
        maxIndex = 0
        guard rectArray.count >= 2 else { return }
        for index in 1..<rectArray.count {
            maxIndex = index
            processRectIndex(index)
        }
    }

    /// `processRectIndex`: neighbouring lines whose edges nearly meet take the wider edge.
    private func processRectIndex(_ index: Int) {
        guard rectArray.count >= 2, index > 0, index <= maxIndex else { return }
        var last = rectArray[index - 1]
        var current = rectArray[index]
        radius = current.height * 0.2
        let doubleRadius = radius * 2.5
        let lastNarrower = (last.minX - current.minX < doubleRadius && last.minX > current.minX)
            || (last.maxX - current.maxX > -doubleRadius && last.maxX < current.maxX)
        if lastNarrower {
            rectArray[index - 1] = CGRect(x: current.minX, y: last.minY, width: current.width, height: last.height)
            processRectIndex(index - 1)
        }
        last = rectArray[index - 1]
        current = rectArray[index]
        let currentNarrower = (current.minX - last.minX < doubleRadius && current.minX > last.minX)
            || (current.maxX - last.maxX > -doubleRadius && current.maxX < last.maxX)
        if currentNarrower {
            rectArray[index] = CGRect(x: last.minX, y: current.minY, width: last.width, height: current.height)
            processRectIndex(index + 1)
        }
    }

    /// `drawBackground`'s path: a rounded box per line with concave corners where a line meets a wider one.
    private func framePath() -> UIBezierPath {
        let path = UIBezierPath()
        var last = CGRect.null
        for (index, current) in rectArray.enumerated() {
            radius = current.height * 0.2
            path.append(UIBezierPath(roundedRect: current, cornerRadius: radius))
            guard index > 0, abs(last.maxY - current.minY) < 15 else {
                last = current
                continue
            }
            appendJoins(to: path, current: current, last: last)
            last = current
        }
        return path
    }

    private func appendJoins(to path: UIBezierPath, current: CGRect, last: CGRect) {
        let a = current.origin
        let b = CGPoint(x: current.maxX, y: current.minY)
        let c = CGPoint(x: last.minX, y: last.maxY)
        let d = CGPoint(x: last.maxX, y: last.maxY)
        if a.x - c.x >= 2 * radius {
            let join = UIBezierPath(
                arcCenter: CGPoint(x: a.x - radius, y: a.y + radius),
                radius: radius,
                startAngle: .pi * 1.5,
                endAngle: 0,
                clockwise: true,
            )
            join.append(UIBezierPath(
                arcCenter: CGPoint(x: a.x + radius, y: a.y + radius),
                radius: radius,
                startAngle: .pi,
                endAngle: .pi * 1.5,
                clockwise: true,
            ))
            join.addLine(to: CGPoint(x: a.x - radius, y: a.y))
            path.append(join)
        }
        if a.x == c.x {
            path.move(to: CGPoint(x: a.x, y: a.y - radius))
            path.addLine(to: CGPoint(x: a.x, y: a.y + radius))
            path.addArc(
                withCenter: CGPoint(x: a.x + radius, y: a.y + radius),
                radius: radius,
                startAngle: .pi,
                endAngle: .pi * 1.5,
                clockwise: true,
            )
            path.addArc(
                withCenter: CGPoint(x: a.x + radius, y: a.y - radius),
                radius: radius,
                startAngle: .pi * 0.5,
                endAngle: .pi,
                clockwise: true,
            )
        }
        if d.x - b.x >= 2 * radius {
            let join = UIBezierPath(
                arcCenter: CGPoint(x: b.x + radius, y: b.y + radius),
                radius: radius,
                startAngle: .pi * 1.5,
                endAngle: .pi,
                clockwise: false,
            )
            join.append(UIBezierPath(
                arcCenter: CGPoint(x: b.x - radius, y: b.y + radius),
                radius: radius,
                startAngle: 0,
                endAngle: .pi * 1.5,
                clockwise: false,
            ))
            join.addLine(to: CGPoint(x: b.x + radius, y: b.y))
            path.append(join)
        }
        if d.x == b.x {
            path.move(to: CGPoint(x: b.x, y: b.y - radius))
            path.addLine(to: CGPoint(x: b.x, y: b.y + radius))
            path.addArc(
                withCenter: CGPoint(x: b.x - radius, y: b.y + radius),
                radius: radius,
                startAngle: 0,
                endAngle: .pi * 1.5,
                clockwise: false,
            )
            path.addArc(
                withCenter: CGPoint(x: b.x - radius, y: b.y - radius),
                radius: radius,
                startAngle: .pi * 0.5,
                endAngle: 0,
                clockwise: false,
            )
        }
        if c.x - a.x >= 2 * radius {
            let join = UIBezierPath(
                arcCenter: CGPoint(x: c.x - radius, y: c.y - radius),
                radius: radius,
                startAngle: .pi * 0.5,
                endAngle: 0,
                clockwise: false,
            )
            join.append(UIBezierPath(
                arcCenter: CGPoint(x: c.x + radius, y: c.y - radius),
                radius: radius,
                startAngle: .pi,
                endAngle: .pi * 0.5,
                clockwise: false,
            ))
            join.addLine(to: CGPoint(x: c.x - radius, y: c.y))
            path.append(join)
        }
        if b.x - d.x >= 2 * radius {
            let join = UIBezierPath(
                arcCenter: CGPoint(x: d.x + radius, y: d.y - radius),
                radius: radius,
                startAngle: .pi * 0.5,
                endAngle: .pi,
                clockwise: true,
            )
            join.append(UIBezierPath(
                arcCenter: CGPoint(x: d.x - radius, y: d.y - radius),
                radius: radius,
                startAngle: 0,
                endAngle: .pi * 0.5,
                clockwise: true,
            ))
            join.addLine(to: CGPoint(x: d.x + radius, y: d.y))
            path.append(join)
        }
    }
}

// MARK: - PhotoDrawingGeometry

/// DrawingUtils' paths and the entity views' sizes, all relative to the painting's longer side.
enum PhotoDrawingGeometry {
    static func longerSide(_ size: CGSize) -> CGFloat {
        max(size.width, size.height)
    }

    /// DrawingSimpleShapeEntityView's `maxLineWidth`, which also insets its path.
    static func shapeMaximumLineWidth(paintingSize: CGSize) -> CGFloat {
        max(10, longerSide(paintingSize) * 0.05)
    }

    /// The shapes' and the vector's stroke between `max(10, side * 0.01)` and `max(10, side * 0.05)`.
    static func shapeLineWidth(_ value: CGFloat, paintingSize: CGSize) -> CGFloat {
        let minimum = max(10, longerSide(paintingSize) * 0.01)
        let maximum = shapeMaximumLineWidth(paintingSize: paintingSize)
        return minimum + (maximum - minimum) * value
    }

    /// `minimumSize`: a fifth of the painting's shorter side.
    static func shapeMinimumSide(paintingSize: CGSize) -> CGFloat {
        min(paintingSize.width, paintingSize.height) * 0.2
    }

    /// The shape in its own bounds of `shape.size`; a bubble's tail reaches below them.
    static func shapePath(_ shape: PhotoDrawingShapeEntity, paintingSize: CGSize) -> CGPath {
        let bounds = CGRect(origin: .zero, size: shape.size)
        let side = longerSide(paintingSize)
        if shape.kind == .bubble {
            return bubble(
                in: bounds,
                cornerRadius: max(10, side * 0.045),
                smallCornerRadius: max(5, side * 0.01),
                tailPosition: shape.tailPosition,
                tailWidth: max(5, side * 0.1),
            )
        }
        let inset = shapeMaximumLineWidth(paintingSize: paintingSize) * 0.5
        let rect = bounds.insetBy(dx: inset, dy: inset)
        switch shape.kind {
        case .bubble,
             .rectangle:
            return CGPath(rect: rect, transform: nil)
        case .ellipse:
            return CGPath(ellipseIn: rect, transform: nil)
        case .star:
            return star(in: rect, extrusion: shape.size.width * 0.2, points: 5)
        }
    }

    /// DrawingVectorEntityView's path.
    static func vectorPath(_ vector: PhotoDrawingVectorEntity, paintingSize: CGSize) -> CGPath {
        let lineWidth = shapeLineWidth(vector.lineWidth, paintingSize: paintingSize)
        return curve(
            start: vector.start,
            end: vector.end,
            mid: vector.midPoint,
            lineWidth: lineWidth,
            arrowSize: vector.kind == .line ? nil : CGSize(width: lineWidth * 1.5, height: lineWidth * 3),
            twoSided: vector.kind == .twoSidedArrow,
        )
    }

    /// `midPointPositionFor`.
    static func midPoint(start: CGPoint, end: CGPoint, length: CGFloat, height: CGFloat) -> CGPoint {
        let distance = end.distance(to: start)
        let angle = start.angle(to: end)
        let along = start.point(atDistance: distance * length, angle: angle)
        return along.point(atDistance: distance * height, angle: angle + .pi * 0.5)
    }

    /// `CGPath.star`.
    static func star(in rect: CGRect, extrusion: CGFloat, points: Int = 5) -> CGPath {
        let path = CGMutablePath()
        let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.05)
        var angle = -CGFloat.pi / 2
        let increment = CGFloat.pi * 2 / CGFloat(points)
        let radius = rect.width / 2
        for index in 0..<points {
            let point = center.point(atDistance: radius, angle: angle)
            let nextPoint = center.point(atDistance: radius, angle: angle + increment)
            let midPoint = center.point(atDistance: extrusion, angle: angle + increment * 0.5)
            if index == 0 {
                path.move(to: point)
            }
            path.addLine(to: midPoint)
            path.addLine(to: nextPoint)
            angle += increment
        }
        path.closeSubpath()
        return path
    }

    /// `CGPath.arrow`.
    static func arrow(from point: CGPoint, controlPoint: CGPoint, width: CGFloat, height: CGFloat) -> CGPath {
        let angle = atan2(point.y - controlPoint.y, point.x - controlPoint.x)
        let adjustment = atan2(width, -height)
        let distance = hypot(width, height)
        let path = CGMutablePath()
        path.move(to: point)
        path.addLine(to: point.point(atDistance: distance, angle: angle - adjustment))
        path.addLine(to: point.point(atDistance: distance, angle: angle + adjustment))
        path.closeSubpath()
        return path
    }

    /// `CGPath.curve`: the line through `mid` stroked to `lineWidth`, shortened under its arrowheads.
    static func curve(
        start: CGPoint,
        end: CGPoint,
        mid: CGPoint,
        lineWidth: CGFloat,
        arrowSize: CGSize?,
        twoSided: Bool,
    ) -> CGPath {
        let controls = controlPoints(start, mid, end)
        let linePath = CGMutablePath()
        var lineStart = start
        if let arrowSize, twoSided {
            lineStart = start.point(atDistance: -arrowSize.height * 0.5, angle: controls.0.first.angle(to: start))
        }
        linePath.move(to: lineStart)
        linePath.addCurve(to: mid, control1: controls.0.first, control2: controls.0.second)
        var lineEnd = end
        if let arrowSize {
            lineEnd = end.point(atDistance: -arrowSize.height * 0.5, angle: controls.1.first.angle(to: end))
        }
        linePath.addCurve(to: lineEnd, control1: controls.1.first, control2: controls.1.second)
        let stroked = linePath.copy(strokingWithWidth: lineWidth, lineCap: .square, lineJoin: .round, miterLimit: 0)
        let path = stroked.mutableCopy() ?? CGMutablePath()
        if let arrowSize {
            path.addPath(arrow(
                from: end,
                controlPoint: controls.1.first,
                width: arrowSize.width,
                height: arrowSize.height,
            ))
            if twoSided {
                path.addPath(arrow(
                    from: start,
                    controlPoint: controls.0.first,
                    width: arrowSize.width,
                    height: arrowSize.height,
                ))
            }
        }
        return path
    }

    /// `configureControlPoints` for three points: the smooth cubic curve's control points for both segments.
    static func controlPoints(
        _ start: CGPoint,
        _ mid: CGPoint,
        _ end: CGPoint,
    ) -> ((first: CGPoint, second: CGPoint), (first: CGPoint, second: CGPoint)) {
        let second = CGPoint(x: (6 * mid.x + end.x - start.x) / 6, y: (6 * mid.y + end.y - start.y) / 6)
        let first = CGPoint(x: (start.x + 2 * mid.x) / 2 - second.x / 2, y: (start.y + 2 * mid.y) / 2 - second.y / 2)
        return (
            (first, CGPoint(x: 2 * mid.x - second.x, y: 2 * mid.y - second.y)),
            (second, CGPoint(x: (end.x + second.x) / 2, y: (end.y + second.y) / 2)),
        )
    }

    /// `CGPath.bubble`.
    static func bubble(
        in rect: CGRect,
        cornerRadius: CGFloat,
        smallCornerRadius: CGFloat,
        tailPosition: CGPoint,
        tailWidth: CGFloat,
    ) -> CGPath {
        let r1 = min(cornerRadius, min(rect.width, rect.height) / 3)
        let r2 = min(smallCornerRadius, min(rect.width, rect.height) / 10)
        let ax = tailPosition.x * rect.width
        let ay = tailPosition.y
        let width = min(max(tailWidth, ay / 2), rect.width / 4)
        let angle = atan2(ay, width)
        let h = r2 / tan(angle / 2)
        let r1a = min(r1, min(rect.maxX - ax, ax - rect.minX) * 0.5)
        let r2a = min(r2, min(rect.maxX - ax, ax - rect.minX) * 0.2)
        let path = CGMutablePath()
        path.addArc(
            center: CGPoint(x: rect.minX + r1, y: rect.minY + r1),
            radius: r1,
            startAngle: .pi,
            endAngle: .pi * 3 / 2,
            clockwise: false,
        )
        path.addArc(
            center: CGPoint(x: rect.maxX - r1, y: rect.minY + r1),
            radius: r1,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: false,
        )
        if ax > rect.width / 2 {
            if ax < rect.width - 1 {
                path.addArc(
                    center: CGPoint(x: rect.maxX - r1a, y: rect.maxY - r1a),
                    radius: r1a,
                    startAngle: 0,
                    endAngle: .pi / 2,
                    clockwise: false,
                )
                path.addArc(
                    center: CGPoint(x: rect.minX + ax + r2a, y: rect.maxY + r2a),
                    radius: r2a,
                    startAngle: .pi * 3 / 2,
                    endAngle: .pi,
                    clockwise: true,
                )
            }
            path.addLine(to: CGPoint(x: rect.minX + ax, y: rect.maxY + ay))
            path.addArc(
                center: CGPoint(x: rect.minX + ax - width - r2, y: rect.maxY + h),
                radius: h,
                startAngle: -(.pi / 2 - angle),
                endAngle: .pi * 3 / 2,
                clockwise: true,
            )
            path.addArc(
                center: CGPoint(x: rect.minX + r1, y: rect.maxY - r1),
                radius: r1,
                startAngle: .pi / 2,
                endAngle: .pi,
                clockwise: false,
            )
        } else {
            path.addArc(
                center: CGPoint(x: rect.maxX - r1, y: rect.maxY - r1),
                radius: r1,
                startAngle: 0,
                endAngle: .pi / 2,
                clockwise: false,
            )
            path.addArc(
                center: CGPoint(x: rect.minX + ax + width + r2, y: rect.maxY + h),
                radius: h,
                startAngle: .pi * 3 / 2,
                endAngle: .pi * 3 / 2 - angle,
                clockwise: true,
            )
            path.addLine(to: CGPoint(x: rect.minX + ax, y: rect.maxY + ay))
            if ax > 1 {
                path.addArc(
                    center: CGPoint(x: rect.minX + ax - r2a, y: rect.maxY + r2a),
                    radius: r2a,
                    startAngle: 0,
                    endAngle: .pi * 3 / 2,
                    clockwise: true,
                )
                path.addArc(
                    center: CGPoint(x: rect.minX + r1a, y: rect.maxY - r1a),
                    radius: r1a,
                    startAngle: .pi / 2,
                    endAngle: .pi,
                    clockwise: false,
                )
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - CGPoint + Drawing

/// DrawingUtils' point helpers.
extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        hypot(point.x - x, point.y - y)
    }

    func angle(to point: CGPoint) -> CGFloat {
        atan2(point.y - y, point.x - x)
    }

    func point(atDistance distance: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(x: distance * cos(angle) + x, y: distance * sin(angle) + y)
    }

    func point(to point: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(x: x + t * (point.x - x), y: y + t * (point.y - y))
    }

    /// `perpendicularPointOnLine`.
    func perpendicularPoint(onLineFrom start: CGPoint, to end: CGPoint) -> CGPoint {
        let lengthSquared = pow(end.x - start.x, 2) + pow(end.y - start.y, 2)
        guard lengthSquared > 0 else { return start }
        let t = ((x - start.x) * (end.x - start.x) + (y - start.y) * (end.y - start.y)) / lengthSquared
        return CGPoint(x: start.x + t * (end.x - start.x), y: start.y + t * (end.y - start.y))
    }
}
