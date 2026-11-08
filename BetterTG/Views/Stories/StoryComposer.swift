// StoryComposer.swift

import AVFoundation
import Combine
import CoreImage.CIFilterBuiltins
import PhotosUI
import TDLibKit
import UIKit
import UniformTypeIdentifiers
import VideoToolbox

// MARK: - StoryComposer

/// ChatListController.openStoryCamera for the account's first story, from what BetterTG has: a photo or a video from
/// the library (Telegram opens its camera with the gallery under it), its MediaEditorScreen preview on a 9:16 canvas
/// with the caption, then ShareWithPeersScreen's Share Story. Telegram's camera, its trimming and splitting of long
/// videos and the editor's drawing, text, stickers and areas aren't ported.
@MainActor final class StoryComposer: NSObject, PHPickerViewControllerDelegate {
    private static var current: StoryComposer?

    private weak var host: UIViewController?
    private let client: TDLibClient
    private let accountID: UUID?

    private init(host: UIViewController, client: TDLibClient, accountID: UUID?) {
        self.host = host
        self.client = client
        self.accountID = accountID
    }

    static func start(from host: UIViewController, client: TDLibClient, accountID: UUID?) {
        let composer = StoryComposer(host: host, client: client, accountID: accountID)
        current = composer
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = composer
        host.present(picker, animated: true)
    }

    /// MediaEditor's 1080 by 1920 canvas: the photo fitted in the middle over MediaEditor's gradient from the
    /// photo's top and bottom colours.
    static func canvas(_ image: UIImage) -> UIImage {
        let size = CGSize(width: 1080, height: 1920)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let (top, bottom) = edgeColors(image)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [
                0,
                1,
            ]) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: 0, y: size.height),
                    options: [],
                )
            }
            image.draw(in: aspectRect(image.size, in: size, filling: false))
        }
    }

    /// The photo's mean colours of its top and bottom halves, read from a 1 by 2 RGBA buffer.
    nonisolated static func edgeColors(_ image: UIImage) -> (UIColor, UIColor) {
        guard let cgImage = image.cgImage else { return (.black, .black) }
        var pixels = [UInt8](repeating: 0, count: 8)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 2))
            return true
        }
        guard drawn else { return (.black, .black) }
        // The buffer's first row is the image's top.
        let color: (Int) -> UIColor = { offset in
            UIColor(
                red: CGFloat(pixels[offset]) / 255,
                green: CGFloat(pixels[offset + 1]) / 255,
                blue: CGFloat(pixels[offset + 2]) / 255,
                alpha: 1,
            )
        }
        return (color(0), color(4))
    }

    private static func aspectRect(_ imageSize: CGSize, in size: CGSize, filling: Bool) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGRect(origin: .zero, size: size) }
        let scale = filling
            ? max(size.width / imageSize.width, size.height / imageSize.height)
            : min(size.width / imageSize.width, size.height / imageSize.height)
        let scaled = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (size.width - scaled.width) / 2,
            y: (size.height - scaled.height) / 2,
            width: scaled.width,
            height: scaled.height,
        )
    }

    /// A video's first frame, its canvas and its length, at most storyMaxVideoDuration's 60 seconds.
    private static func videoMedia(_ url: URL) async -> StoryDraft? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration > 0 else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        guard let frame = try? await generator.image(at: .zero).image else { return nil }
        let image = UIImage(cgImage: frame)
        return .video(
            url,
            firstFrame: image,
            canvas: canvas(image),
            assetDuration: duration,
            range: 0...min(duration, 60),
            overlay: nil,
        )
    }

    nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        let provider = results.first?.itemProvider
        Task { @MainActor in
            picker.dismiss(animated: true)
            guard let provider else {
                Self.current = nil
                return
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                loadVideo(provider)
                return
            }
            guard provider.canLoadObject(ofClass: UIImage.self) else {
                Self.current = nil
                return
            }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                let image = object as? UIImage
                Task { @MainActor in
                    guard let image else {
                        Self.current = nil
                        return
                    }
                    self.openPreview(.photo(Self.canvas(image)))
                }
            }
        }
    }

    /// The picked video, copied out of the provider's file, which goes away when its handler returns.
    private func loadVideo(_ provider: NSItemProvider) {
        provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
            var copy: URL?
            if let url {
                let destination = FileManager.default
                    .temporaryDirectory
                    .appendingPathComponent("bettertg-story-source-\(UUID().uuidString)")
                    .appendingPathExtension(url.pathExtension)
                if (try? FileManager.default.copyItem(at: url, to: destination)) != nil { copy = destination }
            }
            Task { @MainActor in
                guard let copy, let media = await Self.videoMedia(copy) else {
                    Self.current = nil
                    return
                }
                self.openPreview(media)
            }
        }
    }

    private func openPreview(_ media: StoryDraft) {
        guard let host else {
            Self.current = nil
            return
        }
        let client = client
        let accountID = accountID
        Task { @MainActor in
            // storyEditor(remainingCount:): a video may run as long as three stories, or as many as the account may
            // still post (checkStoriesUploadAvailability), a minute each.
            var remaining = 1
            if let ownID = TDLib.shared.activeAccount?.userID,
               case .canPostStoryResultOk(let result)? = try? await client.send(
                   TDNativeRequests.canPostStory(chatId: ownID),
               )
            {
                remaining = max(1, result.storyCount)
            }
            let maxDuration = Double(min(StoryDraft.maxCombinedCount, remaining)) * StoryDraft.maxVideoDuration
            var media = media
            if let duration = media.videoDuration { media = media.withRange(0...min(duration, maxDuration)) }
            let preview = StoryPreviewViewController(
                media: media,
                maxVideoDuration: maxDuration,
                client: client,
                accountID: accountID,
            )
            let navigation = TelegramNavigationController(rootViewController: preview)
            navigation.modalPresentationStyle = .fullScreen
            host.present(navigation, animated: true)
            Self.current = nil
        }
    }
}

// MARK: - StoryDraft

/// What a new story shows: a photo already on its canvas, or a video with its first frame and that frame's canvas,
/// which the preview plays the video over and which gives the export its gradient.
private enum StoryDraft {
    case photo(UIImage)
    /// `overlay`: the editor's entities on a clear 1080 by 1920 image, drawn over every frame.
    /// `range`: the trimmed part of the video, at most storyMaxVideoDuration's 60 seconds.
    case video(
        URL,
        firstFrame: UIImage,
        canvas: UIImage,
        assetDuration: Double,
        range: ClosedRange<Double>,
        overlay: UIImage?,
    )

    /// storyMaxVideoDuration and storyMaxCombinedVideoCount.
    static let maxVideoDuration: Double = 60
    static let maxCombinedCount = 3

    var canvas: UIImage {
        switch self {
        case .photo(let image): image
        case .video(_, _, let canvas, _, _, _): canvas
        }
    }

    var videoDuration: Double? {
        if case .video(_, _, _, let duration, _, _) = self {
            duration
        } else {
            nil
        }
    }

