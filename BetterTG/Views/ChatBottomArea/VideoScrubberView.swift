// VideoScrubberView.swift

import AVFoundation
import UIKit

// MARK: - VideoScrubberView

/// TGMediaPickerGalleryVideoScrubber: a strip of frames across the video, cut to the crop and turned as it goes
/// (TGMediaPickerGalleryVideoScrubberThumbnailView), the trim frame (TGMediaPickerGalleryVideoTrimView) with dark
/// curtains over the cut parts, and the white playhead. Moving a trim handle seeks to its edge and keeps at least
/// `minimumLength`; the playhead scrubs inside the trim. Holding a handle or the playhead still for a quarter second
/// zooms the strip about it until a frame's interval spans the strip, with denser frames read for it, so a short trim
/// lands where it should; letting go zooms back out. As the cover picker (`cover`) it has no trim, and its playhead is
/// a frame-sized handle that a tap on the strip moves.
final class VideoScrubberView: UIView {
    // MARK: Private

    /// What the zoom keeps in place (`TGMediaPickerGalleryVideoScrubberPivotSource`).
    private enum ZoomPivotSource {
        case trimStart
        case trimEnd
        case handle
    }

    // MARK: Internal

    /// The 40 pt strip with room for the playhead, which reaches 4 pt past it.
    static let preferredHeight: CGFloat = 64

    /// `TGVideoScrubberPadding`.
    private static let padding: CGFloat = 8
    private static let stripHeight: CGFloat = 40
    /// TGMediaPickerGalleryVideoTrimView's handle width.
    private static let handleWidth: CGFloat = 12
    /// `TGVideoScrubberTrimRectEpsilon`: a trim this close to an end snaps to it.
    private static let trimRectEpsilon: CGFloat = 3
    private static let valueEpsilon = 0.001
    private static let playheadSize = CGSize(width: 5, height: 48)
    /// The cover picker's handle (`_scrubberHandle` with `cover`).
    private static let coverHandleSize = CGSize(width: 30, height: 48)
    /// The step of a VoiceOver swipe on a trim handle.
    private static let accessibilityStep = 1.0
    /// `TGVideoScrubberZoomActivationInterval`: how long a hold rests before the strip zooms.
    private static let zoomActivationInterval: TimeInterval = 0.25
    private static let zoomAnimationDuration: TimeInterval = 0.3

    var onBeginScrubbing: (() -> Void)?
    var onScrub: ((Double) -> Void)?
    var onEndScrubbing: (() -> Void)?
    var onBeginTrimming: (() -> Void)?
    /// A trim edge moved to this time, which the player shows (`editingStartValueDidChange`).
    var onTrimEdgeChanged: ((Double) -> Void)?
    var onEndTrimming: (() -> Void)?

    /// `TGVideoScrubberMinimumTrimDuration`.
    var minimumLength = VideoEditAdjustments.minimumTrimDuration

    private(set) var duration: Double = 0
    private(set) var trimStart: Double = 0
    private(set) var trimEnd: Double = 0
    private(set) var value: Double = 0
    private(set) var isScrubbing = false
    private(set) var isTrimming = false

    var allowsTrimming = true {
        didSet {
            trimView.isHidden = !allowsTrimming
            setNeedsLayout()
        }
    }

    /// TGMediaPickerGalleryVideoScrubber's `cover`: no trimming, the 30 pt outlined handle, and a tap on the strip
    /// that moves it (`handleTap:`).
    var isCoverPicker = false {
        didSet { applyCoverPicker() }
    }

    private let wrapperView = ExpandedHitView()
    private let stripView = UIView()
    private let leftCurtainView = UIView()
    private let rightCurtainView = UIView()
    private let trimView = VideoTrimFrameView()
    private let playheadView = ExpandedHitView()
    private let playheadImageView = UIImageView(image: VideoScrubberView.playheadImage())
    private let stripTapGesture = UITapGestureRecognizer()

    private var asset: AVAsset?
    /// The displayed frame's size, which the crop is measured in (`videoScrubberOriginalSize:`).
    private var frameSize = CGSize(width: 1, height: 1)
    /// The crop the frames show; `nil` for the whole frame upright.
    private var crop: PhotoCropAdjustments?
    /// The strip's own frames (`_summaryThumbnailViews`) at `summaryTimes`.
    private var thumbnailViews = [VideoScrubberThumbnailView]()
    private var summaryTimes = [Double]()
    /// `_summaryThumbnailSnapshotView`: the old frames over the new ones until they load.
    private var thumbnailSnapshotView: UIView?
    private var thumbnailTask: Task<Void, Never>?
    private var loadedStripWidth: CGFloat = 0
    private var trimInteractionBegan = false
    private var trimInteractionEnded = false
    private var scrubInteractionBegan = false
    private var scrubInteractionEnded = false

    /// The frames read for the zoom under the strip's own (`_zoomedThumbnailViews`) at `zoomedTimes`.
    private var zoomedThumbnailViews = [VideoScrubberThumbnailView]()
    private var zoomedTimes = [Double]()
    private var zoomTask: Task<Void, Never>?
    private var isZoomedIn = false
    private var isPreparingToZoomIn = false
    private var isAnimatingZoomIn = false
    private var isAnimatingZoomOut = false
    /// Tells a finished zoom-out animation whether the zoom it ended is still the one on screen.
    private var zoomGeneration = 0
    private var pivotSource = ZoomPivotSource.handle
    /// The interval between two of the strip's frames, which the zoomed strip's width shows.
    private var zoomedDuration: Double = 0
    private var zoomPivotPosition: Double = 0
    /// The pivot's place in the strip, which stays put as the strip zooms.
    private var zoomPivotCenter: CGFloat = 0
    /// How far the pivot's frame moves with the zoom.
    private var zoomPivotOffset: CGFloat = 0
    private var zoomedPivotIndex = -1

    /// `hasTrimming`: the handles left the video's ends.
    var hasTrimming: Bool {
        allowsTrimming && (trimStart > Self.valueEpsilon || trimEnd < duration - Self.valueEpsilon)
    }

    /// The crop the frames show, the whole frame without one (`videoScrubberOriginalSize:cropRect:`).
    private var displayedCrop: PhotoCropAdjustments {
        crop ?? PhotoCropAdjustments(originalSize: frameSize)
    }

