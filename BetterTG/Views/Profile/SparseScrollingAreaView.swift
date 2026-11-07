// SparseScrollingAreaView.swift

import UIKit

// MARK: - SparseScrollingAreaView

/// SparseItemGridScrollingArea over a media grid: while the grid scrolls, a 3 pt line 44 pt tall runs down the right
/// edge 3 pt in, and a glass capsule 32 pt tall 12 pt from the edge names the month and year at the top of the grid,
/// rolling up or down as they change; both fade 2 seconds after the scrolling stops. Dragging the capsule scrolls the
/// whole grid across the area's height (the line widening to 6 pt); holding it 0.2 s first pulls it 80 pt left with a
/// tap of feedback, and a quick tap opens the calendar. Hidden when the content is less than about twice the area.
final class SparseScrollingAreaView: UIView {
    private static let lineHeight: CGFloat = 44
    private static let verticalInset: CGFloat = 3

    /// The date at the top of the grid: its text ("October 2026") and a value that orders it.
    var currentDate: (() -> (text: String, order: Int)?)?
    var onOpenCalendar: (() -> Void)?
    /// SparseItemGrid's onBeginFastScrolling: the capsule starts being dragged.
    var onBeginFastScrolling: (() -> Void)?
    /// displayTooltip: the text shown once, on the first scroll that shows the scroller; `onTooltipShown` records it.
    var tooltipText: String?
    var onTooltipShown: (() -> Void)?
    weak var scrollView: UIScrollView?

    private var tooltip: SparseScrollingTooltipView?
    private var hasShownTooltip = false

