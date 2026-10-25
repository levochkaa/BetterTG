// FFmpegAnimatedVideo.swift

import Combine
import Dispatch
import FFmpegBridge
import Foundation
import QuartzCore
import TDLibKit
import UIKit

// MARK: - FFmpegVideoAsset

final class FFmpegVideoAsset {
    // MARK: Internal

    let path: String
    let size: CGSize
    let firstFrame: UIImage?
    let hasAlpha: Bool

    // MARK: Private

    private let timingLock = NSLock()
    private let timingLoader: FFmpegVideoTimingLoader
    private var timeline: FFmpegVideoTimeline?

    var frameCount: Int {
        timingLock.lock()
        defer { timingLock.unlock() }
        return timeline?.starts.count ?? 1
    }

    /// One pass, once the timing scan has finished; zero before.
    var duration: TimeInterval {
        timingLock.lock()
        defer { timingLock.unlock() }
        return timeline?.duration ?? 0
    }

    var estimatedMemoryCost: Int {
        // Reserve the bounded timing index even before its lazy scan completes.
        max(1, Int(size.width * size.height * 4)) + FFmpegVideoTimeline.maximumFrames * MemoryLayout<Double>.stride
    }

    init(
        path: String,
        size: CGSize,
        firstFrame: UIImage?,
        hasAlpha: Bool,
    ) {
        self.path = path
        self.size = size
        self.timingLoader = FFmpegVideoTimingLoader.shared(path: path)
        self.firstFrame = firstFrame
        self.hasAlpha = hasAlpha
    }

    func frameIndex(at timestamp: TimeInterval) -> Int {
        timingLock.lock()
        defer { timingLock.unlock() }
        return timeline?.frameIndex(at: timestamp) ?? 0
    }

    func prepareTiming() async -> Bool {
        guard let timeline = await timingLoader.value(), !Task.isCancelled else { return false }
        install(timeline)
        return true
    }

    private func install(_ timeline: FFmpegVideoTimeline) {
        timingLock.lock()
        self.timeline = timeline
        timingLock.unlock()
    }
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
    // MARK: Private

    private static let maximumInputSize = 64 * 1024 * 1024
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

    private static func frameKey(path: String, index: Int) -> NSString {
        "\(path)#\(index)" as NSString
    }
}

// MARK: - FFmpegVideoFrameDecoder

actor FFmpegVideoFrameDecoder {
    // MARK: Private

    private nonisolated let worker = DispatchSerialQueue(label: "BetterTG.animation-decoder", qos: .userInitiated)
    private let path: String
    private let asset: FFmpegVideoAsset
    private let width: Int
    private let height: Int
    private var decoder: OpaquePointer?
    private var decodedIndex = -1
    private var observedFrameCount: Int?

    #if DEBUG
        private var probe: FFmpegAnimationWorkerProbe?
    #endif

    // MARK: Internal

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        worker.asUnownedSerialExecutor()
    }

    init(asset: FFmpegVideoAsset) {
        self.asset = asset
        self.path = asset.path
        self.width = Int(asset.size.width)
        self.height = Int(asset.size.height)
    }

    isolated deinit {
        if let decoder {
            dispatchPrecondition(condition: .onQueue(worker))
            BetterTGFFmpegVideoDecoderDestroy(decoder)
            #if DEBUG
                probe?.record("destroy")
            #endif
        }
    }

    func prepare() async -> Bool {
        guard await asset.prepareTiming() else { return false }
        dispatchPrecondition(condition: .onQueue(worker))
        guard !Task.isCancelled else { return false }
        if decoder != nil { return true }
        guard let decoder = createFFmpegVideoDecoder(path: path) else { return false }
        self.decoder = decoder
        observedFrameCount = asset.frameCount
        #if DEBUG
            probe?.record("create")
            probe?.holdSetupIfRequested()
        #endif
        guard !Task.isCancelled else { return false }
        return true
    }

    func frame(at requestedIndex: Int) -> FFmpegDecodedVideoFrame? {
        dispatchPrecondition(condition: .onQueue(worker))
        guard !Task.isCancelled, requestedIndex >= 0, let decoder else { return nil }
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
            #if DEBUG
                probe?.record("read")
            #endif

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

    #if DEBUG
        fileprivate func observe(with probe: FFmpegAnimationWorkerProbe) {
            self.probe = probe
        }
    #endif

    private func reset() -> Bool {
        guard let decoder, BetterTGFFmpegVideoDecoderReset(decoder) != 0 else { return false }
        #if DEBUG
            probe?.record("reset")
        #endif
        decodedIndex = -1
        return true
    }
}

