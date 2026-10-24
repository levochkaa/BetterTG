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
        case .failed,
             .idle:
            false
        case .holding,
             .locked,
             .preparing,
             .preview,
             .sending,
             .stopping:
            true
        }
    }
}

// MARK: - VideoNoteSubmissionResult

enum VideoNoteSubmissionResult {
    case enqueued(messageID: Int64?)
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
    private let recordingStore: VideoNoteRecordingDraftStore
    private var captureFinalization: VideoNoteCaptureFinalization?
    private var lifecycleTask: Task<Void, Never>?
    private var lifecycleTaskID: UUID?
    private var lifecycleGeneration: UUID?
    private var lifecycleEpoch = 0
    private var lifecyclePaused = false
    private var isInBackground = false
    private var pendingLifecyclePreview: (generation: UUID, draft: VideoNoteRecordingDraft)?
    private var backgroundLease: VideoNoteBackgroundLease?
    private var backgroundLeaseGeneration: UUID?
    private var backgroundLeaseBackend = VideoNoteBackgroundLease.Backend.application
    private let previewPlayer = LocalMediaPlayer()
    private let chatID: Int64
    private let draftKey: ChatDraftKey
    private let replyMessageID: Int64?
    private let replyTo: InputMessageReplyTo?
    private let sendTopic: MessageTopic?
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
    private var operationID: UUID?
    private var operationGeneration = UUID()
    private var finishingCaptureGeneration: UUID?
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
    #if DEBUG
        private var beforeSubmitProbe: ((VideoNoteAsset, VideoNoteInputThumbnailAsset?) async -> Void)?
    #endif

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
        sendTopic: MessageTopic?,
        recordingStore: VideoNoteRecordingDraftStore = .shared,
    ) {
        self.chatID = chatID
        self.draftKey = draftKey
        self.replyMessageID = replyMessageID
        self.replyTo = replyTo
        self.sendTopic = sendTopic
        self.recordingStore = recordingStore
        super.init(nibName: nil, bundle: nil)
        self.isInBackground = UIApplication.shared.applicationState == .background
        self.lifecyclePaused = isInBackground
        captureSession.onAutomaticStop = { [weak self] generation, result in
            guard let self else {
                if case .success(let asset) = result {
                    try? FileManager.default.removeItem(at: asset.url)
                }
                return
            }
            handleAutomaticStop(result, generation: generation)
        }
        captureSession.onRecordingTerminated = { [weak self] generation, error in
            guard let finalization = self?.captureFinalization, finalization.generation == generation else { return }
            finalization.fail(error)
        }
        captureSession.onCaptureInterruption = { [weak self] generation in
            self?.preserveForLifecycle(background: false, generation: generation)
        }
        observeCaptureSession()
        observePreviewPlayer()
        observeLifecycle()
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
            backgroundLease?.finish()
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
        guard !isInBackground, exitDisposition == .none, !didRequestDismiss, !state.isActive else { return false }
        exitDisposition = .none
        recordingDurationBaseline = 0
        return await beginCapture(lockedInitially: false)
    }

    func recordMore() {
        guard !isInBackground, lifecycleTask == nil, operationTask == nil,
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
        startOperation { [weak self] _ in
            guard let self else { return }
            _ = await beginCapture(lockedInitially: true)
        }
    }

    func restore(_ draft: VideoNoteRecordingDraft) {
        guard exitDisposition == .none,
              !didRequestDismiss,
              state == .idle,
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
        startOperation { [weak self] _ in
            guard let self else { return }
            do {
                try await preparePreview(draft: draft, generation: generation)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      operationGeneration == generation,
                      exitDisposition == .none
                else { return }
                fail(L10n.betterTG("VideoNote.RestoreSavedPreviewFailed"))
            }
        }
    }

    func retryPersistedPreview() {
        guard let recordingDraft else { return }
        state = .idle
        restore(recordingDraft)
    }

    func cancel() {
        guard exitDisposition != .preserve else { return }
        if case .sending = state {
            exitDisposition = .discard
            dismissAfterSubmission = true
            return
        }
        exitDisposition = .discard
        captureFinalization?.discard()
        operationGeneration = UUID()
        cancelOperation()
        thumbnailTask?.cancel()
        thumbnailTask = nil
        captureSession.cancelRecording()
        captureSession.stopCapture()
        previewPlayer.stop()
        releasePreviewAudioSession()
        restoreScreenBrightness()
        if let recordingDraft {
            Task { await recordingStore.discard(id: recordingDraft.id) }
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
        guard !isInBackground else { return }
        switch state {
        case .preview:
            submitPreview()
        case .holding,
             .locked:
            finishRecording(submitAfterCapture: true)
        case .failed,
             .idle,
             .preparing,
             .sending,
             .stopping:
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
        guard !isInBackground, trimBaseDraft == nil,
              case .preview(let duration, let isPlaying, let canRecordMore) = state else { return }
        if isPlaying {
            previewPlayer.pause()
            state = .preview(duration: duration, isPlaying: false, canRecordMore: canRecordMore)
        } else {
            lifecyclePaused = false
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
        let epoch = lifecycleEpoch
        startOperation { [weak self] _ in
            guard let self else { return }
            do {
                let storedDraft = try await recordingStore.updateTrim(
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
                let autoplay = epoch == lifecycleEpoch && !lifecyclePaused && !isInBackground
                if autoplay {
                    previewPlayer.play(from: storedDraft.effectiveRange.lowerBound)
                } else {
                    previewPlayer.seek(to: storedDraft.effectiveRange.lowerBound, tolerance: 0)
                }
                state = .preview(
                    duration: storedDraft.effectiveRange.upperBound - storedDraft.effectiveRange.lowerBound,
                    isPlaying: autoplay,
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
                onError?(L10n.betterTG("VideoNote.TrimSaveFailed"))
            }
        }
    }

    func teardownForNavigation() {
        guard exitDisposition == .none else { return }
        let finalization = captureFinalization
        exitDisposition = .preserve
        finalization?.preserve()
        operationGeneration = UUID()
        // A manual finish or canonical append continues, but cannot publish into this UI.
        if finalization == nil || finalization?.isComplete == true {
            cancelOperation()
        }
        thumbnailTask?.cancel()
        thumbnailTask = nil
        if let finalization, !finalization.isComplete {
            let hasRecording = captureSession.stopInputPreservingRecording(generation: finalization.generation)
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-media-probe-video-note-preservation") {
                    VideoNotePreservationProbe.progress(
                        "navigation stop: hasRecording=\(hasRecording); requested=\(finalization.finishRequested); "
                            + captureSession.preservationProbeContext(),
                    )
                }
            #endif
            if hasRecording {
                finalization.requestFinish()
                Task { [self, finalization] in
                    do {
                        if let asset = try await captureSession.stopRecording(generation: finalization.generation) {
                            finalization.accept(asset)
                        }
                    } catch {
                        #if DEBUG
                            if ProcessInfo.processInfo.arguments.contains("-media-probe-video-note-preservation") {
                                VideoNotePreservationProbe.progress("navigation stop error: \(error)")
                            }
                        #endif
                        finalization.fail(error)
                    }
                    _ = await finalization.value()
                }
            } else if !finalization.finishRequested {
                finalization.fail(CancellationError())
                captureSession.stopCapture()
            }
        } else {
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-media-probe-video-note-preservation") {
                    VideoNotePreservationProbe.progress(
                        "navigation stop: missing/complete finalizer; " + captureSession.preservationProbeContext(),
                    )
                }
            #endif
            captureSession.stopCapture()
        }
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
        lifecyclePaused = false
        pendingLifecyclePreview = nil
        captureFinalization = makeCaptureFinalization(generation: generation)
        locked = lockedInitially
        state = .preparing
        loadViewIfNeeded()
        animateInIfNeeded()
        updateOrientation()

        do {
            try await captureSession.prepare(position: preferredPosition, generation: generation)
            try Task.checkCancellation()
            guard operationGeneration == generation,
                  captureFinalization?.isPreserving != true else { throw CancellationError() }
            cameraPreview.updateConnection(
                position: captureSession.currentPosition,
                orientation: currentInterfaceOrientation,
            )
            try await Task<Never, Never>.sleep(for: .milliseconds(150))
            try Task.checkCancellation()
            guard operationGeneration == generation,
                  captureFinalization?.isPreserving != true else { throw CancellationError() }
            let remainingDuration = max(0.5, 60 - recordingDurationBaseline)
            let remainingAutomaticDuration = max(0.5, 59.5 - recordingDurationBaseline)
            try await captureSession.startRecording(
                maximumDuration: remainingDuration,
                automaticStopDuration: remainingAutomaticDuration,
            )
            try Task.checkCancellation()
            guard publishCaptureStarted(generation: generation) else { throw CancellationError() }
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
            return true
        } catch is CancellationError {
            if captureFinalization?.generation == generation, captureFinalization?.finishRequested != true {
                captureFinalization?.fail(CancellationError())
            }
            return false
        } catch {
            if captureFinalization?.generation == generation { captureFinalization?.fail(error) }
            guard !Task.isCancelled,
                  operationGeneration == generation,
                  exitDisposition == .none,
                  captureFinalization?.isPreserving != true
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
        previewContainer.accessibilityHint = L10n.betterTG("Accessibility.TogglePreviewSoundHint")
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
            label: L10n.betterTG("Accessibility.SwitchCamera"),
            action: #selector(flipCamera),
        )
        configureControl(
            flashButton,
            symbol: "bolt.slash.fill",
            label: L10n.betterTG("Accessibility.ToggleFlash"),
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
            .sink { [weak self] update in
                guard let self, update.generation == operationGeneration, exitDisposition == .none,
                      captureFinalization?.isPreserving != true
                else { return }
                switch update.state {
                case .configuring:
                    if !state.isActive || state == .preparing {
                        state = .preparing
                    }
                case .failed(let message):
                    captureFinalization?.fail(VideoNoteCaptureError.recordingUnavailable)
                    if recordingDurationBaseline > 0,
                       recordingDraft != nil,
                       operationTask == nil
                    {
                        let generation = operationGeneration
                        state = .stopping
                        startOperation { [weak self] _ in
                            guard let self else { return }
                            await recoverRecordMorePreview(message: message, generation: generation)
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
                    publishRecordingDuration(duration)
                case .stopping:
                    publishCaptureStopping()
                }
            }
            .store(in: &cancellables)
    }

    private func observeLifecycle() {
        NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.preserveForLifecycle(background: true) }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.resumeLifecyclePreview() }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      type == AVAudioSession.InterruptionType.began.rawValue
                else { return }
                self?.preserveForLifecycle(background: false)
            }
            .store(in: &cancellables)
    }

    private func pauseForLifecycle() {
        lifecycleEpoch += 1
        lifecyclePaused = true
        previewPlayer.pause()
        previewMuted = true
        previewPlayer.setMuted(true)
        releasePreviewAudioSession()
        restoreScreenBrightness()
        if case .preview(let duration, _, let canRecordMore) = state {
            state = .preview(duration: duration, isPlaying: false, canRecordMore: canRecordMore)
        }
    }

    private func preserveForLifecycle(background: Bool, generation: UUID? = nil) {
        guard generation == nil || captureFinalization?.generation == generation else { return }
        if background { isInBackground = true }
        pauseForLifecycle()
        // Pending exports are fenced before onSubmit; accepted submissions retain ownership.
        guard state != .sending, exitDisposition != .discard,
              let finalization = captureFinalization, !finalization.isComplete
        else { return }
        finalization.preserve()
        if background, backgroundLeaseGeneration != finalization.generation {
            backgroundLease?.finish()
            backgroundLeaseGeneration = finalization.generation
            backgroundLease = VideoNoteBackgroundLease(backend: backgroundLeaseBackend) { [weak self, finalization] in
                // Once adopted, the canonical transaction must finish even after expiry.
                guard !finalization.hasAcceptedAsset, !finalization.isComplete else { return }
                self?.captureSession.cancelCapture(generation: finalization.generation)
                finalization.fail(CancellationError())
            }
        }
        guard lifecycleGeneration != finalization.generation else { return }
        lifecycleGeneration = finalization.generation
        finishingCaptureGeneration = finalization.generation
        let previousOperation = operationTask
        let hasRecording = captureSession.stopInputPreservingRecording(generation: finalization.generation)
        if exitDisposition == .none { state = .stopping }
        if hasRecording {
            finalization.requestFinish()
        } else if !finalization.finishRequested {
            finalization.fail(CancellationError())
        }
        startLifecycleOperation { [self, finalization] in
            if hasRecording {
                do {
                    if let asset = try await captureSession.stopRecording(generation: finalization.generation) {
                        finalization.accept(asset)
                    }
                } catch {
                    finalization.fail(error)
                }
            }
            let result = await finalization.value()
            if backgroundLeaseGeneration == finalization.generation { backgroundLease?.finish() }
            await previousOperation?.value
            guard ownsLifecyclePreview(finalization) else { return }
            let draft: VideoNoteRecordingDraft? =
                switch result {
                case .success(let saved): saved
                case .failure:
                    await recordingStore.drafts(for: finalization.destination)
                        .first { $0.id == finalization.baseDraft?.id }
                }
            guard ownsLifecyclePreview(finalization) else { return }
            if let draft {
                recordingDraft = draft
                pendingLifecyclePreview = (finalization.generation, draft)
                state = .preview(
                    duration: draft.effectiveRange.upperBound - draft.effectiveRange.lowerBound,
                    isPlaying: false, canRecordMore: draft.canRecordMore,
                )
                resumeLifecyclePreview(clearBackground: false)
            } else {
                state = .failed(L10n.betterTG("VideoNote.InterruptedBeforePreview"))
            }
        }
    }

    private func ownsLifecyclePreview(_ finalization: VideoNoteCaptureFinalization) -> Bool {
        captureFinalization === finalization && operationGeneration == finalization.generation
            && finalization.destination == draftKey && exitDisposition == .none && !didRequestDismiss
    }

    private func resumeLifecyclePreview(clearBackground: Bool = true) {
        if clearBackground { isInBackground = false }
        guard !isInBackground, let pending = pendingLifecyclePreview,
              pending.generation == operationGeneration, pending.draft.destination == draftKey,
              exitDisposition == .none, !didRequestDismiss
        else { return }
        pendingLifecyclePreview = nil
        startLifecycleOperation { [self] in
            do {
                try await preparePreview(draft: pending.draft, generation: pending.generation, autoplay: false)
            } catch {
                guard operationGeneration == pending.generation, exitDisposition == .none,
                      !didRequestDismiss else { return }
                state = .failed(L10n.betterTG("VideoNote.RestoreSavedPreviewFailed"))
            }
        }
    }

    private func startLifecycleOperation(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        lifecycleTaskID = id
        lifecycleTask = Task { [weak self] in
            await operation()
            guard let self, lifecycleTaskID == id else { return }
            lifecycleTaskID = nil
            lifecycleTask = nil
        }
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
                    guard !isInBackground, !lifecyclePaused else {
                        previewPlayer.pause()
                        return
                    }
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
                    onError?(L10n.betterTG("VideoNote.PreviewPlaybackFailed"))
                case .buffering,
                     .ended,
                     .idle,
                     .paused,
                     .preparing:
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

    private func startOperation(_ operation: @escaping @MainActor (UUID) async -> Void) {
        let id = UUID()
        operationID = id
        operationTask = Task { [weak self] in
            await operation(id)
            self?.completeOperation(id)
        }
    }

    private func completeOperation(_ id: UUID) {
        guard operationID == id else { return }
        operationID = nil
        operationTask = nil
    }

    private func cancelOperation() {
        operationID = nil
        operationTask?.cancel()
        operationTask = nil
    }

    private func finishRecording(submitAfterCapture: Bool) {
        guard !isInBackground, operationTask == nil else { return }
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
        case .failed,
             .idle,
             .preparing,
             .preview,
             .sending,
             .stopping:
            return
        }
        let generation = operationGeneration
        let finalization = captureFinalization
        let epoch = lifecycleEpoch
        finalization?.requestFinish()
        finishingCaptureGeneration = generation
        state = .stopping
        startOperation { [weak self] operationID in
            guard let self else { return }
            var capturedAsset: VideoNoteAsset?
            do {
                guard let asset = try await captureSession.stopRecording(generation: generation) else { return }
                capturedAsset = asset
                try Task.checkCancellation()
                guard operationGeneration == generation || finalization?.isPreserving == true else {
                    try? FileManager.default.removeItem(at: asset.url)
                    return
                }
                try await processCapturedAsset(asset, generation: generation, finalization: finalization)
                guard !Task.isCancelled,
                      operationGeneration == generation,
                      self.operationID == operationID,
                      finalization?.isPreserving != true,
                      lifecycleEpoch == epoch,
                      !captureSession.wasInterrupted(generation: generation)
                else { return }
                completeOperation(operationID)
                if submitAfterCapture {
                    submitPreview()
                }
            } catch is CancellationError {
                finalization?.fail(CancellationError())
                if let capturedAsset {
                    try? FileManager.default.removeItem(at: capturedAsset.url)
                }
                return
            } catch {
                finalization?.fail(error)
                if let capturedAsset {
                    try? FileManager.default.removeItem(at: capturedAsset.url)
                }
                guard !Task.isCancelled,
                      operationGeneration == generation,
                      exitDisposition == .none,
                      finalization?.isPreserving != true
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
        finalization: VideoNoteCaptureFinalization?,
    ) async throws {
        guard let finalization, finalization.generation == generation else {
            try? FileManager.default.removeItem(at: asset.url)
            throw CancellationError()
        }
        finalization.accept(asset)
        let draft = try await finalization.value().get()
        if finalization.isPreserving { return }
        guard operationGeneration == generation else {
            if exitDisposition == .discard {
                await recordingStore.discard(id: draft.id)
            }
            throw CancellationError()
        }
        try Task.checkCancellation()
        recordingDraft = draft
        try await preparePreview(draft: draft, generation: generation)
    }

    private func makeCaptureFinalization(generation: UUID) -> VideoNoteCaptureFinalization {
        VideoNoteCaptureFinalization(
            generation: generation, destination: draftKey, baseDraft: recordingDraft,
            replyMessageID: replyMessageID, replyTo: replyTo, sendTopic: sendTopic, store: recordingStore,
        )
    }

    private func preparePreview(
        draft: VideoNoteRecordingDraft,
        generation: UUID,
        autoplay: Bool = true,
    ) async throws {
        let epoch = lifecycleEpoch
        let composition = try await recordingStore.composition(for: draft)
        guard operationGeneration == generation, exitDisposition == .none else {
            if exitDisposition == .discard {
                await recordingStore.discard(id: draft.id)
            }
            throw CancellationError()
        }
        try Task.checkCancellation()
        if isInBackground {
            recordingDraft = draft
            pendingLifecyclePreview = (generation, draft)
            return
        }
        installPreview(
            draft: draft, composition: composition,
            autoplay: autoplay && epoch == lifecycleEpoch && !lifecyclePaused,
        )
    }

    private func installPreview(
        draft: VideoNoteRecordingDraft,
        composition: VideoNoteCompositionResult,
        autoplay: Bool = true,
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
            autoplay: autoplay,
            loops: true,
            playbackRange: draft.effectiveRange,
        )
        state = .preview(
            duration: draft.effectiveRange.upperBound - draft.effectiveRange.lowerBound,
            isPlaying: autoplay,
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
        guard !isInBackground, lifecycleTask == nil, operationTask == nil,
              trimBaseDraft == nil,
              let onSubmit
        else {
            if onSubmit == nil {
                fail(L10n.betterTG("VideoNote.SendingUnavailable"))
            }
            return
        }
        let generation = operationGeneration
        let draft = recordingDraft
        let epoch = lifecycleEpoch
        let wasInterrupted = captureSession.wasInterrupted(generation: generation)
        if let draft,
           draft.effectiveRange.upperBound - draft.effectiveRange.lowerBound < 1 - 0.000_001
        {
            onError?(L10n.betterTG("VideoNote.TooShort"))
            return
        }
        guard draft != nil || currentAsset != nil else { return }
        state = .sending
        startOperation { [weak self] _ in
            guard let self else { return }
            let asset: VideoNoteAsset
            var thumbnail: VideoNoteInputThumbnailAsset?
            let originRecordingDraftID: UUID?
            if let draft {
                let outputURL = FileManager.default
                    .temporaryDirectory
                    .appendingPathComponent("video-note-send-\(UUID().uuidString).mp4")
                do {
                    asset = try await recordingStore.materialize(
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
                        await recordingStore.discard(id: draft.id)
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
                    onError?(L10n.betterTG("VideoNote.PrepareSendFailed"))
                    return
                }
                originRecordingDraftID = draft.id
            } else if let currentAsset {
                asset = currentAsset
                originRecordingDraftID = nil
            } else {
                return
            }
            #if DEBUG
                await beforeSubmitProbe?(asset, thumbnail)
            #endif
            guard !Task.isCancelled, operationGeneration == generation,
                  lifecycleEpoch == epoch, !isInBackground,
                  wasInterrupted || !captureSession.wasInterrupted(generation: generation)
            else {
                if draft != nil { try? FileManager.default.removeItem(at: asset.url) }
                if let thumbnail { try? FileManager.default.removeItem(at: thumbnail.url) }
                if operationGeneration == generation, exitDisposition == .discard {
                    if let draft { await recordingStore.discard(id: draft.id) }
                    if ownsCurrentAsset, let currentAsset { discardOwnedAsset(currentAsset) }
                    releaseSubmittedPreview()
                    return
                }
                guard operationGeneration == generation, exitDisposition == .none, !didRequestDismiss else { return }
                previewPlayer.pause()
                let duration = draft.map { $0.effectiveRange.upperBound - $0.effectiveRange.lowerBound } ?? asset
                    .duration
                state = .preview(duration: duration, isPlaying: false, canRecordMore: draft?.canRecordMore ?? false)
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
                releaseSubmittedPreview()
            case .retained(let asset, let originConsumed, let message):
                if originConsumed {
                    // The send store owns retries and deletion after the recording is consumed.
                    releaseSubmittedPreview()
                    if !dismissAfterSubmission {
                        onError?(message)
                    }
                    return
                }
                if let draft {
                    try? FileManager.default.removeItem(at: asset.url)
                    if let thumbnail {
                        try? FileManager.default.removeItem(at: thumbnail.url)
                    }
                    if dismissAfterSubmission {
                        thumbnailTask?.cancel()
                        thumbnailTask = nil
                        await recordingStore.discard(id: draft.id)
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
                let autoplay = epoch == lifecycleEpoch && !lifecyclePaused && !isInBackground
                previewPlayer.load(url: asset.url, autoplay: autoplay, loops: true)
                state = .preview(duration: asset.duration, isPlaying: autoplay, canRecordMore: false)
                onError?(message)
            }
        }
    }

    private func releaseSubmittedPreview() {
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

    private func publishCaptureStarted(generation: UUID) -> Bool {
        guard operationGeneration == generation, exitDisposition == .none else { return false }
        guard finishingCaptureGeneration != generation else { return true }
        state = locked ? .locked(recordingDurationBaseline) : .holding(recordingDurationBaseline)
        return true
    }

    private func publishRecordingDuration(_ duration: Double) {
        guard finishingCaptureGeneration != operationGeneration else { return }
        let aggregateDuration = recordingDurationBaseline + duration
        progressLayer.strokeEnd = min(1, max(0, aggregateDuration / 60))
        state = locked ? .locked(aggregateDuration) : .holding(aggregateDuration)
    }

    private func publishCaptureStopping() {
        guard finishingCaptureGeneration != operationGeneration else { return }
        state = .stopping
    }

    private func acceptAutomaticFinish(generation: UUID) -> Bool {
        let acceptsResult: Bool =
            switch state {
            case .holding,
                 .locked,
                 .preparing,
                 .stopping:
                generation == operationGeneration && !didRequestDismiss && exitDisposition == .none
            case .failed,
                 .idle,
                 .preview,
                 .sending:
                false
            }
        guard acceptsResult else { return false }
        finishingCaptureGeneration = generation
        return true
    }

    private func handleAutomaticStop(_ result: Result<VideoNoteAsset, Swift.Error>, generation: UUID) {
        let finalization = captureFinalization
        if let finalization, finalization.generation == generation, finalization.isPreserving {
            switch result {
            case .success(let asset): finalization.accept(asset)
            case .failure(let error): finalization.fail(error)
            }
            return
        }
        guard acceptAutomaticFinish(generation: generation) else {
            if case .success(let asset) = result {
                try? FileManager.default.removeItem(at: asset.url)
            }
            return
        }
        finalization?.requestFinish()
        cancelOperation()
        switch result {
        case .success(let asset):
            finalization?.accept(asset)
            state = .stopping
            startOperation { [weak self] _ in
                guard let self else {
                    if finalization == nil { try? FileManager.default.removeItem(at: asset.url) }
                    return
                }
                do {
                    try Task.checkCancellation()
                    guard operationGeneration == generation, exitDisposition == .none else {
                        throw CancellationError()
                    }
                    try await processCapturedAsset(asset, generation: generation, finalization: finalization)
                } catch is CancellationError {
                    if finalization == nil { try? FileManager.default.removeItem(at: asset.url) }
                } catch {
                    if finalization == nil { try? FileManager.default.removeItem(at: asset.url) }
                    guard !Task.isCancelled,
                          operationGeneration == generation,
                          exitDisposition == .none,
                          finalization?.isPreserving != true
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
            finalization?.fail(error)
            if recordingDurationBaseline > 0, recordingDraft != nil {
                state = .stopping
                startOperation { [weak self] _ in
                    guard let self else { return }
                    await recoverRecordMorePreview(message: message(for: error), generation: generation)
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
            fail(L10n.betterTG("VideoNote.RestorePreviewFailed"))
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
            statusLabel.text = L10n.betterTG("VideoNote.PreparingCamera")
        case .holding(let duration):
            statusLabel.text = L10n.betterTG("VideoNote.HoldingStatus", formatted(duration))
            previewContainer.isUserInteractionEnabled = true
        case .locked(let duration):
            statusLabel.text = L10n.betterTG("VideoNote.LockedStatus", formatted(duration))
            previewContainer.isUserInteractionEnabled = true
        case .stopping:
            loadingIndicator.startAnimating()
            statusLabel.text = L10n.betterTG("VideoNote.PreparingPreview")
            flipButton.isHidden = true
            flashButton.isHidden = true
        case .preview(let duration, let isPlaying, _):
            statusLabel.text = isPlaying
                ? L10n.betterTG("VideoNote.PreviewPlayingStatus", formatted(duration))
                : L10n.betterTG("VideoNote.PreviewPausedStatus", formatted(duration))
            flipButton.isHidden = true
            flashButton.isHidden = true
            previewContainer.isUserInteractionEnabled = true
            previewContainer.isAccessibilityElement = true
            previewContainer.accessibilityTraits = [.button]
            updatePreviewAccessibility()
            updatePreviewMuteBadge()
        case .sending:
            loadingIndicator.startAnimating()
            statusLabel.text = L10n.betterTG("VideoNote.Sending")
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
        case .cancelled,
             .ended,
             .failed:
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
        guard !isInBackground, case .preview = state else { return false }
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
        cancelOperation()
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
                return L10n.betterTG("VideoNote.CameraUnavailable")
            case .configurationFailed:
                return L10n.betterTG("VideoNote.CameraStartFailed")
            case .permissionDenied:
                return L10n.betterTG("VideoNote.PermissionRequired")
            case .recordingUnavailable:
                return L10n.betterTG("VideoNote.RecordingUnavailable")
            }
        }
        return L10n.betterTG("VideoNote.RecordFailed")
    }

    private func formatted(_ duration: Double) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func updatePreviewAccessibility() {
        previewContainer.accessibilityLabel = previewMuted
            ? L10n.betterTG("Accessibility.VideoPreviewMuted")
            : L10n.betterTG("Accessibility.VideoPreviewSoundOn")
        previewContainer.accessibilityValue = previewMuted
            ? L10n.betterTG("Accessibility.Muted")
            : L10n.betterTG("Accessibility.SoundOn")
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
            onError?(L10n.betterTG("VideoNote.PreviewSoundFailed"))
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

#if DEBUG
    extension VideoNoteRecorderViewController {
        private enum LifecycleProbeScenario: String, CaseIterable {
            case background
            case manualBeforeFinish
            case automaticBeforeFinish
            case automaticBeforeDelivery
            case appendBeforeSave
            case appendFailure
            case expireBeforeFinish
            case expireDuringSave
            case cameraInterruption
            case navigationThenBackground
            case explicitCancel
        }

        static func verifyDebugLifecyclePreservation(directory: URL) async throws {
            var immediateExpirations = 0
            var immediateEnds = 0
            let lease = VideoNoteBackgroundLease(backend: .init(begin: { expiration in
                expiration()
                return UIBackgroundTaskIdentifier(rawValue: 41)
            }, end: { _ in immediateEnds += 1 })) { immediateExpirations += 1 }
            lease.finish()
            try VideoNotePreservationProbe.require(
                immediateExpirations == 1 && immediateEnds == 1, "synchronous lease expiry was lost/duplicated",
            )
            for scenario in LifecycleProbeScenario.allCases {
                try await verifyDebugLifecycle(scenario, directory: directory)
            }
            try await verifyDebugLifecyclePendingStartAndSend(directory: directory)
        }

        private static func verifyDebugLifecycle(_ scenario: LifecycleProbeScenario, directory: URL) async throws {
            VideoNotePreservationProbe.lifecycleProgress("\(scenario): started")
            let directory = directory.appendingPathComponent(scenario.rawValue, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = VideoNoteRecordingDraftStore(
                directoryURL: directory.appendingPathComponent("store"), adoptedRecordingOrigins: { [] },
            )
            let route = ChatDraftKey(accountID: UUID(), chatID: 42, topic: nil)
            let sendTopic = MessageTopic.messageTopicForum(.init(forumTopicId: 7))
            let baseAsset = try await VideoNoteAssetWriter.makeDebugSegment(
                outputURL: directory.appendingPathComponent("base.mp4"), duration: 1.1, frameSeed: 3,
            )
            let base = try await store.adopt(
                baseAsset, chatID: route.chatID, draftKey: route, replyMessageID: 31, replyTo: nil,
                sendTopic: sendTopic,
            )
            let recorder = VideoNoteRecorderViewController(
                chatID: route.chatID, draftKey: route, replyMessageID: 31, replyTo: nil, sendTopic: sendTopic,
                recordingStore: store,
            )
            recorder.loadViewIfNeeded()
            recorder.recordingDraft = base
            recorder.recordingDurationBaseline = base.totalDuration
            let generation = recorder.operationGeneration
            let finalization = recorder.makeCaptureFinalization(generation: generation)
            recorder.captureFinalization = finalization
            recorder.state = .holding(base.totalDuration + 0.6)
            var sends = 0
            recorder.onSubmit = { asset, _, _, _, _ in
                sends += 1
                return .retained(asset, originConsumed: false, message: "unexpected send")
            }
            var begins = 0
            var ends = 0
            var expiration: (@MainActor @Sendable () -> Void)?
            recorder.backgroundLeaseBackend = .init(begin: { callback in
                begins += 1
                expiration = callback
                return UIBackgroundTaskIdentifier(rawValue: begins)
            }, end: { _ in ends += 1 })
            let gate = VideoNoteFinishProbe.Gate()
            defer { Task { await gate.open() } }
            let blocksSave = [.appendBeforeSave, .appendFailure, .expireDuringSave].contains(scenario)
            let blocksDelivery = scenario == .automaticBeforeDelivery
            if blocksSave { await store.setBeforeCaptureSaveProbe { await gate.wait() } }
            var beforeFinish: (@Sendable () async -> Void)?
            var beforeDelivery: (@Sendable () async -> Void)?
            if !blocksSave, !blocksDelivery { beforeFinish = { await gate.wait() } }
            if blocksDelivery { beforeDelivery = { await gate.wait() } }
            try await recorder.captureSession.installPreservationProbe(
                output: directory.appendingPathComponent("capture.mp4"), generation: generation,
                beforeFinish: beforeFinish,
                beforeDelivery: beforeDelivery,
            )
            var automaticTask: Task<Void, Never>?
            switch scenario {
            case .automaticBeforeDelivery,
                 .automaticBeforeFinish,
                 .navigationThenBackground:
                automaticTask = recorder.captureSession.requestAutomaticPreservationProbe()
            case .appendBeforeSave,
                 .appendFailure,
                 .expireDuringSave,
                 .manualBeforeFinish:
                recorder.finishForSend()
            case .cameraInterruption:
                recorder.captureSession.interruptPreservationProbe()
            case .background,
                 .expireBeforeFinish,
                 .explicitCancel:
                recorder.preserveForLifecycle(background: true)
            }
            let manualTask = recorder.operationTask
            try await VideoNotePreservationProbe.waitForGate(gate, finalization: finalization)
            VideoNotePreservationProbe.lifecycleProgress("\(scenario): gate entered")
            if scenario == .navigationThenBackground { recorder.teardownForNavigation() }
            recorder.preserveForLifecycle(background: true)
            recorder.resumeLifecyclePreview()
            recorder.preserveForLifecycle(background: true)
            recorder.preserveForLifecycle(background: false, generation: generation)
            try VideoNotePreservationProbe.require(begins == 1, "duplicate lifecycle renewed background lease")
            var restored: [VideoNoteRecordingDraft]?
            let restore = Task {
                await VideoNoteRecordingPreservation.wait(for: route)
                restored = await store.drafts(for: route)
            }
            await VideoNoteRecordingPreservation.wait(for: .init(accountID: UUID(), chatID: route.chatID, topic: nil))
            try VideoNotePreservationProbe.require(restored == nil, "exact route did not wait for canonical result")
            if scenario == .appendFailure { _ = try await store.updateTrim(in: base, range: base.effectiveRange) }
            if scenario == .expireBeforeFinish || scenario == .expireDuringSave {
                expiration?()
                expiration?()
                try VideoNotePreservationProbe.require(ends == 1, "lease expiry did not release exactly once")
                if scenario == .expireDuringSave {
                    try VideoNotePreservationProbe.require(
                        finalization.hasAcceptedAsset && !finalization.isComplete,
                        "expiry cancelled accepted canonical save",
                    )
                }
            }
            if scenario == .explicitCancel { recorder.cancel() }
            await gate.open()
            await automaticTask?.value
            _ = await finalization.value()
            await manualTask?.value
            await recorder.lifecycleTask?.value
            await restore.value
            try VideoNotePreservationProbe.require(ends == 1 && sends == 0, "lease leak or interrupted implicit send")
            let drafts = await store.drafts(for: route)
            if scenario == .explicitCancel {
                try VideoNotePreservationProbe.require(
                    drafts.isEmpty && finalization.isDiscarded,
                    "explicit cancel retained draft",
                )
                return
            }
            guard drafts.count == 1, let draft = drafts.first else {
                throw VideoNotePreservationProbe.Failure(description: "missing/duplicate lifecycle canonical draft")
            }
            let expectedSegments = scenario == .appendFailure || scenario == .expireBeforeFinish ? 1 : 2
            try VideoNotePreservationProbe.require(
                draft.id == base.id && draft.segments.count == expectedSegments
                    && draft.segments.first?.id == base.segments.first?.id
                    && draft.destination == route && draft.replyMessageID == 31 && draft.sendTopic == sendTopic,
                "lifecycle lost canonical base/route/reply/topic",
            )
            for segment in draft.segments {
                _ = try await VideoNoteAssetWriter.validate(url: segment.fileURL, expectedLength: 400)
            }
            recorder.resumeLifecyclePreview()
            await recorder.lifecycleTask?.value
            recorder.resumeLifecyclePreview()
            if scenario == .navigationThenBackground {
                try VideoNotePreservationProbe.require(recorder.state == .idle, "foreground revived detached UI")
            } else {
                guard case .preview(_, false, _) = recorder.state else {
                    throw VideoNotePreservationProbe
                        .Failure(description: "foreground preview was not paused: \(recorder.state)")
                }
                try VideoNotePreservationProbe.require(
                    !recorder.previewPlayer.isPlaybackRequested,
                    "foreground autoplay",
                )
                recorder.preserveForLifecycle(background: true)
                recorder.resumeLifecyclePreview()
                try VideoNotePreservationProbe.require(
                    !recorder.previewPlayer.isPlaybackRequested && begins == 1,
                    "retained preview restarted playback or renewed lease",
                )
            }
            // A delayed callback cannot pause/claim the successor generation.
            recorder.operationGeneration = UUID()
            recorder.captureFinalization = recorder.makeCaptureFinalization(generation: recorder.operationGeneration)
            recorder.lifecyclePaused = false
            recorder.preserveForLifecycle(background: false, generation: generation)
            try VideoNotePreservationProbe.require(!recorder.lifecyclePaused, "old interruption affected successor")
            try VideoNotePreservationProbe.require(
                !FileManager.default.fileExists(atPath: directory.appendingPathComponent("capture.mp4").path),
                "unadopted lifecycle raw output retained",
            )
        }

        private static func verifyDebugLifecyclePendingStartAndSend(directory: URL) async throws {
            VideoNotePreservationProbe.lifecycleProgress("pending-start/accepted-submit: started")
            let store = VideoNoteRecordingDraftStore(
                directoryURL: directory.appendingPathComponent("pending-store"), adoptedRecordingOrigins: { [] },
            )
            let route = ChatDraftKey(accountID: UUID(), chatID: 43, topic: nil)
            let asset = try await VideoNoteAssetWriter.makeDebugSegment(
                outputURL: directory.appendingPathComponent("pending-base.mp4"), duration: 1.1, frameSeed: 3,
            )
            let base = try await store.adopt(
                asset,
                chatID: route.chatID,
                draftKey: route,
                replyMessageID: nil,
                replyTo: nil,
                sendTopic: nil,
            )
            let recorder = VideoNoteRecorderViewController(
                chatID: route.chatID, draftKey: route, replyMessageID: nil, replyTo: nil, sendTopic: nil,
                recordingStore: store,
            )
            recorder.loadViewIfNeeded()
            recorder.recordingDraft = base
            recorder.captureFinalization = recorder.makeCaptureFinalization(generation: recorder.operationGeneration)
            recorder.state = .preparing
            var begins = 0
            var ends = 0
            recorder.backgroundLeaseBackend = .init(begin: { _ in
                begins += 1
                return UIBackgroundTaskIdentifier(rawValue: 1)
            }, end: { _ in ends += 1 })
            recorder.preserveForLifecycle(background: true)
            await recorder.lifecycleTask?.value
            await VideoNoteRecordingPreservation.wait(for: route)
            recorder.resumeLifecyclePreview()
            await recorder.lifecycleTask?.value
            try VideoNotePreservationProbe.require(
                recorder.recordingDraft?.id == base.id && begins == 1 && ends == 1,
                "pending start lost previous draft or leaked lease",
            )
            let gate = VideoNoteFinishProbe.Gate()
            defer { Task { await gate.open() } }
            var sends = 0
            var cancelled = false
            recorder.onSubmit = { asset, _, _, _, _ in
                sends += 1
                await gate.wait()
                cancelled = Task.isCancelled
                return .retained(asset, originConsumed: false, message: "fixture retry")
            }
            let exportGate = VideoNoteFinishProbe.Gate()
            defer { Task { await exportGate.open() } }
            var preparedURLs = [URL]()
            recorder.beforeSubmitProbe = { asset, thumbnail in
                preparedURLs = [asset.url] + (thumbnail.map { [$0.url] } ?? [])
                await exportGate.wait()
            }
            recorder.finishForSend()
            let exportDeadline = ContinuousClock.now.advanced(by: .seconds(15))
            while await !exportGate.isEntered {
                guard ContinuousClock.now < exportDeadline else {
                    throw VideoNotePreservationProbe.Failure(description: "pre-submit export gate timeout")
                }
                try await Task<Never, Never>.sleep(for: .milliseconds(10))
            }
            recorder.preserveForLifecycle(background: true)
            recorder.resumeLifecyclePreview()
            await exportGate.open()
            await recorder.operationTask?.value
            try VideoNotePreservationProbe.require(
                sends == 0 && !preparedURLs.isEmpty
                    && preparedURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }
                    && recorder.recordingDraft?.id == base.id && !recorder.previewPlayer.isPlaybackRequested,
                "background/foreground during export sent, leaked export, deleted canonical draft or autoplayed",
            )
            for segment in base.segments {
                try VideoNotePreservationProbe.require(
                    FileManager.default.fileExists(atPath: segment.fileURL.path),
                    "cancelled export removed canonical source",
                )
            }
            recorder.beforeSubmitProbe = nil
            recorder.finishForSend()
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            while await !gate.isEntered {
                guard ContinuousClock.now < deadline
                    else { throw VideoNotePreservationProbe.Failure(description: "submit gate timeout") }
                try await Task<Never, Never>.sleep(for: .milliseconds(10))
            }
            recorder.preserveForLifecycle(background: true)
            recorder.preserveForLifecycle(background: false)
            try VideoNotePreservationProbe.require(
                recorder.state == .sending && begins == 1,
                "lifecycle claimed accepted submission",
            )
            await gate.open()
            await recorder.operationTask?.value
            try VideoNotePreservationProbe.require(
                sends == 1 && !cancelled,
                "accepted submission was cancelled/duplicated",
            )
            recorder.resumeLifecyclePreview()
            recorder.teardownForNavigation()
        }

        private enum PreservationProbeScenario: String, CaseIterable {
            case navigation
            case manualBeforeFinish
            case automaticBeforeFinish
            case automaticBeforeDelivery
            case appendBeforeSave
            case appendFailure
            case explicitCancel
            case navigationThenCaptureFailure
        }

        static func verifyDebugNavigationPreservation(directory: URL) async throws {
            for scenario in PreservationProbeScenario.allCases {
                try await verifyDebugNavigationPreservation(scenario, directory: directory)
            }
        }

        private static func verifyDebugNavigationPreservation(
            _ scenario: PreservationProbeScenario,
            directory: URL,
        ) async throws {
            VideoNotePreservationProbe.progress("\(scenario): started")
            let directory = directory.appendingPathComponent(scenario.rawValue, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = VideoNoteRecordingDraftStore(
                directoryURL: directory.appendingPathComponent("recording-store"), adoptedRecordingOrigins: { [] },
            )
            let route = ChatDraftKey(accountID: UUID(), chatID: 29, topic: nil)
            let sendTopic = MessageTopic.messageTopicForum(.init(forumTopicId: 7))
            let unrelatedRoutes = [
                ChatDraftKey(accountID: UUID(), chatID: route.chatID, topic: nil),
                ChatDraftKey(accountID: route.accountID, chatID: route.chatID + 1, topic: nil),
                ChatDraftKey(accountID: route.accountID, chatID: route.chatID, topic: sendTopic),
            ]
            let usesBase = scenario == .appendBeforeSave || scenario == .appendFailure
                || scenario == .navigationThenCaptureFailure || scenario == .explicitCancel
            var baseDraft: VideoNoteRecordingDraft?
            if usesBase {
                let asset = try await VideoNoteAssetWriter.makeDebugSegment(
                    outputURL: directory.appendingPathComponent("base.mp4"), duration: 1.1, frameSeed: 3,
                )
                baseDraft = try await store.adopt(
                    asset, chatID: route.chatID, draftKey: route, replyMessageID: 31, replyTo: nil,
                    sendTopic: sendTopic,
                )
            }
            let recorder = VideoNoteRecorderViewController(
                chatID: route.chatID, draftKey: route, replyMessageID: 31, replyTo: nil, sendTopic: sendTopic,
                recordingStore: store,
            )
            // Production loads/attaches preview views before capture preparation.
            recorder.loadViewIfNeeded()
            let generation = recorder.operationGeneration
            recorder.recordingDraft = baseDraft
            recorder.recordingDurationBaseline = baseDraft?.totalDuration ?? 0
            recorder.captureFinalization = recorder.makeCaptureFinalization(generation: generation)
            guard let finalization = recorder.captureFinalization else {
                throw VideoNotePreservationProbe.Failure(description: "missing finalization")
            }
            recorder.state = .holding(recorder.recordingDurationBaseline + 0.6)
            var submitCount = 0
            recorder.onSubmit = { asset, _, _, _, _ in
                submitCount += 1
                return .retained(asset, originConsumed: false, message: "unexpected send")
            }
            let gate = VideoNoteFinishProbe.Gate()
            let blocksSave = scenario == .appendBeforeSave || scenario == .appendFailure
            let blocksDelivery = scenario == .automaticBeforeDelivery
            if blocksSave { await store.setBeforeCaptureSaveProbe { await gate.wait() } }
            var beforeFinish: (@Sendable () async -> Void)?
            var beforeDelivery: (@Sendable () async -> Void)?
            if !blocksSave, !blocksDelivery { beforeFinish = { await gate.wait() } }
            if blocksDelivery { beforeDelivery = { await gate.wait() } }
            defer { Task { await gate.open() } }
            try await recorder.captureSession.installPreservationProbe(
                output: directory.appendingPathComponent("capture.mp4"), generation: generation,
                beforeFinish: beforeFinish,
                beforeDelivery: beforeDelivery,
            )
            VideoNotePreservationProbe.progress("\(scenario): fixture installed")
            try recorder.captureSession.verifyStalePreservationStop(generation: generation)
            var automaticTask: Task<Void, Never>?
            switch scenario {
            case .navigation:
                recorder.teardownForNavigation()
            case .appendBeforeSave,
                 .appendFailure,
                 .explicitCancel,
                 .manualBeforeFinish:
                recorder.finishForSend()
            case .automaticBeforeDelivery,
                 .automaticBeforeFinish,
                 .navigationThenCaptureFailure:
                automaticTask = recorder.captureSession.requestAutomaticPreservationProbe()
            }
            let activeOperation = recorder.operationTask
            VideoNotePreservationProbe.progress(
                "\(scenario): action invoked; state=\(recorder.state); complete=\(finalization.isComplete); "
                    + "requested=\(finalization.finishRequested); " + recorder.captureSession
                        .preservationProbeContext(),
            )
            try await VideoNotePreservationProbe.waitForGate(gate, finalization: finalization)
            VideoNotePreservationProbe.progress("\(scenario): gate entered")
            if scenario == .explicitCancel {
                recorder.cancel()
                await gate.open()
                _ = await finalization.value()
                await activeOperation?.value
                let drafts = await store.drafts(for: route)
                try VideoNotePreservationProbe.require(drafts.isEmpty, "explicit cancel retained canonical draft")
                try VideoNotePreservationProbe.require(
                    finalization.isDiscarded,
                    "explicit cancel did not invalidate finalizer",
                )
                return
            }
            recorder.teardownForNavigation()
            recorder.teardownForNavigation()
            var restored: [VideoNoteRecordingDraft]?
            var unrelatedFinished = false
            let restoration = Task {
                await VideoNoteRecordingPreservation.wait(for: route)
                restored = await store.drafts(for: route)
            }
            let unrelated = Task {
                for unrelatedRoute in unrelatedRoutes {
                    await VideoNoteRecordingPreservation.wait(for: unrelatedRoute)
                }
                unrelatedFinished = true
            }
            await unrelated.value
            VideoNotePreservationProbe.progress("\(scenario): unrelated routes returned")
            try VideoNotePreservationProbe.require(
                restored == nil && unrelatedFinished,
                "route barrier missing or crosses account/chat/topic",
            )
            // Old recorder actions cannot destroy the canonical owner exposed on reopening.
            recorder.cancel()
            recorder.captureSession.publishPreservationProbeState(.recording(14))
            recorder.captureSession.publishPreservationProbeState(.failed("obsolete"))
            if scenario == .appendFailure, let baseDraft {
                _ = try await store.updateTrim(in: baseDraft, range: baseDraft.effectiveRange)
            }
            if scenario == .navigationThenCaptureFailure {
                recorder.captureSession.terminatePreservationProbe()
            }
            await gate.open()
            VideoNotePreservationProbe.progress("\(scenario): gate opened")
            await automaticTask?.value
            let result = await finalization.value()
            VideoNotePreservationProbe.progress("\(scenario): finalizer returned")
            await restoration.value
            VideoNotePreservationProbe.progress("\(scenario): restoration returned")
            await recorder.operationTask?.value
            let failed = scenario == .appendFailure || scenario == .navigationThenCaptureFailure
            switch result {
            case .success where failed:
                throw VideoNotePreservationProbe.Failure(description: "\(scenario): expected finalization failure")
            case .failure where !failed:
                _ = try result.get()
            default:
                break
            }
            guard let restored, restored.count == 1, let draft = restored.first else {
                throw VideoNotePreservationProbe.Failure(description: "\(scenario): missing/duplicate canonical draft")
            }
            try VideoNotePreservationProbe.require(
                draft.destination == route && draft.replyMessageID == 31 && draft.sendTopic == sendTopic,
                "\(scenario): route/reply/topic changed",
            )
            let expectedSegments = usesBase && !failed ? 2 : 1
            try VideoNotePreservationProbe.require(
                draft.segments.count == expectedSegments,
                "\(scenario): wrong segment count",
            )
            if let baseDraft {
                try VideoNotePreservationProbe.require(
                    draft.id == baseDraft.id && draft.segments.first?.id == baseDraft.segments.first?.id,
                    "\(scenario): previous canonical draft replaced",
                )
            }
            for segment in draft.segments {
                _ = try await VideoNoteAssetWriter.validate(url: segment.fileURL, expectedLength: 400)
            }
            try VideoNotePreservationProbe.require(
                recorder.state == .idle && submitCount == 0 && !finalization.isDiscarded,
                "\(scenario): detached state revived, submitted or stale-cancelled",
            )
            try VideoNotePreservationProbe.require(
                !FileManager.default.fileExists(atPath: directory.appendingPathComponent("capture.mp4").path),
                "\(scenario): unadopted temporary capture retained",
            )
        }

        private enum SubmissionProbeScenario: String, CaseIterable {
            case consumed
            case consumedAfterCancel
            case consumedAfterNavigation
            case enqueued
            case unconsumed
            case unconsumedAfterCancel

            var consumesOrigin: Bool {
                self != .unconsumed && self != .unconsumedAfterCancel
            }
        }

        static func verifyDebugSubmissionOwnership(directory: URL) async throws {
            for scenario in SubmissionProbeScenario.allCases {
                try await verifyDebugSubmission(scenario, directory: directory)
            }
        }

        private static func verifyDebugSubmission(_ scenario: SubmissionProbeScenario, directory: URL) async throws {
            let directory = directory.appendingPathComponent(scenario.rawValue, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = VideoNoteFileStore(
                directoryURL: directory.appendingPathComponent("send-store"),
                legacyBindingAllowed: { _ in false },
            )
            let route = ChatDraftKey(accountID: UUID(), chatID: 18, topic: nil)
            let asset = try await VideoNoteAssetWriter.makeDebugSegment(
                outputURL: directory.appendingPathComponent("local.mp4"), duration: 1.1, frameSeed: 12,
            )
            let gate = VideoNoteSubmissionOwnershipProbe.Gate()
            let discardFinished = VideoNoteSubmissionOwnershipProbe.Gate()
            var recorder: VideoNoteRecorderViewController? = VideoNoteRecorderViewController(
                chatID: route.chatID, draftKey: route, replyMessageID: nil, replyTo: nil, sendTopic: nil,
            )
            weak let weakRecorder = recorder
            var discardCount = 0
            var errorCount = 0
            var sendCount = 0
            var submissionError: Swift.Error?
            var retainedDraft: VideoNoteSendDraft?
            recorder?.currentAsset = asset
            recorder?.ownsCurrentAsset = true
            recorder?.state = .preview(duration: asset.duration, isPlaying: false, canRecordMore: false)
            recorder?.onError = { _ in errorCount += 1 }
            recorder?.onDiscard = { asset in
                discardCount += 1
                await store.discardAsset(at: asset.url)
                await discardFinished.wait()
            }
            recorder?.onSubmit = { asset, _, _, _, _ in
                sendCount += 1
                let result: VideoNoteSubmissionResult
                do {
                    if scenario.consumesOrigin {
                        let preparation = try await store.adoptAndPrepareEnqueue(
                            asset, chatID: route.chatID, draftKey: route, originRecordingDraftID: nil,
                            replyMessageID: nil, replyTo: nil,
                        )
                        guard case .ready(let draft) = preparation else {
                            throw VideoNoteSubmissionOwnershipProbe.Failure(description: "fresh fixture was not ready")
                        }
                        if scenario == .enqueued {
                            retainedDraft = try await store.registerEnqueued(draft, temporaryMessageID: -18).draft
                            result = .enqueued(messageID: -18)
                        } else {
                            let pending = try await store.markPending(draft)
                            retainedDraft = pending
                            result = .retained(pending.asset, originConsumed: true, message: "probe retained send")
                        }
                    } else {
                        result = .retained(asset, originConsumed: false, message: "probe local rejection")
                    }
                } catch {
                    submissionError = error
                    result = .retained(asset, originConsumed: false, message: "probe setup failed")
                }
                await gate.wait()
                return result
            }
            recorder?.finishForSend()
            let submissionTask = recorder?.operationTask
            await gate.waitUntilEntered()
            if scenario == .consumedAfterCancel || scenario == .unconsumedAfterCancel {
                recorder?.cancel()
            } else if scenario == .consumedAfterNavigation {
                recorder?.teardownForNavigation()
                recorder?.operationGeneration = UUID()
                recorder?.state = .preparing
            }
            gate.open()
            if scenario == .unconsumedAfterCancel {
                await discardFinished.waitUntilEntered()
                discardFinished.open()
            }
            await submissionTask?.value
            if let submissionError { throw submissionError }
            try VideoNoteSubmissionOwnershipProbe.require(sendCount == 1, "\(scenario): duplicate submission")

            if scenario.consumesOrigin {
                guard let draft = retainedDraft else {
                    throw VideoNoteSubmissionOwnershipProbe
                        .Failure(description: "\(scenario): send-store draft missing")
                }
                let expectedState: VideoNoteComposerState = scenario == .consumedAfterNavigation ? .preparing : .idle
                try VideoNoteSubmissionOwnershipProbe.require(
                    recorder?.state == expectedState && recorder?.currentAsset == nil && recorder?
                        .ownsCurrentAsset == false,
                    "\(scenario): obsolete recorder retained ownership or changed successor state",
                )
                let expectedErrors = scenario == .consumed ? 1 : 0
                try VideoNoteSubmissionOwnershipProbe.require(
                    errorCount == expectedErrors,
                    "\(scenario): incorrect error publication",
                )
                let retry = scenario == .enqueued ? nil : try await store.beginEnqueue(draft)
                recorder?.cancel()
                recorder = nil
                await Task.yield()
                try VideoNoteSubmissionOwnershipProbe.require(
                    weakRecorder == nil,
                    "\(scenario): recorder did not deinitialize",
                )
                try VideoNoteSubmissionOwnershipProbe.require(
                    discardCount == 0,
                    "\(scenario): recorder discarded transferred asset",
                )
                try VideoNoteSubmissionOwnershipProbe.require(
                    FileManager.default.fileExists(atPath: draft.fileURL.path), "\(scenario): canonical media removed",
                )
                let drafts = await store.drafts(for: route)
                try VideoNoteSubmissionOwnershipProbe.require(
                    drafts.contains { $0.id == draft.id && $0.removalRequestedAt == nil },
                    "\(scenario): manifest removed or tombstoned",
                )
                if let retry {
                    let registration = try await store.registerEnqueued(retry, temporaryMessageID: -19)
                    try VideoNoteSubmissionOwnershipProbe.require(
                        registration.draft.temporaryMessageID == -19 && registration.outcome == nil,
                        "\(scenario): retry registration failed after obsolete teardown",
                    )
                }
            } else {
                if scenario == .unconsumed {
                    try VideoNoteSubmissionOwnershipProbe.require(
                        recorder?.currentAsset?.url == asset.url && recorder?.ownsCurrentAsset == true,
                        "unconsumed result lost local asset ownership",
                    )
                    recorder?.cancel()
                    await discardFinished.waitUntilEntered()
                    discardFinished.open()
                }
                recorder = nil
                try VideoNoteSubmissionOwnershipProbe.require(
                    discardCount == 1,
                    "\(scenario): local asset not discarded once",
                )
                try VideoNoteSubmissionOwnershipProbe.require(
                    !FileManager.default.fileExists(atPath: asset.url.path),
                    "\(scenario): local cancelled asset remains",
                )
                try VideoNoteSubmissionOwnershipProbe.require(
                    errorCount == (scenario == .unconsumed ? 1 : 0), "\(scenario): unexpected local error count",
                )
            }
        }

        static func verifyDebugOperationOwnership() async throws {
            let recorder = VideoNoteRecorderViewController(
                chatID: 1, draftKey: .init(accountID: UUID(), chatID: 1, topic: nil),
                replyMessageID: nil, replyTo: nil, sendTopic: nil,
            )
            let losingGate = VideoNoteFinishProbe.Gate()
            let winningGate = VideoNoteFinishProbe.Gate()
            recorder.startOperation { _ in await losingGate.wait() }
            let losingTask = recorder.operationTask
            let losingID = recorder.operationID
            await losingGate.waitUntilEntered()
            recorder.cancelOperation()
            recorder.startOperation { _ in await winningGate.wait() }
            let winningTask = recorder.operationTask
            let winningID = recorder.operationID
            await winningGate.waitUntilEntered()
            await losingGate.open()
            await losingTask?.value
            try VideoNoteFinishProbe.require(
                winningID != losingID && recorder.operationID == winningID && recorder.operationTask != nil,
                "losing completion cleared replacement task",
            )
            await winningGate.open()
            await winningTask?.value
            try VideoNoteFinishProbe.require(
                recorder.operationID == nil && recorder.operationTask == nil, "winning completion failed to clear",
            )
            let generation = recorder.operationGeneration
            recorder.state = .preparing
            try VideoNoteFinishProbe.require(
                !recorder.acceptAutomaticFinish(generation: UUID()), "wrong-generation automatic result accepted",
            )
            try VideoNoteFinishProbe.require(
                recorder.acceptAutomaticFinish(generation: generation), "automatic result while preparing rejected",
            )
            recorder.state = .stopping
            try VideoNoteFinishProbe.require(
                recorder.publishCaptureStarted(generation: generation),
                "late start rejected current capture",
            )
            recorder.publishRecordingDuration(0.7)
            try VideoNoteFinishProbe.require(
                recorder.state == .stopping,
                "late start/duration revived finishing capture",
            )
            let preview = VideoNoteComposerState.preview(duration: 0.6, isPlaying: false, canRecordMore: true)
            recorder.state = preview
            recorder.publishCaptureStopping()
            recorder.publishRecordingDuration(0.8)
            try VideoNoteFinishProbe.require(recorder.state == preview, "queued capture event overwrote preview")
            try VideoNoteFinishProbe.require(
                !recorder.acceptAutomaticFinish(generation: generation), "preview accepted duplicate automatic result",
            )
            recorder.operationGeneration = UUID()
            recorder.state = .preparing
            try VideoNoteFinishProbe.require(
                !recorder.publishCaptureStarted(generation: generation), "obsolete start completed new capture",
            )
            recorder.publishRecordingDuration(0.2)
            try VideoNoteFinishProbe.require(
                recorder.state == .holding(0.2),
                "finishing gate blocked successor capture",
            )
            try VideoNoteFinishProbe.require(!recorder.isViewLoaded, "operation proof loaded UI")
        }
    }
#endif

// MARK: - VideoNotePreviewContainerView

private final class VideoNotePreviewContainerView: UIView {
    var onAccessibilityActivate: (() -> Bool)?

    override func accessibilityActivate() -> Bool {
        onAccessibilityActivate?() ?? false
    }
}
