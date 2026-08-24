// VoiceRecordingTrimView.swift

import UIKit

final class VoiceRecordingTrimView: UIView {
    var onRangeChange: ((Double, Double, Bool, Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        configure(handle: startHandle, updatedEnd: false)
        configure(handle: endHandle, updatedEnd: true)
        addSubview(startHandle)
        addSubview(endHandle)
        accessibilityElements = [startHandle, endHandle]
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(duration: Double, range: Range<Double>) {
        self.duration = max(0, duration)
        lowerBound = max(0, min(range.lowerBound, self.duration))
        upperBound = max(lowerBound, min(range.upperBound, self.duration))
        isHidden = self.duration < minimumVisibleDuration
        setNeedsLayout()
        setNeedsDisplay()
        updateAccessibilityValues()
    }

    func setEditingEnabled(_ enabled: Bool) {
        guard editingEnabled != enabled else { return }
        editingEnabled = enabled
        isUserInteractionEnabled = enabled
        startHandle.isEnabled = enabled
        endHandle.isEnabled = enabled
        accessibilityElementsHidden = !enabled
    }

    func setMinimumVisibleDuration(_ duration: Double) {
        minimumVisibleDuration = max(0, duration)
        isHidden = self.duration < minimumVisibleDuration
    }

    func setMinimumSelectionWidth(_ width: CGFloat) {
        minimumSelectionWidth = max(0, width)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let startX = xPosition(for: lowerBound)
        let endX = xPosition(for: upperBound)
        let handleWidth = CGFloat(12)
        startHandle.frame = CGRect(
            x: startX - handleWidth / 2,
            y: 0,
            width: handleWidth,
            height: bounds.height,
        )
        endHandle.frame = CGRect(
            x: endX - handleWidth / 2,
            y: 0,
            width: handleWidth,
            height: bounds.height,
        )
    }

    override func draw(_ rect: CGRect) {
        guard duration > 0, let context = UIGraphicsGetCurrentContext() else { return }
        let startX = xPosition(for: lowerBound)
        let endX = xPosition(for: upperBound)
        context.setFillColor(UIColor.systemBackground.withAlphaComponent(0.58).cgColor)
        context.fill(CGRect(x: rect.minX, y: rect.minY, width: max(0, startX - rect.minX), height: rect.height))
        context.fill(CGRect(x: endX, y: rect.minY, width: max(0, rect.maxX - endX), height: rect.height))
        context.setStrokeColor(UIColor.systemBlue.cgColor)
        context.setLineWidth(2)
        context.move(to: CGPoint(x: startX, y: rect.minY + 1))
        context.addLine(to: CGPoint(x: endX, y: rect.minY + 1))
        context.move(to: CGPoint(x: startX, y: rect.maxY - 1))
        context.addLine(to: CGPoint(x: endX, y: rect.maxY - 1))
        context.strokePath()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let startHit = startHandle.hitTest(convert(point, to: startHandle), with: event)
        let endHit = endHandle.hitTest(convert(point, to: endHandle), with: event)
        switch (startHit, endHit) {
        case let (start?, end?):
            let startDistance = abs(point.x - startHandle.frame.midX)
            let endDistance = abs(point.x - endHandle.frame.midX)
            return startDistance <= endDistance ? start : end
        case let (start?, nil):
            return start
        case let (nil, end?):
            return end
        case (nil, nil):
            return nil
        }
    }

    private let startHandle = VoiceRecordingTrimHandle()
    private let endHandle = VoiceRecordingTrimHandle()
    private var duration = 0.0
    private var lowerBound = 0.0
    private var upperBound = 0.0
    private var editingEnabled = true
    private var minimumVisibleDuration = 2.0
    private var minimumSelectionWidth = CGFloat(56)

    private var effectiveMinimumDuration: Double {
        guard duration > 0, bounds.width > 0 else { return min(1, duration) }
        return min(duration, max(1, Double(minimumSelectionWidth) * duration / Double(bounds.width)))
    }

    private func configure(handle: VoiceRecordingTrimHandle, updatedEnd: Bool) {
        handle.accessibilityLabel = updatedEnd ? "Trim end" : "Trim start"
        handle.onMove = { [weak self] location, finished in
            self?.moveHandle(updatedEnd: updatedEnd, location: location, finished: finished)
        }
        handle.onAccessibilityStep = { [weak self] direction in
            guard let self else { return }
            let current = updatedEnd ? upperBound : lowerBound
            moveHandle(
                updatedEnd: updatedEnd,
                time: current + Double(direction) * 0.5,
                finished: true,
            )
        }
    }

    private func moveHandle(updatedEnd: Bool, location: CGFloat, finished: Bool) {
        moveHandle(updatedEnd: updatedEnd, time: time(for: location), finished: finished)
    }

    private func moveHandle(updatedEnd: Bool, time: Double, finished: Bool) {
        let minimumDuration = effectiveMinimumDuration
        if updatedEnd {
            upperBound = max(lowerBound + minimumDuration, min(duration, time))
        } else {
            lowerBound = min(upperBound - minimumDuration, max(0, time))
        }
        setNeedsLayout()
        setNeedsDisplay()
        updateAccessibilityValues()
        onRangeChange?(lowerBound, upperBound, updatedEnd, finished)
    }

    private func xPosition(for time: Double) -> CGFloat {
        guard duration > 0 else { return trackMinimumX }
        return trackMinimumX + CGFloat(time / duration) * max(0, trackMaximumX - trackMinimumX)
    }

    private func time(for xPosition: CGFloat) -> Double {
        let trackWidth = max(1, trackMaximumX - trackMinimumX)
        let progress = min(1, max(0, (xPosition - trackMinimumX) / trackWidth))
        return Double(progress) * duration
    }

    private var trackMinimumX: CGFloat { 6 }
    private var trackMaximumX: CGFloat { max(trackMinimumX, bounds.width - 6) }

    private func updateAccessibilityValues() {
        startHandle.accessibilityValue = format(lowerBound)
        endHandle.accessibilityValue = format(upperBound)
    }

    private func format(_ value: Double) -> String {
        let clippedValue = max(0, value)
        let minutes = Int(clippedValue) / 60
        let seconds = clippedValue - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, seconds)
    }
}

private final class VoiceRecordingTrimHandle: UIControl {
    var onMove: ((CGFloat, Bool) -> Void)?
    var onAccessibilityStep: ((CGFloat) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBlue
        isExclusiveTouch = true
        layer.cornerRadius = 3
        isAccessibilityElement = true
        accessibilityTraits = [.adjustable]
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        gesture.minimumPressDuration = 0
        gesture.allowableMovement = .greatestFiniteMagnitude
        addGestureRecognizer(gesture)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -16, dy: -8).contains(point)
    }

    override func accessibilityIncrement() {
        onAccessibilityStep?(1)
    }

    override func accessibilityDecrement() {
        onAccessibilityStep?(-1)
    }

    @objc private func handlePan(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            lastLocation = gesture.location(in: superview).x
            onMove?(lastLocation, false)
        case .ended, .cancelled, .failed:
            lastLocation = gesture.location(in: superview).x
            onMove?(lastLocation, true)
        case .possible:
            break
        @unknown default:
            onMove?(lastLocation, true)
        }
    }

    private var lastLocation = CGFloat.zero
}