// MARK: - FFmpegAnimatedVideoView

final class FFmpegAnimatedVideoView: UIControl, AnimatedFileView {
    // MARK: Internal

    var onFirstFrameReady: (() -> Void)?

    var energySaving: EnergySavingRole? {
        didSet { energySavingChanged() }
    }

    /// Auto-download's video setting for a GIF in a chat: true leaves the file to a tap on the download arrow.
    var requiresTapToDownload = false

    // MARK: Private

    private let thumbnailView = TDImageLoadingView()
    private let downloadStatus = MediaDownloadStatusView()
    private var deferredDownload: DeferredMediaDownload?
    private let frameView = UIImageView()
    private lazy var widthConstraint = widthAnchor.constraint(equalToConstant: 180)
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 180)
    private var representedFileID: Int?
    private var loadedPath: String?
    private var asset: FFmpegVideoAsset?
    private var decoder: FFmpegVideoFrameDecoder?
    private var playbackVisible = false
    /// When the single pass Power Saving allows started, and whether it has played.
    private var energyPassStart: CFTimeInterval?
    private var energyPassPlayed = false
    private var onTap: (() -> Void)?
    private var displayLink: CADisplayLink?
    private var requestedFrameIndex: Int?
    private var fileRequest: AnimatedFileDownload?
    private var assetTask: Task<Void, Never>?
    private var decodeTask: Task<Void, Never>?
    private var decoderSetupTask: Task<Void, Never>?
    private var configurationGeneration = UUID()
    private var decoderSetupGeneration = UUID()

    #if DEBUG
        private var decoderProbe: FFmpegAnimationWorkerProbe?
    #endif

    private var playbackEnabled: Bool {
        UserDefaults.standard.object(forKey: "animatedMediaEnabled") as? Bool ?? true
    }

    /// Power Saving holds a looping animation to a single pass, or to its first frame.
    private var energyAllowsPlayback: Bool {
        switch energySaving?.limit {
        case nil: true
        case .once: !energyPassPlayed
        case .still: false
        }
    }

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
        addSubview(downloadStatus)

        NSLayoutConstraint.activate([
            downloadStatus.centerXAnchor.constraint(equalTo: centerXAnchor),
            downloadStatus.centerYAnchor.constraint(equalTo: centerYAnchor),
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
        accessibilityLabel = L10n.betterTG("Accessibility.VideoSticker")
        accessibilityTraits = .image
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(energySavingChanged),
            name: EnergyUsage.didChange,
            object: nil,
        )
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
        decoderSetupTask?.cancel()
        decodeTask?.cancel()
        assetTask?.cancel()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlayback()
    }

    func configure(
        file: File,
        client: TDLibClient,
        thumbnail: Thumbnail?,
        displaySize: CGSize?,
        onTap: (() -> Void)?,
    ) {
        prepareForReuse()
        guard let request = AnimatedFileDownload(fileID: file.id, client: client) else { return }
        fileRequest = request
        representedFileID = file.id
        self.onTap = onTap
        isUserInteractionEnabled = onTap != nil
        apply(displaySize: displaySize)

        if let thumbnail {
            thumbnailView.load(file: thumbnail.file, accountID: request.source.accountID, client: client)
        }

        if requiresTapToDownload, !file.local.isDownloadingCompleted {
            // The thumbnail with the download arrow; once downloaded the GIF configures as usual.
            deferredDownload = DeferredMediaDownload(file: file, client: client, status: downloadStatus) {
                [weak self] completed in
                guard let self else { return }
                configure(
                    file: completed,
                    client: client,
                    thumbnail: thumbnail,
                    displaySize: displaySize,
                    onTap: onTap,
                )
            }
            isUserInteractionEnabled = true
            return
        }

        request.start(file: file, onFile: { [weak self, weak request] file in
            guard let self, let request, fileRequest === request else { return }
            update(file: file)
        }, onInvalidated: { [weak self, weak request] in
            guard let self, let request, fileRequest === request else { return }
            prepareForReuse()
        })
    }

    func prepareForReuse() {
        fileRequest?.cancel()
        fileRequest = nil
        deferredDownload = nil
        downloadStatus.hide()
        configurationGeneration = UUID()
        decoderSetupGeneration = UUID()
        decoderSetupTask?.cancel()
        decoderSetupTask = nil
        representedFileID = nil
        loadedPath = nil
        asset = nil
        decoder = nil
        requestedFrameIndex = nil
        energyPassStart = nil
        energyPassPlayed = false
        onTap = nil
        onFirstFrameReady = nil
        isUserInteractionEnabled = false
        playbackVisible = false

        assetTask?.cancel()
        assetTask = nil
        decodeTask?.cancel()
        decodeTask = nil
        stopDisplayLink()

        frameView.image = nil
        frameView.isHidden = true
        thumbnailView.isHidden = false
        thumbnailView.cancel()
        thumbnailView.image = nil
        widthConstraint.isActive = false
        heightConstraint.isActive = false
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        playbackVisible = isVisible
        updatePlayback()
    }

    private func apply(displaySize: CGSize?) {
        guard let displaySize else { return }
        widthConstraint.constant = displaySize.width
        heightConstraint.constant = displaySize.height
        widthConstraint.isActive = true
        heightConstraint.isActive = true
    }

    private func update(file: File) {
        guard let request = fileRequest, request.isCurrent,
              representedFileID == file.id,
              file.local.isDownloadingCompleted,
              !file.local.path.isEmpty,
              loadedPath != file.local.path
        else { return }

        loadedPath = file.local.path
        let fileID = file.id
        let generation = configurationGeneration
        assetTask?.cancel()
        assetTask = Task { [weak self] in
            let asset = await FFmpegVideoRepository.asset(at: file.local.path)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled,
                      request.isCurrent,
                      let self,
                      self.fileRequest === request,
                      self.configurationGeneration == generation,
                      self.representedFileID == fileID,
                      self.loadedPath == file.local.path
                else { return }
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
        if let firstFrame = asset.firstFrame {
            frameView.image = firstFrame
            frameView.isHidden = false
            thumbnailView.isHidden = true
            onFirstFrameReady?()
            onFirstFrameReady = nil
        }
        loadedPath = path
        prepareDecoder(asset: asset, path: path)
    }

    private func prepareDecoder(asset: FFmpegVideoAsset, path: String) {
        decoderSetupTask?.cancel()
        stopDisplayLink()
        decoder = nil
        let generation = UUID()
        decoderSetupGeneration = generation
        let request = fileRequest
        let preparedDecoder = FFmpegVideoFrameDecoder(asset: asset)
        #if DEBUG
            let probe = decoderProbe
        #endif
        decoderSetupTask = Task { [weak self] in
            #if DEBUG
                if let probe { await preparedDecoder.observe(with: probe) }
            #endif
            let ready = await preparedDecoder.prepare()
            guard !Task.isCancelled,
                  request?.isCurrent != false,
                  let self,
                  fileRequest === request,
                  decoderSetupGeneration == generation,
                  loadedPath == path,
                  self.asset === asset
            else { return }
            decoderSetupTask = nil
            guard ready else { return }
            decoder = preparedDecoder
            updatePlayback()
        }
        updatePlayback()
    }

    private func updatePlayback() {
        let shouldPlay = fileRequest?.isCurrent == true && playbackVisible && window != nil && playbackEnabled
            && decoder != nil && (asset?.frameCount ?? 0) > 1 && energyAllowsPlayback
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
        energyPassStart = nil
        decodeTask?.cancel()
        decodeTask = nil
        requestedFrameIndex = nil
    }

    @objc private func displayLinkFired() {
        guard fileRequest?.isCurrent == true, let asset, let path = loadedPath else { return }
        var time = CACurrentMediaTime()
        if energySaving?.limit == .once, asset.duration > 0 {
            let start = energyPassStart ?? time
            energyPassStart = start
            guard time - start < asset.duration else {
                finishEnergyPass(frameCount: asset.frameCount, path: path)
                return
            }
            time -= start
        }
        requestFrame(asset.frameIndex(at: time), path: path)
    }

    private func requestFrame(_ index: Int, path: String) {
        guard let request = fileRequest, request.isCurrent else { return }
        if let cached = FFmpegVideoRepository.frame(path: path, index: index) {
            frameView.image = cached
            frameView.isHidden = false
            thumbnailView.isHidden = true
            requestedFrameIndex = nil
            return
        }

        requestedFrameIndex = index
        guard decodeTask == nil, let decoder else { return }
        let generation = configurationGeneration
        decodeTask = Task { [weak self] in
            let frame = await decoder.frame(at: index)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled,
                      request.isCurrent,
                      let self,
                      self.fileRequest === request,
                      self.configurationGeneration == generation,
                      self.loadedPath == path,
                      self.decoder === decoder
                else { return }
                if let frame {
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
        if let deferredDownload {
            deferredDownload.isDownloading ? deferredDownload.cancel() : deferredDownload.start()
            return
        }
        onTap?()
    }

    /// A role or setting change starts over from the first frame.
    @objc private func energySavingChanged() {
        energyPassStart = nil
        energyPassPlayed = false
        stopDisplayLink()
        if energySaving?.limit != nil, let firstFrame = asset?.firstFrame {
            frameView.image = firstFrame
        }
        updatePlayback()
    }

    /// The pass reached its end: the last frame stays.
    private func finishEnergyPass(frameCount: Int, path: String) {
        energyPassPlayed = true
        energyPassStart = nil
        displayLink?.invalidate()
        displayLink = nil
        requestFrame(frameCount - 1, path: path)
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
    telegramMediaUsesFFmpeg(mimeType: animation.mimeType, fileName: animation.fileName)
}

func telegramMediaUsesFFmpeg(mimeType: String, fileName: String) -> Bool {
    let normalizedMimeType = mimeType.lowercased()
    if normalizedMimeType == "video/mp4" || normalizedMimeType == "video/quicktime" {
        return false
    }
    let fileExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
    return fileExtension != "mp4" && fileExtension != "m4v" && fileExtension != "mov"
}

func telegramVideoUsesFFmpeg(mimeType: String, fileName: String) -> Bool {
    let normalizedMimeType = mimeType.lowercased()
    let fileExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
    let appleMimeTypes: Set = ["video/mp4", "video/quicktime", "video/x-m4v"]
    let appleExtensions: Set = ["m4v", "mov", "mp4"]
    guard !appleMimeTypes.contains(normalizedMimeType),
          !appleExtensions.contains(fileExtension)
    else { return false }
    let ffmpegMimeTypes: Set = ["video/webm", "video/vp9", "video/x-matroska"]
    let ffmpegExtensions: Set = ["mkv", "webm"]
    return ffmpegMimeTypes.contains(normalizedMimeType)
        || ffmpegExtensions.contains(fileExtension)
}

#if DEBUG
    /// Records native operations only; the C handle never leaves its actor executor.
    fileprivate final class FFmpegAnimationWorkerProbe: @unchecked Sendable {
        private let lock = NSLock()
        private let setupGate = DispatchSemaphore(value: 0)
        private let holdsSetup: Bool
        private var events = [String]()
        private var ranOnMain = false

        init(holdsSetup: Bool = false) {
            self.holdsSetup = holdsSetup
        }

        func record(_ event: String) {
            lock.lock()
            events.append(event)
            ranOnMain = ranOnMain || Thread.isMainThread
            lock.unlock()
        }

        func snapshot() -> (events: [String], ranOnMain: Bool) {
            lock.lock()
            defer { lock.unlock() }
            return (events, ranOnMain)
        }

        func holdSetupIfRequested() {
            guard holdsSetup else { return }
            record("setup-held")
            if setupGate.wait(timeout: .now() + 5) == .timedOut {
                record("setup-timeout")
            }
        }

        func releaseSetup() {
            setupGate.signal()
        }
    }

    @MainActor extension FFmpegAnimatedVideoView {
        static func runDebugProbeIfRequested() {
            FFmpegAnimationTimingProbe.runDebugProbeIfRequested()
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-animation-worker") else { return }
            Task { await runAnimationWorkerProbe() }
        }
    }

    private extension FFmpegAnimatedVideoView {
        enum WorkerProbeError: Swift.Error {
            case asset, setup, frame, timeout, lifecycle, staleSetup
        }

        @MainActor static func runAnimationWorkerProbe() async {
            let fixtureURL = FileManager.default
.temporaryDirectory
                .appendingPathComponent("bettertg-animation-worker-\(UUID().uuidString).webm")
            let resultURL = FileManager.default
.urls(for: .documentDirectory, in: .userDomainMask)
                .first?
.appendingPathComponent("animation-worker-probe.txt")
            defer { try? FileManager.default.removeItem(at: fixtureURL) }
            let heldProbe = FFmpegAnimationWorkerProbe(holdsSetup: true)
            defer { heldProbe.releaseSetup() }
            let result: String
            do {
                try await Task.detached(priority: .userInitiated) {
                    try FFmpegVODProbeFixture.write(to: fixtureURL)
                }.value
                guard let asset = await FFmpegVideoRepository.asset(at: fixtureURL.path) else {
                    throw WorkerProbeError.asset
                }
                let lifecycleProbe = FFmpegAnimationWorkerProbe()
                var worker: FFmpegVideoFrameDecoder? = FFmpegVideoFrameDecoder(asset: asset)
                await worker?.observe(with: lifecycleProbe)
                guard await worker?.prepare() == true else { throw WorkerProbeError.setup }
                guard await worker?.frame(at: 2) != nil,
                      await worker?.frame(at: 1) != nil
                else { throw WorkerProbeError.frame }
                // Release the last owner on main; native destruction must still use the worker.
                worker = nil
                try await waitForWorkerProbe { lifecycleProbe.snapshot().events.contains("destroy") }

                let view = FFmpegAnimatedVideoView()
                view.decoderProbe = heldProbe
                view.show(asset: asset, path: asset.path)
                try await waitForWorkerProbe { heldProbe.snapshot().events.contains("setup-held") }
                view.prepareForReuse()

                let replacementProbe = FFmpegAnimationWorkerProbe()
                view.decoderProbe = replacementProbe
                view.show(asset: asset, path: asset.path)
                try await waitForWorkerProbe { view.decoder != nil }
                let replacementID = view.decoder.map(ObjectIdentifier.init)
                heldProbe.releaseSetup()
                try await waitForWorkerProbe { heldProbe.snapshot().events.contains("destroy") }
                guard view.decoder.map(ObjectIdentifier.init) == replacementID,
                      view.frameView.image != nil,
                      !view.frameView.isHidden
                else { throw WorkerProbeError.staleSetup }
                view.prepareForReuse()
                try await waitForWorkerProbe { replacementProbe.snapshot().events.contains("destroy") }

                let lifecycle = lifecycleProbe.snapshot()
                let held = heldProbe.snapshot()
                let replacement = replacementProbe.snapshot()
                guard !lifecycle.ranOnMain, !held.ranOnMain, !replacement.ranOnMain,
                      lifecycle.events.count(where: { $0 == "create" }) == 1,
                      lifecycle.events.contains("read"), lifecycle.events.contains("reset"),
                      lifecycle.events.count(where: { $0 == "destroy" }) == 1,
                      held.events.count(where: { $0 == "destroy" }) == 1,
                      !held.events.contains("setup-timeout"),
                      replacement.events.count(where: { $0 == "destroy" }) == 1
                else { throw WorkerProbeError.lifecycle }
                result = "Animation worker probe: create/read/reset/destroy-off-main=true, "
                    + "main-release-worker-destroy=true, delayed-setup-cancel=true, "
                    + "same-path-reuse-fenced=true, replacement-ready=true, first-frame-preserved=true, "
                    + "exactly-once-teardown=true, native-reads=\(lifecycle.events.count(where: { $0 == "read" }))"
            } catch {
                result = "Animation worker probe failed: \(error)"
            }
            if let resultURL { try? Data(result.utf8).write(to: resultURL, options: .atomic) }
            log(result)
        }

        @MainActor static func waitForWorkerProbe(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(4))
            while !condition() {
                guard ContinuousClock.now < deadline else { throw WorkerProbeError.timeout }
                try await Task<Never, Never>.sleep(for: .milliseconds(10))
            }
        }
    }
#endif
