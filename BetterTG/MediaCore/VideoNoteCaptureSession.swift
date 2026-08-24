// VideoNoteCaptureSession.swift

import AVFoundation
import Combine
import ImageIO
import UIKit

enum VideoNoteCaptureError: Swift.Error {
    case cameraUnavailable
    case configurationFailed
    case permissionDenied
    case recordingUnavailable
}

final class VideoNoteCaptureSession: NSObject, @unchecked Sendable {
    enum Position: Equatable {
        case back
        case front

        var capturePosition: AVCaptureDevice.Position {
            switch self {
            case .back: .back
            case .front: .front
            }
        }

    }

    enum State: Equatable {
        case configuring
        case failed(String)
        case idle
        case ready(Position)
        case recording(Double)
        case stopping
    }

    override init() {
        super.init()
        observeSessionLifecycle()
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        contextLock.withLock {
            captureEnabled = false
            preparationGeneration = nil
            activeCaptureGeneration = nil
            pendingRecordingStart = nil
        }
        cancelRecording()
        deactivateAudioSession()
        let torchDevice = videoInput?.device
        configurationQueue.async { [captureSession] in
            Self.disableTorch(on: torchDevice)
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }

    let captureSession = AVCaptureSession()
    var onAutomaticStop: ((Result<VideoNoteAsset, Error>) -> Void)?

    var statePublisher: AnyPublisher<State, Never> {
        stateSubject.removeDuplicates().eraseToAnyPublisher()
    }

    var currentPosition: Position {
        contextLock.lock()
        defer { contextLock.unlock() }
        return position
    }

    func prepare(position: Position = .front, generation: UUID) async throws {
        try Task.checkCancellation()
        let displacedRecording = contextLock.withLock { () -> RecordingContext? in
            preparationGeneration = generation
            activeCaptureGeneration = nil
            captureEnabled = false
            pendingRecordingStart = nil
            let context = recordingContext
            recordingContext = nil
            enqueueStateLocked(.configuring)
            return context
        }
        displacedRecording?.writer.cancel()

        do {
            try await withTaskCancellationHandler {
                try await prepareIsolated(position: position, generation: generation)
                try Task.checkCancellation()
            } onCancel: { [weak self] in
                self?.terminateCapture(matching: generation)
            }
        } catch {
            if error is CancellationError || Task.isCancelled {
                terminateCapture(matching: generation)
            }
            throw error
        }
    }

    private func prepareIsolated(position: Position, generation: UUID) async throws {
        let microphoneGranted = await AVAudioApplication.requestRecordPermission()
        try Task.checkCancellation()
        guard isCurrentPreparation(generation) else { throw CancellationError() }
        guard microphoneGranted else {
            guard failPreparation(
                generation,
                message: "Microphone access is required for video notes."
            ) else { throw CancellationError() }
            throw VideoNoteCaptureError.permissionDenied
        }
        let cameraGranted = await requestCameraPermission()
        try Task.checkCancellation()
        guard isCurrentPreparation(generation) else { throw CancellationError() }
        guard cameraGranted else {
            guard failPreparation(
                generation,
                message: "Camera access is required for video notes."
            ) else { throw CancellationError() }
            throw VideoNoteCaptureError.permissionDenied
        }
        await MainActor.run { Media.shared.stop() }
        try await configure(position: position, generation: generation)
    }

    func invalidatePreparation() {
        terminateCapture(matching: nil)
    }

    func updateOrientation(_ orientation: UIInterfaceOrientation) {
        contextLock.withLock {
            interfaceOrientation = orientation
        }
    }

    func startRecording(maximumDuration: Double = 60) async throws {
        try Task.checkCancellation()
        let requestID = UUID()
        let registered = contextLock.withLock { () -> Bool in
            guard captureEnabled,
                  pendingRecordingStart == nil,
                  recordingContext == nil
            else { return false }
            pendingRecordingStart = requestID
            return true
        }
        guard registered else { throw VideoNoteCaptureError.recordingUnavailable }

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    configurationQueue.async { [weak self] in
                        guard let self else {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        do {
                            let normalizedMaximumDuration = min(60, max(0.5, maximumDuration))
                            let outputURL = FileManager.default.temporaryDirectory
                                .appendingPathComponent("\(UUID().uuidString)-video-note.mp4")
                            let writer = try VideoNoteAssetWriter(
                                outputURL: outputURL,
                                length: 400,
                                maximumDuration: normalizedMaximumDuration,
                            )
                            let context = self.contextLock.withLock { () -> RecordingContext? in
                                guard self.pendingRecordingStart == requestID,
                                      self.captureEnabled,
                                      self.recordingContext == nil,
                                      self.captureSession.isRunning
                                else { return nil }
                                self.pendingRecordingStart = nil
                                let context = RecordingContext(
                                    writer: writer,
                                    position: self.position,
                                    orientation: self.interfaceOrientation,
                                    minimumPresentationTime: CMClockGetTime(CMClockGetHostTimeClock()),
                                    automaticStopDuration: min(59.5, normalizedMaximumDuration),
                                    startRequestID: requestID,
                                )
                                self.recordingContext = context
                                self.enqueueStateLocked(.recording(0))
                                return context
                            }
                            guard context != nil else {
                                writer.cancel()
                                throw CancellationError()
                            }
                            continuation.resume()
                        } catch {
                            self.clearPendingRecordingStart(requestID)
                            continuation.resume(throwing: error)
                        }
                    }
                }
                try Task.checkCancellation()
            } onCancel: { [weak self] in
                self?.cancelRecordingStart(requestID)
            }
        } catch {
            cancelRecordingStart(requestID)
            throw error
        }
    }

    func stopRecording() async throws -> VideoNoteAsset {
        guard let context = contextLock.withLock({ () -> RecordingContext? in
            guard let currentContext = recordingContext,
                  !currentContext.stopRequested
            else { return nil }
            currentContext.stopRequested = true
            return currentContext
        }) else { throw VideoNoteCaptureError.recordingUnavailable }
        return try await finishRecording(context)
    }

    private func finishRecording(_ context: RecordingContext) async throws -> VideoNoteAsset {
        let ownsRecording = contextLock.withLock { () -> Bool in
            guard recordingContext === context else { return false }
            enqueueStateLocked(.stopping)
            return true
        }
        guard ownsRecording else { throw VideoNoteCaptureError.recordingUnavailable }

        videoOutputQueue.async { [weak self, writer = context.writer] in
            self?.contextLock.withLock {
                context.videoClosed = true
            }
            writer.markVideoFinished()
        }
        audioOutputQueue.async { [weak self, writer = context.writer] in
            self?.contextLock.withLock {
                context.audioClosed = true
            }
            writer.markAudioFinished()
        }
        do {
            let asset = try await withTaskCancellationHandler {
                try await context.writer.finish()
            } onCancel: { [weak self] in
                self?.cancelFinishingContext(context)
            }
            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: asset.url)
                clearRecordingContextIfOwned(context)
                throw CancellationError()
            }
            guard clearRecordingContextIfOwned(context) else {
                try? FileManager.default.removeItem(at: asset.url)
                throw CancellationError()
            }
            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: asset.url)
                throw CancellationError()
            }
            return asset
        } catch {
            clearRecordingContextIfOwned(context)
            throw error
        }
    }

    func cancelRecording() {
        let context = contextLock.withLock { () -> RecordingContext? in
            pendingRecordingStart = nil
            let context = recordingContext
            recordingContext = nil
            enqueueStateLocked(captureEnabled ? .ready(position) : .idle)
            return context
        }
        context?.writer.cancel()
    }

    private func clearPendingRecordingStart(_ requestID: UUID) {
        contextLock.withLock {
            if pendingRecordingStart == requestID {
                pendingRecordingStart = nil
            }
        }
    }

    private func cancelRecordingStart(_ requestID: UUID) {
        let writer = contextLock.withLock { () -> VideoNoteAssetWriter? in
            if pendingRecordingStart == requestID {
                pendingRecordingStart = nil
            }
            guard let context = recordingContext,
                  context.startRequestID == requestID
            else { return nil }
            recordingContext = nil
            enqueueStateLocked(captureEnabled ? .ready(position) : .idle)
            return context.writer
        }
        writer?.cancel()
    }

    private func cancelFinishingContext(_ context: RecordingContext) {
        contextLock.withLock {
            guard recordingContext === context else { return }
            recordingContext = nil
            enqueueStateLocked(captureEnabled ? .ready(position) : .idle)
        }
        context.writer.cancel()
    }

    func switchCamera() async throws -> Position {
        return try await withCheckedThrowingContinuation { continuation in
            configurationQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                do {
                    let switchContext = try self.contextLock.withLock {
                        () throws -> (Position, RecordingContext?) in
                        guard self.captureEnabled,
                              self.captureSession.isRunning
                        else { throw VideoNoteCaptureError.recordingUnavailable }
                        let context = self.recordingContext
                        context?.videoFramesEnabled = false
                        context?.audioFramesEnabled = false
                        return (self.position == .front ? .back : .front, context)
                    }
                    let targetPosition = switchContext.0
                    self.captureSession.beginConfiguration()
                    do {
                        try self.replaceVideoInput(position: targetPosition)
                        self.captureSession.commitConfiguration()
                    } catch {
                        self.captureSession.commitConfiguration()
                        self.contextLock.withLock {
                            if self.recordingContext === switchContext.1 {
                                switchContext.1?.videoFramesEnabled = true
                                switchContext.1?.audioFramesEnabled = true
                            }
                        }
                        throw error
                    }
                    self.configureOutputConnections()
                    switchContext.1?.writer.beginCameraTransition()
                    let isCurrent = self.contextLock.withLock { () -> Bool in
                        guard self.captureEnabled else { return false }
                        if let context = switchContext.1,
                           self.recordingContext === context
                        {
                            context.position = targetPosition
                            context.minimumVideoPresentationTime = CMClockGetTime(CMClockGetHostTimeClock())
                            context.awaitingFirstVideoAfterSwitch = true
                            context.videoFramesEnabled = true
                        } else if self.recordingContext == nil {
                            self.enqueueStateLocked(.ready(targetPosition))
                        }
                        return true
                    }
                    guard isCurrent else {
                        throw CancellationError()
                    }
                    continuation.resume(returning: targetPosition)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func setTorchActive(_ active: Bool) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            configurationQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                do {
                    let device = try self.contextLock.withLock { () throws -> AVCaptureDevice in
                        guard self.captureEnabled,
                              self.position == .back,
                              let device = self.videoInput?.device,
                              device.hasTorch,
                              device.isTorchModeSupported(active ? .on : .off)
                        else { throw VideoNoteCaptureError.recordingUnavailable }
                        return device
                    }
                    try device.lockForConfiguration()
                    device.torchMode = active ? .on : .off
                    device.unlockForConfiguration()
                    continuation.resume(returning: active)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func setZoomFactor(_ factor: CGFloat, rampRate: Float? = nil) {
        configurationQueue.async { [weak self] in
            guard let self else { return }
            let device = self.contextLock.withLock { () -> AVCaptureDevice? in
                guard self.captureEnabled else { return nil }
                return self.videoInput?.device
            }
            guard let device else { return }
            do {
                try device.lockForConfiguration()
                let maximum = min(device.maxAvailableVideoZoomFactor, 6)
                let boundedFactor = min(maximum, max(device.minAvailableVideoZoomFactor, factor))
                if let rampRate {
                    device.ramp(toVideoZoomFactor: boundedFactor, withRate: rampRate)
                } else {
                    device.cancelVideoZoomRamp()
                    device.videoZoomFactor = boundedFactor
                }
                device.unlockForConfiguration()
            } catch {
                return
            }
        }
    }

    func stopCapture() {
        terminateCapture(matching: nil)
    }

    private final class RecordingContext: @unchecked Sendable {
        init(
            writer: VideoNoteAssetWriter,
            position: Position,
            orientation: UIInterfaceOrientation,
            minimumPresentationTime: CMTime,
            automaticStopDuration: Double,
            startRequestID: UUID,
        ) {
            self.writer = writer
            self.position = position
            self.orientation = orientation
            self.minimumPresentationTime = minimumPresentationTime
            self.minimumVideoPresentationTime = minimumPresentationTime
            self.minimumAudioPresentationTime = minimumPresentationTime
            self.automaticStopDuration = automaticStopDuration
            self.startRequestID = startRequestID
        }

        let generation = UUID()
        let writer: VideoNoteAssetWriter
        var position: Position
        let orientation: UIInterfaceOrientation
        let minimumPresentationTime: CMTime
        var minimumVideoPresentationTime: CMTime
        var minimumAudioPresentationTime: CMTime
        let automaticStopDuration: Double
        let startRequestID: UUID
        var stopRequested = false
        var didRequestAutomaticStop = false
        var videoClosed = false
        var audioClosed = false
        var audioFramesEnabled = true
        var videoFramesEnabled = true
        var awaitingFirstVideoAfterSwitch = false
        var lastRawVideoPresentationTime: CMTime?
        var lastAdjustedVideoPresentationTime: CMTime?
        var presentationTimeOffset = CMTime.zero
        var lastPublishedDuration = Double.zero
    }

    private let configurationQueue = DispatchQueue(label: "bettertg.video-note.capture.configuration")
    private let videoOutputQueue = DispatchQueue(label: "bettertg.video-note.capture.video", qos: .userInitiated)
    private let audioOutputQueue = DispatchQueue(label: "bettertg.video-note.capture.audio", qos: .userInitiated)
    private let contextLock = NSLock()
    private let stateSubject = CurrentValueSubject<State, Never>(.idle)
    private var preparationGeneration: UUID?
    private var activeCaptureGeneration: UUID?
    private var captureEnabled = false
    private var pendingRecordingStart: UUID?
    private var recordingContext: RecordingContext?
    private var position = Position.front
    private var interfaceOrientation = UIInterfaceOrientation.portrait
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var notificationTokens = [NSObjectProtocol]()
    private var ownsAudioSession = false

    private func requestCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func isCurrentPreparation(_ generation: UUID) -> Bool {
        contextLock.lock()
        defer { contextLock.unlock() }
        return preparationGeneration == generation
    }

    private func failPreparation(_ generation: UUID, message: String) -> Bool {
        let didFail = contextLock.withLock { () -> Bool in
            guard preparationGeneration == generation else { return false }
            preparationGeneration = nil
            activeCaptureGeneration = nil
            captureEnabled = false
            enqueueStateLocked(.failed(message))
            return true
        }
        if didFail {
            configurationQueue.async { [weak self] in
                guard let self else { return }
                Self.disableTorch(on: videoInput?.device)
                if captureSession.isRunning {
                    captureSession.stopRunning()
                }
                deactivateAudioSession()
            }
        }
        return didFail
    }

    private func configure(position: Position, generation: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            configurationQueue.async { [weak self] in
                guard let self, self.isCurrentPreparation(generation) else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                do {
                    try self.activateAudioSession()
                    self.captureSession.beginConfiguration()
                    do {
                        self.captureSession.sessionPreset = .high
                        try self.replaceVideoInput(position: position)
                        if self.audioInput == nil {
                            guard let microphone = AVCaptureDevice.default(for: .audio) else {
                                throw VideoNoteCaptureError.configurationFailed
                            }
                            let input = try AVCaptureDeviceInput(device: microphone)
                            guard self.captureSession.canAddInput(input) else {
                                throw VideoNoteCaptureError.configurationFailed
                            }
                            self.captureSession.addInput(input)
                            self.audioInput = input
                        }
                        if !self.captureSession.outputs.contains(self.videoOutput) {
                            self.videoOutput.alwaysDiscardsLateVideoFrames = true
                            self.videoOutput.videoSettings = [
                                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                            ]
                            guard self.captureSession.canAddOutput(self.videoOutput) else {
                                throw VideoNoteCaptureError.configurationFailed
                            }
                            self.captureSession.addOutput(self.videoOutput)
                            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoOutputQueue)
                        }
                        if !self.captureSession.outputs.contains(self.audioOutput) {
                            guard self.captureSession.canAddOutput(self.audioOutput) else {
                                throw VideoNoteCaptureError.configurationFailed
                            }
                            self.captureSession.addOutput(self.audioOutput)
                            self.audioOutput.setSampleBufferDelegate(self, queue: self.audioOutputQueue)
                        }
                        self.captureSession.commitConfiguration()
                    } catch {
                        self.captureSession.commitConfiguration()
                        throw error
                    }
                    self.configureOutputConnections()
                    guard self.isCurrentPreparation(generation) else {
                        throw CancellationError()
                    }
                    if !self.captureSession.isRunning {
                        self.captureSession.startRunning()
                    }
                    let shouldEnable = self.contextLock.withLock { () -> Bool in
                        guard self.preparationGeneration == generation else { return false }
                        self.captureEnabled = true
                        self.preparationGeneration = nil
                        self.activeCaptureGeneration = generation
                        self.enqueueStateLocked(.ready(position))
                        return true
                    }
                    guard shouldEnable else {
                        throw CancellationError()
                    }
                    continuation.resume()
                } catch {
                    let ownsPreparation = self.contextLock.withLock { () -> Bool in
                        guard self.preparationGeneration == generation else { return false }
                        self.captureEnabled = false
                        self.preparationGeneration = nil
                        self.activeCaptureGeneration = nil
                        self.enqueueStateLocked(.failed("Couldn’t start the video-note camera."))
                        return true
                    }
                    if ownsPreparation {
                        Self.disableTorch(on: self.videoInput?.device)
                        if self.captureSession.isRunning {
                            self.captureSession.stopRunning()
                        }
                        self.deactivateAudioSession()
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func replaceVideoInput(position: Position) throws {
        guard let camera = cameraDevice(position: position) else {
            throw VideoNoteCaptureError.cameraUnavailable
        }
        let newInput = try AVCaptureDeviceInput(device: camera)
        let previousInput = videoInput
        if let previousInput {
            captureSession.removeInput(previousInput)
        }
        guard captureSession.canAddInput(newInput) else {
            if let previousInput, captureSession.canAddInput(previousInput) {
                captureSession.addInput(previousInput)
            }
            throw VideoNoteCaptureError.configurationFailed
        }
        captureSession.addInput(newInput)
        videoInput = newInput
        contextLock.lock()
        self.position = position
        contextLock.unlock()
        configureOutputConnections()
    }

    private func cameraDevice(position: Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position.capturePosition,
        )
        return discovery.devices.first
    }

    private func configureOutputConnections() {
        if let connection = videoOutput.connection(with: .video) {
            connection.automaticallyAdjustsVideoMirroring = false
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }
        }
    }

    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setActive(false)
        try session.setCategory(.playAndRecord, mode: .videoRecording, policy: .default, options: [
            .allowBluetoothHFP,
            .allowBluetoothA2DP,
        ])
        try session.setActive(true)
        contextLock.withLock {
            ownsAudioSession = true
        }
    }

    private func deactivateAudioSession() {
        let shouldDeactivate = contextLock.withLock { () -> Bool in
            guard ownsAudioSession else { return false }
            ownsAudioSession = false
            return true
        }
        guard shouldDeactivate else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    @discardableResult
    private func clearRecordingContextIfOwned(_ context: RecordingContext) -> Bool {
        contextLock.withLock {
            guard recordingContext === context else { return false }
            recordingContext = nil
            if captureEnabled {
                enqueueStateLocked(.ready(position))
            }
            return true
        }
    }

    private func terminateCapture(matching generation: UUID?) {
        let result = contextLock.withLock { () -> (Bool, RecordingContext?) in
            if let generation,
               preparationGeneration != generation,
               activeCaptureGeneration != generation
            {
                return (false, nil)
            }
            preparationGeneration = nil
            activeCaptureGeneration = nil
            captureEnabled = false
            pendingRecordingStart = nil
            let context = recordingContext
            recordingContext = nil
            enqueueStateLocked(.idle)
            return (true, context)
        }
        guard result.0 else { return }
        result.1?.writer.cancel()
        configurationQueue.async { [weak self] in
            guard let self else { return }
            Self.disableTorch(on: videoInput?.device)
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
            deactivateAudioSession()
        }
    }

    private func enqueueStateLocked(_ state: State) {
        DispatchQueue.main.async { [stateSubject] in
            stateSubject.send(state)
        }
    }

    private static func disableTorch(on device: AVCaptureDevice?) {
        guard let device, device.hasTorch, device.torchMode != .off else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
        } catch {
            return
        }
    }

    private func observeSessionLifecycle() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: captureSession,
            queue: nil,
        ) { [weak self] _ in
            self?.handleCaptureFailure("Video-note capture was interrupted.")
        })
        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: captureSession,
            queue: nil,
        ) { [weak self] _ in
            self?.handleCaptureFailure("Video-note capture stopped unexpectedly.")
        })
        notificationTokens.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil,
        ) { [weak self] _ in
            self?.handleCaptureFailure("Video-note capture stopped in the background.")
        })
    }

    private func handleCaptureFailure(_ message: String) {
        let result = contextLock.withLock { () -> (Bool, RecordingContext?) in
            guard captureEnabled || recordingContext != nil || preparationGeneration != nil else {
                return (false, nil)
            }
            captureEnabled = false
            preparationGeneration = nil
            activeCaptureGeneration = nil
            pendingRecordingStart = nil
            let context = recordingContext
            recordingContext = nil
            enqueueStateLocked(.failed(message))
            return (true, context)
        }
        guard result.0 else { return }
        result.1?.writer.cancel()
        configurationQueue.async { [weak self] in
            guard let self else { return }
            Self.disableTorch(on: videoInput?.device)
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
            deactivateAudioSession()
        }
    }

    private func handleRecordingFailure(_ message: String, context: RecordingContext) {
        let isCurrent = contextLock.withLock { () -> Bool in
            guard recordingContext === context else { return false }
            captureEnabled = false
            activeCaptureGeneration = nil
            pendingRecordingStart = nil
            recordingContext = nil
            enqueueStateLocked(.failed(message))
            return true
        }
        context.writer.cancel()
        guard isCurrent else { return }
        configurationQueue.async { [weak self] in
            guard let self else { return }
            Self.disableTorch(on: videoInput?.device)
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
            deactivateAudioSession()
        }
    }
}

