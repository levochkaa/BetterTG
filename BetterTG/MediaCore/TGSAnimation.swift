// TGSAnimation.swift

import Combine
import Foundation
import Lottie
import QuartzCore
import RLottie
import TDLibKit
import UIKit

// MARK: - TGSAnimationRepository

enum TGSAnimationRepository {
    // MARK: Private

    private static let cache: NSCache<NSString, LottieAnimation> = {
        let cache = NSCache<NSString, LottieAnimation>()
        cache.countLimit = 64
        return cache
    }()

    // MARK: Internal

    static func animation(at path: String) async -> LottieAnimation? {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let decodeTask = Task.detached(priority: .userInitiated) { () -> LottieAnimation? in
            guard !Task.isCancelled,
                  let compressed = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
                  !Task.isCancelled,
                  let json = try? decompressTGS(compressed),
                  !Task.isCancelled,
                  let animation = try? LottieAnimation.from(data: json, strategy: .legacyCodable)
            else { return nil }
            cache.setObject(animation, forKey: key)
            return animation
        }

        return await withTaskCancellationHandler {
            await decodeTask.value
        } onCancel: {
            decodeTask.cancel()
        }
    }
}

// MARK: - TGSFrameSource

/// One TGS file in rlottie at one size, as Telegram's AnimatedStickerNode renders stickers and emoji: frames render off
/// the main thread, on the source's own queue, into bitmaps. Small frames (emoji, statuses, reactions) stay cached, so
/// a
/// loop renders each once; a sticker's large frames render each time, as Telegram's direct mode does.
final class TGSFrameSource: @unchecked Sendable {
    // MARK: Private

    /// Frames up to this many pixels are kept: a 50 pt emoji at 3x.
    private static let cachedFrameArea = 150 * 150

    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private static let frameCache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    // MARK: Internal

    let frameCount: Int
    let frameRate: Double
    let pixelWidth: Int
    let pixelHeight: Int
    /// The larger side the source was made for, which a view compares its own size with.
    let maximumSide: Int

    private let animation: OpaquePointer
    private let queue: DispatchQueue
    private let frameKeyPrefix: String
    private let cachesFrames: Bool
    private let lock = NSLock()
    private var waiters = [Int: [@MainActor (CGImage?) -> Void]]()

    var duration: TimeInterval {
        Double(frameCount) / frameRate
    }

    var lastFrame: Int {
        frameCount - 1
    }

    deinit {
        rlottie_bridge_destroy(animation)
    }

