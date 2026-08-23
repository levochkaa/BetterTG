// SettingsViewController.swift

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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.navigationBar.prefersLargeTitles = false
        tableView.reloadData()
    }

    override func numberOfSections(in _: UITableView) -> Int { Section.allCases.count }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        Section(rawValue: section)?.rows.count ?? 0
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
        guard let row = Section(rawValue: indexPath.section)?.rows[indexPath.row] else { return cell }

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
        case .appearance:
            cell.accessoryType = .disclosureIndicator
        case .animatedMedia:
            let toggle = UISwitch()
            toggle.isOn = UserDefaults.standard.object(forKey: "animatedMediaEnabled") as? Bool ?? true
            toggle.addTarget(self, action: #selector(animatedMediaChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        case .version:
            cell.selectionStyle = .none
        case .logOut:
            break
        }
        return cell
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = Section(rawValue: indexPath.section)?.rows[indexPath.row] else { return }
        if row == .appearance {
            navigationController?.pushViewController(AppearanceViewController(), animated: true)
            return
        }
        guard row == .logOut else { return }
        let alert = UIAlertController(
            title: "Log Out?",
            message: "You can sign back in at any time.",
            preferredStyle: .actionSheet,
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Log Out", style: .destructive) { _ in
            Task {
                await PushRelayCoordinator.shared.prepareForLogout()
                _ = try? await td.logOut()
            }
        })
        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView.cellForRow(at: indexPath)
            popover.sourceRect = tableView.cellForRow(at: indexPath)?.bounds ?? .zero
        }
        present(alert, animated: true)
    }

    @objc private func animatedMediaChanged(_ sender: UISwitch) {
        UserDefaults.standard.set(sender.isOn, forKey: "animatedMediaEnabled")
    }
}

private extension SettingsViewController {
    enum Section: Int, CaseIterable {
        case appearance
        case media
        case about
        case account

        var title: String? {
            switch self {
            case .appearance: "Appearance"
            case .media: "Media"
            case .about: "About"
            case .account: nil
            }
        }

        var rows: [Row] {
            switch self {
            case .appearance: [.appearance]
            case .media: [.animatedMedia]
            case .about: [.version]
            case .account: [.logOut]
            }
        }
    }

    enum Row: Equatable {
        case appearance
        case animatedMedia
        case version
        case logOut

        var title: String {
            switch self {
            case .appearance: "Color Theme"
            case .animatedMedia: "Animated Media"
            case .version: "BetterTG Version"
            case .logOut: "Log Out"
            }
        }

        var subtitle: String? {
            switch self {
            case .appearance: AppAppearance.current.title
            case .animatedMedia: "TGS, WebP and WebM"
            case .version: Utils.applicationVersion
            case .logOut: nil
            }
        }

        var symbolName: String {
            switch self {
            case .appearance: "paintpalette.fill"
            case .animatedMedia: "sparkles.tv"
            case .version: "info.circle.fill"
            case .logOut: "rectangle.portrait.and.arrow.right"
            }
        }

        var tintColor: UIColor {
            switch self {
            case .appearance: .systemBlue
            case .animatedMedia: .systemPurple
            case .version: .systemBlue
            case .logOut: .systemRed
            }
        }

        var isSelectable: Bool { self == .appearance || self == .logOut }
        var isDestructive: Bool { self == .logOut }
    }
}
