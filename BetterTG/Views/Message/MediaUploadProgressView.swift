// MediaUploadProgressView.swift

import Combine
import TDLibKit
import UIKit

// MARK: - MediaUploadProgressRegistry

/// Upload overlay state that outlives a row reconfiguration. An album recreates its tiles whenever one of its
/// messages changes, and TDLib replaces a sent message with a new ID; Telegram keeps the same media node across both,
/// so the arc neither restarts nor vanishes before its fade-out ends.
@MainActor enum MediaUploadProgressRegistry {
    struct Key: Hashable {
        let chatID: Int64
        let messageID: Int64
    }

    struct State {
        var progress: CGFloat
        var finishedAt: CFTimeInterval?
        var updatedAt: CFTimeInterval
    }

    private static let capacity = 64
    private static var states = [Key: State]()
    /// Uploaded photo originals, which TDLib keeps on disk after the sent message switches to remote sizes.
    private static var localPhotos = [Key: File]()
    /// Sent message ID to the ID it had while pending. TDLib assigns server IDs above every pending ID, one message
    /// at a time, so ordering a half-sent album by ID would move its sent members to the end for a moment.
    private static var sendOrderIDs = [Key: Int64]()
    /// Decoded previews of photos this session sends, by the local path TDLib uploads them from.
    private static var sentPreviews = [String: (image: UIImage, addedAt: CFTimeInterval)]()

    static func state(for key: Key) -> State? {
        prune()
        return states[key]
    }

    static func record(_ key: Key, progress: CGFloat? = nil, finishedAt: CFTimeInterval? = nil) {
        let now = CACurrentMediaTime()
        var state = states[key] ?? State(progress: 0, updatedAt: now)
        if let progress { state.progress = max(state.progress, progress) }
        if let finishedAt, state.finishedAt == nil { state.finishedAt = finishedAt }
        state.updatedAt = now
        states[key] = state
        if states.count > capacity, let oldest = states.min(by: { $0.value.updatedAt < $1.value.updatedAt })?.key {
            states[oldest] = nil
        }
    }

    static func remove(_ key: Key) {
        states[key] = nil
    }

    /// Telegram stores the composer's image in the cache of the message it sends (`applyMediaResourceChanges`), so the
    /// new bubble draws on its first frame instead of after the original decodes.
    static func rememberSentPreview(_ image: UIImage, path: String) {
        let now = CACurrentMediaTime()
        sentPreviews = sentPreviews.filter { now - $0.value.addedAt < 120 }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        for key in Set([path, resolved]) {
            sentPreviews[key] = (image, now)
        }
        while sentPreviews.count > 20,
              let oldest = sentPreviews.min(by: { $0.value.addedAt < $1.value.addedAt })?.key
        {
            sentPreviews[oldest] = nil
        }
    }

    static func sentPreview(forPath path: String) -> UIImage? {
        path.isEmpty ? nil : sentPreviews[path]?.image
    }

    static func rememberLocalPhoto(_ file: File, for key: Key) {
        localPhotos[key] = file
        if localPhotos.count > capacity, let any = localPhotos.keys.first(where: { $0 != key }) {
            localPhotos[any] = nil
        }
    }

    static func localPhoto(for key: Key) -> File? {
        guard let file = localPhotos[key] else { return nil }
        guard FileManager.default.fileExists(atPath: file.local.path) else {
            localPhotos[key] = nil
            return nil
        }
        return file
    }

    /// The sent message continues the pending message's fade-out (`ChatMessageInteractiveMediaNode` keeps its node).
    static func noteSendSucceeded(chatID: Int64, oldMessageID: Int64, newMessageID: Int64) {
        let old = Key(chatID: chatID, messageID: oldMessageID)
        let new = Key(chatID: chatID, messageID: newMessageID)
        sendOrderIDs[new] = sendOrderIDs.removeValue(forKey: old) ?? oldMessageID
        if sendOrderIDs.count > capacity * 4, let any = sendOrderIDs.keys.first(where: { $0 != new }) {
            sendOrderIDs[any] = nil
        }
        if let photo = localPhotos.removeValue(forKey: old) { localPhotos[new] = photo }
        guard let state = states.removeValue(forKey: old) else { return }
        let now = CACurrentMediaTime()
        states[new] = State(
            progress: 1,
            finishedAt: state.finishedAt ?? now,
            updatedAt: now,
        )
    }

