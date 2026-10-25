// AdsInfoViewController.swift

import TDLibKit
import UIKit

// MARK: - TelegramMarkdownText

/// parseMarkdownIntoAttributedString for Telegram's strings: `**bold**` and `[text](link)`, where an empty link takes
/// `defaultLink`, and a link's ">" becomes Telegram's chevron (`Settings/TextArrowRight`).
enum TelegramMarkdownText {
    static func make(
        _ text: String,
        font: UIFont,
        boldFont: UIFont,
        color: UIColor,
        linkColor: UIColor,
        defaultLink: URL?,
        alignment: NSTextAlignment = .natural,
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineSpacing = 1
        let result = NSMutableAttributedString()
        var isBold = false
        func appendPlain(_ part: Substring) {
            for (index, piece) in part.components(separatedBy: "**").enumerated() {
                if index > 0 { isBold.toggle() }
                result.append(NSAttributedString(string: piece, attributes: [
                    .font: isBold ? boldFont : font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph,
                ]))
            }
        }
        var index = text.startIndex
        for match in text.matches(of: /\[([^\]]*)\]\(([^)]*)\)/) {
            appendPlain(text[index..<match.range.lowerBound])
            let target = String(match.output.2)
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: linkColor,
                .paragraphStyle: paragraph,
            ]
            if let link = target.isEmpty ? defaultLink : URL(string: target) { attributes[.link] = link }
            let label = String(match.output.1)
            if let arrow = label.range(of: ">") {
                result.append(NSAttributedString(
                    string: String(label[..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces) + "\u{00A0}",
                    attributes: attributes,
                ))
                let chevron = NSTextAttachment(image: UIImage(
                    systemName: "chevron.right",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: font.pointSize * 0.7, weight: .semibold),
                )?.withTintColor(linkColor, renderingMode: .alwaysOriginal) ?? UIImage())
                let chevronString = NSMutableAttributedString(attachment: chevron)
                chevronString.addAttributes(attributes, range: NSRange(location: 0, length: chevronString.length))
                result.append(chevronString)
            } else {
                result.append(NSAttributedString(string: label, attributes: attributes))
            }
            index = match.range.upperBound
        }
        appendPlain(text[index...])
        return result
    }
}

// MARK: - AdsInfoViewController

/// Telegram's AdsInfoScreen in its channel mode: the ads logo on its gradient, "About These Ads", how they respect
/// privacy, split the revenue with the channel and can be removed, the "Can I Launch an Ad?" block and Understood.
/// Opened for an ad, its "more" button gives AdsInfoScreen's `infoPressed` menu: the sponsor's info, Report Ad and
/// Remove Ad. `.sponsoredMessages` is AdInfoScreen, What are sponsored messages?, for an ad that can't be reported.
final class AdsInfoViewController: UIViewController, UITextViewDelegate {
    enum Mode {
        case ads
        case sponsoredMessages
    }

    /// The ad's menu behind the "more" button; none hides the button.
    var menuActions: (() -> [TelegramContextMenuAction])?

    private let mode: Mode
    private let client: TDLibClient
    private let accountID: UUID?
    private let moreButton = UIButton(type: .system)
    private let removalTextView = UITextView()

    init(mode: Mode, client: TDLibClient) {
        self.mode = mode
        self.client = client
        self.accountID = TDLib.shared.activeAccountID
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
        }
        let close = UIButton(type: .system, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        close.setImage(UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
        ), for: .normal)
        close.tintColor = .secondaryLabel
        close.accessibilityLabel = L10n.telegram("Common.Close")

        moreButton.setImage(UIImage(
            systemName: "ellipsis",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
        ), for: .normal)
        moreButton.tintColor = .secondaryLabel
        moreButton.accessibilityLabel = L10n.telegram("Common.More")
        moreButton.addAction(UIAction { [weak self] _ in self?.presentMenu() }, for: .touchUpInside)
        moreButton.isHidden = menuActions?().isEmpty ?? true

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        let content =
            switch mode {
            case .ads: adsContent()
            case .sponsoredMessages: sponsoredMessagesContent()
            }

