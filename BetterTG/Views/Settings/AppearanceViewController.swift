// AppearanceViewController.swift

import UIKit

// MARK: - AppearanceViewController

/// The theme choice, then ThemeSettingsController's Stickers and Emoji.
final class AppearanceViewController: UITableViewController {
    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Appearance.Title")
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "AppearanceCell")
    }

    override func numberOfSections(in _: UITableView) -> Int {
        2
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? AppAppearance.allCases.count : 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "AppearanceCell", for: indexPath)
        guard indexPath.section == 0 else {
            var configuration = cell.defaultContentConfiguration()
            configuration.text = L10n.telegram("ChatSettings.StickersAndReactions")
            cell.contentConfiguration = configuration
            cell.accessoryType = .disclosureIndicator
            return cell
        }
        let appearance = AppAppearance.allCases[indexPath.row]
        var configuration = cell.defaultContentConfiguration()
        configuration.text = appearance.title
        configuration.image = UIImage(systemName: appearance.symbolName)
        configuration.imageProperties.tintColor = .systemBlue
        cell.contentConfiguration = configuration
        cell.accessoryType = appearance == AppAppearance.current ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 0 else {
            navigationController?.pushViewController(
                InstalledStickerSetsViewController(mode: .stickers),
                animated: true,
            )
            return
        }
        AppAppearance.allCases[indexPath.row].apply()
        tableView.reloadSections(IndexSet(integer: 0), with: .none)
    }
}

private extension AppAppearance {
    var symbolName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
}
