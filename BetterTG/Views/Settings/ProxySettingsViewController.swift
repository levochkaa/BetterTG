// ProxySettingsViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - ProxyPresentation

/// How Telegram names and shares a proxy.
enum ProxyPresentation {
    /// DataAndStorageSettingsController's and the list's type: SOCKS5, MTProto or WEB.
    static func typeTitle(_ proxy: TDNativeProxy) -> String {
        switch proxy.type {
        case .proxyTypeSocks5: L10n.telegram("ChatSettings.ConnectionType.UseSocks5")
        case .proxyTypeMtproto: L10n.telegram("SocksProxySetup.ProxyTelegram")
        case .proxyTypeWeb: L10n.telegram("SocksProxySetup.ProxyWeb")
        case .proxyTypeHttp: "HTTP"
        }
    }

    /// shareProxyList's links: t.me/socks with the user and password, t.me/proxy with the secret. A web or HTTP
    /// proxy has no link Telegram shares here.
    static func link(_ proxy: TDNativeProxy) -> String? {
        let base = "server=\(encode(proxy.server))&port=\(proxy.port)"
        switch proxy.type {
        case .proxyTypeSocks5(let socks):
            guard !socks.username.isEmpty || !socks.password.isEmpty else { return "https://t.me/socks?\(base)" }
            return "https://t.me/socks?\(base)&user=\(encode(socks.username))&pass=\(encode(socks.password))"
        case .proxyTypeMtproto(let mtproto):
            return "https://t.me/proxy?\(base)&secret=\(encode(mtproto.secret))"
        case .proxyTypeHttp,
             .proxyTypeWeb:
            return nil
        }
    }

    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

// MARK: - ProxySettingsViewController

/// ProxyListSettingsController on TDLib's proxies: Use Proxy, then Saved Proxies with Add Proxy and each server with
/// its type and status (checking, its ping or unavailable; connecting or connected for the one in use), a check on
/// the active one, an info button that edits it and a Delete swipe, and Share Proxy List. A tap on a server makes it
/// the active one and turns the proxy on. Telegram's Use for Calls is not offered: BetterTG has no calls.
final class ProxySettingsViewController: SettingsListViewController {
    private var proxies: [TDNativeAddedProxy]?
    /// pingProxy's round trip by proxy ID; nil while unknown, NaN once the proxy didn't answer.
    private var pings = [Int: Double]()
    private var connectionState: ConnectionState?
    private var loadTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var connectionCancellable: AnyCancellable?

    /// ProxySettings' activeServer: the enabled proxy, else the one used last, else the first.
    private var activeProxy: TDNativeAddedProxy? {
        guard let proxies else { return nil }
        return proxies.first(where: \.isEnabled)
            ?? proxies.filter { $0.lastUsedDate > 0 }.max { $0.lastUsedDate < $1.lastUsedDate }
            ?? proxies.first
    }

    deinit {
        loadTask?.cancel()
        pingTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("SocksProxySetup.Title")
        connectionCancellable = TDLib.shared
            .connectionStates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.connectionState = state
                self?.reload()
            }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        load()
    }

