// AppearanceViewController.swift

import UIKit

// MARK: - MediaDisplaySettings

/// Telegram's MediaDisplaySettings: whether a tap near the gallery's side edge shows the next or previous media,
/// on by default.
enum MediaDisplaySettings {
    private static let showNextMediaOnTapKey = "BetterTG.showNextMediaOnTap"

    static var showNextMediaOnTap: Bool {
        get { UserDefaults.standard.object(forKey: showNextMediaOnTapKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showNextMediaOnTapKey) }
    }
}

// MARK: - AppearanceViewController

/// The theme choice, then ThemeSettingsController's Stickers and Emoji and its Other section's Show Next Media on Tap.
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
        3
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? AppAppearance.allCases.count : 1
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 2 ? L10n.telegram("Appearance.Other") : nil
    }

    override func tableView(_: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 2 ? L10n.telegram("Appearance.ShowNextMediaOnTapInfo") : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "AppearanceCell", for: indexPath)
        if indexPath.section == 2 {
            var configuration = cell.defaultContentConfiguration()
            configuration.text = L10n.telegram("Appearance.ShowNextMediaOnTap")
            cell.contentConfiguration = configuration
            let toggle = UISwitch()
            toggle.isOn = MediaDisplaySettings.showNextMediaOnTap
            toggle.addAction(UIAction { action in
                MediaDisplaySettings.showNextMediaOnTap = (action.sender as? UISwitch)?.isOn ?? true
            }, for: .valueChanged)
            cell.accessoryView = toggle
            cell.accessoryType = .none
            cell.selectionStyle = .none
            return cell
        }
        cell.accessoryView = nil
        cell.selectionStyle = .default
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
        guard indexPath.section != 2 else { return }
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