    /// The stories a long video makes: a minute each from the trimmed part's start, at most three.
    var segments: [ClosedRange<Double>] {
        guard case .video(_, _, _, _, let range, _) = self else { return [] }
        var result = [ClosedRange<Double>]()
        var start = range.lowerBound
        while start < range.upperBound - 0.01, result.count < Self.maxCombinedCount {
            result.append(start...min(range.upperBound, start + Self.maxVideoDuration))
            start += Self.maxVideoDuration
        }
        return result
    }

    /// The story with the editor's entities: drawn into a photo, kept for a video's export.
    func withOverlay(_ overlay: UIImage?) -> StoryDraft {
        guard let overlay else { return self }
        switch self {
        case .photo(let image):
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let size = StoryEntitiesView.size
            return .photo(UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
                overlay.draw(in: CGRect(origin: .zero, size: size))
            })
        case .video(let url, let firstFrame, let canvas, let assetDuration, let range, _):
            return .video(
                url,
                firstFrame: firstFrame,
                canvas: canvas,
                assetDuration: assetDuration,
                range: range,
                overlay: overlay,
            )
        }
    }

    /// The video trimmed to `range`.
    func withRange(_ range: ClosedRange<Double>) -> StoryDraft {
        guard case .video(let url, let firstFrame, let canvas, let assetDuration, _, let overlay) = self else {
            return self
        }
        return .video(
            url,
            firstFrame: firstFrame,
            canvas: canvas,
            assetDuration: assetDuration,
            range: range,
            overlay: overlay,
        )
    }

    /// postStory's content: the photo as a JPEG, or the video exported for a story.
    func content() async throws -> TDNativeInputStoryContent {
        switch self {
        case .photo(let image):
            guard let data = image.jpegData(compressionQuality: 0.9) else { throw StoryVideoExport.Failure() }
            let url = FileManager.default
                .temporaryDirectory
                .appendingPathComponent("bettertg-story-\(UUID().uuidString).jpg")
            try data.write(to: url)
            return .inputStoryContentPhoto(TDNativeInputStoryContentPhoto(
                photo: .inputFileLocal(InputFileLocal(path: url.path)),
                addedStickerFileIds: [],
            ))
        case .video(let url, let firstFrame, _, _, let range, let overlay):
            let duration = range.upperBound - range.lowerBound
            let (output, hasAudio) = try await StoryVideoExport.export(
                url,
                firstFrame: firstFrame,
                range: range,
                overlay: overlay,
            )
            return .inputStoryContentVideo(TDNativeInputStoryContentVideo(
                video: .inputFileLocal(InputFileLocal(path: output.path)),
                addedStickerFileIds: [],
                duration: duration,
                coverFrameTimestamp: 0,
                isAnimation: !hasAudio,
            ))
        }
    }
}

// MARK: - StoryVideoExport

/// MediaEditorVideoExport for a story: MediaEditorValues' 720 by 1280, the video fitted over its first frame's
/// gradient as the preview shows it, cut to its first 60 seconds, written by StoryVideoWriter as Telegram's
/// configuration asks.
private enum StoryVideoExport {
    struct Failure: Error {}

    /// hasHEVCHardwareEncoder.
    private static let hasHEVCEncoder: Bool = {
        var encoderID: CFString?
        var properties: CFDictionary?
        let result = VTCopySupportedPropertyDictionaryForEncoder(
            width: 1920,
            height: 1080,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: [:] as CFDictionary,
            encoderIDOut: &encoderID,
            supportedPropertiesOut: &properties,
        )
        return result == noErr
    }()

    static func export(
        _ source: URL,
        firstFrame: UIImage,
        range: ClosedRange<Double>,
        overlay: UIImage?,
    ) async throws -> (URL, Bool) {
        let source = AVURLAsset(url: source)
        guard let sourceTrack = try await source.loadTracks(withMediaType: .video).first else { throw Failure() }
        let sourceAudio = try await source.loadTracks(withMediaType: .audio)
        let hasAudio = !sourceAudio.isEmpty
        let (transform, frameRate) = try await (
            sourceTrack.load(.preferredTransform),
            sourceTrack.load(.nominalFrameRate),
        )
        // The trimmed part from zero, as MediaEditorVideoExport's composition takes the trim range.
        let duration = range.upperBound - range.lowerBound
        let trim = CMTimeRange(
            start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600),
        )
        let asset = AVMutableComposition()
        guard let track = asset.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw Failure() }
        try track.insertTimeRange(trim, of: sourceTrack, at: .zero)
        track.preferredTransform = transform
        for audio in sourceAudio {
            let audioTrack = asset.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid,
            )
            try audioTrack?.insertTimeRange(trim, of: audio, at: .zero)
        }
        let assetDuration = trim.duration
        let renderSize = CGSize(width: 720, height: 1280)
        let (top, bottom) = StoryComposer.edgeColors(firstFrame)
        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: 0, y: renderSize.height)
        gradient.color0 = CIColor(color: top)
        gradient.point1 = .zero
        gradient.color1 = CIColor(color: bottom)
        let background = (gradient.outputImage ?? CIImage(color: .black))
            .cropped(to: CGRect(origin: .zero, size: renderSize))
        var configuration = AVVideoComposition.Configuration()
        configuration.customVideoCompositorClass = StoryVideoCompositor.self
        configuration.renderSize = renderSize
        configuration.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate > 0 ? frameRate.rounded() : 30))
        configuration.instructions = [StoryVideoInstruction(
            timeRange: CMTimeRange(start: .zero, duration: assetDuration),
            trackID: track.trackID,
            orientation: orientation(transform),
            background: background,
            overlay: overlay.flatMap { CIImage(image: $0) }.map {
                $0.transformed(by: CGAffineTransform(
                    scaleX: renderSize.width / StoryEntitiesView.size.width,
                    y: renderSize.height / StoryEntitiesView.size.height,
                ))
            },
        )]
        let composition = AVVideoComposition(configuration: configuration)
        let output = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bettertg-story-\(UUID().uuidString).mp4")
        let audioTracks = asset.tracks(withMediaType: .audio)
        try await StoryVideoWriter.write(
            asset: asset,
            videoTrack: track,
            audioTracks: audioTracks,
            composition: composition,
            timeRange: CMTimeRange(start: .zero, duration: assetDuration),
            videoSettings: videoSettings(duration: duration, size: renderSize),
            to: output,
        )
        return (output, hasAudio)
    }

    /// recommendedVideoExportConfiguration for a story: 720 by 1280, HEVC where the device has its hardware encoder and
    /// H.264 High with CABAC otherwise, at 5800 kbps under 10 s, 5500 under 20, 5000 under 30, then down to 3700 by 60.
    private static func videoSettings(duration: Double, size: CGSize) -> [String: Any] {
        let kbps =
            if duration < 10 {
                5800
            } else if duration < 20 {
                5500
            } else if duration < 30 {
                5000
            } else {
                Int(5000 - (5000 - 3700) * min(1, (duration - 30) / 30))
            }
        let compression: [String: Any] = hasHEVCEncoder
            ? [
                AVVideoAverageBitRateKey: kbps * 1000,
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel as String,
            ]
            : [
                AVVideoAverageBitRateKey: kbps * 1000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
            ]
        return [
            AVVideoCodecKey: hasHEVCEncoder ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoCompressionPropertiesKey: compression,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
    }

    /// The stored frame's orientation from the track's preferred transform.
    private static func orientation(_ transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (transform.a, transform.b, transform.c, transform.d) {
        case (0, 1, -1, 0): .right
        case (0, -1, 1, 0): .left
        case (-1, 0, 0, -1): .down
        default: .up
        }
    }
}

