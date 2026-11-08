// StoryDrawing.swift

import UIKit

// MARK: - StoryDrawingTool

/// DrawingToolState.Key's pen, arrow, marker, neon, blur and eraser, with DrawingState.initial's colours and sizes.
enum StoryDrawingTool: CaseIterable {
    case pen
    case arrow
    case marker
    case neon
    case blur
    case eraser

    var initialColor: UIColor? {
        switch self {
        case .pen: UIColor(red: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)
        case .arrow: UIColor(red: 0xFF / 255, green: 0x8A / 255, blue: 0, alpha: 1)
        case .marker: UIColor(red: 0xFF / 255, green: 0xD6 / 255, blue: 0x0A / 255, alpha: 1)
        case .neon: UIColor(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255, alpha: 1)
        case .blur,
             .eraser: nil
        }
    }

    var initialSize: CGFloat {
        switch self {
        case .arrow,
             .pen: 0.23
        case .marker: 0.75
        case .neon: 0.4
        case .blur,
             .eraser: 0.5
        }
    }

    /// One stroke of the tool.
    func makeStroke(color: UIColor, size: CGFloat, drawingSize: CGSize) -> StoryStroke {
        switch self {
        case .marker: StoryMarkerStroke(color: color, size: size, drawingSize: drawingSize)
        case .neon: StoryNeonStroke(color: color, size: size, drawingSize: drawingSize)
        default: StoryPenStroke(tool: self, color: color, size: size, drawingSize: drawingSize)
        }
    }
}

// MARK: - StoryStroke

/// DrawingElement: a stroke fed touch by touch, finished, and drawn in story points.
protocol StoryStroke: AnyObject {
    func add(_ location: CGPoint, velocity: CGFloat)
    func end(at location: CGPoint)
    func draw(in context: CGContext)
}

// MARK: - StoryPenStroke

/// PenTool for one stroke in story points: each touch's width falls with its speed between the size's width and a
/// fifth of the way up from the thinnest (a fixed width for the eraser), eased 30/70 with the last; points closer than
/// 8 pt are dropped and the rest smoothed through quadratic and cubic Béziers into 24 to 48 steps, each pair of steps a
/// segment with round ends. The arrow adds two strokes 0.45 rad either side of the line's end; a tap leaves a dot.
final class StoryPenStroke: StoryStroke {
    struct Point {
        let location: CGPoint
        let width: CGFloat
    }

    struct Segment {
        let a: CGPoint
        let b: CGPoint
        let c: CGPoint
        let d: CGPoint
        let abCenter: CGPoint
        let cdCenter: CGPoint
        let radius1: CGFloat
        let radius2: CGFloat
    }

    let tool: StoryDrawingTool
    let color: UIColor
    /// The blur tool's source: the story blurred, shown through the stroke.
    var blurredImage: CGImage?
    private(set) var segments = [Segment]()
    private(set) var activeSegments = [Segment]()
    private(set) var arrow: (left: CGPoint, start: CGPoint, right: CGPoint, width: CGFloat)?

    private let drawingSize: CGSize

    private let renderLineWidth: CGFloat
    private let renderMinLineWidth: CGFloat
    private let renderArrowLength: CGFloat
    private var points = [Point](repeating: Point(location: .zero, width: 0), count: 4)
    private var pointPtr = 0
    private var previousWidth: CGFloat?
    private var smoothPoints = [Point]()
    private var activeSmoothPoints = [Point]()

    var allSegments: [Segment] {
        segments + activeSegments
    }

    init(tool: StoryDrawingTool, color: UIColor, size: CGFloat, drawingSize: CGSize) {
        self.tool = tool
        self.color = color
        let longest = max(drawingSize.width, drawingSize.height)
        let minLineWidth = max(1, longest * 0.002)
        let maxLineWidth = max(10, longest * 0.07)
        let lineWidth = minLineWidth + (maxLineWidth - minLineWidth) * size
        self.renderLineWidth = lineWidth
        self.drawingSize = drawingSize
        self.renderMinLineWidth = tool == .eraser || tool == .blur
            ? lineWidth
            : minLineWidth + (lineWidth - minLineWidth) * 0.2
        self.renderArrowLength = max(max(10, longest * 0.02), lineWidth * 3)
    }