    /// `_thumbnailSize`: 40 pt high, as wide as the crop turned, its own width at least half its height
    /// (`reloadThumbnails`' `frameAspectRatio`).
    private var thumbnailSize: CGSize {
        let crop = displayedCrop
        let rect = crop.cropRect
        var aspectRatio = rect.width > 0 && rect.height > 0 ? max(0.5, rect.width / rect.height) : 1
        if crop.orientation.isSideward {
            aspectRatio = 1 / aspectRatio
        }
        return CGSize(width: ceil(Self.stripHeight * aspectRatio), height: Self.stripHeight)
    }

    /// `zoomAvailable`: one zoom at a time, over the strip's frames, for a video longer than a second.
    private var zoomAvailable: Bool {
        !isZoomedIn && !isPreparingToZoomIn && !summaryTimes.isEmpty && duration > 1
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
        configureGestures()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let wrapperFrame = CGRect(
            x: Self.padding,
            y: ((bounds.height - Self.stripHeight) / 2).rounded(.down),
            width: max(0, bounds.width - Self.padding * 2),
            height: Self.stripHeight,
        )
        if wrapperFrame.size != wrapperView.frame.size {
            discardZoom()
        }
        wrapperView.frame = wrapperFrame
        stripView.frame = wrapperView.bounds
        // The zoom keeps its own layout until it ends.
        guard !isZoomedIn else { return }
        if !isTrimming {
            layoutTrimView(zoomedIn: false)
        }
        layoutThumbnails(forZoom: false)
        reloadThumbnailsIfNeeded()
        if !isScrubbing, !isTrimming {
            updatePlayheadPosition(zoomedIn: false)
        }
    }

    // MARK: Drawing

    /// The playhead: a 2 pt white bar with a faint dark shadow.
    private static func playheadImage() -> UIImage {
        UIGraphicsImageRenderer(size: playheadSize).image { context in
            let cgContext = context.cgContext
            cgContext.setShadow(offset: .zero, blur: 0.5, color: UIColor(white: 0, alpha: 0.65).cgColor)
            UIColor.white.setFill()
            UIBezierPath(
                roundedRect: CGRect(x: (playheadSize.width - 2) / 2, y: 1.5, width: 2, height: playheadSize.height - 3),
                cornerRadius: 2,
            ).fill()
        }
    }

    /// `_stringFromTotalSeconds:`.
    private static func timeString(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600
        let minutes = total / 60 % 60
        let remainder = total % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }

