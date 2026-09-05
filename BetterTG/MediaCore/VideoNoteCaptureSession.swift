// VideoNoteCaptureSession.swift

import AVFoundation
import Combine
import ImageIO
import UIKit

// MARK: - VideoNoteCaptureError

enum VideoNoteCaptureError: Swift.Error {
    case cameraUnavailable
    case configurationFailed
    case permissionDenied
    case recordingUnavailable
}

#if DEBUG
    extension VideoNoteCaptureSession {
        func installPreservationProbe(
            output: URL,
            generation: UUID,
            beforeFinish: (@Sendable () async -> Void)? = nil,
            beforeDelivery: (@Sendable () async -> Void)? = nil,
        ) async throws {
            _ = try await installDebugRecording(output: output, generation: generation)
            contextLock.withLock { stateGeneration = generation }
            probeBeforeFinish = beforeFinish
            probeBeforeAutomaticDelivery = beforeDelivery
        }

        func requestAutomaticPreservationProbe() -> Task<Void, Never>? {
            guard let context = contextLock.withLock({ recordingContext }) else { return nil }
            return requestAutomaticStop(context)
        }

        func terminatePreservationProbe() {
            handleCaptureFailure("Probe lifecycle interruption")
        }

        func interruptPreservationProbe() {
            handleCaptureInterruption()
        }

        func publishPreservationProbeState(_ state: State) {
            contextLock.withLock { enqueueStateLocked(state, generation: stateGeneration) }
        }

        func verifyStalePreservationStop(generation: UUID) throws {
            let rejected = !stopInputPreservingRecording(generation: UUID())
            let unchanged = contextLock.withLock {
                recordingContext?.captureGeneration == generation
                    && recordingContext?.videoFramesEnabled == true
                    && recordingContext?.audioFramesEnabled == true
            }
            try VideoNotePreservationProbe.require(rejected && unchanged, "stale preservation stop mutated replacement")
        }

        func preservationProbeContext() -> String {
            contextLock.withLock {
                "active=\(String(describing: activeCaptureGeneration)); "
                    + "context=\(String(describing: recordingContext?.captureGeneration)); "
                    + "owner=\(String(describing: recordingContext?.finishOwner))"
            }
        }

        @MainActor static func verifyDebugFinishOwnership(directory: URL) async throws {
            let session = VideoNoteCaptureSession()
            let generation = UUID()
            let output = directory.appendingPathComponent("automatic.mp4")
            let adopted = directory.appendingPathComponent("adopted.mp4")
            let context = try await session.installDebugRecording(output: output, generation: generation)
            let finishGate = VideoNoteFinishProbe.Gate()
            let deliveryGate = VideoNoteFinishProbe.Gate()
            session.probeBeforeFinish = { await finishGate.wait() }
            session.probeBeforeAutomaticDelivery = { await deliveryGate.wait() }
            var callbackCount = 0
            var callbackError: Error?
            session.onAutomaticStop = { deliveredGeneration, result in
                callbackCount += 1
                do {
                    try VideoNoteFinishProbe.require(deliveredGeneration == generation, "wrong capture generation")
                    let asset = try result.get()
                    try FileManager.default.moveItem(at: asset.url, to: adopted)
                } catch { callbackError = error }
            }
            guard let automatic = session.requestAutomaticStop(context) else {
                throw VideoNoteFinishProbe.Failure(description: "automatic reservation failed")
            }
            defer {
                session.cancelRecording()
                Task { await finishGate.open()
                await deliveryGate.open()
                }
            }
            await finishGate.waitUntilEntered()
            try await VideoNoteFinishProbe.require(
                session.stopRecording(generation: generation) == nil,
                "manual release took automatic reservation",
            )
            try VideoNoteFinishProbe.require(session.requestAutomaticStop(context) == nil, "duplicate auto owner")
            await finishGate.open()
            await deliveryGate.waitUntilEntered()
            try VideoNoteFinishProbe.require(
                FileManager.default.fileExists(atPath: output.path),
                "writer output missing",
            )
            try VideoNoteFinishProbe.require(callbackCount == 0, "callback bypassed delivery gate")
            for _ in 0..<2 {
                try await VideoNoteFinishProbe.require(
                    session.stopRecording(generation: generation) == nil,
                    "writer-done manual release took automatic output",
                )
            }
            await deliveryGate.open()
            await automatic.value
            if let callbackError { throw callbackError }
            try VideoNoteFinishProbe.require(callbackCount == 1, "automatic output not delivered exactly once")
            _ = try await VideoNoteAssetWriter.validate(url: adopted, expectedLength: 400)
            session.cancelRecording()
            try VideoNoteFinishProbe.require(session.requestAutomaticStop(context) == nil, "delivered context revived")
            try VideoNoteFinishProbe.require(
                FileManager.default.fileExists(atPath: adopted.path),
                "adopted asset removed",
            )

            // Cancel while the automatic owner has reserved, before native finish starts.
            let cancelledOutput = directory.appendingPathComponent("cancelled-before-finish.mp4")
            let cancelled = try await session.installDebugRecording(output: cancelledOutput, generation: UUID())
            let cancellationGate = VideoNoteFinishProbe.Gate()
            session.probeBeforeFinish = { await cancellationGate.wait() }
            session.probeBeforeAutomaticDelivery = nil
            guard let cancelledTask = session.requestAutomaticStop(cancelled) else {
                throw VideoNoteFinishProbe.Failure(description: "cancel fixture reservation failed")
            }
            await cancellationGate.waitUntilEntered()
            session.cancelRecording()
            await cancellationGate.open()
            await cancelledTask.value
            try VideoNoteFinishProbe.require(callbackCount == 1, "cancelled finish called receiver")
            try VideoNoteFinishProbe.require(
                !FileManager.default.fileExists(atPath: cancelledOutput.path), "cancelled writer output retained",
            )

            // Cancel after writer completion but before delivery, then start another capture.
            let obsoleteOutput = directory.appendingPathComponent("obsolete.mp4")
            let obsoleteGeneration = UUID()
            let obsolete = try await session.installDebugRecording(
                output: obsoleteOutput,
                generation: obsoleteGeneration,
            )
            let obsoleteDelivery = VideoNoteFinishProbe.Gate()
            session.probeBeforeFinish = nil
            session.probeBeforeAutomaticDelivery = { await obsoleteDelivery.wait() }
            guard let obsoleteTask = session.requestAutomaticStop(obsolete) else {
                throw VideoNoteFinishProbe.Failure(description: "obsolete fixture reservation failed")
            }
            await obsoleteDelivery.waitUntilEntered()
            session.cancelRecording()
            let replacementGeneration = UUID()
            let replacementOutput = directory.appendingPathComponent("replacement.mp4")
            let replacement = try await session.installDebugRecording(
                output: replacementOutput, generation: replacementGeneration,
            )
            do {
                _ = try await session.stopRecording(generation: obsoleteGeneration)
                throw VideoNoteFinishProbe.Failure(description: "stale manual stop reserved new capture")
            } catch is CancellationError {}
            await obsoleteDelivery.open()
            await obsoleteTask.value
            try VideoNoteFinishProbe.require(callbackCount == 1, "obsolete result delivered to replacement")
            try VideoNoteFinishProbe.require(
                !FileManager.default.fileExists(atPath: obsoleteOutput.path),
                "obsolete output retained",
            )
            try VideoNoteFinishProbe.require(
                session.contextLock.withLock { session.recordingContext === replacement },
                "replacement context cleared",
            )
            let manualGate = VideoNoteFinishProbe.Gate()
            session.probeBeforeFinish = { await manualGate.wait() }
            let manual = Task { try await session.stopRecording(generation: replacementGeneration) }
            await manualGate.waitUntilEntered()
            try await VideoNoteFinishProbe.require(
                session.stopRecording(generation: replacementGeneration) == nil, "duplicate manual owner",
            )
            try VideoNoteFinishProbe.require(
                session.requestAutomaticStop(replacement) == nil,
                "auto replaced manual owner",
            )
            await manualGate.open()
            guard let manualAsset = try await manual.value else {
                throw VideoNoteFinishProbe.Failure(description: "manual owner lost asset")
            }
            _ = try await VideoNoteAssetWriter.validate(url: manualAsset.url, expectedLength: 400)
            session.cancelRecording()
            try VideoNoteFinishProbe.require(
                FileManager.default.fileExists(atPath: manualAsset.url.path),
                "manual-owned asset removed",
            )

            let orphanOutput = directory.appendingPathComponent("no-callback.mp4")
            let orphan = try await session.installDebugRecording(output: orphanOutput, generation: UUID())
            session.probeBeforeFinish = nil
            session.probeBeforeAutomaticDelivery = nil
            session.onAutomaticStop = nil
            await session.requestAutomaticStop(orphan)?.value
            try VideoNoteFinishProbe.require(
                !FileManager.default.fileExists(atPath: orphanOutput.path),
                "orphan output retained",
            )
            try VideoNoteFinishProbe.require(
                FileManager.default.fileExists(atPath: adopted.path),
                "later cleanup removed adopted output",
            )

            let taskCancelledOutput = directory.appendingPathComponent("caller-cancelled.mp4")
            let taskCancelledGeneration = UUID()
            _ = try await session.installDebugRecording(
                output: taskCancelledOutput,
                generation: taskCancelledGeneration,
            )
            let taskCancellationGate = VideoNoteFinishProbe.Gate()
            session.probeBeforeFinish = { await taskCancellationGate.wait() }
            let cancelledManual = Task { try await session.stopRecording(generation: taskCancelledGeneration) }
            await taskCancellationGate.waitUntilEntered()
            cancelledManual.cancel()
            await taskCancellationGate.open()
            do {
                _ = try await cancelledManual.value
                throw VideoNoteFinishProbe.Failure(description: "cancelled caller received an asset")
            } catch is CancellationError {
            } catch VideoNoteAssetWriterError.cancelled {}
            try VideoNoteFinishProbe.require(
                session.contextLock.withLock { session.recordingContext == nil }, "cancelled caller retained context",
            )
            try VideoNoteFinishProbe.require(
                !FileManager.default.fileExists(atPath: taskCancelledOutput.path), "caller-cancelled output retained",
            )

            let failedOutput = directory.appendingPathComponent("writer-failed.mp4")
            let failedGeneration = UUID()
            let failed = try await session.installDebugRecording(
                output: failedOutput, generation: failedGeneration, appendSamples: false,
            )
            let failureGate = VideoNoteFinishProbe.Gate()
            session.probeBeforeFinish = nil
            session.probeBeforeAutomaticDelivery = { await failureGate.wait() }
            var failureCount = 0
            session.onAutomaticStop = { deliveredGeneration, result in
                if deliveredGeneration == failedGeneration,
                   case .failure(VideoNoteAssetWriterError.invalidAsset) = result
                { failureCount += 1 }
            }
            guard let failedTask = session.requestAutomaticStop(failed) else {
                throw VideoNoteFinishProbe.Failure(description: "failure fixture reservation failed")
            }
            await failureGate.waitUntilEntered()
            try await VideoNoteFinishProbe.require(
                session.stopRecording(generation: failedGeneration) == nil, "manual stop replaced queued failure owner",
            )
            await failureGate.open()
            await failedTask.value
            try VideoNoteFinishProbe.require(failureCount == 1, "native writer failure not delivered exactly once")
            try VideoNoteFinishProbe.require(
                session.contextLock.withLock { session.recordingContext == nil }, "failed writer retained context",
            )
            try VideoNoteFinishProbe.require(
                !FileManager.default.fileExists(atPath: failedOutput.path), "failed writer output retained",
            )
        }

        private func installDebugRecording(
            output: URL, generation: UUID, appendSamples: Bool = true,
        ) async throws -> RecordingContext {
            let writer: VideoNoteAssetWriter =
 if appendSamples {
                try await VideoNoteAssetWriter.makeDebugRecording(
                    outputURL: output, duration: 0.6, frameSeed: 9,
                )
            } else {
                try VideoNoteAssetWriter(outputURL: output)
            }
            let context = RecordingContext(
                writer: writer, position: .front, orientation: .portrait, minimumPresentationTime: .zero,
                automaticStopDuration: 0.5, startRequestID: UUID(), captureGeneration: generation,
            )
            contextLock.withLock {
                activeCaptureGeneration = generation
                recordingContext = context
            }
            return context
        }
    }
