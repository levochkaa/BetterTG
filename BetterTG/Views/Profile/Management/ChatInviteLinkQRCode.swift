// ChatInviteLinkQRCode.swift

import CoreImage
import CoreImage.CIFilterBuiltins
import Lottie
import UIKit

// MARK: - TelegramQRCode

/// Telegram's qrCode(string:color:backgroundColor:icon:ecl:): black modules on white that round off where they have
/// no neighbor and fill the inner corners between neighbors, rounded finder markers, and an empty square in the
/// middle for Telegram's logo.
enum TelegramQRCode {
    struct Rendered {
        let image: UIImage
        /// The empty middle square in the image's points.
        let cutout: CGRect
    }

    private static let context = CIContext()

    static func render(_ string: String, side: CGFloat, scale: CGFloat) -> Rendered? {
        guard let data = string.data(using: .isoLatin1, allowLossyConversion: false) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let generated = context.createCGImage(output, from: output.extent) else { return nil }
        let size = generated.width
        guard size > 0, generated.height == size else { return nil }
        var pixels = [UInt8](repeating: 255, count: size * size)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let bitmap = CGContext(
                data: buffer.baseAddress,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue,
            ) else { return false }
            bitmap.interpolationQuality = .none
            bitmap.draw(generated, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { return nil }
        let modules = pixels.map { $0 < 128 }

        // qrCodeCutout: an odd number of modules near 30% of the code, at most 23.
        var cutoutSize = Int((CGFloat(size) * 0.297).rounded())
        if size == 39 {
            cutoutSize = 11
        } else if cutoutSize % 2 == 0 {
            cutoutSize += 1
        }
        cutoutSize = min(23, cutoutSize)
        let quad = floor(side / CGFloat(size) * scale) / scale
        let cutoutSide = quad * CGFloat(cutoutSize - 2)
        let cutoutOrigin = floor((side - cutoutSide) / 2 * scale) / scale
        let cutoutRect = CGRect(x: cutoutOrigin, y: cutoutOrigin, width: cutoutSide, height: cutoutSide)
        let padding = ((side - quad * CGFloat(size)) / 2 * scale).rounded() / scale
        let start = (size - cutoutSize) / 2
        let end = start + cutoutSize - 1

        func value(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, x < size, y >= 0, y < size else { return false }
            if x > start, x < end, y > start, y < end { return false }
            return modules[y * size + x]
        }

        var markerSize = 0
        for i in 1..<size where !value(i, 1) {
            markerSize = i - 1
            break
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let c = context.cgContext
            UIColor.white.setFill()
            c.fill(CGRect(x: 0, y: 0, width: side, height: side))
            UIColor.black.setFill()
            UIColor.black.setStroke()
            for y in 0..<size {
                for x in 0..<size {
                    let inMarker = (y < markerSize + 1 && (x < markerSize + 1 || x > size - markerSize - 2))
                        || (y > size - markerSize - 2 && x < markerSize + 1)
                    if inMarker { continue }
                    let rect = CGRect(
                        x: padding + CGFloat(x) * quad,
                        y: padding + CGFloat(y) * quad,
                        width: quad,
                        height: quad,
                    )
                    if value(x, y) {
                        var corners = UIRectCorner.allCorners
                        if value(x, y - 1) { corners.subtract([.topLeft, .topRight]) }
                        if value(x, y + 1) { corners.subtract([.bottomLeft, .bottomRight]) }
                        if value(x - 1, y) { corners.subtract([.topLeft, .bottomLeft]) }
                        if value(x + 1, y) { corners.subtract([.topRight, .bottomRight]) }
                        UIBezierPath(
                            roundedRect: rect,
                            byRoundingCorners: corners,
                            cornerRadii: CGSize(width: quad / 3, height: quad / 3),
                        ).fill()
                    } else {
                        // An empty module between three filled ones fills its corner up to a rounded hole.
                        let half = quad / 2
                        let quadrants: [(UIRectCorner, CGRect, Bool)] = [
                            (
                                .topLeft,
                                CGRect(x: rect.minX, y: rect.minY, width: half, height: half),
                                value(x - 1, y - 1) && value(x - 1, y) && value(x, y - 1),
                            ),
                            (
                                .topRight,
                                CGRect(x: rect.midX, y: rect.minY, width: half, height: half),
                                value(x + 1, y - 1) && value(x + 1, y) && value(x, y - 1),
                            ),
                            (
                                .bottomLeft,
                                CGRect(x: rect.minX, y: rect.midY, width: half, height: half),
                                value(x - 1, y + 1) && value(x - 1, y) && value(x, y + 1),
                            ),
                            (
                                .bottomRight,
                                CGRect(x: rect.midX, y: rect.midY, width: half, height: half),
                                value(x + 1, y + 1) && value(x + 1, y) && value(x, y + 1),
                            ),
                        ]
                        for (_, quadrant, filled) in quadrants where filled {
                            c.saveGState()
                            c.clip(to: quadrant)
                            let path = UIBezierPath(rect: quadrant)
                            path.append(UIBezierPath(
                                roundedRect: rect,
                                byRoundingCorners: .allCorners,
                                cornerRadii: CGSize(width: quad / 4, height: quad / 4),
                            ))
                            path.usesEvenOddFillRule = true
                            path.fill()
                            c.restoreGState()
                        }
                    }
                }
            }

            c.translateBy(x: padding, y: padding)
            c.setLineWidth(quad)
            let markerSide = floor(CGFloat(markerSize - 1) * quad * 1.05 * scale) / scale
            func drawMarker(x: CGFloat, y: CGFloat) {
                c.addPath(UIBezierPath(
                    roundedRect: CGRect(x: x + quad / 2, y: y + quad / 2, width: markerSide, height: markerSide),
                    cornerRadius: markerSide / 3.5,
                ).cgPath)
                c.strokePath()
                let dotSide = markerSide - quad * 3
                c.addPath(UIBezierPath(
                    roundedRect: CGRect(x: x + quad * 2, y: y + quad * 2, width: dotSide, height: dotSide),
                    cornerRadius: dotSide / 3.5,
                ).cgPath)
                c.fillPath()
            }
            drawMarker(x: quad, y: quad)
            drawMarker(x: CGFloat(size - 2) * quad - markerSide, y: quad)
            drawMarker(x: quad, y: CGFloat(size - 2) * quad - markerSide)
        }
        return Rendered(image: image, cutout: cutoutRect)
    }
}

// MARK: - ChatInviteLinkQRCodeViewController

/// Telegram's QrCodeScreen for an invite link: Invite by QR Code over the code on a white card with Telegram's
/// animated plane in its middle, who can scan it, and Share QR Code, which shares the code as a 768-point image.
final class ChatInviteLinkQRCodeViewController: UIViewController {
    private static let topInset: CGFloat = 38
    private static let qrSide: CGFloat = 256
    private static let imageSide: CGFloat = 240
    private static let buttonHeight: CGFloat = 52
    private static let buttonSideInset: CGFloat = 30
    private static let textSideInset: CGFloat = 16
    private static let bottomSpacing: CGFloat = 8

