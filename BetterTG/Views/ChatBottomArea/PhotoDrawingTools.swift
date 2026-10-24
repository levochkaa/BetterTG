// PhotoDrawingTools.swift

import UIKit

// MARK: - PhotoDrawingTool

/// DrawingToolState.Key: the brushes in ToolsComponent's order.
enum PhotoDrawingTool: Int, CaseIterable {
    case pen
    case arrow
    case marker
    case neon
    case blur
    case eraser

    /// Blur and Eraser have no color.
    var hasColor: Bool {
        self != .blur && self != .eraser
    }
}

// MARK: - PhotoDrawingToolState

/// DrawingState: the selected tool and each tool's color and size, saved for the next painting like
/// DrawingScreen's `saveToolState`.
struct PhotoDrawingToolState: Equatable {
    struct Brush: Equatable {
        var color: PhotoDrawingColor
        /// 0 to 1.
        var size: CGFloat
    }

    /// `DrawingState.initial`.
    static let initial = PhotoDrawingToolState(
        selectedTool: .pen,
        brushes: [
            .pen: Brush(color: PhotoDrawingColor(rgb: 0xFF453A), size: 0.23),
            .arrow: Brush(color: PhotoDrawingColor(rgb: 0xFF8A00), size: 0.23),
            .marker: Brush(color: PhotoDrawingColor(rgb: 0xFFD60A), size: 0.75),
            .neon: Brush(color: PhotoDrawingColor(rgb: 0x34C759), size: 0.4),
            .blur: Brush(color: .black, size: 0.5),
            .eraser: Brush(color: .black, size: 0.5),
        ],
    )

    private static let defaultsKey = "PhotoDrawingToolState"

    var selectedTool: PhotoDrawingTool
    var brushes: [PhotoDrawingTool: Brush]

    var brush: Brush {
        get { brushes[selectedTool] ?? Self.initial.brushes[selectedTool] ?? Brush(color: .white, size: 0.5) }
        set { brushes[selectedTool] = newValue }
    }

    /// The saved state, or the initial one.
    static func load() -> PhotoDrawingToolState {
        guard let saved = UserDefaults.standard.dictionary(forKey: defaultsKey) else { return initial }
        var state = initial
        if let raw = saved["selected"] as? Int, let tool = PhotoDrawingTool(rawValue: raw) {
            state.selectedTool = tool
        }
        for tool in PhotoDrawingTool.allCases {
            guard let values = saved["\(tool.rawValue)"] as? [Double], values.count == 3 else { continue }
            state.brushes[tool] = Brush(
                color: PhotoDrawingColor(rgb: Int(values[0]), alpha: CGFloat(values[1])),
                size: min(max(CGFloat(values[2]), 0), 1),
            )
        }
        return state
    }

    func save() {
        var saved: [String: Any] = ["selected": selectedTool.rawValue]
        for (tool, brush) in brushes {
            saved["\(tool.rawValue)"] = [Double(brush.color.rgb), Double(brush.color.alpha), Double(brush.size)]
        }
        UserDefaults.standard.set(saved, forKey: Self.defaultsKey)
    }
}

// MARK: - PhotoDrawingPoint

/// DrawingPoint: a touch in the painting with its speed there.
struct PhotoDrawingPoint {
    let location: CGPoint
    let velocity: CGFloat
}

// MARK: - PhotoDrawingGestureState

/// DrawingGesturePipeline.DrawingGestureState.
enum PhotoDrawingGestureState {
    case began
    case changed
    case ended
    case cancelled
}

// MARK: - PhotoDrawingElement

/// DrawingElement: a stroke while it is drawn, shown live and drawn into the painting when it is committed.
@MainActor protocol PhotoDrawingElement: AnyObject {
    var isValid: Bool { get }
    /// The painting's area the element covers.
    var bounds: CGRect { get }

    /// The live view over the painting, or none.
    func makeRenderView() -> UIView?
    func updatePath(_ point: PhotoDrawingPoint, state: PhotoDrawingGestureState)
    /// The element at the painting's full size into a context in UIKit's coordinates.
    func draw(in context: CGContext, size: CGSize)
}

/// `normalizeDrawingRect`.
func normalizedDrawingRect(_ rect: CGRect, drawingSize: CGSize) -> CGRect {
    guard !rect.isNull, !rect.isInfinite else { return .zero }
    return rect.intersection(CGRect(origin: .zero, size: drawingSize)).integral
}

// MARK: - PhotoDrawingPenElement

/// PenTool: Pen and Arrow with their speed-thinned width and smoothing, and Eraser and Blur at an even width.
@MainActor final class PhotoDrawingPenElement: PhotoDrawingElement {
    // MARK: Private

    private struct Point {
        let location: CGPoint
        let width: CGFloat
    }

    private struct Segment {
        let a: CGPoint
        let b: CGPoint
        let c: CGPoint
        let d: CGPoint
        let radius1: CGFloat
        let radius2: CGFloat
        let rect: CGRect
    }

    private enum SmootherInput {
        case quad(Point, Point, Point)
        case cubic(Point, Point, Point, Point)

        var start: Point {
            switch self {
            case .cubic(let start, _, _, _),
                 .quad(let start, _, _): start
            }
        }

        var end: Point {
            switch self {
            case .cubic(_, _, _, let end),
                 .quad(_, _, let end): end
            }
        }
    }

    /// RenderView: the stroke drawn a third of the painting's size, with an accumulated image after every 512
    /// segments, as an alpha mask for Eraser and Blur.
    private final class RenderView: UIView {
        final class ActiveView: UIView {
            weak var parent: RenderView?

