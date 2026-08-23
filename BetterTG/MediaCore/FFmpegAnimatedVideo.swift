// FFmpegAnimatedVideo.swift

import Combine
import FFmpegBridge
import Foundation
import QuartzCore
import TDLibKit
import UIKit

// MARK: - FFmpegVideoAsset

final class FFmpegVideoAsset {
    // MARK: Lifecycle

    init(
        path: String,
        size: CGSize,
        frameRate: Double,
        duration: TimeInterval,
        frameCount: Int,
        firstFrame: UIImage?,
        hasAlpha: Bool,
    ) {
        self.path = path
        self.size = size
        self.frameRate = frameRate
        self.duration = duration
        self.observedFrameCount = frameCount
        self.firstFrame = firstFrame
        self.hasAlpha = hasAlpha
    }

    // MARK: Internal

    let path: String
    let size: CGSize
    let frameRate: Double
    let duration: TimeInterval
    let firstFrame: UIImage?
    let hasAlpha: Bool

    var frameCount: Int {
        frameCountLock.lock()
        defer { frameCountLock.unlock() }
        return observedFrameCount
    }

    var estimatedMemoryCost: Int {
        max(1, Int(size.width * size.height * 4))
    }

    func frameIndex(at timestamp: TimeInterval) -> Int {
        let count = frameCount
        guard count > 1 else { return 0 }
        let frame = Int(floor(timestamp * frameRate))
        return max(0, frame % count)
    }

    func update(frameCount: Int) {
        guard frameCount > 0 else { return }
        frameCountLock.lock()
        observedFrameCount = frameCount
        frameCountLock.unlock()
    }

    // MARK: Private

    private let frameCountLock = NSLock()
    private var observedFrameCount: Int
}

// MARK: - FFmpegDecodedVideoFrame

struct FFmpegDecodedVideoFrame {
    let image: UIImage
    let index: Int
    let presentationTime: TimeInterval
    let duration: TimeInterval
    let hasAlpha: Bool
    let observedFrameCount: Int?
}

// MARK: - FFmpegVideoRepository

enum FFmpegVideoRepository {
    // MARK: Internal

    static func asset(at path: String) async -> FFmpegVideoAsset? {
        let key = path as NSString
        if let cached = assetCache.object(forKey: key) {
            return cached
        }

        let loadTask = Task.detached(priority: .userInitiated) { () -> FFmpegVideoAsset? in
            guard !Task.isCancelled,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let fileSize = attributes[.size] as? NSNumber,
                  fileSize.intValue <= maximumInputSize,
                  let decoder = createFFmpegVideoDecoder(path: path)
            else { return nil }
            defer { BetterTGFFmpegVideoDecoderDestroy(decoder) }

            let width = Int(BetterTGFFmpegVideoDecoderWidth(decoder))
            let height = Int(BetterTGFFmpegVideoDecoderHeight(decoder))
            guard width > 0,
                  height > 0,
                  width <= maximumDimension,
                  height <= maximumDimension,
                  width * height <= maximumPixelCount
            else { return nil }

            let sourceFrameRate = BetterTGFFmpegVideoDecoderFrameRate(decoder)
            let frameRate = min(
                30,
                max(1, sourceFrameRate.isFinite && sourceFrameRate > 0 ? sourceFrameRate : 30),
            )
            let sourceDuration = BetterTGFFmpegVideoDecoderDuration(decoder)
            let duration = sourceDuration.isFinite ? max(0, sourceDuration) : 0
            let estimatedFrameCount = min(
                maximumFrameCount,
                max(1, Int(ceil((duration > 0 ? duration : 10) * frameRate))),
            )

            var frameData = Data(count: width * height * 4)
            var presentationTime = TimeInterval.zero
            var frameDuration = TimeInterval.zero
            var hasAlpha = Int32.zero
            let result = frameData.withUnsafeMutableBytes { bytes in
                BetterTGFFmpegVideoDecoderReadFrame(
                    decoder,
                    bytes.bindMemory(to: UInt8.self).baseAddress,
                    Int32(width),
                    Int32(height),
                    Int32(width * 4),
                    &presentationTime,
                    &frameDuration,
                    &hasAlpha,
                )
            }
            guard result == 1,
                  let firstFrame = makeFFmpegBGRAImage(data: frameData, width: width, height: height)
            else { return nil }

            let asset = FFmpegVideoAsset(
                path: path,
                size: CGSize(width: width, height: height),
                frameRate: frameRate,
                duration: duration,
                frameCount: estimatedFrameCount,
                firstFrame: firstFrame,
                hasAlpha: hasAlpha != 0,
            )
            assetCache.setObject(asset, forKey: key, cost: asset.estimatedMemoryCost)
            setFrame(firstFrame, path: path, index: 0)
            return asset
        }

        return await withTaskCancellationHandler {
            await loadTask.value
        } onCancel: {
            loadTask.cancel()
        }
    }

