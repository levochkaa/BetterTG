// TelegramLinkRouter.swift

import Combine
import TDLibKit
import UIKit

// MARK: - TelegramLinkRouter

@MainActor final class TelegramLinkRouter {
    static let shared = TelegramLinkRouter()

    private var cancellables = Set<AnyCancellable>()
    private var pendingLanguageID: String?
    private weak var pendingWindow: UIWindow?

    private init() {
        nc.publisher(&cancellables, for: .authorizationStateReady) { [weak self] _ in
            DispatchQueue.main.async { self?.openPendingLanguage() }
        }
    }

    static func languagePackID(in url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let scheme = components.scheme?.lowercased()
        let host = components.host?.lowercased()
        let identifier: String?
        if scheme == "https" || scheme == "http" {
            guard ["t.me", "telegram.me", "telegram.dog"].contains(host),
                  components.user == nil, components.password == nil else { return nil }
            let path = components.path.split(separator: "/")
            guard path.count == 2, ["setlanguage", "addlanguage"].contains(path[0].lowercased()) else { return nil }
            identifier = String(path[1])
        } else if scheme == "tg" || scheme == "bettertg" {
            guard host == "setlanguage" || host == "addlanguage" else { return nil }
            identifier = components.queryItems?.first(where: { $0.name == "lang" })?.value
        } else {
            return nil
        }
        guard let identifier, !identifier.isEmpty, identifier.utf8.count <= 128,
              identifier.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
                      .contains($0)
              }) else { return nil }
        return identifier
    }

    func open(_ url: URL, from presenter: UIViewController?) {
        guard handle(url, from: presenter) else {
            UIApplication.shared.open(url)
            return
        }
    }

    @discardableResult func handle(_ url: URL, from presenter: UIViewController?) -> Bool {
        guard let identifier = Self.languagePackID(in: url) else { return false }
        guard TDLib.shared.isActiveAccountReady else {
            pendingLanguageID = identifier
            pendingWindow = presenter?.viewIfLoaded?.window
            return true
        }
        guard let presenter else { return true }
        presenter.view.endEditing(true)
        topPresenter(presenter).present(LanguagePackPreviewViewController(identifier: identifier), animated: true)
        return true
    }

    private func openPendingLanguage() {
        guard TDLib.shared.isActiveAccountReady, let identifier = pendingLanguageID,
              let root = pendingWindow?.rootViewController else { return }
        pendingLanguageID = nil
        topPresenter(root).present(LanguagePackPreviewViewController(identifier: identifier), animated: true)
    }

    private func topPresenter(_ root: UIViewController) -> UIViewController {
        if let presented = root.presentedViewController { return topPresenter(presented) }
        if let navigation = root as? UINavigationController, let visible = navigation.visibleViewController {
            return topPresenter(visible)
        }
        if let child = root.children.last(where: { $0.viewIfLoaded?.window != nil }) { return topPresenter(child) }
        return root
    }
}

// MARK: - LanguagePackPreviewViewController

/// UIKit adaptation of Telegram's LanguageLinkPreviewController: preview first, apply on the user's action.
@MainActor private final class LanguagePackPreviewViewController: UIViewController {
    private let identifier: String
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let applyButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var language: AppLanguage?
    private var task: Task<Void, Never>?

    init(identifier: String) {
        self.identifier = identifier
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { task?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        sheetPresentationController?.detents = [.medium(), .large()]
        sheetPresentationController?.prefersGrabberVisible = true
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.text = L10n.telegram("Settings.AppLanguage")
        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0
        bodyLabel.text = identifier
        bodyLabel.accessibilityIdentifier = "language-pack-preview"
        applyButton.setTitle(L10n.telegram("ApplyLanguage.ChangeLanguageAction"), for: .normal)
        applyButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .medium)
        applyButton.accessibilityIdentifier = "language-pack-apply"
        applyButton.isEnabled = false
        applyButton.addTarget(self, action: #selector(applyLanguage), for: .touchUpInside)
        cancelButton.setTitle(L10n.telegram("Common.Cancel"), for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .medium)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel, spinner, applyButton, cancelButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48),
            applyButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
        spinner.startAnimating()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let language = try await AppLocalization.shared.languagePack(id: identifier)
                try Task.checkCancellation()
                self.language = language
                spinner.stopAnimating()
                titleLabel.text = L10n.telegram("ApplyLanguage.ChangeLanguageTitle")
                bodyLabel.text = L10n.betterTG(
                    "Localization.Preview",
                    language.nativeName,
                    min(100, Int(language.translationProgress * 100)),
                )
                applyButton.isEnabled = language.totalStringCount > 0
                if language.id == AppLocalization.shared.selectedLanguagePackID {
                    bodyLabel.text = L10n.telegram("ApplyLanguage.ChangeLanguageAlreadyActive", language.nativeName)
                    applyButton.isEnabled = false
                    cancelButton.setTitle(L10n.telegram("Common.OK"), for: .normal)
                }
            } catch is CancellationError {
                dismiss(animated: true)
            } catch {
                spinner.stopAnimating()
                bodyLabel.text = L10n.telegram("ApplyLanguage.LanguageNotSupportedError")
            }
        }
    }

    @objc private func applyLanguage() {
        guard let language, applyButton.isEnabled else { return }
        applyButton.isEnabled = false
        spinner.startAnimating()
        isModalInPresentation = true
        cancelButton.isEnabled = false
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await AppLocalization.shared.apply(language)
                dismiss(animated: true)
            } catch {
                spinner.stopAnimating()
                bodyLabel.text = L10n.betterTG("Localization.DownloadError")
                applyButton.isEnabled = true
                cancelButton.isEnabled = true
                isModalInPresentation = false
            }
        }
    }

    @objc private func cancel() {
        task?.cancel()
        dismiss(animated: true)
    }
}
