// SettingsViewController.swift

import Combine
import UIKit

// MARK: - SettingsViewController

final class SettingsViewController: UITableViewController {
    // MARK: Private

    private var cancellables = Set<AnyCancellable>()

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Settings.Title")
        navigationItem.largeTitleDisplayMode = .never
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 58, bottom: 0, right: 0)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")

        nc.publisher(&cancellables, for: .telegramAccountsChanged) { [weak self] _ in
            self?.tableView.reloadData()
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
        tableView.reloadData()
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)
        guard let row = rows(in: indexPath.section)[safe: indexPath.row] else { return cell }

        var configuration = cell.defaultContentConfiguration()
        configuration.text = row.title
        configuration.secondaryText = row.subtitle
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
        case .appearance, .language:
            cell.accessoryType = .disclosureIndicator
        case .animatedMedia:
            let toggle = UISwitch()
            toggle.isOn = UserDefaults.standard.object(forKey: "animatedMediaEnabled") as? Bool ?? true
            toggle.addTarget(self, action: #selector(animatedMediaChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        case .logOut, .version:
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
        case .logOut:
            confirmLogout(from: indexPath)
        case .animatedMedia, .version:
            break
        }
    }

    private func rows(in sectionIndex: Int) -> [Row] {
        guard let section = Section(rawValue: sectionIndex) else { return [] }
        switch section {
        case .accounts:
            let accountRows: [Row] = TDLib.shared.sortedAccounts.map { .account($0.id) }
            return accountRows + [.addAccount]
        case .appearance:
            return [.appearance, .language]
        case .media:
            return [.animatedMedia]
        case .about:
            return [.version]
        case .accountActions:
            return [.logOut]
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
        case accounts
        case appearance
        case media
        case about
        case accountActions

        // MARK: Internal

        var title: String? {
            switch self {
            case .accounts: L10n.betterTG("Accounts.Section")
            case .appearance: L10n.telegram("Settings.Appearance")
            case .media: L10n.betterTG("Settings.MediaSection")
            case .about: L10n.betterTG("Settings.AboutSection")
            case .accountActions: nil
            }
        }
    }

    enum Row: Equatable {
        case account(UUID)
        case addAccount
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
            case .addAccount, .logOut:
                nil
            }
        }

        var symbolName: String {
            switch self {
            case .account: "person.crop.circle.fill"
            case .addAccount: "plus.circle.fill"
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
            case .addAccount, .appearance, .language, .version: .systemBlue
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
