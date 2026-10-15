// SettingsViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - SettingsViewController

/// Telegram's Settings (PeerInfoScreen in settings mode): the account's profile, its accounts, Saved Messages,
/// Devices and Chat Folders, then Notifications, Privacy, Data and Storage, Appearance and Language.
final class SettingsViewController: UITableViewController {
    // MARK: Private

    private var cancellables = Set<AnyCancellable>()
    private var me: User?
    private var meAccountID: UUID?
    private var sessionCount: Int?
    private var loadTask: Task<Void, Never>?

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Settings.Title")
        navigationItem.largeTitleDisplayMode = .never
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 58, bottom: 0, right: 0)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")
        tableView.register(SettingsProfileCell.self, forCellReuseIdentifier: SettingsProfileCell.reuseIdentifier)

        nc.publisher(&cancellables, for: .telegramAccountsChanged) { [weak self] _ in
            self?.loadAccountState()
        }
        nc.publisher(&cancellables, for: .appLanguageChanged) { [weak self] _ in
            self?.title = L10n.telegram("Settings.Title")
            self?.tableView.reloadData()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.navigationBar.prefersLargeTitles = false
        loadAccountState()
    }

    override func numberOfSections(in _: UITableView) -> Int { Section.allCases.count }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows(in: section).count
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    override func tableView(_: UITableView, titleForFooterInSection section: Int) -> String? {
        guard Section(rawValue: section) == .media else { return nil }
        return L10n.betterTG("Settings.AnimatedMediaInfo")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if Section(rawValue: indexPath.section) == .profile {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsProfileCell.reuseIdentifier,
                for: indexPath,
            )
            (cell as? SettingsProfileCell)?.configure(
                user: meAccountID == TDLib.shared.activeAccountID ? me : nil,
                client: TDLib.shared.activeClient,
                accountID: TDLib.shared.activeAccountID,
            )
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)
        guard let row = rows(in: indexPath.section)[safe: indexPath.row] else { return cell }

        var configuration = cell.defaultContentConfiguration()
        if row.showsValue {
            configuration = .valueCell()
        }
        configuration.text = row.title
        configuration.secondaryText = row == .devices ? sessionCount.map(String.init) : row.subtitle
        configuration.image = UIImage(systemName: row.symbolName)
        configuration.imageProperties.tintColor = row.tintColor
        configuration.imageProperties.maximumSize = CGSize(width: 25, height: 25)
        configuration.textProperties.color = row.isDestructive ? .systemRed : .label
        configuration.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = configuration
        cell.backgroundColor = .secondarySystemGroupedBackground
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = row.isSelectable ? .default : .none

        switch row {
        case .account(let id):
            cell.accessoryType = id == TDLib.shared.activeAccountID ? .checkmark : .none
        case .addAccount:
            configuration.textProperties.color = .systemBlue
            cell.contentConfiguration = configuration
        case .appearance, .chatFolders, .dataAndStorage, .devices, .language, .notifications, .privacy,
             .savedMessages:
            cell.accessoryType = .disclosureIndicator
        case .animatedMedia:
            let toggle = UISwitch()
            toggle.isOn = UserDefaults.standard.object(forKey: "animatedMediaEnabled") as? Bool ?? true
            toggle.addTarget(self, action: #selector(animatedMediaChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        case .logOut, .profile, .version:
            break
        }
        return cell
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = rows(in: indexPath.section)[safe: indexPath.row] else { return }
        switch row {
        case .account(let id):
            guard id != TDLib.shared.activeAccountID else { return }
            performAccountOperation { try TDLib.shared.switchToAccount(id) }
        case .addAccount:
            performAccountOperation { try TDLib.shared.addAccount() }
        case .appearance:
            navigationController?.pushViewController(AppearanceViewController(), animated: true)
        case .language:
            navigationController?.pushViewController(LanguageSelectionViewController(), animated: true)
        case .profile:
            navigationController?.pushViewController(EditProfileViewController(), animated: true)
        case .savedMessages:
            openSavedMessages()
        case .devices:
            navigationController?.pushViewController(ActiveSessionsViewController(), animated: true)
        case .chatFolders:
            navigationController?.pushViewController(ChatFoldersViewController(rootVM: .shared), animated: true)
        case .notifications:
            navigationController?.pushViewController(NotificationSettingsViewController(), animated: true)
        case .privacy:
            navigationController?.pushViewController(PrivacySettingsViewController(), animated: true)
        case .dataAndStorage:
            navigationController?.pushViewController(DataAndStorageViewController(), animated: true)
        case .logOut:
            confirmLogout(from: indexPath)
        case .animatedMedia, .version:
            break
        }
    }

    private func rows(in sectionIndex: Int) -> [Row] {
        guard let section = Section(rawValue: sectionIndex) else { return [] }
        switch section {
        case .profile:
            return TDLib.shared.activeAccountID == nil ? [] : [.profile]
        case .accounts:
            let accountRows: [Row] = TDLib.shared.sortedAccounts.map { .account($0.id) }
            return accountRows + [.addAccount]
        case .shortcuts:
            return TDLib.shared.activeAccountID == nil ? [] : [.savedMessages, .devices, .chatFolders]
        case .appearance:
            let accountRows: [Row] = TDLib.shared.activeAccountID == nil
                ? []
                : [.notifications, .privacy, .dataAndStorage]
            return accountRows + [.appearance, .language]
        case .media:
            return [.animatedMedia]
        case .about:
            return [.version]
        case .accountActions:
            return [.logOut]
        }
    }

    /// The profile header and the Devices count, read again whenever Settings shows.
    private func loadAccountState() {
        tableView.reloadData()
        guard let accountID = TDLib.shared.activeAccountID else { return }
        let client = TDLib.shared.activeClient
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            async let meRequest = client.getMe()
            async let sessionsRequest = client.send(TDNativeRequests.getActiveSessions())
            let me = try? await meRequest
            let sessions = try? await sessionsRequest
            guard let self, !Task.isCancelled, TDLib.shared.activeAccountID == accountID else { return }
            if let me {
                self.me = me
                meAccountID = accountID
            }
            sessionCount = sessions?.sessions.count
            tableView.reloadData()
        }
    }

    /// Telegram's Saved Messages row opens the account's own chat.
    private func openSavedMessages() {
        guard let accountID = TDLib.shared.activeAccountID else { return }
        let client = TDLib.shared.activeClient
        Task { [weak self] in
            guard let me = try? await client.getMe(),
                  let chat = try? await client.createPrivateChat(force: false, userId: me.id),
                  let customChat = await RootVM.shared.getCustomChatForNavigation(from: chat.id, client: client),
                  self != nil, TDLib.shared.activeAccountID == accountID
            else { return }
            NavigationStorage.shared.push(.customChat(customChat))
        }
    }

    private func performAccountOperation(_ operation: @escaping @MainActor () throws -> Void) {
        Task { @MainActor [weak self] in
            do {
                try operation()
            } catch {
                self?.showError(error.localizedDescription)
            }
        }
    }

    private func confirmLogout(from indexPath: IndexPath) {
        let accountName = TDLib.shared.activeAccount?.localizedTitle ?? L10n.betterTG("Accounts.ThisAccount")
        let alert = UIAlertController(
            title: L10n.telegram("Settings.LogoutConfirmationTitle"),
            message: L10n.betterTG("Accounts.RemoveFromDevice", accountName),
            preferredStyle: .actionSheet,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("Settings.Logout"), style: .destructive) { [weak self] _ in
            self?.performAccountOperation { try TDLib.shared.logOutActiveAccount() }
        })
        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView.cellForRow(at: indexPath)
            popover.sourceRect = tableView.cellForRow(at: indexPath)?.bounds ?? .zero
        }
        present(alert, animated: true)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(
            title: L10n.betterTG("Accounts.ErrorTitle"),
            message: message,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        present(alert, animated: true)
    }

    @objc private func animatedMediaChanged(_ sender: UISwitch) {
        UserDefaults.standard.set(sender.isOn, forKey: "animatedMediaEnabled")
    }
}