    /// The cover picker's handle: a rounded white outline 2 pt less a hairline wide, with the playhead's shadow.
    private static func coverHandleImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        // `TGSeparatorHeight`: a hairline of the screen.
        let lineWidth = 2 - 1 / max(1, format.scale)
        return UIGraphicsImageRenderer(size: coverHandleSize, format: format).image { context in
            let cgContext = context.cgContext
            cgContext.setShadow(offset: .zero, blur: 0.5, color: UIColor(white: 0, alpha: 0.65).cgColor)
            let path = UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: coverHandleSize).insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
                cornerRadius: 8,
            )
            path.lineWidth = lineWidth
            UIColor.white.setStroke()
            path.stroke()
        }
    }

    /// The video to scrub and its trim; `frameSize` is its displayed frame's size.
    func configure(asset: AVAsset, duration: Double, frameSize: CGSize, trimRange: ClosedRange<Double>?) {
        discardZoom()
        self.asset = asset
        self.duration = max(0, duration)
        let hasFrame = frameSize.width.isFinite && frameSize.height.isFinite && frameSize.width > 0
            && frameSize.height > 0
        self.frameSize = hasFrame ? frameSize : CGSize(width: 1, height: 1)
        crop = nil
        trimStart = min(max(0, trimRange?.lowerBound ?? 0), self.duration)
        trimEnd = min(max(trimStart, trimRange?.upperBound ?? self.duration), self.duration)
        value = trimStart
        loadedStripWidth = 0
        trimView.setHighlighted(hasTrimming, animated: false)
        updateAccessibilityValues()
        setNeedsLayout()
    }

    /// `updateThumbnails`: the frames take the crop, crossfading from the old ones; a crop of another shape
    /// reloads them, the old ones staying until the new ones load (`reloadDataAndReset:false`).
    func setCrop(_ newCrop: PhotoCropAdjustments?) {
        guard newCrop != crop else { return }
        discardZoom()
        let oldSize = thumbnailSize
        crop = newCrop
        guard !thumbnailViews.isEmpty else { return }
        addThumbnailSnapshot()
        if thumbnailSize == oldSize {
            let crop = displayedCrop
            for view in thumbnailViews {
                view.crop = crop
            }
            fadeOutThumbnailSnapshot()
        } else {
            loadedStripWidth = 0
            setNeedsLayout()
        }
    }

    /// `setValue:resetPosition:`: the player's position, ignored while the playhead is held.
    func setPlaybackPosition(_ newValue: Double) {
        guard duration > Self.valueEpsilon, !isScrubbing else { return }
        value = min(max(0, newValue), duration)
        if !isTrimming {
            updatePlayheadPosition(zoomedIn: isZoomedIn)
        }
    }

    /// `resetToStart`.
    func resetToStart() {
        value = trimStart
        let rect = scrubbingRect()
        playheadView.center.x = trimView.frame.minX + rect.minX + playheadView.bounds.width / 2
    }

    /// The cover picker's `trimStartValue` and `trimEndValue`, the main scrubber's trim, which a tap keeps the handle
    /// inside.
    func setTrimRange(_ range: ClosedRange<Double>) {
        trimStart = min(max(0, range.lowerBound), duration)
        trimEnd = min(max(trimStart, range.upperBound), duration)
        setNeedsLayout()
    }

    private func configureViews() {
        wrapperView.hitInsets = UIEdgeInsets(top: -5, left: -10, bottom: -5, right: -10)
        addSubview(wrapperView)
        stripView.clipsToBounds = true
        stripView.layer.cornerRadius = 9
        stripView.layer.cornerCurve = .continuous
        stripView.backgroundColor = UIColor(white: 0.2, alpha: 1)
        stripView.isUserInteractionEnabled = false
        wrapperView.addSubview(stripView)
        // The curtains' rounded outer ends match the strip's.
        for (curtain, corners) in [
            (leftCurtainView, CACornerMask([.layerMinXMinYCorner, .layerMinXMaxYCorner])),
            (rightCurtainView, CACornerMask([.layerMaxXMinYCorner, .layerMaxXMaxYCorner])),
        ] {
            curtain.backgroundColor = UIColor.black.withAlphaComponent(0.8)
            curtain.layer.cornerRadius = 9
            curtain.layer.maskedCorners = corners
            curtain.isUserInteractionEnabled = false
            wrapperView.addSubview(curtain)
        }
        trimView.isExclusiveTouch = true
        wrapperView.addSubview(trimView)
        playheadView.frame = CGRect(origin: CGPoint(x: 0, y: -4), size: Self.playheadSize)
        playheadView.hitInsets = UIEdgeInsets(top: -5, left: -12, bottom: -5, right: -12)
        playheadImageView.frame = playheadView.bounds
        playheadView.addSubview(playheadImageView)
        playheadView.isAccessibilityElement = false
        wrapperView.addSubview(playheadView)

        trimView.leftHandle.accessibilityLabel = L10n.betterTG("Accessibility.VideoEditor.TrimStart")
        trimView.rightHandle.accessibilityLabel = L10n.betterTG("Accessibility.VideoEditor.TrimEnd")
        trimView.leftHandle.onAccessibilityAdjust = { [weak self] step in
            self?.adjustTrim(start: true, by: step * Self.accessibilityStep)
        }
        trimView.rightHandle.onAccessibilityAdjust = { [weak self] step in
            self?.adjustTrim(start: false, by: step * Self.accessibilityStep)
        }
    }

    private func configureGestures() {
        for handle in [trimView.leftHandle, trimView.rightHandle] {
            let press = UILongPressGestureRecognizer(target: self, action: #selector(handleTrimPress(_:)))
            press.minimumPressDuration = 0.1
            press.delegate = self
            handle.addGestureRecognizer(press)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleTrimPan(_:)))
            pan.delegate = self
            handle.addGestureRecognizer(pan)
        }
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePlayheadPress(_:)))
        press.minimumPressDuration = 0.1
        press.delegate = self
        playheadView.addGestureRecognizer(press)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePlayheadPan(_:)))
        pan.delegate = self
        playheadView.addGestureRecognizer(pan)
        stripTapGesture.addTarget(self, action: #selector(handleStripTap(_:)))
        stripTapGesture.isEnabled = false
        stripView.addGestureRecognizer(stripTapGesture)
    }

    /// The cover picker's look and touches; the trim's are the main scrubber's.
    private func applyCoverPicker() {
        allowsTrimming = !isCoverPicker
        let size = isCoverPicker ? Self.coverHandleSize : Self.playheadSize
        playheadView.frame = CGRect(origin: CGPoint(x: playheadView.frame.minX, y: -4), size: size)
        playheadImageView.frame = playheadView.bounds
        playheadImageView.image = isCoverPicker ? Self.coverHandleImage() : Self.playheadImage()
        stripView.isUserInteractionEnabled = isCoverPicker
        stripTapGesture.isEnabled = isCoverPicker
        setNeedsLayout()
    }

    // MARK: Geometry

    /// `_scrubbingRectZoomedIn:` in the strip's coordinates: the width between the handles, or zoomed, as many
    /// times wider as the video is longer than the zoomed interval, about the pivot. `nil` is the current one
    /// (`_scrubbingRect`).
    private func scrubbingRect(zoomedIn: Bool? = nil) -> CGRect {
        let handle = allowsTrimming ? Self.handleWidth : 0
        var origin = handle
        var width = max(1, wrapperView.bounds.width - handle * 2)
        if zoomedIn ?? isZoomedIn {
            let interval = zoomedDuration > Self.valueEpsilon ? zoomedDuration : duration
            let zoomedWidth = width * CGFloat(duration / max(interval, Self.valueEpsilon))
            origin += zoomPivotCenter - zoomPivotCenter * zoomedWidth / width
            width = zoomedWidth
        }
        return CGRect(x: origin, y: 0, width: width, height: Self.stripHeight)
    }

    /// `_trimFrameForStartPosition:endPosition:duration:zoomedIn:`: the frame spans both handles around the kept
    /// part.
    private func trimFrame(start: Double, end: Double, zoomedIn: Bool) -> CGRect {
        guard duration > Self.valueEpsilon else { return wrapperView.bounds }
        let rect = scrubbingRect(zoomedIn: zoomedIn)
        let normalRect = scrubbingRect(zoomedIn: false)
        let minX = CGFloat(start / duration) * rect.width + rect.minX - normalRect.minX
        let maxX = CGFloat(end / duration) * rect.width + rect.minX + normalRect.minX
        return CGRect(x: minX, y: 0, width: maxX - minX, height: Self.stripHeight)
    }

    /// `_trimStartPosition:trimEndPosition:forTrimFrame:`.
    private func trimPositions(for frame: CGRect) -> (start: Double, end: Double) {
        let rect = scrubbingRect()
        let start = Double((frame.minX + Self.handleWidth - rect.minX) / rect.width) * duration
        let end = Double((frame.maxX - Self.handleWidth - rect.minX) / rect.width) * duration
        return (start, end)
    }

    /// `_scrubberPositionForPosition:duration:zoomedIn:`.
    private func playheadCenterX(for position: Double, zoomedIn: Bool) -> CGFloat {
        let rect = scrubbingRect(zoomedIn: zoomedIn)
        let width = playheadView.bounds.width
        let fraction = duration > Self.valueEpsilon ? CGFloat(position / duration) : 0
        return width / 2 + rect.minX + fraction * (rect.width - width)
    }

    /// `_positionForScrubberPosition:duration:`.
    private func position(forPlayheadCenterX centerX: CGFloat) -> Double {
        let rect = scrubbingRect()
        let width = playheadView.bounds.width
        return Double((centerX - width / 2 - rect.minX) / max(1, rect.width - width)) * duration
    }

    /// `_layoutTrimViewZoomedIn:`.
    private func layoutTrimView(zoomedIn: Bool) {
        trimView.frame = trimFrame(start: trimStart, end: trimEnd, zoomedIn: zoomedIn)
        layoutCurtains(zoomedIn: zoomedIn)
    }

    /// `_layoutTrimCurtainViews`: the curtains reach from the video's ends under the handles' rounded outer edges.
    private func layoutCurtains(zoomedIn: Bool) {
        leftCurtainView.isHidden = !allowsTrimming
        rightCurtainView.isHidden = !allowsTrimming
        guard allowsTrimming else { return }
        let rect = scrubbingRect(zoomedIn: zoomedIn)
        let normalRect = scrubbingRect(zoomedIn: false)
        let trim = trimView.frame
        leftCurtainView.frame = CGRect(
            x: rect.minX - 12,
            y: 0,
            width: max(0, trim.minX - rect.minX + normalRect.minX + 11),
            height: Self.stripHeight,
        )
        rightCurtainView.frame = CGRect(
            x: trim.maxX - 7,
            y: 0,
            width: max(0, rect.width - trim.maxX + normalRect.minX + 19),
            height: Self.stripHeight,
        )
    }

    /// `_updateScrubberAnimationsAndResetCurrentPosition:zoomedIn:` without the animation: the playhead at the
    /// value, against a handle's inner edge when the value is at the trim's start or end.
    private func updatePlayheadPosition(zoomedIn: Bool) {
        guard duration > Self.valueEpsilon else { return }
        let normalRect = scrubbingRect(zoomedIn: false)
        let width = playheadView.bounds.width
        var x = floor(playheadCenterX(for: value, zoomedIn: zoomedIn)) - width / 2
        // The cover picker's handle isn't held against a trim it doesn't show.
        if allowsTrimming, trimStart > Self.valueEpsilon, abs(value - trimStart) < 0.01 {
            x = trimView.frame.minX + normalRect.minX
        } else if allowsTrimming, abs(value - trimEnd) < 0.01 {
            x = trimView.frame.maxX - normalRect.minX - width
        }
        playheadView.frame.origin = CGPoint(x: x, y: -4)
    }

    private func setPlayheadHidden(_ hidden: Bool, animated: Bool) {
        guard animated else {
            playheadView.isHidden = hidden
            playheadView.alpha = hidden ? 0 : 1
            return
        }
        playheadView.isHidden = false
        UIView.animate(withDuration: 0.25) {
            self.playheadView.alpha = hidden ? 0 : 1
        } completion: { finished in
            if finished {
                self.playheadView.isHidden = hidden
            }
        }
    }

    // MARK: Thumbnails

    /// `_layoutSummaryThumbnailViewsForZoom:`: the frames side by side, centered on the strip; for the zoom, the
    /// pivot's frame moves by the zoom's offset and the others spread from it as far apart as the read frames reach.
    private func layoutThumbnails(forZoom: Bool) {
        guard !thumbnailViews.isEmpty else { return }
        let size = thumbnailSize
        let totalWidth = size.width * CGFloat(thumbnailViews.count)
        let originX = (stripView.bounds.width - totalWidth) / 2
        guard forZoom, thumbnailViews.indices.contains(zoomedPivotIndex),
              let first = zoomedThumbnailViews.first?.frame, let last = zoomedThumbnailViews.last?.frame
        else {
            for (index, view) in thumbnailViews.enumerated() {
                view.frame = CGRect(
                    x: originX + size.width * CGFloat(index),
                    y: 0,
                    width: size.width,
                    height: size.height,
                )
            }
            return
        }
        let pivotIndex = zoomedPivotIndex
        let pivotX = originX + size.width * CGFloat(pivotIndex) + zoomPivotOffset
        let leftStep = pivotX - first.minX + first.width
        let rightStep = last.maxX - pivotX
        for (index, view) in thumbnailViews.enumerated() {
            var x = pivotX
            if index < pivotIndex {
                x = pivotX - leftStep * CGFloat(pivotIndex - index)
            } else if index > pivotIndex {
                x = pivotX + rightStep * CGFloat(index - pivotIndex)
            }
            view.frame = CGRect(x: x, y: 0, width: size.width, height: size.height)
        }
    }

    /// `_layoutZoomedThumbnailViewsStacked:`: the read frames under the pivot's frame, or side by side from it,
    /// the later ones after it and the earlier ones before it.
    private func layoutZoomedThumbnails(stacked: Bool) {
        guard !zoomedThumbnailViews.isEmpty, thumbnailViews.indices.contains(zoomedPivotIndex),
              summaryTimes.indices.contains(zoomedPivotIndex)
        else { return }
        let size = thumbnailSize
        let stack = thumbnailViews[zoomedPivotIndex].frame
        guard !stacked else {
            for view in zoomedThumbnailViews {
                view.frame = stack
            }
            return
        }
        let pivotTime = summaryTimes[zoomedPivotIndex]
        let frames = Array(zip(zoomedTimes, zoomedThumbnailViews))
        var step: CGFloat = 1
        for (time, view) in frames where time >= pivotTime {
            view.frame = CGRect(
                x: stack.minX + size.width * step + zoomPivotOffset,
                y: 0,
                width: size.width,
                height: size.height,
            )
            step += 1
        }
        step = 1
        for (time, view) in frames.reversed() where time < pivotTime {
            view.frame = CGRect(
                x: stack.minX - size.width * step + zoomPivotOffset,
                y: 0,
                width: size.width,
                height: size.height,
            )
            step += 1
        }
    }

    /// `reloadThumbnails`: enough evenly spaced frames of the crop's shape to cover the strip, read whole at the
    /// frame's own aspect and at most twice the strip's scale.
    private func reloadThumbnailsIfNeeded() {
        let width = stripView.bounds.width
        guard let asset, duration > Self.valueEpsilon, width > 0, width != loadedStripWidth else { return }
        discardZoom()
        loadedStripWidth = width
        thumbnailTask?.cancel()
        for view in thumbnailViews {
            view.removeFromSuperview()
        }
        let size = thumbnailSize
        let frameCount = max(1, Int(ceil(width / size.width)))
        let interval = duration / Double(frameCount)
        summaryTimes = (0..<frameCount).map { Double($0) * interval }
        let times = summaryTimes.map { CMTime(seconds: $0, preferredTimescale: 600) }
        let crop = displayedCrop
        thumbnailViews = times.map { _ in
            let view = VideoScrubberThumbnailView(crop: crop)
            stripView.addSubview(view)
            return view
        }
        if let thumbnailSnapshotView {
            stripView.bringSubviewToFront(thumbnailSnapshotView)
        }
        layoutThumbnails(forZoom: false)
        let generator = makeThumbnailGenerator(for: asset)
        thumbnailTask = Task { [weak self] in
            for await result in generator.images(for: times) {
                guard !Task.isCancelled else { return }
                guard let self, let image = try? result.image,
                      let index = times.firstIndex(of: result.requestedTime),
                      index < thumbnailViews.count
                else { continue }
                thumbnailViews[index].setImage(UIImage(cgImage: image), fadesIn: thumbnailSnapshotView == nil)
            }
            guard !Task.isCancelled else { return }
            self?.fadeOutThumbnailSnapshot()
        }
    }

    /// TGMediaAssetImageSignals' `videoThumbnailsForAVAsset:`: exact upright frames of the whole picture, sized
    /// by the frame's own aspect.
    private func makeThumbnailGenerator(for asset: AVAsset) -> AVAssetImageGenerator {
        let scale = min(2, traitCollection.displayScale)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(
            width: ceil(Self.stripHeight * frameSize.width / frameSize.height) * scale,
            height: Self.stripHeight * scale,
        )
        return generator
    }

    /// A picture of the strip as it is, over its frames.
    private func addThumbnailSnapshot() {
        guard thumbnailSnapshotView == nil, let snapshot = stripView.snapshotView(afterScreenUpdates: false) else {
            return
        }
        snapshot.frame = stripView.bounds
        snapshot.isUserInteractionEnabled = false
        stripView.addSubview(snapshot)
        thumbnailSnapshotView = snapshot
    }

    private func fadeOutThumbnailSnapshot() {
        guard let snapshot = thumbnailSnapshotView else { return }
        thumbnailSnapshotView = nil
        UIView.animate(withDuration: 0.2) {
            snapshot.alpha = 0
        } completion: { _ in
            snapshot.removeFromSuperview()
        }
    }

    // MARK: Zoom

    /// The hold starts over: a waiting zoom is dropped and another waits for the finger to rest
    /// (`performSelector:withObject:afterDelay:`).
    private func scheduleZoomIn(from source: ZoomPivotSource) {
        cancelZoomIn()
        guard zoomAvailable else { return }
        pivotSource = source
        perform(#selector(zoomIn), with: nil, afterDelay: Self.zoomActivationInterval)
    }

    /// `zoomIn`: the zoom spans the strip's frames on either side of the one nearest the pivot, with enough frames
    /// read across them to fill the strip, twice over past the second frame.
    @objc private func zoomIn() {
        guard zoomAvailable, let asset else { return }
        isPreparingToZoomIn = true
        let positions = trimPositions(for: trimView.frame)
        let normalRect = scrubbingRect(zoomedIn: false)
        switch pivotSource {
        case .trimStart:
            zoomPivotCenter = trimView.frame.minX
            zoomPivotPosition = positions.start
        case .trimEnd:
            zoomPivotCenter = trimView.frame.maxX - normalRect.minX * 2
            zoomPivotPosition = positions.end
        case .handle:
            // `_zoomPivotCenterForHandle`: the playhead's center, moved across its width with the value.
            let fraction = CGFloat(value / max(0.0001, duration)) * 2 - 1
            zoomPivotCenter = playheadView.center.x - normalRect.minX + fraction * playheadView.bounds.width / 2
            zoomPivotPosition = position(forPlayheadCenterX: playheadView.center.x)
        }
        if summaryTimes.count > 1 {
            zoomedDuration = summaryTimes[1] - summaryTimes[0]
        }
        var pivotIndex = 0
        var minimalInterval = Double.greatestFiniteMagnitude
        for (index, time) in summaryTimes.enumerated() where abs(time - zoomPivotPosition) < minimalInterval {
            minimalInterval = abs(time - zoomPivotPosition)
            pivotIndex = index
        }
        zoomedPivotIndex = pivotIndex
        let lastIndex = summaryTimes.count - 1
        let rightIndex = min(pivotIndex + 1, lastIndex)
        let startTime = summaryTimes[max(0, pivotIndex - 1)]
        let endTime = rightIndex == lastIndex ? duration : summaryTimes[rightIndex]
        let multiplier: CGFloat = pivotIndex > 1 ? 2.1 : 1
        let frameCount = Int(ceil(stripView.bounds.width / thumbnailSize.width * multiplier))
        guard frameCount >= 1, endTime >= startTime else {
            isPreparingToZoomIn = false
            resetZooming()
            return
        }
        // `videoScrubber:evenlySpacedTimestamps:startingAt:endingAt:`.
        let interval = (endTime - startTime) / Double(frameCount)
        zoomedTimes = (0..<frameCount).map { startTime + Double($0) * interval }
        let times = zoomedTimes.map { CMTime(seconds: $0, preferredTimescale: CMTimeScale(NSEC_PER_SEC)) }
        let crop = displayedCrop
        zoomedThumbnailViews = times.map { _ in
            let view = VideoScrubberThumbnailView(crop: crop)
            stripView.insertSubview(view, at: 0)
            return view
        }
        let generator = makeThumbnailGenerator(for: asset)
        zoomTask = Task { [weak self] in
            for await result in generator.images(for: times) {
                guard !Task.isCancelled else { return }
                guard let self, let image = try? result.image,
                      let index = times.firstIndex(of: result.requestedTime),
                      index < zoomedThumbnailViews.count
                else { continue }
                zoomedThumbnailViews[index].setImage(UIImage(cgImage: image), fadesIn: false)
            }
            guard !Task.isCancelled else { return }
            self?.commitZoomIn()
        }
    }

    /// `commitZoomIn`: the read frames spread out from under the pivot's frame as the strip's own frames move
    /// apart and the trim stretches with them, the pivot staying under the finger. The strip reaches past its ends
    /// while zoomed.
    private func commitZoomIn() {
        guard isPreparingToZoomIn, thumbnailViews.indices.contains(zoomedPivotIndex),
              summaryTimes.indices.contains(zoomedPivotIndex)
        else { return }
        isZoomedIn = true
        isPreparingToZoomIn = false
        isAnimatingZoomIn = true
        layoutZoomedThumbnails(stacked: true)
        let pivotTime = summaryTimes[zoomedPivotIndex]
        let normalPivotFrame = thumbnailViews[zoomedPivotIndex].frame
        let normalRect = scrubbingRect(zoomedIn: false)
        let zoomedRect = scrubbingRect(zoomedIn: true)
        let pivotFraction = CGFloat(pivotTime / max(0.0001, duration))
        let zoomedPivotPosition = (zoomedRect.width - thumbnailSize.width) * pivotFraction
        zoomPivotOffset = zoomedPivotPosition - normalPivotFrame.minX + zoomedRect.minX - normalRect.minX
        stripView.clipsToBounds = false
        UIView.animate(
            withDuration: Self.zoomAnimationDuration,
            delay: 0,
            options: [.curveEaseInOut, .layoutSubviews, .allowUserInteraction],
        ) {
            self.layoutZoomedThumbnails(stacked: false)
            self.layoutThumbnails(forZoom: true)
            self.layoutTrimView(zoomedIn: true)
        } completion: { _ in
            self.isAnimatingZoomIn = false
        }
    }

    /// `cancelZoomIn`: a waiting or loading zoom stops; one on screen stays.
    private func cancelZoomIn() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(zoomIn), object: nil)
        guard isPreparingToZoomIn else { return }
        isPreparingToZoomIn = false
        resetZooming()
    }

    /// `zoomOut`: the strip's frames, the trim and the playhead go back as the read frames gather under the
    /// pivot's frame, then the read frames go. The trim takes no touches until it's back.
    private func zoomOut() {
        isAnimatingZoomOut = true
        trimView.isUserInteractionEnabled = false
        let generation = zoomGeneration
        UIView.animate(
            withDuration: Self.zoomAnimationDuration,
            delay: 0,
            options: [.curveEaseInOut, .layoutSubviews],
        ) {
            self.layoutThumbnails(forZoom: false)
            self.layoutZoomedThumbnails(stacked: true)
            self.layoutTrimView(zoomedIn: false)
            self.updatePlayheadPosition(zoomedIn: false)
        } completion: { _ in
            guard generation == self.zoomGeneration else { return }
            self.isAnimatingZoomOut = false
            self.resetZooming()
            self.trimView.isUserInteractionEnabled = true
            self.stripView.clipsToBounds = true
            self.setNeedsLayout()
        }
    }

    /// `_resetZooming`.
    private func resetZooming() {
        isZoomedIn = false
        zoomTask?.cancel()
        zoomTask = nil
        zoomedDuration = 0
        zoomPivotPosition = 0
        zoomPivotOffset = 0
        zoomedPivotIndex = -1
        for view in zoomedThumbnailViews {
            view.removeFromSuperview()
        }
        zoomedThumbnailViews = []
        zoomedTimes = []
    }

    /// The zoom ends at once, for new frames or a new strip width.
    private func discardZoom() {
        cancelZoomIn()
        guard isZoomedIn || isAnimatingZoomOut else { return }
        zoomGeneration += 1
        resetZooming()
        isAnimatingZoomIn = false
        isAnimatingZoomOut = false
        trimView.isUserInteractionEnabled = true
        stripView.clipsToBounds = true
        layoutThumbnails(forZoom: false)
        layoutTrimView(zoomedIn: false)
        updatePlayheadPosition(zoomedIn: false)
    }

    // MARK: Trimming

    @objc private func handleTrimPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            beginTrimInteraction(atStart: gesture.view === trimView.leftHandle)
        case .cancelled,
             .ended,
             .failed:
            endTrimInteraction()
        default:
            break
        }
    }

    @objc private func handleTrimPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: trimView)
        gesture.setTranslation(.zero, in: trimView)
        switch gesture.state {
        case .began:
            beginTrimInteraction(atStart: gesture.view === trimView.leftHandle)
        case .changed:
            if gesture.view === trimView.leftHandle {
                startHandleMoved(by: translation.x)
            } else {
                endHandleMoved(by: translation.x)
            }
        case .cancelled,
             .ended,
             .failed:
            endTrimInteraction()
        default:
            break
        }
    }

    /// The trim view's `didBeginEditing`: the frame lights up, the playhead hides, and resting there zooms about
    /// the held edge.
    private func beginTrimInteraction(atStart: Bool) {
        guard !trimInteractionBegan else { return }
        trimInteractionBegan = true
        trimInteractionEnded = false
        isTrimming = true
        onBeginTrimming?()
        scheduleZoomIn(from: atStart ? .trimStart : .trimEnd)
        trimView.setHighlighted(true, animated: true)
        setPlayheadHidden(true, animated: false)
    }

    /// `didEndEditing`: a frame within 3 pt of an end snaps to it, stays lit while it trims, and the strip zooms
    /// back out.
    private func endTrimInteraction() {
        trimInteractionBegan = false
        guard !trimInteractionEnded else { return }
        trimInteractionEnded = true
        isTrimming = false
        var frame = trimView.frame
        let rect = scrubbingRect()
        let normalRect = scrubbingRect(zoomedIn: false)
        let maxWidth = rect.width + normalRect.minX * 2
        let leftmostPosition = rect.minX - normalRect.minX
        if frame.minX < leftmostPosition + Self.trimRectEpsilon {
            let delta = leftmostPosition - frame.minX
            frame.origin.x += delta
            frame.size.width = min(maxWidth, frame.width - delta)
        }
        if frame.maxX > maxWidth - Self.trimRectEpsilon {
            frame.size.width = min(maxWidth, frame.width + maxWidth - frame.maxX)
        }
        trimView.frame = frame
        layoutCurtains(zoomedIn: isZoomedIn)
        let positions = trimPositions(for: frame)
        trimStart = max(0, positions.start)
        trimEnd = min(duration, positions.end)
        trimView.setHighlighted(hasTrimming, animated: true)
        setPlayheadHidden(false, animated: true)
        updateAccessibilityValues()
        cancelZoomIn()
        if isZoomedIn {
            zoomOut()
        }
        onEndTrimming?()
    }

    /// `startHandleMoved:`: the frame's left edge follows the finger while the trim keeps its minimum, and a rest
    /// there zooms about it.
    private func startHandleMoved(by dx: CGFloat) {
        guard !isAnimatingZoomIn else { return }
        let current = trimView.frame
        let rect = scrubbingRect()
        let normalRect = scrubbingRect(zoomedIn: false)
        let originX = max(0, current.minX + dx)
        let delta = originX - current.minX
        let maxWidth = rect.width + normalRect.minX * 2 - originX
        let frame = CGRect(x: originX, y: 0, width: min(maxWidth, current.width - delta), height: Self.stripHeight)
        let positions = trimPositions(for: frame)
        guard positions.end - positions.start >= minimumLength else { return }
        trimView.frame = frame
        layoutCurtains(zoomedIn: isZoomedIn)
        trimStart = max(0, positions.start)
        trimEnd = min(duration, positions.end)
        value = trimStart
        playheadView.center.x = frame.minX + Self.handleWidth + playheadView.bounds.width / 2
        onTrimEdgeChanged?(trimStart)
        scheduleZoomIn(from: .trimStart)
    }

    /// `endHandleMoved`: the frame's right edge follows the finger up to the video's end, and a rest there zooms
    /// about it.
    private func endHandleMoved(by dx: CGFloat) {
        guard !isAnimatingZoomIn else { return }
        let current = trimView.frame
        let rect = scrubbingRect()
        let normalRect = scrubbingRect(zoomedIn: false)
        let localOriginX = current.minX - rect.minX + normalRect.minX
        let maxWidth = rect.width + normalRect.minX * 2 - localOriginX
        let frame = CGRect(x: current.minX, y: 0, width: min(maxWidth, current.width + dx), height: Self.stripHeight)
        let positions = trimPositions(for: frame)
        guard positions.end - positions.start >= minimumLength else { return }
        trimView.frame = frame
        layoutCurtains(zoomedIn: isZoomedIn)
        trimStart = max(0, positions.start)
        trimEnd = min(duration, positions.end)
        value = trimEnd
        playheadView.center.x = frame.maxX - Self.handleWidth - playheadView.bounds.width / 2
        onTrimEdgeChanged?(trimEnd)
        scheduleZoomIn(from: .trimEnd)
    }

    /// VoiceOver's swipes on a handle move its edge by a second, keeping the minimum length.
    private func adjustTrim(start: Bool, by seconds: Double) {
        guard allowsTrimming, duration > Self.valueEpsilon else { return }
        if start {
            trimStart = min(max(0, trimStart + seconds), trimEnd - minimumLength)
            value = trimStart
        } else {
            trimEnd = max(min(duration, trimEnd + seconds), trimStart + minimumLength)
            value = trimEnd
        }
        onBeginTrimming?()
        layoutTrimView(zoomedIn: isZoomedIn)
        updatePlayheadPosition(zoomedIn: isZoomedIn)
        trimView.setHighlighted(hasTrimming, animated: true)
        updateAccessibilityValues()
        onTrimEdgeChanged?(value)
        onEndTrimming?()
    }

    private func updateAccessibilityValues() {
        trimView.leftHandle.accessibilityValue = Self.timeString(trimStart)
        trimView.rightHandle.accessibilityValue = Self.timeString(trimEnd)
    }

    // MARK: Scrubbing

    /// `handlePress:`: holding the playhead zooms about it once it rests.
    @objc private func handlePlayheadPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            beginScrubInteraction(schedulesZoom: true)
        case .cancelled,
             .ended,
             .failed:
            endScrubInteraction()
        default:
            break
        }
    }

    /// `handlePan:`: the playhead stays between the handles, at either one the value is the trim's edge, and a
    /// rest zooms about it.
    @objc private func handlePlayheadPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        switch gesture.state {
        case .began:
            beginScrubInteraction(schedulesZoom: false)
        case .changed:
            guard !isAnimatingZoomIn, !isAnimatingZoomOut else { return }
            let rect = scrubbingRect()
            let normalRect = scrubbingRect(zoomedIn: false)
            let halfWidth = playheadView.bounds.width / 2
            var minPosition = rect.minX + halfWidth
            var maxPosition = rect.maxX - halfWidth
            if allowsTrimming {
                minPosition = max(minPosition, trimView.frame.minX + normalRect.minX + halfWidth)
                maxPosition = min(maxPosition, trimView.frame.maxX - normalRect.minX - halfWidth)
            }
            let centerX = min(max(playheadView.center.x + translation.x, minPosition), maxPosition)
            playheadView.center.x = centerX
            var position = position(forPlayheadCenterX: centerX)
            if allowsTrimming {
                if abs(centerX - minPosition) < .ulpOfOne {
                    position = trimStart
                } else if abs(centerX - maxPosition) < .ulpOfOne {
                    position = trimEnd
                }
            }
            value = min(max(0, position), duration)
            onScrub?(value)
            scheduleZoomIn(from: .handle)
        case .cancelled,
             .ended,
             .failed:
            endScrubInteraction()
        default:
            break
        }
    }

    /// The press waits for a rest to zoom; a pan zooms only once it rests after moving.
    private func beginScrubInteraction(schedulesZoom: Bool) {
        guard !scrubInteractionBegan else { return }
        scrubInteractionBegan = true
        scrubInteractionEnded = false
        isScrubbing = true
        onBeginScrubbing?()
        if schedulesZoom {
            scheduleZoomIn(from: .handle)
        } else {
            cancelZoomIn()
        }
    }

    private func endScrubInteraction() {
        scrubInteractionBegan = false
        guard !scrubInteractionEnded else { return }
        scrubInteractionEnded = true
        isScrubbing = false
        onEndScrubbing?()
        cancelZoomIn()
        if isZoomedIn {
            zoomOut()
        }
    }

    /// `handleTap:`: the cover's handle springs to the tapped place, kept inside the trim, and the player follows.
    @objc private func handleStripTap(_ gesture: UITapGestureRecognizer) {
        guard isCoverPicker, duration > Self.valueEpsilon, !isScrubbing, !isZoomedIn, !isPreparingToZoomIn else {
            return
        }
        let tappedX = gesture.location(in: wrapperView).x
        let tapped = min(max(position(forPlayheadCenterX: tappedX), trimStart), trimEnd)
        value = tapped
        let centerX = playheadCenterX(for: tapped, zoomedIn: false)
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 1.1, initialSpringVelocity: 0) {
            self.playheadView.center.x = centerX
        }
        onBeginScrubbing?()
        onScrub?(tapped)
        onEndScrubbing?()
    }
}