    /// The order of `message` among its album: its pending ID when this session sent it, else its ID.
    static func sendOrderID(of message: Message) -> Int64 {
        sendOrderIDs[Key(chatID: message.chatId, messageID: message.id)] ?? message.id
    }

    private static func prune() {
        let now = CACurrentMediaTime()
        states = states.filter { _, state in
            guard let finishedAt = state.finishedAt else { return true }
            return now - finishedAt < 1
        }
    }
}

/// The local file to show for `photo` instead of its `preferred` size, or nil to load that size. Telegram copies an
/// uploaded photo into the cache of its sent representation (`applyMediaResourceChanges`), so a sent bubble never
/// drops to the blurred minithumbnail. TDLib keeps the original on disk but describes the sent photo with remote
/// sizes: use a downloaded size at least as large as the preferred one, else the uploaded original.
@MainActor func telegramLocalPhotoFile(for message: Message?, photo: Photo, preferred: PhotoSizeType) -> File? {
    let area: (PhotoSize, PhotoSize) -> Bool = { $0.width * $0.height < $1.width * $1.height }
    let key = message.map { MediaUploadProgressRegistry.Key(chatID: $0.chatId, messageID: $0.id) }
    if let key, let message, case .messageSendingStatePending = message.sendingState,
       let original = photo.sizes.filter(\.photo.local.isDownloadingCompleted).max(by: area)
    {
        MediaUploadProgressRegistry.rememberLocalPhoto(original.photo, for: key)
    }
    let target = photo.sizes.getSize(preferred)
    if target?.photo.local.isDownloadingCompleted == true { return nil }
    let minimumSide = target.map { max($0.width, $0.height) } ?? 0
    if let local = photo.sizes
        .filter({ $0.photo.local.isDownloadingCompleted && max($0.width, $0.height) >= minimumSide })
        .min(by: area)
    {
        return local.photo
    }
    return key.flatMap(MediaUploadProgressRegistry.localPhoto(for:))
}

// MARK: - MediaUploadProgressView

/// Telegram's radial status for a photo, video or GIF that is still uploading (`ChatMessageInteractiveMediaNode`,
/// `RadialProgressContentNode`): a dark disc with a rotating arc for the uploaded share and a cancel cross. A tap
/// on the disc cancels the send.
final class MediaUploadProgressView: UIControl {
    // MARK: Private

    private static let minimumProgress: CGFloat = 0.027
    private static let fadeDuration: CFTimeInterval = 0.25

    override var intrinsicContentSize: CGSize { CGSize(width: diameter, height: diameter) }

    // MARK: Internal

    /// Called when the overlay appears or finishes, so the host can hide its play icon and ignore other taps.
    var onActiveChange: ((Bool) -> Void)?

    private(set) var isActive = false

