// TGSAnimation.swift

import Combine
import Foundation
import Lottie
import QuartzCore
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

// MARK: - TGSStickerView

final class TGSStickerView: UIControl, AnimatedFileView {
    // MARK: Internal

    var onFirstFrameReady: (() -> Void)?

    // MARK: Private

    private let thumbnailView = TDImageLoadingView()
    private let animationView = LottieAnimationView(configuration: LottieConfiguration(
        renderingEngine: .automatic,
        decodingStrategy: .legacyCodable,
    ))
    private lazy var widthConstraint = widthAnchor.constraint(equalToConstant: 180)
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 180)
    private var representedFileID: Int?
    private var loadedPath: String?
    private var playbackVisible = false
    private var onTap: (() -> Void)?
    private var fileRequest: AnimatedFileDownload?
    private var decodeTask: Task<Void, Never>?

    private var playbackEnabled: Bool {
        UserDefaults.standard.object(forKey: "animatedMediaEnabled") as? Bool ?? true
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.contentMode = .scaleAspectFit
        addSubview(thumbnailView)

        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.contentMode = .scaleAspectFit
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.isHidden = true
        animationView.isUserInteractionEnabled = false
        addSubview(animationView)

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: bottomAnchor),
            animationView.topAnchor.constraint(equalTo: topAnchor),
            animationView.leadingAnchor.constraint(equalTo: leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: trailingAnchor),
            animationView.bottomAnchor.constraint(equalTo: bottomAnchor),
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
        decodeTask?.cancel()
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

        decodeTask?.cancel()
        decodeTask = nil

        animationView.stop()
        animationView.animation = nil
        animationView.isHidden = true
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
        decodeTask?.cancel()
        decodeTask = Task { [weak self] in
            let animation = await TGSAnimationRepository.animation(at: file.local.path)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled, request.isCurrent,
                      let self, self.fileRequest === request,
                      self.representedFileID == fileID, self.loadedPath == file.local.path
                else { return }
                self.show(animation: animation)
            }
        }
    }

    private func show(animation: LottieAnimation?) {
        guard let animation else {
            animationView.stop()
            animationView.animation = nil
            animationView.isHidden = true
            thumbnailView.isHidden = false
            return
        }

        animationView.animation = animation
        animationView.currentProgress = synchronizedProgress(for: animation)
        animationView.forceDisplayUpdate()
        animationView.isHidden = false
        thumbnailView.isHidden = true
        onFirstFrameReady?()
        onFirstFrameReady = nil
        updatePlayback()
    }

    private func updatePlayback() {
        let shouldPlay = fileRequest?.isCurrent == true && playbackVisible && window != nil
            && playbackEnabled && animationView.animation != nil
        if shouldPlay {
            guard !animationView.isAnimationPlaying else { return }
            playSynchronized()
        } else {
            animationView.pause()
        }
    }

    private func playSynchronized() {
        guard fileRequest?.isCurrent == true, let animation = animationView.animation,
              playbackVisible,
              window != nil,
              playbackEnabled
        else { return }

        let progress = synchronizedProgress(for: animation)
        animationView.play(fromProgress: progress, toProgress: 1, loopMode: .playOnce) { [weak self] finished in
            guard finished else { return }
            DispatchQueue.main.async { self?.playSynchronized() }
        }
    }

    private func synchronizedProgress(for animation: LottieAnimation) -> AnimationProgressTime {
        guard animation.duration.isFinite, animation.duration > 0 else { return 0 }
        return CACurrentMediaTime().truncatingRemainder(dividingBy: animation.duration) / animation.duration
    }

    @objc private func tapped() {
        onTap?()
    }
}
