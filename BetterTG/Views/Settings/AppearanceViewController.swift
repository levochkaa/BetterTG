// AppearanceViewController.swift

import UIKit

// MARK: - AppearanceViewController

final class AppearanceViewController: UITableViewController {
    // MARK: Lifecycle

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Appearance"
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "AppearanceCell")
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        AppAppearance.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "AppearanceCell", for: indexPath)
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