    var diameter: CGFloat = 50 {
        didSet {
            guard diameter != oldValue else { return }
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    private let arcContainer = CALayer()
    private let arcLayer = CAShapeLayer()
    private let crossLayer = CAShapeLayer()
    private var cancellable: AnyCancellable?
    private var seedTask: Task<Void, Never>?
    private var onCancel: (() -> Void)?
    private var progress = MediaUploadProgressView.minimumProgress
    private var generation = UUID()
    private var registryKey: MediaUploadProgressRegistry.Key?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true
        clipsToBounds = true
        // mediaOverlayControlColors: black 45% in the day theme, 60% in the night theme.
        backgroundColor = UIColor { traits in
            UIColor.black.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.6 : 0.45)
        }
        for shape in [arcLayer, crossLayer] {
            shape.fillColor = UIColor.clear.cgColor
            shape.strokeColor = UIColor.white.cgColor
            shape.lineCap = .round
        }
        arcLayer.strokeStart = 0
        arcLayer.strokeEnd = Self.minimumProgress
        arcContainer.addSublayer(arcLayer)
        layer.addSublayer(arcContainer)
        layer.addSublayer(crossLayer)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = L10n.telegram("Common.Cancel")
        addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = bounds.width
        layer.cornerRadius = side / 2
        let factor = side / 50
        let arcWidth = max(1.6, 2.25 * factor)
        let pathDiameter = side - arcWidth - 2.5 * 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arcContainer.frame = bounds
        arcLayer.frame = arcContainer.bounds
        arcLayer.lineWidth = arcWidth
        arcLayer.path = UIBezierPath(
            arcCenter: CGPoint(x: side / 2, y: side / 2),
            radius: pathDiameter / 2,
            startAngle: -.pi / 2,
            endAngle: .pi * 3 / 2,
            clockwise: true,
        ).cgPath
        crossLayer.frame = bounds
        crossLayer.lineWidth = max(1.3, 2 * factor)
        let cross = 14 * factor
        let path = UIBezierPath()
        path.move(to: CGPoint(x: side / 2 - cross / 2, y: side / 2 - cross / 2))
        path.addLine(to: CGPoint(x: side / 2 + cross / 2, y: side / 2 + cross / 2))
        path.move(to: CGPoint(x: side / 2 + cross / 2, y: side / 2 - cross / 2))
        path.addLine(to: CGPoint(x: side / 2 - cross / 2, y: side / 2 + cross / 2))
        crossLayer.path = path.cgPath
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, isActive { startRotation() }
    }

    /// The file a pending message uploads, or nil when the message is sent or carries no uploadable media.
    static func pendingFile(of message: Message) -> File? {
        guard case .messageSendingStatePending = message.sendingState else { return nil }
        return switch message.content {
        case .messagePhoto(let photo):
            photo.photo.sizes.max { $0.width * $0.height < $1.width * $1.height }?.photo
        case .messageVideo(let video):
            video.video.video
        case .messageAnimation(let animation):
            animation.animation.animation
        default:
            nil
        }
    }

    /// Shows the overlay while `message` uploads its media and follows `updateFile` until the upload completes. A
    /// reconfigured or replacement row resumes the recorded progress or fade-out.
    func configure(message: Message, client: TDLibClient, onCancel: @escaping () -> Void) {
        reset()
        let key = MediaUploadProgressRegistry.Key(chatID: message.chatId, messageID: message.id)
        let saved = MediaUploadProgressRegistry.state(for: key)
        guard let file = Self.pendingFile(of: message),
              !file.remote.isUploadingCompleted,
              saved?.finishedAt == nil,
              let origin = TDImageOrigin.captured(client: client)
        else {
            // Sent, or uploaded while this row was rebuilt: finish the fade the previous overlay began.
            guard let saved else { return }
            registryKey = key
            setActive(true)
            resumeFinish(from: saved.finishedAt ?? CACurrentMediaTime())
            return
        }
        registryKey = key
        self.onCancel = onCancel
        let generation = generation
        setActive(true)
        if let saved, saved.progress > progress {
            progress = saved.progress
            arcLayer.strokeEnd = saved.progress
        }
        apply(file, animated: false)
        cancellable = TDImageLoadingView.fileUpdates(source: origin.source, fileID: file.id)
            .sink { [weak self] in self?.apply($0, animated: true) }
        // The message carries the file as it was when the message was loaded; read the current upload state.
        seedTask = Task { [weak self] in
            guard let current = try? await client.getFile(fileId: file.id),
                  let self, self.generation == generation
            else { return }
            apply(current, animated: false)
        }
    }

    func reset() {
        generation = UUID()
        registryKey = nil
        cancellable = nil
        seedTask?.cancel()
        seedTask = nil
        onCancel = nil
        progress = Self.minimumProgress
        layer.removeAllAnimations()
        crossLayer.removeAllAnimations()
        arcLayer.removeAllAnimations()
        arcContainer.removeAllAnimations()
        arcLayer.strokeEnd = Self.minimumProgress
        alpha = 1
        crossLayer.transform = CATransform3DIdentity
        isEnabled = true
        setActive(false)
    }