    private let line = UIView()
    private let capsule: UIVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = false
        let view = UIVisualEffectView(effect: effect)
        view.cornerConfiguration = .capsule()
        return view
    }()

    private let label = UILabel()
    private var shownDate: (text: String, order: Int)?
    private var isVisible = false
    private var isDragging = false
    private var isAvailable = false
    private var grabOffset: CGFloat = 0
    private var hideWork: DispatchWorkItem?
    private var grabTimer: Timer?
    private var dragStart: (offset: CGFloat, touchY: CGFloat)?
    private let feedback = UIImpactFeedbackGenerator(style: .light)

    // MARK: Layout

    private var scrollFraction: CGFloat {
        guard let scrollView else { return 0 }
        let insets = scrollView.adjustedContentInset
        let range = scrollView.contentSize.height + insets.top + insets.bottom - scrollView.bounds.height
        guard range > 0 else { return 0 }
        return min(1, max(0, (scrollView.contentOffset.y + insets.top) / range))
    }

    /// The track's insets: the grid's safe area, not its content inset, which may hold a header that scrolls away.
    private var trackInsets: UIEdgeInsets {
        scrollView?.safeAreaInsets ?? .zero
    }

    /// The capsule's travel: from the top inset to the bottom one, centred on the line's 44 pt.
    private var capsuleTravel: (minY: CGFloat, maxY: CGFloat) {
        let insets = trackInsets
        let height = capsule.bounds.height
        let minY = Self.verticalInset + insets.top + floor((Self.lineHeight - height) / 2)
        let maxY = bounds.height - Self.verticalInset - insets.bottom - floor((Self.lineHeight - height) / 2) - height
        return (minY, max(minY, maxY))
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        line.layer.cornerRadius = 1.5
        line.alpha = 0
        line.isUserInteractionEnabled = false
        addSubview(line)
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textAlignment = .center
        capsule.contentView.addSubview(label)
        capsule.alpha = 0
        addSubview(capsule)
        let pan = UILongPressGestureRecognizer(target: self, action: #selector(dragged(_:)))
        pan.minimumPressDuration = 0
        capsule.addGestureRecognizer(pan)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.updateLineColor() }
        updateLineColor()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Only the visible capsule takes touches.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isAvailable, isVisible || isDragging, capsule.frame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }

    /// The grid moved: the line and the capsule follow, and appear while it scrolls.
    func update(isScrolling: Bool) {
        guard let scrollView else { return }
        let contentHeight = scrollView.contentSize.height
        isAvailable = contentHeight > 0 && bounds.height / contentHeight < 0.55
        guard isAvailable else {
            hide(animated: false)
            return
        }
        if let date = currentDate?() {
            setDate(date)
        }
        if isScrolling { show() }
        if isScrolling { displayTooltipOnFirstScroll() }
        layoutIndicators()
    }

    func hide(animated: Bool) {
        hideWork?.cancel()
        dismissTooltip()
        isVisible = false
        let changes = {
            self.line.alpha = 0
            self.capsule.alpha = 0
        }
        if animated {
            UIView.animate(withDuration: 0.3, animations: changes)
        } else {
            changes()
        }
    }

    /// displayTooltipOnFirstScroll: the tooltip by the line for five seconds, the capsule 3 pt further left.
    private func displayTooltipOnFirstScroll() {
        guard !hasShownTooltip, let tooltipText else { return }
        hasShownTooltip = true
        let tooltip = SparseScrollingTooltipView(text: tooltipText)
        tooltip.frame = bounds
        tooltip.alpha = 0
        addSubview(tooltip)
        self.tooltip = tooltip
        UIView.animate(withDuration: 0.2) { tooltip.alpha = 1 }
        onTooltipShown?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.dismissTooltip() }
    }

    private func dismissTooltip() {
        guard let tooltip else { return }
        self.tooltip = nil
        UIView.animate(withDuration: 0.3, animations: { tooltip.alpha = 0 }, completion: { _ in
            tooltip.removeFromSuperview()
        })
        layoutIndicators()
    }

    private func updateLineColor() {
        line.backgroundColor = traitCollection.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.5)
            : UIColor(white: 0, alpha: 0.3)
    }

    private func layoutIndicators() {
        let insets = trackInsets
        let fraction = scrollFraction
        let lineTop = Self.verticalInset + insets.top
        let lineBottom = bounds.height - Self.verticalInset - insets.bottom - Self.lineHeight
        let lineWidth: CGFloat = isDragging || tooltip != nil ? 6 : 3
        line.frame = CGRect(
            x: bounds.width - 3 - lineWidth,
            y: lineTop * (1 - fraction) + lineBottom * fraction,
            width: lineWidth,
            height: Self.lineHeight,
        )
        line.layer.cornerRadius = lineWidth / 2
        let labelSize = label.sizeThatFits(CGSize(width: 240, height: 32))
        let size = CGSize(width: ceil(labelSize.width) + 26, height: 32)
        capsule.bounds.size = size
        let travel = capsuleTravel
        capsule.frame.origin = CGPoint(
            x: bounds.width - 12 - size.width - grabOffset - (tooltip == nil ? 0 : 3),
            y: travel.minY * (1 - fraction) + travel.maxY * fraction,
        )
        label.frame = capsule.contentView.bounds
        if let tooltip {
            tooltip.frame = bounds
            tooltip.layout(arrow: line.frame.insetBy(dx: -3, dy: -8), in: bounds.size)
        }
    }

    private func setDate(_ date: (text: String, order: Int)) {
        guard shownDate?.text != date.text else { return }
        if let previous = shownDate, capsule.alpha > 0 {
            // RollingText: the new month rolls in from below when it's later, from above when earlier.
            let transition = CATransition()
            transition.type = .push
            transition.subtype = date.order > previous.order ? .fromTop : .fromBottom
            transition.duration = 0.2
            label.layer.add(transition, forKey: "roll")
        }
        shownDate = date
        label.text = date.text
    }

    private func show() {
        hideWork?.cancel()
        if !isVisible {
            isVisible = true
            UIView.animate(withDuration: 0.3) {
                self.line.alpha = 1
                self.capsule.alpha = 1
            }
        }
        guard !isDragging else { return }
        let work = DispatchWorkItem { [weak self] in self?.hide(animated: true) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    // MARK: Dragging

    @objc private func dragged(_ gesture: UILongPressGestureRecognizer) {
        guard let scrollView else { return }
        let y = gesture.location(in: self).y
        switch gesture.state {
        case .began:
            isDragging = true
            dismissTooltip()
            onBeginFastScrolling?()
            dragStart = (scrollView.contentOffset.y, y)
            scrollView.setContentOffset(scrollView.contentOffset, animated: false)
            grabTimer?.invalidate()
            grabTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.grab() }
            }
            show()
        case .changed:
            guard let dragStart else { return }
            if grabTimer != nil { grab() }
            let travel = capsuleTravel
            let area = travel.maxY - travel.minY
            guard area > 0 else { return }
            let insets = scrollView.adjustedContentInset
            let scrollable = scrollView.contentSize.height + insets.top + insets.bottom - scrollView.bounds.height
            var offset = dragStart.offset + (y - dragStart.touchY) * scrollable / area
            offset = min(max(offset, -insets.top), scrollable - insets.top)
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: offset), animated: false)
        case .cancelled,
             .ended,
             .failed:
            let tapped = grabTimer != nil && gesture.state == .ended
            grabTimer?.invalidate()
            grabTimer = nil
            isDragging = false
            dragStart = nil
            grabOffset = 0
            UIView.animate(withDuration: 0.2) { self.layoutIndicators() }
            show()
            if tapped { onOpenCalendar?() }
        default:
            break
        }
    }

    /// performOffsetBarTimerEvent: the capsule steps 80 pt left under the finger.
    private func grab() {
        grabTimer?.invalidate()
        grabTimer = nil
        feedback.impactOccurred()
        grabOffset = 80
        UIView.animate(withDuration: 0.1) { self.layoutIndicators() }
    }
}

