// InvoiceMessageContentView.swift

import TDLibKit
import UIKit

/// Telegram's invoice bubble (ChatMessageInvoiceBubbleContentNode over ChatMessageAttachedContentNode): the
/// product's photo first, badged with the price and INVOICE (RECEIPT once paid, with (Test) for a test invoice) as
/// ChatMessageInteractiveMediaNode badges it; then its title and, without a photo, the price and INVOICE; then its
/// description. A Stars invoice (XTR) shows no price. Paying goes through the message's Pay button.
final class InvoiceMessageContentView: UIView, MessageSupplementView {
    private let mediaView = TDImageLoadingView()
    private let bodyTextView = MessageTextContentView()

    init(invoice: TDNativeMessageInvoice, client: TDLibClient) {
        super.init(frame: .zero)
        layer.cornerRadius = 5
        clipsToBounds = true
        backgroundColor = UIColor.systemBlue.withAlphaComponent(0.05)

        let accent = UIView()
        accent.translatesAutoresizingMaskIntoConstraints = false
        accent.backgroundColor = .systemBlue
        addSubview(accent)

        let content = UIStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 4
        addSubview(content)

        let product = invoice.productInfo
        let label = Self.label(invoice)
        if let photo = product.photo,
           let size = photo.sizes.max(by: { $0.width * $0.height < $1.width * $1.height })
        {
            mediaView.contentMode = .scaleAspectFill
            mediaView.clipsToBounds = true
            mediaView.layer.cornerRadius = 4
            mediaView.backgroundColor = .tertiarySystemFill
            mediaView.load(
                file: size.photo,
                placeholderData: photo.minithumbnail?.data,
                maximumPixelSize: 720,
                client: client,
            )
            content.addArrangedSubview(mediaView)
            content.setCustomSpacing(6, after: mediaView)
            let aspect = min(1.3, max(0.5, CGFloat(size.height) / max(1, CGFloat(size.width))))
            mediaView.heightAnchor.constraint(equalTo: mediaView.widthAnchor, multiplier: aspect).isActive = true
            if let label { addBadge(label, to: mediaView) }
        }

        let title = product.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
            titleLabel.textColor = .systemBlue
            titleLabel.numberOfLines = 0
            content.addArrangedSubview(titleLabel)
        }
        if product.photo == nil, let label {
            let subtitle = UILabel()
            subtitle.attributedText = label
            subtitle.numberOfLines = 0
            content.addArrangedSubview(subtitle)
        }
        if !product.description.text.isEmpty {
            bodyTextView.configure(
                formattedText: product.description,
                client: client,
                statusText: "",
                statusColor: .secondaryLabel,
                maximumWidth: Utils.maxMessageContentWidth - 24,
            )
            content.addArrangedSubview(bodyTextView)
        }

        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            accent.topAnchor.constraint(equalTo: topAnchor),
            accent.bottomAnchor.constraint(equalTo: bottomAnchor),
            accent.leadingAnchor.constraint(equalTo: leadingAnchor),
            accent.widthAnchor.constraint(equalToConstant: 3),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

        isAccessibilityElement = true
        accessibilityLabel = [title, label?.string ?? "", product.description.text]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The price in bold then INVOICE, or RECEIPT once paid, each with (Test) for a test invoice; nil for Stars.
    static func label(_ invoice: TDNativeMessageInvoice) -> NSAttributedString? {
        guard invoice.currency != "XTR" else { return nil }
        let test = invoice.isTest ? " (Test)" : ""
        let string = NSMutableAttributedString()
        if invoice.receiptMessageId != 0 {
            string.append(NSAttributedString(
                string: L10n.telegram("Checkout.Receipt.Title").uppercased() + test,
                attributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.label],
            ))
        } else {
            string.append(NSAttributedString(
                string: amountText(invoice.totalAmount, currency: invoice.currency) + " ",
                attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: UIColor.label],
            ))
            string.append(NSAttributedString(
                string: L10n.telegram("Message.InvoiceLabel") + test,
                attributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.label],
            ))
        }
        return string
    }

    /// formatCurrencyAmount: the amount in the currency's smallest units, shown with its symbol.
    static func amountText(_ amount: Int64, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let digits = formatter.maximumFractionDigits
        let value = Decimal(amount) / pow(Decimal(10), digits)
        return formatter.string(from: value as NSDecimalNumber) ?? "\(amount) \(currency)"
    }

    func prepareForReuse() {
        mediaView.cancel()
        bodyTextView.prepareForReuse()
    }

    func setPlaybackVisible(_ visible: Bool) {
        bodyTextView.setCustomEmojiPlaybackVisible(visible)
    }

    private func addBadge(_ text: NSAttributedString, to mediaView: UIView) {
        let badge = UILabel()
        badge.translatesAutoresizingMaskIntoConstraints = false
        let white = NSMutableAttributedString(attributedString: text)
        white.addAttribute(.foregroundColor, value: UIColor.white, range: NSRange(location: 0, length: white.length))
        white.enumerateAttribute(.font, in: NSRange(location: 0, length: white.length)) { value, range, _ in
            let weight: UIFont.Weight = (value as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) == true
                ? .semibold
                : .regular
            white.addAttribute(.font, value: UIFont.systemFont(ofSize: 12, weight: weight), range: range)
        }
        badge.attributedText = white
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        container.layer.cornerRadius = 9
        container.addSubview(badge)
        mediaView.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: mediaView.topAnchor, constant: 6),
            container.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor, constant: 6),
            container.heightAnchor.constraint(equalToConstant: 18),
            badge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            badge.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            badge.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
    }
}