    override func makeSections() -> [SettingsSection] {
        guard let proxies else { return [] }
        let isOn = proxies.contains(where: \.isEnabled)
        var sections = [SettingsSection(rows: [SettingsRow(
            title: L10n.telegram("ChatSettings.ConnectionType.UseProxy"),
            accessory: .toggle(isOn: isOn) { [weak self] isOn in self?.setEnabled(isOn) },
            isEnabled: !proxies.isEmpty,
        )])]
        var rows = [SettingsRow(
            title: L10n.telegram("SocksProxySetup.AddProxy"),
            style: .action(destructive: false),
            symbol: "plus",
            action: { [weak self] in self?.openEditor(for: nil) },
        )]
        let activeID = activeProxy?.id
        for proxy in proxies {
            let isActive = proxy.id == activeID
            let status = status(of: proxy, isActive: isActive)
            rows.append(SettingsRow(
                title: "\(proxy.proxy.server):\(proxy.proxy.port)",
                detail: status.text,
                detailColor: status.isActive ? .tintColor : nil,
                style: .subtitle,
                symbol: "checkmark",
                symbolTint: isActive ? .tintColor : .clear,
                action: { [weak self] in self?.activate(proxy) },
                swipeAction: (
                    title: L10n.telegram("Common.Delete"),
                    handler: { [weak self] in self?.remove(proxy) },
                ),
                trailingView: SettingsTrailingView { [weak self] in
                    let button = UIButton(type: .detailDisclosure)
                    button.addAction(UIAction { _ in self?.openEditor(for: proxy) }, for: .touchUpInside)
                    return button
                },
            ))
        }
        sections.append(SettingsSection(header: L10n.telegram("SocksProxySetup.SavedProxies"), rows: rows))
        if !proxies.isEmpty {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("SocksProxySetup.ShareProxyList"),
                style: .action(destructive: false),
                action: { [weak self] in self?.shareList() },
            )]))
        }
        return sections
    }

    // MARK: Private

    /// The server's line: the connection state for the proxy in use, else its type with checking, the ping or
    /// unavailable.
    private func status(of proxy: TDNativeAddedProxy, isActive: Bool) -> (text: String, isActive: Bool) {
        let ping = pings[proxy.id].flatMap { $0.isNaN ? nil : Int(($0 * 1000).rounded()) }
        if proxy.isEnabled, isActive {
            switch connectionState {
            case .connectionStateWaitingForNetwork:
                return (L10n.telegram("State.WaitingForNetwork").lowercased(), false)
            case .connectionStateReady:
                var text = L10n.telegram("SocksProxySetup.ProxyStatusConnected")
                if let ping { text += ", " + L10n.telegram("SocksProxySetup.ProxyStatusPing", "\(ping)") }
                return (text, true)
            default:
                return (L10n.telegram("SocksProxySetup.ProxyStatusConnecting"), false)
            }
        }
        let type = ProxyPresentation.typeTitle(proxy.proxy)
        if case .proxyTypeWeb = proxy.proxy.type {
            return ("\(type), " + L10n.telegram("SocksProxySetup.ProxyStatusNotTested"), false)
        }
        switch pings[proxy.id] {
        case nil:
            return ("\(type), " + L10n.telegram("SocksProxySetup.ProxyStatusChecking"), false)
        case let value? where value.isNaN:
            return ("\(type), " + L10n.telegram("SocksProxySetup.ProxyStatusUnavailable"), false)
        default:
            return ("\(type), " + L10n.telegram("SocksProxySetup.ProxyStatusPing", "\(ping ?? 0)"), false)
        }
    }

    private func load() {
        guard contextIsCurrent else { return }
        loadTask?.cancel()
        let client = client
        loadTask = Task { [weak self] in
            let proxies = try? await client.send(TDNativeRequests.getProxies())
            guard let self, !Task.isCancelled, contextIsCurrent else { return }
            self.proxies = proxies?.proxies ?? []
            reload()
            pingAll()
        }
    }

    /// ProxyServersStatuses: each server is pinged once the list shows; web servers are not.
    private func pingAll() {
        pingTask?.cancel()
        let client = client
        let targets = (proxies ?? []).filter {
            if case .proxyTypeWeb = $0.proxy.type {
                false
            } else {
                pings[$0.id] == nil
            }
        }
        guard !targets.isEmpty else { return }
        pingTask = Task { [weak self] in
            await withTaskGroup(of: (Int, Double).self) { group in
                for proxy in targets {
                    group.addTask {
                        let seconds = try? await client.send(TDNativeRequests.pingProxy(proxy: proxy.proxy))
                        return (proxy.id, seconds?.seconds ?? .nan)
                    }
                }
                for await (id, seconds) in group {
                    guard !Task.isCancelled else { return }
                    self?.applyPing(seconds, to: id)
                }
            }
        }
    }

    private func applyPing(_ seconds: Double, to id: Int) {
        pings[id] = seconds
        reload()
    }

    private func setEnabled(_ isOn: Bool) {
        guard let active = activeProxy else { return }
        perform { client in
            _ =
                if isOn {
                    try await client.send(TDNativeRequests.enableProxy(proxyId: active.id))
                } else {
                    try await client.send(TDNativeRequests.disableProxy())
                }
        } completion: { [weak self] in self?.load() }
    }

    /// activateServer: the server becomes the active one and the proxy turns on.
    private func activate(_ proxy: TDNativeAddedProxy) {
        guard !proxy.isEnabled else { return }
        perform { client in
            _ = try await client.send(TDNativeRequests.enableProxy(proxyId: proxy.id))
        } completion: { [weak self] in self?.load() }
    }

    private func remove(_ proxy: TDNativeAddedProxy) {
        perform { client in
            _ = try await client.send(TDNativeRequests.removeProxy(proxyId: proxy.id))
        } completion: { [weak self] in
            self?.pings[proxy.id] = nil
            self?.load()
        }
    }

    private func openEditor(for proxy: TDNativeAddedProxy?) {
        navigationController?.pushViewController(ProxyServerSettingsViewController(editedProxy: proxy), animated: true)
    }

    /// shareProxyList: every server's link, a blank line apart.
    private func shareList() {
        let text = (proxies ?? []).compactMap { ProxyPresentation.link($0.proxy) }.joined(separator: "\n\n")
        guard !text.isEmpty else { return }
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = view
        present(activity, animated: true)
    }
}