// MARK: UIGestureRecognizerDelegate

extension VideoScrubberView: UIGestureRecognizerDelegate {
    /// A handle's press and pan work together; other views' gestures don't.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer,
    ) -> Bool {
        gestureRecognizer.view === otherGestureRecognizer.view
    }
}

// MARK: - VideoScrubberThumbnailView

/// TGMediaPickerGalleryVideoScrubberThumbnailView: the whole frame turned and mirrored behind a box that shows the
/// crop from its top left, the crop's width filling the box (`updateCropping`), with a faint dark line on the right
/// edge between frames.
private final class VideoScrubberThumbnailView: UIView {
    // MARK: Private

    /// `1 - TGRetinaPixel`.
    private static let stripeThickness: CGFloat = 0.5

    // MARK: Internal

    var crop: PhotoCropAdjustments {
        didSet { updateCropping() }
    }

    private let imageView = UIImageView()
    private let stripeView = UIView()

    init(crop: PhotoCropAdjustments) {
        self.crop = crop
        super.init(frame: .zero)
        clipsToBounds = true
        isUserInteractionEnabled = false
        imageView.contentMode = .scaleToFill
        addSubview(imageView)
        stripeView.backgroundColor = UIColor(white: 0, alpha: 0.3)
        addSubview(stripeView)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCropping()
    }