    private func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        isHidden = !active
        if active, window != nil { startRotation() }
        onActiveChange?(active)
    }

    private func apply(_ file: File, animated: Bool) {
        guard isActive, isEnabled else { return }
        if file.remote.isUploadingCompleted {
            finish()
            return
        }
        let size = max(file.size, file.expectedSize)
        let fraction = size > 0 ? CGFloat(file.remote.uploadedSize) / CGFloat(size) : 0
        let value = min(1, max(Self.minimumProgress, fraction))
        // Never step back: the seeded `getFile` state can arrive after a newer `updateFile`.
        guard value >= progress else { return }
        let previous = arcLayer.presentation()?.strokeEnd ?? arcLayer.strokeEnd
        progress = value
        arcLayer.strokeEnd = value
        if let registryKey { MediaUploadProgressRegistry.record(registryKey, progress: value) }
        accessibilityValue = "\(Int(value * 100))%"
        guard animated, window != nil, !UIAccessibility.isReduceMotionEnabled else {
            arcLayer.removeAnimation(forKey: "progress")
            return
        }
        // RadialProgressContentSpinnerNode: 0.2 s linear, up to 0.45 s more for a jump over a quarter.
        let delta = max(0, value - previous)
        var duration = 0.2
        if delta > 0.25 { duration += Double(min(0.45, 0.45 * ((delta - 0.25) * 5))) }
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = previous
        animation.toValue = value
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        arcLayer.add(animation, forKey: "progress")
    }

    /// The upload is done; the sent message replaces this row shortly. Fade out as `RadialProgressContentNode` does.
    private func finish() {
        let now = CACurrentMediaTime()
        if let registryKey { MediaUploadProgressRegistry.record(registryKey, progress: 1, finishedAt: now) }
        resumeFinish(from: now)
    }

    /// Fades out over what remains of the 0.25 s that began at `finishedAt`.
    private func resumeFinish(from finishedAt: CFTimeInterval) {
        cancellable = nil
        seedTask?.cancel()
        seedTask = nil
        isEnabled = false
        progress = 1
        arcLayer.strokeEnd = 1
        let remaining = Self.fadeDuration - (CACurrentMediaTime() - finishedAt)
        guard remaining > 0.01 else {
            setActive(false)
            return
        }
        let generation = generation
        // An album builds a replacement tile before adding it to the window, and may do so with UIKit animations
        // off; a UIView animation would then finish at once. A layer animation starts when the tile is shown.
        UIView.performWithoutAnimation { alpha = 0 }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = Float(remaining / Self.fadeDuration)
        fade.toValue = Float(0)
        fade.duration = remaining
        fade.timingFunction = CAMediaTimingFunction(name: .linear)
        layer.add(fade, forKey: "uploadFade")
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self, self.generation == generation else { return }
            layer.removeAnimation(forKey: "uploadFade")
            setActive(false)
            alpha = 1
        }
    }

    private func startRotation() {
        guard arcContainer.animation(forKey: "rotation") == nil else { return }
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        let start = Float.pi + 0.58
        rotation.fromValue = start
        rotation.toValue = start + Float.pi * 2
        rotation.duration = 1.5
        // Phase from the shared media clock, so a rebuilt tile continues the angle of the one it replaced.
        rotation.timeOffset = CACurrentMediaTime().truncatingRemainder(dividingBy: rotation.duration)
        rotation.repeatCount = .infinity
        rotation.timingFunction = CAMediaTimingFunction(name: .linear)
        rotation.isRemovedOnCompletion = false
        arcContainer.add(rotation, forKey: "rotation")
    }

    @objc private func cancelTapped() {
        guard isActive, isEnabled, let onCancel else { return }
        isEnabled = false
        if let registryKey { MediaUploadProgressRegistry.remove(registryKey) }
        onCancel()
    }
}
