// VideoEditProbe.swift

#if DEBUG
    import AVFoundation
    import UIKit

    /// Launch with `-ui-probe-video-edit`. Once an account is active it opens the attachment sheet's video editor on
    /// a generated six-second test video with a tone, so the trim and mute are checked without photo library access.
    /// Done shows the edit and converts the video as it would be sent, with `VideoSendTranscoder` at Medium, then
    /// shows the converted file's length, size and sound; nothing is sent.
    @MainActor enum VideoEditProbe {
        /// The edit and the converted file, closed by Close.
        private final class ResultViewController: UIViewController {
            private let label = UILabel()

            var text: String {
                get { label.text ?? "" }
                set { label.text = newValue }
            }

            init(text: String) {
                super.init(nibName: nil, bundle: nil)
                label.text = text
                modalPresentationStyle = .fullScreen
            }

            @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

            override func viewDidLoad() {
                super.viewDidLoad()
                view.backgroundColor = .black
                label.textColor = .white
                label.textAlignment = .center
                label.numberOfLines = 0
                label.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
                let close = UIButton(type: .system, primaryAction: UIAction(title: "Close") { [weak self] _ in
                    self?.dismiss(animated: true)
                })
                for subview in [label, close] as [UIView] {
                    subview.translatesAutoresizingMaskIntoConstraints = false
                    view.addSubview(subview)
                }
                let guide = view.safeAreaLayoutGuide
                NSLayoutConstraint.activate([
                    close.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
                    close.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
                    label.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
                    label.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
                    label.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
                ])
            }
        }

        static func runIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-video-edit") else { return }
            Task { @MainActor in
                for _ in 0..<60 where TDLib.shared.activeAccountID == nil {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                guard TDLib.shared.activeAccountID != nil else { return }
                let url: URL
                do {
                    url = try await Task.detached(priority: .userInitiated) { try await ProbeVideo.make() }.value
                } catch {
                    log("Video edit probe could not write its video: \(error)")
                    return
                }
                try? await Task.sleep(for: .seconds(1))
                var presenter = window.rootViewController
                while let presented = presenter?.presentedViewController {
                    presenter = presented
                }
                guard let presenter else { return }
                let editor = VideoEditViewController(asset: AVURLAsset(url: url), adjustments: nil)
                editor.onDone = { [weak presenter] edit in
                    // The editor dismisses itself right after handing back the edit.
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        let summary = describe(edit)
                        let result = ResultViewController(text: summary + "\n\nconverting…")
                        presenter?.present(result, animated: true)
                        let converted = await convert(url, edit: edit)
                        result.text = summary + "\n\n" + converted
                    }
                }
                presenter.present(editor, animated: true)
            }
        }

        private static func describe(_ edit: VideoEditAdjustments?) -> String {
            guard let edit else { return "unchanged" }
            var lines = [String]()
            if let trimRange = edit.trimRange {
                lines.append(String(format: "trim %.2f–%.2f s", trimRange.lowerBound, trimRange.upperBound))
            }
            lines.append(edit.sendsAsGIF ? "muted: sent as a GIF" : "with sound")
            lines.append(edit.conversion(for: .medium))
            return lines.joined(separator: "\n")
        }

        /// The video as `VideoSendGenerationCoordinator` would hand it to TDLib.
        private static func convert(_ source: URL, edit: VideoEditAdjustments?) async -> String {
            let directory = FileManager.default.temporaryDirectory
            let destination = directory.appendingPathComponent("bettertg-video-edit-probe-sent.mp4")
            let transcoder = VideoSendTranscoder(preset: .medium, edit: edit)
            do {
                try await transcoder.transcode(from: source, to: destination) { _ in }
                let output = AVURLAsset(url: destination)
                let duration = try await output.load(.duration).seconds
                let size = try await output.loadTracks(withMediaType: .video).first?.load(.naturalSize) ?? .zero
                let hasAudio = try await !output.loadTracks(withMediaType: .audio).isEmpty
                return String(format: "converted %.2f s, %d×%d", duration, Int(size.width), Int(size.height))
                    + (hasAudio ? ", with sound" : ", no sound")
            } catch {
                return "conversion failed: \(error)"
            }
        }
    }

    // MARK: - ProbeVideo

    /// A 1280×720 H.264 movie at 30 fps: each second a colour with its number, a white bar along the bottom that
    /// grows over the whole video, and a 440 Hz tone. The message content probe plays it as a game's animation.
    enum ProbeVideo {
        enum Failure: Error {
            case unwritable
        }

        static let size = CGSize(width: 1280, height: 720)
        static let seconds = 6
        static let frameRate = 30
        static let sampleRate = 44100

        static func make() async throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("bettertg-video-edit-probe.mov")
            try? FileManager.default.removeItem(at: url)
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
            ])
            videoInput.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: Int(size.width),
                    kCVPixelBufferHeightKey as String: Int(size.height),
                ],
            )
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64000,
            ])
            audioInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(videoInput), writer.canAdd(audioInput) else { throw Failure.unwritable }
            writer.add(videoInput)
            writer.add(audioInput)
            guard writer.startWriting() else { throw writer.error ?? Failure.unwritable }
            writer.startSession(atSourceTime: .zero)
            let stills = (0..<seconds).map(still)
            let audioFormat = try audioFormatDescription()
            let samplesPerFrame = sampleRate / frameRate
            let frameCount = seconds * frameRate
            // The writer interleaves the tracks and holds one back until the other catches up, so each track is
            // fed whenever it is ready instead of in lockstep.
            var videoFrame = 0
            var audioFrame = 0
            while videoFrame < frameCount || audioFrame < frameCount {
                guard writer.status == .writing else { throw writer.error ?? Failure.unwritable }
                var appended = false
                if videoFrame < frameCount, videoInput.isReadyForMoreMediaData {
                    guard let buffer = pixelBuffer(
                        frame: videoFrame,
                        of: frameCount,
                        still: stills[videoFrame / frameRate],
                        pool: adaptor.pixelBufferPool,
                    ),
                        adaptor.append(buffer, withPresentationTime: CMTime(
                            value: CMTimeValue(videoFrame),
                            timescale: CMTimeScale(frameRate),
                        ))
                    else { throw writer.error ?? Failure.unwritable }
                    videoFrame += 1
                    if videoFrame == frameCount { videoInput.markAsFinished() }
                    appended = true
                }
                if audioFrame < frameCount, audioInput.isReadyForMoreMediaData {
                    guard let sample = tone(
                        start: audioFrame * samplesPerFrame,
                        count: samplesPerFrame,
                        format: audioFormat,
                    ), audioInput.append(sample) else { throw writer.error ?? Failure.unwritable }
                    audioFrame += 1
                    if audioFrame == frameCount { audioInput.markAsFinished() }
                    appended = true
                }
                if !appended { try await Task.sleep(for: .milliseconds(5)) }
            }
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? Failure.unwritable }
            return url
        }

        private static func still(_ second: Int) -> CGImage? {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor(hue: CGFloat(second) / CGFloat(seconds), saturation: 0.75, brightness: 0.85, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                let text = "\(second + 1)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 360),
                    .foregroundColor: UIColor.white,
                ]
                let textSize = text.size(withAttributes: attributes)
                text.draw(
                    at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                    withAttributes: attributes,
                )
            }
            return image.cgImage
        }

        private static func pixelBuffer(
            frame: Int,
            of frameCount: Int,
            still: CGImage?,
            pool: CVPixelBufferPool?,
        ) -> CVPixelBuffer? {
            guard let pool else { return nil }
            var created: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &created) == kCVReturnSuccess,
                  let buffer = created
            else { return nil }
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            guard let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue,
            ) else { return nil }
            if let still {
                context.draw(still, in: CGRect(origin: .zero, size: size))
            }
            // Core Graphics counts from the bottom, so the bar runs along the frame's bottom edge.
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: size.width * CGFloat(frame + 1) / CGFloat(frameCount), height: 24))
            return buffer
        }

        private static func audioFormatDescription() throws -> CMAudioFormatDescription {
            var description = AudioStreamBasicDescription(
                mSampleRate: Float64(sampleRate),
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                mBytesPerPacket: 2,
                mFramesPerPacket: 1,
                mBytesPerFrame: 2,
                mChannelsPerFrame: 1,
                mBitsPerChannel: 16,
                mReserved: 0,
            )
            var format: CMAudioFormatDescription?
            let status = CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &description,
                layoutSize: 0,
                layout: nil,
                magicCookieSize: 0,
                magicCookie: nil,
                extensions: nil,
                formatDescriptionOut: &format,
            )
            guard status == noErr, let format else { throw Failure.unwritable }
            return format
        }

        /// `count` samples of mono 16-bit PCM from sample `start`.
        private static func tone(start: Int, count: Int, format: CMAudioFormatDescription) -> CMSampleBuffer? {
            let samples = (0..<count).map { index in
                Int16(sin(2 * Double.pi * 440 * Double(start + index) / Double(sampleRate)) * 8000)
            }
            let length = count * MemoryLayout<Int16>.size
            var created: CMBlockBuffer?
            guard CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: length,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: length,
                flags: 0,
                blockBufferOut: &created,
            ) == kCMBlockBufferNoErr, let block = created else { return nil }
            let copied = samples.withUnsafeBytes { bytes -> OSStatus in
                guard let base = bytes.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
                return CMBlockBufferReplaceDataBytes(
                    with: base,
                    blockBuffer: block,
                    offsetIntoDestination: 0,
                    dataLength: length,
                )
            }
            guard copied == kCMBlockBufferNoErr else { return nil }
            var sample: CMSampleBuffer?
            let status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: kCFAllocatorDefault,
                dataBuffer: block,
                formatDescription: format,
                sampleCount: count,
                presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(sampleRate)),
                packetDescriptions: nil,
                sampleBufferOut: &sample,
            )
            return status == noErr ? sample : nil
        }
    }
#endif