    /// The frame's picture; the first one fades in.
    func setImage(_ image: UIImage, fadesIn: Bool) {
        imageView.image = image
        guard fadesIn else { return }
        alpha = 0
        UIView.animate(withDuration: 0.15) { self.alpha = 1 }
    }

    /// `updateCropping`: the frame, `originalSize` large, placed as the player places it, then moved so the crop's
    /// top meets the box's when the box's shape was held to half its height.
    private func updateCropping() {
        let size = bounds.size
        let rect = crop.cropRect
        guard size.width > 0, rect.width > 0, rect.height > 0 else { return }
        let turned = crop.orientation.isSideward ? CGSize(width: rect.height, height: rect.width) : rect.size
        let contentHeight = turned.height * size.width / turned.width
        var placement = crop.contentPlacement(in: size)
        placement.center.y += (contentHeight - size.height) / 2
        imageView.transform = .identity
        imageView.bounds = CGRect(origin: .zero, size: crop.originalSize)
        imageView.center = placement.center
        imageView.transform = placement.transform
        stripeView.frame = CGRect(
            x: size.width - Self.stripeThickness,
            y: 0,
            width: Self.stripeThickness,
            height: size.height,
        )
    }
}

// MARK: - VideoTrimFrameView

/// TGMediaPickerGalleryVideoTrimView: two rounded handles with grips joined by thin lines, white at rest and yellow
/// while trimmed.
private final class VideoTrimFrameView: ExpandedHitView {
    // MARK: Private

