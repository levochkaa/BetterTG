// StoryVideoScrubber.swift

import AVFoundation
import UIKit

// MARK: - StoryVideoScrubber

/// MediaScrubberComponent's editor track for a story video: the video's frames along a 39 pt strip with 9 pt corners,
/// dimmed outside the trimmed part, which white 14 pt handles with dark capsules and a white border mark; a handle or
/// the border turns 0xffd300 while dragged. The part is 1 to 60 seconds long (storyMaxVideoDuration); dragging inside
/// it moves it whole. The playback cursor, a 2 by 42 pt white bar with a shadow, follows the player.
final class StoryVideoScrubber: UIView {
    static let height: CGFloat = 39

    private static let handleWidth: CGFloat = 14
    private static let borderHeight: CGFloat = 1 + 1 / 3
    private static let minimumDuration: Double = 1
    private static let maximumDuration: Double = 60

    /// The trimmed part changed: its bounds, which edge moved (nil for the whole part), and whether the drag ended.
    var onTrim: ((ClosedRange<Double>, Bool?, Bool) -> Void)?

    private(set) var range: ClosedRange<Double>

    private let duration: Double
    private let dimmedFrames = UIView()
    private let frames = UIView()
    private let framesMask = CALayer()
    private let leftHandle = UIImageView()
    private let rightHandle = UIImageView()
    private let leftCapsule = UIView()
    private let rightCapsule = UIView()
    private let border = UIImageView()
    private let zone = UIView()
    private let cursor = UIImageView()
    private var position: Double = 0
    private var dragStart: (location: CGFloat, range: ClosedRange<Double>)?
    private var isDragging = false

    // MARK: Frames

    private var frameImages = [UIImage]()
    private var frameAspect: CGFloat = 9 / 16

