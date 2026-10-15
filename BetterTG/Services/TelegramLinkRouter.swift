// TelegramLinkRouter.swift

import Combine
import TDLibKit
import UIKit

// MARK: - TelegramLinkRouter

@MainActor final class TelegramLinkRouter {
    /// A link that waits until the account is ready.
    private enum PendingLink {
        case language(String)
        case chatFolder(String)
    }

    static let shared = TelegramLinkRouter()

    private var cancellables = Set<AnyCancellable>()
    private var pendingLink: PendingLink?
    private weak var pendingWindow: UIWindow?

    private init() {
        nc.publisher(&cancellables, for: .authorizationStateReady) { [weak self] _ in
            DispatchQueue.main.async { self?.openPendingLink() }
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
        guard let identifier, isLinkIdentifier(identifier) else { return nil }
        return identifier
    }

    /// Telegram's UrlHandling for folder invite links: t.me/addlist/<slug> (also /folder/ and /list/) and
    /// tg://addlist?slug=<slug>, as the t.me link `checkChatFolderInviteLink` takes.
    static func chatFolderInviteLink(in url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let scheme = components.scheme?.lowercased()
        let host = components.host?.lowercased()
        let slug: String?
        if scheme == "https" || scheme == "http" {
            guard ["t.me", "telegram.me", "telegram.dog"].contains(host),
                  components.user == nil, components.password == nil else { return nil }
            let path = components.path.split(separator: "/")
            guard path.count == 2, ["addlist", "folder", "list"].contains(path[0].lowercased()) else { return nil }
            slug = String(path[1])
        } else if scheme == "tg" || scheme == "bettertg" {
            guard host == "addlist" else { return nil }
            slug = components.queryItems?.first(where: { $0.name == "slug" })?.value
        } else {
            return nil
        }
        guard let slug, isLinkIdentifier(slug) else { return nil }
        return "https://t.me/addlist/\(slug)"
    }

    private static func isLinkIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.utf8.count <= 128 && identifier.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains($0)
        }
    }

    func open(_ url: URL, from presenter: UIViewController?) {
        guard handle(url, from: presenter) else {
            UIApplication.shared.open(url)
            return
        }
    }

    @discardableResult func handle(_ url: URL, from presenter: UIViewController?) -> Bool {
        let link: PendingLink
        if let inviteLink = Self.chatFolderInviteLink(in: url) {
            link = .chatFolder(inviteLink)
        } else if let identifier = Self.languagePackID(in: url) {
            link = .language(identifier)
        } else {
            return false
        }
        guard TDLib.shared.isActiveAccountReady else {
            pendingLink = link
            pendingWindow = presenter?.viewIfLoaded?.window
            return true
        }
        guard let presenter else { return true }
        presenter.view.endEditing(true)
        present(link, from: topPresenter(presenter))
        return true
    }

    private func openPendingLink() {
        guard TDLib.shared.isActiveAccountReady, let link = pendingLink,
              let root = pendingWindow?.rootViewController else { return }
        pendingLink = nil
        present(link, from: topPresenter(root))
    }

    private func present(_ link: PendingLink, from presenter: UIViewController) {
        switch link {
        case .language(let identifier):
            presenter.present(LanguagePackPreviewViewController(identifier: identifier), animated: true)
        case .chatFolder(let inviteLink):
            ChatFolderInviteLinkPreviewViewController.present(inviteLink: inviteLink, from: presenter)
        }
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
    private let applyButton = TelegramSheetActionButton()
    private let cancelButton = TelegramSheetActionButton()
    private let dimmer = UIControl()
    private let sheetStack = UIStackView()
    private let textStack = UIStackView()
    private var textHeight: NSLayoutConstraint!
    private var sheetWidth: NSLayoutConstraint!
    private var language: AppLanguage?
    private var task: Task<Void, Never>?
    private var didAnimateIn = false
    private var isApplying = false

    init(identifier: String) {
        self.identifier = identifier
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        dimmer.translatesAutoresizingMaskIntoConstraints = false
        dimmer.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        view.addSubview(dimmer)
        sheetStack.translatesAutoresizingMaskIntoConstraints = false
        sheetStack.axis = .vertical
        sheetStack.spacing = 8
        view.addSubview(sheetStack)
        sheetWidth = sheetStack.widthAnchor.constraint(equalToConstant: 382)
        NSLayoutConstraint.activate([
            dimmer.topAnchor.constraint(equalTo: view.topAnchor),
            dimmer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sheetStack.centerXAnchor.constraint(equalTo: view.centerXAnchor), sheetWidth,
            sheetStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
        ])
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 16
        card.clipsToBounds = true
        sheetStack.addArrangedSubview(card)
        sheetStack.addArrangedSubview(cancelButton)
        cancelButton.backgroundColor = .secondarySystemBackground
        cancelButton.layer.cornerRadius = 16
        cancelButton.clipsToBounds = true
        for button in [applyButton, cancelButton] {
            button.heightAnchor.constraint(equalToConstant: 57).isActive = true
        }
        applyButton.setTitle(L10n.telegram("ApplyLanguage.ChangeLanguageAction"), for: .normal)
        applyButton.accessibilityIdentifier = "language-pack-apply"
        applyButton.isEnabled = false
        applyButton.addTarget(self, action: #selector(applyLanguage), for: .touchUpInside)
        cancelButton.setTitle(L10n.telegram("Common.Cancel"), for: .normal)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        titleLabel.font = .systemFont(ofSize: 18, weight: .medium)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.text = L10n.telegram("Settings.AppLanguage")
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0
        bodyLabel.text = identifier
        bodyLabel.accessibilityIdentifier = "language-pack-preview"
        textStack.axis = .vertical
        textStack.spacing = 12
        textStack.translatesAutoresizingMaskIntoConstraints = false
        [titleLabel, bodyLabel, spinner].forEach(textStack.addArrangedSubview)
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = false
        card.addSubview(scroll)
        scroll.addSubview(textStack)
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(applyButton)
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(separator)
        textHeight = scroll.heightAnchor.constraint(equalToConstant: 120)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: card.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor), textHeight,
            textStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            textStack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -10),
            textStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -12),
            textStack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -20),
            applyButton.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            applyButton.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            applyButton.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            applyButton.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            separator.topAnchor.constraint(equalTo: applyButton.topAnchor),
            separator.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),
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
            } catch is CancellationError { dismiss(animated: true) }
            catch {
                spinner.stopAnimating()
                bodyLabel.text = L10n.telegram("ApplyLanguage.LanguageNotSupportedError")
            }
            view.setNeedsLayout()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = min(view.bounds.width, view.bounds.height) - 20
        if abs(sheetWidth.constant - width) > 0.5 { sheetWidth.constant = width }
        let fitting = textStack.systemLayoutSizeFitting(
            CGSize(width: max(1, width - 20), height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        )
        let available = max(60, view.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom - 142)
        let height = min(available, ceil(fitting.height + 24))
        if abs(textHeight.constant - height) > 0.5 { textHeight.constant = height }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAnimateIn else { return }
        didAnimateIn = true
        sheetStack.transform = CGAffineTransform(translationX: 0, y: sheetStack.bounds.height + 40)
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction],
        ) { self.sheetStack.transform = .identity }
    }

    @objc private func applyLanguage() {
        guard let language, applyButton.isEnabled else { return }
        isApplying = true
        applyButton.isEnabled = false
        spinner.startAnimating()
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
                isApplying = false
                view.setNeedsLayout()
            }
        }
    }

    @objc private func cancel() {
        guard !isApplying else { return }
        task?.cancel()
        dismiss(animated: true)
    }
}

// MARK: - TelegramSheetActionButton

/// An action button of Telegram's action-sheet previews (language pack, chat invite link).
final class TelegramSheetActionButton: UIControl {
    override var isEnabled: Bool { didSet { updateAppearance() } }
    override var isHighlighted: Bool { didSet { updateAppearance() } }

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 20, weight: .medium)
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isAccessibilityElement = true
        updateAppearance()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTitle(_ title: String?, for _: UIControl.State) {
        label.text = title
        accessibilityLabel = title
    }

    private func updateAppearance() {
        backgroundColor = isHighlighted ? .tertiarySystemBackground : .secondarySystemBackground
        label.textColor = isEnabled ? .systemBlue : .tertiaryLabel
        accessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
    }
}
