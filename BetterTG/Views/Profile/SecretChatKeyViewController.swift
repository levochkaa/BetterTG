// SecretChatKeyViewController.swift

import TDLibKit
import UIKit

// MARK: - SecretChatKeyViewController

/// SecretChatKeyController: the secret chat's key as SecretChatKeyVisualization's picture, its first 32 bytes in hex,
/// and the note that the two devices should show the same, with telegram.org's secret chats FAQ.
final class SecretChatKeyViewController: UIViewController {
    private let keyHash: Data
    private let name: String
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let keyLabel = UILabel()
    private let infoView = UITextView()
    private var renderedSide: CGFloat = 0

    init(keyHash: Data, name: String) {
        self.keyHash = keyHash
        self.name = name
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("EncryptionKey.Title")
        view.backgroundColor = .systemBackground
        imageView.layer.magnificationFilter = .nearest
        keyLabel.numberOfLines = 0
        keyLabel.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        keyLabel.textColor = .label
        keyLabel.text = Self.hexText(keyHash)
        infoView.isEditable = false
        infoView.isScrollEnabled = false
        infoView.backgroundColor = .clear
        infoView.textContainerInset = .zero
        infoView.textContainer.lineFragmentPadding = 0
        infoView.attributedText = infoText()
        infoView.linkTextAttributes = [.foregroundColor: UIColor.tintColor]
        view.addSubview(scrollView)
        for subview in [imageView, keyLabel, infoView] {
            scrollView.addSubview(subview)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaInsets
        scrollView.frame = view.bounds
        let sideInset: CGFloat = 10
        let bandWidth = view.bounds.width - safe.left - safe.right
        let available = view.bounds.height - safe.top - safe.bottom
        let side = min(bandWidth - sideInset * 2, available - sideInset * 2 - 100, 512).rounded(.down)
        if side != renderedSide, side > 0 {
            renderedSide = side
            imageView.image = Self.keyImage(keyHash, side: side)
        }
        let textWidth = bandWidth - sideInset * 2
        let keySize = keyLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        let infoSize = infoView.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        let contentHeight = side + 12 + keySize.height + 10 + infoSize.height
        let top = sideInset + max(0, ((available - sideInset * 2 - contentHeight) / 2).rounded(.down))
        let minX = safe.left
        imageView.frame = CGRect(x: minX + ((bandWidth - side) / 2).rounded(.down), y: top, width: side, height: side)
        keyLabel.frame = CGRect(
            x: minX + ((bandWidth - keySize.width) / 2).rounded(.down), y: imageView.frame.maxY + 12,
            width: keySize.width, height: keySize.height,
        )
        infoView.frame = CGRect(
            x: minX + ((bandWidth - infoSize.width) / 2).rounded(.down), y: keyLabel.frame.maxY + 10,
            width: infoSize.width, height: infoSize.height,
        )
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.contentSize = CGSize(width: view.bounds.width, height: contentHeight + sideInset * 2)
    }

    // MARK: Key

    /// processHexString over the SHA-1 part and the first 16 bytes of the SHA-256 part: four lines of 8 bytes, a space
    /// between bytes and another between groups of four.
    static func hexText(_ keyHash: Data) -> String {
        let bytes = [UInt8](keyHash)
        let ranges = [0..<8, 8..<16, 16..<24, 24..<32]
        return ranges.compactMap { range -> String? in
            guard range.upperBound <= bytes.count else { return nil }
            return bytes[range]
                .enumerated()
                .map { index, byte in
                    (index == 4 ? " " : "") + String(format: "%02x", byte)
                }
                .joined(separator: " ")
        }
        .joined(separator: "\n")
    }

    /// SecretChatKeyVisualization: 12 by 12 squares, each two bits of the key hash (low bits first) choosing one of
    /// four
    /// colours; the first 128 bits come from the SHA-1 part, the rest from the SHA-256 part, as TDLib's 36 bytes run.
    static func keyImage(_ keyHash: Data, side: CGFloat) -> UIImage {
        let colors: [UIColor] = [0xFFFFFF, 0xD5E6F3, 0x2D5775, 0x2F99C9].map { rgb in
            UIColor(
                red: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1,
            )
        }
        let bytes = [UInt8](keyHash)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            colors[0].setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            let cell = side / 12
            for index in 0..<144 {
                let bit = index * 2
                let byte = bit / 8
                let value = byte < bytes.count ? Int(bytes[byte] >> UInt8(bit % 8)) & 3 : 0
                colors[value].setFill()
                var rect = CGRect(
                    x: CGFloat(index % 12) * cell,
                    y: CGFloat(index / 12) * cell,
                    width: cell,
                    height: cell,
                )
                if side > 200 {
                    rect = CGRect(
                        x: rect.minX.rounded(.up), y: rect.minY.rounded(.up),
                        width: rect.width.rounded(.up), height: rect.height.rounded(.up),
                    )
                }
                context.fill(rect)
            }
        }
    }

    /// EncryptionKey.Description with the name in semibold and telegram.org linking to the FAQ.
    private func infoText() -> NSAttributedString {
        let text = L10n.telegram("EncryptionKey.Description", name, name)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph,
        ])
        let nsText = text as NSString
        var searchRange = NSRange(location: 0, length: nsText.length)
        while !name.isEmpty {
            let range = nsText.range(of: name, options: [], range: searchRange)
            guard range.location != NSNotFound else { break }
            result.addAttribute(.font, value: UIFont.systemFont(ofSize: 14, weight: .semibold), range: range)
            let next = range.location + range.length
            searchRange = NSRange(location: next, length: nsText.length - next)
        }
        let link = nsText.range(of: "telegram.org")
        if link.location != NSNotFound, let url = URL(string: "https://telegram.org/faq#secret-chats") {
            result.addAttribute(.link, value: url, range: link)
        }
        return result
    }
}