// MARK: - StoryVideoInstruction

/// The export's one instruction: which track to draw, how its stored frames turn upright, and the gradient under them.
private final class StoryVideoInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let trackID: CMPersistentTrackID
    let orientation: CGImagePropertyOrientation
    let background: CIImage
    /// The editor's entities at the render size, over the frame.
    let overlay: CIImage?

    init(
        timeRange: CMTimeRange,
        trackID: CMPersistentTrackID,
        orientation: CGImagePropertyOrientation,
        background: CIImage,
        overlay: CIImage?,
    ) {
        self.timeRange = timeRange
        self.trackID = trackID
        self.orientation = orientation
        self.background = background
        self.overlay = overlay
        self.requiredSourceTrackIDs = [NSNumber(value: trackID)]
    }
}

// MARK: - StoryVideoCompositor

/// Draws each frame upright and aspect fitted in the middle of the story over the gradient, as MediaEditor's
/// composer draws a video that doesn't fill 9:16.
private final class StoryVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]

    private let context = CIContext()

    func renderContextChanged(_: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? StoryVideoInstruction,
              let source = request.sourceFrame(byTrackID: instruction.trackID),
              let output = request.renderContext.newPixelBuffer()
        else {
            request.finish(with: StoryVideoExport.Failure())
            return
        }
        var image = CIImage(cvPixelBuffer: source).oriented(instruction.orientation)
        let renderSize = request.renderContext.size
        let extent = image.extent
        let scale = min(renderSize.width / extent.width, renderSize.height / extent.height)
        let size = CGSize(width: extent.width * scale, height: extent.height * scale)
        image = image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(
                translationX: (renderSize.width - size.width) / 2,
                y: (renderSize.height - size.height) / 2,
            ))
        var composed = image.composited(over: instruction.background)
        if let overlay = instruction.overlay { composed = overlay.composited(over: composed) }
        context.render(composed, to: output)
        request.finish(withComposedVideoFrame: output)
    }
}

// MARK: - StoryPlayerView

/// The preview's looping video, aspect fitted like the canvas.
private final class StoryPlayerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        unsafeDowncast(layer, to: AVPlayerLayer.self)
    }
}

// MARK: - StoryPreviewViewController

