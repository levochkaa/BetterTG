// ProxyServerPreviewViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - ProxyServerPreviewViewController

/// ProxyServerPreviewScreen for a t.me/proxy or t.me/socks link: Proxy over a table of the server, port, username
/// and password or the hidden secret, and Check Status, then Connect Proxy. Checking or connecting first warns that
/// the proxy's admin will see the user's IP address. Connecting saves the server, turns it on and waits up to 15
/// seconds for TDLib to be online; it then closes with "Proxy Enabled", or puts the previous proxy back and says it
/// failed to connect. A web proxy has no port or status rows.
final class ProxyServerPreviewViewController: UIViewController {
    private enum Status {
        case checking
        case available(Double)
        case unavailable
    }

    private let proxy: TDNativeProxy
    private let accountID: UUID?
    private let client: TDLibClient
    private let table = UIStackView()
    private let connectButton = UIButton(configuration: .filled())
    private var status: Status?
    /// Whether the user already accepted the IP address warning.
    private var isChecked = false
    private var inProgress = false
    private var statusValueButton: UIButton?
    private var connectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    private var contextIsCurrent: Bool {
        accountID != nil && TDLib.shared.activeAccountID == accountID && TDLib.shared.activeClient.id == client.id
    }

    private var isWebProxy: Bool {
        if case .proxyTypeWeb = proxy.type {
            true
        } else {
            false
        }
    }

    init(proxy: TDNativeProxy) {
        self.proxy = proxy
        self.accountID = TDLib.shared.activeAccountID
        self.client = TDLib.shared.activeClient
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        connectTask?.cancel()
        pingTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        let close = UIButton(type: .system)
        close.setImage(UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
        ), for: .normal)
        close.tintColor = .label
        close.backgroundColor = .tertiarySystemFill
        close.layer.cornerRadius = 22
        close.accessibilityLabel = L10n.telegram("Common.Close")
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        let title = UILabel()
        title.text = L10n.telegram("SocksProxySetup.Title")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textAlignment = .center

        table.axis = .vertical
        table.backgroundColor = .secondarySystemGroupedBackground
        table.layer.cornerRadius = 10
        table.layer.cornerCurve = .continuous
        table.clipsToBounds = true
        buildTable()