    init(asset: AVAsset, duration: Double, range: ClosedRange<Double>) {
        self.duration = duration
        self.range = range
        super.init(frame: CGRect(x: 0, y: 0, width: 300, height: Self.height))
        for container in [dimmedFrames, frames] {
            container.clipsToBounds = true
            container.layer.cornerRadius = 9
            container.isUserInteractionEnabled = false
            addSubview(container)
        }
        dimmedFrames.alpha = 0.35
        frames.layer.mask = framesMask
        framesMask.backgroundColor = UIColor.white.cgColor
        addSubview(zone)
        let handleImage = Self.handleImage()
        for (handle, capsule) in [(leftHandle, leftCapsule), (rightHandle, rightCapsule)] {
            handle.image = handleImage
            handle.tintColor = .white
            handle.isUserInteractionEnabled = true
            capsule.backgroundColor = UIColor(red: 0x34 / 255, green: 0x34 / 255, blue: 0x36 / 255, alpha: 1)
            capsule.layer.cornerRadius = 1
            handle.addSubview(capsule)
            addSubview(handle)
        }
        border.image = Self.borderImage()
        border.tintColor = .white
        addSubview(border)
        cursor.image = Self.cursorImage()
        cursor.isUserInteractionEnabled = false
        addSubview(cursor)
        for (view, action) in [
            (leftHandle, #selector(leftDragged(_:))),
            (rightHandle, #selector(rightDragged(_:))),
            (zone, #selector(zoneDragged(_:))),
        ] {
            let press = UILongPressGestureRecognizer(target: self, action: action)
            press.minimumPressDuration = 0
            press.allowableMovement = .infinity
            view.addGestureRecognizer(press)
        }
        loadFrames(asset)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The handles' hit areas reach 9 pt either side and 8 pt up and down, as hitTestSlop gives them.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -9, dy: -8).contains(point) || super.point(inside: point, with: event)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for handle in [leftHandle, rightHandle] where handle.frame.insetBy(dx: -9, dy: -8).contains(point) {
            return handle
        }
        return super.hitTest(point, with: event)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dimmedFrames.frame = bounds
        frames.frame = bounds
        layoutTrim()
        layoutFrames()
    }

    // MARK: Images

    /// The editor handle: white, rounded 9 pt outside, with a 3 pt lip over the frames.
    private static func handleImage() -> UIImage {
        let size = CGSize(width: handleWidth, height: height)
        return UIGraphicsImageRenderer(size: size)
            .image { context in
                let cg = context.cgContext
                cg.setFillColor(UIColor.white.cgColor)
                cg.addPath(UIBezierPath(
                    roundedRect: CGRect(x: 0, y: 0, width: size.width * 2, height: size.height),
                    cornerRadius: 9,
                ).cgPath)
                cg.fillPath()
                cg.setBlendMode(.clear)
                cg.addPath(UIBezierPath(
                    roundedRect: CGRect(
                        x: handleWidth - 3,
                        y: borderHeight,
                        width: handleWidth,
                        height: size.height - borderHeight * 2,
                    ),
                    cornerRadius: 2,
                ).cgPath)
                cg.fillPath()
            }
            .withRenderingMode(.alwaysTemplate)
    }

    private static func borderImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: height))
            .image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1, height: borderHeight))
                context.fill(CGRect(x: 0, y: height - borderHeight, width: 1, height: borderHeight))
            }
            .withRenderingMode(.alwaysTemplate)
            .resizableImage(withCapInsets: UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0))
    }

    /// The playback cursor: a 2 by 42 pt white bar with a shadow, 6 pt in.
    private static func cursorImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: handleWidth, height: 50)).image { context in
            let cg = context.cgContext
            cg.setShadow(offset: .zero, blur: 2, color: UIColor.black.withAlphaComponent(0.55).cgColor)
            cg.setFillColor(UIColor.white.cgColor)
            cg.addPath(UIBezierPath(roundedRect: CGRect(x: 6, y: 4, width: 2, height: 42), cornerRadius: 1).cgPath)
            cg.fillPath()
        }
    }

    func setPosition(_ seconds: Double) {
        position = seconds
        layoutCursor()
    }

    // MARK: Layout

    private func x(for seconds: Double) -> CGFloat {
        let width = Self.handleWidth
        return width / 2 + (bounds.width - width) * CGFloat(duration > 0 ? seconds / duration : 0)
    }

    private func seconds(for x: CGFloat) -> Double {
        let width = Self.handleWidth
        return Double((x - width / 2) / max(1, bounds.width - width)) * duration
    }

    private func layoutTrim() {
        let width = Self.handleWidth
        let height = bounds.height
        let left = CGRect(x: x(for: range.lowerBound) - width / 2, y: 0, width: width, height: height)
        let right = CGRect(
            x: max(left.maxX, x(for: range.upperBound) - width / 2),
            y: 0,
            width: width,
            height: height,
        )
        leftHandle.transform = .identity
        rightHandle.transform = .identity
        leftHandle.frame = left
        rightHandle.frame = right
        rightHandle.transform = CGAffineTransform(scaleX: -1, y: 1)
        let capsule = CGRect(x: 5 - 1 / 3, y: ((height - 12) / 2).rounded(.down), width: 3, height: 12)
        leftCapsule.frame = capsule
        rightCapsule.frame = capsule
        border.frame = CGRect(x: left.maxX, y: 0, width: max(0, right.minX - left.maxX), height: height)
        zone.frame = border.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        framesMask.frame = CGRect(x: left.minX, y: 0, width: right.maxX - left.minX, height: height)
        CATransaction.commit()
        let color = isDragging ? UIColor(red: 1, green: 0xD3 / 255, blue: 0, alpha: 1) : .white
        leftHandle.tintColor = color
        rightHandle.tintColor = color
        border.tintColor = color
        layoutCursor()
    }

    private func layoutCursor() {
        let fraction = duration > 0 ? CGFloat(position / duration) : 0
        let x = Self.handleWidth - 1 + (bounds.width - Self.handleWidth * 2 + 2) * fraction
        cursor.frame = CGRect(
            x: x - Self.handleWidth / 2,
            y: (bounds.height - 50) / 2,
            width: Self.handleWidth,
            height: 50,
        )
        cursor.isHidden = isDragging
    }

    /// The video's frames side by side across the strip, each as tall as it.
    private func loadFrames(_ asset: AVAsset) {
        Task { [weak self] in
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let (size, transform) = try? await track.load(.naturalSize, .preferredTransform)
            else { return }
            let upright = CGRect(origin: .zero, size: size).applying(transform).size
            let aspect = abs(upright.width) / max(1, abs(upright.height))
            guard let self else { return }
            frameAspect = aspect
            let count = max(1, Int(ceil(bounds.width / (Self.height * aspect))))
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 120, height: 120)
            let duration = duration
            let times = (0..<count).map { index in
                CMTime(seconds: duration * (Double(index) + 0.5) / Double(count), preferredTimescale: 600)
            }
            var images = [UIImage]()
            for await result in generator.images(for: times) {
                if let image = try? result.image { images.append(UIImage(cgImage: image)) }
            }
            frameImages = images
            layoutFrames()
        }
    }

    private func layoutFrames() {
        for container in [dimmedFrames, frames] {
            container.subviews.forEach { $0.removeFromSuperview() }
            let width = Self.height * frameAspect
            for (index, image) in frameImages.enumerated() {
                let view = UIImageView(image: image)
                view.contentMode = .scaleAspectFill
                view.clipsToBounds = true
                view.frame = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: Self.height)
                container.addSubview(view)
            }
        }
    }

    // MARK: Dragging

    @objc private func leftDragged(_ gesture: UILongPressGestureRecognizer) {
        drag(gesture) { start, delta in
            let lower = max(0, min(start.lowerBound + delta, start.upperBound - Self.minimumDuration))
            return max(lower, start.upperBound - Self.maximumDuration)...start.upperBound
        } edge: { true }
    }

    @objc private func rightDragged(_ gesture: UILongPressGestureRecognizer) {
        drag(gesture) { start, delta in
            let upper = min(duration, max(start.upperBound + delta, start.lowerBound + Self.minimumDuration))
            return start.lowerBound...min(upper, start.lowerBound + Self.maximumDuration)
        } edge: { false }
    }

    @objc private func zoneDragged(_ gesture: UILongPressGestureRecognizer) {
        drag(gesture) { start, delta in
            let length = start.upperBound - start.lowerBound
            let lower = max(0, min(start.lowerBound + delta, duration - length))
            return lower...lower + length
        } edge: { nil }
    }

    private func drag(
        _ gesture: UILongPressGestureRecognizer,
        update: (ClosedRange<Double>, Double) -> ClosedRange<Double>,
        edge: () -> Bool?,
    ) {
        let location = gesture.location(in: self).x
        switch gesture.state {
        case .began:
            dragStart = (location, range)
            isDragging = true
            layoutTrim()
        case .changed:
            guard let dragStart else { return }
            range = update(dragStart.range, seconds(for: location) - seconds(for: dragStart.location))
            layoutTrim()
            onTrim?(range, edge(), false)
        case .cancelled,
             .ended:
            dragStart = nil
            isDragging = false
            layoutTrim()
            onTrim?(range, edge(), true)
        default:
            break
        }
    }
}
