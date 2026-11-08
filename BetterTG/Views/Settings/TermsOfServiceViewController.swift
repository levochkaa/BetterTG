// TermsOfServiceViewController.swift

import TDLibKit
import UIKit

// MARK: - TermsOfServiceViewController

/// Telegram's TermsOfServiceController for updateTermsOfService: Terms of Service over the new text, which scrolls,
/// with Decline and Agree & Continue under it. Agree asks PrivacyPolicy's age question first when the terms set a
/// minimum age; Decline warns that the account will be deleted, as TDLib requires, before `onDecline` deletes it.
final class TermsOfServiceViewController: UIViewController, UITextViewDelegate {
    private let terms: TermsOfService
    private let onAccept: (@escaping (Bool) -> Void) -> Void
    private let onDecline: () -> Void
    private let textView = UITextView()
    private let declineButton = UIButton(configuration: .plain())
    private let acceptButton = UIButton(configuration: .plain())
    private let spinner = UIActivityIndicatorView(style: .medium)

    /// `onAccept` accepts the terms and reports whether it succeeded, which closes the screen.
    init(
        terms: TermsOfService,
        onAccept: @escaping (@escaping (Bool) -> Void) -> Void,
        onDecline: @escaping () -> Void,
    ) {
        self.terms = terms
        self.onAccept = onAccept
        self.onDecline = onDecline
        super.init(nibName: nil, bundle: nil)
        isModalInPresentation = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Login.TermsOfServiceHeader")
        view.backgroundColor = .systemBackground
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.attributedText = NSAttributedString(getAttributedString(from: terms.text))
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        textView.dataDetectorTypes = [.link]
        textView.delegate = self
        view.addSubview(textView)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        view.addSubview(separator)

        var decline = AttributedString(L10n.telegram("PrivacyPolicy.Decline"))
        decline.font = .preferredFont(forTextStyle: .body)
        declineButton.configuration?.attributedTitle = decline
        declineButton.addTarget(self, action: #selector(declinePressed), for: .touchUpInside)
        var accept = AttributedString(L10n.telegram("PrivacyPolicy.Accept"))
        accept.font = .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .semibold)
        acceptButton.configuration?.attributedTitle = accept
        acceptButton.addTarget(self, action: #selector(acceptPressed), for: .touchUpInside)
        spinner.hidesWhenStopped = true
        let bar = UIStackView(arrangedSubviews: [declineButton, UIView(), spinner, acceptButton])
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.alignment = .center
        bar.spacing = 8
        view.addSubview(bar)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            separator.topAnchor.constraint(equalTo: textView.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / max(1, traitCollection.displayScale)),
            bar.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 4),
            bar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            bar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
            bar.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    func textView(
        _: UITextView,
        primaryActionFor textItem: UITextItem,
        defaultAction: UIAction,
    ) -> UIAction? {
        guard case .link(let url) = textItem.content else { return defaultAction }
        return UIAction { _ in UIApplication.shared.open(url) }
    }

    @objc private func acceptPressed() {
        guard terms.minUserAge > 0 else {
            accept()
            return
        }
        let alert = UIAlertController(
            title: L10n.telegram("PrivacyPolicy.AgeVerificationTitle"),
            message: L10n.telegram("PrivacyPolicy.AgeVerificationMessage", "\(terms.minUserAge)"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("PrivacyPolicy.AgeVerificationAgree"), style: .default) {
            [weak self] _ in self?.accept()
        })
        present(alert, animated: true)
    }

    private func accept() {
        setInProgress(true)
        onAccept { [weak self] succeeded in
            guard let self else { return }
            if succeeded {
                dismiss(animated: true)
            } else {
                setInProgress(false)
                let alert = UIAlertController(
                    title: nil,
                    message: L10n.telegram("Login.UnknownError"),
                    preferredStyle: .alert,
                )
                alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    /// leftAction: PrivacyPolicy.Decline's warning, whose Decline and Delete deletes the account.
    @objc private func declinePressed() {
        let alert = UIAlertController(
            title: L10n.telegram("PrivacyPolicy.Decline"),
            message: L10n.telegram("PrivacyPolicy.DeclineMessage"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(
            title: L10n.telegram("PrivacyPolicy.DeclineDeclineAndDelete"),
            style: .destructive,
        ) { [weak self] _ in
            self?.setInProgress(true)
            self?.onDecline()
        })
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func setInProgress(_ inProgress: Bool) {
        acceptButton.isEnabled = !inProgress
        declineButton.isEnabled = !inProgress
        if inProgress { spinner.startAnimating() } else { spinner.stopAnimating() }
    }
}

// MARK: - TermsOfServicePresenter

/// ApplicationContext's termsOfServiceUpdate: the active account's new terms over everything, accepted with
/// acceptTermsOfService, or declined by deleting the account with TDLib's "Decline ToS update" reason.
@MainActor enum TermsOfServicePresenter {
    private weak static var presented: UIViewController?

    static func present(_ update: UpdateTermsOfService, client: TDLibClient) {
        guard presented == nil else { return }
        let id = update.termsOfServiceId
        let controller = TermsOfServiceViewController(terms: update.termsOfService) { completion in
            Task {
                let accepted = await (try? client.send(TDNativeRequests.acceptTermsOfService(termsOfServiceId: id)))
                    != nil
                completion(accepted)
            }
        } onDecline: {
            Task {
                _ = try? await client.send(TDNativeRequests.deleteAccount(reason: "Decline ToS update", password: ""))
            }
        }
        show(controller)
    }

    fileprivate static func show(_ controller: TermsOfServiceViewController) {
        let window = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard let presenter = window?.rootViewController?.chatListTopPresenter else { return }
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .fullScreen
        presented = navigation
        presenter.present(navigation, animated: true)
    }
}

#if DEBUG
    extension TermsOfServicePresenter {
        /// `-ui-probe-terms-of-service`: made-up terms with a minimum age, whose Agree and Decline only close the
        /// screen, to look at it without touching the account.
        static func presentProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-terms-of-service") else { return }
            Task {
                try? await ProbeFixtures.waitForActiveAccount()
                try? await Task.sleep(for: .seconds(2))
                let text = "These are BetterTG's probe terms. Read them at https://telegram.org/tos before agreeing."
                let terms = TDNativeTermsOfService(
                    text: TDNativeFormattedText(text: text, entities: []),
                    minUserAge: 18,
                    showPopup: true,
                )
                var controller: TermsOfServiceViewController?
                controller = TermsOfServiceViewController(terms: terms) { completion in
                    completion(true)
                } onDecline: {
                    controller?.dismiss(animated: true)
                }
                if let controller { show(controller) }
            }
        }
    }
#endif
