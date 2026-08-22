// SettingsViewController.swift

import UIKit

final class SettingsViewController: UITableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        tableView.backgroundColor = .black
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close),
        )
    }

    override func numberOfSections(in _: UITableView) -> Int {
        2
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 2 : 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.backgroundColor = .secondarySystemBackground
        if indexPath.section == 0, indexPath.row == 0 {
            var configuration = cell.defaultContentConfiguration()
            configuration.text = "Animated media"
            configuration.secondaryText = "TGS, WebP, WebM"
            cell.contentConfiguration = configuration
            let toggle = UISwitch()
            toggle.isOn = UserDefaults.standard.object(forKey: "animatedMediaEnabled") as? Bool ?? true
            toggle.addTarget(self, action: #selector(animatedMediaChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        } else if indexPath.section == 0 {
            var configuration = cell.defaultContentConfiguration()
            configuration.text = "Version"
            configuration.secondaryText = Utils.applicationVersion
            cell.contentConfiguration = configuration
            cell.selectionStyle = .none
        } else {
            var configuration = cell.defaultContentConfiguration()
            configuration.text = "Log Out"
            configuration.textProperties.color = .systemRed
            cell.contentConfiguration = configuration
        }
        return cell
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        let alert = UIAlertController(title: "Log Out?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Log Out", style: .destructive) { [weak self] _ in
            Task {
                _ = try? await td.logOut()
                await MainActor.run { self?.dismiss(animated: true) }
            }
        })
        present(alert, animated: true)
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func animatedMediaChanged(_ sender: UISwitch) {
        UserDefaults.standard.set(sender.isOn, forKey: "animatedMediaEnabled")
    }
}
