// AdsReportViewController.swift

import TDLibKit
import UIKit

// MARK: - AdsReportViewController

/// Telegram's AdsReportScreen: "Report Ad" over TDLib's options for `reportChatSponsoredMessage`. An option may open
/// more options under its name; the report ends when TDLib takes it (`ok`), hides the ads (`adsHidden`) or needs
/// Premium (`premiumRequired`). Under the options, Telegram's line about its ad guidelines links to them.
final class AdsReportViewController: SettingsListViewController, UITextViewDelegate {
    /// AdsReportScreen's ReportResult.
    enum Outcome {
        case reported
        case hidden
        case premiumRequired
    }

    typealias Report = (Data) async throws -> TDNativeReportSponsoredResult

    private let header: String
    /// The option that led here (SheetPageContent's `title`).
    private let chosenOption: String?
    private let options: [TDNativeReportOption]
    private let report: Report
    private let completion: (Outcome) -> Void
    private var isSending = false

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private init(
        header: String,
        chosenOption: String?,
        options: [TDNativeReportOption],
        report: @escaping Report,
        completion: @escaping (Outcome) -> Void,
    ) {
        self.header = header
        self.chosenOption = chosenOption
        self.options = options
        self.report = report
        self.completion = completion
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("ReportAd.Title")
        navigationItem.subtitle = chosenOption
        tableView.register(
            AdsReportFooterView.self,
            forHeaderFooterViewReuseIdentifier: AdsReportFooterView.reuseIdentifier,
        )
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: L10n.telegram("Common.Cancel"),
                style: .plain,
                target: self,
                action: #selector(cancel),
            )
        }
    }

    override func makeSections() -> [SettingsSection] {
        // SheetPageContent's section header, uppercased.
        [SettingsSection(header: header.uppercased(), rows: options.map { option in
            SettingsRow(title: option.text, accessory: .disclosure, isEnabled: !isSending) { [weak self] in
                self?.choose(option)
            }
        })]
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection _: Int) -> UIView? {
        let footer = tableView.dequeueReusableHeaderFooterView(withIdentifier: AdsReportFooterView.reuseIdentifier)
        (footer as? AdsReportFooterView)?.configure(delegate: self)
        return footer
    }

    /// AdsReportScreen over the first options TDLib returned for the ad.
    static func present(
        title: String,
        options: [TDNativeReportOption],
        report: @escaping Report,
        from presenter: UIViewController,
        completion: @escaping (Outcome) -> Void,
    ) {
        let controller = AdsReportViewController(
            header: title,
            chosenOption: nil,
            options: options,
            report: report,
            completion: completion,
        )
        presenter.chatListTopPresenter.present(
            TelegramNavigationController(rootViewController: controller),
            animated: true,
        )
    }

    func textView(
        _: UITextView,
        primaryActionFor textItem: UITextItem,
        defaultAction _: UIAction,
    ) -> UIAction? {
        guard case .link(let url) = textItem.content else { return nil }
        // Telegram opens the guidelines with `forceExternal`.
        return UIAction { _ in UIApplication.shared.open(url) }
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    /// SheetContent's action: the report with the option; more options push a page under its name.
    private func choose(_ option: TDNativeReportOption) {
        guard !isSending, contextIsCurrent else { return }
        isSending = true
        reload()
        let report = report
        Task { [weak self] in
            let result: TDNativeReportSponsoredResult
            do {
                result = try await report(option.id)
            } catch {
                guard let self, contextIsCurrent else { return }
                isSending = false
                reload()
                presentChatListActionFailure()
                return
            }
            guard let self, contextIsCurrent else { return }
            isSending = false
            reload()
            switch result {
            case .reportSponsoredResultOptionRequired(let required):
                navigationController?.pushViewController(
                    AdsReportViewController(
                        header: required.title,
                        chosenOption: option.text,
                        options: required.options,
                        report: report,
                        completion: completion,
                    ),
                    animated: true,
                )
            case .reportSponsoredResultOk:
                finish(.reported)
            case .reportSponsoredResultAdsHidden:
                finish(.hidden)
            case .reportSponsoredResultPremiumRequired:
                finish(.premiumRequired)
            case .reportSponsoredResultFailed:
                // The ad is too old or gone.
                presentChatListActionFailure()
            }
        }
    }

    private func finish(_ outcome: Outcome) {
        let completion = completion
        let host: UIViewController = navigationController ?? self
        host.dismiss(animated: true) { completion(outcome) }
    }
}

// MARK: - AdsReportFooterView

/// SheetPageContent's footer: ReportAd.Help with its link to Telegram's ad guidelines.
private final class AdsReportFooterView: UITableViewHeaderFooterView {
    static let reuseIdentifier = "AdsReportFooterView"

    private let textView = UITextView()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            textView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -7),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(delegate: UITextViewDelegate) {
        let font = UIFont.preferredFont(forTextStyle: .footnote)
        textView.attributedText = TelegramMarkdownText.make(
            L10n.telegram("ReportAd.Help"),
            font: font,
            boldFont: .systemFont(ofSize: font.pointSize, weight: .semibold),
            color: .secondaryLabel,
            linkColor: .tintColor,
            defaultLink: URL(string: L10n.telegram("ReportAd.Help_URL")),
        )
        textView.linkTextAttributes = [.foregroundColor: UIColor.tintColor]
        textView.delegate = delegate
    }
}
