// PhotoCropProbe.swift

#if DEBUG
    import UIKit

    /// Launch with `-ui-probe-photo-crop`. Once an account is active it opens the attachment sheet's crop editor on
    /// a drawn 1600×1200 test photo, so the editor is checked without photo library access. Done shows the photo as
    /// it would be sent, rendered at the standard 1280 px; nothing is sent.
    @MainActor enum PhotoCropProbe {
        /// The rendered photo with its pixel size, closed by Close.
        private final class ResultViewController: UIViewController {
            private let image: UIImage
            private let isCropped: Bool

            init(image: UIImage, isCropped: Bool) {
                self.image = image
                self.isCropped = isCropped
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
                label.text = "\(isCropped ? "cropped" : "whole") \(Int(image.size.width))×\(Int(image.size.height))"
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
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-photo-crop") else { return }
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
                let photo = makePhoto()
                let editor = PhotoCropViewController(image: photo, adjustments: nil)
                editor.onDone = { [weak presenter] edit in
                    let result = edit?.adjustments.render(photo, sourcePixelSize: photoSize, maximumSide: 1280)
                    // The editor dismisses itself right after handing back the edit.
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        presenter?.present(
                            ResultViewController(image: result ?? photo, isCropped: edit != nil),
                            animated: true,
                        )
                    }
                }
                presenter.present(editor, animated: true)
            }
        }

        /// Four colored quadrants with a grid and their corner names, so a crop, a turn or a mirror shows in the
        /// result.
        private static func makePhoto() -> UIImage {
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
            }
        }
    }
#endif
