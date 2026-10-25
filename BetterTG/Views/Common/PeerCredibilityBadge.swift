// PeerCredibilityBadge.swift

import TDLibKit
import UIKit

// MARK: - PeerCredibilityBadge

/// Telegram's credibility icon after a peer's name (EmojiStatusComponent's `.verified`, `.scam` and `.fake`, from
/// PresentationResourcesChatList's verifiedIcon, scamIcon and fakeIcon): the blue verified badge, or the red outlined
/// SCAM or FAKE label, which outranks it.
enum PeerCredibilityBadge: Equatable {
    case verified
    case scam
    case fake

    var accessibilityLabel: String {
        switch self {
        case .verified: L10n.betterTG("Accessibility.Verified")
        case .scam: L10n.telegram("Message.ScamAccount")
        case .fake: L10n.telegram("Message.FakeAccount")
        }
    }

    /// TDLib's `verification_status` of the chat's person or supergroup.
    init?(status: TDNativeVerificationStatus?) {
        guard let status else { return nil }
        if status.isScam {
            self = .scam
        } else if status.isFake {
            self = .fake
        } else if status.isVerified {
            self = .verified
        } else {
            return nil
        }
    }

    @MainActor init?(chat: CustomChat) {
        guard !chat.isSavedMessages else { return nil }
        let status: TDNativeVerificationStatus? =
            switch chat.type {
            case .bot(let user),
                 .user(let user): user.verificationStatus
            case .supergroup(let supergroup): supergroup.verificationStatus
            case .group: nil
            }
        self.init(status: status)
    }

    /// The title followed by the badge, if any.
    static func title(
        _ title: String,
        badge: PeerCredibilityBadge?,
        font: UIFont,
        color: UIColor,
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: title, attributes: [.font: font, .foregroundColor: color])
        if let badge { result.append(badge.attributedSuffix(font: font)) }
        return result
    }

    /// PresentationResourcesChatList's scam and fake icons: the word in 10 pt medium inside a 1 pt red rounded frame.
    private static func labelImage(_ text: String, font: UIFont) -> UIImage {
        let labelFont = UIFont.systemFont(ofSize: max(9, font.pointSize * 10 / 17), weight: .medium)
        let textSize = (text as NSString).size(withAttributes: [.font: labelFont])
        let size = CGSize(width: ceil(textSize.width) + 8, height: ceil(textSize.height) + 2)
        let color = UIColor.systemRed
        return UIGraphicsImageRenderer(size: size).image { _ in
            let frame = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            let path = UIBezierPath(roundedRect: frame, cornerRadius: 2)
            path.lineWidth = 1
            color.setStroke()
            path.stroke()
            (text as NSString).draw(
                at: CGPoint(x: 4, y: 1),
                withAttributes: [.font: labelFont, .foregroundColor: color],
            )
        }
    }

    /// The badge as text after the title: a 4 pt gap, then the icon sized to the font.
    func attributedSuffix(font: UIFont) -> NSAttributedString {
        let image = image(font: font)
        let attachment = NSTextAttachment(image: image)
        // Centre the badge on the font's cap height, as Telegram centres it on the title line.
        attachment.bounds = CGRect(
            x: 0,
            y: (font.capHeight - image.size.height) / 2,
            width: image.size.width,
            height: image.size.height,
        )
        let result = NSMutableAttributedString(string: "\u{2004}")
        result.append(NSAttributedString(attachment: attachment))
        return result
    }

    /// The icon sized to the title's font.
    func image(font: UIFont) -> UIImage {
        switch self {
        case .verified:
            let configuration = UIImage.SymbolConfiguration(pointSize: font.pointSize * 0.85, weight: .semibold)
                .applying(UIImage.SymbolConfiguration(paletteColors: [.white, .systemBlue]))
            return UIImage(systemName: "checkmark.seal.fill", withConfiguration: configuration) ?? UIImage()
        case .fake,
             .scam:
            return Self.labelImage(
                L10n.telegram(self == .scam ? "Message.ScamAccount" : "Message.FakeAccount").uppercased(),
                font: font,
            )
        }
    }
}