// MARK: - SparseScrollingTooltipView

/// SparseItemGridScrollingArea's TooltipComponent: dark blur in Telegram's bubble with its point at the top right (at
/// the bottom right when it stands above), 8 pt in, the scrolling-grid icon and up to 200 pt of 13 pt white text.
final class SparseScrollingTooltipView: UIView {
    private static let maskImage: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 42, height: 42))
        .image { _ in
            UIColor.black.setFill()
            bubblePath().fill()
        }
        .resizableImage(withCapInsets: UIEdgeInsets(top: 33, left: 16, bottom: 8, right: 25))

    private static let invertedMaskImage: UIImage = UIGraphicsImageRenderer(
        size: CGSize(width: 42, height: 42),
    )
    .image { context in
        context.cgContext.translateBy(x: 0, y: 42)
        context.cgContext.scaleBy(x: 1, y: -1)
        UIColor.black.setFill()
        bubblePath().fill()
    }
    .resizableImage(withCapInsets: UIEdgeInsets(top: 9, left: 16, bottom: 32, right: 25))

    private let background = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let backgroundMask = UIImageView()
    private let icon = SparseScrollingTooltipIcon(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
    private let label = UILabel()

    init(text: String) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        background.mask = backgroundMask
        addSubview(background)
        addSubview(icon)
        label.text = text
        label.font = .systemFont(ofSize: 13)
        label.textColor = .white
        label.numberOfLines = 0
        addSubview(label)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The bubble's outline in a 42 pt square, its point at the top right.
    private static func bubblePath() -> UIBezierPath {
        let path = UIBezierPath()
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        func c(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat, _ y: CGFloat) {
            path.addCurve(to: p(x, y), controlPoint1: p(x1, y1), controlPoint2: p(x2, y2))
        }
        path.move(to: p(0, 18.0252))
        c(0, 14.1279, 0, 12.1792, 0.5358, 10.609)
        c(1.5362, 7.6772, 3.8388, 5.3746, 6.7706, 4.3742)
        c(8.3409, 3.8384, 10.2895, 3.8384, 14.1868, 3.8384)
        path.addLine(to: p(16.7927, 3.8384))
        c(18.2591, 3.8384, 18.9923, 3.8384, 19.7211, 3.8207)
        c(25.1911, 3.6877, 30.6172, 2.8072, 35.8485, 1.2035)
        c(36.5454, 0.9899, 37.241, 0.758, 38.6321, 0.2943)
        c(39.1202, 0.1316, 39.3643, 0.0503, 39.5299, 0.0245)
        c(40.8682, -0.184, 42.0224, 0.9702, 41.8139, 2.3085)
        c(41.7881, 2.4741, 41.7067, 2.7181, 41.544, 3.2062)
        c(41.0803, 4.5974, 40.8485, 5.293, 40.6348, 5.99)
        c(39.0312, 11.2213, 38.1507, 16.6473, 38.0177, 22.1173)
        c(38, 22.846, 38, 23.5793, 38, 25.0457)
        path.addLine(to: p(38, 27.6516))
        c(38, 31.5489, 38, 33.4975, 37.4642, 35.0677)
        c(36.4638, 37.9995, 34.1612, 40.3022, 31.2294, 41.3026)
        c(29.6591, 41.8384, 27.7105, 41.8384, 23.8132, 41.8384)
        path.addLine(to: p(16, 41.8384))
        c(10.3995, 41.8384, 7.5992, 41.8384, 5.4601, 40.7484)
        c(3.5785, 39.7897, 2.0487, 38.2599, 1.0899, 36.3783)
        c(0, 34.2392, 0, 31.4389, 0, 25.8384)
        path.close()
        return path
    }

    /// Lays the bubble out left of `arrow` (the line's frame grown 3 pt across and 8 pt along) and under it, or above
    /// it when there's no room below, in a container of `size`.
    func layout(arrow: CGRect, in size: CGSize) {
        let insets: CGFloat = 8
        let iconSide: CGFloat = 32
        let textSize = label.sizeThatFits(CGSize(
            width: min(200, size.width - iconSide - 8),
            height: .greatestFiniteMagnitude,
        ))
        let contentHeight = max(iconSide, ceil(textSize.height))
        let contentSize = CGSize(
            width: insets * 2 + iconSide + 8 + ceil(textSize.width),
            height: insets * 2 + contentHeight,
        )
        var content = CGRect(origin: CGPoint(x: arrow.minX - contentSize.width, y: arrow.maxY), size: contentSize)
        if content.minX < 0 { content.origin.x = arrow.maxX }
        let backgroundFrame: CGRect
        if content.maxY > size.height {
            content.origin.y = arrow.minY - content.height - 4
            backgroundMask.image = Self.invertedMaskImage
            backgroundFrame = CGRect(
                x: content.minX, y: content.minY - 1, width: content.width + 4, height: content.height + 8,
            )
        } else {
            backgroundMask.image = Self.maskImage
            backgroundFrame = CGRect(
                x: content.minX, y: content.minY - 4, width: content.width + 4, height: content.height + 4,
            )
        }
        background.frame = backgroundFrame
        backgroundMask.frame = CGRect(origin: .zero, size: backgroundFrame.size)
        icon.frame = CGRect(
            x: content.minX + insets, y: content.minY + insets + floor((contentHeight - iconSide) / 2),
            width: iconSide, height: iconSide,
        )
        label.frame = CGRect(
            x: content.minX + insets + iconSide + 8,
            y: content.minY + insets + floor((contentHeight - ceil(textSize.height)) / 2),
            width: ceil(textSize.width),
            height: ceil(textSize.height),
        )
    }
}