            override func draw(_ rect: CGRect) {
                guard let context = UIGraphicsGetCurrentContext(), let parent, let element = parent.element else {
                    return
                }
                if element.isEraser {
                    // The eraser's mask: opaque but where the stroke goes.
                    context.setFillColor(UIColor.white.cgColor)
                    context.fill(rect)
                    if let accumulation = parent.accumulationImage {
                        context.setBlendMode(.copy)
                        UIImage(cgImage: accumulation).draw(in: bounds)
                    }
                    context.setBlendMode(.clear)
                } else if let accumulation = parent.accumulationImage {
                    UIImage(cgImage: accumulation).draw(in: bounds)
                }
                context.scaleBy(x: 1 / parent.drawScale, y: 1 / parent.drawScale)
                element.drawSegments(in: context, from: parent.start, to: parent.segmentsCount)
                element.drawActiveSegments(in: context)
            }
        }

        /// RenderView's `setup` scale.
        private static let scale: CGFloat = 0.33

        weak var element: PhotoDrawingPenElement?
        private(set) var accumulationImage: CGImage?
        private(set) var start = 0
        private(set) var segmentsCount = 0
        private(set) var drawScale: CGFloat = 1

        private let activeView = ActiveView()

        func setup(element: PhotoDrawingPenElement, size: CGSize) {
            self.element = element
            backgroundColor = .clear
            isOpaque = false
            isUserInteractionEnabled = false
            let viewSize = CGSize(width: ceil(size.width * Self.scale), height: ceil(size.height * Self.scale))
            drawScale = size.width / viewSize.width
            bounds = CGRect(origin: .zero, size: viewSize)
            transform = CGAffineTransform(scaleX: drawScale, y: size.height / viewSize.height)
            center = CGPoint(x: size.width / 2, y: size.height / 2)
            activeView.frame = CGRect(origin: .zero, size: viewSize)
            activeView.backgroundColor = .clear
            activeView.isOpaque = false
            activeView.contentMode = .redraw
            activeView.contentScaleFactor = 1
            activeView.parent = self
            addSubview(activeView)
            activeView.setNeedsDisplay()
        }

        /// `draw(element:rect:)`.
        func update(rect: CGRect) {
            guard let element else { return }
            alpha = element.isEraser || element.isBlur ? 1 : element.color.alpha
            guard !rect.isNull, !rect.isInfinite, !rect.isEmpty else { return }
            var dirtyRect: CGRect? = rect
            let limit = 512
            if segmentsCount - start > limit {
                dirtyRect = nil
                let newStart = start + limit
                accumulationImage = accumulate(element: element, to: newStart)
                start = newStart
            }
            segmentsCount = element.segments.count
            if let dirtyRect {
                let scaled = dirtyRect.insetBy(dx: -40, dy: -40)
                    .applying(CGAffineTransform(scaleX: 1 / drawScale, y: 1 / drawScale))
                activeView.setNeedsDisplay(scaled)
            } else {
                activeView.setNeedsDisplay()
            }
        }

        /// `animateArrowPaths`: the arrowhead's two lines drawn out.
        func animateArrow(
            start: CGPoint,
            direction: CGFloat,
            length: CGFloat,
            lineWidth: CGFloat,
            completion: @escaping () -> Void,
        ) {
            guard let element else {
                completion()
                return
            }
            let arrowStart = CGPoint(x: start.x / drawScale, y: start.y / drawScale)
            var layers = [CAShapeLayer]()
            for angle in [direction - 0.45, direction + 0.45] {
                let path = UIBezierPath()
                path.move(to: arrowStart)
                path.addLine(to: arrowStart.point(atDistance: length / drawScale, angle: angle))
                let shape = CAShapeLayer()
                shape.path = path.cgPath
                shape.lineWidth = lineWidth / drawScale
                shape.strokeColor = element.renderColor.cgColor
                shape.fillColor = nil
                shape.lineCap = .round
                shape.frame = bounds
                layer.addSublayer(shape)
                layers.append(shape)
            }
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                completion()
                layers.forEach { $0.removeFromSuperlayer() }
            }
            for shape in layers {
                let animation = CABasicAnimation(keyPath: "strokeEnd")
                animation.fromValue = 0
                animation.toValue = 1
                animation.duration = 0.2
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                shape.add(animation, forKey: "strokeEnd")
            }
            CATransaction.commit()
        }