    private static let handleWidth: CGFloat = 12
    /// TGMediaPickerGalleryVideoTrimView's accent, `0xf8d74a`.
    private static let trimmingColor = UIColor(red: 0xF8 / 255, green: 0xD7 / 255, blue: 0x4A / 255, alpha: 1)

    // MARK: Internal

    let leftHandle = VideoTrimHandleView(mirrored: false)
    let rightHandle = VideoTrimHandleView(mirrored: true)

    private let borderView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        hitInsets = UIEdgeInsets(top: -5, left: -25, bottom: -5, right: -25)
        leftHandle.hitInsets = UIEdgeInsets(top: -5, left: -25, bottom: -5, right: -10)
        rightHandle.hitInsets = UIEdgeInsets(top: -5, left: -10, bottom: -5, right: -25)
        borderView.image = Self.borderImage()
        borderView.contentMode = .scaleToFill
        for view in [leftHandle, rightHandle, borderView] as [UIView] {
            view.tintColor = .white
            addSubview(view)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = Self.handleWidth
        leftHandle.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        rightHandle.frame = CGRect(x: bounds.width - width, y: 0, width: width, height: bounds.height)
        borderView.frame = CGRect(x: width, y: 0, width: max(0, bounds.width - width * 2), height: bounds.height)
    }