    /// smoothPoints: 24 to 48 steps 6 pt apart along the quadratic or cubic curve, the widths eased alike.
    private static func smooth(_ start: Point, control1: Point, control2: Point?, end: Point) -> [Point] {
        let count = min(48, max(floor(distance(start.location, end.location) / 6), 24))
        var result = [Point]()
        for t in stride(from: CGFloat(0), to: 1, by: 1 / count) {
            let u = 1 - t
            if let control2 {
                let location = CGPoint(
                    x: u * u * u * start.location.x + 3 * u * u * t * control1.location.x
                        + 3 * u * t * t * control2.location.x + t * t * t * end.location.x,
                    y: u * u * u * start.location.y + 3 * u * u * t * control1.location.y
                        + 3 * u * t * t * control2.location.y + t * t * t * end.location.y,
                )
                let w1 = (start.width + control1.width) / 2
                let w2 = (control2.width + end.width) / 2
                let width = u * u * u * start.width + 3 * u * u * t * w1 + 3 * u * t * t * w2 + t * t * t * end.width
                result.append(Point(location: location, width: width))
            } else {
                let location = CGPoint(
                    x: u * u * start.location.x + 2 * u * t * control1.location.x + t * t * end.location.x,
                    y: u * u * start.location.y + 2 * u * t * control1.location.y + t * t * end.location.y,
                )
                let control = (start.width + end.width) / 2
                let width = u * u * start.width + 2 * u * t * control + t * t * end.width
                result.append(Point(location: location, width: width))
            }
        }
        result.append(end)
        return result
    }