    /// `cacheKey` names the file in rlottie's model cache, so another size of it skips parsing.
    fileprivate init?(json: Data, cacheKey: String, maximumSide: Int) {
        guard let animation = json.withUnsafeBytes({ buffer -> OpaquePointer? in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: CChar.self) else { return nil }
            return rlottie_bridge_create(base, buffer.count, cacheKey)
        }) else { return nil }
        self.animation = animation
        self.frameCount = Int(rlottie_bridge_frame_count(animation))
        self.frameRate = rlottie_bridge_frame_rate(animation)
        var width = 0
        var height = 0
        rlottie_bridge_size(animation, &width, &height)
        // The animation's own aspect, fitted into the requested side.
        let scale = Double(maximumSide) / Double(max(width, height))
        self.pixelWidth = max(1, Int((Double(width) * scale).rounded()))
        self.pixelHeight = max(1, Int((Double(height) * scale).rounded()))
        self.maximumSide = maximumSide
        self.cachesFrames = pixelWidth * pixelHeight <= Self.cachedFrameArea
        self.frameKeyPrefix = "\(cacheKey)|\(pixelWidth)x\(pixelHeight)#"
        self.queue = DispatchQueue(label: "com.bettertg.tgs-render", qos: .userInitiated)
    }

    private static func pageRounded(_ length: Int) -> Int {
        let page = Int(vm_page_size)
        return (length + page - 1) / page * page
    }

    // MARK: Internal

    /// The frame `time` seconds into a loop.
    func loopFrame(at time: TimeInterval) -> Int {
        Int((time * frameRate).rounded(.down)) % frameCount
    }

    func cachedFrame(_ index: Int) -> CGImage? {
        cachesFrames ? Self.frameCache.object(forKey: frameKey(index)) : nil
    }

    /// Renders `index` off the main thread; requests for a frame already rendering share it.
    @MainActor func frame(_ index: Int, completion: @escaping @MainActor (CGImage?) -> Void) {
        if let cached = cachedFrame(index) {
            completion(cached)
            return
        }
        lock.lock()
        let rendering = waiters[index] != nil
        waiters[index, default: []].append(completion)
        lock.unlock()
        guard !rendering else { return }
        queue.async { [self] in
            let image = render(index)
            if let image, cachesFrames {
                Self.frameCache.setObject(image, forKey: frameKey(index), cost: pixelWidth * pixelHeight * 4)
            }
            lock.lock()
            let completions = waiters.removeValue(forKey: index) ?? []
            lock.unlock()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for completion in completions {
                        completion(image)
                    }
                }
            }
        }
    }

    private func frameKey(_ index: Int) -> NSString {
        "\(frameKeyPrefix)\(index)" as NSString
    }

    /// Premultiplied BGRA in sRGB, the order rlottie writes on Apple platforms, in page-aligned memory with 64-byte
    /// rows, as Texture's ASCGImageBuffer and Telegram's DrawingContext allocate it: Core Animation then maps the
    /// pixels into the render server instead of copying each frame on the main thread.
    private func render(_ index: Int) -> CGImage? {
        let bytesPerRow = (pixelWidth * 4 + 63) & ~63
        let length = bytesPerRow * pixelHeight
        var address: vm_address_t = 0
        // vm_allocate hands out zeroed pages, so the frame starts transparent.
        guard vm_allocate(mach_task_self_, &address, vm_size_t(Self.pageRounded(length)), VM_FLAGS_ANYWHERE)
            == KERN_SUCCESS,
            let pixels = UnsafeMutableRawPointer(bitPattern: UInt(address))
        else { return nil }
        rlottie_bridge_render(
            animation,
            Int32(min(max(0, index), lastFrame)),
            pixels.assumingMemoryBound(to: UInt32.self),
            pixelWidth,
            pixelHeight,
            bytesPerRow,
        )
        guard let provider = CGDataProvider(dataInfo: nil, data: pixels, size: length, releaseData: { _, data, size in
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: data)),
                vm_size_t(TGSFrameSource.pageRounded(size)),
            )
        }) else {
            vm_deallocate(mach_task_self_, address, vm_size_t(Self.pageRounded(length)))
            return nil
        }
        return CGImage(
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: Self.colorSpace,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue,
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent,
        )
    }
}

// MARK: - TGSFrameSourceRepository

enum TGSFrameSourceRepository {
    private actor Loader {
        private var tasks = [String: Task<TGSFrameSource?, Never>]()

        func source(key: String, load: @escaping @Sendable () -> TGSFrameSource?) async -> TGSFrameSource? {
            if let task = tasks[key] { return await task.value }
            let task = Task.detached(priority: .userInitiated) { load() }
            tasks[key] = task
            let source = await task.value
            tasks[key] = nil
            return source
        }
    }

    /// A sticker's side is rounded up to this, so nearby sizes share a source.
    private static let sideStep = 8
    /// Larger views scale the frames up: a gallery sticker stays sharp enough, and a frame stays affordable to render.
    private static let maximumSide = 720

    private static let sources: NSCache<NSString, TGSFrameSource> = {
        let cache = NSCache<NSString, TGSFrameSource>()
        cache.countLimit = 96
        return cache
    }()

    private static let loader = Loader()

    /// The side, in pixels, a view of `pointSize` at `scale` renders at.
    static func side(for pointSize: CGSize, scale: CGFloat) -> Int {
        let pixels = Int((max(pointSize.width, pointSize.height) * scale).rounded(.up))
        let stepped = (max(1, pixels) + sideStep - 1) / sideStep * sideStep
        return min(stepped, maximumSide)
    }

    static func source(path: String, side: Int) async -> TGSFrameSource? {
        let key = "\(path)|\(side)"
        if let cached = sources.object(forKey: key as NSString) { return cached }
        let source = await loader.source(key: key) {
            guard let compressed = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
                  let json = try? decompressTGS(compressed)
            else { return nil }
            return TGSFrameSource(json: json, cacheKey: path, maximumSide: side)
        }
        if let source { sources.setObject(source, forKey: key as NSString) }
        return source
    }

    /// Parses the file into rlottie's model cache ahead of a view, as a downloaded message's media is prepared.
    static func prepare(path: String) async {
        _ = await source(path: path, side: 64)
    }
}

// MARK: - TGSStickerView

