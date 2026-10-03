// TDLibVODPartialCoverageProbe.swift

#if DEBUG
    import AVFoundation
    import Combine
    import CryptoKit
    import UIKit

    /// Exercises the real range source, FFmpeg decoder and sample-buffer player.
    /// Only TDLib transport/availability is injected; this is not a server proof.
    enum TDLibVODPartialCoverageProbe {
        private struct ProbeError: Error, CustomStringConvertible {
            let description: String
        }

        private struct Fixture {
            let size: Int64
            let checksum: String
        }

        @MainActor static func run(in window: UIWindow) async {
            let resultURL = FileManager.default
.urls(for: .documentDirectory, in: .userDomainMask)
                .first!.appendingPathComponent("vod-partial-coverage-probe.txt")
            let fixtureURL = FileManager.default
.temporaryDirectory
                .appendingPathComponent("vod-partial-coverage-\(UUID().uuidString).mp4")
            func record(_ text: String) {
                try? "\(Date()): \(text)\n".write(to: resultURL, atomically: true, encoding: .utf8)
            }
            record("START generating native H264 MP4")
            defer { try? FileManager.default.removeItem(at: fixtureURL) }
            var activePlayer: TDLibVODFFmpegSampleBufferPlayer?
            var checkpoints = [String]()
            var observedStates = [String]()
            var observedFailure = "none"
            var observations = Set<AnyCancellable>()
            do {
                let fixture = try await Task.detached(priority: .utility) {
                    try await makeFixture(at: fixtureURL)
                }.value
                guard fixture.size > 4 * TDLibVODRangeSource.normalFetchSize else {
                    throw ProbeError(description: "Fixture too small: \(fixture.size)")
                }
                let ceiling = fixture.size / 2
                checkpoints
                    .append("H264 video-only 480x270/15fps/24s, bytes=\(fixture.size), sha256=\(fixture.checksum)")
                record(checkpoints.joined(separator: "; "))
                let backend = TDLibVODProbeBackend(
                    fileURL: fixtureURL, fileSize: fixture.size,
                    network: TDLibVODProbeNetwork(available: true),
                )
                await backend.setAutoFulfill(true)
                await backend.setAutomaticDownloadCeiling(ceiling)
                await backend.setDownloadDelay(.milliseconds(80))
                let coordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-vod-partial-coverage", client: backend.client,
                    requestTimeout: .seconds(4),
                )
                let lease = await coordinator.acquire(file: backend.file(expectedSize: fixture.size))
                let player = TDLibVODFFmpegSampleBufferPlayer(lease: lease)
                activePlayer = player
                player.statePublisher.sink { observedStates.append(String(describing: $0)) }.store(in: &observations)
                player.failurePublisher
.sink { if let failure = $0 { observedFailure = String(describing: failure) } }
                    .store(in: &observations)
                player.surfaceView.frame = CGRect(x: 8, y: window.safeAreaInsets.top + 8, width: 240, height: 135)
                player.surfaceView.isUserInteractionEnabled = false
                window.addSubview(player.surfaceView)
                player.setMuted(true)
                player.setPlaybackVisible(true)
                player.prepare(autoplay: true)
                try await waitUntil("initial playback", player: player) {
                    player.state == .playing && player.currentTime > 0.3 && player.isReadyForDisplay
                }
                player.pause()
                let initialTime = player.currentTime
                let initialCoverage = await backend.cachedByteCount
                let initialFile = await backend.file(expectedSize: fixture.size)
                guard initialCoverage > 0, initialCoverage <= ceiling,
                      !initialFile.local.isDownloadingCompleted, initialTime < 12,
                      abs(player.duration - 24) < 0.1
                else { throw ProbeError(description: "Initial coverage/time/duration invariant failed") }
                checkpoints
                    .append(
                        "early-play=\(initialTime)s, cached=\(initialCoverage)/\(fixture.size), tail-unavailable=true, complete=false",
                    )
                record(checkpoints.joined(separator: "; "))

                let initialCalls = await backend.downloadCalls.count
                var seekCompleted = false
                player.seek(to: 18) { seekCompleted = true }
                player.play()
                try await waitUntil("missing tail request", player: player) {
                    await backend.downloadCalls.dropFirst(initialCalls).contains { $0.range.lowerBound >= ceiling }
                }
                try await waitUntil("tail buffering", player: player) { player.state == .buffering }
                let blockedTime = player.currentTime
                try await Task<Never, Never>.sleep(for: .milliseconds(400))
                guard !seekCompleted, player.state == .buffering,
                      abs(player.currentTime - blockedTime) < 0.1,
                      await backend.cachedByteCount <= ceiling,
                      let requestedTail = await backend.downloadCalls.last,
                      requestedTail.range.lowerBound >= ceiling
                else { throw ProbeError(description: "Unavailable tail did not hold the seek") }
                checkpoints
                    .append("seek18=buffering, unavailable-range=\(requestedTail.range), completion-withheld=true")
                record(checkpoints.joined(separator: "; "))

                player.pause()
                try await Task<Never, Never>.sleep(for: .milliseconds(400))
                guard player.state == .paused, !seekCompleted else {
                    throw ProbeError(description: "Metadata wait ignored pause")
                }
                player.play()
                try await waitUntil("buffering after paused metadata wait", player: player) {
                    player.state == .buffering
                }
                player.setPlaybackVisible(false)
                try await Task<Never, Never>.sleep(for: .milliseconds(400))
                guard player.state == .paused, !seekCompleted else {
                    throw ProbeError(description: "Metadata wait ignored offscreen suspension")
                }
                let callsBeforeVisibility = await backend.downloadCalls.count
                player.setPlaybackVisible(true)
                try await waitUntil("visible metadata wait", player: player) {
                    let calls = await backend.downloadCalls
                    return player.state == .buffering && calls.count > callsBeforeVisibility
                        && calls.last.map { $0.range.lowerBound >= ceiling } == true
                }
                guard let resumedTail = await backend.downloadCalls.last else {
                    throw ProbeError(description: "Missing resumed tail request")
                }
                checkpoints.append("metadata-wait pause/resume+offscreen=true")

                await backend.setAutomaticDownloadCeiling(nil)
                await backend.addCached(resumedTail.range)
                await lease.source.update(file: backend.file(expectedSize: fixture.size), sequence: 1)
                try await waitUntil("seek playback after updateFile", player: player) {
                    seekCompleted && player.state == .playing && player.currentTime > 18.2 && player.isReadyForDisplay
                }
                player.pause()
                let resumedTime = player.currentTime
                let resumedCoverage = await backend.cachedByteCount
                let resumedFile = await backend.file(expectedSize: fixture.size)
                let calls = await backend.downloadCalls
                guard resumedCoverage < fixture.size, !resumedFile.local.isDownloadingCompleted,
                      calls.allSatisfy({ !$0.isFullDownload && !$0.range.isEmpty
                          && $0.range.lowerBound >= 0 && $0.range.upperBound <= fixture.size })
                else {
                    throw ProbeError(
                        description: "Seek coverage=\(resumedCoverage)/\(fixture.size), complete=\(resumedFile.local.isDownloadingCompleted), calls=\(calls)",
                    )
                }
                checkpoints
                    .append(
                        "seek-resumed=\(resumedTime)s, cached=\(resumedCoverage)/\(fixture.size), complete=false, finite-requests=\(calls.count)",
                    )
                await player.close()
                player.surfaceView.removeFromSuperview()
                activePlayer = nil
                try await waitUntil("transport cleanup", player: nil) {
                    let active = await backend.activeDownloadCount
                    let cancelled = await backend.cancelCount
                    let completed = await backend.completedCancelCount
                    return active == 0 && cancelled > 0 && cancelled == completed
                }
                checkpoints
                    .append(
                        "cleanup=true; reveal+updateFile recovery, not update-only causality; injected availability, no live TDLib/server/audio/PiP proof",
                    )
                record("PASS " + checkpoints.joined(separator: "; "))
            } catch {
                if let activePlayer {
                    await activePlayer.close()
                    activePlayer.surfaceView.removeFromSuperview()
                }
                record("FAIL \(error); failure=\(observedFailure); states=\(observedStates); " + checkpoints
                    .joined(separator: "; "))
            }
        }

        @MainActor private static func waitUntil(
            _ stage: String, player: TDLibVODFFmpegSampleBufferPlayer?,
            condition: () async -> Bool,
        ) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            while await !condition() {
                guard ContinuousClock.now < deadline, player?.state != .failed else {
                    throw ProbeError(
                        description: "\(stage): state=\(String(describing: player?.state)), time=\(player?.currentTime ?? -1)",
                    )
                }
                try await Task<Never, Never>.sleep(for: .milliseconds(40))
            }
        }

        /// Generate actual independently decodable media, not padding around a small fixture.
        /// One pixel buffer at a time; all frame filling, encoding and hashing stays off main.
        private static func makeFixture(at url: URL) async throws -> Fixture {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            writer.shouldOptimizeForNetworkUse = true
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 480, AVVideoHeightKey: 270,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 4_000_000,
                    AVVideoExpectedSourceFrameRateKey: 15,
                    AVVideoMaxKeyFrameIntervalKey: 15,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                ],
            ])
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 480,
                kCVPixelBufferHeightKey as String: 270,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ])
            guard writer.canAdd(input) else { throw ProbeError(description: "Cannot add video writer input") }
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? ProbeError(description: "Cannot start writer") }
            var completed = false
            defer { if !completed { writer.cancelWriting() } }
            writer.startSession(atSourceTime: .zero)
            let deadline = ContinuousClock.now.advanced(by: .seconds(60))
            var random = UInt32(0xA044_2026)
            for index in 0..<360 {
                guard ContinuousClock.now < deadline
                    else { throw ProbeError(description: "Fixture generation timed out") }
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing, ContinuousClock.now < deadline else {
                        throw writer.error ?? ProbeError(description: "Writer timed out")
                    }
                    try await Task<Never, Never>.sleep(for: .milliseconds(5))
                }
                try Task.checkCancellation()
                try autoreleasepool {
                    guard let pool = adaptor.pixelBufferPool
                        else { throw ProbeError(description: "Missing pixel buffer pool") }
                    var buffer: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                          let buffer else { throw ProbeError(description: "Pixel allocation failed") }
                    guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else {
                        throw ProbeError(description: "Pixel lock failed")
                    }
                    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                    guard let base = CVPixelBufferGetBaseAddress(buffer)
                        else { throw ProbeError(description: "Missing pixel storage") }
                    let stride = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<UInt32>.stride
                    let pixels = base.assumingMemoryBound(to: UInt32.self)
                    for y in 0..<270 {
                        for x in 0..<480 {
                            random = random &* 1_664_525 &+ 1_013_904_223
                            pixels[y * stride + x] = 0xFF00_0000 | (random >> 8)
                        }
                    }
                    guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 15))
                        else {
                        throw writer.error ?? ProbeError(description: "Video append failed")
                    }
                }
            }
            writer.endSession(atSourceTime: CMTime(value: 24, timescale: 1))
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed
                else { throw writer.error ?? ProbeError(description: "Writer finish failed") }
            completed = true
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            return Fixture(
                size: Int64(data.count),
                checksum: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            )
        }
    }
#endif
