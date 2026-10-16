// PhotoCropProbe.swift

#if DEBUG
    import UIKit

    /// Launch with `-ui-probe-photo-crop`, or `-ui-probe-photo-tools` for the Tools tab. Once an account is active it
    /// opens the attachment sheet's photo editor on a drawn 1600×1200 test photo, so the editor is checked without
    /// photo library access; the tools' photo adds a black-to-white strip for Highlights, Shadows, Fade and Curves.
    /// After `-ui-probe-photo-tools`, `blur` opens Blur with a radial blur already on, `linear` with a turned linear
    /// one, and `curves` opens Curves with the photo's histogram. Done shows the photo as it would be sent, with its
    /// crop and tools rendered at the standard 1280 px; nothing is sent.
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

        private static let photoSize = CGSize(width: 1600, height: 1200)

        static func runIfRequested(in window: UIWindow) {
            let arguments = ProcessInfo.processInfo.arguments
            let toolsIndex = arguments.firstIndex(of: "-ui-probe-photo-tools")
            let opensTools = toolsIndex != nil
            guard opensTools || arguments.contains("-ui-probe-photo-crop") else { return }
            let toolsOption = toolsIndex.flatMap { arguments[safe: $0 + 1] }
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
                let photo = makePhoto(withStrip: opensTools)
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
    }
#endif