    static func frame(path: String, index: Int) -> UIImage? {
        frameCache.object(forKey: frameKey(path: path, index: index))
    }

    static func setFrame(_ image: UIImage, path: String, index: Int) {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        frameCache.setObject(
            image,
            forKey: frameKey(path: path, index: index),
            cost: max(1, Int(pixels * 4)),
        )
    }

    // MARK: Private

    private static let maximumInputSize = 64 * 1024 * 1024
    private static let maximumFrameCount = 600
    private static let maximumDimension = 2048
    private static let maximumPixelCount = 4 * 1024 * 1024

    private static let assetCache: NSCache<NSString, FFmpegVideoAsset> = {
        let cache = NSCache<NSString, FFmpegVideoAsset>()
        cache.countLimit = 48
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    private static let frameCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 180
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    private static func frameKey(path: String, index: Int) -> NSString {
        "\(path)#\(index)" as NSString
    }
}

// MARK: - FFmpegVideoFrameDecoder

actor FFmpegVideoFrameDecoder {
    // MARK: Lifecycle

    init?(asset: FFmpegVideoAsset) {
        self.width = Int(asset.size.width)
        self.height = Int(asset.size.height)
        guard let decoder = createFFmpegVideoDecoder(path: asset.path) else { return nil }
        self.decoder = decoder
    }

    deinit {
        BetterTGFFmpegVideoDecoderDestroy(decoder)
    }

    // MARK: Internal

    func frame(at requestedIndex: Int) -> FFmpegDecodedVideoFrame? {
        guard requestedIndex >= 0 else { return nil }
        var targetIndex = observedFrameCount.map { requestedIndex % $0 } ?? requestedIndex
        if targetIndex <= decodedIndex {
            guard reset() else { return nil }
        }

        var resets = 0
        while decodedIndex < targetIndex {
            guard !Task.isCancelled else { return nil }
            var frameData = Data(count: width * height * 4)
            var presentationTime = TimeInterval.zero
            var frameDuration = TimeInterval.zero
            var hasAlpha = Int32.zero
            let result = frameData.withUnsafeMutableBytes { bytes in
                BetterTGFFmpegVideoDecoderReadFrame(
                    decoder,
                    bytes.bindMemory(to: UInt8.self).baseAddress,
                    Int32(width),
                    Int32(height),
                    Int32(width * 4),
                    &presentationTime,
                    &frameDuration,
                    &hasAlpha,
                )
            }

            if result == 0 {
                let frameCount = decodedIndex + 1
                guard frameCount > 0, resets == 0 else { return nil }
                observedFrameCount = frameCount
                targetIndex = requestedIndex % frameCount
                guard reset() else { return nil }
                resets += 1
                continue
            }
            guard result == 1 else { return nil }

            decodedIndex += 1
            if decodedIndex == targetIndex {
                guard let image = makeFFmpegBGRAImage(data: frameData, width: width, height: height) else { return nil }
                return FFmpegDecodedVideoFrame(
                    image: image,
                    index: decodedIndex,
                    presentationTime: presentationTime,
                    duration: frameDuration,
                    hasAlpha: hasAlpha != 0,
                    observedFrameCount: observedFrameCount,
                )
            }
        }
        return nil
    }

    // MARK: Private

    private let width: Int
    private let height: Int
    private let decoder: OpaquePointer
    private var decodedIndex = -1
    private var observedFrameCount: Int?

    private func reset() -> Bool {
        guard BetterTGFFmpegVideoDecoderReset(decoder) != 0 else { return false }
        decodedIndex = -1
        return true
    }
}

// MARK: - FFmpegAnimatedVideoView

final class FFmpegAnimatedVideoView: UIControl {
    // MARK: Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.contentMode = .scaleAspectFit
        addSubview(thumbnailView)

