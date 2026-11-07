// PeerQRCodeViewController.swift

import CoreImage
import TDLibKit
import UIKit

// MARK: - PeerQRCodeViewController

/// ChatQrCodeScreen for a public username: Telegram's default gradient behind a white card, 42 pt round, whose code
/// shows the gradient through its modules (codeForegroundNode masked by the code), "@USERNAME" in rounded bold under
/// it in the same gradient, the 100 pt avatar standing 70% above the card, and Share QR Code, which shares the card as
/// an image. Telegram's theme carousel isn't ported.
final class PeerQRCodeViewController: UIViewController {
    private static let gradientColors = [0xDBDDBB, 0x6BA587, 0xD5D88D, 0x88B884].map { UIColor(rgb: $0).cgColor }

    private let username: String
    private let peer: SettingsPeer
    private let client: TDLibClient
    private let accountID: UUID?
    private let background = CAGradientLayer()
    private let card = UIView()
    private let cardGradient = CAGradientLayer()
    private let cardMask = CALayer()
    private let avatarView = ProfileAvatarView()
    private let shareButton = UIButton(configuration: .prominentGlass())
    private var renderedSide: CGFloat = 0

    private var link: String {
        "https://t.me/\(username)"
    }

    init(username: String, peer: SettingsPeer, client: TDLibClient, accountID: UUID?) {
        self.username = username
        self.peer = peer
        self.client = client
        self.accountID = accountID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("PeerInfo.QRCode.Title")
        background.colors = Self.gradientColors
        background.startPoint = CGPoint(x: 0, y: 0)
        background.endPoint = CGPoint(x: 1, y: 1)
        view.layer.addSublayer(background)
        card.backgroundColor = .white
        card.layer.cornerRadius = 42
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        view.addSubview(card)
        cardGradient.colors = Self.gradientColors
        cardGradient.startPoint = CGPoint(x: 0, y: 0)
        cardGradient.endPoint = CGPoint(x: 1, y: 1)
        cardGradient.mask = cardMask
        card.layer.addSublayer(cardGradient)
        avatarView.isUserInteractionEnabled = false
        avatarView.configure(
            file: peer.file,
            minithumbnail: peer.minithumbnail,
            placeholder: peer.placeholder,
            // The account's own code shows its photo, not Saved Messages.
            usesPeerPhotoForSavedMessages: true,
            accountID: accountID,
            client: client,
        )
        view.addSubview(avatarView)
        var configuration = shareButton.configuration ?? .prominentGlass()
        configuration.title = L10n.telegram("InviteLink.QRCode.Share")
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }
        shareButton.configuration = configuration
        shareButton.addAction(UIAction { [weak self] _ in self?.share() }, for: .touchUpInside)
        view.addSubview(shareButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        background.frame = view.bounds
        let safe = view.safeAreaInsets
        let buttonFrame = CGRect(
            x: 16 + safe.left, y: view.bounds.height - safe.bottom - 16 - 52,
            width: view.bounds.width - 32 - safe.left - safe.right, height: 52,
        )
        shareButton.frame = buttonFrame
        // QrContentNode: a card up to 300 pt, 45 pt from the sides, 1.1 times as tall as wide, centred above the
        // button with the avatar's 70% over it.
        let wide = view.bounds.width > 320
        let avatarSide: CGFloat = wide ? 100 : 70
        let cardWidth = min(300, view.bounds.width - safe.left - safe.right - (wide ? 45 : 55) * 2)
        let cardHeight = floor(cardWidth * 1.1)
        let available = buttonFrame.minY - safe.top
        let cardY = safe.top + floor((available - cardHeight + avatarSide * 0.7) / 2)
        card.frame = CGRect(
            x: floor((view.bounds.width - cardWidth) / 2),
            y: cardY,
            width: cardWidth,
            height: cardHeight,
        )
        avatarView.frame = CGRect(
            x: floor((view.bounds.width - avatarSide) / 2), y: cardY - floor(avatarSide * 0.7),
            width: avatarSide, height: avatarSide,
        )
        cardGradient.frame = card.convert(view.bounds, from: view)
        cardMask.frame = CGRect(
            origin: CGPoint(x: -cardGradient.frame.minX, y: -cardGradient.frame.minY),
            size: card.bounds.size,
        )
        CATransaction.commit()
        if renderedSide != cardWidth { renderMask(cardWidth: cardWidth) }
    }

    /// The black-on-white code as alpha: modules opaque, the rest clear.
    private static func alphaMask(from image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        let inverted = input.applyingFilter("CIColorInvert").applyingFilter("CIMaskToAlpha")
        let context = CIContext()
        guard let cgImage = context.createCGImage(inverted, from: inverted.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    /// The code (220 pt, 160 pt on narrow screens) and "@USERNAME" under it as the mask the gradient shows through.
    private func renderMask(cardWidth: CGFloat) {
        renderedSide = cardWidth
        let scale = traitCollection.displayScale
        let imageSide: CGFloat = view.bounds.width > 320 ? 220 : 160
        guard let code = TelegramQRCode.render(link, side: imageSide, scale: scale),
              let codeMask = Self.alphaMask(from: code.image) else { return }
        let size = CGSize(width: cardWidth, height: floor(cardWidth * 1.1))
        let text = "@" + username.uppercased()
        let fontSize: CGFloat = text.count > 18 ? 16 : text.count > 12 ? 22 : 24
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let rounded = font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: fontSize) } ?? font
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let imageFrame = CGRect(
                x: floor((size.width - imageSide) / 2), y: floor((size.width - imageSide) / 2),
                width: imageSide, height: imageSide,
            )
            codeMask.draw(in: imageFrame)
            // The middle square holds a filled circle, as codeIconBackgroundNode does under Telegram's plane.
            let cutout = code.cutout.offsetBy(dx: imageFrame.minX, dy: imageFrame.minY).insetBy(dx: 4, dy: 4)
            UIColor.black.setFill()
            UIBezierPath(ovalIn: cutout).fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: rounded, .foregroundColor: UIColor.black]
            let textSize = (text as NSString).size(withAttributes: attributes)
            let textY = imageFrame.maxY + floor((size.height - imageFrame.maxY - textSize.height) / 2) - 5
            (text as NSString).draw(
                at: CGPoint(x: floor((size.width - textSize.width) / 2), y: textY), withAttributes: attributes,
            )
        }
        cardMask.contents = image.cgImage
        cardMask.contentsScale = image.scale
    }

    /// shareQrCode: the card with its avatar on the gradient, as an image, with the link.
    private func share() {
        let bounds = card.frame.union(avatarView.frame).insetBy(dx: -24, dy: -24)
        let image = UIGraphicsImageRenderer(bounds: bounds).image { context in
            view.layer.render(in: context.cgContext)
        }
        let sheet = UIActivityViewController(
            activityItems: [image, URL(string: link) as Any],
            applicationActivities: nil,
        )
        sheet.popoverPresentationController?.sourceView = shareButton
        present(sheet, animated: true)
    }
}
