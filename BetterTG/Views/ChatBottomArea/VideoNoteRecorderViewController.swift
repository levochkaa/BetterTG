// VideoNoteRecorderViewController.swift

import AVFoundation
import Combine
@preconcurrency import TDLibKit
import UIKit

// MARK: - VideoNoteComposerState

enum VideoNoteComposerState: Equatable {
    case failed(String)
    case holding(Double)
    case idle
    case locked(Double)
    case preparing
    case preview(duration: Double, isPlaying: Bool, canRecordMore: Bool)
    case sending
    case stopping

    var isActive: Bool {
        switch self {
        case .failed, .idle:
            false
        case .holding, .locked, .preparing, .preview, .sending, .stopping:
            true
        }
    }
}

// MARK: - VideoNoteSubmissionResult

enum VideoNoteSubmissionResult {
    case enqueued
    case retained(VideoNoteAsset, originConsumed: Bool, message: String)
}

// MARK: - VideoNoteRecorderViewController

@MainActor final class VideoNoteRecorderViewController: UIViewController {
    // MARK: Private

    private enum ExitDisposition {
        case discard
        case none
        case preserve
    }

    // MARK: Internal

    var onDismiss: (() -> Void)?
    var onDiscard: ((VideoNoteAsset) async -> Void)?
    var onError: ((String) -> Void)?
    var onPreviewData: ((VideoNoteRecordingDraft, [VideoNoteThumbnailSample]) -> Void)?
    var onThumbnailData: (([VideoNoteThumbnailSample], [UUID]) -> Void)?
    var onStateChange: ((VideoNoteComposerState) -> Void)?
    var onSubmit: ((
        VideoNoteAsset,
        VideoNoteInputThumbnailAsset?,
        UUID?,
        Int64?,
        InputMessageReplyTo?,
    ) async -> VideoNoteSubmissionResult)?

    private(set) var state = VideoNoteComposerState.idle {
        didSet {
            guard state != oldValue else { return }
            updateUI()
            onStateChange?(state)
        }
    }

    private let captureSession = VideoNoteCaptureSession()
    private let previewPlayer = LocalMediaPlayer()
    private let chatID: Int64
    private let draftKey: ChatDraftKey
    private let replyMessageID: Int64?
    private let replyTo: InputMessageReplyTo?
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let previewContainer = VideoNotePreviewContainerView()
    private let cameraPreview = VideoNoteCameraPreviewView()
    private let playbackPreview = LocalVideoSurfaceView()
    private let muteBadgeView = UIView()
    private let muteBadgeImageView = UIImageView(image: UIImage(systemName: "speaker.slash.fill"))
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()
    private let flipButton = UIButton(type: .system)
    private let flashButton = UIButton(type: .system)
    private let progressLayer = CAShapeLayer()
    private var cancellables = Set<AnyCancellable>()
    private var operationTask: Task<Void, Never>?
    private var operationGeneration = UUID()
    private var preferredPosition = VideoNoteCaptureSession.Position.front
    private var lastFlipTimestamp: TimeInterval?
    private var lastRecordMoreTimestamp: TimeInterval?
    private var currentAsset: VideoNoteAsset?
    private var recordingDraft: VideoNoteRecordingDraft?
    private var previewThumbnails = [VideoNoteThumbnailSample]()
    private var previewMuted = true
    private var previewOwnsAudioSession = false
    private var previewAudioSessionTask: Task<Void, Never>?
    private var thumbnailGeneration = UUID()
    private var thumbnailAppliedStage = 0
    private var thumbnailTask: Task<Void, Never>?
    private var recordingDurationBaseline = 0.0
    private var transientTrimRange: Range<Double>?
    private var trimBaseDraft: VideoNoteRecordingDraft?
    private var ownsCurrentAsset = false
    private var locked = false
    private var didAnimateIn = false
    private var didRequestDismiss = false
    private var dismissAfterSubmission = false
    private var flashEnabled = false
    private var exitDisposition = ExitDisposition.none
    private var initialScreenBrightness: CGFloat?
    private var currentZoomFactor: CGFloat = 1
    private var pinchStartZoomFactor: CGFloat = 1

    var hasPersistedRecordingDraft: Bool {
        recordingDraft != nil
    }

    private var currentInterfaceOrientation: UIInterfaceOrientation {
        view.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
    }