        frameView.translatesAutoresizingMaskIntoConstraints = false
        frameView.contentMode = .scaleAspectFit
        frameView.isHidden = true
        frameView.isUserInteractionEnabled = false
        addSubview(frameView)

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: bottomAnchor),
            frameView.topAnchor.constraint(equalTo: topAnchor),
            frameView.leadingAnchor.constraint(equalTo: leadingAnchor),
            frameView.trailingAnchor.constraint(equalTo: trailingAnchor),
            frameView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityLabel = "Video sticker"
        accessibilityTraits = .image
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
    }

    // MARK: Internal

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlayback()
    }

    func configure(
        file: File,
        thumbnail: Thumbnail?,
        displaySize: CGSize?,
        onTap: (() -> Void)?,
    ) {
        prepareForReuse()
        representedFileID = file.id
        self.onTap = onTap
        isUserInteractionEnabled = onTap != nil
        apply(displaySize: displaySize)

        if let thumbnail {
            thumbnailView.load(file: thumbnail.file)
        }

        update(file: file)
        fileCancellable = nc.publisher(for: .updateFile)
            .receive(on: DispatchQueue.main)
            .filter { $0.file.id == file.id }
            .sink { [weak self] update in self?.update(file: update.file) }

        if !file.local.isDownloadingCompleted {
            downloadTask = Task { [weak self] in
                let downloaded = try? await td.downloadFile(
                    fileId: file.id,
                    limit: 0,
                    offset: 0,
                    priority: 2,
                    synchronous: false,
                )
                guard let self, let downloaded else { return }
                await MainActor.run { self.update(file: downloaded) }
            }
        }
    }

    func prepareForReuse() {
        let fileID = representedFileID
        representedFileID = nil
        loadedPath = nil
        asset = nil
        decoder = nil
        requestedFrameIndex = nil
        onTap = nil
        isUserInteractionEnabled = false
        playbackVisible = false

        downloadTask?.cancel()
        downloadTask = nil
        assetTask?.cancel()
        assetTask = nil
        decodeTask?.cancel()
        decodeTask = nil
        fileCancellable?.cancel()
        fileCancellable = nil
        stopDisplayLink()

        frameView.image = nil
        frameView.isHidden = true
        thumbnailView.isHidden = false
        thumbnailView.cancel()
        widthConstraint.isActive = false
        heightConstraint.isActive = false

        if let fileID {
            Task { try? await td.cancelDownloadFile(fileId: fileID, onlyIfPending: true) }
        }
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        playbackVisible = isVisible
        updatePlayback()
    }

    // MARK: Private

    private let thumbnailView = TDImageLoadingView()
    private let frameView = UIImageView()
    private lazy var widthConstraint = widthAnchor.constraint(equalToConstant: 180)
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 180)
    private var representedFileID: Int?
    private var loadedPath: String?
    private var asset: FFmpegVideoAsset?
    private var decoder: FFmpegVideoFrameDecoder?
    private var playbackVisible = false
    private var onTap: (() -> Void)?
    private var displayLink: CADisplayLink?
    private var requestedFrameIndex: Int?
    private var downloadTask: Task<Void, Never>?
    private var assetTask: Task<Void, Never>?
    private var decodeTask: Task<Void, Never>?
    private var fileCancellable: AnyCancellable?

    private var playbackEnabled: Bool {
        UserDefaults.standard.object(forKey: "animatedMediaEnabled") as? Bool ?? true
    }

    private func apply(displaySize: CGSize?) {
        guard let displaySize else { return }
        widthConstraint.constant = displaySize.width
        heightConstraint.constant = displaySize.height
        widthConstraint.isActive = true
        heightConstraint.isActive = true
    }

    private func update(file: File) {
        guard representedFileID == file.id,
              file.local.isDownloadingCompleted,
              !file.local.path.isEmpty,
              loadedPath != file.local.path
        else { return }

        loadedPath = file.local.path
        let fileID = file.id
        assetTask?.cancel()
        assetTask = Task { [weak self] in
            let asset = await FFmpegVideoRepository.asset(at: file.local.path)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.representedFileID == fileID else { return }
                self.show(asset: asset, path: file.local.path)
            }
        }
    }

    private func show(asset: FFmpegVideoAsset?, path: String) {
        guard let asset else {
            frameView.image = nil
            frameView.isHidden = true
            thumbnailView.isHidden = false
            return
        }

        self.asset = asset
        decoder = FFmpegVideoFrameDecoder(asset: asset)
        if let firstFrame = asset.firstFrame {
            frameView.image = firstFrame
            frameView.isHidden = false
            thumbnailView.isHidden = true
        }
        loadedPath = path
        updatePlayback()
    }

    private func updatePlayback() {
        let shouldPlay = playbackVisible && window != nil && playbackEnabled && (asset?.frameCount ?? 0) > 1
        if shouldPlay {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        displayLink.preferredFrameRateRange = ProcessInfo.processInfo.isLowPowerModeEnabled
            ? CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            : CAFrameRateRange(minimum: 20, maximum: 60, preferred: 60)
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
        displayLinkFired()
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        decodeTask?.cancel()
        decodeTask = nil
        requestedFrameIndex = nil
    }

    @objc private func displayLinkFired() {
        guard let asset, let path = loadedPath else { return }
        requestFrame(asset.frameIndex(at: CACurrentMediaTime()), path: path)
    }

    private func requestFrame(_ index: Int, path: String) {
        if let cached = FFmpegVideoRepository.frame(path: path, index: index) {
            frameView.image = cached
            frameView.isHidden = false
            thumbnailView.isHidden = true
            requestedFrameIndex = nil
            return
        }

        requestedFrameIndex = index
        guard decodeTask == nil, let decoder else { return }
        decodeTask = Task { [weak self] in
            let frame = await decoder.frame(at: index)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.loadedPath == path else { return }
                if let frame {
                    if let frameCount = frame.observedFrameCount {
                        self.asset?.update(frameCount: frameCount)
                    }
                    FFmpegVideoRepository.setFrame(frame.image, path: path, index: frame.index)
                    if self.requestedFrameIndex == index {
                        self.frameView.image = frame.image
                        self.frameView.isHidden = false
                        self.thumbnailView.isHidden = true
                        self.requestedFrameIndex = nil
                    }
                }
                self.decodeTask = nil
                if let pending = self.requestedFrameIndex, pending != index {
                    self.requestFrame(pending, path: path)
                }
            }
        }
    }

    @objc private func tapped() {
        onTap?()
    }
}