    private let link: String
    private let isChannel: Bool
    private let closeButton = UIButton(type: .close)
    private let titleLabel = UILabel()
    private let codeCard = UIView()
    private let codeView = UIImageView()
    private let logoView = LottieAnimationView(configuration: LottieConfiguration(
        renderingEngine: .automatic,
        decodingStrategy: .legacyCodable,
    ))
    private let textLabel = UILabel()
    private let shareButton = UIButton(type: .system)
    private var logoConstraints = [NSLayoutConstraint]()
    private var renderedScale: CGFloat?
    private var measuredWidth: CGFloat?

    /// The sheet's height above the bottom safe area for the current width.
    private var contentHeight: CGFloat {
        let width = max(view.bounds.width, presentingViewController?.view.bounds.width ?? 0)
        let fitting = CGSize(width: width - Self.textSideInset * 2, height: .greatestFiniteMagnitude)
        let titleHeight = titleLabel.sizeThatFits(fitting).height
        let textHeight = textLabel.sizeThatFits(fitting).height
        return Self.topInset + titleHeight / 2 + 13 + Self.qrSide + 17 + textHeight + 23 + Self.buttonHeight
            + Self.bottomSpacing
    }

    init(link: String, isChannel: Bool) {
        self.link = link
        self.isChannel = isChannel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        sheetPresentationController?.detents = [.custom { [weak self] _ in self?.contentHeight }]
        sheetPresentationController?.prefersGrabberVisible = false
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        view.addSubview(closeButton)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = L10n.telegram("InviteLink.QRCode.Title")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header
        view.addSubview(titleLabel)

        codeCard.translatesAutoresizingMaskIntoConstraints = false
        codeCard.backgroundColor = .white
        codeCard.layer.cornerRadius = 24
        codeCard.layer.cornerCurve = .continuous
        codeCard.clipsToBounds = true
        view.addSubview(codeCard)
        codeView.translatesAutoresizingMaskIntoConstraints = false
        codeView.isAccessibilityElement = true
        codeView.accessibilityLabel = L10n.telegram("InviteLink.QRCode.Title")
        codeView.accessibilityTraits = .image
        codeCard.addSubview(codeView)
        logoView.translatesAutoresizingMaskIntoConstraints = false
        logoView.loopMode = .loop
        logoView.contentMode = .scaleAspectFit
        logoView.isUserInteractionEnabled = false
        codeCard.addSubview(logoView)

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.text = L10n.telegram(isChannel ? "InviteLink.QRCode.InfoChannel" : "InviteLink.QRCode.Info")
        textLabel.font = .systemFont(ofSize: 15)
        textLabel.textColor = .label
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 0
        textLabel.lineBreakStrategy = .standard
        view.addSubview(textLabel)

        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        var title = AttributedString(L10n.telegram("InviteLink.QRCode.Share"))
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        configuration.attributedTitle = title
        shareButton.configuration = configuration
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        shareButton.addAction(UIAction { [weak self] _ in self?.shareCode() }, for: .touchUpInside)
        view.addSubview(shareButton)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.centerYAnchor.constraint(equalTo: view.topAnchor, constant: Self.topInset),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 60),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -60),