// MARK: - SparseScrollingTooltipIcon

/// ScrollingTooltipAnimationComponent: two columns of 12 pt squares scrolling to a random place each second (then a
/// 0.3 s rest), faded at the top and bottom, with a small scroll bar and its capsule following.
final class SparseScrollingTooltipIcon: UIView {
    private var progress: CGFloat = 0
    private var from: CGFloat = 0
    private var to = CGFloat.random(in: 0...1)
    private var start: CFTimeInterval = 0
    private var displayLink: CADisplayLink?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = nil
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        guard window != nil else { return }
        start = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let itemSize: CGFloat = 12
        let spacing: CGFloat = 1
        let listHeight = itemSize * 100 + spacing * 99
        let offset = progress * listHeight
        context.setFillColor(UIColor(white: 1, alpha: 0.3).cgColor)
        var index = Int(floor(offset / (itemSize + spacing)))
        while true {
            let y = CGFloat(index) * (itemSize + spacing) - offset
            if y >= bounds.height { break }
            for column in 0..<2 {
                UIBezierPath(
                    roundedRect: CGRect(
                        x: CGFloat(column) * (itemSize + spacing),
                        y: y,
                        width: itemSize,
                        height: itemSize,
                    ),
                    cornerRadius: 2,
                ).fill()
            }
            index += 1
        }
        let fade = 10 / bounds.height
        var locations: [CGFloat] = [0, fade, 1 - fade, 1]
        let colors = [
            UIColor.white,
            UIColor.white.withAlphaComponent(0),
            UIColor.white.withAlphaComponent(0),
            UIColor.white,
        ]
            .map(\.cgColor)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: &locations,
        ) {
            context.setBlendMode(.destinationOut)
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: bounds.height), options: [])
            context.setBlendMode(.normal)
        }
        context.setFillColor(UIColor.white.cgColor)
        let indicatorHeight: CGFloat = 10
        let indicatorX = (itemSize + spacing) * 2
        let indicatorY = (bounds.height - indicatorHeight) * progress
        UIBezierPath(
            roundedRect: CGRect(x: indicatorX, y: indicatorY, width: 3, height: indicatorHeight), cornerRadius: 1.5,
        ).fill()
        UIBezierPath(
            roundedRect: CGRect(x: indicatorX - 23, y: indicatorY + 1, width: 19, height: 8), cornerRadius: 4,
        ).fill()
    }

    @objc private func step() {
        let elapsed = CACurrentMediaTime() - start
        if elapsed >= 1.3 {
            from = to
            to = .random(in: 0...1)
            start = CACurrentMediaTime()
        }
        let t = CGFloat(min(1, elapsed / 1.0))
        // listViewAnimationCurveEaseInOut
        let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        progress = from + (to - from) * eased
        setNeedsDisplay()
    }
}