/// MediaEditorScreen's preview: the story on black with 12 pt corners, Close and Next in the bar, and the caption
/// field over the story's bottom (Add a caption...); Next goes on to Share Story.
private final class StoryPreviewViewController: UIViewController, UITextViewDelegate,
UIColorPickerViewControllerDelegate {
    private var media: StoryDraft
    private let client: TDLibClient
    private let accountID: UUID?
    private let imageView = UIImageView()
    private let captionView = UITextView()
    private let placeholder = UILabel()
    /// MediaEditorScreen's timeout button: the hours the story stays, 24 unless Premium picks 6, 12 or 48.
    private let timerButton = UIButton(type: .system)
    private var hours = 24
    private var isPremium = false

    /// A video story's player, looping over the part that will be posted.
    private let playerView = StoryPlayerView()
    /// MediaEditorScreen's entities over the story, in story points.
    private let entitiesView = StoryEntitiesView()
    /// TextSizeSliderComponent at the screen's leading edge while a text is edited.
    private let sizeSlider = StoryTextSizeSlider()
    /// The keyboard's top in the view, its bottom while the keyboard is down.
    private var keyboardTop = CGFloat.greatestFiniteMagnitude
    private var keyboardObservation: AnyCancellable?
    private lazy var nextItem = UIBarButtonItem(
        title: L10n.telegram("Story.Editor.Next"),
        primaryAction: UIAction { [weak self] _ in self?.next() },
    )
    private lazy var closeItem = UIBarButtonItem(
        title: L10n.telegram("Common.Close"),
        primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) },
    )
    private lazy var doneItem = UIBarButtonItem(
        title: L10n.telegram("Common.Done"),
        primaryAction: UIAction { [weak self] _ in self?.entitiesView.endEditing() },
    )
    /// The editor's text button, as its bottom panel's AddText.
    private lazy var textItem = UIBarButtonItem(
        image: UIImage(systemName: "textformat"),
        primaryAction: UIAction { [weak self] _ in
            self?.captionView.resignFirstResponder()
            self?.entitiesView.insertText()
        },
    )
    /// DrawingScreen: the tools under the story, the colour swatch beside them, the chosen tool, its colour and size.
    private let drawingTools = StoryDrawingToolsView()
    private let drawingSwatch = StoryColorSwatchButton()
    private var drawingTool = StoryDrawingTool.pen
    private var drawingColors = StoryDrawingTool.allCases.reduce(into: [StoryDrawingTool: UIColor]()) {
        $0[$1] = $1.initialColor
    }

    private var drawingSizes = StoryDrawingTool.allCases.reduce(into: [StoryDrawingTool: CGFloat]()) {
        $0[$1] = $1.initialSize
    }

    private var isDrawing = false
    /// The strokes when drawing began, which Cancel goes back to.
    private var drawingStrokeCount = 0
    /// The editor's draw button, as its bottom panel's Pencil.
    private lazy var drawItem = UIBarButtonItem(
        image: UIImage(named: "MediaEditor/Pencil")?.withRenderingMode(.alwaysTemplate),
        primaryAction: UIAction { [weak self] _ in self?.setDrawing(true) },
    )
    private lazy var drawingCancelItem = UIBarButtonItem(
        title: L10n.telegram("Common.Cancel"),
        primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            entitiesView.drawingView.restore(strokeCount: drawingStrokeCount)
            setDrawing(false)
        },
    )
    private lazy var drawingDoneItem = UIBarButtonItem(
        title: L10n.telegram("Common.Done"),
        primaryAction: UIAction { [weak self] _ in self?.setDrawing(false) },
    )
    private lazy var undoItem = UIBarButtonItem(
        image: UIImage(systemName: "arrow.uturn.backward"),
        primaryAction: UIAction { [weak self] _ in self?.entitiesView.drawingView.undo() },
    )
    private lazy var clearItem = UIBarButtonItem(
        title: L10n.telegram("Paint.Clear"),
        primaryAction: UIAction { [weak self] _ in self?.entitiesView.drawingView.clear() },
    )
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    /// MediaScrubberComponent over the caption: the video's trimmed part.
    private var scrubber: StoryVideoScrubber?
    private var timeObserver: Any?

    private let maxVideoDuration: Double

    init(media: StoryDraft, maxVideoDuration: Double, client: TDLibClient, accountID: UUID?) {
        self.media = media
        self.maxVideoDuration = maxVideoDuration
        self.client = client
        self.accountID = accountID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark
        navigationItem.leftBarButtonItem = closeItem
        imageView.image = media.canvas
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.layer.cornerCurve = .continuous
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        if case .video(let url, _, _, let assetDuration, let range, _) = media {
            let player = AVQueuePlayer()
            self.player = player
            loop(url, over: range)
            playerView.playerLayer.player = player
            playerView.playerLayer.videoGravity = .resizeAspect
            playerView.isUserInteractionEnabled = false
            playerView.frame = imageView.bounds
            playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            imageView.addSubview(playerView)
            let scrubber = StoryVideoScrubber(
                asset: AVURLAsset(url: url),
                duration: assetDuration,
                range: range,
                maximumDuration: maxVideoDuration,
                segmentDuration: StoryDraft.maxVideoDuration,
            )
            scrubber.onTrim = { [weak self] range, edge, ended in self?.trim(to: range, edge: edge, ended: ended) }
            view.addSubview(scrubber)
            self.scrubber = scrubber
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(value: 1, timescale: 30),
                queue: .main,
            ) { [weak self] time in
                MainActor.assumeIsolated { self?.scrubber?.setPosition(time.seconds) }
            }
        }

        captionView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        captionView.layer.cornerRadius = 18
        captionView.font = .systemFont(ofSize: 17)
        captionView.textColor = .white
        captionView.textContainerInset = UIEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        captionView.isScrollEnabled = false
        captionView.delegate = self
        captionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captionView)
        placeholder.text = L10n.telegram("Story.Editor.InputPlaceholderAddCaption")
        placeholder.font = .systemFont(ofSize: 17)
        placeholder.textColor = UIColor.white.withAlphaComponent(0.6)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        captionView.addSubview(placeholder)
        timerButton.tintColor = .white
        timerButton.showsMenuAsPrimaryAction = true
        // Telegram's order from top to bottom, wherever the menu opens.
        timerButton.preferredMenuElementOrder = .fixed
        timerButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(timerButton)
        updateTimer()
        let client = client
        Task { [weak self] in
            let me = try? await client.send(TDNativeRequests.getMe())
            guard let self else { return }
            isPremium = me?.isPremium ?? false
            updateTimer()
        }

        textItem.accessibilityLabel = L10n.telegram("Paint.Text")
        drawItem.accessibilityLabel = L10n.telegram("Paint.Draw")
        navigationItem.rightBarButtonItems = [nextItem, textItem, drawItem]
        drawingTools.alpha = 0
        drawingSwatch.alpha = 0
        view.addSubview(drawingTools)
        view.addSubview(drawingSwatch)
        drawingTools.onSelect = { [weak self] tool in
            self?.drawingTool = tool
            self?.applyDrawingTool()
        }
        drawingTools.onResize = { [weak self] size in
            guard let self else { return }
            drawingSizes[drawingTool] = size
            applyDrawingTool()
            entitiesView.drawingView.setBrushSizePreview(size)
        }
        drawingTools.onResizeEnd = { [weak self] in self?.entitiesView.drawingView.setBrushSizePreview(nil) }
        sizeSlider.onRelease = { [weak self] in self?.entitiesView.drawingView.setBrushSizePreview(nil) }
        drawingSwatch.onTap = { [weak self] in self?.presentColorPicker() }
        drawingSwatch.onPick = { [weak self] color in
            guard let self, drawingColors[drawingTool] != nil else { return }
            drawingColors[drawingTool] = color
            applyDrawingTool()
        }
        entitiesView.drawingView.onStrokesChange = { [weak self] in self?.updateUndo() }
        // getCurrentImage: a video's frame on screen now, on its canvas, or the photo.
        entitiesView.drawingView.storyImage = { [weak self] in await self?.currentStoryImage() }
        imageView.isUserInteractionEnabled = true
        imageView.addSubview(entitiesView)
        // A tap while the caption is edited only ends that, as MediaEditorScreen's tap does with the keyboard up.
        entitiesView.shouldInsertText = { [weak self] in
            guard let self, captionView.isFirstResponder else { return true }
            captionView.resignFirstResponder()
            return false
        }
        entitiesView.editingCenter = { [weak self] in
            guard let self else { return CGPoint(x: 540, y: 960) }
            let story = imageView.frame
            let bottom = max(story.minY + 120, min(story.maxY, keyboardTop))
            let point = CGPoint(x: story.midX, y: (story.minY + bottom) / 2)
            return view.convert(point, to: entitiesView)
        }
        keyboardObservation = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, let window = view.window,
                      let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                else { return }
                keyboardTop = view.convert(window.convert(frame, from: nil), from: nil).minY
                entitiesView.updateEditingPosition()
                layoutSizeSlider()
            }
        sizeSlider.alpha = 0
        view.addSubview(sizeSlider)
        sizeSlider.onChange = { [weak self] value in
            guard let self else { return }
            if isDrawing {
                drawingSizes[drawingTool] = value
                applyDrawingTool()
                entitiesView.drawingView.setBrushSizePreview(value)
                return
            }
            guard let entity = entitiesView.editingEntity else { return }
            entity.fontSize = value
            entity.update()
            entitiesView.updateEditingPosition()
        }
        entitiesView.settingsBar.onColor = { [weak self] in self?.presentColorPicker() }
        entitiesView.settingsBar.onFonts = { [weak self] source in self?.presentFontPicker(from: source) }
        entitiesView.onEditingChange = { [weak self] isEditing in
            guard let self else { return }
            if isEditing, let entity = entitiesView.editingEntity { sizeSlider.value = entity.fontSize }
            UIView.animate(withDuration: 0.2) { self.sizeSlider.alpha = isEditing ? 1 : 0 }
            navigationItem.rightBarButtonItems = isEditing ? [doneItem] : [nextItem, textItem, drawItem]
            navigationItem.leftBarButtonItem = isEditing ? nil : closeItem
            UIView.animate(withDuration: 0.2) {
                self.captionView.alpha = isEditing ? 0 : 1
                self.scrubber?.alpha = isEditing ? 0 : 1
                self.timerButton.alpha = isEditing ? 0 : 1
            }
        }

        let guide = view.safeAreaLayoutGuide
        // The caption rises with the keyboard over the story, which keeps its size.
        let captionBottom = captionView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -10)
        captionBottom.priority = .defaultHigh - 1
        // As tall as the safe area allows, 9:16.
        let imageHeight = imageView.heightAnchor.constraint(equalTo: guide.heightAnchor, constant: -16)
        imageHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            imageView.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualTo: guide.widthAnchor, constant: -16),
            imageView.bottomAnchor.constraint(lessThanOrEqualTo: guide.bottomAnchor, constant: -8),
            imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor, multiplier: 9 / 16),
            imageHeight,
            captionView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 10),
            captionView.trailingAnchor.constraint(equalTo: timerButton.leadingAnchor, constant: -6),
            timerButton.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -8),
            timerButton.centerYAnchor.constraint(equalTo: captionView.centerYAnchor),
            timerButton.widthAnchor.constraint(equalToConstant: 44),
            timerButton.heightAnchor.constraint(equalToConstant: 36),
            captionBottom,
            captionView.bottomAnchor.constraint(
                lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor,
                constant: -10,
            ),
            captionView.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            placeholder.leadingAnchor.constraint(equalTo: captionView.leadingAnchor, constant: 15),
            placeholder.centerYAnchor.constraint(equalTo: captionView.centerYAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        player?.play()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player?.pause()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutSizeSlider()
        if let scrubber {
            let story = imageView.frame
            scrubber.frame = CGRect(
                x: story.minX + 12,
                y: captionView.frame.minY - 8 - StoryVideoScrubber.height,
                width: story.width - 24,
                height: StoryVideoScrubber.height,
            )
        }
        layoutDrawingTools()
        // The entities' story points scaled onto the story.
        let scale = imageView.bounds.width / StoryEntitiesView.size.width
        entitiesView.transform = CGAffineTransform(scaleX: scale, y: scale)
        entitiesView.center = CGPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholder.isHidden = !textView.text.isEmpty
    }

    func colorPickerViewController(
        _: UIColorPickerViewController,
        didSelect color: UIColor,
        continuously _: Bool,
    ) {
        if isDrawing {
            drawingColors[drawingTool] = color
            applyDrawingTool()
            return
        }
        guard let entity = entitiesView.editingEntity else { return }
        entity.color = color
        entity.update()
        entitiesView.settingsBar.refresh()
    }

    func colorPickerViewControllerDidFinish(_: UIColorPickerViewController) {
        entitiesView.editingEntity?.resumeEditing()
    }

    /// presentTimeoutSetup: Choose how long the story will be visible, then 6, 12, 24 and 48 Hours with a check on
    /// the chosen one; without Premium all but 24 carry a lock and explain Premium instead.
    private func updateTimer() {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: "timer",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium),
        )
        configuration.imagePadding = 2
        configuration.title = "\(hours)"
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 12, weight: .semibold)
            return attributes
        }
        configuration.contentInsets = .zero
        timerButton.configuration = configuration
        timerButton.accessibilityLabel = L10n.telegramPlural("Story.Editor.ExpirationValue", count: hours)
        let options = [6, 12, 24, 48].map { value in
            let locked = value != 24 && !isPremium
            return UIAction(
                title: L10n.telegramPlural("Story.Editor.ExpirationValue", count: value),
                image: locked ? UIImage(systemName: "lock.fill") : nil,
                state: value == hours ? .on : .off,
            ) { [weak self] _ in
                guard let self else { return }
                if locked {
                    let alert = UIAlertController(
                        title: nil,
                        message: L10n.telegram("Story.Editor.TooltipPremiumExpiration")
                            .replacing("[", with: "")
                            .replacing("]()", with: ""),
                        preferredStyle: .alert,
                    )
                    alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
                    present(alert, animated: true)
                } else {
                    hours = value
                    updateTimer()
                }
            }
        }
        timerButton.menu = UIMenu(title: L10n.telegram("Story.Editor.ExpirationText"), children: options)
    }

    /// The slider's place: the leading edge, centred between the top inset and the keyboard or the bottom inset.
    private func currentStoryImage() async -> CGImage? {
        guard case .video(let url, _, _, _, _, _) = media, let player else { return media.canvas.cgImage }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        guard let frame = try? await generator.image(at: player.currentTime()).image else {
            return media.canvas.cgImage
        }
        return StoryComposer.canvas(UIImage(cgImage: frame)).cgImage
    }

    /// The video looping over its trimmed part.
    private func loop(_ url: URL, over range: ClosedRange<Double>) {
        guard let player else { return }
        looper?.disableLooping()
        player.removeAllItems()
        looper = AVPlayerLooper(
            player: player,
            templateItem: AVPlayerItem(url: url),
            timeRange: CMTimeRange(
                start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
                duration: CMTime(seconds: range.upperBound - range.lowerBound, preferredTimescale: 600),
            ),
        )
    }

    /// MediaEditor's trim: while a handle moves the video stops on that edge's frame, and the loop starts over the
    /// new part once it is let go.
    private func trim(to range: ClosedRange<Double>, edge: Bool?, ended: Bool) {
        media = media.withRange(range)
        guard let player, case .video(let url, _, _, _, _, _) = media else { return }
        if ended {
            loop(url, over: range)
            player.play()
        } else {
            player.pause()
            let time = edge == false ? range.upperBound : range.lowerBound
            player.seek(
                to: CMTime(seconds: time, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero,
            )
        }
    }

    /// The tools 120 pt tall along the story's bottom, the swatch at its leading corner.
    private func layoutDrawingTools() {
        let story = imageView.frame
        drawingTools.frame = CGRect(x: story.minX + 56, y: story.maxY - 120, width: story.width - 60, height: 120)
        drawingSwatch.frame = CGRect(x: story.minX + 8, y: story.maxY - 56, width: 44, height: 44)
    }

    private func layoutSizeSlider() {
        let top = view.safeAreaInsets.top
        let bottom = min(view.bounds.height - view.safeAreaInsets.bottom, keyboardTop)
        sizeSlider.frame = CGRect(
            x: view.safeAreaInsets.left,
            y: top + (bottom - top) / 2 - 120,
            width: 30,
            height: 240,
        )
    }

    /// presentFontPicker: Telegram's eight fonts, each named in itself at 17 pt, over the keyboard by the button.
    private func presentFontPicker(from source: UIView) {
        let bar = entitiesView.settingsBar
        let actions = StoryTextEntityView.fonts.map { font in
            var action = TelegramContextMenuAction(title: font.title) { bar.chooseFont(font.name) }
            action.titleFont = font.name.flatMap { UIFont(name: $0, size: 17) } ?? .systemFont(
                ofSize: 17,
                weight: .semibold,
            )
            // textFont .custom(height: 42, verticalOffset: -6 for Noteworthy).
            action.titleRowHeight = 42
            action.titleVerticalOffset = font.title == "Noteworthy" ? -6 : 0
            return action
        }
        presentTelegramContextMenu(
            sourceView: source,
            actions: actions,
            presentationStyle: .menuOnly,
            menuAnchorView: source,
            menuSpacing: 8,
        )
    }

    /// presentColorPicker, as the system's colour picker: editing pauses while it is up.
    private func presentColorPicker() {
        let picker = UIColorPickerViewController()
        picker.supportsAlpha = false
        // The editor's dark ColorPickerScreen.
        picker.overrideUserInterfaceStyle = .dark
        picker.delegate = self
        if isDrawing {
            guard let color = drawingColors[drawingTool] else { return }
            picker.selectedColor = color
        } else {
            guard let entity = entitiesView.editingEntity else { return }
            picker.selectedColor = entity.color
            entity.suspendEditing()
        }
        present(picker, animated: true)
    }

    /// DrawingScreen in and out: the tools, the swatch and the size slider come in place of the caption and the
    /// timer, and the bar offers Cancel and Undo, Clear All and Done.
    private func setDrawing(_ on: Bool) {
        captionView.resignFirstResponder()
        isDrawing = on
        entitiesView.isDrawing = on
        if on {
            drawingStrokeCount = entitiesView.drawingView.strokes.count
            applyDrawingTool()
            updateUndo()
        }
        navigationItem.leftBarButtonItems = on ? [drawingCancelItem, undoItem] : [closeItem]
        navigationItem.rightBarButtonItems = on ? [drawingDoneItem, clearItem] : [nextItem, textItem, drawItem]
        UIView.animate(withDuration: 0.2) {
            self.captionView.alpha = on ? 0 : 1
            self.scrubber?.alpha = on ? 0 : 1
            self.timerButton.alpha = on ? 0 : 1
            self.drawingTools.alpha = on ? 1 : 0
            self.drawingSwatch.alpha = on ? 1 : 0
            self.sizeSlider.alpha = on ? 1 : 0
        }
    }

    private func applyDrawingTool() {
        let drawing = entitiesView.drawingView
        drawing.tool = drawingTool
        drawing.size = drawingSizes[drawingTool] ?? 0.5
        if let color = drawingColors[drawingTool] { drawing.color = color }
        drawingTools.update(selected: drawingTool, colors: drawingColors, sizes: drawingSizes)
        // The blur and the eraser have no colour: the swatch shows its ring alone.
        drawingSwatch.color = drawingColors[drawingTool]
        drawingSwatch.isEnabled = drawingColors[drawingTool] != nil
        sizeSlider.value = drawing.size
    }

    private func updateUndo() {
        let hasStrokes = !entitiesView.drawingView.strokes.isEmpty
        undoItem.isEnabled = hasStrokes
        clearItem.isEnabled = hasStrokes
    }

    private func next() {
        captionView.resignFirstResponder()
        entitiesView.endEditing()
        let share = StoryShareViewController(
            media: media.withOverlay(entitiesView.renderOverlay()),
            caption: captionView.text ?? "",
            hours: hours,
        )
        navigationController?.pushViewController(share, animated: true)
    }
}

