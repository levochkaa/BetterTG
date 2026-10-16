// BotLoginUrlAlert.swift

import UIKit

// MARK: - BotLoginUrlAlert

/// chatMessageActionUrlAuthController: "Open Link" for a login URL button, asking whether to open the link, with
/// Telegram's checks "Log in to domain as Name" and, when the bot asks, "Allow Bot to send me messages". Clearing the
/// first clears and disables the second. The checks sit in the system alert as its content view controller; where
/// UIKit doesn't offer that, the alert opens with Telegram's defaults (logged in, messages allowed).
@MainActor enum BotLoginUrlAlert {
    private static let contentSelector = NSSelectorFromString("setContentViewController:")

    static func make(
        url: String,
        domain: String,
        botName: String,
        accountName: String,
        requestsWriteAccess: Bool,
        open: @escaping (_ authorize: Bool, _ allowWriteAccess: Bool) -> Void,
    ) -> UIAlertController {
        let alert = UIAlertController(
            title: L10n.telegram("Conversation.OpenBotLinkTitle"),
            message: plain(L10n.telegram("Conversation.OpenBotLinkText", url)),
            preferredStyle: .alert,
        )
        let content = ChecksViewController(
            loginText: L10n.telegram("Conversation.OpenBotLinkLogin", domain, accountName),
            writeText: requestsWriteAccess ? L10n.telegram("Conversation.OpenBotLinkAllowMessages", botName) : nil,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        let openAction = UIAlertAction(title: L10n.telegram("Conversation.OpenBotLinkOpen"), style: .default) { _ in
            open(content.authorize, content.authorize && content.allowWriteAccess && requestsWriteAccess)
        }
        alert.addAction(openAction)
        alert.preferredAction = openAction
        if !setContent(content, of: alert) {
            // Without the checks the alert names what Open does.
            var lines = [alert.message ?? "", plain(content.loginText)]
            if let writeText = content.writeText { lines.append(plain(writeText)) }
            alert.message = lines.joined(separator: "\n\n")
        }
        return alert
    }

    /// Telegram's `**bold**` spans over the alert's footnote text.
    fileprivate static func attributed(_ text: String) -> NSAttributedString {
        let regular = UIFont.preferredFont(forTextStyle: .footnote)
        let bold = UIFont.systemFont(ofSize: regular.pointSize, weight: .semibold)
        let result = NSMutableAttributedString()
        for (index, part) in text.components(separatedBy: "**").enumerated() {
            result.append(NSAttributedString(string: part, attributes: [
                .font: index.isMultiple(of: 2) ? regular : bold,
                .foregroundColor: UIColor.label,
            ]))
        }
        return result
    }

    /// `-[UIAlertController setContentViewController:]`, checked before it is called.
    private static func setContent(_ content: UIViewController, of alert: UIAlertController) -> Bool {
        guard UIAlertController.instancesRespond(to: contentSelector) else { return false }
        typealias SetContent = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        unsafeBitCast(alert.method(for: contentSelector), to: SetContent.self)(alert, contentSelector, content)
        return true
    }

    private static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
    }
}

// MARK: - ChecksViewController

/// ChatMessageActionUrlAuthAlertContentNode's two check rows: a 22 pt check at 12 pt, the text from 46 pt.
private final class ChecksViewController: UIViewController {
    let loginText: String
    let writeText: String?
    private(set) var authorize = true
    private(set) var allowWriteAccess = true

    private let loginRow: CheckRow
    private let writeRow: CheckRow?
    private let stack = UIStackView()

    init(loginText: String, writeText: String?) {
        self.loginText = loginText
        self.writeText = writeText
        self.loginRow = CheckRow(text: BotLoginUrlAlert.attributed(loginText))
        self.writeRow = writeText.map { CheckRow(text: BotLoginUrlAlert.attributed($0)) }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
        ])
        stack.addArrangedSubview(loginRow)
        loginRow.addAction(UIAction { [weak self] _ in self?.toggleAuthorize() }, for: .touchUpInside)
        if let writeRow {
            stack.addArrangedSubview(writeRow)
            writeRow.addAction(UIAction { [weak self] _ in self?.toggleWriteAccess() }, for: .touchUpInside)
        }
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

    /// `authorizeTap`: logging out of the login drops the write access too.
    private func toggleAuthorize() {
        authorize.toggle()
        if !authorize { allowWriteAccess = false }
        update()
    }

    private func toggleWriteAccess() {
        guard authorize else { return }
        allowWriteAccess.toggle()
        update()
    }

    private func update() {
        loginRow.isChecked = authorize
        writeRow?.isChecked = allowWriteAccess
        writeRow?.alpha = authorize ? 1 : 0.4
        writeRow?.isEnabled = authorize
    }
}

// MARK: - CheckRow

private final class CheckRow: UIControl {
    var isChecked = false {
        didSet {
            checkView.image = UIImage(systemName: isChecked ? "checkmark.circle.fill" : "circle")
            checkView.tintColor = isChecked ? tintColor : .tertiaryLabel
            accessibilityTraits = isChecked ? [.button, .selected] : .button
        }
    }

    private let checkView = UIImageView()
    private let label = UILabel()

    init(text: NSAttributedString) {
        super.init(frame: .zero)
        checkView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20)
        checkView.contentMode = .center
        label.attributedText = text
        label.numberOfLines = 4
        for view in [checkView, label] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            checkView.leadingAnchor.constraint(equalTo: leadingAnchor),
            checkView.topAnchor.constraint(equalTo: topAnchor, constant: -2),
            checkView.widthAnchor.constraint(equalToConstant: 22),
            checkView.heightAnchor.constraint(equalToConstant: 22),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 34),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isAccessibilityElement = true
        accessibilityLabel = text.string
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }
}