        connectButton.configuration?.cornerStyle = .fixed
        connectButton.configuration?.background.cornerRadius = 10
        connectButton.configuration?.title = L10n.telegram("SocksProxySetup.ConnectAndSave")
        connectButton.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = .systemFont(ofSize: 17, weight: .semibold)
            return attributes
        }
        connectButton.addAction(UIAction { [weak self] _ in self?.connect() }, for: .touchUpInside)

        for subview in [close, title, table, connectButton] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            close.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            title.centerYAnchor.constraint(equalTo: view.topAnchor, constant: 38),
            title.leadingAnchor.constraint(equalTo: close.trailingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -76),
            table.topAnchor.constraint(equalTo: view.topAnchor, constant: 88),
            table.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            table.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            connectButton.topAnchor.constraint(equalTo: table.bottomAnchor, constant: 28),
            connectButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 30),
            connectButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -30),
            connectButton.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    /// OpenResolvedUrl's `.proxy`: the preview as a sheet.
    static func present(_ proxy: TDNativeProxy, from host: UIViewController) {
        let controller = ProxyServerPreviewViewController(proxy: proxy)
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.custom { _ in 420 }, .large()]
            sheet.prefersGrabberVisible = false
        }
        host.present(controller, animated: true)
    }

    private static func matches(_ lhs: TDNativeProxy, _ rhs: TDNativeProxy) -> Bool {
        guard lhs.server == rhs.server, lhs.port == rhs.port else { return false }
        switch (lhs.type, rhs.type) {
        case (.proxyTypeSocks5(let a), .proxyTypeSocks5(let b)):
            return a.username == b.username && a.password == b.password
        case (.proxyTypeMtproto(let a), .proxyTypeMtproto(let b)):
            return a.secret == b.secret
        case (.proxyTypeWeb(let a), .proxyTypeWeb(let b)):
            return a.secret == b.secret && a.path == b.path
        case (.proxyTypeHttp(let a), .proxyTypeHttp(let b)):
            return a.username == b.username && a.password == b.password
        default:
            return false
        }
    }

    /// The connection status filtered to online after the switch, with Telegram's 15 second timeout. The state
    /// from before the switch doesn't count: TDLib first reports connecting to the proxy.
    private static func waitUntilOnline(timeout: TimeInterval) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                var isFirst = true
                for await state in TDLib.shared.connectionStates.values {
                    if case .connectionStateReady = state, !isFirst { return true }
                    isFirst = false
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    // MARK: Private

    /// TableComponent's rows: the title on the left, the value on the right, hairlines between them.
    private func buildTable() {
        table.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var rows: [(String, UIView)] = [(L10n.telegram("SocksProxySetup.Hostname"), valueLabel(proxy.server))]
        if !isWebProxy {
            rows.append((L10n.telegram("SocksProxySetup.Port"), valueLabel("\(proxy.port)")))
        }
        switch proxy.type {
        case .proxyTypeSocks5(let socks):
            if !socks.username.isEmpty {
                rows.append((L10n.telegram("SocksProxySetup.Username"), valueLabel(socks.username)))
            }
            if !socks.password.isEmpty {
                rows.append((L10n.telegram("SocksProxySetup.Password"), valueLabel(socks.password)))
            }
        case .proxyTypeHttp(let http):
            if !http.username.isEmpty {
                rows.append((L10n.telegram("SocksProxySetup.Username"), valueLabel(http.username)))
            }
        case .proxyTypeMtproto,
             .proxyTypeWeb:
            rows.append((L10n.telegram("SocksProxySetup.Secret"), valueLabel("•••••")))
        }
        if !isWebProxy {
            let button = UIButton(type: .system)
            button.contentHorizontalAlignment = .leading
            button.titleLabel?.font = .systemFont(ofSize: 15)
            button.addAction(UIAction { [weak self] _ in self?.checkTapped() }, for: .touchUpInside)
            statusValueButton = button
            updateStatus()
            rows.append((L10n.telegram("SocksProxySetup.Status"), button))
        }
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = UIView()
                separator.backgroundColor = .separator
                separator.heightAnchor
                    .constraint(equalToConstant: 1 / max(1, traitCollection.displayScale))
                    .isActive = true
                table.addArrangedSubview(separator)
            }
            table.addArrangedSubview(tableRow(title: row.0, value: row.1))
        }
    }

    private func tableRow(title: String, value: UIView) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15)
        titleLabel.textColor = .label
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.widthAnchor.constraint(equalToConstant: 100).isActive = true
        let row = UIStackView(arrangedSubviews: [titleLabel, value])
        row.spacing = 12
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        return row
    }

    private func valueLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 15)
        label.textColor = .label
        label.numberOfLines = 0
        return label
    }

    /// Check Status in the accent colour, then checking, the ping or unavailable in red.
    private func updateStatus() {
        guard let button = statusValueButton else { return }
        let (text, color, enabled): (String, UIColor, Bool) =
            switch status {
            case nil: (L10n.telegram("SocksProxySetup.CheckStatus"), .tintColor, true)
            case .checking: (L10n.telegram("SocksProxySetup.ProxyStatusChecking"), .label, false)
            case .available(let seconds):
                (L10n.telegram("SocksProxySetup.ProxyStatusPing", "\(Int(seconds * 1000))"), .label, false)
            case .unavailable: (L10n.telegram("SocksProxySetup.ProxyStatusUnavailable"), .systemRed, false)
            }
        button.setTitle(text, for: .normal)
        button.setTitleColor(color, for: .normal)
        button.setTitleColor(color, for: .disabled)
        button.isEnabled = enabled
    }

    private func checkTapped() {
        displayWarningIfNeeded { [weak self] in self?.check() }
    }

    private func check() {
        guard contextIsCurrent else { return }
        status = .checking
        updateStatus()
        let client = client
        let proxy = proxy
        pingTask = Task { [weak self] in
            let seconds = try? await client.send(TDNativeRequests.pingProxy(proxy: proxy))
            guard let self, !Task.isCancelled else { return }
            status = seconds.map { .available($0.seconds) } ?? .unavailable
            updateStatus()
        }
    }

    /// displayWarningIfNeeded: once accepted, checking and connecting go ahead without asking again.
    private func displayWarningIfNeeded(_ commit: @escaping () -> Void) {
        guard !isChecked else { return commit() }
        let alert = UIAlertController(
            title: L10n.telegram("SocksProxySetup.Warning.Title"),
            message: L10n.telegram("SocksProxySetup.Warning.Text"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("SocksProxySetup.Warning.Proceed"), style: .default) {
            [weak self] _ in
            self?.isChecked = true
            commit()
        })
        present(alert, animated: true)
    }

    private func connect() {
        guard !inProgress else { return }
        displayWarningIfNeeded { [weak self] in self?.startConnecting() }
    }

    private func setInProgress(_ value: Bool) {
        inProgress = value
        connectButton.configuration?.showsActivityIndicator = value
        connectButton.configuration?.title = value ? nil : L10n.telegram("SocksProxySetup.ConnectAndSave")
    }

    /// The server is saved (or found among the saved ones) and turned on, then TDLib has 15 seconds to come online.
    private func startConnecting() {
        guard contextIsCurrent else { return }
        setInProgress(true)
        let client = client
        let proxy = proxy
        connectTask = Task { [weak self] in
            let saved = await (try? client.send(TDNativeRequests.getProxies()))?.proxies ?? []
            let previous = saved.first(where: \.isEnabled)
            let existing = saved.first { Self.matches($0.proxy, proxy) }
            let added: TDNativeAddedProxy?
            do {
                if let existing {
                    _ = try await client.send(TDNativeRequests.enableProxy(proxyId: existing.id))
                    added = nil
                } else {
                    added = try await client.send(TDNativeRequests.addProxy(proxy: proxy, enable: true, comment: ""))
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                setInProgress(false)
                presentFailure()
                return
            }
            ProxyStatusStore.shared.refresh()
            let online = await Self.waitUntilOnline(timeout: 15)
            guard let self, !Task.isCancelled else {
                ProxyStatusStore.shared.refresh()
                return
            }
            defer { ProxyStatusStore.shared.refresh() }
            setInProgress(false)
            if online {
                let presenter = presentingViewController
                dismiss(animated: true) {
                    guard let view = presenter?.view else { return }
                    TelegramUndoToast.show(
                        text: L10n.telegram("SocksProxySetup.ProxyEnabled").replacing("\n", with: " "),
                        in: view,
                        bottomInset: 12,
                        undo: nil,
                    )
                }
                return
            }
            // The previous settings come back: the proxy that was on, and no new server.
            _ =
                if let previous {
                    try? await client.send(TDNativeRequests.enableProxy(proxyId: previous.id))
                } else {
                    try? await client.send(TDNativeRequests.disableProxy())
                }
            if let added {
                _ = try? await client.send(TDNativeRequests.removeProxy(proxyId: added.id))
            }
            presentFailure()
        }
    }

    private func presentFailure() {
        let alert = UIAlertController(
            title: nil,
            message: L10n.telegram("SocksProxySetup.FailedToConnect"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        present(alert, animated: true)
    }
}