// MARK: - StoryShareViewController

/// ShareWithPeersScreen for a new story: WHO CAN VIEW THIS STORY (Everyone, Contacts, Close Friends with their list,
/// Selected Contacts once chosen), Allow Screenshots and Keep on My Page with its note, and Post Story, which posts
/// it from Saved Messages for a day (postStory).
private final class StoryShareViewController: SettingsListViewController {
    private enum Audience {
        case everyone
        case contacts
        case closeFriends
        case selected
    }

    private let media: StoryDraft
    private let caption: String
    private let hours: Int
    private var audience = Audience.everyone
    private var selectedUserIDs = [Int64]()
    /// The people left out under Everyone and Contacts (exceptUserIds).
    private var excludedFromEveryone = [Int64]()
    private var excludedFromContacts = [Int64]()
    /// The account's close friends (getCloseFriends), edited with setCloseFriends.
    private var closeFriendIDs = [Int64]()
    private var firstNames = [Int64: String]()
    private var allowsScreenshots = true
    private var keepsOnPage = true
    private var isPosting = false
    /// ShareWithPeersScreen's sendAsPeers: the account, then the chats it can post stories to.
    private var postAsPeers = [StoryPostAsPeer]()
    /// The chat the story goes to, nil for the account's own.
    private var postAsChatID: Int64?