        let button = UIButton(type: .system, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.attributedTitle = AttributedString(
            L10n.telegram(mode == .ads ? "AdsInfo.Understood" : "Common.Done"),
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]),
        )
        button.configuration = configuration

        for subview in [scrollView, close, moreButton, button] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            close.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            moreButton.topAnchor.constraint(equalTo: close.topAnchor),
            moreButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            moreButton.widthAnchor.constraint(equalToConstant: 44),
            moreButton.heightAnchor.constraint(equalToConstant: 44),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: button.topAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 30),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            content.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            button.heightAnchor.constraint(equalToConstant: 52),
            button.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),
        ])
        if mode == .ads { loadRemovalLevel() }
    }

    /// AdsInfoScreen's `displayUndo`: the toast over the sheet.
    func showToast(_ text: String) {
        TelegramUndoToast.show(text: text, in: view, bottomInset: 84, undo: nil)
    }

    func textView(
        _: UITextView,
        primaryActionFor textItem: UITextItem,
        defaultAction _: UIAction,
    ) -> UIAction? {
        guard case .link(let url) = textItem.content else { return nil }
        // Telegram opens these pages with `forceExternal`.
        return UIAction { _ in UIApplication.shared.open(url) }
    }

    // MARK: Content

    private func adsContent() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16

        let icon = AdsInfoIconView()
        let iconRow = UIView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconRow.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: iconRow.topAnchor),
            icon.bottomAnchor.constraint(equalTo: iconRow.bottomAnchor),
            icon.centerXAnchor.constraint(equalTo: iconRow.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 90),
            icon.heightAnchor.constraint(equalToConstant: 90),
        ])
        stack.addArrangedSubview(iconRow)
        stack.setCustomSpacing(17, after: iconRow)

        let title = centeredLabel(L10n.telegram("AdsInfo.Title"), font: .systemFont(ofSize: 20, weight: .semibold))
        title.accessibilityTraits = .header
        stack.addArrangedSubview(title)
        stack.setCustomSpacing(8, after: title)
        let info = centeredLabel(L10n.telegram("AdsInfo.Info"), font: .systemFont(ofSize: 15))
        info.textColor = .secondaryLabel
        stack.addArrangedSubview(inset(info, by: 14))

        stack.addArrangedSubview(paragraph(
            symbol: "hand.raised.fill",
            title: L10n.telegram("AdsInfo.Respect.Title"),
            text: markdownTextView(L10n.telegram("AdsInfo.Respect.Text")),
        ))
        stack.addArrangedSubview(paragraph(
            symbol: "chart.pie.fill",
            title: L10n.telegram("AdsInfo.Split.Title"),
            text: markdownTextView(L10n.telegram("AdsInfo.Split.Text")),
        ))
        configureRemovalText(level: 50)
        stack.addArrangedSubview(paragraph(
            symbol: "nosign",
            title: L10n.telegram("AdsInfo.Ads.Title"),
            text: removalTextView,
        ))

        let launch = UIStackView()
        launch.axis = .vertical
        launch.spacing = 6
        launch.isLayoutMarginsRelativeArrangement = true
        launch.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 13, leading: 20, bottom: 13, trailing: 20)
        launch.backgroundColor = .secondarySystemBackground
        launch.layer.cornerRadius = 26
        launch.layer.cornerCurve = .continuous
        launch.addArrangedSubview(centeredLabel(
            L10n.telegram("AdsInfo.Launch.Title"),
            font: .systemFont(ofSize: 20, weight: .semibold),
        ))
        let launchText = markdownTextView(
            L10n.telegram("AdsInfo.Launch.Text"),
            link: URL(string: L10n.telegram("AdsInfo.Launch.Text_URL")),
            alignment: .center,
            color: .label,
        )
        launch.addArrangedSubview(launchText)
        stack.setCustomSpacing(7, after: stack.arrangedSubviews.last ?? stack)
        stack.addArrangedSubview(launch)
        return stack
    }

    /// AdInfoScreen: the explanation in parts around Telegram's ads page, which shows as its own link.
    private func sponsoredMessagesContent() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        let title = centeredLabel(
            L10n.telegram("SponsoredMessageInfoScreen.Title"),
            font: .systemFont(ofSize: 17, weight: .semibold),
        )
        title.accessibilityTraits = .header
        stack.addArrangedSubview(inset(title, by: 44))
        let link = L10n.telegram("SponsoredMessageInfo.Url")
        let parts = L10n.telegram("SponsoredMessageInfoScreen.MarkdownText").components(separatedBy: "[url]")
        for (index, part) in parts.enumerated() {
            let text = part.trimmingCharacters(in: .newlines)
            if !text.isEmpty {
                stack.addArrangedSubview(markdownTextView(text, font: .systemFont(ofSize: 16), color: .label))
            }
            if index == 0 {
                stack.addArrangedSubview(markdownTextView(
                    "[\(link)](\(link))",
                    font: .systemFont(ofSize: 16),
                    color: .label,
                ))
            }
        }
        return stack
    }

    private func centeredLabel(_ text: String, font: UIFont) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }

    private func inset(_ view: UIView, by inset: CGFloat) -> UIView {
        let container = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
        ])
        return container
    }

    private func markdownTextView(
        _ text: String,
        link: URL? = nil,
        alignment: NSTextAlignment = .natural,
        font: UIFont = .systemFont(ofSize: 15),
        color: UIColor = .secondaryLabel,
    ) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.linkTextAttributes = [.foregroundColor: UIColor.tintColor]
        textView.delegate = self
        textView.attributedText = TelegramMarkdownText.make(
            text,
            font: font,
            boldFont: .systemFont(ofSize: font.pointSize, weight: .semibold),
            color: color,
            linkColor: .tintColor,
            defaultLink: link,
            alignment: alignment,
        )
        return textView
    }

    /// AdsInfoScreen's ParagraphComponent: the icon in the accent colour, the title and the text after it.
    private func paragraph(symbol: String, title: String, text: UIView) -> UIView {
        let icon = UIImageView(image: UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium),
        ))
        icon.tintColor = .tintColor
        icon.contentMode = .center
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.numberOfLines = 0
        let column = UIStackView(arrangedSubviews: [titleLabel, text])
        column.axis = .vertical
        column.spacing = 5
        let container = UIView()
        for subview in [icon, column] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor, constant: 9),
            column.topAnchor.constraint(equalTo: container.topAnchor),
            column.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 40),
            column.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
        ])
        return container
    }

    /// AdsInfo.Ads.Text with the boost level that lets channels remove ads (PremiumConfiguration's
    /// `minChannelRestrictAdsLevel`, 50 until TDLib's `chatBoostFeatures` says). BetterTG sells no Premium, so the
    /// Premium link reads as text.
    private func configureRemovalText(level: Int) {
        let text = L10n.telegram("AdsInfo.Ads.Text", "\(level)").withoutTelegramLinks
        removalTextView.isEditable = false
        removalTextView.isScrollEnabled = false
        removalTextView.backgroundColor = .clear
        removalTextView.textContainerInset = .zero
        removalTextView.textContainer.lineFragmentPadding = 0
        removalTextView.attributedText = TelegramMarkdownText.make(
            text,
            font: .systemFont(ofSize: 15),
            boldFont: .systemFont(ofSize: 15, weight: .semibold),
            color: .secondaryLabel,
            linkColor: .tintColor,
            defaultLink: nil,
        )
    }

    private func loadRemovalLevel() {
        let client = client
        let accountID = accountID
        Task { [weak self] in
            guard let features = try? await client.send(TDNativeRequests.getChatBoostFeatures(isChannel: true)),
                  features.minSponsoredMessageDisableBoostLevel > 0,
                  let self, TDLib.shared.activeAccountID == accountID else { return }
            configureRemovalText(level: features.minSponsoredMessageDisableBoostLevel)
        }
    }

    private func presentMenu() {
        guard let actions = menuActions?(), !actions.isEmpty else { return }
        presentTelegramContextMenu(sourceView: moreButton, actions: actions, presentationStyle: .sourceMorph)
    }
}

// MARK: - AdsInfoIconView

/// AdsInfoScreen's icon: Telegram's ads logo on a 90 pt circle with its blue, violet and pink diagonal gradient.
private final class AdsInfoIconView: UIView {
    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradient.colors = [UIColor(rgb: 0x6E91FF), UIColor(rgb: 0x9472FF), UIColor(rgb: 0xCC6CDD)].map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(gradient)
        let symbol = UIImageView(image: UIImage(
            systemName: "megaphone.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 40, weight: .medium),
        ))
        symbol.tintColor = .white
        symbol.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbol)
        NSLayoutConstraint.activate([
            symbol.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbol.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isAccessibilityElement = false
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        gradient.cornerRadius = bounds.width / 2
    }
}