/// A TGS sticker or emoji drawn from rlottie frames rendered off the main thread, as Telegram draws them.
final class TGSStickerView: UIControl, AnimatedFileView {
    /// How the sticker plays once loaded. Dice use the play-once and still-end modes, as Telegram's
    /// ManagedDiceAnimationNode plays a fresh roll once and shows an old roll at its last frame.
    enum PlaybackMode: Equatable {
        case loop
        /// Plays from the point the roll reached since `startedAt` (a `CACurrentMediaTime` value) to the end and
        /// holds the last frame.
        case once(startedAt: CFTimeInterval)
        case stillEnd
    }

    // MARK: Internal

    var onFirstFrameReady: (() -> Void)?

    var energySaving: EnergySavingRole? {
        didSet { energySavingChanged() }
    }

    var loopLimit: Int? {
        didSet { if loopLimit != oldValue { energySavingChanged() } }
    }

    var templateColor: UIColor? {
        didSet {
            guard templateColor != oldValue else { return }
            thumbnailView.templateColor = templateColor
            frameView.templateColor = templateColor
        }
    }

    var playbackMode = PlaybackMode.loop {
        didSet {
            guard playbackMode != oldValue else { return }
            restartPlayback()
        }
    }

    // MARK: Private

    private let thumbnailView = TDImageLoadingView()
    private let frameView = AnimationFrameView()
    private lazy var widthConstraint = widthAnchor.constraint(equalToConstant: 180)
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 180)
    private var representedFileID: Int?
    private var loadedPath: String?
    private var playbackVisible = false
    private var onTap: (() -> Void)?
    private var fileRequest: AnimatedFileDownload?
    private var loadTask: Task<Void, Never>?
    private var source: TGSFrameSource?
    private var displayLink: CADisplayLink?
    /// The frame on screen, the latest one asked for, and whether a render for this view is under way.
    private var shownFrame: Int?
    private var wantedFrame: Int?
    private var isRendering = false
    /// When Power Saving's single pass or `loopLimit`'s loops started, and whether they have played.
    private var passStart: CFTimeInterval?
    private var energyPassPlayed = false
    private var limitedLoopsPlayed = false

    /// The decoded animation's frames per second, once it has loaded.
    var framerate: Double? {
        source?.frameRate
    }

    private var playbackEnabled: Bool {
        UserDefaults.standard.object(forKey: "animatedMediaEnabled") as? Bool ?? true
    }

    private var isShown: Bool {
        fileRequest?.isCurrent == true && playbackVisible && window != nil
    }

    /// The side the view needs its frames at.
    private var neededSide: Int {
        var size = bounds.size
        if size.width < 1 || size.height < 1 {
            size = widthConstraint.isActive
                ? CGSize(width: widthConstraint.constant, height: heightConstraint.constant)
                : CGSize(width: 160, height: 160)
        }
        let scale = window?.screen.scale ?? max(traitCollection.displayScale, 1)
        return TGSFrameSourceRepository.side(for: size, scale: scale)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        thumbnailView.contentMode = .scaleAspectFit
        for view in [thumbnailView, frameView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.isUserInteractionEnabled = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        frameView.isHidden = true

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityLabel = L10n.telegram("VoiceOver.Chat.AnimatedSticker")
        accessibilityTraits = .image
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackHoldChanged),
            name: TGSPlaybackHold.didChange,
            object: nil,
        )
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
        loadTask?.cancel()
        displayLink?.invalidate()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlayback()
    }

    /// A view that grows well past its frames' size (a sticker opened in the gallery) renders them again at the new
    /// size; the current frames stay until the new ones arrive.
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let source, let path = loadedPath, loadTask == nil else { return }
        let side = neededSide
        guard Double(side) > Double(source.maximumSide) * 1.25 else { return }
        load(path: path, side: side)
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
        representedFileID = nil
        loadedPath = nil
        onTap = nil
        onFirstFrameReady = nil
        isUserInteractionEnabled = false
        playbackVisible = false

        loadTask?.cancel()
        loadTask = nil
        stopDisplayLink()
        source = nil
        shownFrame = nil
        wantedFrame = nil
        isRendering = false
        passStart = nil
        energyPassPlayed = false
        limitedLoopsPlayed = false
        playbackMode = .loop
        frameView.show(nil)
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

    fileprivate func tick() {
        let plan = plannedFrame(now: CACurrentMediaTime())
        request(plan.index)
        if plan.finished { stopDisplayLink() }
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
        load(path: file.local.path, side: neededSide)
    }

    private func load(path: String, side: Int) {
        guard let request = fileRequest else { return }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let source = await TGSFrameSourceRepository.source(path: path, side: side)
            guard !Task.isCancelled, request.isCurrent, let self, fileRequest === request, loadedPath == path
            else { return }
            loadTask = nil
            guard let source else { return }
            show(source: source)
        }
    }

    private func show(source: TGSFrameSource) {
        let replacing = self.source != nil
        self.source = source
        isRendering = false
        // A new size shows the same frame again.
        let frame = replacing ? shownFrame : nil
        shownFrame = nil
        request(frame ?? restingFrame(now: CACurrentMediaTime()))
        updatePlayback()
    }

    /// The frame the mode shows now, and whether playback has reached its resting frame.
    private func plannedFrame(now: CFTimeInterval) -> (index: Int, finished: Bool) {
        guard let source else { return (0, true) }
        switch playbackMode {
        case .stillEnd:
            return (source.lastFrame, true)
        case .once(let startedAt):
            // With autoplay off the result stays readable at the roll's last frame.
            guard playbackEnabled else { return (source.lastFrame, true) }
            let frame = Int(((now - startedAt) * source.frameRate).rounded(.down))
            return frame >= source.lastFrame ? (source.lastFrame, true) : (max(0, frame), false)
        case .loop:
            if let limit = energySaving?.limit {
                // Power Saving: a single pass from the first frame, or the first frame alone.
                guard limit == .once, !energyPassPlayed else {
                    return (limit == .once ? source.lastFrame : 0, true)
                }
                let frame = elapsedFrames(now: now, source: source)
                guard frame < source.lastFrame else {
                    energyPassPlayed = true
                    passStart = nil
                    return (source.lastFrame, true)
                }
                return (frame, false)
            }
            if let loopLimit {
                // InlineStickerItemLayer's loopCount: then the first frame until the view is shown again.
                guard !limitedLoopsPlayed else { return (0, true) }
                let frame = elapsedFrames(now: now, source: source)
                guard frame < source.frameCount * loopLimit else {
                    limitedLoopsPlayed = true
                    passStart = nil
                    return (0, true)
                }
                return (frame % source.frameCount, false)
            }
            // The shared clock keeps equal stickers in step.
            return (source.loopFrame(at: now), false)
        }
    }

    /// The frame a player that isn't playing shows, without starting a pass.
    private func restingFrame(now: CFTimeInterval) -> Int {
        guard let source else { return 0 }
        switch playbackMode {
        case .stillEnd:
            return source.lastFrame
        case .once(let startedAt):
            guard playbackEnabled else { return source.lastFrame }
            return min(source.lastFrame, max(0, Int(((now - startedAt) * source.frameRate).rounded(.down))))
        case .loop:
            if let limit = energySaving?.limit { return limit == .once && energyPassPlayed ? source.lastFrame : 0 }
            if loopLimit != nil { return 0 }
            return source.loopFrame(at: now)
        }
    }

    private func elapsedFrames(now: CFTimeInterval, source: TGSFrameSource) -> Int {
        let start = passStart ?? now
        passStart = start
        return Int(((now - start) * source.frameRate).rounded(.down))
    }

    private func updatePlayback() {
        // A hidden player plays its limited loops again when shown, as InlineStickerItemLayer resets its count; a
        // pass under way starts over.
        if !isShown {
            limitedLoopsPlayed = false
            passStart = nil
        }
        guard source != nil else {
            stopDisplayLink()
            return
        }
        // A hold keeps players that haven't started where they are, and one that pauses stops those playing too.
        let held = TGSPlaybackHold.pausesPlayback || (TGSPlaybackHold.isActive && displayLink == nil)
        guard isShown, playbackEnabled || playbackMode != .loop, !held else {
            stopDisplayLink()
            if shownFrame == nil { request(restingFrame(now: CACurrentMediaTime())) }
            return
        }
        let plan = plannedFrame(now: CACurrentMediaTime())
        request(plan.index)
        if plan.finished {
            stopDisplayLink()
        } else {
            startDisplayLink()
        }
    }

    private func restartPlayback() {
        energyPassPlayed = false
        limitedLoopsPlayed = false
        passStart = nil
        guard source != nil else { return }
        stopDisplayLink()
        shownFrame = nil
        request(restingFrame(now: CACurrentMediaTime()))
        updatePlayback()
    }

    private func startDisplayLink() {
        guard displayLink == nil, let source else { return }
        let link = CADisplayLink(target: TGSDisplayLinkTarget(self), selector: #selector(TGSDisplayLinkTarget.tick))
        let rate = Float(min(60, source.frameRate))
        link.preferredFrameRateRange = ProcessInfo.processInfo.isLowPowerModeEnabled
            ? CAFrameRateRange(minimum: min(15, rate), maximum: min(30, rate), preferred: min(30, rate))
            : CAFrameRateRange(minimum: min(15, rate), maximum: rate, preferred: rate)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Shows `index` at once when it is cached, or renders it. One render runs at a time, so a frame that misses its
    /// moment is skipped; the latest one asked for follows the render under way.
    private func request(_ index: Int) {
        guard let source else { return }
        wantedFrame = index
        guard index != shownFrame else { return }
        if let cached = source.cachedFrame(index) {
            show(cached, index: index)
            return
        }
        guard !isRendering else { return }
        isRendering = true
        source.frame(index) { [weak self, weak source] image in
            guard let self, let source, self.source === source else { return }
            isRendering = false
            if let image { show(image, index: index) }
            if let wanted = wantedFrame, wanted != index, wanted != shownFrame { request(wanted) }
        }
    }

    private func show(_ image: CGImage, index: Int) {
        frameView.show(image)
        shownFrame = index
        guard frameView.isHidden else { return }
        frameView.isHidden = false
        thumbnailView.isHidden = true
        onFirstFrameReady?()
        onFirstFrameReady = nil
    }

    @objc private func tapped() {
        onTap?()
    }

    /// A role or setting change starts over: the first frame while held, the shared phase while looping.
    @objc private func energySavingChanged() {
        guard case .loop = playbackMode else { return }
        restartPlayback()
    }

    /// A hold that pauses playback stops a playing sticker on its current frame; its end resumes them one per frame.
    @objc private func playbackHoldChanged() {
        if TGSPlaybackHold.pausesPlayback {
            stopDisplayLink()
            return
        }
        guard !TGSPlaybackHold.isActive, window != nil, playbackVisible, source != nil,
              displayLink == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + TGSPlaybackHold.nextResumeDelay()) { [weak self] in
            self?.updatePlayback()
        }
    }
}