    private var postAs: StoryPostAsPeer? {
        postAsPeers.first { $0.chatID == postAsChatID }
    }

    private var privacy: TDNativeStoryPrivacySettings {
        switch audience {
        case .everyone:
            .storyPrivacySettingsEveryone(TDNativeStoryPrivacySettingsEveryone(exceptUserIds: excludedFromEveryone))
        case .contacts:
            .storyPrivacySettingsContacts(TDNativeStoryPrivacySettingsContacts(exceptUserIds: excludedFromContacts))
        case .closeFriends: .storyPrivacySettingsCloseFriends
        case .selected:
            .storyPrivacySettingsSelectedUsers(TDNativeStoryPrivacySettingsSelectedUsers(userIds: selectedUserIDs))
        }
    }

    /// ShareWithPeersScreen's count: the stories a long video makes.
    private var storyCount: Int {
        max(1, media.segments.count)
    }

    init(media: StoryDraft, caption: String, hours: Int) {
        self.media = media
        self.caption = caption
        self.hours = hours
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Story.Privacy.ShareStory")
        let client = client
        Task { [weak self] in
            let users = try? await client.send(TDNativeRequests.getCloseFriends())
            guard let self, contextIsCurrent, let users else { return }
            closeFriendIDs = users.userIds
            reload()
        }
        Task { [weak self] in
            let peers = await StoryPostAsPeer.load(client: client)
            guard let self, contextIsCurrent else { return }
            postAsPeers = peers
            reload()
        }
    }

    override func makeSections() -> [SettingsSection] {
        let excluded: ([Int64]) -> String = { ids in
            ids.isEmpty
                ? L10n.telegram("Story.Privacy.ExcludePeople")
                : L10n.telegram("Story.Privacy.ExcludePeopleExceptNames", self.names(ids))
        }
        let audiences: [(Audience, String, String?)] = [
            (.everyone, "Story.Privacy.CategoryEveryone", excluded(excludedFromEveryone)),
            (.contacts, "Story.Privacy.CategoryContacts", excluded(excludedFromContacts)),
            (.closeFriends, "Story.Privacy.CategoryCloseFriends", L10n.telegram("Story.Privacy.EditList")),
            (
                .selected,
                "Story.Privacy.CategorySelectedContacts",
                selectedUserIDs.isEmpty ? L10n.telegram("Story.Privacy.Choose") : names(selectedUserIDs),
            ),
        ]
        var sections = [SettingsSection]()
        // POST STORY AS, once the account can post somewhere else: the chosen peer, opening the list.
        if postAsPeers.count > 1, let postAs {
            sections.append(SettingsSection(
                header: L10n.telegram(storyCount > 1
                    ? "Story.Privacy.PostStoriesAsHeader"
                    : "Story.Privacy.PostStoryAsHeader"),
                rows: [SettingsRow(
                    title: postAs.peer.title,
                    detail: postAs.subtitle,
                    style: .peer(postAs.peer),
                    accessory: .disclosure,
                    isEnabled: !isPosting,
                ) { [weak self] in self?.choosePostAs() }],
            ))
        }
        let pinTitle: String
        let pinFooter: String
        let hoursText = L10n.telegramPlural("Story.Privacy.KeepOnMyPageHours", count: hours)
        if let postAs, postAs.chatID != nil {
            pinTitle = L10n.telegram(postAs.isGroup
                ? "Story.Privacy.KeepOnGroupPage"
                : "Story.Privacy.KeepOnChannelPage")
            let key = postAs.isGroup ? "Story.Privacy.KeepOnGroupPage" : "Story.Privacy.KeepOnChannelPage"
            pinFooter = L10n.telegram(key + (storyCount > 1 ? "ManyInfo" : "Info"), hoursText)
        } else {
            pinTitle = L10n.telegram("Story.Privacy.KeepOnMyPage")
            pinFooter = L10n.telegram(
                storyCount > 1 ? "Story.Privacy.KeepOnMyPageManyInfo" : "Story.Privacy.KeepOnMyPageInfo",
                hoursText,
            )
        }
        // A chat's story is public to it: no categories.
        if postAsChatID == nil {
            sections.append(SettingsSection(
                header: L10n.telegram(storyCount > 1
                    ? "Story.Privacy.WhoCanViewStoriesHeader"
                    : "Story.Privacy.WhoCanViewHeader"),
                rows: audiences.map { audience, key, detail in
                    SettingsRow(
                        title: L10n.telegram(key),
                        detail: detail,
                        style: detail == nil ? .value : .subtitle,
                        accessory: self.audience == audience ? .checkmark : .none,
                        isEnabled: !isPosting,
                    ) { [weak self] in self?.choose(audience) }
                },
            ))
        }
        sections += [
            SettingsSection(
                footer: pinFooter,
                rows: [
                    SettingsRow(
                        title: L10n.telegram("Story.Privacy.AllowScreenshots"),
                        accessory: .toggle(isOn: allowsScreenshots) { [weak self] value in
                            self?.allowsScreenshots = value
                        },
                    ),
                    SettingsRow(
                        title: pinTitle,
                        accessory: .toggle(isOn: keepsOnPage) { [weak self] value in self?.keepsOnPage = value },
                    ),
                ],
            ),
            SettingsSection(rows: [SettingsRow(
                title: storyCount > 1
                    ? L10n.telegramPlural("Story.Privacy.PostStories", count: storyCount)
                    : L10n.telegram("Story.Privacy.PostStory"),
                style: .action(destructive: false),
                accessory: isPosting ? .activity : .none,
                isEnabled: !isPosting,
            ) { [weak self] in self?.post() }]),
        ]
        return sections
    }