#endif

// MARK: - VideoNoteCaptureSession

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

    struct StateUpdate: Equatable {
        let generation: UUID?
        let state: State
    }

    private final class RecordingContext: @unchecked Sendable {
        enum FinishOwner {
            case automatic
            case manual
        }

        let generation = UUID()
        let captureGeneration: UUID
        let writer: VideoNoteAssetWriter
        var position: Position
        let orientation: UIInterfaceOrientation
        let minimumPresentationTime: CMTime
        var minimumVideoPresentationTime: CMTime
        var minimumAudioPresentationTime: CMTime
        let automaticStopDuration: Double
        let startRequestID: UUID
        var finishOwner: FinishOwner?
        var videoClosed = false
        var audioClosed = false
        var audioFramesEnabled = true
        var videoFramesEnabled = true
        var awaitingFirstVideoAfterSwitch = false
        var lastRawVideoPresentationTime: CMTime?
        var lastAdjustedVideoPresentationTime: CMTime?
        var presentationTimeOffset = CMTime.zero
        var lastPublishedDuration = Double.zero

        var stopRequested: Bool { finishOwner != nil }

        init(
            writer: VideoNoteAssetWriter,
            position: Position,
            orientation: UIInterfaceOrientation,
            minimumPresentationTime: CMTime,
            automaticStopDuration: Double,
            startRequestID: UUID,
            captureGeneration: UUID,
        ) {
            self.writer = writer
            self.position = position
            self.orientation = orientation
            self.minimumPresentationTime = minimumPresentationTime
            self.minimumVideoPresentationTime = minimumPresentationTime
            self.minimumAudioPresentationTime = minimumPresentationTime
            self.automaticStopDuration = automaticStopDuration
            self.startRequestID = startRequestID
            self.captureGeneration = captureGeneration
        }
    }

    let captureSession = AVCaptureSession()
    @MainActor var onAutomaticStop: ((UUID, Result<VideoNoteAsset, Error>) -> Void)?
    @MainActor var onRecordingTerminated: ((UUID, Error) -> Void)?
    @MainActor var onCaptureInterruption: ((UUID) -> Void)?

    private let configurationQueue = DispatchQueue(label: "bettertg.video-note.capture.configuration")
    private let videoOutputQueue = DispatchQueue(label: "bettertg.video-note.capture.video", qos: .userInitiated)
    private let audioOutputQueue = DispatchQueue(label: "bettertg.video-note.capture.audio", qos: .userInitiated)
    private let contextLock = NSLock()
    private let stateSubject = CurrentValueSubject<StateUpdate, Never>(.init(generation: nil, state: .idle))
    private var stateGeneration: UUID?
    private var interruptedGeneration: UUID?
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
    #if DEBUG
        private var probeBeforeFinish: (@Sendable () async -> Void)?
        private var probeBeforeAutomaticDelivery: (@Sendable () async -> Void)?
    #endif

    var statePublisher: AnyPublisher<StateUpdate, Never> {
        stateSubject.removeDuplicates().eraseToAnyPublisher()
    }

    var currentPosition: Position {
        contextLock.lock()
        defer { contextLock.unlock() }
        return position
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

    func prepare(position: Position = .front, generation: UUID) async throws {
        try Task.checkCancellation()
        let displacedRecording = contextLock.withLock { () -> RecordingContext? in
            stateGeneration = generation
            preparationGeneration = generation
            activeCaptureGeneration = nil
            captureEnabled = false
            pendingRecordingStart = nil
            let context = recordingContext
            recordingContext = nil
            enqueueStateLocked(.configuring, generation: generation)
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

    func invalidatePreparation() {
        terminateCapture(matching: nil)
    }

    func updateOrientation(_ orientation: UIInterfaceOrientation) {
        contextLock.withLock {
            interfaceOrientation = orientation
        }
    }

    func startRecording(
        maximumDuration: Double = 60,
        automaticStopDuration: Double? = nil,
    ) async throws {
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
                            let normalizedAutomaticStopDuration = min(
                                normalizedMaximumDuration,
                                max(0.5, automaticStopDuration ?? min(59.5, normalizedMaximumDuration)),
                            )
                            let outputURL = FileManager.default
                                .temporaryDirectory
                                .appendingPathComponent("\(UUID().uuidString)-video-note.mp4")
                            let writer = try VideoNoteAssetWriter(
                                outputURL: outputURL,
                                length: 400,
                                maximumDuration: normalizedMaximumDuration,
                            )
                            let context = contextLock.withLock { () -> RecordingContext? in
                                guard self.pendingRecordingStart == requestID,
                                      self.captureEnabled,
                                      self.recordingContext == nil,
                                      let captureGeneration = self.activeCaptureGeneration,
                                      self.captureSession.isRunning
                                else { return nil }
                                self.pendingRecordingStart = nil
                                let context = RecordingContext(
                                    writer: writer,
                                    position: self.position,
                                    orientation: self.interfaceOrientation,
                                    minimumPresentationTime: CMClockGetTime(CMClockGetHostTimeClock()),
                                    automaticStopDuration: normalizedAutomaticStopDuration,
                                    startRequestID: requestID,
                                    captureGeneration: captureGeneration,
                                )
                                self.recordingContext = context
                                self.enqueueStateLocked(.recording(0), generation: captureGeneration)
                                return context
                            }
                            guard context != nil else {
                                writer.cancel()
                                throw CancellationError()
                            }
                            continuation.resume()
                        } catch {
                            clearPendingRecordingStart(requestID)
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

    func stopRecording(generation: UUID) async throws -> VideoNoteAsset? {
        try Task.checkCancellation()
        let context = try contextLock.withLock { () throws -> RecordingContext? in
            guard let currentContext = recordingContext else {
                throw VideoNoteCaptureError.recordingUnavailable
            }
            guard currentContext.captureGeneration == generation else { throw CancellationError() }
            guard currentContext.finishOwner == nil else { return nil }
            currentContext.finishOwner = .manual
            return currentContext
        }
        guard let context else { return nil }
        return try await finishRecording(context)
    }

    func cancelRecording() {
        let context = contextLock.withLock { () -> RecordingContext? in
            pendingRecordingStart = nil
            let context = recordingContext
            recordingContext = nil
            enqueueStateLocked(
                captureEnabled ? .ready(position) : .idle,
                generation: context?.captureGeneration ?? stateGeneration,
            )
            return context
        }
        context?.writer.cancel()
    }

    func switchCamera() async throws -> Position {
        let generation = contextLock.withLock { stateGeneration }
        return try await withCheckedThrowingContinuation { continuation in
            configurationQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                do {
                    let switchContext = try contextLock.withLock {
                        () throws -> (Position, RecordingContext?) in
                        guard self.stateGeneration == generation,
                              self.captureEnabled,
                              self.captureSession.isRunning
                        else { throw VideoNoteCaptureError.recordingUnavailable }
                        let context = self.recordingContext
                        context?.videoFramesEnabled = false
                        context?.audioFramesEnabled = false
                        return (self.position == .front ? .back : .front, context)
                    }
                    let targetPosition = switchContext.0
                    captureSession.beginConfiguration()
                    do {
                        try replaceVideoInput(position: targetPosition)
                        captureSession.commitConfiguration()
                    } catch {
                        captureSession.commitConfiguration()
                        contextLock.withLock {
                            if self.recordingContext === switchContext.1 {
                                switchContext.1?.videoFramesEnabled = true
                                switchContext.1?.audioFramesEnabled = true
                            }
                        }
                        throw error
                    }
                    configureOutputConnections()
                    switchContext.1?.writer.beginCameraTransition()
                    let isCurrent = contextLock.withLock { () -> Bool in
                        guard self.stateGeneration == generation, self.captureEnabled else { return false }
                        if let context = switchContext.1,
                           self.recordingContext === context
                        {
                            context.position = targetPosition
                            context.minimumVideoPresentationTime = CMClockGetTime(CMClockGetHostTimeClock())
                            context.awaitingFirstVideoAfterSwitch = true
                            context.videoFramesEnabled = true
                        } else if self.recordingContext == nil {
                            self.enqueueStateLocked(.ready(targetPosition), generation: generation)
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
                    let device = try contextLock.withLock { () throws -> AVCaptureDevice in
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
            let device = contextLock.withLock { () -> AVCaptureDevice? in
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

    func cancelCapture(generation: UUID) {
        terminateCapture(matching: generation)
    }

    func wasInterrupted(generation: UUID) -> Bool {
        contextLock.withLock { interruptedGeneration == generation }
    }

    /// Stops device work without cancelling a finish already owned by manual/auto stop.
    func stopInputPreservingRecording(generation: UUID) -> Bool {
        let ownership = contextLock.withLock { () -> (matched: Bool, hasRecording: Bool) in
            guard activeCaptureGeneration == generation || preparationGeneration == generation else { return (
                false,
                false,
            ) }
            preparationGeneration = nil
            pendingRecordingStart = nil
            captureEnabled = false
            recordingContext?.videoFramesEnabled = false
            recordingContext?.audioFramesEnabled = false
            return (true, recordingContext?.captureGeneration == generation)
        }
        guard ownership.matched else { return false }
        configurationQueue.async { [weak self] in
            guard let self, contextLock.withLock({ self.stateGeneration == generation }) else { return }
            Self.disableTorch(on: videoInput?.device)
            if captureSession.isRunning { captureSession.stopRunning() }
            deactivateAudioSession()
        }
        return ownership.hasRecording
    }

    func waitForCaptureShutdown() async {
        await withCheckedContinuation { continuation in
            configurationQueue.async {
                continuation.resume()
            }
        }
    }

    private func prepareIsolated(position: Position, generation: UUID) async throws {
        let microphoneGranted = await AVAudioApplication.requestRecordPermission()
        try Task.checkCancellation()
        guard isCurrentPreparation(generation) else { throw CancellationError() }
        guard microphoneGranted else {
            guard failPreparation(
                generation,
                message: "Microphone access is required for video notes.",
            ) else { throw CancellationError() }
            throw VideoNoteCaptureError.permissionDenied
        }
        let cameraGranted = await requestCameraPermission()
        try Task.checkCancellation()
        guard isCurrentPreparation(generation) else { throw CancellationError() }
        guard cameraGranted else {
            guard failPreparation(
                generation,
                message: "Camera access is required for video notes.",
            ) else { throw CancellationError() }
            throw VideoNoteCaptureError.permissionDenied
        }
        await MainActor.run { Media.shared.stop() }
        try await configure(position: position, generation: generation)
    }

    private func finishRecording(_ context: RecordingContext) async throws -> VideoNoteAsset {
        let ownsRecording = contextLock.withLock { () -> Bool in
            guard recordingContext === context else { return false }
            enqueueStateLocked(.stopping, generation: context.captureGeneration)
            return true
        }
        guard ownsRecording else { throw VideoNoteCaptureError.recordingUnavailable }

        #if DEBUG
            await probeBeforeFinish?()
        #endif

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
            let ownsResult = contextLock.withLock {
                guard recordingContext === context else { return false }
                if context.finishOwner == .manual {
                    recordingContext = nil
                    if captureEnabled { enqueueStateLocked(.ready(position), generation: context.captureGeneration) }
                }
                return true
            }
            guard ownsResult else {
                try? FileManager.default.removeItem(at: asset.url)
                throw CancellationError()
            }
            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: asset.url)
                throw CancellationError()
            }
            return asset
        } catch {
            if context.finishOwner == .manual {
                clearRecordingContextIfOwned(context)
            }
            throw error
        }
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
            enqueueStateLocked(captureEnabled ? .ready(position) : .idle, generation: context.captureGeneration)
            return context.writer
        }
        writer?.cancel()
    }

    private func cancelFinishingContext(_ context: RecordingContext) {
        contextLock.withLock {
            guard recordingContext === context else { return }
            recordingContext = nil
            enqueueStateLocked(captureEnabled ? .ready(position) : .idle, generation: context.captureGeneration)
        }
        context.writer.cancel()
    }

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
        return preparationGeneration == generation && interruptedGeneration != generation
    }

    private func failPreparation(_ generation: UUID, message: String) -> Bool {
        let didFail = contextLock.withLock { () -> Bool in
            guard preparationGeneration == generation else { return false }
            preparationGeneration = nil
            activeCaptureGeneration = nil
            captureEnabled = false
            enqueueStateLocked(.failed(message), generation: generation)
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
                guard let self, isCurrentPreparation(generation) else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                do {
                    try activateAudioSession()
                    captureSession.beginConfiguration()
                    do {
                        captureSession.sessionPreset = .high
                        try replaceVideoInput(position: position)
                        if audioInput == nil {
                            guard let microphone = AVCaptureDevice.default(for: .audio) else {
                                throw VideoNoteCaptureError.configurationFailed
                            }
                            let input = try AVCaptureDeviceInput(device: microphone)
                            guard captureSession.canAddInput(input) else {
                                throw VideoNoteCaptureError.configurationFailed
                            }
                            captureSession.addInput(input)
                            audioInput = input
                        }
                        if !captureSession.outputs.contains(videoOutput) {
                            videoOutput.alwaysDiscardsLateVideoFrames = true
                            videoOutput.videoSettings = [
                                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                            ]
                            guard captureSession.canAddOutput(videoOutput) else {
                                throw VideoNoteCaptureError.configurationFailed
                            }
                            captureSession.addOutput(videoOutput)
                            videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
                        }
                        if !captureSession.outputs.contains(audioOutput) {
                            guard captureSession.canAddOutput(audioOutput) else {
                                throw VideoNoteCaptureError.configurationFailed
                            }
                            captureSession.addOutput(audioOutput)
                            audioOutput.setSampleBufferDelegate(self, queue: audioOutputQueue)
                        }
                        captureSession.commitConfiguration()
                    } catch {
                        captureSession.commitConfiguration()
                        throw error
                    }
                    configureOutputConnections()
                    guard isCurrentPreparation(generation) else {
                        throw CancellationError()
                    }
                    if !captureSession.isRunning {
                        captureSession.startRunning()
                    }
                    let shouldEnable = contextLock.withLock { () -> Bool in
                        guard self.preparationGeneration == generation,
                              self.interruptedGeneration != generation
                        else { return false }
                        self.captureEnabled = true
                        self.preparationGeneration = nil
                        self.activeCaptureGeneration = generation
                        self.enqueueStateLocked(.ready(position), generation: generation)
                        return true
                    }
                    guard shouldEnable else {
                        throw CancellationError()
                    }
                    continuation.resume()
                } catch {
                    let ownsPreparation = contextLock.withLock { () -> Bool in
                        guard self.preparationGeneration == generation else { return false }
                        self.captureEnabled = false
                        self.preparationGeneration = nil
                        self.activeCaptureGeneration = nil
                        self.enqueueStateLocked(
                            .failed("Couldn’t start the video-note camera."),
                            generation: generation,
                        )
                        return true
                    }
                    if ownsPreparation {
                        Self.disableTorch(on: videoInput?.device)
                        if captureSession.isRunning {
                            captureSession.stopRunning()
                        }
                        deactivateAudioSession()
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

    @discardableResult private func clearRecordingContextIfOwned(_ context: RecordingContext) -> Bool {
        contextLock.withLock {
            guard recordingContext === context else { return false }
            recordingContext = nil
            if captureEnabled {
                enqueueStateLocked(.ready(position), generation: context.captureGeneration)
            }
            return true
        }
    }

    private func terminateCapture(matching generation: UUID?) {
        let result = contextLock.withLock { () -> (Bool, RecordingContext?, UUID?) in
            if let generation,
               preparationGeneration != generation,
               activeCaptureGeneration != generation
            {
                return (false, nil, nil)
            }
            preparationGeneration = nil
            activeCaptureGeneration = nil
            captureEnabled = false
            pendingRecordingStart = nil
            let context = recordingContext
            recordingContext = nil
            enqueueStateLocked(.idle, generation: generation ?? stateGeneration)
            return (true, context, stateGeneration)
        }
        guard result.0 else { return }
        result.1?.writer.cancel()
        configurationQueue.async { [weak self] in
            guard let self, contextLock.withLock({ self.stateGeneration == result.2 }) else { return }
            Self.disableTorch(on: videoInput?.device)
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
            deactivateAudioSession()
        }
    }

    private func enqueueStateLocked(_ state: State, generation: UUID?) {
        let update = StateUpdate(generation: generation, state: state)
        DispatchQueue.main.async { [stateSubject] in
            stateSubject.send(update)
        }
    }

    private func publishTermination(_ context: RecordingContext?, error: Error) {
        guard let context else { return }
        Task { @MainActor [weak self] in
            self?.onRecordingTerminated?(context.captureGeneration, error)
        }
    }

    private func observeSessionLifecycle() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: captureSession,
            queue: nil,
        ) { [weak self] _ in
            self?.handleCaptureInterruption()
        })
        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: captureSession,
            queue: nil,
        ) { [weak self] _ in
            self?.handleCaptureFailure("Video-note capture stopped unexpectedly.")
        })
    }

    private func handleCaptureInterruption() {
        let generation = contextLock.withLock { () -> UUID? in
            guard let generation = recordingContext?.captureGeneration
                ?? activeCaptureGeneration ?? preparationGeneration
            else { return nil }
            interruptedGeneration = generation
            captureEnabled = false
            pendingRecordingStart = nil
            recordingContext?.videoFramesEnabled = false
            recordingContext?.audioFramesEnabled = false
            return generation
        }
        guard let generation else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let onCaptureInterruption {
                onCaptureInterruption(generation)
            } else {
                handleCaptureFailure("Video-note capture was interrupted.")
            }
        }
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
            enqueueStateLocked(.failed(message), generation: context?.captureGeneration ?? stateGeneration)
            return (true, context)
        }
        guard result.0 else { return }
        result.1?.writer.cancel()
        publishTermination(result.1, error: CancellationError())
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
            enqueueStateLocked(.failed(message), generation: context.captureGeneration)
            return true
        }
        context.writer.cancel()
        publishTermination(context, error: VideoNoteAssetWriterError.writerFailed)
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

// MARK: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate

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
              output === videoOutput
              ? !context.videoClosed && context.videoFramesEnabled
              : !context.audioClosed && context.audioFramesEnabled,
              rawPresentationTime >= context.minimumPresentationTime,
              output === videoOutput
              ? rawPresentationTime >= context.minimumVideoPresentationTime
              : rawPresentationTime >= context.minimumAudioPresentationTime
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
        enqueueStateLocked(.recording(duration), generation: context.captureGeneration)
        contextLock.unlock()
    }

    @discardableResult private func requestAutomaticStop(_ context: RecordingContext) -> Task<Void, Never>? {
        contextLock.lock()
        guard recordingContext === context,
              context.finishOwner == nil
        else {
            contextLock.unlock()
            return nil
        }
        context.finishOwner = .automatic
        contextLock.unlock()
        return Task { [weak self] in
            guard let self else {
                context.writer.cancel()
                return
            }
            let result: Result<VideoNoteAsset, Error>
            do {
                let asset = try await finishRecording(context)
                result = .success(asset)
            } catch {
                if isExpectedAutomaticStopCancellation(error) {
                    publishTermination(context, error: error)
                    return
                }
                result = .failure(error)
            }
            #if DEBUG
                await probeBeforeAutomaticDelivery?()
            #endif
            await deliverAutomaticStop(result, context: context)
        }
    }

    @MainActor private func deliverAutomaticStop(
        _ result: Result<VideoNoteAsset, Error>,
        context: RecordingContext,
    ) {
        // Claim and callback share one MainActor turn; the callback takes sole asset ownership.
        guard clearRecordingContextIfOwned(context), let onAutomaticStop else {
            if case .success(let asset) = result {
                try? FileManager.default.removeItem(at: asset.url)
            }
            return
        }
        onAutomaticStop(context.captureGeneration, result)
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

// MARK: - VideoNoteCameraPreviewView

final class VideoNoteCameraPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            preconditionFailure("VideoNoteCameraPreviewView requires AVCaptureVideoPreviewLayer")
        }
        return layer
    }

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

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
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
        orientation _: UIInterfaceOrientation,
    ) {
        guard let connection = previewLayer.connection else { return }
        if let device = connection.inputPorts.compactMap({ ($0.input as? AVCaptureDeviceInput)?.device }).first,
           rotationCoordinator?.device !== device
        {
            rotationObservation = nil
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            rotationCoordinator = coordinator
            rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) {
                [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                DispatchQueue.main.async { self?.applyPreviewRotation(angle) }
            }
        }
        if let rotationCoordinator {
            applyPreviewRotation(rotationCoordinator.videoRotationAngleForHorizonLevelPreview)
        }
        connection.automaticallyAdjustsVideoMirroring = false
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = position == .front
        }
    }

    private func applyPreviewRotation(_ angle: CGFloat) {
        guard let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        connection.videoRotationAngle = angle
        CATransaction.commit()
    }
}