    /// segments(fromSmoothPoints:): each step's edges at half its width either side of the line.
    private static func segments(from points: [Point]) -> [Segment] {
        var result = [Segment]()
        guard points.count > 1 else { return result }
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let dx = current.location.x - previous.location.x
            let dy = current.location.y - previous.location.y
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 0.0001 else { continue }
            let perpendicular = CGPoint(x: -dy / length, y: dx / length)
            let offset: (CGPoint, CGFloat, CGFloat) -> CGPoint = { point, width, sign in
                CGPoint(
                    x: point.x + sign * perpendicular.x * width / 2,
                    y: point.y + sign * perpendicular.y * width / 2,
                )
            }
            result.append(Segment(
                a: offset(previous.location, previous.width, 1),
                b: offset(previous.location, previous.width, -1),
                c: offset(current.location, current.width, 1),
                d: offset(current.location, current.width, -1),
                abCenter: previous.location,
                cdCenter: current.location,
                radius1: previous.width / 2,
                radius2: current.width / 2,
            ))
        }
        return result
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    private static func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    /// pathForSegment: the step's quadrilateral with round ends.
    private static func path(of segment: Segment) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [segment.a, segment.c, segment.d, segment.b])
        path.closeSubpath()
        path.addEllipse(in: CGRect(
            x: segment.abCenter.x - segment.radius1,
            y: segment.abCenter.y - segment.radius1,
            width: segment.radius1 * 2,
            height: segment.radius1 * 2,
        ))
        path.addEllipse(in: CGRect(
            x: segment.cdCenter.x - segment.radius2,
            y: segment.cdCenter.y - segment.radius2,
            width: segment.radius2 * 2,
            height: segment.radius2 * 2,
        ))
        return path
    }

    func add(_ location: CGPoint, velocity: CGFloat) {
        let velocity = velocity == 0 ? 1000 : velocity
        var width = max(renderMinLineWidth, min(renderLineWidth - velocity / 200, renderLineWidth))
        if let previousWidth { width = width * 0.3 + previousWidth * 0.7 }
        previousWidth = width
        if pointPtr == 0 {
            points[0] = Point(location: location, width: width)
            pointPtr = 1
        } else {
            guard Self.distance(points[pointPtr - 1].location, location) > 8 else { return }
            if pointPtr >= 4 {
                points[3] = Point(location: Self.mid(points[2].location, location), width: points[2].width)
                if var smooth = currentSmoothPoints(3) {
                    if let last = smoothPoints.last { smooth.insert(last, at: 0) }
                    segments += Self.segments(from: smooth)
                    smoothPoints += smooth
                    activeSmoothPoints = []
                    activeSegments = []
                }
                points[0] = points[3]
                pointPtr = 1
            }
            points[pointPtr] = Point(location: location, width: width)
            pointPtr += 1
        }
        guard let smooth = currentSmoothPoints(pointPtr - 1) else { return }
        activeSmoothPoints = smooth
        activeSegments = Self.segments(from: smooth)
    }

    func end(at location: CGPoint) {
        segments += activeSegments
        smoothPoints += activeSmoothPoints
        activeSegments = []
        activeSmoothPoints = []
        if tool == .arrow {
            guard smoothPoints.count > 4, let end = smoothPoints.last else { return }
            var direction: CGFloat?
            for index in 1..<min(smoothPoints.count - 2, 200) {
                let point = smoothPoints[smoothPoints.count - 1 - index].location
                if Self.distance(point, end.location) > renderArrowLength * 0.5 {
                    direction = atan2(point.y - end.location.y, point.x - end.location.x)
                    break
                }
            }
            guard let direction else { return }
            let at: (CGFloat) -> CGPoint = { angle in
                CGPoint(
                    x: end.location.x + self.renderArrowLength * cos(angle),
                    y: end.location.y + self.renderArrowLength * sin(angle),
                )
            }
            arrow = (at(direction - 0.45), end.location, at(direction + 0.45), end.width)
        } else if segments.isEmpty {
            let radius = renderLineWidth / 2
            let a = CGPoint(x: location.x - radius, y: location.y)
            let b = CGPoint(x: location.x + radius, y: location.y)
            segments.append(Segment(
                a: a,
                b: b,
                c: CGPoint(x: a.x, y: a.y + 0.1),
                d: CGPoint(x: b.x, y: b.y + 0.1),
                abCenter: location,
                cdCenter: CGPoint(x: location.x, y: location.y + 0.1),
                radius1: radius,
                radius2: radius,
            ))
        }
    }

    /// draw(in:): the eraser clears, the blur shows the blurred story through the stroke, the rest fill in the colour
    /// at full opacity.
    func draw(in context: CGContext) {
        if tool == .blur {
            drawBlur(in: context)
            return
        }
        context.saveGState()
        context.setBlendMode(tool == .eraser ? .clear : .normal)
        context.setFillColor(color.withAlphaComponent(1).cgColor)
        for segment in allSegments {
            let path = CGMutablePath()
            path.addLines(between: [segment.a, segment.c, segment.d, segment.b])
            path.closeSubpath()
            path.addEllipse(in: CGRect(
                x: segment.abCenter.x - segment.radius1,
                y: segment.abCenter.y - segment.radius1,
                width: segment.radius1 * 2,
                height: segment.radius1 * 2,
            ))
            path.addEllipse(in: CGRect(
                x: segment.cdCenter.x - segment.radius2,
                y: segment.cdCenter.y - segment.radius2,
                width: segment.radius2 * 2,
                height: segment.radius2 * 2,
            ))
            context.addPath(path)
            context.fillPath(using: .winding)
        }
        if let arrow {
            context.setStrokeColor(color.withAlphaComponent(1).cgColor)
            context.setLineWidth(arrow.width)
            context.setLineCap(.round)
            context.strokeLineSegments(between: [arrow.start, arrow.left, arrow.start, arrow.right])
        }
        context.restoreGState()
    }

    /// PenTool's blur: the segments as a mask at half the resolution, and the blurred story drawn through it.
    private func drawBlur(in context: CGContext) {
        guard let blurredImage else { return }
        let width = Int(drawingSize.width / 2)
        let height = Int(drawingSize.height / 2)
        guard width > 0, height > 0, let mask = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue,
        ) else { return }
        mask.setFillColor(gray: 0, alpha: 1)
        mask.fill(CGRect(x: 0, y: 0, width: width, height: height))
        mask.translateBy(x: 0, y: CGFloat(height))
        mask.scaleBy(x: 0.5, y: -0.5)
        mask.setFillColor(gray: 1, alpha: 1)
        for segment in allSegments {
            mask.addPath(Self.path(of: segment))
            mask.fillPath(using: .winding)
        }
        guard let maskImage = mask.makeImage() else { return }
        let bounds = CGRect(origin: .zero, size: drawingSize)
        context.saveGState()
        context.translateBy(x: 0, y: drawingSize.height)
        context.scaleBy(x: 1, y: -1)
        context.clip(to: bounds, mask: maskImage)
        context.draw(blurredImage, in: bounds)
        context.restoreGState()
    }

    private func currentSmoothPoints(_ count: Int) -> [Point]? {
        switch count {
        case 2: Self.smooth(points[0], control1: points[1], control2: nil, end: points[2])
        case 3: Self.smooth(points[0], control1: points[1], control2: points[2], end: points[3])
        default: nil
        }
    }
}