private func createFFmpegVideoDecoder(path: String) -> OpaquePointer? {
    path.withCString { BetterTGFFmpegVideoDecoderCreate($0) }
}

private func makeFFmpegBGRAImage(data: Data, width: Int, height: Int) -> UIImage? {
    let bytesPerRow = width * 4
    guard data.count >= bytesPerRow * height,
          let provider = CGDataProvider(data: data as CFData),
          let image = CGImage(
              width: width,
              height: height,
              bitsPerComponent: 8,
              bitsPerPixel: 32,
              bytesPerRow: bytesPerRow,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGBitmapInfo(
                  rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue,
              ),
              provider: provider,
              decode: nil,
              shouldInterpolate: true,
              intent: .defaultIntent,
          )
    else { return nil }
    return UIImage(cgImage: image)
}

func telegramAnimationUsesFFmpeg(_ animation: Animation) -> Bool {
    mediaUsesFFmpeg(mimeType: animation.mimeType, fileName: animation.fileName)
}

private func mediaUsesFFmpeg(mimeType: String, fileName: String) -> Bool {
    let normalizedMimeType = mimeType.lowercased()
    if normalizedMimeType == "video/mp4" || normalizedMimeType == "video/quicktime" {
        return false
    }
    let fileExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
    return fileExtension != "mp4" && fileExtension != "m4v" && fileExtension != "mov"
}
