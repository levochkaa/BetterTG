// StoryDrawing.swift

import UIKit

// MARK: - StoryDrawingTool

/// DrawingToolState.Key's pen, arrow and eraser, with DrawingState.initial's colours and sizes.
enum StoryDrawingTool: CaseIterable {
    case pen
    case arrow
    case eraser

    var initialColor: UIColor? {
        switch self {
        case .pen: UIColor(red: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)
        case .arrow: UIColor(red: 0xFF / 255, green: 0x8A / 255, blue: 0, alpha: 1)
        case .eraser: nil
        }
    }

    var initialSize: CGFloat {
        self == .eraser ? 0.5 : 0.23
    }
}

// MARK: - StoryPenStroke

/// PenTool for one stroke in story points: each touch's width falls with its speed between the size's width and a
/// fifth of the way up from the thinnest (a fixed width for the eraser), eased 30/70 with the last; points closer than
/// 8 pt are dropped and the rest smoothed through quadratic and cubic Béziers into 24 to 48 steps, each pair of steps a
/// segment with round ends. The arrow adds two strokes 0.45 rad either side of the line's end; a tap leaves a dot.
final class StoryPenStroke {
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
    private(set) var segments = [Segment]()
    private(set) var activeSegments = [Segment]()
    private(set) var arrow: (left: CGPoint, start: CGPoint, right: CGPoint, width: CGFloat)?

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
        self.renderMinLineWidth = tool == .eraser ? lineWidth : minLineWidth + (lineWidth - minLineWidth) * 0.2
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

    /// draw(in:): the eraser clears, the rest fill in the colour at full opacity.
    func draw(in context: CGContext) {
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
    var tool = StoryDrawingTool.pen
    var color = StoryDrawingTool.pen.initialColor ?? .white
    var size = StoryDrawingTool.pen.initialSize
    var onStrokesChange: (() -> Void)?

    private(set) var strokes = [StoryPenStroke]()

    private var committed: CGImage?
    private var active: StoryPenStroke?

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
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
            let stroke = StoryPenStroke(tool: tool, color: color, size: size, drawingSize: bounds.size)
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
        let stroke = StoryPenStroke(tool: tool, color: color, size: size, drawingSize: bounds.size)
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

    private func rebuild() {
        committed = strokes.isEmpty ? nil : render(strokes: strokes, over: nil)
        setNeedsDisplay()
        onStrokesChange?()
    }

    private func render(strokes: [StoryPenStroke], over image: CGImage?) -> CGImage? {
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
                case .eraser: "Eraser"
                }
            background.contents = UIImage(named: "MediaEditor/Tool\(name)")?.cgImage
            shadow.contents = UIImage(named: "MediaEditor/Tool\(name)Shadow")?.cgImage
            tip.image = UIImage(named: "MediaEditor/Tool\(name)Tip")?.withRenderingMode(.alwaysTemplate)
            tip.frame = CGRect(origin: .zero, size: size)
            shadow.frame = CGRect(origin: .zero, size: size).insetBy(dx: -4, dy: 0)
            background.frame = CGRect(origin: .zero, size: size)
            band.frame = CGRect(x: 3, y: 64, width: size.width - 6, height: size.width - 16)
            band.anchorPoint = CGPoint(x: 0.5, y: 0)
            band.position = CGPoint(x: size.width / 2, y: 64)
            layer.addSublayer(shadow)
            layer.addSublayer(background)
            addSubview(tip)
            if tool != .eraser { layer.addSublayer(band) }
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
        let spacing: CGFloat = 44
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
    }
}