private extension SettingsViewController {
    enum Section: Int, CaseIterable {
        case profile
        case accounts
        case shortcuts
        case appearance
        case media
        case about
        case accountActions

        // MARK: Internal

        var title: String? {
            switch self {
            case .accounts: L10n.betterTG("Accounts.Section")
            case .media: L10n.betterTG("Settings.MediaSection")
            case .about: L10n.betterTG("Settings.AboutSection")
            case .accountActions, .appearance, .profile, .shortcuts: nil
            }
        }
    }

    enum Row: Equatable {
        case profile
        case account(UUID)
        case addAccount
        case savedMessages
        case devices
        case chatFolders
        case notifications
        case privacy
        case dataAndStorage
        case appearance
        case language
        case animatedMedia
        case version
        case logOut

        // MARK: Internal

        var account: TelegramAccount? {
            guard case .account(let id) = self else { return nil }
            return TDLib.shared.accounts.first(where: { $0.id == id })
        }

        var title: String {
            switch self {
            case .account:
                account?.localizedTitle ?? L10n.betterTG("Accounts.Account")
            case .addAccount:
                L10n.telegram("Settings.AddAccount")
            case .profile:
                L10n.telegram("EditProfile.Title")
            case .savedMessages:
                L10n.telegram("Settings.SavedMessages")
            case .devices:
                L10n.telegram("Settings.Devices")
            case .chatFolders:
                L10n.telegram("Settings.ChatFolders")
            case .notifications:
                L10n.telegram("Settings.NotificationsAndSounds")
            case .privacy:
                L10n.telegram("Settings.PrivacySettings")
            case .dataAndStorage:
                L10n.telegram("Settings.ChatSettings")
            case .appearance:
                L10n.telegram("Conversation.Theme")
            case .language:
                L10n.telegram("Settings.AppLanguage")
            case .animatedMedia:
                L10n.betterTG("Settings.AnimatedMedia")
            case .version:
                L10n.betterTG("Settings.Version")
            case .logOut:
                L10n.telegram("Settings.Logout")
            }
        }

