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
    weak var scrollView: UIScrollView?

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
        layoutIndicators()
    }

    func hide(animated: Bool) {
        hideWork?.cancel()
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
        let lineWidth: CGFloat = isDragging ? 6 : 3
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
            x: bounds.width - 12 - size.width - grabOffset,
            y: travel.minY * (1 - fraction) + travel.maxY * fraction,
        )
        label.frame = capsule.contentView.bounds
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