    /// The top and bottom lines between the handles, one point and a hairline thick.
    private static func borderImage() -> UIImage {
        let line = 1 + 1 / UITraitCollection.current.displayScale
        let size = CGSize(width: 1, height: 40)
        return UIGraphicsImageRenderer(size: size)
            .image { context in
                context.fill(CGRect(x: 0, y: 0, width: 1, height: line))
                context.fill(CGRect(x: 0, y: size.height - line, width: 1, height: line))
            }
            .withRenderingMode(.alwaysTemplate)
    }

    /// `setTrimming:animated:`.
    func setHighlighted(_ highlighted: Bool, animated: Bool) {
        let color = highlighted ? Self.trimmingColor : .white
        let apply = {
            for view in [self.leftHandle, self.rightHandle, self.borderView] as [UIView] {
                view.tintColor = color
            }
        }
        if animated {
            UIView.animate(withDuration: 0.15, animations: apply)
        } else {
            apply()
        }
    }
}

// MARK: - VideoTrimHandleView

/// A trim handle: rounded on its outer side, with a dark grip, and adjustable by VoiceOver.
private final class VideoTrimHandleView: ExpandedHitView {
    override var tintColor: UIColor! {
        didSet { imageView.tintColor = tintColor }
    }

    // MARK: Internal