        private func accumulate(element: PhotoDrawingPenElement, to end: Int) -> CGImage? {
            let size = bounds.size
            guard let context = PhotoDrawing.makeContext(width: Int(size.width), height: Int(size.height)) else {
                return accumulationImage
            }
            UIGraphicsPushContext(context)
            defer { UIGraphicsPopContext() }
            if element.isEraser {
                context.setFillColor(UIColor.white.cgColor)
                context.fill(CGRect(origin: .zero, size: size))
            }
            if let accumulationImage {
                context.setBlendMode(.copy)
                UIImage(cgImage: accumulationImage).draw(in: CGRect(origin: .zero, size: size))
            }
            context.setBlendMode(element.isEraser ? .clear : .copy)
            context.scaleBy(x: 1 / drawScale, y: 1 / drawScale)
            element.drawSegments(in: context, from: start, to: end)
            return context.makeImage()
        }
    }

    // MARK: Internal

    let color: PhotoDrawingColor
    let hasArrow: Bool
    let isEraser: Bool
    let isBlur: Bool
    let renderColor: UIColor
    private(set) var isFinishingArrow = false

    private let drawingSize: CGSize
    private let renderLineWidth: CGFloat
    private let renderMinLineWidth: CGFloat
    private let renderArrowLength: CGFloat
    private var renderArrowLineWidth: CGFloat
    private let blurredImage: CGImage?
    private var arrowStart: CGPoint?
    private var arrowDirection: CGFloat?
    private var arrowPaths = [CGPath]()
    private var points = Array(repeating: Point(location: .zero, width: 0), count: 4)
    private var pointPtr = 0
    private var smoothPoints = [Point]()
    private var activeSmoothPoints = [Point]()
    private var segments = [Segment]()
    private var activeSegments = [Segment]()
    private var segmentPaths = [Int: CGPath]()
    private var previousActiveRect: CGRect?
    private var previousRenderLineWidth: CGFloat?
    private weak var renderView: RenderView?

    var isValid: Bool {
        hasArrow ? arrowStart != nil && arrowDirection != nil : !segments.isEmpty
    }

    var bounds: CGRect {
        var combined = boundingRect(from: 0, to: segments.count).insetBy(dx: -20, dy: -20)
        for path in arrowPaths {
            combined = combined.union(path.boundingBox.insetBy(dx: -renderArrowLineWidth, dy: -renderArrowLineWidth))
                .insetBy(dx: -20, dy: -20)
        }
        return normalizedDrawingRect(combined, drawingSize: drawingSize)
    }

    /// `lineWidth` is the tool's size, 0 to 1.
    init(
        drawingSize: CGSize,
        color: PhotoDrawingColor,
        lineWidth: CGFloat,
        hasArrow: Bool,
        isEraser: Bool,
        isBlur: Bool,
        blurredImage: CGImage?,
    ) {
        self.drawingSize = drawingSize
        self.color = isEraser || isBlur ? .black : color
        self.hasArrow = hasArrow
        self.isEraser = isEraser
        self.isBlur = isBlur
        self.blurredImage = blurredImage
        let side = max(drawingSize.width, drawingSize.height)
        let minLineWidth = max(1, side * 0.002)
        let maxLineWidth = max(10, side * 0.07)
        let width = minLineWidth + (maxLineWidth - minLineWidth) * lineWidth
        self.renderLineWidth = width
        self.renderMinLineWidth = isEraser || isBlur ? width : minLineWidth + (width - minLineWidth) * 0.2
        self.renderArrowLength = max(max(10, side * 0.02), width * 3)
        self.renderArrowLineWidth = max(minLineWidth * 1.8, width * 0.75)
        self.renderColor = color.withAlpha(1).uiColor
    }

    /// The tool's size, 0 to 1, as its width in the painting.
    static func lineWidth(_ size: CGFloat, drawingSize: CGSize) -> CGFloat {
        let side = max(drawingSize.width, drawingSize.height)
        let minLineWidth = max(1, side * 0.002)
        let maxLineWidth = max(10, side * 0.07)
        return minLineWidth + (maxLineWidth - minLineWidth) * size
    }

    /// `pathForSegment`: a capsule from one width to the next.
    private static func path(for segment: Segment) -> CGPath {
        let path = CGMutablePath()
        path.move(to: segment.b)
        let abStartAngle = atan2(segment.b.y - segment.a.y, segment.b.x - segment.a.x)
        path.addArc(
            center: CGPoint(x: (segment.a.x + segment.b.x) / 2, y: (segment.a.y + segment.b.y) / 2),
            radius: segment.radius1,
            startAngle: abStartAngle,
            endAngle: abStartAngle + .pi,
            clockwise: true,
        )
        path.addLine(to: segment.c)
        let cdStartAngle = atan2(segment.c.y - segment.d.y, segment.c.x - segment.d.x)
        path.addArc(
            center: CGPoint(x: (segment.c.x + segment.d.x) / 2, y: (segment.c.y + segment.d.y) / 2),
            radius: segment.radius2,
            startAngle: cdStartAngle,
            endAngle: cdStartAngle + .pi,
            clockwise: true,
        )
        path.closeSubpath()
        return path
    }

    private static func quadBezier(_ start: CGPoint, _ control: CGPoint, _ end: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(x: quadBezier(start.x, control.x, end.x, t: t), y: quadBezier(start.y, control.y, end.y, t: t))
    }

    private static func quadBezier(_ start: CGFloat, _ control: CGFloat, _ end: CGFloat, t: CGFloat) -> CGFloat {
        let inverse = 1 - t
        return inverse * inverse * start + 2 * inverse * t * control + t * t * end
    }

    private static func cubicBezier(
        _ start: CGPoint,
        _ control1: CGPoint,
        _ control2: CGPoint,
        _ end: CGPoint,
        t: CGFloat,
    ) -> CGPoint {
        CGPoint(
            x: cubicBezier(start.x, control1.x, control2.x, end.x, t: t),
            y: cubicBezier(start.y, control1.y, control2.y, end.y, t: t),
        )
    }

    private static func cubicBezier(
        _ start: CGFloat,
        _ control1: CGFloat,
        _ control2: CGFloat,
        _ end: CGFloat,
        t: CGFloat,
    ) -> CGFloat {
        let inverse = 1 - t
        return inverse * inverse * inverse * start + 3 * inverse * inverse * t * control1
            + 3 * inverse * t * t * control2 + t * t * t * end
    }

    func makeRenderView() -> UIView? {
        let view = RenderView()
        view.setup(element: self, size: drawingSize)
        renderView = view
        return view
    }

    /// `finishArrow`: the arrowhead is drawn out before the stroke is committed.
    func finishArrow(_ completion: @escaping () -> Void) {
        guard let arrowStart, let arrowDirection, let renderView else {
            completion()
            return
        }
        isFinishingArrow = true
        renderView.animateArrow(
            start: arrowStart,
            direction: arrowDirection,
            length: renderArrowLength,
            lineWidth: renderArrowLineWidth,
        ) { [weak self] in
            self?.isFinishingArrow = false
            completion()
        }
    }

    func updatePath(_ point: PhotoDrawingPoint, state: PhotoDrawingGestureState) {
        let result = addPoint(point)
        let resetActiveRect = result?.reset ?? false
        let updatedRect = result?.rect
        var combinedRect = updatedRect
        if let previousActiveRect {
            combinedRect = updatedRect?.union(previousActiveRect) ?? previousActiveRect
        }
        previousActiveRect = resetActiveRect ? updatedRect : combinedRect
        if let combinedRect {
            renderView?.update(rect: combinedRect)
        }
        guard state == .ended else { return }
        if !activeSegments.isEmpty {
            let previousCount = segments.count
            segments.append(contentsOf: activeSegments)
            smoothPoints.append(contentsOf: activeSmoothPoints)
            activeSegments.removeAll()
            activeSmoothPoints.removeAll()
            renderView?.update(rect: boundingRect(from: previousCount, to: segments.count))
        }
        if hasArrow {
            var direction: CGFloat?
            if smoothPoints.count > 4, let last = smoothPoints.last?.location {
                for index in 1..<min(smoothPoints.count - 2, 200) {
                    let previous = smoothPoints[smoothPoints.count - 1 - index].location
                    if previous.distance(to: last) > renderArrowLength * 0.5 {
                        direction = last.angle(to: previous)
                        break
                    }
                }
            }
            arrowStart = smoothPoints.last?.location
            arrowDirection = direction
            setupArrow()
        } else if segments.isEmpty {
            // A tap leaves a dot.
            let radius = renderLineWidth / 2
            let location = point.location
            segments.append(Segment(
                a: CGPoint(x: location.x - radius, y: location.y),
                b: CGPoint(x: location.x + radius, y: location.y),
                c: CGPoint(x: location.x - radius, y: location.y + 0.1),
                d: CGPoint(x: location.x + radius, y: location.y + 0.1),
                radius1: radius,
                radius2: radius,
                rect: CGRect(x: location.x - radius, y: location.y - radius, width: radius * 2, height: radius * 2),
            ))
            renderView?.update(rect: segments[0].rect)
        }
    }

    func draw(in context: CGContext, size: CGSize) {
        guard !segments.isEmpty else { return }
        context.saveGState()
        defer { context.restoreGState() }
        if isEraser {
            context.setBlendMode(.clear)
        } else if isBlur {
            context.setBlendMode(.normal)
        } else {
            context.setAlpha(color.alpha)
            context.setBlendMode(.copy)
        }
        context.setShouldAntialias(true)
        if isBlur {
            drawBlur(in: context, size: size)
        } else {
            drawSegments(in: context, from: 0, to: segments.count)
        }
        if !arrowPaths.isEmpty {
            context.setStrokeColor(renderColor.cgColor)
            context.setLineWidth(renderArrowLineWidth)
            context.setLineCap(.round)
            for path in arrowPaths {
                context.addPath(path)
                context.strokePath()
            }
        }
    }

    fileprivate func drawSegments(in context: CGContext, from start: Int, to end: Int) {
        guard start < end else { return }
        context.setFillColor(renderColor.cgColor)
        for index in start..<min(end, segments.count) {
            context.addPath(path(forSegmentAt: index))
            context.fillPath()
        }
    }

    fileprivate func drawActiveSegments(in context: CGContext) {
        context.setFillColor(renderColor.cgColor)
        for segment in activeSegments {
            context.addPath(Self.path(for: segment))
            context.fillPath()
        }
    }

    // MARK: Drawing

    /// The blurred photo where the stroke goes, through a half-size mask of it.
    private func drawBlur(in context: CGContext, size: CGSize) {
        guard let blurredImage else { return }
        let maskWidth = max(1, Int(size.width / 2))
        let maskHeight = max(1, Int(size.height / 2))
        guard let mask = CGContext(
            data: nil,
            width: maskWidth,
            height: maskHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue,
        ) else { return }
        mask.setFillColor(gray: 0, alpha: 1)
        mask.fill(CGRect(x: 0, y: 0, width: maskWidth, height: maskHeight))
        mask.translateBy(x: 0, y: CGFloat(maskHeight))
        mask.scaleBy(x: CGFloat(maskWidth) / size.width, y: -CGFloat(maskHeight) / size.height)
        mask.setFillColor(gray: 1, alpha: 1)
        for index in segments.indices {
            mask.addPath(path(forSegmentAt: index))
            mask.fillPath()
        }
        guard let maskImage = mask.makeImage() else { return }
        let rect = CGRect(origin: .zero, size: size)
        // Back to Core Graphics' own coordinates, where images and masks draw upright.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.clip(to: rect, mask: maskImage)
        context.draw(blurredImage, in: rect)
    }

    private func setupArrow() {
        guard let start = arrowStart, let direction = arrowDirection else { return }
        arrowPaths = [direction - 0.45, direction + 0.45].map { angle in
            let path = CGMutablePath()
            path.move(to: start)
            path.addLine(to: start.point(atDistance: renderArrowLength, angle: angle))
            return path
        }
        renderArrowLineWidth = smoothPoints.last?.width ?? renderArrowLineWidth
    }

    private func path(forSegmentAt index: Int) -> CGPath {
        if let path = segmentPaths[index] {
            return path
        }
        let path = Self.path(for: segments[index])
        segmentPaths[index] = path
        return path
    }

    // MARK: Points

    /// `addPoint`: the width thins with speed, points closer than 8 px are dropped, and every fourth point closes
    /// a smoothed cubic piece.
    private func addPoint(_ point: PhotoDrawingPoint) -> (reset: Bool, rect: CGRect)? {
        let filterDistance: CGFloat = 8
        let velocity = point.velocity == 0 ? 1000 : point.velocity
        var width = max(renderMinLineWidth, min(renderLineWidth - velocity / 200, renderLineWidth))
        if let previousRenderLineWidth {
            width = width * 0.3 + previousRenderLineWidth * 0.7
        }
        previousRenderLineWidth = width
        var resetActiveRect = false
        var finalizedRect: CGRect?
        if pointPtr == 0 {
            points[0] = Point(location: point.location, width: width)
            pointPtr += 1
        } else {
            let previousPoint = points[pointPtr - 1].location
            guard previousPoint.distance(to: point.location) > filterDistance else { return nil }
            if pointPtr >= 4 {
                points[3] = Point(
                    location: points[2].location.point(to: point.location, t: 0.5),
                    width: points[2].width,
                )
                if var newSmoothPoints = currentSmoothPoints(3) {
                    if let previousSmoothPoint = smoothPoints.last {
                        newSmoothPoints.insert(previousSmoothPoint, at: 0)
                    }
                    let (newSegments, rect) = makeSegments(newSmoothPoints)
                    smoothPoints.append(contentsOf: newSmoothPoints)
                    segments.append(contentsOf: newSegments)
                    finalizedRect = rect
                    activeSmoothPoints.removeAll()
                    activeSegments.removeAll()
                    resetActiveRect = true
                }
                points[0] = points[3]
                pointPtr = 1
            }
            points[pointPtr] = Point(location: point.location, width: width)
            pointPtr += 1
        }
        guard let newSmoothPoints = currentSmoothPoints(pointPtr - 1) else {
            if let finalizedRect {
                return (resetActiveRect, finalizedRect)
            }
            return nil
        }
        let (newSegments, rect) = makeSegments(newSmoothPoints)
        activeSmoothPoints = newSmoothPoints
        activeSegments = newSegments
        if let finalizedRect, let rect {
            return (resetActiveRect, finalizedRect.union(rect))
        }
        if let combined = rect ?? finalizedRect {
            return (resetActiveRect, combined)
        }
        return nil
    }

    private func currentSmoothPoints(_ count: Int) -> [Point]? {
        switch count {
        case 2: smooth(.quad(points[0], points[1], points[2]))
        case 3: smooth(.cubic(points[0], points[1], points[2], points[3]))
        default: nil
        }
    }

    /// `smoothPoints`: 24 to 48 points along the curve, every 6 px.
    private func smooth(_ input: SmootherInput) -> [Point] {
        let distance = input.start.location.distance(to: input.end.location)
        let numberOfSegments = min(48, max(floor(distance / 6), 24))
        let step = 1 / numberOfSegments
        var result = [Point]()
        for t in stride(from: CGFloat(0), to: 1, by: step) {
            switch input {
            case .quad(let start, let control, let end):
                result.append(Point(
                    location: Self.quadBezier(start.location, control.location, end.location, t: t),
                    width: Self.quadBezier(start.width, (start.width + end.width) / 2, end.width, t: t),
                ))
            case .cubic(let start, let control1, let control2, let end):
                result.append(Point(
                    location: Self.cubicBezier(
                        start.location,
                        control1.location,
                        control2.location,
                        end.location,
                        t: t,
                    ),
                    width: Self.cubicBezier(
                        start.width,
                        (start.width + control1.width) / 2,
                        (control2.width + end.width) / 2,
                        end.width,
                        t: t,
                    ),
                ))
            }
        }
        result.append(input.end)
        return result
    }

    private func makeSegments(_ smoothPoints: [Point]) -> ([Segment], CGRect?) {
        var result = [Segment]()
        var updateRect = CGRect.null
        for index in 1..<smoothPoints.count {
            let previousPoint = smoothPoints[index - 1].location
            let previousWidth = smoothPoints[index - 1].width
            let currentPoint = smoothPoints[index].location
            let currentWidth = smoothPoints[index].width
            guard abs(currentPoint.x - previousPoint.x) > 0.0001 || abs(currentPoint.y - previousPoint.y) > 0.0001
            else {
                continue
            }
            var perpendicular = CGPoint(x: -(currentPoint.y - previousPoint.y), y: currentPoint.x - previousPoint.x)
            let length = hypot(perpendicular.x, perpendicular.y)
            if length > 0 {
                perpendicular = CGPoint(x: perpendicular.x / length, y: perpendicular.y / length)
            }
            let a = CGPoint(
                x: previousPoint.x + perpendicular.x * previousWidth / 2,
                y: previousPoint.y + perpendicular.y * previousWidth / 2,
            )
            let b = CGPoint(
                x: previousPoint.x - perpendicular.x * previousWidth / 2,
                y: previousPoint.y - perpendicular.y * previousWidth / 2,
            )
            let c = CGPoint(
                x: currentPoint.x + perpendicular.x * currentWidth / 2,
                y: currentPoint.y + perpendicular.y * currentWidth / 2,
            )
            let d = CGPoint(
                x: currentPoint.x - perpendicular.x * currentWidth / 2,
                y: currentPoint.y - perpendicular.y * currentWidth / 2,
            )
            let abCenter = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let abRadius = CGPoint(x: abCenter.x - b.x, y: abCenter.y - b.y)
            let ab = CGPoint(x: abCenter.x - abRadius.y, y: abCenter.y + abRadius.x)
            let cdCenter = CGPoint(x: (c.x + d.x) / 2, y: (c.y + d.y) / 2)
            let cdRadius = CGPoint(x: cdCenter.x - c.x, y: cdCenter.y - c.y)
            let cd = CGPoint(x: cdCenter.x - cdRadius.y, y: cdCenter.y + cdRadius.x)
            let minX = min(a.x, b.x, c.x, d.x, ab.x, cd.x)
            let minY = min(a.y, b.y, c.y, d.y, ab.y, cd.y)
            let maxX = max(a.x, b.x, c.x, d.x, ab.x, cd.x)
            let maxY = max(a.y, b.y, c.y, d.y, ab.y, cd.y)
            let segmentRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            updateRect = updateRect.union(segmentRect)
            result.append(Segment(
                a: a,
                b: b,
                c: c,
                d: d,
                radius1: previousWidth / 2,
                radius2: currentWidth / 2,
                rect: segmentRect,
            ))
        }
        return (result, updateRect.isNull ? nil : updateRect)
    }

    private func boundingRect(from start: Int, to end: Int) -> CGRect {
        guard start < end else { return .null }
        var rect = CGRect.null
        for index in start..<end {
            rect = rect.union(segments[index].rect)
        }
        return rect
    }
}