// MARK: - StoryDrawingView

/// DrawingView over the story in story points: a finger draws with the chosen tool while drawing is on, the strokes
/// kept so the last can be undone and all cleared. It draws at one pixel a story point, the story's own resolution.
final class StoryDrawingView: UIView {
    var tool = StoryDrawingTool.pen {
        didSet {
            guard tool != oldValue else { return }
            preparedBlurredImage = tool == .blur ? makeBlurredImage() : nil
        }
    }

    /// The story under the drawing, which the blur tool blurs.
    var storyImage: (() -> CGImage?)?
    var color = StoryDrawingTool.pen.initialColor ?? .white
    var size = StoryDrawingTool.pen.initialSize
    var onStrokesChange: (() -> Void)?

    private(set) var strokes = [StoryStroke]()

    private var committed: CGImage?
    private var active: StoryStroke?
    /// brushSizePreviewLayer: a white circle as wide as the brush, in the middle while its size changes.
    private let brushPreview = CAShapeLayer()
    private var preparedBlurredImage: CGImage?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        layer.contentsScale = 1
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        addGestureRecognizer(tap)
        brushPreview.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        brushPreview.path = CGPath(ellipseIn: brushPreview.bounds, transform: nil)
        brushPreview.strokeColor = UIColor(red: 0x91 / 255, green: 0x91 / 255, blue: 0x91 / 255, alpha: 1).cgColor
        brushPreview.fillColor = UIColor.white.cgColor
        brushPreview.opacity = 0
        brushPreview.shadowColor = UIColor.black.cgColor
        brushPreview.shadowOpacity = 0.5
        brushPreview.shadowOffset = CGSize(width: 0, height: 3)
        brushPreview.shadowRadius = 20
        layer.addSublayer(brushPreview)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        brushPreview.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // UIKit gives a view the screen's scale in a window; the story needs one pixel a point.
        layer.contentsScale = 1
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        if let committed {
            context.saveGState()
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(committed, in: bounds)
            context.restoreGState()
        }
        active?.draw(in: context)
    }

    /// setBrushSizePreview: the circle at the size's width, between 0.2% and 7% of the longer side, or gone.
    func setBrushSizePreview(_ size: CGFloat?) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        if let size {
            let longest = max(bounds.width, bounds.height)
            let minimum = max(1, longest * 0.002)
            let maximum = max(10, longest * 0.07)
            let width = minimum + (maximum - minimum) * size
            brushPreview.transform = CATransform3DMakeScale(width / 100, width / 100, 1)
            brushPreview.opacity = 1
        } else {
            brushPreview.opacity = 0
        }
        CATransaction.commit()
    }

    func undo() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
        rebuild()
    }

    func clear() {
        strokes = []
        rebuild()
    }

    /// Back to the first `count` strokes, as Cancel leaves the drawing as it was.
    func restore(strokeCount count: Int) {
        guard count < strokes.count else { return }
        strokes = Array(strokes.prefix(count))
        rebuild()
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)
        let velocity = gesture.velocity(in: self)
        let speed = (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()
        switch gesture.state {
        case .began:
            let stroke = makeStroke()
            stroke.add(location, velocity: speed)
            active = stroke
        case .changed:
            active?.add(location, velocity: speed)
        case .cancelled,
             .ended:
            active?.add(location, velocity: speed)
            finish(at: location)
        default:
            break
        }
        setNeedsDisplay()
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        let stroke = makeStroke()
        stroke.add(location, velocity: 0)
        active = stroke
        finish(at: location)
        setNeedsDisplay()
    }

    private func finish(at location: CGPoint) {
        guard let stroke = active else { return }
        active = nil
        stroke.end(at: location)
        strokes.append(stroke)
        committed = render(strokes: [stroke], over: committed)
        onStrokesChange?()
    }

    private func makeStroke() -> StoryStroke {
        let stroke = tool.makeStroke(color: color, size: size, drawingSize: bounds.size)
        (stroke as? StoryPenStroke)?.blurredImage = preparedBlurredImage
        return stroke
    }

    /// getFullImage: the story and the drawing fitted into 256 pt and blurred twice with a radius of 7, roughly a
    /// Gaussian of 6 there.
    private func makeBlurredImage() -> CGImage? {
        guard let story = storyImage?() else { return nil }
        let scale = min(256 / bounds.width, 256 / bounds.height)
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: story).draw(in: CGRect(origin: .zero, size: size))
            if let committed { UIImage(cgImage: committed).draw(in: CGRect(origin: .zero, size: size)) }
        }
        guard let input = CIImage(image: small) else { return nil }
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: 6).cropped(to: input.extent)
        return CIContext().createCGImage(blurred, from: input.extent)
    }

    private func rebuild() {
        committed = strokes.isEmpty ? nil : render(strokes: strokes, over: nil)
        setNeedsDisplay()
        onStrokesChange?()
    }

    private func render(strokes: [StoryStroke], over image: CGImage?) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: bounds.size, format: format)
            .image { context in
                if let image {
                    UIImage(cgImage: image).draw(in: bounds)
                }
                for stroke in strokes {
                    stroke.draw(in: context.cgContext)
                }
            }
            .cgImage
    }
}

