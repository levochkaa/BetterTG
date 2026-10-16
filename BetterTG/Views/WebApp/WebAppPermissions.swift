// WebAppPermissions.swift

import Security
import UIKit

// MARK: - WebAppBotPermissions

/// What a bot's Web Apps may do on one account: Telegram's TelegramBotBiometricsState and WebAppPermissionsState,
/// kept per account and bot in the user defaults.
struct WebAppBotPermissions: Codable {
    /// TelegramBotBiometricsState.
    struct Biometry: Codable {
        /// The token the page saved, encrypted with the key whose public part it keeps.
        struct OpaqueToken: Codable {
            var publicKey: Data
            var data: Data
        }

        var deviceID: Data
        var accessRequested = false
        var accessGranted = false
        var opaqueToken: OpaqueToken?

        /// TelegramBotBiometricsState.create: a random 32-byte device ID.
        static func create() -> Biometry {
            var bytes = [UInt8](repeating: 0, count: 32)
            if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
                bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
            }
            return Biometry(deviceID: Data(bytes))
        }
    }

    /// WebAppPermissionsState.Location: whether the bot asked for the location and the user's answer.
    struct Location: Codable {
        var isRequested: Bool
        var isAllowed: Bool
    }

    var biometry: Biometry?
    var location: Location?

    @MainActor static func load(accountKey: String, botUserID: Int64) -> WebAppBotPermissions {
        guard let data = UserDefaults.standard.data(forKey: storageKey(accountKey: accountKey, botUserID: botUserID)),
              let permissions = try? JSONDecoder().decode(WebAppBotPermissions.self, from: data)
        else { return WebAppBotPermissions() }
        return permissions
    }

    @discardableResult @MainActor static func update(
        accountKey: String,
        botUserID: Int64,
        _ change: (inout WebAppBotPermissions) -> Void,
    ) -> WebAppBotPermissions {
        var permissions = load(accountKey: accountKey, botUserID: botUserID)
        change(&permissions)
        if let data = try? JSONEncoder().encode(permissions) {
            UserDefaults.standard.set(data, forKey: storageKey(accountKey: accountKey, botUserID: botUserID))
        }
        return permissions
    }

    private static func storageKey(accountKey: String, botUserID: Int64) -> String {
        "webApp.permissions.\(accountKey).\(botUserID)"
    }
}

// MARK: - WebAppBotSettingsViewController

/// botSettingsScreen for `web_app_biometry_open_settings` (the Biometry switch) and the bot info's "Allow access to"
/// section for `web_app_open_location_settings` (the Geolocation switch), under the bot's name.
@MainActor final class WebAppBotSettingsViewController: UITableViewController {
    enum Kind {
        case biometry
        case location
    }

    private struct Row {
        let title: String
        let isOn: Bool
        let toggle: (inout WebAppBotPermissions, Bool) -> Void
    }

    private let kind: Kind
    private let accountKey: String
    private let botUserID: Int64
    private var rows = [Row]()

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    private init(kind: Kind, bridge: WebAppBridge) {
        self.kind = kind
        self.accountKey = bridge.accountKey
        self.botUserID = bridge.botUserID
        super.init(style: .insetGrouped)
        title = bridge.botName
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) },
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        reloadRows()
    }

    override func numberOfSections(in _: UITableView) -> Int {
        1
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        rows.count
    }

    override func tableView(_: UITableView, titleForHeaderInSection _: Int) -> String? {
        switch kind {
        case .biometry: nil
        case .location: rows.isEmpty ? nil : L10n.telegram("PeerInfo.Permissions.Title")
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        let row = rows[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = row.title
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        let toggle = UISwitch()
        toggle.isOn = row.isOn
        toggle.addAction(UIAction { [weak self, weak toggle] _ in
            guard let self, let toggle else { return }
            WebAppBotPermissions.update(accountKey: accountKey, botUserID: botUserID) { permissions in
                row.toggle(&permissions, toggle.isOn)
            }
            reloadRows(reloadingTable: false)
        }, for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    static func present(_ kind: Kind, bridge: WebAppBridge) {
        guard let presenter = bridge.topPresenter() else { return }
        let controller = WebAppBotSettingsViewController(kind: kind, bridge: bridge)
        let navigation = UINavigationController(rootViewController: controller)
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presenter.present(navigation, animated: true)
    }

    // MARK: Private

    private func reloadRows(reloadingTable: Bool = true) {
        let permissions = WebAppBotPermissions.load(accountKey: accountKey, botUserID: botUserID)
        var rows = [Row]()
        switch kind {
        case .biometry:
            if let biometry = permissions.biometry {
                rows.append(Row(title: L10n.telegram("Settings.BotSettings.Biometry"), isOn: biometry.accessGranted) {
                    var biometry = $0.biometry ?? .create()
                    biometry.accessGranted = $1
                    $0.biometry = biometry
                })
            }
        case .location:
            if let location = permissions.location, location.isRequested || location.isAllowed {
                rows.append(Row(
                    title: L10n.telegram("PeerInfo.Permissions.Geolocation"),
                    isOn: location.isAllowed,
                ) {
                    $0.location = WebAppBotPermissions.Location(isRequested: true, isAllowed: $1)
                })
            }
        }
        self.rows = rows
        if reloadingTable { tableView.reloadData() }
    }
}