// MARK: - PhotoDrawingNeonElement

/// NeonTool: a glowing line, white with the color's glow, or dark with a purple glow for black.
@MainActor final class PhotoDrawingNeonElement: PhotoDrawingElement {
    // MARK: Private

    /// RenderView: the glow, border and fill as shape layers while the line is drawn.
    private final class RenderView: UIView {
        let shadowLayer = CAShapeLayer()
        let borderLayer = CAShapeLayer()
        let fillLayer = CAShapeLayer()

        func setup(element: PhotoDrawingNeonElement, size: CGSize) {
            backgroundColor = .clear
            isOpaque = false
            isUserInteractionEnabled = false
            contentScaleFactor = 1
            let colors = element.colors
            let bounds = CGRect(origin: .zero, size: size)
            frame = bounds
            for shape in [shadowLayer, borderLayer, fillLayer] {
                shape.frame = bounds
                shape.contentsScale = 1
                shape.lineCap = .round
                shape.lineJoin = .round
                layer.addSublayer(shape)
            }
            shadowLayer.lineWidth = element.renderStrokeWidth * 0.5
            shadowLayer.fillColor = colors.fill.cgColor
            shadowLayer.strokeColor = colors.fill.cgColor
            shadowLayer.shadowColor = colors.shadow.cgColor
            shadowLayer.shadowRadius = element.renderShadowRadius
            shadowLayer.shadowOpacity = 1
            shadowLayer.shadowOffset = .zero
            borderLayer.lineWidth = element.renderStrokeWidth
            borderLayer.fillColor = UIColor.clear.cgColor
            borderLayer.strokeColor = PhotoDrawingColor(colors.fill)
                .mixed(
                    with: PhotoDrawingColor(colors.shadow),
                    alpha: 0.25,
                )
                .cgColor
            fillLayer.fillColor = colors.fill.cgColor
        }