// MARK: - StoryDrawingToolsView

/// ToolsComponent: the tools 44 pt apart around the middle, each ToolView's 40 by 176 pt picture at half size, the
/// chosen one 12 pt higher; a tool's tip and band take its colour and the band its size. A tap chooses a tool, and a
/// drag up or down on the chosen one changes its size.
final class StoryDrawingToolsView: UIView {
    private final class ToolView: UIView {
        let tool: StoryDrawingTool

        private let shadow = CALayer()
        private let background = CALayer()
        private let tip = UIImageView()
        private let band = CAGradientLayer()

        init(tool: StoryDrawingTool) {
            self.tool = tool
            let size = CGSize(width: 40, height: 176)
            super.init(frame: CGRect(origin: .zero, size: size))
            let name =
                switch tool {
                case .pen: "Pen"
                case .arrow: "Arrow"
                case .marker: "Marker"
                case .neon: "Neon"
                case .blur: "Blur"
                case .eraser: "Eraser"
                }
            background.contents = UIImage(named: "MediaEditor/Tool\(name)")?.cgImage
            shadow.contents = UIImage(named: "MediaEditor/Tool\(name)Shadow")?.cgImage
            // The blur's tip keeps its own picture; the others take the colour.
            tip.image = UIImage(named: "MediaEditor/Tool\(name)Tip")?
                .withRenderingMode(tool == .blur ? .alwaysOriginal : .alwaysTemplate)
            tip.frame = CGRect(origin: .zero, size: size)
            shadow.frame = CGRect(origin: .zero, size: size).insetBy(dx: -4, dy: 0)
            background.frame = CGRect(origin: .zero, size: size)
            band.frame = CGRect(x: 3, y: 64, width: size.width - 6, height: size.width - 16)
            band.anchorPoint = CGPoint(x: 0.5, y: 0)
            band.position = CGPoint(x: size.width / 2, y: 64)
            layer.addSublayer(shadow)
            // The marker's and the neon's tips sit under the body.
            if tool == .marker || tool == .neon || tool == .blur {
                addSubview(tip)
                layer.addSublayer(background)
            } else {
                layer.addSublayer(background)
                addSubview(tip)
            }
            if tool != .eraser, tool != .blur { layer.addSublayer(band) }
        }

