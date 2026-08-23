// AnimatedWebP.swift

import Combine
import Foundation
import libwebp
import QuartzCore
import TDLibKit
import UIKit

// MARK: - AnimatedWebPAsset

final class AnimatedWebPAsset {
    // MARK: Lifecycle

    init(
        data: NSData,
        size: CGSize,
        frameEndTimes: [TimeInterval],
        loopCount: Int,
        firstFrame: UIImage?,
    ) {
        self.data = data
        self.size = size
        self.frameEndTimes = frameEndTimes
        self.loopCount = loopCount
        self.firstFrame = firstFrame
    }

    // MARK: Internal

    let data: NSData
    let size: CGSize
    let frameEndTimes: [TimeInterval]
    let loopCount: Int
    let firstFrame: UIImage?

    var frameCount: Int {
        frameEndTimes.count
    }

    var duration: TimeInterval {
        frameEndTimes.last ?? 0
    }

    var estimatedMemoryCost: Int {
        data.length + max(1, Int(size.width * size.height * 4))
    }

    func frameIndex(at timestamp: TimeInterval) -> Int {
        guard frameEndTimes.count > 1, duration > 0 else { return 0 }
        let position = timestamp.truncatingRemainder(dividingBy: duration)
        var lowerBound = 0
        var upperBound = frameEndTimes.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if position < frameEndTimes[middle] {
                upperBound = middle
            } else {
                lowerBound = middle + 1
            }
        }
        return min(lowerBound, frameEndTimes.count - 1)
    }
}

// MARK: - AnimatedWebPRepository

enum AnimatedWebPRepository {
    // MARK: Internal

    static func asset(at path: String) async -> AnimatedWebPAsset? {
        let key = path as NSString
        if let cached = assetCache.object(forKey: key) {
            return cached
        }

        let loadTask = Task.detached(priority: .userInitiated) { () -> AnimatedWebPAsset? in
            guard !Task.isCancelled,
                  let data = NSData(contentsOfFile: path),
                  data.length <= maximumInputSize,
                  !Task.isCancelled,
                  let asset = decodeAsset(data: data)
            else { return nil }
            assetCache.setObject(asset, forKey: key, cost: asset.estimatedMemoryCost)
            if let firstFrame = asset.firstFrame {
                setFrame(firstFrame, path: path, index: 0)
            }
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

    private static let maximumInputSize = 32 * 1024 * 1024

    private static let assetCache: NSCache<NSString, AnimatedWebPAsset> = {
        let cache = NSCache<NSString, AnimatedWebPAsset>()
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

    private static func decodeAsset(data: NSData) -> AnimatedWebPAsset? {
        guard let metadata = decodeAnimatedWebPMetadata(data: data),
              let decoder = makeAnimatedWebPDecoder(data: data)
        else { return nil }
        defer { WebPAnimDecoderDelete(decoder) }
        var bytes: UnsafeMutablePointer<UInt8>?
        var timestamp: Int32 = 0
        guard WebPAnimDecoderGetNext(decoder, &bytes, &timestamp) != 0,
              let bytes
        else { return nil }
        let firstFrame = makeAnimatedWebPImage(bytes: bytes, width: metadata.width, height: metadata.height)

        return AnimatedWebPAsset(
            data: data,
            size: CGSize(width: metadata.width, height: metadata.height),
            frameEndTimes: metadata.frameEndTimes,
            loopCount: metadata.loopCount,
            firstFrame: firstFrame,
        )
    }

    private static func frameKey(path: String, index: Int) -> NSString {
        "\(path)#\(index)" as NSString
    }
}

// MARK: - AnimatedWebPFrameDecoder

actor AnimatedWebPFrameDecoder {
    // MARK: Lifecycle

    init?(asset: AnimatedWebPAsset) {
        self.data = asset.data
        self.size = asset.size
        guard let decoder = makeAnimatedWebPDecoder(data: asset.data) else { return nil }
        self.decoder = decoder
    }

    deinit {
        WebPAnimDecoderDelete(decoder)
    }

    // MARK: Internal

    func frame(at requestedIndex: Int) -> UIImage? {
        guard requestedIndex >= 0 else { return nil }
        if requestedIndex <= decodedIndex {
            WebPAnimDecoderReset(decoder)
            decodedIndex = -1
        }

        var image: UIImage?
        while decodedIndex < requestedIndex {
            guard !Task.isCancelled else { return nil }
            var bytes: UnsafeMutablePointer<UInt8>?
            var timestamp: Int32 = 0
            guard WebPAnimDecoderGetNext(decoder, &bytes, &timestamp) != 0,
                  let bytes
            else { return nil }
            decodedIndex += 1
            if decodedIndex == requestedIndex {
                image = makeAnimatedWebPImage(
                    bytes: bytes,
                    width: Int(size.width),
                    height: Int(size.height),
                )
            }
        }
        return image
    }

    // MARK: Private

    private let data: NSData
    private let size: CGSize
    private let decoder: OpaquePointer
    private var decodedIndex = -1
}

// MARK: - AnimatedWebPView

final class AnimatedWebPView: UIControl {
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
        accessibilityLabel = "Animated sticker"
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
    private var asset: AnimatedWebPAsset?
    private var decoder: AnimatedWebPFrameDecoder?
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
            let asset = await AnimatedWebPRepository.asset(at: file.local.path)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.representedFileID == fileID else { return }
                self.show(asset: asset, path: file.local.path)
            }
        }
    }

    private func show(asset: AnimatedWebPAsset?, path: String) {
        guard let asset else {
            frameView.image = nil
            frameView.isHidden = true
            thumbnailView.isHidden = false
            return
        }

        self.asset = asset
        decoder = AnimatedWebPFrameDecoder(asset: asset)
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
        guard let asset, let path = loadedPath, asset.duration > 0 else { return }
        requestFrame(asset.frameIndex(at: CACurrentMediaTime()), path: path)
    }

    private func requestFrame(_ index: Int, path: String) {
        if let cached = AnimatedWebPRepository.frame(path: path, index: index) {
            frameView.image = cached
            frameView.isHidden = false
            thumbnailView.isHidden = true
            requestedFrameIndex = nil
            return
        }

        requestedFrameIndex = index
        guard decodeTask == nil, let decoder else { return }
        decodeTask = Task { [weak self] in
            let image = await decoder.frame(at: index)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.loadedPath == path else { return }
                if let image {
                    AnimatedWebPRepository.setFrame(image, path: path, index: index)
                    if self.requestedFrameIndex == index {
                        self.frameView.image = image
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

private func makeAnimatedWebPImage(bytes: UnsafeMutablePointer<UInt8>, width: Int, height: Int) -> UIImage? {
    let bytesPerRow = width * 4
    let byteCount = bytesPerRow * height
    let data = Data(bytes: bytes, count: byteCount)
    guard let provider = CGDataProvider(data: data as CFData),
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