        func updatePath(_ path: CGPath, shadowPath: CGPath) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shadowLayer.path = path
            shadowLayer.shadowPath = shadowPath
            borderLayer.path = path
            fillLayer.path = path
            CATransaction.commit()
        }
    }

    private let drawingSize: CGSize
    private let color: PhotoDrawingColor
    private let renderStrokeWidth: CGFloat
    private let renderShadowRadius: CGFloat
    private let renderLineWidth: CGFloat
    private let path = CGMutablePath()
    private var activePath: CGPath?
    private var addedPaths = 0
    private var renderPath: CGPath?
    private var shadowRenderPath: CGPath?
    private var points = Array(repeating: CGPoint.zero, count: 4)
    private var pointPtr = 0
    private weak var renderView: RenderView?

    // MARK: Internal

    var isValid: Bool {
        renderPath != nil
    }

    var bounds: CGRect {
        guard let shadowRenderPath else { return .zero }
        let inset = -renderShadowRadius - 30
        return normalizedDrawingRect(
            shadowRenderPath.boundingBoxOfPath.insetBy(dx: inset, dy: inset),
            drawingSize: drawingSize,
        )
    }

    /// The line's fill and glow: white over the color, or the color over purple for black.
    private var colors: (fill: UIColor, shadow: UIColor) {
        if color.lightness < 0.01 {
            return (color.uiColor, UIColor(rgb: 0x440881))
        }
        return (.white, color.uiColor)
    }

    init(drawingSize: CGSize, color: PhotoDrawingColor, lineWidth: CGFloat) {
        self.drawingSize = drawingSize
        self.color = color
        self.renderStrokeWidth = min(drawingSize.width, drawingSize.height) * 0.008
        self.renderShadowRadius = min(drawingSize.width, drawingSize.height) * 0.02
        self.renderLineWidth = PhotoDrawingPenElement.lineWidth(lineWidth, drawingSize: drawingSize)
    }

    private static func scale(of transform: CGAffineTransform) -> CGFloat {
        sqrt(abs(transform.a * transform.d - transform.b * transform.c))
    }

    func makeRenderView() -> UIView? {
        let view = RenderView()
        view.setup(element: self, size: drawingSize)
        renderView = view
        return view
    }

    func updatePath(_ point: PhotoDrawingPoint, state: PhotoDrawingGestureState) {
        guard addPoint(point.location) || state == .ended else { return }
        let current = path.mutableCopy() ?? CGMutablePath()
        if let activePath {
            current.addPath(activePath)
        }
        let stroked = current.copy(strokingWithWidth: renderLineWidth, lineCap: .round, lineJoin: .round, miterLimit: 0)
        let shadow = current.copy(
            strokingWithWidth: renderLineWidth * 2,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 0,
        )
        if !current.isEmpty {
            renderPath = stroked
            shadowRenderPath = shadow
            renderView?.updatePath(stroked, shadowPath: shadow)
        }
        guard state == .ended else { return }
        if let activePath {
            path.addPath(activePath)
            renderPath = path.copy(strokingWithWidth: renderLineWidth, lineCap: .round, lineJoin: .round, miterLimit: 0)
        } else if addedPaths == 0 {
            // A tap leaves a dot.
            let location = points[0]
            let dot = CGRect(
                x: location.x - renderLineWidth / 2,
                y: location.y - renderLineWidth / 2,
                width: renderLineWidth,
                height: renderLineWidth,
            )
            renderPath = CGPath(ellipseIn: dot, transform: nil)
            shadowRenderPath = CGPath(
                ellipseIn: dot.insetBy(dx: -renderLineWidth / 2, dy: -renderLineWidth / 2),
                transform: nil,
            )
            if let renderPath, let shadowRenderPath {
                renderView?.updatePath(renderPath, shadowPath: shadowRenderPath)
            }
        }
    }

    /// The glow drawn from far outside so only its shadow lands, then the border and the fill.
    func draw(in context: CGContext, size _: CGSize) {
        guard let renderPath, let shadowRenderPath else { return }
        let neonColors = colors
        context.saveGState()
        defer { context.restoreGState() }
        context.setShouldAntialias(true)
        context.setBlendMode(.normal)
        let shadowOffset = CGSize(width: 3000, height: 3000)
        context.translateBy(x: -shadowOffset.width, y: -shadowOffset.height)
        context.addPath(shadowRenderPath)
        context.setLineCap(.round)
        context.setFillColor(neonColors.fill.cgColor)
        context.setStrokeColor(neonColors.fill.cgColor)
        context.setLineWidth(renderStrokeWidth * 0.5)
        // Shadow offsets ignore the flipped transform, so the offset follows the context's own y direction.
        context.setShadow(
            offset: shadowOffset.applying(context.ctm),
            blur: renderShadowRadius * 1.9 * Self.scale(of: context.ctm),
            color: neonColors.shadow.withAlphaComponent(0.87).cgColor,
        )
        context.drawPath(using: .fillStroke)
        context.translateBy(x: shadowOffset.width, y: shadowOffset.height)
        context.setShadow(offset: .zero, blur: 0, color: UIColor.clear.cgColor)
        context.addPath(renderPath)
        context.setLineWidth(renderStrokeWidth)
        context.setStrokeColor(
            PhotoDrawingColor(neonColors.fill).mixed(with: PhotoDrawingColor(neonColors.shadow), alpha: 0.25).cgColor,
        )
        context.strokePath()
        context.addPath(renderPath)
        context.setFillColor(neonColors.fill.cgColor)
        context.fillPath()
    }

    private func addPoint(_ location: CGPoint) -> Bool {
        let filterDistance: CGFloat = 10
        if pointPtr == 0 {
            points[0] = location
            pointPtr += 1
        } else {
            guard points[pointPtr - 1].distance(to: location) > filterDistance else { return false }
            if pointPtr >= 4 {
                points[3] = points[2].point(to: location, t: 0.5)
                if let bezier = bezierPath(3) {
                    path.addPath(bezier)
                    addedPaths += 1
                    activePath = nil
                }
                points[0] = points[3]
                pointPtr = 1
            }
            points[pointPtr] = location
            pointPtr += 1
        }
        guard let bezier = bezierPath(pointPtr - 1) else { return false }
        activePath = bezier
        return true
    }

    private func bezierPath(_ count: Int) -> CGPath? {
        let bezier = CGMutablePath()
        switch count {
        case 1:
            bezier.move(to: points[0])
            bezier.addLine(to: points[1])
        case 2:
            bezier.move(to: points[0])
            bezier.addQuadCurve(to: points[2], control: points[1])
        case 3:
            bezier.move(to: points[0])
            bezier.addCurve(to: points[3], control1: points[1], control2: points[2])
        default:
            return nil
        }
        return bezier
    }
}

