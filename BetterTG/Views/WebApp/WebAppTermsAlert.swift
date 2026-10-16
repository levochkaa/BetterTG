// WebAppTermsAlert.swift

import UIKit

// MARK: - WebAppTermsAlert

/// webAppTermsAlertController: Terms of Use before an attachment menu bot is added, with Telegram's "I agree to the
/// Terms of Use" check whose link opens the mini app terms. Continue is enabled once the check is set and passes it on
/// as the bot's write access (`completion(checkState.value)`). The check sits in the system alert as its content
/// view controller; where UIKit doesn't offer that, the alert ends with the agreement and Continue stands for it.
@MainActor enum WebAppTermsAlert {
    private static let contentSelector = NSSelectorFromString("setContentViewController:")

    static func make(
        cancel: @escaping () -> Void = {},
        proceed: @escaping (_ allowWriteAccess: Bool) -> Void,
    ) -> UIAlertController {
        let alert = UIAlertController(
            title: L10n.telegram("WebApp.DisclaimerTitle"),
            message: L10n.telegram("WebApp.DisclaimerText"),
            preferredStyle: .alert,
        )
        let content = WebAppTermsCheckViewController(agreement: L10n.telegram("WebApp.DisclaimerAgree"))
        let hasCheck = setContent(content, of: alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel) { _ in cancel() })
        let continueAction = UIAlertAction(title: L10n.telegram("WebApp.DisclaimerContinue"), style: .default) { _ in
            proceed(hasCheck ? content.isChecked : true)
        }
        alert.addAction(continueAction)
        alert.preferredAction = continueAction
        if hasCheck {
            continueAction.isEnabled = false
            content.onChange = { [weak continueAction] isChecked in continueAction?.isEnabled = isChecked }
        } else {
            alert.message = [alert.message ?? "", content.agreementText.string].joined(separator: "\n\n")
        }
        return alert
    }

    /// `-[UIAlertController setContentViewController:]`, checked before it is called.
    private static func setContent(_ content: UIViewController, of alert: UIAlertController) -> Bool {
        guard UIAlertController.instancesRespond(to: contentSelector) else { return false }
        typealias SetContent = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        unsafeBitCast(alert.method(for: contentSelector), to: SetContent.self)(alert, contentSelector, content)
        return true
    }
}

// MARK: - WebAppTermsCheckViewController

/// AlertCheckComponent: a 22 pt check and the agreement, whose `[Terms of Use]()` link opens
/// WebApp.Disclaimer_URL outside the app while a tap anywhere else toggles the check.
private final class WebAppTermsCheckViewController: UIViewController {
    let agreementText: NSAttributedString
    var onChange: ((Bool) -> Void)?
    private(set) var isChecked = false

    private let linkRange: NSRange?
    private let row = UIView()
    private let checkView = UIImageView()
    private let label = UILabel()

    init(agreement: String) {
        let parsed = Self.parse(agreement)
        self.agreementText = parsed.text
        self.linkRange = parsed.link
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        checkView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20)
        checkView.contentMode = .center
        label.attributedText = agreementText
        label.numberOfLines = 0
        row.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(row)
        for subview in [checkView, label] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            row.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            checkView.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            checkView.topAnchor.constraint(equalTo: row.topAnchor, constant: -2),
            checkView.widthAnchor.constraint(equalToConstant: 22),
            checkView.heightAnchor.constraint(equalToConstant: 22),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 34),
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            label.topAnchor.constraint(equalTo: row.topAnchor),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 20),
        ])
        row.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(rowTapped(_:))))
        row.isAccessibilityElement = true
        row.accessibilityLabel = agreementText.string
        row.accessibilityCustomActions = [UIAccessibilityCustomAction(
            name: L10n.telegram("WebApp.DisclaimerTitle"),
        ) { _ in
            Self.openTerms()
            return true
        }]
        update()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let width = view.bounds.width > 0 ? view.bounds.width : 270
        let size = view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        )
        if preferredContentSize.height != size.height {
            preferredContentSize = CGSize(width: width, height: size.height)
        }
    }

    /// The agreement's `[text]()` link as tinted text, and its range.
    private static func parse(_ markdown: String) -> (text: NSAttributedString, link: NSRange?) {
        let font = UIFont.preferredFont(forTextStyle: .footnote)
        let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.label]
        let result = NSMutableAttributedString()
        var rest = Substring(markdown)
        var link: NSRange?
        if let open = rest.firstIndex(of: "["), let close = rest[open...].firstIndex(of: "]"),
           rest[rest.index(after: close)...].hasPrefix("("),
           let end = rest[close...].firstIndex(of: ")")
        {
            result.append(NSAttributedString(string: String(rest[..<open]), attributes: plain))
            let linkText = String(rest[rest.index(after: open)..<close])
            link = NSRange(location: result.length, length: (linkText as NSString).length)
            result.append(NSAttributedString(
                string: linkText,
                attributes: [.font: font, .foregroundColor: UIColor.link],
            ))
            rest = rest[rest.index(after: end)...]
        }
        result.append(NSAttributedString(string: String(rest), attributes: plain))
        return (result, link)
    }

    /// AlertCheckComponent's `linkAction`: `openExternalUrl(… forceExternal: true)`.
    private static func openTerms() {
        guard let url = URL(string: L10n.telegram("WebApp.Disclaimer_URL")) else { return }
        UIApplication.shared.open(url)
    }

    @objc private func rowTapped(_ gesture: UITapGestureRecognizer) {
        if let linkRange, linkContains(gesture.location(in: label), range: linkRange) {
            Self.openTerms()
            return
        }
        isChecked.toggle()
        update()
        onChange?(isChecked)
    }

    /// The link's line rects in the label, a little larger for the finger.
    private func linkContains(_ point: CGPoint, range: NSRange) -> Bool {
        guard let text = label.attributedText, label.bounds.width > 0 else { return false }
        let storage = NSTextStorage(attributedString: text)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var contains = false
        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: container,
        ) { rect, stop in
            if rect.insetBy(dx: -4, dy: -6).contains(point) {
                contains = true
                stop.pointee = true
            }
        }
        return contains
    }

    private func update() {
        checkView.image = UIImage(systemName: isChecked ? "checkmark.circle.fill" : "circle")
        checkView.tintColor = isChecked ? view.tintColor : .tertiaryLabel
        row.accessibilityTraits = isChecked ? [.button, .selected] : .button
    }
}