    init(
        chatID: Int64,
        draftKey: ChatDraftKey,
        replyMessageID: Int64?,
        replyTo: InputMessageReplyTo?,
    ) {
        self.chatID = chatID
        self.draftKey = draftKey
        self.replyMessageID = replyMessageID
        self.replyTo = replyTo
        super.init(nibName: nil, bundle: nil)
        captureSession.onAutomaticStop = { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else {
                    if case .success(let asset) = result {
                        try? FileManager.default.removeItem(at: asset.url)
                    }
                    return
                }
                handleAutomaticStop(result)
            }
        }
        observeCaptureSession()
        observePreviewPlayer()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        operationTask?.cancel()
        thumbnailTask?.cancel()
        previewAudioSessionTask?.cancel()
        captureSession.stopCapture()
        previewPlayer.stop()
        MainActor.assumeIsolated {
            releasePreviewAudioSession()
            restoreScreenBrightness()
        }
        if ownsCurrentAsset, let currentAsset {
            let discard = onDiscard
            Task {
                if let discard {
                    await discard(currentAsset)
                } else {
                    await VideoNoteFileStore.shared.discardAsset(at: currentAsset.url)
                }
            }
        }
    }

    override func loadView() {
        view = UIView()
        configureViews()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutCamera()
        updateOrientation()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.view.setNeedsLayout()
            self?.view.layoutIfNeeded()
        }) { [weak self] _ in
            self?.updateOrientation()
        }
    }

    func beginHolding() async -> Bool {
        guard !state.isActive else { return false }
        exitDisposition = .none
        recordingDurationBaseline = 0
        return await beginCapture(lockedInitially: false)
    }

    func recordMore() {
        guard operationTask == nil,
              trimBaseDraft == nil,
              case .preview = state,
              let recordingDraft,
              recordingDraft.canRecordMore
        else { return }
        let now = CACurrentMediaTime()
        guard lastRecordMoreTimestamp.map({ now - $0 >= 0.5 }) ?? true else { return }
        lastRecordMoreTimestamp = now
        exitDisposition = .none
        recordingDurationBaseline = recordingDraft.totalDuration
        thumbnailTask?.cancel()
        thumbnailTask = nil
        previewPlayer.stop()
        releasePreviewAudioSession()
        playbackPreview.isHidden = true
        cameraPreview.isHidden = false
        state = .preparing
        operationTask = Task { [weak self] in
            guard let self else { return }
            _ = await beginCapture(lockedInitially: true)
            operationTask = nil
        }
    }

    func restore(_ draft: VideoNoteRecordingDraft) {
        guard state == .idle,
              operationTask == nil,
              draft.destination == draftKey
        else { return }
        exitDisposition = .none
        recordingDraft = draft
        recordingDurationBaseline = draft.totalDuration
        let generation = UUID()
        operationGeneration = generation
        loadViewIfNeeded()
        animateInIfNeeded()
        cameraPreview.isHidden = true
        playbackPreview.isHidden = false
        state = .stopping
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { operationTask = nil }
            do {
                try await preparePreview(draft: draft, generation: generation)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      operationGeneration == generation,
                      exitDisposition == .none
                else { return }
                fail("Couldn’t restore the saved video-message preview.")
            }
        }
    }

    func retryPersistedPreview() {
        guard let recordingDraft else { return }
        state = .idle
        restore(recordingDraft)
    }

    func cancel() {
        if case .sending = state {
            exitDisposition = .discard
            dismissAfterSubmission = true
            return
        }
        exitDisposition = .discard
        operationGeneration = UUID()
        operationTask?.cancel()
        operationTask = nil
        thumbnailTask?.cancel()
        thumbnailTask = nil
        captureSession.cancelRecording()
        captureSession.stopCapture()
        previewPlayer.stop()
        releasePreviewAudioSession()
        restoreScreenBrightness()
        if let recordingDraft {
            Task { await VideoNoteRecordingDraftStore.shared.discard(id: recordingDraft.id) }
        }
        recordingDraft = nil
        previewThumbnails = []
        if ownsCurrentAsset, let currentAsset {
            discardOwnedAsset(currentAsset)
        }
        currentAsset = nil
        ownsCurrentAsset = false
        state = .idle
        dismissAnimated()
    }

    func finishForPreview() {
        finishRecording(submitAfterCapture: false)
    }

    func finishForSend() {
        switch state {
        case .preview:
            submitPreview()
        case .holding, .locked:
            finishRecording(submitAfterCapture: true)
        case .failed, .idle, .preparing, .sending, .stopping:
            break
        }
    }

    func lockRecording() {
        locked = true
        if case .holding(let duration) = state {
            state = .locked(duration)
        }
    }

    func togglePreviewPlayback() {
        guard trimBaseDraft == nil else { return }
        guard case .preview(let duration, let isPlaying, let canRecordMore) = state else { return }
        if isPlaying {
            previewPlayer.pause()
            state = .preview(duration: duration, isPlaying: false, canRecordMore: canRecordMore)
        } else {
            previewPlayer.play()
            state = .preview(duration: duration, isPlaying: true, canRecordMore: canRecordMore)
        }
    }

    func updateTrim(
        start: Double,
        end: Double,
        updatedEnd: Bool,
        finished: Bool,
    ) {
        guard case .preview = state,
              operationTask == nil,
              let previousDraft = recordingDraft,
              previousDraft.totalDuration > 1
        else { return }
        let duration = previousDraft.totalDuration
        var lowerBound = max(0, min(start, duration))
        var upperBound = max(lowerBound, min(end, duration))
        let selectionDuration = upperBound - lowerBound
        guard selectionDuration >= 1 - 0.000_001 else {
            if finished {
                onPreviewData?(previousDraft, previewThumbnails)
            }
            return
        }
        if selectionDuration < 1 {
            if updatedEnd, lowerBound + 1 <= duration {
                upperBound = lowerBound + 1
            } else {
                lowerBound = max(0, upperBound - 1)
            }
        }
        if trimBaseDraft == nil {
            trimBaseDraft = previousDraft
        }
        let canonicalDraft = trimBaseDraft ?? previousDraft
        let range = lowerBound..<upperBound
        transientTrimRange = range
        previewPlayer.pause()
        previewPlayer.seek(
            to: updatedEnd ? upperBound : lowerBound,
            tolerance: 0,
            constrainedToPlaybackRange: false,
        )
        state = .preview(
            duration: upperBound - lowerBound,
            isPlaying: false,
            canRecordMore: previousDraft.canRecordMore,
        )
        guard finished else { return }
        let generation = operationGeneration
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { operationTask = nil }
            do {
                let storedDraft = try await VideoNoteRecordingDraftStore.shared.updateTrim(
                    in: canonicalDraft,
                    range: range,
                )
                guard !Task.isCancelled,
                      operationGeneration == generation,
                      exitDisposition == .none,
                      recordingDraft?.id == storedDraft.id
                else { return }
                recordingDraft = storedDraft
                trimBaseDraft = nil
                transientTrimRange = nil
                previewPlayer.setPlaybackRange(storedDraft.effectiveRange)
                previewPlayer.play(from: storedDraft.effectiveRange.lowerBound)
                state = .preview(
                    duration: storedDraft.effectiveRange.upperBound - storedDraft.effectiveRange.lowerBound,
                    isPlaying: true,
                    canRecordMore: storedDraft.canRecordMore,
                )
                onPreviewData?(storedDraft, previewThumbnails)
            } catch {
                guard !Task.isCancelled,
                      operationGeneration == generation,
                      exitDisposition == .none
                else { return }
                recordingDraft = canonicalDraft
                trimBaseDraft = nil
                transientTrimRange = nil
                previewPlayer.setPlaybackRange(canonicalDraft.effectiveRange)
                previewPlayer.seek(to: canonicalDraft.effectiveRange.lowerBound, tolerance: 0)
                state = .preview(
                    duration: canonicalDraft.effectiveRange.upperBound - canonicalDraft.effectiveRange.lowerBound,
                    isPlaying: false,
                    canRecordMore: canonicalDraft.canRecordMore,
                )
                onPreviewData?(canonicalDraft, previewThumbnails)
                onError?("Couldn’t save the video trim range.")
            }
        }
    }

    func teardownForNavigation() {
        exitDisposition = .preserve
        operationGeneration = UUID()
        operationTask?.cancel()
        operationTask = nil
        thumbnailTask?.cancel()
        thumbnailTask = nil
        captureSession.cancelRecording()
        captureSession.stopCapture()
        previewPlayer.stop()
        releasePreviewAudioSession()
        restoreScreenBrightness()
        currentAsset = nil
        ownsCurrentAsset = false
        recordingDraft = nil
        previewThumbnails = []
        state = .idle
        dismissAnimated()
    }

    private func beginCapture(lockedInitially: Bool) async -> Bool {
        let generation = UUID()
        operationGeneration = generation
        locked = lockedInitially
        state = .preparing
        loadViewIfNeeded()
        animateInIfNeeded()
        updateOrientation()

        do {
            try await captureSession.prepare(position: preferredPosition, generation: generation)
            try Task.checkCancellation()
            guard operationGeneration == generation else { throw CancellationError() }
            cameraPreview.updateConnection(
                position: captureSession.currentPosition,
                orientation: currentInterfaceOrientation,
            )
            try await Task<Never, Never>.sleep(for: .milliseconds(150))
            try Task.checkCancellation()
            guard operationGeneration == generation else { throw CancellationError() }
            let remainingDuration = max(0.5, 60 - recordingDurationBaseline)
            let remainingAutomaticDuration = max(0.5, 59.5 - recordingDurationBaseline)
            try await captureSession.startRecording(
                maximumDuration: remainingDuration,
                automaticStopDuration: remainingAutomaticDuration,
            )
            try Task.checkCancellation()
            guard operationGeneration == generation else { throw CancellationError() }
            state = locked
                ? .locked(recordingDurationBaseline)
                : .holding(recordingDurationBaseline)
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard !Task.isCancelled,
                  operationGeneration == generation,
                  exitDisposition == .none
            else { return false }
            let errorMessage = message(for: error)
            if lockedInitially, recordingDraft != nil, operationGeneration == generation {
                await recoverRecordMorePreview(message: errorMessage, generation: generation)
            } else {
                fail(errorMessage)
            }
            return false
        }
    }

    private func configureViews() {
        view.backgroundColor = .clear
        blurView.frame = view.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(blurView)

        previewContainer.backgroundColor = .black
        previewContainer.clipsToBounds = true
        previewContainer.accessibilityIdentifier = "video-note-camera-circle"
        previewContainer.accessibilityHint = "Double-tap to toggle preview sound."
        previewContainer.onAccessibilityActivate = { [weak self] in
            self?.togglePreviewMute() ?? false
        }
        view.addSubview(previewContainer)

        cameraPreview.frame = previewContainer.bounds
        cameraPreview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cameraPreview.attach(session: captureSession.captureSession, position: preferredPosition)
        previewContainer.addSubview(cameraPreview)

        playbackPreview.frame = previewContainer.bounds
        playbackPreview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playbackPreview.playerLayer.videoGravity = .resizeAspectFill
        playbackPreview.isHidden = true
        previewPlayer.attach(to: playbackPreview.playerLayer)
        previewContainer.addSubview(playbackPreview)

        muteBadgeView.backgroundColor = UIColor.black.withAlphaComponent(0.58)
        muteBadgeView.layer.cornerRadius = 18
        muteBadgeView.layer.cornerCurve = .continuous
        muteBadgeView.isHidden = true
        muteBadgeView.isAccessibilityElement = false
        muteBadgeImageView.tintColor = .white
        muteBadgeImageView.contentMode = .center
        muteBadgeImageView.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        muteBadgeView.addSubview(muteBadgeImageView)
        previewContainer.addSubview(muteBadgeView)

        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = UIColor.white.withAlphaComponent(0.6).cgColor
        progressLayer.lineWidth = 4
        progressLayer.lineCap = .round
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = 0
        previewContainer.layer.addSublayer(progressLayer)

        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.color = .white
        previewContainer.addSubview(loadingIndicator)

        statusLabel.textAlignment = .center
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        statusLabel.textColor = .label
        statusLabel.numberOfLines = 2
        statusLabel.accessibilityIdentifier = "video-note-camera-status"
        view.addSubview(statusLabel)

        configureControl(
            flipButton,
            symbol: "camera.rotate.fill",
            label: "Switch camera",
            action: #selector(flipCamera),
        )
        configureControl(
            flashButton,
            symbol: "bolt.slash.fill",
            label: "Toggle flash",
            action: #selector(toggleFlash),
        )
        view.addSubview(flipButton)
        view.addSubview(flashButton)

        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        previewContainer.addGestureRecognizer(pinchGesture)
        let previewTap = UITapGestureRecognizer(target: self, action: #selector(previewTapped))
        previewContainer.addGestureRecognizer(previewTap)
        updateUI()
    }

    private func configureControl(
        _ button: UIButton,
        symbol: String,
        label: String,
        action: Selector,
    ) {
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold),
            forImageIn: .normal,
        )
        button.tintColor = .label
        button.backgroundColor = .secondarySystemBackground
        button.layer.cornerRadius = 22
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func layoutCamera() {
        let safeTop = view.safeAreaInsets.top
        let controlHeight: CGFloat = 60
        let maximumSide = min(369, view.bounds.width - 24)
        let availableHeight = max(0, view.bounds.height - safeTop - controlHeight)
        let side = min(maximumSide, max(160, availableHeight - 32))
        let preferredCenterY = max(safeTop + 24 + side / 2, view.bounds.height * 0.4)
        let maximumCenterY = max(safeTop + side / 2, view.bounds.height - controlHeight - 16 - side / 2)
        let centerY = min(preferredCenterY, maximumCenterY)
        previewContainer.frame = CGRect(
            x: floor((view.bounds.width - side) / 2),
            y: floor(centerY - side / 2),
            width: side,
            height: side,
        )
        previewContainer.layer.cornerRadius = side / 2
        cameraPreview.layer.cornerRadius = side / 2
        playbackPreview.layer.cornerRadius = side / 2

        progressLayer.frame = previewContainer.bounds
        progressLayer.path = UIBezierPath(
            ovalIn: previewContainer.bounds.insetBy(dx: 3, dy: 3),
        ).cgPath
        progressLayer.setAffineTransform(CGAffineTransform(rotationAngle: -.pi / 2))

        loadingIndicator.center = CGPoint(x: previewContainer.bounds.midX, y: previewContainer.bounds.midY)
        muteBadgeView.frame = CGRect(
            x: previewContainer.bounds.maxX - 54,
            y: previewContainer.bounds.maxY - 54,
            width: 36,
            height: 36,
        )
        statusLabel.frame = CGRect(
            x: 20,
            y: previewContainer.frame.maxY + 8,
            width: view.bounds.width - 40,
            height: 44,
        )
        flipButton.frame = CGRect(x: 8, y: view.bounds.height - 52, width: 44, height: 44)
        flashButton.frame = CGRect(x: 63, y: view.bounds.height - 52, width: 44, height: 44)
    }

    private func observeCaptureSession() {
        captureSession.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] captureState in
                guard let self else { return }
                switch captureState {
                case .configuring:
                    if !state.isActive || state == .preparing {
                        state = .preparing
                    }
                case .failed(let message):
                    if recordingDurationBaseline > 0,
                       recordingDraft != nil,
                       operationTask == nil
                    {
                        let generation = operationGeneration
                        state = .stopping
                        operationTask = Task { [weak self] in
                            guard let self else { return }
                            await recoverRecordMorePreview(message: message, generation: generation)
                            operationTask = nil
                        }
                    } else if recordingDurationBaseline == 0 || recordingDraft == nil {
                        fail(message)
                    }
                case .idle:
                    break
                case .ready(let position):
                    preferredPosition = position
                    cameraPreview.updateConnection(position: position, orientation: currentInterfaceOrientation)
                case .recording(let duration):
                    let aggregateDuration = recordingDurationBaseline + duration
                    progressLayer.strokeEnd = min(1, max(0, aggregateDuration / 60))
                    state = locked ? .locked(aggregateDuration) : .holding(aggregateDuration)
                case .stopping:
                    state = .stopping
                }
            }
            .store(in: &cancellables)
    }

    private func observePreviewPlayer() {
        previewPlayer.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playerState in
                guard let self,
                      case .preview(let duration, _, let canRecordMore) = state
                else { return }
                switch playerState {
                case .playing:
                    state = .preview(
                        duration: duration,
                        isPlaying: true,
                        canRecordMore: canRecordMore,
                    )
                case .failed:
                    previewMuted = true
                    previewPlayer.setMuted(true)
                    releasePreviewAudioSession()
                    updatePreviewAccessibility()
                    updatePreviewMuteBadge()
                    state = .preview(
                        duration: duration,
                        isPlaying: false,
                        canRecordMore: canRecordMore,
                    )
                    onError?("Couldn’t play the video-message preview.")
                case .buffering, .ended, .idle, .paused, .preparing:
                    state = .preview(
                        duration: duration,
                        isPlaying: false,
                        canRecordMore: canRecordMore,
                    )
                }
            }
            .store(in: &cancellables)
        previewPlayer.loopPublisher
            .sink { [weak self] in
                guard let self,
                      case .preview = state
                else { return }
                previewMuted = true
                previewPlayer.setMuted(true)
                releasePreviewAudioSession()
                updatePreviewAccessibility()
                updatePreviewMuteBadge()
            }
            .store(in: &cancellables)
        Media.shared
            .$savedMediaPath
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] path in
                guard let self,
                      !path.isEmpty,
                      previewOwnsAudioSession || previewAudioSessionTask != nil
                else { return }
                previewAudioSessionTask?.cancel()
                previewAudioSessionTask = nil
                previewOwnsAudioSession = false
                previewMuted = true
                previewPlayer.setMuted(true)
                updatePreviewAccessibility()
                updatePreviewMuteBadge()
            }
            .store(in: &cancellables)
    }

    private func finishRecording(submitAfterCapture: Bool) {
        guard operationTask == nil else { return }
        switch state {
        case .holding(let duration):
            if duration - recordingDurationBaseline < 0.5 {
                if recordingDurationBaseline == 0 {
                    cancel()
                }
                return
            }
        case .locked(let duration):
            if duration - recordingDurationBaseline < 0.5 {
                return
            }
        case .failed, .idle, .preparing, .preview, .sending, .stopping:
            return
        }
        let generation = operationGeneration
        state = .stopping
        operationTask = Task { [weak self] in
            guard let self else { return }
            var capturedAsset: VideoNoteAsset?
            do {
                let asset = try await captureSession.stopRecording()
                capturedAsset = asset
                try Task.checkCancellation()
                guard operationGeneration == generation else {
                    try? FileManager.default.removeItem(at: asset.url)
                    return
                }
                try await processCapturedAsset(asset, generation: generation)
                operationTask = nil
                if submitAfterCapture {
                    submitPreview()
                }
            } catch is CancellationError {
                if let capturedAsset {
                    try? FileManager.default.removeItem(at: capturedAsset.url)
                }
                operationTask = nil
                return
            } catch {
                if let capturedAsset {
                    try? FileManager.default.removeItem(at: capturedAsset.url)
                }
                operationTask = nil
                guard !Task.isCancelled,
                      operationGeneration == generation,
                      exitDisposition == .none
                else { return }
                if recordingDurationBaseline > 0,
                   recordingDraft != nil,
                   operationGeneration == generation
                {
                    await recoverRecordMorePreview(message: message(for: error), generation: generation)
                } else {
                    fail(message(for: error))
                }
            }
        }
    }

    private func processCapturedAsset(
        _ asset: VideoNoteAsset,
        generation: UUID,
    ) async throws {
        guard asset.duration >= 0.5 else {
            try? FileManager.default.removeItem(at: asset.url)
            throw VideoNoteRecordingDraftStoreError.invalidAsset
        }
        let draft: VideoNoteRecordingDraft =
            if let recordingDraft {
                try await VideoNoteRecordingDraftStore.shared.append(asset, to: recordingDraft)
            } else {
                try await VideoNoteRecordingDraftStore.shared.adopt(
                    asset,
                    chatID: chatID,
                    draftKey: draftKey,
                    replyMessageID: replyMessageID,
                    replyTo: replyTo,
                )
            }
        guard operationGeneration == generation else {
            if exitDisposition == .discard {
                await VideoNoteRecordingDraftStore.shared.discard(id: draft.id)
            }
            throw CancellationError()
        }
        try Task.checkCancellation()
        recordingDraft = draft
        try await preparePreview(draft: draft, generation: generation)
    }

    private func preparePreview(
        draft: VideoNoteRecordingDraft,
        generation: UUID,
    ) async throws {
        let composition = try await VideoNoteRecordingDraftStore.shared.composition(for: draft)
        guard operationGeneration == generation, exitDisposition == .none else {
            if exitDisposition == .discard {
                await VideoNoteRecordingDraftStore.shared.discard(id: draft.id)
            }
            throw CancellationError()
        }
        try Task.checkCancellation()
        installPreview(draft: draft, composition: composition)
    }

    private func installPreview(
        draft: VideoNoteRecordingDraft,
        composition: VideoNoteCompositionResult,
    ) {
        recordingDraft = draft
        exitDisposition = .none
        trimBaseDraft = nil
        transientTrimRange = nil
        previewThumbnails = []
        currentAsset = nil
        ownsCurrentAsset = false
        releasePreviewAudioSession()
        captureSession.stopCapture()
        restoreScreenBrightness()
        cameraPreview.isHidden = true
        playbackPreview.isHidden = false
        playbackPreview.alpha = 0
        previewMuted = true
        previewPlayer.setMuted(previewMuted)
        previewPlayer.load(
            composition: composition,
            autoplay: true,
            loops: true,
            playbackRange: draft.effectiveRange,
        )
        state = .preview(
            duration: draft.effectiveRange.upperBound - draft.effectiveRange.lowerBound,
            isPlaying: true,
            canRecordMore: draft.canRecordMore,
        )
        onPreviewData?(draft, [])
        loadThumbnails(for: draft, composition: composition)
        UIView.animate(withDuration: 0.2) {
            self.playbackPreview.alpha = 1
        }
    }

    private func loadThumbnails(
        for draft: VideoNoteRecordingDraft,
        composition: VideoNoteCompositionResult,
    ) {
        thumbnailTask?.cancel()
        let generation = UUID()
        thumbnailGeneration = generation
        thumbnailAppliedStage = 0
        let segmentIDs = draft.segments.map(\.id)
        thumbnailTask = Task { [weak self] in
            guard let self else { return }
            do {
                let samples = try await VideoNoteSegmentComposer.thumbnails(
                    for: composition,
                    onFirst: { [weak self] sample in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            applyThumbnailSamples(
                                Array(repeating: sample, count: 13),
                                segmentIDs: segmentIDs,
                                generation: generation,
                                stage: 1,
                            )
                        }
                    },
                )
                try Task.checkCancellation()
                applyThumbnailSamples(
                    samples,
                    segmentIDs: segmentIDs,
                    generation: generation,
                    stage: 2,
                )
                thumbnailTask = nil
            } catch {
                guard thumbnailGeneration == generation else { return }
                thumbnailTask = nil
            }
        }
    }

    private func applyThumbnailSamples(
        _ samples: [VideoNoteThumbnailSample],
        segmentIDs: [UUID],
        generation: UUID,
        stage: Int,
    ) {
        guard thumbnailGeneration == generation,
              stage >= thumbnailAppliedStage,
              recordingDraft?.segments.map(\.id) == segmentIDs
        else { return }
        thumbnailAppliedStage = stage
        previewThumbnails = samples
        onThumbnailData?(samples, segmentIDs)
    }

    private func submitPreview() {
        guard operationTask == nil,
              trimBaseDraft == nil,
              let onSubmit
        else {
            if onSubmit == nil {
                fail("Video message sending isn’t available.")
            }
            return
        }
        let generation = operationGeneration
        let draft = recordingDraft
        if let draft,
           draft.effectiveRange.upperBound - draft.effectiveRange.lowerBound < 1 - 0.000_001
        {
            onError?("Video messages must be at least 1 second. Record more before sending.")
            return
        }
        guard draft != nil || currentAsset != nil else { return }
        state = .sending
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { operationTask = nil }
            let asset: VideoNoteAsset
            var thumbnail: VideoNoteInputThumbnailAsset?
            let originRecordingDraftID: UUID?
            if let draft {
                let outputURL = FileManager.default
                    .temporaryDirectory
                    .appendingPathComponent("video-note-send-\(UUID().uuidString).mp4")
                do {
                    asset = try await VideoNoteRecordingDraftStore.shared.materialize(
                        draft,
                        outputURL: outputURL,
                    )
                    thumbnail = try await makeOutgoingThumbnail(for: asset.url)
                    try Task.checkCancellation()
                    guard operationGeneration == generation else { throw CancellationError() }
                } catch {
                    try? FileManager.default.removeItem(at: outputURL)
                    if let thumbnail {
                        try? FileManager.default.removeItem(at: thumbnail.url)
                    }
                    thumbnail = nil
                    guard operationGeneration == generation else { return }
                    if dismissAfterSubmission || exitDisposition == .discard {
                        thumbnailTask?.cancel()
                        thumbnailTask = nil
                        await VideoNoteRecordingDraftStore.shared.discard(id: draft.id)
                        recordingDraft = nil
                        previewThumbnails = []
                        previewPlayer.stop()
                        releasePreviewAudioSession()
                        state = .idle
                        dismissAnimated()
                        return
                    }
                    state = .preview(
                        duration: draft.effectiveRange.upperBound - draft.effectiveRange.lowerBound,
                        isPlaying: previewPlayer.isPlaybackRequested,
                        canRecordMore: draft.canRecordMore,
                    )
                    onError?("Couldn’t prepare the video message for sending.")
                    return
                }
                originRecordingDraftID = draft.id
            } else if let currentAsset {
                asset = currentAsset
                originRecordingDraftID = nil
            } else {
                return
            }
            let result = await onSubmit(
                asset,
                thumbnail,
                originRecordingDraftID,
                replyMessageID,
                replyTo,
            )
            guard !Task.isCancelled, operationGeneration == generation else {
                if case .retained(let staleAsset, let originConsumed, _) = result,
                   !originConsumed,
                   draft != nil
                {
                    try? FileManager.default.removeItem(at: staleAsset.url)
                    if let thumbnail {
                        try? FileManager.default.removeItem(at: thumbnail.url)
                    }
                }
                return
            }
            switch result {
            case .enqueued:
                thumbnailTask?.cancel()
                thumbnailTask = nil
                ownsCurrentAsset = false
                currentAsset = nil
                recordingDraft = nil
                previewThumbnails = []
                previewPlayer.stop()
                releasePreviewAudioSession()
                state = .idle
                dismissAnimated()
            case .retained(let asset, let originConsumed, let message):
                if !originConsumed, let draft {
                    try? FileManager.default.removeItem(at: asset.url)
                    if let thumbnail {
                        try? FileManager.default.removeItem(at: thumbnail.url)
                    }
                    if dismissAfterSubmission {
                        thumbnailTask?.cancel()
                        thumbnailTask = nil
                        await VideoNoteRecordingDraftStore.shared.discard(id: draft.id)
                        recordingDraft = nil
                        previewThumbnails = []
                        previewPlayer.stop()
                        releasePreviewAudioSession()
                        state = .idle
                        dismissAnimated()
                    } else {
                        state = .preview(
                            duration: draft.effectiveRange.upperBound - draft.effectiveRange.lowerBound,
                            isPlaying: previewPlayer.isPlaybackRequested,
                            canRecordMore: draft.canRecordMore,
                        )
                        onError?(message)
                    }
                    return
                }
                if dismissAfterSubmission {
                    thumbnailTask?.cancel()
                    thumbnailTask = nil
                    if let onDiscard {
                        await onDiscard(asset)
                    } else {
                        await VideoNoteFileStore.shared.discardAsset(at: asset.url)
                    }
                    ownsCurrentAsset = false
                    currentAsset = nil
                    recordingDraft = nil
                    previewThumbnails = []
                    previewPlayer.stop()
                    releasePreviewAudioSession()
                    state = .idle
                    dismissAnimated()
                    return
                }
                currentAsset = asset
                ownsCurrentAsset = true
                releasePreviewAudioSession()
                thumbnailTask?.cancel()
                thumbnailTask = nil
                recordingDraft = nil
                previewThumbnails = []
                previewMuted = true
                previewPlayer.setMuted(true)
                previewPlayer.load(url: asset.url, autoplay: true, loops: true)
                state = .preview(duration: asset.duration, isPlaying: true, canRecordMore: false)
                onError?(message)
            }
        }
    }

    private func makeOutgoingThumbnail(
        for videoURL: URL,
    ) async throws -> VideoNoteInputThumbnailAsset? {
        let outputURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("video-note-thumbnail-\(UUID().uuidString).jpg")
        do {
            let sample = try await VideoNoteSegmentComposer.thumbnail(
                for: AVURLAsset(url: videoURL),
                at: 0,
            )
            let data = sample.jpegData
            try await Task.detached(priority: .utility) {
                try data.write(to: outputURL, options: .atomic)
            }.value
            try Task.checkCancellation()
            return VideoNoteInputThumbnailAsset(
                height: sample.height,
                url: outputURL,
                width: sample.width,
            )
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            log("Video-note outgoing thumbnail fallback: \(error)")
            return nil
        }
    }

    private func handleAutomaticStop(_ result: Result<VideoNoteAsset, Swift.Error>) {
        let acceptsResult: Bool =
            switch state {
            case .holding, .locked, .stopping:
                !didRequestDismiss && exitDisposition == .none
            case .failed, .idle, .preparing, .preview, .sending:
                false
            }
        guard acceptsResult else {
            if case .success(let asset) = result {
                try? FileManager.default.removeItem(at: asset.url)
            }
            return
        }
        operationTask?.cancel()
        let generation = operationGeneration
        switch result {
        case .success(let asset):
            state = .stopping
            operationTask = Task { [weak self] in
                guard let self else { return }
                defer { operationTask = nil }
                do {
                    try await processCapturedAsset(asset, generation: generation)
                } catch is CancellationError {
                    try? FileManager.default.removeItem(at: asset.url)
                } catch {
                    try? FileManager.default.removeItem(at: asset.url)
                    guard !Task.isCancelled,
                          operationGeneration == generation,
                          exitDisposition == .none
                    else { return }
                    if recordingDurationBaseline > 0,
                       recordingDraft != nil,
                       operationGeneration == generation
                    {
                        await recoverRecordMorePreview(message: message(for: error), generation: generation)
                    } else {
                        fail(message(for: error))
                    }
                }
            }
        case .failure(let error):
            if recordingDurationBaseline > 0, recordingDraft != nil {
                state = .stopping
                operationTask = Task { [weak self] in
                    guard let self else { return }
                    await recoverRecordMorePreview(message: message(for: error), generation: generation)
                    operationTask = nil
                }
            } else {
                fail(message(for: error))
            }
        }
    }

    private func recoverRecordMorePreview(
        message: String,
        generation: UUID,
    ) async {
        guard operationGeneration == generation,
              exitDisposition == .none,
              let recordingDraft
        else { return }
        captureSession.cancelRecording()
        captureSession.stopCapture()
        releasePreviewAudioSession()
        restoreScreenBrightness()
        do {
            try await preparePreview(draft: recordingDraft, generation: generation)
            onError?(message)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled,
                  operationGeneration == generation,
                  exitDisposition == .none
            else { return }
            fail("Couldn’t restore the video-message preview.")
        }
    }

    private func discardOwnedAsset(_ asset: VideoNoteAsset) {
        let discard = onDiscard
        Task {
            if let discard {
                await discard(asset)
            } else {
                await VideoNoteFileStore.shared.discardAsset(at: asset.url)
            }
        }
    }

    private func updateUI() {
        guard isViewLoaded else { return }
        loadingIndicator.stopAnimating()
        flipButton.isHidden = false
        flashButton.isHidden = false
        previewContainer.isUserInteractionEnabled = false
        switch state {
        case .preparing:
            loadingIndicator.startAnimating()
            statusLabel.text = "Preparing camera…"
        case .holding(let duration):
            statusLabel.text = "\(formatted(duration))  ← Cancel  ↑ Lock"
            previewContainer.isUserInteractionEnabled = true
        case .locked(let duration):
            statusLabel.text = "\(formatted(duration))  Locked"
            previewContainer.isUserInteractionEnabled = true
        case .stopping:
            loadingIndicator.startAnimating()
            statusLabel.text = "Preparing preview…"
            flipButton.isHidden = true
            flashButton.isHidden = true
        case .preview(let duration, let isPlaying, _):
            statusLabel.text = "\(formatted(duration))  \(isPlaying ? "Playing" : "Paused")"
            flipButton.isHidden = true
            flashButton.isHidden = true
            previewContainer.isUserInteractionEnabled = true
            previewContainer.isAccessibilityElement = true
            previewContainer.accessibilityTraits = [.button]
            updatePreviewAccessibility()
            updatePreviewMuteBadge()
        case .sending:
            loadingIndicator.startAnimating()
            statusLabel.text = "Sending…"
            flipButton.isHidden = true
            flashButton.isHidden = true
        case .failed(let message):
            statusLabel.text = message
            flipButton.isHidden = true
            flashButton.isHidden = true
        case .idle:
            statusLabel.text = nil
            flipButton.isHidden = true
            flashButton.isHidden = true
        }
        if case .preview = state {
            // Preview accessibility is configured above.
        } else {
            previewContainer.isAccessibilityElement = false
            muteBadgeView.isHidden = true
        }
        flashButton.setImage(
            UIImage(systemName: flashEnabled ? "bolt.fill" : "bolt.slash.fill"),
            for: .normal,
        )
    }

    @objc private func flipCamera() {
        let now = CACurrentMediaTime()
        if let lastFlipTimestamp, now - lastFlipTimestamp < 1 { return }
        lastFlipTimestamp = now
        let snapshot = cameraPreview.snapshotView(afterScreenUpdates: false)
        if let snapshot {
            snapshot.frame = previewContainer.bounds
            previewContainer.insertSubview(snapshot, aboveSubview: cameraPreview)
        }
        Task { [weak self, weak snapshot] in
            guard let self else { return }
            do {
                let position = try await captureSession.switchCamera()
                preferredPosition = position
                cameraPreview.updateConnection(position: position, orientation: currentInterfaceOrientation)
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.35)
                await updateFlashForCurrentCamera()
                UIView.animate(withDuration: 0.2, animations: {
                    snapshot?.alpha = 0
                }, completion: { _ in snapshot?.removeFromSuperview() })
            } catch {
                snapshot?.removeFromSuperview()
            }
        }
    }

    @objc private func toggleFlash() {
        flashEnabled.toggle()
        Task { [weak self] in
            await self?.updateFlashForCurrentCamera()
        }
        updateUI()
    }

    private func updateFlashForCurrentCamera() async {
        if preferredPosition == .front {
            _ = try? await captureSession.setTorchActive(false)
            if flashEnabled {
                if initialScreenBrightness == nil {
                    initialScreenBrightness = view.window?.windowScene?.screen.brightness
                }
                UIView.animate(withDuration: 0.2) {
                    self.view.window?.windowScene?.screen.brightness = 1
                }
            } else {
                restoreScreenBrightness()
            }
        } else {
            restoreScreenBrightness()
            _ = try? await captureSession.setTorchActive(flashEnabled)
        }
    }

    private func restoreScreenBrightness() {
        guard let initialScreenBrightness else { return }
        self.initialScreenBrightness = nil
        UIView.animate(withDuration: 0.2) {
            self.view.window?.windowScene?.screen.brightness = initialScreenBrightness
        }
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchStartZoomFactor = currentZoomFactor
        case .changed:
            currentZoomFactor = min(6, max(1, pinchStartZoomFactor * gesture.scale))
            captureSession.setZoomFactor(currentZoomFactor)
        case .cancelled, .ended, .failed:
            currentZoomFactor = 1
            captureSession.setZoomFactor(1, rampRate: 8)
        case .possible:
            break
        @unknown default:
            currentZoomFactor = 1
            captureSession.setZoomFactor(1, rampRate: 8)
        }
    }

    @objc private func previewTapped() {
        _ = togglePreviewMute()
    }

    private func togglePreviewMute() -> Bool {
        guard case .preview = state else { return false }
        previewMuted.toggle()
        previewPlayer.setMuted(true)
        updatePreviewAudioSession()
        updatePreviewAccessibility()
        updatePreviewMuteBadge()
        return true
    }

    private func updateOrientation() {
        guard isViewLoaded else { return }
        let orientation = currentInterfaceOrientation
        captureSession.updateOrientation(orientation)
        cameraPreview.updateConnection(position: preferredPosition, orientation: orientation)
    }

    private func fail(_ message: String) {
        operationGeneration = UUID()
        operationTask?.cancel()
        operationTask = nil
        captureSession.cancelRecording()
        captureSession.stopCapture()
        releasePreviewAudioSession()
        restoreScreenBrightness()
        state = .failed(message)
    }

    private func message(for error: Swift.Error) -> String {
        if let captureError = error as? VideoNoteCaptureError {
            switch captureError {
            case .cameraUnavailable:
                return "No camera is available for video messages."
            case .configurationFailed:
                return "Couldn’t start the video-message camera."
            case .permissionDenied:
                return "Camera and microphone access are required for video messages."
            case .recordingUnavailable:
                return "Video-message recording is unavailable."
            }
        }
        return "Couldn’t record the video message."
    }

    private func formatted(_ duration: Double) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func updatePreviewAccessibility() {
        previewContainer.accessibilityLabel = previewMuted
            ? "Video message preview, muted"
            : "Video message preview, sound on"
        previewContainer.accessibilityValue = previewMuted ? "Muted" : "Sound on"
    }

    private func updatePreviewMuteBadge() {
        guard case .preview = state else {
            muteBadgeView.isHidden = true
            return
        }
        muteBadgeView.isHidden = !previewMuted
    }

    private func updatePreviewAudioSession() {
        previewAudioSessionTask?.cancel()
        previewAudioSessionTask = nil
        guard !previewMuted, case .preview = state else {
            releasePreviewAudioSession()
            return
        }
        Media.shared.stop()
        let generation = operationGeneration
        previewAudioSessionTask = Task { [weak self] in
            guard let self else { return }
            await captureSession.waitForCaptureShutdown()
            guard !Task.isCancelled,
                  operationGeneration == generation,
                  exitDisposition == .none,
                  !previewMuted,
                  Media.shared.savedMediaPath.isEmpty,
                  case .preview = state
            else { return }
            activatePreviewAudioSession()
            previewAudioSessionTask = nil
        }
    }

    private func activatePreviewAudioSession() {
        guard !previewOwnsAudioSession else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false)
            try session.setCategory(.playback, mode: .moviePlayback, policy: .default, options: [
                .allowAirPlay,
                .allowBluetoothA2DP,
            ])
            try session.setActive(true)
            previewOwnsAudioSession = true
            previewPlayer.setMuted(false)
        } catch {
            previewOwnsAudioSession = false
            previewMuted = true
            previewPlayer.setMuted(true)
            updatePreviewAccessibility()
            updatePreviewMuteBadge()
            onError?("Couldn’t enable video-preview sound.")
        }
    }

    private func releasePreviewAudioSession() {
        previewAudioSessionTask?.cancel()
        previewAudioSessionTask = nil
        guard previewOwnsAudioSession else { return }
        previewOwnsAudioSession = false
        Media.shared.endAudioSessionRecord()
    }

    private func animateInIfNeeded() {
        guard !didAnimateIn else { return }
        didAnimateIn = true
        view.alpha = 0
        previewContainer.transform = CGAffineTransform(scaleX: 0.82, y: 0.82)
        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            self.view.alpha = 1
            self.previewContainer.transform = .identity
        }
    }

    private func dismissAnimated() {
        guard !didRequestDismiss else { return }
        didRequestDismiss = true
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseIn],
        ) {
            self.view.alpha = 0
            self.previewContainer.transform = CGAffineTransform(scaleX: 0.84, y: 0.84)
        } completion: { [weak self] _ in
            self?.onDismiss?()
        }
    }
}

// MARK: - VideoNotePreviewContainerView

private final class VideoNotePreviewContainerView: UIView {
    var onAccessibilityActivate: (() -> Bool)?

    override func accessibilityActivate() -> Bool {
        onAccessibilityActivate?() ?? false
    }
}