// MARK: - PhotoDrawingMarkerElement

/// MarkerTool with DrawingMetalView's marker brush: a soft tilted ellipse stamped every 2 px along a smoothed line,
/// each stamp's opacity shared out over the stamps it overlaps.
@MainActor final class PhotoDrawingMarkerElement: PhotoDrawingElement {
    // MARK: Private

    private final class RenderView: UIView {
        private var context: CGContext?
        private var scale: CGFloat = 1

        func setup(size: CGSize) {
            isUserInteractionEnabled = false
            backgroundColor = .clear
            frame = CGRect(origin: .zero, size: size)
            scale = min(1, 1024 / max(size.width, size.height, 1))
            context = PhotoDrawing.makeContext(
                width: max(1, Int((size.width * scale).rounded())),
                height: max(1, Int((size.height * scale).rounded())),
            )
            context?.scaleBy(x: scale, y: scale)
        }

        func draw(stamps: ArraySlice<CGPoint>, element: PhotoDrawingMarkerElement) {
            guard let context, !stamps.isEmpty else { return }
            element.drawStamps(stamps, in: context)
            layer.contents = context.makeImage()
        }
    }

    private static let pointStep: CGFloat = 2
    /// The brush's fixed tilt.
    private static let rotation: CGFloat = 0.55