        var subtitle: String? {
            switch self {
            case .account(let id):
                id == TDLib.shared.activeAccountID
                    ? L10n.betterTG("Accounts.Current")
                    : account?.phoneNumber.map { "+\($0)" }
            case .appearance:
                AppAppearance.current.title
            case .language:
                AppLocalization.shared.currentLanguage.nativeName
            case .animatedMedia:
                L10n.betterTG("Settings.AnimatedMediaFormats")
            case .version:
                Utils.applicationVersion
            case .addAccount, .chatFolders, .dataAndStorage, .devices, .logOut, .notifications, .privacy, .profile,
                 .savedMessages:
                nil
            }
        }

        /// Rows that show their value on the right, as Telegram's disclosure items do.
        var showsValue: Bool {
            switch self {
            case .appearance, .devices, .language: true
            default: false
            }
        }

        var symbolName: String {
            switch self {
            case .profile: "person.crop.circle"
            case .account: "person.crop.circle.fill"
            case .addAccount: "plus.circle.fill"
            case .savedMessages: "bookmark.fill"
            case .devices: "laptopcomputer.and.iphone"
            case .chatFolders: "folder.fill"
            case .notifications: "bell.badge.fill"
            case .privacy: "lock.fill"
            case .dataAndStorage: "externaldrive.fill"
            case .appearance: "paintpalette.fill"
            case .language: "globe"
            case .animatedMedia: "sparkles.tv"
            case .version: "info.circle.fill"
            case .logOut: "rectangle.portrait.and.arrow.right"
            }
        }

        var tintColor: UIColor {
            switch self {
            case .account: .systemTeal
            case .addAccount, .appearance, .language, .profile, .savedMessages, .version: .systemBlue
            case .devices: .systemOrange
            case .chatFolders: .systemCyan
            case .notifications: .systemRed
            case .privacy: .systemGray
            case .dataAndStorage: .systemGreen
            case .animatedMedia: .systemPurple
            case .logOut: .systemRed
            }
        }

        var isSelectable: Bool {
            switch self {
            case .animatedMedia, .version:
                false
            default:
                true
            }
        }

        var isDestructive: Bool { self == .logOut }
    }
}

// MARK: - SettingsProfileCell

/// Telegram's settings header: the account's photo, name, phone number and username, opening Edit Profile.
private final class SettingsProfileCell: UITableViewCell {
    static let reuseIdentifier = "SettingsProfileCell"

    private let avatarView = ProfileAvatarView()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .secondarySystemGroupedBackground
        accessoryType = .disclosureIndicator
        let labels = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        labels.axis = .vertical
        labels.spacing = 3
        for subview in [avatarView, labels] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        avatarView.isUserInteractionEnabled = false
        nameLabel.font = .preferredFont(forTextStyle: .title3)
        nameLabel.adjustsFontForContentSizeCategory = true
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 2
        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            avatarView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            avatarView.widthAnchor.constraint(equalToConstant: 64),
            avatarView.heightAnchor.constraint(equalToConstant: 64),
            labels.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 14),
            labels.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            labels.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    func configure(user: User?, client: TDLibClient, accountID: UUID?) {
        guard let user else {
            nameLabel.text = TDLib.shared.activeAccount?.localizedTitle
            detailLabel.text = nil
            return
        }
        nameLabel.text = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        var details = [String]()
        if !user.phoneNumber.isEmpty { details.append("+\(user.phoneNumber)") }
        if let username = user.usernames?.editableUsername, !username.isEmpty { details.append("@\(username)") }
        detailLabel.text = details.joined(separator: " • ")
        accessibilityLabel = [nameLabel.text, detailLabel.text].compactMap(\.self).joined(separator: ", ")
        // The account's own photo, never the Saved Messages icon.
        avatarView.configure(
            file: user.profilePhoto?.small,
            largeFile: user.profilePhoto?.big,
            minithumbnail: user.profilePhoto?.minithumbnail,
            placeholder: user.telegramAvatarPlaceholder,
            accountID: accountID,
            accountUserID: 0,
            client: client,
        )
    }
}