    /// presentSendAsPeer: Post Story As, the account and its chats with a check on the chosen one.
    private func choosePostAs() {
        let list = StoryPostAsViewController(peers: postAsPeers, chosenChatID: postAsChatID) { [weak self] chatID in
            guard let self else { return }
            postAsChatID = chatID
            reload()
        }
        navigationController?.pushViewController(list, animated: true)
    }

    /// ShareWithPeersScreen's category subtitles: exclude people or except the names, edit list, choose or the names.
    private func names(_ ids: [Int64]) -> String {
        ids.compactMap { firstNames[$0] }.joined(separator: ", ")
    }

    /// A tap chooses the category; on the chosen one it opens its list (Telegram's subtitle link): the people to
    /// leave out, the close friends or the selected contacts. Selected Contacts opens it at once while empty.
    private func choose(_ audience: Audience) {
        guard self.audience == audience || audience == .selected && selectedUserIDs.isEmpty else {
            self.audience = audience
            reload()
            return
        }
        let current: [Int64]
        let title: String
        switch audience {
        case .contacts,
             .everyone:
            current = audience == .everyone ? excludedFromEveryone : excludedFromContacts
            title = L10n.telegram("Story.Privacy.ExcludedPeople")
        case .closeFriends:
            current = closeFriendIDs
            title = L10n.telegram("Story.Privacy.CategoryCloseFriends")
        case .selected:
            current = selectedUserIDs
            title = L10n.telegram("Story.Privacy.CategorySelectedContacts")
        }
        let picker = SettingsPeerPickerViewController(excludedUserIDs: [], excludedChatIDs: [])
        picker.listsOnlyPeople = true
        picker.pickerTitle = title
        picker.initiallySelectedUserIDs = current
        picker.allowsEmptySelection = audience != .selected
        picker.onDone = { [weak self] userIDs, _ in self?.applyList(userIDs, to: audience) }
        present(TelegramNavigationController(rootViewController: picker), animated: true)
    }

    private func applyList(_ userIDs: [Int64], to audience: Audience) {
        switch audience {
        case .everyone: excludedFromEveryone = userIDs
        case .contacts: excludedFromContacts = userIDs
        case .closeFriends:
            // setCloseFriends: the list belongs to the account, not to this story.
            closeFriendIDs = userIDs
            let client = client
            Task { _ = try? await client.send(TDNativeRequests.setCloseFriends(userIds: userIDs)) }
        case .selected:
            selectedUserIDs = userIDs
            if !userIDs.isEmpty { self.audience = .selected }
        }
        reload()
        loadNames(userIDs)
    }

    private func loadNames(_ ids: [Int64]) {
        let missing = ids.filter { firstNames[$0] == nil }
        guard !missing.isEmpty else { return }
        let client = client
        Task { [weak self] in
            var found = [Int64: String]()
            for id in missing {
                guard let user = try? await client.getUser(userId: id) else { continue }
                found[id] = user.firstName.isEmpty ? user.lastName : user.firstName
            }
            guard let self, contextIsCurrent else { return }
            firstNames.merge(found) { $1 }
            reload()
        }
    }

    /// The story for postStory from the account's Saved Messages, active for the chosen hours.
    private func post() {
        guard !isPosting, contextIsCurrent, let ownID = TDLib.shared.activeAccount?.userID else { return }
        let chatID = postAsChatID ?? ownID
        isPosting = true
        reload()
        let client = client
        let privacy = privacy
        let caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let keepsOnPage = keepsOnPage
        let allowsScreenshots = allowsScreenshots
        let activePeriod = hours * 3600
        let media = media
        // Telegram's editor hands the story to its upload and closes: the export and the post go on behind the chat
        // list, whose story item shows the upload ring meanwhile.
        weak let presenter = navigationController?.presentingViewController
        let preparing = StoryPosting.shared.begin(chatID)
        navigationController?.dismiss(animated: true)
        Task { @MainActor in
            defer { StoryPosting.shared.end(preparing) }
            do {
                // A long video goes as a minute a story, the caption on the first (MediaEditorStoryCompletion).
                let parts = media.segments.count > 1 ? media.segments.map { media.withRange($0) } : [media]
                for (index, part) in parts.enumerated() {
                    let content = try await part.content()
                    let text = index == 0 ? caption : ""
                    _ = try await client.send(TDNativeRequests.postStory(
                        chatId: chatID,
                        content: content,
                        areas: nil,
                        caption: text.isEmpty ? nil : FormattedText(entities: [], text: text),
                        privacySettings: privacy,
                        albumIds: [],
                        activePeriod: activePeriod,
                        fromStoryFullId: nil,
                        isPostedToChatPage: keepsOnPage,
                        protectContent: !allowsScreenshots,
                    ))
                }
            } catch {
                guard let presenter, presenter.presentedViewController == nil else { return }
                let alert = UIAlertController(
                    title: nil,
                    message: ChatManagementRows.failureText(error),
                    preferredStyle: .alert,
                )
                alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
                presenter.present(alert, animated: true)
            }
        }
    }
}

// MARK: - StoryPostAsPeer

/// One of ShareWithPeersScreen's sendAsPeers: the account (personal account) or a chat it can post stories to, with
/// its subscribers or members.
private struct StoryPostAsPeer {
    let chatID: Int64?
    let peer: SettingsPeer
    let subtitle: String
    let isGroup: Bool

