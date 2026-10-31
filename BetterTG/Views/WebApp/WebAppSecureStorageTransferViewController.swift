// WebAppSecureStorageTransferViewController.swift

import TDLibKit
import UIKit

/// Telegram's WebAppSecureStorageTransferScreen: a bot asks to import the SecureStorage data that an account no
/// longer signed in left on this device. The sheet shows the bot, its request and those accounts with the date each
/// stored the key; Import gives the chosen account's identifier, closing gives nil.
@MainActor final class WebAppSecureStorageTransferViewController: UIViewController,
UIAdaptivePresentationControllerDelegate {
    private let keys: [WebAppSecureStorage.ExistingKey]
    private let botUserID: Int64
    private let botName: String
    private let accountID: UUID?
    private let client: TDLibClient
    private var completion: ((String?) -> Void)?
    private var selectedIndex = 0
    private var rowChecks = [UIImageView]()
    private let avatarView = ProfileAvatarView()

    init(
        keys: [WebAppSecureStorage.ExistingKey],
        botUserID: Int64,
        botName: String,
        accountID: UUID?,
        client: TDLibClient,
        completion: @escaping (String?) -> Void,
    ) {
        self.keys = keys
        self.botUserID = botUserID
        self.botName = botName
        self.accountID = accountID
        self.client = client
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        presentationController?.delegate = self
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
        }

        let close = UIButton(type: .system, primaryAction: UIAction { [weak self] _ in self?.finish(with: nil) })
        close.setImage(UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
        ), for: .normal)
        close.tintColor = .secondaryLabel
        close.accessibilityLabel = L10n.telegram("Common.Close")

        let titleLabel = UILabel()
        titleLabel.text = L10n.telegram("WebApp.ImportData.Title")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.accessibilityTraits = .header

        let descriptionLabel = UILabel()
        descriptionLabel.numberOfLines = 0
        descriptionLabel.textAlignment = .center
        descriptionLabel.attributedText = Self.markdown(
            L10n.telegram("WebApp.ImportData.Description", botName),
            font: .systemFont(ofSize: 15),
        )

        let header = UILabel()
        header.text = L10n.telegram("WebApp.ImportData.AccountHeader").uppercased()
        header.font = .systemFont(ofSize: 13)
        header.textColor = .secondaryLabel

        let list = UIStackView()
        list.axis = .vertical
        list.backgroundColor = .secondarySystemGroupedBackground
        list.layer.cornerRadius = 10
        list.layer.cornerCurve = .continuous
        list.clipsToBounds = true
        for (index, key) in keys.enumerated() {
            if index > 0 {
                let separator = UIView()
                separator.backgroundColor = .separator
                separator.heightAnchor
                    .constraint(equalToConstant: 1 / max(1, traitCollection.displayScale))
                    .isActive = true
                let inset = UIView()
                inset.addSubview(separator)
                separator.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    separator.leadingAnchor.constraint(equalTo: inset.leadingAnchor, constant: 16),
                    separator.trailingAnchor.constraint(equalTo: inset.trailingAnchor),
                    separator.topAnchor.constraint(equalTo: inset.topAnchor),
                    separator.bottomAnchor.constraint(equalTo: inset.bottomAnchor),
                ])
                list.addArrangedSubview(inset)
            }
            list.addArrangedSubview(row(for: key, index: index))
        }

        let importButton = UIButton(type: .system, primaryAction: UIAction { [weak self] _ in
            guard let self, keys.indices.contains(selectedIndex) else { return }
            finish(with: keys[selectedIndex].uuid)
        })
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .fixed
        configuration.background.cornerRadius = 10
        configuration.attributedTitle = AttributedString(
            L10n.telegram("WebApp.ImportData.Import"),
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]),
        )
        importButton.configuration = configuration

        avatarView.isUserInteractionEnabled = false
        let avatarContainer = UIView()
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarContainer.addSubview(avatarView)
        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: avatarContainer.topAnchor),
            avatarView.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor),
            avatarView.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 80),
            avatarView.heightAnchor.constraint(equalToConstant: 80),
        ])
        let content = UIStackView(arrangedSubviews: [avatarContainer, descriptionLabel, header, list])
        content.axis = .vertical
        content.alignment = .fill
        content.setCustomSpacing(22, after: avatarContainer)
        content.setCustomSpacing(29, after: descriptionLabel)
        content.setCustomSpacing(7, after: header)

        for subview in [close, titleLabel, content, importButton] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            close.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: close.trailingAnchor, constant: 8),
            content.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            importButton.topAnchor.constraint(greaterThanOrEqualTo: content.bottomAnchor, constant: 24),
            importButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            importButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            importButton.heightAnchor.constraint(equalToConstant: 50),
            importButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),
        ])
        loadAvatar()
        updateChecks()
    }

    /// Telegram's **bold** markers.
    private static func markdown(_ text: String, font: UIFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, part) in text.components(separatedBy: "**").enumerated() {
            result.append(NSAttributedString(string: part, attributes: [
                .font: index.isMultiple(of: 2) ? font : UIFont.systemFont(ofSize: font.pointSize, weight: .semibold),
                .foregroundColor: UIColor.label,
            ]))
        }
        return result
    }

    func presentationControllerDidDismiss(_: UIPresentationController) {
        finish(with: nil, dismissing: false)
    }

    private func row(for key: WebAppSecureStorage.ExistingKey, index: Int) -> UIView {
        let button = UIButton(type: .system, primaryAction: UIAction { [weak self] _ in
            self?.selectedIndex = index
            self?.updateChecks()
        })
        let name = UILabel()
        name.text = key.accountName
        name.font = .systemFont(ofSize: 17, weight: .semibold)
        name.textColor = .label
        let date = UILabel()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        date.text = L10n.telegram(
            "WebApp.ImportData.CreatedOn",
            formatter.string(from: Date(timeIntervalSince1970: TimeInterval(key.timestamp))),
        )
        date.font = .systemFont(ofSize: 15)
        date.textColor = .secondaryLabel
        let labels = UIStackView(arrangedSubviews: [name, date])
        labels.axis = .vertical
        labels.spacing = 3
        labels.isUserInteractionEnabled = false
        let check = UIImageView()
        check.tintColor = .tintColor
        check.contentMode = .scaleAspectFit
        rowChecks.append(check)
        for subview in [check, labels] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            check.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 16),
            check.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 22),
            check.heightAnchor.constraint(equalToConstant: 22),
            labels.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 16),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -16),
            labels.topAnchor.constraint(equalTo: button.topAnchor, constant: 11),
            labels.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -11),
        ])
        button.accessibilityLabel = [name.text, date.text].compactMap(\.self).joined(separator: ", ")
        return button
    }

    private func updateChecks() {
        for (index, check) in rowChecks.enumerated() {
            let selected = index == selectedIndex
            check.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
            check.tintColor = selected ? .tintColor : .tertiaryLabel
            check.superview?.accessibilityTraits = selected ? [.button, .selected] : .button
        }
    }

    private func loadAvatar() {
        let client = client
        let botUserID = botUserID
        Task { [weak self] in
            guard let user = try? await client.getUser(userId: botUserID), let self else { return }
            avatarView.configure(
                file: user.profilePhoto?.small,
                minithumbnail: user.profilePhoto?.minithumbnail,
                placeholder: user.telegramAvatarPlaceholder,
                accountID: accountID,
                client: client,
            )
        }
    }

    private func finish(with uuid: String?, dismissing: Bool = true) {
        guard let completion else { return }
        self.completion = nil
        completion(uuid)
        if dismissing { dismiss(animated: true) }
    }
}
