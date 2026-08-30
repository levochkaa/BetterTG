// VideoNoteThumbnailStripView.swift

import ImageIO
import UIKit

// MARK: - VideoNoteThumbnailStripView

final class VideoNoteThumbnailStripView: UIView {
    var onRangeChange: ((Double, Double, Bool, Bool) -> Void)?

    private let imageViews = (0..<13).map { _ in UIImageView() }
    private let trimView = VoiceRecordingTrimView()
    private var decodeTask: Task<Void, Never>?
    private var decodeGeneration = UUID()
    private var displayedSegmentIDs = [UUID]()
    private var displayedSampleTimes = [Double]()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .tertiarySystemFill
        clipsToBounds = false
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        for imageView in imageViews {
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.backgroundColor = .secondarySystemFill
            addSubview(imageView)
        }
        trimView.setMinimumVisibleDuration(1.01)
        trimView.setMinimumSelectionWidth(0)
        trimView.onRangeChange = { [weak self] start, end, updatedEnd, finished in
            self?.onRangeChange?(start, end, updatedEnd, finished)
        }
        addSubview(trimView)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        decodeTask?.cancel()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width / CGFloat(imageViews.count)
        for (index, imageView) in imageViews.enumerated() {
            let minX = floor(CGFloat(index) * width)
            let maxX = index == imageViews.count - 1
                ? bounds.width
                : ceil(CGFloat(index + 1) * width)
            imageView.frame = CGRect(x: minX, y: 0, width: max(0, maxX - minX), height: bounds.height)
        }
        trimView.frame = bounds
    }

    func update(
        samples: [VideoNoteThumbnailSample],
        segmentIDs: [UUID],
        duration: Double,
        range: Range<Double>,
        editingEnabled: Bool,
    ) {
        trimView.update(duration: duration, range: range)
        trimView.setEditingEnabled(editingEnabled)
        updateImages(samples: samples, segmentIDs: segmentIDs)
    }

    func updateImages(
        samples: [VideoNoteThumbnailSample],
        segmentIDs: [UUID],
    ) {
        let sampleTimes = samples.map(\.time)
        guard segmentIDs != displayedSegmentIDs || sampleTimes != displayedSampleTimes else { return }
        displayedSegmentIDs = segmentIDs
        displayedSampleTimes = sampleTimes
        decodeTask?.cancel()
        let generation = UUID()
        decodeGeneration = generation
        if samples.isEmpty {
            apply(images: [])
            return
        }
        let data = samples.map(\.jpegData)
        let decodeOperation = Task.detached(priority: .utility) {
            var images = [SendableImage?]()
            images.reserveCapacity(data.count)
            for jpegData in data {
                guard !Task.isCancelled else { return [SendableImage?]() }
                let options = [
                    kCGImageSourceShouldCache: true,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary
                guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, options)
                else {
                    images.append(nil)
                    continue
                }
                images.append(SendableImage(image))
            }
            return images
        }
        decodeTask = Task { [weak self] in
            let decoded = await withTaskCancellationHandler {
                await decodeOperation.value
            } onCancel: {
                decodeOperation.cancel()
            }
            guard let self,
                  !Task.isCancelled,
                  decodeGeneration == generation,
                  displayedSegmentIDs == segmentIDs
            else { return }
            apply(images: decoded.map { $0?.image })
            decodeTask = nil
        }
    }

    func setEditingEnabled(_ enabled: Bool) {
        trimView.setEditingEnabled(enabled)
    }

    private func apply(images: [CGImage?]) {
        let fallback = images.compactMap(\.self).first
        for (index, imageView) in imageViews.enumerated() {
            let image = index < images.count ? images[index] ?? fallback : fallback
            imageView.image = image.map { UIImage(cgImage: $0) }
        }
    }
}

// MARK: - SendableImage

private struct SendableImage: @unchecked Sendable {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}