    private let drawingSize: CGSize
    private let color: PhotoDrawingColor
    private let renderLineWidth: CGFloat
    private var points = [CGPoint]()
    private var bezierPoints = [CGPoint]()
    private var bezierStep = 0
    private var lastRenderedPoint: CGPoint?
    private var stamps = [CGPoint]()
    private var renderedStamps = 0
    private lazy var stampImage = makeStampImage()
    private weak var renderView: RenderView?

    // MARK: Internal

    var isValid: Bool {
        points.count > 6
    }

    var bounds: CGRect {
        guard !points.isEmpty else { return .zero }
        var rect = CGRect.null
        for point in points {
            rect = rect.union(CGRect(origin: point, size: .zero))
        }
        return normalizedDrawingRect(rect.insetBy(dx: -80, dy: -80), drawingSize: drawingSize)
    }

    init(drawingSize: CGSize, color: PhotoDrawingColor, lineWidth: CGFloat) {
        self.drawingSize = drawingSize
        self.color = color
        let side = max(drawingSize.width, drawingSize.height)
        let minLineWidth = max(10, side * 0.01)
        let maxLineWidth = max(20, side * 0.09)
        self.renderLineWidth = minLineWidth + (maxLineWidth - minLineWidth) * lineWidth
    }

    func makeRenderView() -> UIView? {
        let view = RenderView()
        view.setup(size: drawingSize)
        renderView = view
        return view
    }