        @available(*, unavailable) required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// update(state:): the tip in the colour and the band shaded to 70% at its ends, as tall as the size.
        func update(color: UIColor?, size: CGFloat) {
            guard let color else { return }
            tip.tintColor = color
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            let darker = UIColor(hue: hue, saturation: saturation, brightness: brightness * 0.7, alpha: alpha)
            band.colors = [darker.cgColor, color.cgColor, color.cgColor, darker.cgColor]
            band.locations = [0, 0.15, 0.85, 1]
            band.startPoint = CGPoint(x: 0, y: 0.5)
            band.endPoint = CGPoint(x: 1, y: 0.5)
            band.transform = CATransform3DMakeScale(1, 0.08 + 0.92 * size, 1)
        }
    }

    var onSelect: ((StoryDrawingTool) -> Void)?
    var onResize: ((CGFloat) -> Void)?
    var onResizeEnd: (() -> Void)?

    private var toolViews = [ToolView]()
    private var selected = StoryDrawingTool.pen
    private var sizes = [StoryDrawingTool: CGFloat]()
    private var resizeStart: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        for tool in StoryDrawingTool.allCases {
            let view = ToolView(tool: tool)
            view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
            view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
            addSubview(view)
            toolViews.append(view)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutTools()
    }

    func update(selected: StoryDrawingTool, colors: [StoryDrawingTool: UIColor], sizes: [StoryDrawingTool: CGFloat]) {
        self.selected = selected
        self.sizes = sizes
        for view in toolViews {
            view.update(color: colors[view.tool], size: sizes[view.tool] ?? 0.5)
        }
        UIView.animate(
            withDuration: 0.7,
            delay: 0,
            usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0,
            options: .allowUserInteraction,
        ) { self.layoutTools() }
    }

    private func layoutTools() {
        // ToolsComponent's 44 pt, closer together where the story is narrower than the row.
        let spacing = min(44, (bounds.width - 24) / CGFloat(toolViews.count - 1))
        let left = (bounds.width - spacing * CGFloat(toolViews.count - 1)) / 2
        for (index, view) in toolViews.enumerated() {
            let isSelected = view.tool == selected
            view.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            view.center = CGPoint(x: left + spacing * CGFloat(index), y: 176 / 2 - 30 + (isSelected ? 18 : 30))
        }
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view as? ToolView else { return }
        onSelect?(view.tool)
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view as? ToolView, view.tool == selected else { return }
        if gesture.state == .began { resizeStart = sizes[selected] ?? 0.5 }
        let size = max(0, min(1, resizeStart - gesture.translation(in: self).y / 200))
        onResize?(size)
        if gesture.state == .ended || gesture.state == .cancelled { onResizeEnd?() }
    }
}

// MARK: - StoryMarkerStroke

/// MarkerTool through DrawingMetalView's brush: BezierGenerator's quadratic smoothing every 5 pt, then the marker
/// texture stamped every 2 pt at the size's width (1% to 9% of 1920), turned -0.55 rad, each stamp's alpha 5.5 over
/// the stamps that overlap it, laid over each other.
final class StoryMarkerStroke: StoryStroke {
    private let width: CGFloat
    private let stamp: CGImage?
    private let canvas: CGContext?
    private var points = [CGPoint]()
    private var step = 0
    private var lastStamped: CGPoint?

