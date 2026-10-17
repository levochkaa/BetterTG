// PhotoCropProbe.swift

#if DEBUG
    import AVFoundation
    import UIKit

    /// Launch with `-ui-probe-photo-crop`, or `-ui-probe-photo-tools` for the Tools tab. Once an account is active it
    /// opens the attachment sheet's photo editor on a drawn 1600×1200 test photo, so the editor is checked without
    /// photo library access; the tools' photo adds a black-to-white strip for Highlights, Shadows, Fade and Curves.
    /// After `-ui-probe-photo-tools`, `blur` opens Blur with a radial blur already on, `linear` with a turned linear
    /// one, and `curves` opens Curves with the photo's histogram. Done shows the photo as it would be sent, with its
    /// crop and tools rendered at the standard 1280 px; nothing is sent.
    /// `-ui-probe-photo-crop auto` opens the crop on a sea horizon rising 8° to the right, for AUTO. A few seconds
    /// in it logs the angle Vision found, or gives AUTO the drawn tilt when Vision found none.
    /// `-ui-probe-photo-crop live` opens the crop on a Live Photo's still: the first frame of a generated six-second
    /// motion with a tone, scaled to 1920×1080 because a library Live Photo's still is larger than its motion. Done
    /// writes the still and converts the motion as the attachment sheet sends a Live Photo in Live mode
    /// (`livePhotoConversion`, then `VideoSendTranscoder` as `VideoSendGenerationCoordinator` runs it), and shows
    /// the still above the converted motion's first frame, so their crops can be compared; nothing is sent.
    @MainActor enum PhotoCropProbe {
        /// The rendered photo with its pixel size, closed by Close.
        private final class ResultViewController: UIViewController {
            private let image: UIImage
            private let isEdited: Bool

            init(image: UIImage, isEdited: Bool) {
                self.image = image
                self.isEdited = isEdited
                super.init(nibName: nil, bundle: nil)
                modalPresentationStyle = .fullScreen
            }

            @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

            override func viewDidLoad() {
                super.viewDidLoad()
                view.backgroundColor = .black
                let imageView = UIImageView(image: image)
                imageView.contentMode = .scaleAspectFit
                let label = UILabel()
                label.textColor = .white
                label.textAlignment = .center
                label.text = "\(isEdited ? "edited" : "whole") \(Int(image.size.width))×\(Int(image.size.height))"
                let close = UIButton(type: .system, primaryAction: UIAction(title: "Close") { [weak self] _ in
                    self?.dismiss(animated: true)
                })
                for subview in [imageView, label, close] as [UIView] {
                    subview.translatesAutoresizingMaskIntoConstraints = false
                    view.addSubview(subview)
                }
                let guide = view.safeAreaLayoutGuide
                NSLayoutConstraint.activate([
                    close.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
                    close.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
                    label.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 8),
                    label.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
                    imageView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
                    imageView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
                    imageView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
                    imageView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
                ])
            }
        }

        /// The written still above the converted motion's first frame, with their sizes and the conversion, closed by
        /// Close.
        private final class LivePhotoResultViewController: UIViewController {
            private let label = UILabel()
            private let stillView = UIImageView()
            private let motionView = UIImageView()

            var text: String {
                get { label.text ?? "" }
                set { label.text = newValue }
            }

            var still: UIImage? {
                get { stillView.image }
                set { stillView.image = newValue }
            }

            var motionFrame: UIImage? {
                get { motionView.image }
                set { motionView.image = newValue }
            }

            init() {
                super.init(nibName: nil, bundle: nil)
                modalPresentationStyle = .fullScreen
            }

            @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

            override func viewDidLoad() {
                super.viewDidLoad()
                view.backgroundColor = .black
                label.textColor = .white
                label.textAlignment = .center
                label.numberOfLines = 0
                label.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
                for imageView in [stillView, motionView] {
                    imageView.contentMode = .scaleAspectFit
                    imageView.backgroundColor = UIColor(white: 0.12, alpha: 1)
                }
                let images = UIStackView(arrangedSubviews: [stillView, motionView])
                images.axis = .vertical
                images.spacing = 8
                images.distribution = .fillEqually
                let close = UIButton(type: .system, primaryAction: UIAction(title: "Close") { [weak self] _ in
                    self?.dismiss(animated: true)
                })
                for subview in [images, label, close] as [UIView] {
                    subview.translatesAutoresizingMaskIntoConstraints = false
                    view.addSubview(subview)
                }
                let guide = view.safeAreaLayoutGuide
                NSLayoutConstraint.activate([
                    close.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
                    close.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
                    label.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 8),
                    label.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
                    label.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
                    images.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 12),
                    images.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
                    images.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
                    images.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -8),
                ])
            }
        }

        private static let photoSize = CGSize(width: 1600, height: 1200)
        /// The horizon photo's tilt, inside the ±10° Vision finds a horizon in; leveling it is this turn clockwise.
        private static let horizonTilt: CGFloat = 8 * .pi / 180
        /// The Live Photo still's size: the 1280×720 motion's shape, larger as a library still is.
        private static let liveStillSize = CGSize(width: 1920, height: 1080)

        static func runIfRequested(in window: UIWindow) {
            let arguments = ProcessInfo.processInfo.arguments
            let toolsIndex = arguments.firstIndex(of: "-ui-probe-photo-tools")
            let cropIndex = arguments.firstIndex(of: "-ui-probe-photo-crop")
            let opensTools = toolsIndex != nil
            guard opensTools || cropIndex != nil else { return }
            let toolsOption = toolsIndex.flatMap { arguments[safe: $0 + 1] }
            let cropOption = opensTools ? nil : cropIndex.flatMap { arguments[safe: $0 + 1] }
            let opensAuto = cropOption == "auto"
            let opensLive = cropOption == "live"
            Task { @MainActor in
                for _ in 0..<60 where TDLib.shared.activeAccountID == nil {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                guard TDLib.shared.activeAccountID != nil else { return }
                try? await Task.sleep(for: .seconds(2))
                var presenter = window.rootViewController
                while let presented = presenter?.presentedViewController {
                    presenter = presented
                }
                guard let presenter else { return }
                if opensLive {
                    await presentLivePhoto(from: presenter)
                    return
                }
                let photo = opensAuto ? makeHorizonPhoto() : makePhoto(withStrip: opensTools)
                let preset = toolsPreset(for: toolsOption)
                let editor = PhotoCropViewController(
                    image: photo,
                    adjustments: preset.adjustments,
                    initialTab: opensTools ? .tools : .crop,
                    initialToolsTab: preset.tab,
                )
                editor.onDone = { [weak presenter] edit in
                    let result = edit?.adjustments.renderEdited(photo, sourcePixelSize: photoSize, maximumSide: 1280)
                    // The editor dismisses itself right after handing back the edit.
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        presenter?.present(
                            ResultViewController(image: result ?? photo, isEdited: edit != nil),
                            animated: true,
                        )
                    }
                }
                presenter.present(editor, animated: true)
                if opensAuto {
                    try? await Task.sleep(for: .seconds(3))
                    reportAutoRotation(of: editor)
                }
            }
        }

        /// Vision's angle for AUTO, or the drawn tilt when Vision found none, so AUTO shows either way.
        private static func reportAutoRotation(of editor: PhotoCropViewController) {
            let drawn = Double(horizonTilt * 180 / .pi)
            guard editor.autoRotationAngle == 0 else {
                let found = Double(editor.autoRotationAngle * 180 / .pi)
                log(String(
                    format: "Photo crop probe: AUTO turns %.2f° clockwise; the horizon rises %.2f°",
                    found,
                    drawn,
                ))
                return
            }
            log(String(format: "Photo crop probe: Vision found no horizon; AUTO turns the drawn %.2f°", drawn))
            editor.setAutoRotationAngle(horizonTilt)
        }

        // MARK: - Live Photo

        /// The crop on the Live Photo's still; Done writes the still and converts the motion as they would be sent.
        private static func presentLivePhoto(from presenter: UIViewController) async {
            let motion: URL
            let still: UIImage
            do {
                motion = try await Task.detached(priority: .userInitiated) { () async throws -> URL in
                    try await ProbeVideo.make(
                        seconds: ProbeVideo.seconds,
                        frameRate: ProbeVideo.frameRate,
                        named: "bettertg-live-photo-probe.mov",
                    )
                }.value
                still = try await makeLiveStill(of: motion)
            } catch {
                log("Photo crop probe could not write its Live Photo: \(error)")
                return
            }
            let editor = PhotoCropViewController(image: still, adjustments: nil)
            editor.onDone = { [weak presenter] edit in
                // The editor dismisses itself right after handing back the edit.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    let result = LivePhotoResultViewController()
                    result.text = "writing the still…"
                    presenter?.present(result, animated: true)
                    let crop = edit?.adjustments
                    guard let selection = await writeLiveSelection(still: still, motion: motion, crop: crop) else {
                        result.text = "the still could not be written"
                        return
                    }
                    result.still = UIImage(contentsOfFile: selection.url.path(percentEncoded: false))
                    let summary = describeLive(selection, still: result.still, crop: crop)
                    result.text = summary + "\n\nconverting the motion…"
                    let converted = await convertMotion(of: selection)
                    result.motionFrame = converted.frame
                    result.text = summary + "\n" + converted.summary
                    log("Photo crop probe Live Photo: " + result.text.replacingOccurrences(of: "\n", with: "; "))
                    SelectedDocumentFileStore.remove([selection.url])
                }
            }
            presenter.present(editor, animated: true)
        }

        /// The motion's first frame scaled up to `liveStillSize`.
        private static func makeLiveStill(of motion: URL) async throws -> UIImage {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: motion))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let frame = try await generator.image(at: .zero).image
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: liveStillSize, format: format).image { _ in
                UIImage(cgImage: frame).draw(in: CGRect(origin: .zero, size: liveStillSize))
            }
        }

        /// The item PhotoAssetSelectionLoader's Live mode makes: the still written with the editor's crop and tools at
        /// the standard 1280 px, with the motion and the crop its conversion takes.
        private static func writeLiveSelection(
            still: UIImage,
            motion: URL,
            crop: PhotoCropAdjustments?,
        ) async -> SelectedImage? {
            guard let data = still.jpegData(compressionQuality: 0.95) else { return nil }
            let written = await Task.detached(priority: .userInitiated) { () -> SelectedImage? in
                guard let crop else { return writeImage(data: data, maximumSide: PhotoSendPreset.maximumSide) }
                return writeImage(data: data, cropping: crop, maximumSide: PhotoSendPreset.maximumSide)
            }.value
            guard var selection = written else { return nil }
            selection.livePhotoVideoURL = motion
            selection.livePhotoCrop = crop
            return selection
        }

        private static func describeLive(
            _ selection: SelectedImage,
            still: UIImage?,
            crop: PhotoCropAdjustments?,
        ) -> String {
            var lines = [String]()
            let stillSize = still.map { "\(Int($0.size.width * $0.scale))×\(Int($0.size.height * $0.scale))" }
            let sourceSize = "\(Int(liveStillSize.width))×\(Int(liveStillSize.height))"
            lines.append("still \(stillSize ?? "unreadable") from \(sourceSize)")
            if let crop, !crop.hasDefaultCropping {
                let rect = crop.cropRect
                lines.append(
                    "crop \(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height))"
                        + " of \(Int(crop.originalSize.width))×\(Int(crop.originalSize.height))"
                        + ", turned \(crop.orientation)" + (crop.isMirrored ? ", mirrored" : "")
                        + String(format: ", straightened %.2f°", Double(crop.rotation * 180 / .pi)),
                )
            } else {
                lines.append("uncropped")
            }
            if let crop, !crop.tools.isDefault {
                lines.append("tools on the still only")
            }
            lines.append(selection.livePhotoConversion)
            return lines.joined(separator: "\n")
        }

        /// The motion as `VideoSendGenerationCoordinator` converts it for TDLib, read back with its first frame.
        private static func convertMotion(of selection: SelectedImage) async -> (frame: UIImage?, summary: String) {
            guard let motion = selection.livePhotoVideoURL,
                  let conversion = VideoEditAdjustments.parse(conversion: selection.livePhotoConversion)
            else { return (nil, "the conversion could not be read") }
            let directory = FileManager.default.temporaryDirectory
            let destination = directory.appendingPathComponent("bettertg-live-photo-probe-sent.mp4")
            let transcoder = VideoSendTranscoder(preset: conversion.preset, edit: conversion.edit)
            do {
                try await transcoder.transcode(from: motion, to: destination) { _ in }
                let output = AVURLAsset(url: destination)
                let duration = try await output.load(.duration).seconds
                let size = try await output.loadTracks(withMediaType: .video).first?.load(.naturalSize) ?? .zero
                let hasAudio = try await !output.loadTracks(withMediaType: .audio).isEmpty
                let generator = AVAssetImageGenerator(asset: output)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
                let frame = try? await generator.image(at: .zero).image
                let summary = String(format: "motion %.2f s, %d×%d", duration, Int(size.width), Int(size.height))
                    + (hasAudio ? ", with sound" : ", no sound")
                return (frame.map { UIImage(cgImage: $0) }, summary)
            } catch {
                return (nil, "motion conversion failed: \(error)")
            }
        }

        /// The tools panel and the edit the editor opens with for the option after `-ui-probe-photo-tools`.
        private static func toolsPreset(for option: String?)
            -> (tab: PhotoToolsTab, adjustments: PhotoCropAdjustments?)
        {
            var adjustments = PhotoCropAdjustments(originalSize: photoSize)
            switch option {
            case "blur":
                adjustments.tools.blur.type = .radial
                adjustments.tools.blur.point = CGPoint(x: 0.4, y: 0.45)
                return (.blur, adjustments)
            case "linear":
                adjustments.tools.blur.type = .linear
                adjustments.tools.blur.angle = -.pi / 6
                return (.blur, adjustments)
            case "curves":
                return (.curves, nil)
            default:
                return (.list, nil)
            }
        }

        /// Four colored quadrants with a grid and their corner names, so a crop, a turn or a mirror shows in the
        /// result; `withStrip` adds a black-to-white strip along the bottom, so the tones the tools change show.
        private static func makePhoto(withStrip: Bool) -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: photoSize, format: format).image { context in
                let half = CGSize(width: photoSize.width / 2, height: photoSize.height / 2)
                let quadrants: [(UIColor, CGPoint, String)] = [
                    (.systemRed, .zero, "TL"),
                    (.systemGreen, CGPoint(x: half.width, y: 0), "TR"),
                    (.systemBlue, CGPoint(x: 0, y: half.height), "BL"),
                    (.systemOrange, CGPoint(x: half.width, y: half.height), "BR"),
                ]
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 160),
                    .foregroundColor: UIColor.white,
                ]
                for (color, origin, name) in quadrants {
                    color.setFill()
                    context.fill(CGRect(origin: origin, size: half))
                    let text = name as NSString
                    let size = text.size(withAttributes: attributes)
                    text.draw(
                        at: CGPoint(
                            x: origin.x + (half.width - size.width) / 2,
                            y: origin.y + (half.height - size.height) / 2,
                        ),
                        withAttributes: attributes,
                    )
                }
                UIColor.white.withAlphaComponent(0.6).setFill()
                for x in stride(from: CGFloat(0), through: photoSize.width, by: 100) {
                    context.fill(CGRect(x: x - 1, y: 0, width: 2, height: photoSize.height))
                }
                for y in stride(from: CGFloat(0), through: photoSize.height, by: 100) {
                    context.fill(CGRect(x: 0, y: y - 1, width: photoSize.width, height: 2))
                }
                guard withStrip,
                      let gradient = CGGradient(
                          colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [UIColor.black.cgColor, UIColor.white.cgColor] as CFArray,
                          locations: [0, 1],
                      )
                else { return }
                let strip = CGRect(x: 0, y: photoSize.height - 150, width: photoSize.width, height: 150)
                context.cgContext.saveGState()
                context.cgContext.clip(to: strip)
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: strip.minX, y: strip.midY),
                    end: CGPoint(x: strip.maxX, y: strip.midY),
                    options: [],
                )
                context.cgContext.restoreGState()
            }
        }

        /// Sky over dark water with waves along a horizon rising `horizonTilt` to the right.
        private static func makeHorizonPhoto() -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: photoSize, format: format).image { context in
                let canvas = context.cgContext
                canvas.translateBy(x: photoSize.width / 2, y: photoSize.height / 2)
                // Counterclockwise on screen, so the horizon rises to the right.
                canvas.rotate(by: -horizonTilt)
                let side: CGFloat = 2400
                let sky = CGRect(x: -side / 2, y: -side / 2, width: side, height: side / 2)
                let skyColors = [
                    UIColor(red: 0.25, green: 0.5, blue: 0.9, alpha: 1).cgColor,
                    UIColor(red: 0.85, green: 0.92, blue: 1, alpha: 1).cgColor,
                ]
                if let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: skyColors as CFArray,
                    locations: [0, 1],
                ) {
                    canvas.saveGState()
                    canvas.clip(to: sky)
                    canvas.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: 0, y: sky.minY),
                        end: CGPoint(x: 0, y: sky.maxY),
                        options: [],
                    )
                    canvas.restoreGState()
                }
                UIColor(red: 0.05, green: 0.2, blue: 0.35, alpha: 1).setFill()
                canvas.fill(CGRect(x: -side / 2, y: 0, width: side, height: side / 2))
                UIColor(red: 0.3, green: 0.5, blue: 0.65, alpha: 0.5).setFill()
                for y in stride(from: CGFloat(40), to: side / 2, by: 37) {
                    canvas.fill(CGRect(x: -side / 2, y: y, width: side, height: 3))
                }
            }
        }
    }
#endif