    func updatePath(_ point: PhotoDrawingPoint, state: PhotoDrawingGestureState) {
        let location = point.location
        if let last = points.last, last.distance(to: location) < 10 {
        } else {
            points.append(location)
        }
        // Brush's `updated`.
        switch state {
        case .began:
            bezierStep = 0
            bezierPoints = [location]
            pushPoint(location, isEnd: false)
        case .changed:
            if !bezierPoints.isEmpty, location != lastRenderedPoint {
                pushPoint(location, isEnd: false)
            }
        case .cancelled,
             .ended:
            if bezierPoints.count >= 3 {
                pushPoint(location, isEnd: true)
            }
            bezierPoints.removeAll()
            bezierStep = 0
            lastRenderedPoint = nil
        }
        renderView?.draw(stamps: stamps[renderedStamps...], element: self)
        renderedStamps = stamps.count
    }

    func draw(in context: CGContext, size _: CGSize) {
        guard !stamps.isEmpty else { return }
        context.saveGState()
        context.setBlendMode(.normal)
        drawStamps(stamps[...], in: context)
        context.restoreGState()
    }

    fileprivate func drawStamps(_ stamps: ArraySlice<CGPoint>, in context: CGContext) {
        guard let stampImage else { return }
        let side = renderLineWidth
        let overlapping = max(1, side / Self.pointStep)
        let alpha = min(1, color.alpha / overlapping * 5.5)
        UIGraphicsPushContext(context)
        let image = UIImage(cgImage: stampImage)
        for stamp in stamps {
            image.draw(
                in: CGRect(x: stamp.x - side / 2, y: stamp.y - side / 2, width: side, height: side),
                blendMode: .normal,
                alpha: alpha,
            )
        }
        UIGraphicsPopContext()
    }

    /// `pushPoint`: the smoothed points as lines, with a stamp every 2 px along them.
    private func pushPoint(_ point: CGPoint, isEnd: Bool) {
        let smooth = pushBezierPoint(point)
        guard smooth.count >= 2 else { return }
        var previousPoint = lastRenderedPoint ?? smooth[0]
        for index in 1..<smooth.count {
            let current = smooth[index]
            if (isEnd && index == smooth.count - 1) || previousPoint.distance(to: current) >= Self.pointStep {
                let length = previousPoint.distance(to: current)
                let count = max(length / Self.pointStep, 1)
                for step in 0..<Int(count) {
                    let fraction = CGFloat(step) / count
                    stamps.append(CGPoint(
                        x: previousPoint.x + (current.x - previousPoint.x) * fraction,
                        y: previousPoint.y + (current.y - previousPoint.y) * fraction,
                    ))
                }
                previousPoint = current
            }
        }
        lastRenderedPoint = previousPoint
    }

    /// BezierGenerator's `pushPoint`: a quadratic piece between the midpoints of every new pair of points.
    private func pushBezierPoint(_ point: CGPoint) -> [CGPoint] {
        guard point != bezierPoints.last else { return [] }
        bezierPoints.append(point)
        guard bezierPoints.count >= 3 else { return [] }
        bezierStep += 1
        let step = bezierStep
        let end = bezierPoints[step].point(to: bezierPoints[step + 1], t: 0.5)
        let begin: CGPoint
        let control: CGPoint
        if step == 1 {
            begin = bezierPoints[0]
            control = bezierPoints[0].point(to: bezierPoints[1], t: 0.5).point(to: bezierPoints[1], t: 0.5)
        } else {
            begin = bezierPoints[step - 1].point(to: bezierPoints[step], t: 0.5)
            control = bezierPoints[step]
        }
        let segmentCount = max(Int(begin.distance(to: end) / 5), 2)
        var result = [CGPoint]()
        for index in 0..<segmentCount {
            let t = CGFloat(index) / CGFloat(segmentCount)
            let inverse = 1 - t
            result.append(CGPoint(
                x: inverse * inverse * begin.x + 2 * inverse * t * control.x + t * t * end.x,
                y: inverse * inverse * begin.y + 2 * inverse * t * control.y + t * t * end.y,
            ))
        }
        result.append(end)
        return result
    }

    /// The brush texture (`marker.png`): a flat soft ellipse, tilted and in the color.
    private func makeStampImage() -> CGImage? {
        let side = max(2, Int(ceil(renderLineWidth)))
        guard let context = PhotoDrawing.makeContext(width: side, height: side) else { return nil }
        let size = CGFloat(side)
        context.translateBy(x: size / 2, y: size / 2)
        context.rotate(by: Self.rotation)
        context.translateBy(x: -size / 2, y: -size / 2)
        let ellipse = CGRect(x: size / 48, y: size * 15 / 48, width: size * 46 / 48, height: size * 17 / 48)
        context.setShadow(offset: .zero, blur: size / 48, color: color.withAlpha(0.6).cgColor)
        context.setFillColor(color.withAlpha(0.6).cgColor)
        context.fillEllipse(in: ellipse.insetBy(dx: size / 96, dy: size / 96))
        return context.makeImage()
    }
}

// MARK: - PhotoDrawingFillElement

/// FillTool: the whole painting in one color, cleared, or blurred.
@MainActor final class PhotoDrawingFillElement: PhotoDrawingElement {
    private let drawingSize: CGSize
    private let color: PhotoDrawingColor
    private let blurredImage: CGImage?

    var isValid: Bool {
        true
    }

    var bounds: CGRect {
        CGRect(origin: .zero, size: drawingSize)
    }

    init(drawingSize: CGSize, color: PhotoDrawingColor, blurredImage: CGImage?) {
        self.drawingSize = drawingSize
        self.color = color
        self.blurredImage = blurredImage
    }

    func makeRenderView() -> UIView? {
        nil
    }

    func updatePath(_: PhotoDrawingPoint, state _: PhotoDrawingGestureState) {}

    func draw(in context: CGContext, size: CGSize) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setShouldAntialias(false)
        context.setBlendMode(.copy)
        let rect = CGRect(origin: .zero, size: size)
        if let blurredImage {
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(blurredImage, in: rect)
        } else {
            context.setFillColor(color.cgColor)
            context.fill(rect)
        }
    }
}