    init(color: UIColor, size: CGFloat, drawingSize: CGSize) {
        let longest = max(drawingSize.width, drawingSize.height)
        let minLineWidth = max(10, longest * 0.01)
        let maxLineWidth = max(20, longest * 0.09)
        self.width = minLineWidth + (maxLineWidth - minLineWidth) * size
        self.stamp = Self.makeStamp(color: color, width: width)
        self.canvas = CGContext(
            data: nil,
            width: Int(drawingSize.width),
            height: Int(drawingSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        )
        // Story points top down, as the drawing view's.
        canvas?.translateBy(x: 0, y: drawingSize.height)
        canvas?.scaleBy(x: 1, y: -1)
    }

    /// The texture in the colour, turned -0.55 rad about its centre.
    private static func makeStamp(color: UIColor, width: CGFloat) -> CGImage? {
        guard let texture = UIImage(named: "MediaEditor/Marker") else { return nil }
        let side = max(1, ceil(width))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
            .image { context in
                let cg = context.cgContext
                cg.translateBy(x: side / 2, y: side / 2)
                cg.rotate(by: -0.55)
                cg.translateBy(x: -side / 2, y: -side / 2)
                texture.withTintColor(color.withAlphaComponent(1), renderingMode: .alwaysTemplate)
                    .draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            }
            .cgImage
    }

    func add(_ location: CGPoint, velocity _: CGFloat) {
        if points.isEmpty {
            points = [location]
            step = 0
            return
        }
        guard location != points.last else { return }
        points.append(location)
        guard points.count >= 3 else { return }
        step += 1
        stamp(along: smoothPoints(), isEnd: false)
    }

    func end(at location: CGPoint) {
        if points.count < 3 {
            // A tap or a short touch still leaves the marker's mark.
            stamp(along: points + [location], isEnd: true)
        }
    }

    func draw(in context: CGContext) {
        guard let image = canvas?.makeImage() else { return }
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.restoreGState()
    }

    /// generateSmoothPathPoints: a quadratic through the middles of the last points, a step every 5 pt.
    private func smoothPoints() -> [CGPoint] {
        let mid: (CGPoint, CGPoint) -> CGPoint = { CGPoint(x: ($0.x + $1.x) / 2, y: ($0.y + $1.y) / 2) }
        let end = mid(points[step], points[step + 1])
        let begin: CGPoint
        let control: CGPoint
        if step == 1 {
            begin = points[0]
            control = mid(mid(points[0], points[1]), points[1])
        } else {
            begin = mid(points[step - 1], points[step])
            control = points[step]
        }
        let distance = ((end.x - begin.x) * (end.x - begin.x) + (end.y - begin.y) * (end.y - begin.y)).squareRoot()
        let count = max(Int(distance / 5), 2)
        var result = (0..<count).map { index -> CGPoint in
            let t = CGFloat(index) / CGFloat(count)
            let u = 1 - t
            return CGPoint(
                x: u * u * begin.x + 2 * u * t * control.x + t * t * end.x,
                y: u * u * begin.y + 2 * u * t * control.y + t * t * end.y,
            )
        }
        result.append(end)
        return result
    }

    /// pushPoint and preparedBuffer: lines between the points 2 pt or more apart, a stamp each 2 pt along them.
    private func stamp(along points: [CGPoint], isEnd: Bool) {
        guard let canvas, let stamp, let first = points.first else { return }
        let width = width
        let stepLength: CGFloat = 2
        canvas.setAlpha(min(1, 5.5 / max(1, width / stepLength)))
        let put: (CGPoint) -> Void = { point in
            canvas.draw(stamp, in: CGRect(x: point.x - width / 2, y: point.y - width / 2, width: width, height: width))
        }
        guard points.count > 1 else {
            put(first)
            return
        }
        var previous = lastStamped ?? first
        for (index, point) in points.enumerated().dropFirst() {
            let dx = point.x - previous.x
            let dy = point.y - previous.y
            let length = (dx * dx + dy * dy).squareRoot()
            guard (isEnd && index == points.count - 1) || length >= stepLength else { continue }
            let count = max(length / stepLength, 1)
            for i in 0..<Int(count) {
                let t = CGFloat(i) / count
                put(CGPoint(x: previous.x + dx * t, y: previous.y + dy * t))
            }
            previous = point
        }
        lastStamped = previous
    }
}

// MARK: - StoryNeonStroke

/// NeonTool: the line smoothed like the pen's but at one width (0.2% to 7% of 1920), filled white with a rim 0.8% of
/// 1080 wide of white mixed a quarter with the colour, over the colour's glow at 87% blurred 1.9 × 2% of 1080 around a
/// shape twice as wide; a black line keeps its colour and glows in 0x440881.
final class StoryNeonStroke: StoryStroke {
    private let lineWidth: CGFloat
    private let strokeWidth: CGFloat
    private let shadowRadius: CGFloat
    private let fillColor: UIColor
    private let shadowColor: UIColor
    private let path = UIBezierPath()
    private var activePath: UIBezierPath?
    private var points = [CGPoint](repeating: .zero, count: 4)
    private var pointPtr = 0

