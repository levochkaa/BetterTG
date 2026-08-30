// SettingsViewController.swift

import Combine
import UIKit

final class SettingsViewController: UITableViewController {
    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.largeTitleDisplayMode = .never
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 58, bottom: 0, right: 0)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")

        nc.publisher(&cancellables, for: .telegramAccountsChanged) { [weak self] _ in
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
        return "Animated stickers and media can use more processing power."
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
        case .appearance:
            cell.accessoryType = .disclosureIndicator
        case .animatedMedia:
            let toggle = UISwitch()
            toggle.isOn = UserDefaults.standard.object(forKey: "animatedMediaEnabled") as? Bool ?? true
            toggle.addTarget(self, action: #selector(animatedMediaChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        case .version, .logOut:
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
        case .logOut:
            confirmLogout(from: indexPath)
        case .animatedMedia, .version:
            break
        }
    }

    private var cancellables = Set<AnyCancellable>()

    private func rows(in sectionIndex: Int) -> [Row] {
        guard let section = Section(rawValue: sectionIndex) else { return [] }
        switch section {
        case .accounts:
            let accountRows: [Row] = TDLib.shared.sortedAccounts.map { .account($0.id) }
            return accountRows + [.addAccount]
        case .appearance:
            return [.appearance]
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
        let accountName = TDLib.shared.activeAccount?.title ?? "this account"
        let alert = UIAlertController(
            title: "Log Out?",
            message: "\(accountName) will be removed from this device.",
            preferredStyle: .actionSheet,
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Log Out", style: .destructive) { [weak self] _ in
            self?.performAccountOperation { try TDLib.shared.logOutActiveAccount() }
        })
        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView.cellForRow(at: indexPath)
            popover.sourceRect = tableView.cellForRow(at: indexPath)?.bounds ?? .zero
        }
        present(alert, animated: true)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Account Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
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

        var title: String? {
            switch self {
            case .accounts: "Accounts"
            case .appearance: "Appearance"
            case .media: "Media"
            case .about: "About"
            case .accountActions: nil
            }
        }
    }

    enum Row: Equatable {
        case account(UUID)
        case addAccount
        case appearance
        case animatedMedia
        case version
        case logOut

        var account: TelegramAccount? {
            guard case .account(let id) = self else { return nil }
            return TDLib.shared.accounts.first(where: { $0.id == id })
        }

        var title: String {
            switch self {
            case .account:
                account?.title ?? "Account"
            case .addAccount:
                "Add Account"
            case .appearance:
                "Color Theme"
            case .animatedMedia:
                "Animated Media"
            case .version:
                "BetterTG Version"
            case .logOut:
                "Log Out"
            }
        }

        var subtitle: String? {
            switch self {
            case .account(let id):
                id == TDLib.shared.activeAccountID ? "Current Account" : account?.phoneNumber.map { "+\($0)" }
            case .appearance:
                AppAppearance.current.title
            case .animatedMedia:
                "TGS, WebP and WebM"
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
            case .animatedMedia: "sparkles.tv"
            case .version: "info.circle.fill"
            case .logOut: "rectangle.portrait.and.arrow.right"
            }
        }

        var tintColor: UIColor {
            switch self {
            case .account: .systemTeal
            case .addAccount, .appearance, .version: .systemBlue
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
