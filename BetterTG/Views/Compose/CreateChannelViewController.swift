// CreateChannelViewController.swift

import TDLibKit
import UIKit

// MARK: - ChannelIntroViewController

/// The splash Telegram shows before a first channel (ComposeController.openCreateNewChannel's PermissionController):
/// what a channel is, and Create Channel, which takes this screen's place with the channel's details.
final class ChannelIntroViewController: UIViewController, ComposeFlowScreen {
    private let iconView = UIImageView(image: UIImage(systemName: "megaphone.fill"))
    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private let createButton = UIButton(configuration: .filled())

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit
        iconView.isAccessibilityElement = false
        titleLabel.text = L10n.telegram("ChannelIntro.Title")
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header
        textLabel.text = L10n.telegram("ChannelIntro.Text")
        textLabel.font = .preferredFont(forTextStyle: .body)
        textLabel.adjustsFontForContentSizeCategory = true
        textLabel.textColor = .secondaryLabel
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 0
        createButton.configuration?.title = L10n.telegram("ChannelIntro.CreateChannel")
        createButton.configuration?.cornerStyle = .large
        createButton.configuration?.buttonSize = .large
        createButton.addTarget(self, action: #selector(createPressed), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, textLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.setCustomSpacing(24, after: iconView)
        for subview in [stack, createButton] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 96),
            iconView.heightAnchor.constraint(equalToConstant: 96),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: -40),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
            createButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            createButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            createButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    /// PermissionController.proceed: replaceTopController with the channel's details.
    @objc private func createPressed() {
        guard let navigationController, navigationController.topViewController === self else { return }
        var controllers = navigationController.viewControllers
        controllers[controllers.count - 1] = CreateChannelViewController()
        navigationController.setViewControllers(controllers, animated: true)
    }
}

// MARK: - CreateChannelViewController

/// Telegram's createChannelController: the channel's photo, name and optional description. Next (on its tap only)
/// creates the channel (createNewSupergroupChat with isChannel), sets the photo and goes on to its link setup, which
/// replaces the compose screens as Telegram's replaceAllButRootController does.
final class CreateChannelViewController: SettingsListViewController, ComposeFlowScreen {
    private static let descriptionLimit = 255

    private let photoHeader = ComposePhotoHeaderView(buttonTitle: L10n.telegram("Channel.UpdatePhotoItem"))
    private lazy var photoPicker = ComposePhotoPicker(host: self)
    private var channelTitle = ""
    private var channelDescription = ""
    private var photo: UIImage?
    private var isCreating = false
    private var createTask: Task<Void, Never>?

    deinit {
        createTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("ChannelIntro.CreateChannel")
        photoHeader.onSetPhoto = { [weak self] source in
            guard let self else { return }
            photoPicker.presentMenu(from: source, hasPhoto: photo != nil)
        }
        photoPicker.onChange = { [weak self] image in
            self?.photo = image
            self?.photoHeader.setPhoto(image)
        }
        photoHeader.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: ComposePhotoHeaderView.height)
        tableView.tableHeaderView = photoHeader
        updateNextButton()
    }

    override func makeSections() -> [SettingsSection] {
        [
            SettingsSection(rows: [SettingsRow(title: "", style: .input(SettingsTextInput(
                text: channelTitle,
                placeholder: L10n.telegram("GroupInfo.ChannelListNamePlaceholder"),
                maxLength: 128,
            ) { [weak self] text in
                self?.channelTitle = text
                self?.updateNextButton()
            }))]),
            SettingsSection(footer: L10n.telegram("Channel.About.Help"), rows: [SettingsRow(
                title: "",
                style: .input(SettingsTextInput(
                    text: channelDescription,
                    placeholder: L10n.telegram("Channel.Edit.AboutItem"),
                    maxLength: Self.descriptionLimit,
                    isMultiline: true,
                ) { [weak self] text in self?.channelDescription = text }),
            )]),
        ]
    }

    /// CreateChannelController's error texts.
    private static func failureText(_ error: Error) -> String {
        let message = (error as? TDLibError)?.message ?? ""
        return message.contains("RESTRICTED")
            ? L10n.telegram("Common.ActionNotAllowedError")
            : L10n.telegram("Login.UnknownError")
    }

    private func updateNextButton() {
        guard !isCreating else {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: indicator)
            return
        }
        let button = navigationItem.rightBarButtonItem?.action == #selector(nextPressed)
            ? navigationItem.rightBarButtonItem
            : UIBarButtonItem(
                title: L10n.telegram("Common.Next"),
                style: .prominent,
                target: self,
                action: #selector(nextPressed),
            )
        button?.isEnabled = !channelTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        navigationItem.rightBarButtonItem = button
    }

    /// createChannelController's done: the channel, its photo, then its link setup.
    @objc private func nextPressed() {
        let title = channelTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isCreating, contextIsCurrent else { return }
        view.endEditing(true)
        isCreating = true
        photoHeader.setEnabled(false)
        updateNextButton()
        let client = client
        let description = channelDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let photo = photo
        createTask = Task { [weak self] in
            do {
                let chat = try await client.send(TDNativeRequests.createNewSupergroupChat(
                    title: title,
                    isForum: false,
                    isChannel: true,
                    description: description,
                    location: nil,
                    messageAutoDeleteTime: 0,
                    forImport: false,
                ))
                if let photo {
                    _ = await ComposePhotoPicker.upload(photo, chatID: chat.id, client: client)
                }
                guard let self else { return }
                createTask = nil
                guard contextIsCurrent else { return }
                guard case .chatTypeSupergroup(let supergroup) = chat.type else {
                    _ = await ComposeContacts.open(chatID: chat.id, client: client) { self.contextIsCurrent }
                    return
                }
                NavigationStorage.shared.replaceComposeFlow(with: ChannelLinkSetupViewController(
                    chatID: chat.id,
                    supergroupID: supergroup.supergroupId,
                ))
            } catch {
                guard let self else { return }
                createTask = nil
                isCreating = false
                photoHeader.setEnabled(true)
                updateNextButton()
                guard contextIsCurrent else { return }
                presentAlert(title: nil, message: Self.failureText(error))
            }
        }
    }
}