    init(color: UIColor, size: CGFloat, drawingSize: CGSize) {
        let longest = max(drawingSize.width, drawingSize.height)
        let shortest = min(drawingSize.width, drawingSize.height)
        let minLineWidth = max(1, longest * 0.002)
        let maxLineWidth = max(10, longest * 0.07)
        self.lineWidth = minLineWidth + (maxLineWidth - minLineWidth) * size
        self.strokeWidth = shortest * 0.008
        self.shadowRadius = shortest * 0.02
        let color = color.withAlphaComponent(1)
        if StoryTextEntityView.lightness(color) < 0.01 {
            self.fillColor = color
            self.shadowColor = UIColor(red: 0x44 / 255, green: 0x08 / 255, blue: 0x81 / 255, alpha: 1)
        } else {
            self.fillColor = .white
            self.shadowColor = color
        }
    }

    /// UIColor.mixedWith.
    private static func mix(_ first: UIColor, _ second: UIColor, _ alpha: CGFloat) -> UIColor {
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0
        guard first.getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              second.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        else { return first }
        let u = 1 - alpha
        return UIColor(
            red: r1 * u + r2 * alpha,
            green: g1 * u + g2 * alpha,
            blue: b1 * u + b2 * alpha,
            alpha: a1 * u + a2 * alpha,
        )
    }

    func add(_ location: CGPoint, velocity _: CGFloat) {
        if pointPtr == 0 {
            points[0] = location
            pointPtr = 1
        } else {
            let previous = points[pointPtr - 1]
            let dx = previous.x - location.x
            let dy = previous.y - location.y
            guard (dx * dx + dy * dy).squareRoot() > 10 else { return }
            if pointPtr >= 4 {
                points[3] = CGPoint(x: (points[2].x + location.x) / 2, y: (points[2].y + location.y) / 2)
                if let curve = curve(3) {
                    path.append(curve)
                    activePath = nil
                }
                points[0] = points[3]
                pointPtr = 1
            }
            points[pointPtr] = location
            pointPtr += 1
        }
        activePath = curve(pointPtr - 1)
    }

    func end(at location: CGPoint) {
        if let activePath { path.append(activePath) }
        activePath = nil
        if path.isEmpty {
            path.move(to: location)
            path.addLine(to: CGPoint(x: location.x + 0.1, y: location.y))
        }
    }

    /// draw(in:): the glow from a copy drawn out of sight, then the rim and the fill.
    func draw(in context: CGContext) {
        let line = path.cgPath.mutableCopy() ?? CGMutablePath()
        if let activePath { line.addPath(activePath.cgPath) }
        guard !line.isEmpty else { return }
        let shape = line.copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 0)
        let glow = line.copy(strokingWithWidth: lineWidth * 2, lineCap: .round, lineJoin: .round, miterLimit: 0)
        context.saveGState()
        context.setBlendMode(.normal)
        // Only the shadow lands on the canvas: the glow's shape is drawn far to the left of it.
        let offset: CGFloat = 4000
        context.translateBy(x: -offset, y: 0)
        context.addPath(glow)
        context.setFillColor(fillColor.cgColor)
        context.setStrokeColor(fillColor.cgColor)
        context.setLineWidth(strokeWidth * 0.5)
        context.setLineCap(.round)
        context.setShadow(
            offset: CGSize(width: offset, height: 0),
            blur: shadowRadius * 1.9,
            color: shadowColor.withAlphaComponent(0.87).cgColor,
        )
        context.drawPath(using: .fillStroke)
        context.translateBy(x: offset, y: 0)
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.addPath(shape)
        context.setLineWidth(strokeWidth)
        context.setStrokeColor(Self.mix(fillColor, shadowColor, 0.25).cgColor)
        context.strokePath()
        context.addPath(shape)
        context.fillPath()
        context.restoreGState()
    }

    private func curve(_ count: Int) -> UIBezierPath? {
        let curve = UIBezierPath()
        curve.move(to: points[0])
        switch count {
        case 1: curve.addLine(to: points[1])
        case 2: curve.addQuadCurve(to: points[2], controlPoint: points[1])
        case 3: curve.addCurve(to: points[3], controlPoint1: points[1], controlPoint2: points[2])
        default: return nil
        }
        return curve
    }
}