// MARK: - TGSDisplayLinkTarget

/// CADisplayLink retains its target; this one holds the view weakly, so a view leaving the screen is freed.
private final class TGSDisplayLinkTarget: NSObject {
    private weak var view: TGSStickerView?

    init(_ view: TGSStickerView) {
        self.view = view
    }

    @MainActor @objc func tick() {
        view?.tick()
    }
}

// MARK: - TGSPlaybackHold

/// Keeps animated stickers and emoji that start playing on their current frame while a hold is active. Lottie's Core
/// Animation engine builds each animation on the main thread when it starts, and a chat coming back under a closing
/// gallery restarted all of them at once, which delayed the drag and slowed it to about 30 Hz. Telegram renders them
/// off the main thread; here the chat stays on its frames until the gallery has landed.
@MainActor final class TGSPlaybackHold {
    // MARK: Internal

    static let didChange = Notification.Name("TGSPlaybackHoldDidChange")

    // MARK: Private

    private static var activeCount = 0
    private static var pausingCount = 0
    private static var resumeOrder = 0

    static var isActive: Bool { activeCount > 0 }

    /// Whether stickers already playing stop on their current frame too, not only those about to start.
    static var pausesPlayback: Bool { pausingCount > 0 }

    private let pausesPlaying: Bool
    private var isReleased = false

    init(pausesPlaying: Bool = false) {
        self.pausesPlaying = pausesPlaying
        if Self.activeCount == 0 { Self.resumeOrder = 0 }
        Self.activeCount += 1
        guard pausesPlaying else { return }
        Self.pausingCount += 1
        if Self.pausingCount == 1 { NotificationCenter.default.post(name: Self.didChange, object: nil) }
    }

    /// A transition that ends without releasing (for example, a torn-down context) must not freeze stickers.
    isolated deinit { release() }

    /// Spreads resumptions over frames, one per 1/60 s.
    static func nextResumeDelay() -> TimeInterval {
        defer { resumeOrder += 1 }
        return TimeInterval(resumeOrder) / 60
    }

    func release() {
        guard !isReleased else { return }
        isReleased = true
        if pausesPlaying { Self.pausingCount -= 1 }
        Self.activeCount -= 1
        guard Self.activeCount == 0 else { return }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