// MARK: - ProxyServerSettingsViewController

/// ProxyServerSettingsController: Paste From Clipboard while the clipboard has text, SOCKS5 or MTProto, the server
/// and port, then the optional username and password or the required secret, and Share. Done saves it (addProxy,
/// or editProxy keeping it on or off) once it is complete. Telegram's WEB servers are listed but not offered here.
final class ProxyServerSettingsViewController: SettingsListViewController {
    private enum Mode {
        case socks5
        case mtproto
    }

    private let editedProxy: TDNativeAddedProxy?
    private var mode = Mode.socks5
    private var server = ""
    private var port = ""
    private var username = ""
    private var password = ""
    private var secret = ""

    private var proxy: TDNativeProxy? {
        let host = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, let port = Int(port), (1...65535).contains(port) else { return nil }
        switch mode {
        case .socks5:
            return TDNativeProxy(server: host, port: port, type: .proxyTypeSocks5(TDNativeProxyTypeSocks5(
                username: username,
                password: password,
            )))
        case .mtproto:
            let secret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.isValidSecret(secret) else { return nil }
            return TDNativeProxy(server: host, port: port, type: .proxyTypeMtproto(TDNativeProxyTypeMtproto(
                secret: secret,
            )))
        }
    }

    init(editedProxy: TDNativeAddedProxy?) {
        self.editedProxy = editedProxy
        super.init()
        if let editedProxy { fill(from: editedProxy.proxy) }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("SocksProxySetup.Title")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Done"),
            style: .prominent,
            target: self,
            action: #selector(doneTapped),
        )
        updateDone()
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [SettingsSection]()
        if UIPasteboard.general.hasStrings {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("SocksProxySetup.PasteFromClipboard"),
                style: .action(destructive: false),
                action: { [weak self] in self?.pasteFromClipboard() },
            )]))
        }
        sections.append(SettingsSection(rows: [
            SettingsRow(
                title: L10n.telegram("SocksProxySetup.ProxySocks5"),
                accessory: mode == .socks5 ? .checkmark : .none,
                action: { [weak self] in self?.setMode(.socks5) },
            ),
            SettingsRow(
                title: L10n.telegram("SocksProxySetup.ProxyTelegram"),
                accessory: mode == .mtproto ? .checkmark : .none,
                action: { [weak self] in self?.setMode(.mtproto) },
            ),
        ]))
        sections.append(SettingsSection(
            header: L10n.telegram("SocksProxySetup.Connection").uppercased(),
            rows: [
                inputRow(L10n.telegram("SocksProxySetup.Hostname"), text: server, keyboard: .URL) { [weak self] in
                    self?.server = $0
                },
                inputRow(L10n.telegram("SocksProxySetup.Port"), text: port, keyboard: .numberPad) { [weak self] in
                    self?.port = $0
                },
            ],
        ))
        switch mode {
        case .socks5:
            sections.append(SettingsSection(header: L10n.telegram("SocksProxySetup.Credentials"), rows: [
                inputRow(L10n.telegram("SocksProxySetup.Username"), text: username) { [weak self] in
                    self?.username = $0
                },
                inputRow(L10n.telegram("SocksProxySetup.Password"), text: password) { [weak self] in
                    self?.password = $0
                },
            ]))
        case .mtproto:
            sections.append(SettingsSection(header: L10n.telegram("SocksProxySetup.RequiredCredentials"), rows: [
                inputRow(L10n.telegram("SocksProxySetup.SecretPlaceholder"), text: secret) { [weak self] in
                    self?.secret = $0
                },
            ]))
        }
        sections.append(SettingsSection(rows: [SettingsRow(
            title: L10n.telegram("Conversation.ContextMenuShare"),
            style: .action(destructive: false),
            isEnabled: proxy.flatMap(ProxyPresentation.link) != nil,
            action: { [weak self] in self?.share() },
        )]))
        return sections
    }

    // MARK: Private

    /// MTProxySecret.parse: 16 bytes in hex, or `dd` and 16 bytes, or `ee` with a domain, in hex or URL-safe base64.
    private static func isValidSecret(_ secret: String) -> Bool {
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        if secret.count >= 32, secret.count.isMultiple(of: 2), secret.unicodeScalars.allSatisfy(hex.contains) {
            return true
        }
        var base64 = secret.replacing("-", with: "+").replacing("_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return (Data(base64Encoded: base64)?.count ?? 0) >= 16
    }

    private func inputRow(
        _ placeholder: String,
        text: String,
        keyboard: UIKeyboardType = .default,
        onChange: @escaping (String) -> Void,
    ) -> SettingsRow {
        SettingsRow(title: placeholder, style: .input(SettingsTextInput(
            text: text,
            placeholder: placeholder,
            autocapitalization: .none,
            autocorrection: false,
            keyboardType: keyboard,
            onChange: { [weak self] value in
                onChange(value)
                self?.updateDone()
            },
        )))
    }

    private func fill(from proxy: TDNativeProxy) {
        server = proxy.server
        port = "\(proxy.port)"
        switch proxy.type {
        case .proxyTypeSocks5(let socks):
            mode = .socks5
            username = socks.username
            password = socks.password
        case .proxyTypeMtproto(let mtproto):
            mode = .mtproto
            secret = mtproto.secret
        case .proxyTypeHttp,
             .proxyTypeWeb:
            break
        }
    }

    private func setMode(_ mode: Mode) {
        guard self.mode != mode else { return }
        self.mode = mode
        reload()
        updateDone()
    }

    private func updateDone() {
        navigationItem.rightBarButtonItem?.isEnabled = proxy != nil
        // Share follows completeness too; its section is the last.
        if isViewLoaded, let last = sections.indices.last {
            reload(sections: IndexSet(integer: last))
        }
    }

    /// usePasteboardSettings: a t.me/proxy or t.me/socks link on the clipboard fills the form.
    private func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        let client = client
        Task { [weak self] in
            let link = try? await client.send(TDNativeRequests.getInternalLinkType(link: text))
            guard let self, contextIsCurrent,
                  case .internalLinkTypeProxy(let value) = link, let proxy = value.proxy else { return }
            fill(from: proxy)
            reload()
            updateDone()
        }
    }

    @objc private func doneTapped() {
        guard let proxy else { return }
        let editedProxy = editedProxy
        perform { client in
            _ =
                if let editedProxy {
                    try await client.send(TDNativeRequests.editProxy(
                        proxyId: editedProxy.id,
                        proxy: proxy,
                        enable: editedProxy.isEnabled,
                        comment: editedProxy.comment,
                    ))
                } else {
                    try await client.send(TDNativeRequests.addProxy(proxy: proxy, enable: false, comment: ""))
                }
        } completion: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }

    private func share() {
        guard let link = proxy.flatMap(ProxyPresentation.link) else { return }
        let activity = UIActivityViewController(activityItems: [link], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = view
        present(activity, animated: true)
    }
}