extension VideoNoteCaptureSession: AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate
{
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection,
    ) {
        guard output === videoOutput || output === audioOutput else { return }
        let rawPresentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        contextLock.lock()
        guard let context = recordingContext,
              (output === videoOutput
                  ? !context.videoClosed && context.videoFramesEnabled
                  : !context.audioClosed && context.audioFramesEnabled),
              rawPresentationTime >= context.minimumPresentationTime,
              (output === videoOutput
                  ? rawPresentationTime >= context.minimumVideoPresentationTime
                  : rawPresentationTime >= context.minimumAudioPresentationTime)
        else {
            contextLock.unlock()
            return
        }
        if output === videoOutput {
            if context.awaitingFirstVideoAfterSwitch {
                context.awaitingFirstVideoAfterSwitch = false
                if let lastRawTime = context.lastRawVideoPresentationTime {
                    let gap = rawPresentationTime.seconds - lastRawTime.seconds - 1 / 30
                    if gap.isFinite, gap > 0 {
                        context.presentationTimeOffset = context.presentationTimeOffset
                            + CMTime(seconds: gap, preferredTimescale: 600)
                    }
                }
                context.minimumAudioPresentationTime = rawPresentationTime
                context.audioFramesEnabled = true
            }
            context.lastRawVideoPresentationTime = rawPresentationTime
        }
        let position = context.position
        let interfaceOrientation = context.orientation
        var adjustedPresentationTime = rawPresentationTime - context.presentationTimeOffset
        if output === videoOutput,
           let lastAdjustedTime = context.lastAdjustedVideoPresentationTime,
           adjustedPresentationTime <= lastAdjustedTime
        {
            adjustedPresentationTime = lastAdjustedTime + CMTime(value: 1, timescale: 600)
        }
        if output === videoOutput {
            context.lastAdjustedVideoPresentationTime = adjustedPresentationTime
        }
        let presentationTimeOffset = context.presentationTimeOffset
        contextLock.unlock()
        do {
            if output === videoOutput {
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                let result = try context.writer.appendVideo(
                    pixelBuffer: pixelBuffer,
                    presentationTime: adjustedPresentationTime,
                    orientation: writerOrientation(
                        position: position,
                        interfaceOrientation: interfaceOrientation,
                    ),
                )
                if result == .reachedLimit {
                    requestAutomaticStop(context)
                    return
                }
                if result == .appended {
                    publishDurationIfNeeded(context)
                }
            } else {
                let result = try context.writer.appendAudio(
                    sampleBuffer,
                    presentationTimeOffset: presentationTimeOffset,
                )
                if result == .reachedLimit {
                    requestAutomaticStop(context)
                }
            }
        } catch {
            handleRecordingFailure("Couldn’t encode the video note.", context: context)
        }
    }

    private func publishDurationIfNeeded(_ context: RecordingContext) {
        let duration = context.writer.recordedDuration
        contextLock.lock()
        guard recordingContext === context,
              !context.stopRequested
        else {
            contextLock.unlock()
            return
        }
        if duration > context.automaticStopDuration {
            contextLock.unlock()
            requestAutomaticStop(context)
            return
        }
        guard duration - context.lastPublishedDuration >= 0.1 else {
            contextLock.unlock()
            return
        }
        context.lastPublishedDuration = duration
        enqueueStateLocked(.recording(duration))
        contextLock.unlock()
    }

    private func requestAutomaticStop(_ context: RecordingContext) {
        contextLock.lock()
        guard recordingContext === context,
              !context.didRequestAutomaticStop,
              !context.stopRequested
        else {
            contextLock.unlock()
            return
        }
        context.didRequestAutomaticStop = true
        context.stopRequested = true
        contextLock.unlock()
        Task { [weak self] in
            guard let self else { return }
            do {
                let asset = try await finishRecording(context)
                DispatchQueue.main.async { [weak self] in self?.onAutomaticStop?(.success(asset)) }
            } catch {
                if isExpectedAutomaticStopCancellation(error) {
                    return
                }
                DispatchQueue.main.async { [weak self] in self?.onAutomaticStop?(.failure(error)) }
            }
        }
    }

    private func isExpectedAutomaticStopCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let captureError = error as? VideoNoteCaptureError,
           case .recordingUnavailable = captureError
        {
            return true
        }
        if let writerError = error as? VideoNoteAssetWriterError,
           case .cancelled = writerError
        {
            return true
        }
        return false
    }

    private func writerOrientation(
        position: Position,
        interfaceOrientation: UIInterfaceOrientation,
    ) -> CGImagePropertyOrientation {
        switch (position, interfaceOrientation) {
        case (.back, .portrait): .right
        case (.front, .portrait): .leftMirrored
        case (.back, .portraitUpsideDown): .left
        case (.front, .portraitUpsideDown): .rightMirrored
        case (.back, .landscapeLeft): .down
        case (.front, .landscapeLeft): .upMirrored
        case (.back, .landscapeRight): .up
        case (.front, .landscapeRight): .downMirrored
        case (.back, .unknown): .right
        case (.front, .unknown): .leftMirrored
        @unknown default:
            position == .front ? .leftMirrored : .right
        }
    }
}

final class VideoNoteCameraPreviewView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityLabel = "Video note camera preview"
        previewLayer.videoGravity = .resizeAspectFill
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            preconditionFailure("VideoNoteCameraPreviewView requires AVCaptureVideoPreviewLayer")
        }
        return layer
    }

    func attach(
        session: AVCaptureSession,
        position: VideoNoteCaptureSession.Position,
        orientation: UIInterfaceOrientation = .portrait,
    ) {
        previewLayer.session = session
        updateConnection(position: position, orientation: orientation)
    }

    func updateConnection(
        position: VideoNoteCaptureSession.Position,
        orientation: UIInterfaceOrientation,
    ) {
        guard let connection = previewLayer.connection else { return }
        let angle: CGFloat = switch orientation {
        case .portrait: 90
        case .portraitUpsideDown: 270
        case .landscapeLeft: 180
        case .landscapeRight: 0
        case .unknown: 90
        @unknown default: 90
        }
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        connection.automaticallyAdjustsVideoMirroring = false
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = position == .front
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }
}
