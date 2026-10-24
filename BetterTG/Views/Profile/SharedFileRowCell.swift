// SharedFileRowCell.swift

import TDLibKit
import UIKit

// MARK: - FileExtensionIcon

/// ListMessageFileItemNode's extension icon: a 40 pt card with a folded corner in the extension's gradient (red for
/// slides and PDF, green for sheets, yellow for archives, blue otherwise) and the extension on it.
@MainActor enum FileExtensionIcon {
    private static var cache = [UInt32: UIImage]()

    private static let red: (UInt32, UInt32) = (0xFF875F, 0xFF5069)
    private static let green: (UInt32, UInt32) = (0x99DE6F, 0x5FB84F)
    private static let blue: (UInt32, UInt32) = (0x72D5FD, 0x2A9EF1)
    private static let yellow: (UInt32, UInt32) = (0xFFA24B, 0xED705C)

    private static let colorsByExtension: [String: (UInt32, UInt32)] = [
        "ppt": red, "pptx": red, "pdf": red, "key": red,
        "xls": green, "xlsx": green, "csv": green,
        "zip": yellow, "rar": yellow, "gzip": yellow, "ai": yellow,
    ]

    /// The extension after the name's last dot, lowercased.
    static func fileExtension(of name: String) -> String? {
        guard let dot = name.lastIndex(of: "."), name.index(after: dot) < name.endIndex else { return nil }
        return name[name.index(after: dot)...].lowercased()
    }

    static func image(for fileExtension: String?) -> UIImage {
        let colors = fileExtension.flatMap { colorsByExtension[$0] } ?? blue
        if let cached = cache[colors.0] { return cached }
        let image = render(colors: colors)
        cache[colors.0] = image
        return image
    }

    /// generateExtensionImage: the card's path clipped to 13 pt corners, the gradient top to bottom, and the fold's
    /// half-white overlay at the top right.
    private static func render(colors: (UInt32, UInt32)) -> UIImage {
        let size = CGSize(width: 40, height: 40)
        return UIGraphicsImageRenderer(size: size).image { renderer in
            let context = renderer.cgContext
            let card = UIBezierPath()
            card.move(to: CGPoint(x: 6, y: 0))
            card.addLine(to: CGPoint(x: 26.757, y: 0))
            card.addCurve(
                to: CGPoint(x: 28.879, y: 0.879),
                controlPoint1: CGPoint(x: 27.553, y: 0),
                controlPoint2: CGPoint(x: 28.316, y: 0.316),
            )
            card.addLine(to: CGPoint(x: 39.121, y: 11.121))
            card.addCurve(
                to: CGPoint(x: 40, y: 13.243),
                controlPoint1: CGPoint(x: 39.684, y: 11.684),
                controlPoint2: CGPoint(x: 40, y: 12.447),
            )
            card.addLine(to: CGPoint(x: 40, y: 34))
            card.addCurve(to: CGPoint(x: 34, y: 40), controlPoint1: CGPoint(x: 40, y: 37.314), controlPoint2: CGPoint(
                x: 37.314,
                y: 40,
            ))
            card.addLine(to: CGPoint(x: 6, y: 40))
            card.addCurve(to: CGPoint(x: 0, y: 34), controlPoint1: CGPoint(x: 2.686, y: 40), controlPoint2: CGPoint(
                x: 0,
                y: 37.314,
            ))
            card.addLine(to: CGPoint(x: 0, y: 6))
            card.addCurve(to: CGPoint(x: 6, y: 0), controlPoint1: CGPoint(x: 0, y: 2.686), controlPoint2: CGPoint(
                x: 2.686,
                y: 0,
            ))
            card.close()
            let rounded = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 13)
            context.saveGState()
            card.addClip()
            rounded.addClip()
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [color(colors.0).cgColor, color(colors.1).cgColor] as CFArray,
                locations: [0, 1],
            )
            if let gradient {
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            // The fold: a 14 pt corner piece in half white over the card's cut corner.
            context.setBlendMode(.overlay)
            context.setFillColor(UIColor.white.withAlphaComponent(0.5).cgColor)
            context.translateBy(x: 26, y: 0)
            let fold = UIBezierPath()
            fold.move(to: CGPoint(x: -1, y: 0))
            fold.addLine(to: CGPoint(x: 14, y: 0))
            fold.addLine(to: CGPoint(x: 14, y: 14))
            fold.addCurve(to: CGPoint(x: 12, y: 12), controlPoint1: CGPoint(x: 14, y: 12.895), controlPoint2: CGPoint(
                x: 13.105,
                y: 12,
            ))
            fold.addLine(to: CGPoint(x: 4, y: 12))
            fold.addCurve(to: CGPoint(x: 2, y: 10), controlPoint1: CGPoint(x: 2.895, y: 12), controlPoint2: CGPoint(
                x: 2,
                y: 11.105,
            ))
            fold.addLine(to: CGPoint(x: 2, y: 2))
            fold.addCurve(to: CGPoint(x: 0, y: 0), controlPoint1: CGPoint(x: 2, y: 0.895), controlPoint2: CGPoint(
                x: 1.105,
                y: 0,
            ))
            fold.close()
            fold.fill()
            context.restoreGState()
        }
    }

    private static func color(_ rgb: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1,
        )
    }
}

