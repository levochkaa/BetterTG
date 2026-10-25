// LicensesViewController.swift

import UIKit

// MARK: - LicensesViewController

/// Settings' Licenses: BetterTG's source code and license, and the open-source components in the app with their
/// license texts from `Resources/Licenses`.
final class LicensesViewController: SettingsListViewController {
    private struct Component {
        let name: String
        let license: String
        /// The text's name in the bundle, without `.txt`.
        let resource: String
    }

    private static let sourceCodeURL = URL(string: "https://github.com/levochkaa/BetterTG")

    private static let components = [
        Component(name: "FFmpeg", license: "LGPL-2.1-or-later", resource: "License-FFmpeg"),
        Component(name: "libwebp", license: "BSD-3-Clause", resource: "License-libwebp"),
        Component(name: "Lottie", license: "Apache-2.0", resource: "License-Lottie"),
        Component(name: "OpenSSL", license: "Apache-2.0", resource: "License-OpenSSL"),
        Component(name: "rlottie", license: "LGPL-2.1-or-later", resource: "License-rlottie"),
        Component(name: "SwiftMath", license: "MIT, OFL-1.1, GUST", resource: "License-SwiftMath"),
        Component(name: "TDLib", license: "BSL-1.0", resource: "License-TDLib"),
        Component(name: "TDLibKit", license: "MIT", resource: "License-TDLibKit"),
        Component(name: "Telegram for iOS", license: "GPL-2.0-or-later", resource: "License-Telegram-iOS"),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.betterTG("Settings.Licenses")
    }

    override func makeSections() -> [SettingsSection] {
        [
            SettingsSection(footer: L10n.betterTG("Licenses.SourceCodeInfo"), rows: [
                SettingsRow(title: L10n.betterTG("Licenses.SourceCode"), accessory: .disclosure) { [weak self] in
                    guard let self, let url = Self.sourceCodeURL else { return }
                    WebBrowser.open(url, from: self)
                },
                SettingsRow(title: "GNU General Public License v3", accessory: .disclosure) { [weak self] in
                    self?.openText(title: "GPL-3.0", resource: "License-GPL-3.0")
                },
            ]),
            SettingsSection(
                header: L10n.betterTG("Licenses.Components"),
                rows: Self.components.map { component in
                    SettingsRow(
                        title: component.name,
                        detail: component.license,
                        style: .subtitle,
                        accessory: .disclosure,
                    ) { [weak self] in
                        self?.openText(title: component.name, resource: component.resource)
                    }
                },
            ),
        ]
    }

    private func openText(title: String, resource: String) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        navigationController?.pushViewController(LicenseTextViewController(title: title, text: text), animated: true)
    }
}

// MARK: - LicenseTextViewController

/// A license's full text.
private final class LicenseTextViewController: UIViewController {
    private let text: String

    init(title: String, text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemBackground

        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .footnote)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 24, right: 12)
        textView.dataDetectorTypes = .link
        textView.text = Self.reflowed(text)
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// Joins the lines a license wraps at about 70 characters, so its paragraphs wrap to the screen. A line after a
    /// short one, such as a title, and a list item keep their breaks.
    private static func reflowed(_ text: String) -> String {
        var lines = [String]()
        var previousLength = 0
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let continuesParagraph = !line.isEmpty && previousLength >= 50
                && line.firstMatch(of: /^(\(?[0-9A-Za-z]{1,3}[.)]|[-*•])\s/) == nil
            if continuesParagraph, let last = lines.popLast() {
                lines.append(last + " " + line)
            } else {
                lines.append(line)
            }
            previousLength = line.count
        }
        return lines.joined(separator: "\n")
    }
}