    /// The account, then getChatsToPostStories' chats.
    @MainActor static func load(client: TDLibClient) async -> [StoryPostAsPeer] {
        guard let ownID = TDLib.shared.activeAccount?.userID,
              let me = await SettingsPeer.user(ownID, client: client)
        else { return [] }
        var peers = [StoryPostAsPeer(
            chatID: nil,
            peer: me,
            subtitle: L10n.telegram("VoiceChat.PersonalAccount"),
            isGroup: false,
        )]
        let chats = try? await client.send(TDNativeRequests.getChatsToPostStories())
        for id in chats?.chatIds ?? [] {
            guard let chat = try? await client.getChat(chatId: id) else { continue }
            var isGroup = true
            var count = 0
            if case .chatTypeSupergroup(let type) = chat.type {
                isGroup = !type.isChannel
                count = await (try? client.getSupergroup(supergroupId: type.supergroupId))?.memberCount ?? 0
            }
            let subtitle = count > 0
                ? L10n.telegramPlural(
                    isGroup ? "Conversation.StatusMembers" : "Conversation.StatusSubscribers",
                    count: count,
                )
                : L10n.telegram(isGroup ? "Group.Status" : "Channel.Status")
            peers.append(StoryPostAsPeer(
                chatID: id,
                peer: SettingsPeer(chat: chat),
                subtitle: subtitle,
                isGroup: isGroup,
            ))
        }
        return peers
    }
}

// MARK: - StoryPostAsViewController

/// ShareWithPeersScreen's peers subject, Post Story As: the account first, a check on the chosen one. The account is
/// chosen at once; a chat after checkStoriesUploadAvailability (canPostStory) allows it, and a chat that needs boosts
/// opens its boost levels instead.
private final class StoryPostAsViewController: SettingsListViewController {
    private let peers: [StoryPostAsPeer]
    private let chosenChatID: Int64?
    private let onChoose: (Int64?) -> Void
    private var checkingChatID: Int64?

    init(peers: [StoryPostAsPeer], chosenChatID: Int64?, onChoose: @escaping (Int64?) -> Void) {
        self.peers = peers
        self.chosenChatID = chosenChatID
        self.onChoose = onChoose
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Story.Privacy.PostStoryAs")
    }

    override func makeSections() -> [SettingsSection] {
        [SettingsSection(rows: peers.map { peer in
            SettingsRow(
                title: peer.peer.title,
                detail: peer.subtitle,
                style: .peer(peer.peer),
                accessory: checkingChatID != nil && checkingChatID == peer.chatID
                    ? .activity
                    : peer.chatID == chosenChatID ? .checkmark : .none,
                isEnabled: checkingChatID == nil,
            ) { [weak self] in self?.choose(peer) }
        })]
    }

    private func choose(_ peer: StoryPostAsPeer) {
        guard let chatID = peer.chatID else {
            finish(nil)
            return
        }
        checkingChatID = chatID
        reload()
        let client = client
        Task { [weak self] in
            let result = try? await client.send(TDNativeRequests.canPostStory(chatId: chatID))
            guard let self, contextIsCurrent else { return }
            checkingChatID = nil
            reload()
            switch result {
            case .canPostStoryResultOk:
                finish(chatID)
            case .canPostStoryResultBoostNeeded:
                guard let chat = try? await client.getChat(chatId: chatID), contextIsCurrent else { return }
                navigationController?.pushViewController(
                    BoostLevelsViewController(chat: chat, isAdmin: true, client: client),
                    animated: true,
                )
            default:
                break
            }
        }
    }

    private func finish(_ chatID: Int64?) {
        onChoose(chatID)
        navigationController?.popViewController(animated: true)
    }
}

// MARK: - StoryPosting

/// Stories still exporting or waiting for postStory after Share Story closed, by the chat they go to, so its story
/// item shows the upload ring until TDLib's is_being_posted takes over.
@MainActor final class StoryPosting {
    static let shared = StoryPosting()

    @Published private(set) var preparingChatIDs = [UUID: Int64]()

    func begin(_ chatID: Int64) -> UUID {
        let id = UUID()
        preparingChatIDs[id] = chatID
        return id
    }

    func end(_ id: UUID) {
        preparingChatIDs[id] = nil
    }
}

// MARK: - StoryVideoWriter

/// MediaEditorVideoExport's reader and writer: the composed frames and the sound read over the range and written to a
/// streamable MPEG-4, the sound as AAC at 44.1 kHz and 320 kbps in stereo.
private final class StoryVideoWriter: @unchecked Sendable {
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let pairs: [(AVAssetReaderOutput, AVAssetWriterInput)]
    private let queue = DispatchQueue(label: "bettertg.story.export")

    private init(reader: AVAssetReader, writer: AVAssetWriter, pairs: [(AVAssetReaderOutput, AVAssetWriterInput)]) {
        self.reader = reader
        self.writer = writer
        self.pairs = pairs
    }

    static func write(
        asset: AVAsset,
        videoTrack: AVAssetTrack,
        audioTracks: [AVAssetTrack],
        composition: AVVideoComposition,
        timeRange: CMTimeRange,
        videoSettings: [String: Any],
        to url: URL,
    ) async throws {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = timeRange
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        var pairs = [(AVAssetReaderOutput, AVAssetWriterInput)]()
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA],
        )
        videoOutput.videoComposition = composition
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        pairs.append((videoOutput, videoInput))
        if !audioTracks.isEmpty {
            let audioOutput = AVAssetReaderAudioMixOutput(
                audioTracks: audioTracks,
                audioSettings: [AVFormatIDKey: kAudioFormatLinearPCM],
            )
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: 64 * 5 * 1000,
                AVNumberOfChannelsKey: 2,
            ])
            audioInput.expectsMediaDataInRealTime = false
            pairs.append((audioOutput, audioInput))
        }
        for (output, input) in pairs {
            guard reader.canAdd(output), writer.canAdd(input) else { throw StoryVideoExport.Failure() }
            reader.add(output)
            writer.add(input)
        }
        let job = StoryVideoWriter(reader: reader, writer: writer, pairs: pairs)
        try await job.run(from: timeRange.start)
    }

    private func run(from start: CMTime) async throws {
        guard reader.startReading(), writer.startWriting() else { throw StoryVideoExport.Failure() }
        writer.startSession(atSourceTime: start)
        await withTaskGroup(of: Void.self) { group in
            for index in pairs.indices {
                group.addTask { await self.pump(index) }
            }
        }
        if reader.status == .failed || writer.status == .failed {
            writer.cancelWriting()
            throw writer.error ?? reader.error ?? StoryVideoExport.Failure()
        }
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? StoryVideoExport.Failure() }
    }

    /// Copies the output's samples into the input as it takes them, then marks the input finished.
    private func pump(_ index: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pairs[index].1.requestMediaDataWhenReady(on: queue) {
                let (output, input) = self.pairs[index]
                while input.isReadyForMoreMediaData {
                    guard let sample = output.copyNextSampleBuffer(), input.append(sample) else {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
    }
}