// MARK: - SharedFileRowCell

/// ListMessageFileItemNode for a file: its preview or the extension icon at the left, the name, the caption on a
/// line, and the size with the full date; a global search result puts the date at the right instead.
final class SharedFileRowCell: UICollectionViewCell {
    static let reuseIdentifier = "SharedFileRowCell"

    private let iconView = UIImageView()
    private let extensionLabel = UILabel()
    private let previewView = TDImageLoadingView()
    private let titleLabel = UILabel()
    private let dateLabel = UILabel()
    private let captionLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let separator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)
        extensionLabel.translatesAutoresizingMaskIntoConstraints = false
        extensionLabel.textColor = .white
        extensionLabel.textAlignment = .center
        extensionLabel.adjustsFontSizeToFitWidth = true
        extensionLabel.minimumScaleFactor = 0.8
        contentView.addSubview(extensionLabel)
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.contentMode = .scaleAspectFill
        previewView.clipsToBounds = true
        previewView.layer.cornerRadius = 6
        contentView.addSubview(previewView)
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        dateLabel.font = .systemFont(ofSize: 14)
        dateLabel.textColor = .secondaryLabel
        dateLabel.setContentHuggingPriority(.required, for: .horizontal)
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        captionLabel.font = .systemFont(ofSize: 14)
        descriptionLabel.font = .systemFont(ofSize: 14)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.lineBreakMode = .byTruncatingMiddle
        progressView.isHidden = true
        let header = UIStackView(arrangedSubviews: [titleLabel, dateLabel])
        header.alignment = .firstBaseline
        header.spacing = 4
        let stack = UIStackView(arrangedSubviews: [header, captionLabel, descriptionLabel, progressView])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 2
        contentView.addSubview(stack)
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        contentView.addSubview(separator)
        let scale = UITraitCollection.current.displayScale
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),
            extensionLabel.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
            extensionLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor, constant: 5),
            extensionLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 36),
            previewView.leadingAnchor.constraint(equalTo: iconView.leadingAnchor),
            previewView.topAnchor.constraint(equalTo: iconView.topAnchor),
            previewView.widthAnchor.constraint(equalToConstant: 40),
            previewView.heightAnchor.constraint(equalToConstant: 40),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 65),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 65),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / max(scale, 1)),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        previewView.cancel()
        previewView.image = nil
    }

    private static func extensionFont(size: CGFloat) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        return font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? font
    }

    /// Returns false for a message that is not a file, which keeps the generic row.
    @discardableResult func configure(message: Message, isGlobalSearch: Bool, client: TDLibClient) -> Bool {
        guard case .messageDocument(let content) = message.content else { return false }
        let document = content.document
        let name = document.fileName.isEmpty ? L10n.telegram("Message.File") : document.fileName
        titleLabel.text = name
        let fileExtension = FileExtensionIcon.fileExtension(of: name)
        iconView.image = FileExtensionIcon.image(for: fileExtension)
        extensionLabel.text = fileExtension
        extensionLabel.font = Self.extensionFont(size: (fileExtension?.count ?? 0) > 3 ? 14 : 15)
        if let thumbnail = document.thumbnail, case .thumbnailFormatJpeg = thumbnail.format {
            previewView.isHidden = false
            previewView.load(
                file: thumbnail.file,
                placeholderData: document.minithumbnail?.data,
                maximumPixelSize: 120,
                client: client,
            )
        } else {
            previewView.isHidden = true
        }
        let caption = content.caption.text.trimmingCharacters(in: .whitespacesAndNewlines)
        captionLabel.text = caption
        captionLabel.isHidden = caption.isEmpty
        let bytes = Int64(max(document.document.size, document.document.expectedSize))
        let size = bytes > 0 ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : nil
        let date = Date(timeIntervalSince1970: TimeInterval(message.date))
        if isGlobalSearch {
            dateLabel.text = profileDateString(message.date)
            dateLabel.isHidden = false
            descriptionLabel.text = size
        } else {
            dateLabel.isHidden = true
            descriptionLabel.text = [size, ChatVM.fullDateString(date)].compactMap(\.self).joined(separator: " • ")
        }
        accessibilityLabel = [
            name,
            caption.isEmpty ? nil : caption,
            descriptionLabel.text,
            dateLabel.isHidden
                ? nil
                : dateLabel.text,
        ]
            .compactMap(\.self)
            .joined(separator: ", ")
        setDownloadProgress(nil)
        return true
    }

    /// A file downloading to open; nil hides the bar.
    func setDownloadProgress(_ progress: Float?) {
        progressView.isHidden = progress == nil
        progressView.progress = progress ?? 0
        accessibilityValue = progress.map { L10n.betterTG("Accessibility.PercentDownloaded", Int($0 * 100)) }
    }
}