    /// VoiceOver's increment (+1) or decrement (-1).
    var onAccessibilityAdjust: ((Double) -> Void)?

    // MARK: Private

    private let imageView = UIImageView()
    private let grip = UIView()

    init(mirrored: Bool) {
        super.init(frame: .zero)
        imageView.image = Self.handleImage(mirrored: mirrored)
        addSubview(imageView)
        let hairline = 1 / UITraitCollection.current.displayScale
        grip.backgroundColor = UIColor(red: 0x34 / 255, green: 0x34 / 255, blue: 0x36 / 255, alpha: 1)
        grip.layer.cornerRadius = 1
        grip.frame = CGRect(x: mirrored ? 5 + hairline : 5 - hairline, y: 14 + hairline, width: 2, height: 11)
        addSubview(grip)
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
    }

    override func accessibilityIncrement() {
        onAccessibilityAdjust?(1)
    }

    override func accessibilityDecrement() {
        onAccessibilityAdjust?(-1)
    }

    /// A 12×40 piece of a rounded square, its inner edge cut so the lines between the handles meet it.
    private static func handleImage(mirrored: Bool) -> UIImage {
        let size = CGSize(width: 12, height: 40)
        let line = 1 + 1 / UITraitCollection.current.displayScale
        return UIGraphicsImageRenderer(size: size)
            .image { context in
                let cgContext = context.cgContext
                if mirrored {
                    cgContext.translateBy(x: size.width, y: 0)
                    cgContext.scaleBy(x: -1, y: 1)
                }
                UIColor.white.setFill()
                UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 40, height: 40), cornerRadius: 9).fill()
                cgContext.setBlendMode(.clear)
                UIBezierPath(
                    roundedRect: CGRect(x: 11, y: line, width: 20, height: size.height - line * 2),
                    cornerRadius: 2,
                ).fill()
            }
            .withRenderingMode(.alwaysTemplate)
    }
}

// MARK: - ExpandedHitView

/// `hitTestEdgeInsets`: a view that takes touches beyond its bounds by negative insets.
private class ExpandedHitView: UIView {
    var hitInsets = UIEdgeInsets.zero

    override func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
        !isHidden && alpha > 0.01 && bounds.inset(by: hitInsets).contains(point)
    }
}