            codeCard.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 13),
            codeCard.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            codeCard.widthAnchor.constraint(equalToConstant: Self.qrSide),
            codeCard.heightAnchor.constraint(equalToConstant: Self.qrSide),
            codeView.centerXAnchor.constraint(equalTo: codeCard.centerXAnchor),
            codeView.centerYAnchor.constraint(equalTo: codeCard.centerYAnchor),
            codeView.widthAnchor.constraint(equalToConstant: Self.imageSide),
            codeView.heightAnchor.constraint(equalToConstant: Self.imageSide),

            textLabel.topAnchor.constraint(equalTo: codeCard.bottomAnchor, constant: 17),
            textLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.textSideInset),
            textLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.textSideInset),

            shareButton.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 23),
            shareButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.buttonSideInset),
            shareButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.buttonSideInset),
            shareButton.heightAnchor.constraint(equalToConstant: Self.buttonHeight),
        ])
        loadLogo()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let scale = traitCollection.displayScale
        if renderedScale != scale {
            renderedScale = scale
            renderCode(scale: scale)
        }
        if measuredWidth != view.bounds.width {
            measuredWidth = view.bounds.width
            sheetPresentationController?.invalidateDetents()
        }
    }

    private func renderCode(scale: CGFloat) {
        guard let rendered = TelegramQRCode.render(link, side: Self.imageSide, scale: scale) else { return }
        codeView.image = rendered.image
        // The plane fills the empty middle, a point above its center.
        NSLayoutConstraint.deactivate(logoConstraints)
        logoConstraints = [
            logoView.centerXAnchor.constraint(equalTo: codeView.leadingAnchor, constant: rendered.cutout.midX),
            logoView.centerYAnchor.constraint(equalTo: codeView.topAnchor, constant: rendered.cutout.midY - 1),
            logoView.widthAnchor.constraint(equalToConstant: rendered.cutout.width),
            logoView.heightAnchor.constraint(equalToConstant: rendered.cutout.height),
        ]
        NSLayoutConstraint.activate(logoConstraints)
    }

    private func loadLogo() {
        guard let path = Bundle.main.path(forResource: "PlaneLogo", ofType: "tgs") else { return }
        Task { [weak self] in
            guard let animation = await TGSAnimationRepository.animation(at: path), let self else { return }
            logoView.animation = animation
            logoView.play()
        }
    }

    /// shareQrCode(asImage: true): the code alone, 768 points on white, from the bottom of the window.
    private func shareCode() {
        guard let image = TelegramQRCode.render(link, side: 768, scale: 1)?.image else { return }
        let controller = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = shareButton
            popover.sourceRect = shareButton.bounds
        }
        presentGrowing(controller, from: shareButton)
    }
}
