// ActiveSessionsViewController.swift

import TDLibKit
import UIKit

// MARK: - ActiveSessionsViewController

/// Telegram's Devices (RecentSessionsController): this session, Terminate all other sessions, incomplete login
/// attempts, the other active sessions newest first with swipe to terminate, and the inactivity period after which
/// Telegram terminates a session. A session opens Telegram's RecentSessionScreen.
final class ActiveSessionsViewController: SettingsListViewController {
    private var sessions: TDNativeSessions?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("AuthSessions.DevicesTitle")
        load()
    }

    override func makeSections() -> [SettingsSection] {
        guard let sessions else {
            return [SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("Channel.NotificationLoading"),
                style: .status(.secondaryLabel),
                accessory: .activity,
            )])]
        }
        let current = sessions.sessions.first(where: \.isCurrent)
        let pending = sessions.sessions.filter { !$0.isCurrent && $0.isPasswordPending }
        let others = sessions.sessions
            .filter { !$0.isCurrent && !$0.isPasswordPending }
            .sorted { $0.lastActiveDate > $1.lastActiveDate }

        var result = [SettingsSection]()
        var currentRows = current.map { [sessionRow($0)] } ?? []
        if !others.isEmpty || !pending.isEmpty {
            currentRows.append(SettingsRow(
                title: L10n.telegram("AuthSessions.TerminateOtherSessions"),
                style: .action(destructive: true),
                symbol: "hand.raised.fill",
                symbolTint: .systemRed,
            ) { [weak self] in self?.confirmTerminateOthers() })
        }
        result.append(SettingsSection(
            header: L10n.telegram("AuthSessions.CurrentSession"),
            footer: others.isEmpty && pending.isEmpty ? nil : L10n.telegram("AuthSessions.TerminateOtherSessionsHelp"),
            rows: currentRows,
        ))
        if !pending.isEmpty {
            result.append(SettingsSection(
                header: L10n.telegram("AuthSessions.IncompleteAttempts"),
                footer: L10n.telegram("AuthSessions.IncompleteAttemptsInfo"),
                rows: pending.map(sessionRow),
            ))
        }
        if !others.isEmpty {
            result.append(SettingsSection(
                header: L10n.telegram("AuthSessions.OtherSessions"),
                rows: others.map(sessionRow),
            ))
        }
        let ttlSectionIndex = result.count
        result.append(SettingsSection(
            header: L10n.telegram("AuthSessions.TerminateIfAwayTitle").uppercased(),
            rows: [SettingsRow(
                title: L10n.telegram("AuthSessions.TerminateIfAwayFor"),
                detail: SettingsFormatting.timeInterval(seconds: sessions.inactiveSessionTtlDays * 24 * 60 * 60),
            ) { [weak self] in
                self?.presentTtlMenu(at: IndexPath(row: 0, section: ttlSectionIndex))
            }],
        ))
        return result
    }

    /// Telegram trims the store and build tags from the version: "Telegram iOS 11.2".
    fileprivate static func applicationText(_ session: TDNativeSession) -> String {
        var version = session.applicationVersion
            .replacing("APPSTORE", with: "")
            .replacing("BETA", with: "Beta")
            .trimmingCharacters(in: .whitespaces)
        if let open = version.range(of: " ("), let close = version.range(
            of: ")",
            range: open.upperBound..<version.endIndex,
        ) {
            version.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return "\(session.applicationName) \(version)".trimmingCharacters(in: .whitespaces)
    }

    /// Telegram's iconForSession, with system symbols: it reads the device model, platform and system names, in its
    /// order, before the type TDLib infers, which leaves an iPhone model such as "iPhone19,2" unknown.
    fileprivate static func icon(for session: TDNativeSession) -> (symbol: String, tint: UIColor) {
        let platform = session.platform.lowercased()
        let device = session.deviceModel.lowercased()
        let system = session.systemVersion.lowercased()
        if device.contains("xbox") { return ("gamecontroller", .systemGreen) }
        if device.contains("chrome"), !device.contains("chromebook") { return ("globe", .systemGreen) }
        if device.contains("brave") { return ("globe", .systemOrange) }
        if device.contains("vivaldi") { return ("globe", .systemRed) }
        if device.contains("safari") { return ("globe", .systemBlue) }
        if device.contains("firefox") { return ("globe", .systemOrange) }
        if device.contains("opera") { return ("globe", .systemRed) }
        if platform.contains("android") { return ("candybarphone", .systemGreen) }
        if device.contains("iphone") { return ("iphone", .systemBlue) }
        if device.contains("ipad") { return ("ipad", .systemBlue) }
        let isMacOS = platform.contains("macos") || system.contains("macos")
        if isMacOS, device.contains("mac") { return ("laptopcomputer", .systemBlue) }
        if platform.contains("ios") || isMacOS { return ("apple.logo", .systemBlue) }
        if platform.contains("ubuntu") || system.contains("ubuntu") { return ("desktopcomputer", .systemOrange) }
        if platform.contains("linux") || system.contains("linux") { return ("desktopcomputer", .systemGray) }
        if platform.contains("windows") || system.contains("windows") { return ("pc", .systemBlue) }
        return icon(for: session.deviceType)
    }

    private static func icon(for type: TDNativeSessionDeviceType) -> (symbol: String, tint: UIColor) {
        switch type {
        case .sessionDeviceTypeIphone: ("iphone", .systemBlue)
        case .sessionDeviceTypeIpad: ("ipad", .systemBlue)
        case .sessionDeviceTypeApple,
             .sessionDeviceTypeMac: ("laptopcomputer", .systemBlue)
        case .sessionDeviceTypeAndroid: ("candybarphone", .systemGreen)
        case .sessionDeviceTypeWindows: ("pc", .systemBlue)
        case .sessionDeviceTypeLinux,
             .sessionDeviceTypeUbuntu: ("desktopcomputer", .systemOrange)
        case .sessionDeviceTypeChrome: ("globe", .systemGreen)
        case .sessionDeviceTypeBrave,
             .sessionDeviceTypeFirefox: ("globe", .systemOrange)
        case .sessionDeviceTypeEdge,
             .sessionDeviceTypeSafari: ("globe", .systemBlue)
        case .sessionDeviceTypeOpera,
             .sessionDeviceTypeVivaldi: ("globe", .systemRed)
        case .sessionDeviceTypeXbox: ("gamecontroller", .systemGreen)
        case .sessionDeviceTypeUnknown: ("questionmark.app", .systemGray)
        }
    }

    private func load() {
        guard contextIsCurrent else { return }
        let client = client
        Task { [weak self] in
            let sessions = try? await client.send(TDNativeRequests.getActiveSessions())
            guard let self, contextIsCurrent, let sessions else { return }
            self.sessions = sessions
            reload()
        }
    }

    private func sessionRow(_ session: TDNativeSession) -> SettingsRow {
        let icon = Self.icon(for: session)
        let activity = session.isCurrent
            ? L10n.telegram("Presence.online")
            : SettingsFormatting.activityDate(session.lastActiveDate)
        let location = session.location.isEmpty ? activity : "\(session.location) • \(activity)"
        var row = SettingsRow(
            title: session.deviceModel.isEmpty ? session.applicationName : session.deviceModel,
            detail: "\(Self.applicationText(session))\n\(location)",
            style: .subtitle,
            symbol: icon.symbol,
            symbolTint: icon.tint,
        ) { [weak self] in self?.openSession(session) }
        if !session.isCurrent {
            let id = session.id
            row.swipeAction = (
                title: L10n.telegram("AuthSessions.Terminate"),
                handler: { [weak self] in self?.confirmTerminate(id) },
            )
        }
        return row
    }

    private func openSession(_ session: TDNativeSession) {
        guard presentedViewController == nil else { return }
        let detail = SessionDetailViewController(session: session) { [weak self] in
            self?.load()
        }
        let navigation = UINavigationController(rootViewController: detail)
        navigation.sheetPresentationController?.detents = [.medium(), .large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        present(navigation, animated: true)
    }

    private func confirmTerminate(_ id: Int64) {
        confirm(
            message: L10n.telegram("AuthSessions.TerminateSessionText"),
            actionTitle: L10n.telegram("AuthSessions.TerminateSession"),
        ) { [weak self] in
            self?.perform { client in
                _ = try await client.send(TDNativeRequests.terminateSession(sessionId: id))
            } completion: { [weak self] in
                self?.load()
            }
        }
    }

    private func confirmTerminateOthers() {
        confirm(
            message: L10n.telegram("AuthSessions.TerminateOtherSessionsText"),
            actionTitle: L10n.telegram("AuthSessions.TerminateOtherSessions"),
        ) { [weak self] in
            self?.perform { client in
                _ = try await client.send(TDNativeRequests.terminateAllOtherSessions())
            } completion: { [weak self] in
                self?.load()
            }
        }
    }

    /// Telegram's If Inactive For menu: 1 week, 1 month, 3 months or 6 months (setInactiveSessionTtl).
    private func presentTtlMenu(at indexPath: IndexPath) {
        guard let sessions, let cell = tableView.cellForRow(at: indexPath) else { return }
        let actions = [7, 30, 90, 180].map { days in
            TelegramContextMenuAction(
                title: SettingsFormatting.timeInterval(seconds: days * 24 * 60 * 60),
                image: sessions.inactiveSessionTtlDays == days ? UIImage(systemName: "checkmark") : nil,
            ) { [weak self] in
                self?.perform { client in
                    _ = try await client.send(TDNativeRequests.setInactiveSessionTtl(inactiveSessionTtlDays: days))
                } completion: { [weak self] in
                    self?.load()
                }
            }
        }
        presentTelegramContextMenu(sourceView: cell, actions: actions, presentationStyle: .menuOnly)
    }
}

// MARK: - SessionDetailViewController

/// Telegram's RecentSessionScreen: the session's application, system, IP address and location, and Terminate
/// Session for any session but this one.
private final class SessionDetailViewController: SettingsListViewController {
    private let session: TDNativeSession
    private let onTerminated: () -> Void

    private var sessionTitle: String {
        session.deviceModel.isEmpty ? session.applicationName : session.deviceModel
    }

    init(session: TDNativeSession, onTerminated: @escaping () -> Void) {
        self.session = session
        self.onTerminated = onTerminated
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = sessionTitle
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Close"), style: .plain, target: self, action: #selector(closePressed),
        )
    }

    override func makeSections() -> [SettingsSection] {
        let icon = ActiveSessionsViewController.icon(for: session)
        let activity = session.isCurrent
            ? L10n.telegram("Presence.online")
            : Date(timeIntervalSince1970: TimeInterval(session.lastActiveDate)).formatted(date: .long, time: .shortened)
        var sections = [
            SettingsSection(rows: [SettingsRow(
                title: sessionTitle,
                detail: activity,
                style: .subtitle,
                symbol: icon.symbol,
                symbolTint: icon.tint,
            )]),
            SettingsSection(rows: [
                SettingsRow(
                    title: L10n.telegram("AuthSessions.View.Application"),
                    detail: ActiveSessionsViewController.applicationText(session),
                ),
                SettingsRow(
                    title: L10n.telegram("AuthSessions.View.OS"),
                    detail: "\(session.platform) \(session.systemVersion)".trimmingCharacters(in: .whitespaces),
                ),
                SettingsRow(title: L10n.telegram("AuthSessions.View.IP"), detail: session.ipAddress),
                SettingsRow(title: L10n.telegram("AuthSessions.View.Location"), detail: session.location),
            ]),
        ]
        sections[1].footer = L10n.telegram("AuthSessions.View.LocationInfo")
        if !session.isCurrent {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("AuthSessions.View.TerminateSession"),
                style: .action(destructive: true),
            ) { [weak self] in self?.confirmTerminate() }]))
        }
        return sections
    }

    private func confirmTerminate() {
        let id = session.id
        confirm(
            message: L10n.telegram("AuthSessions.TerminateSessionText"),
            actionTitle: L10n.telegram("AuthSessions.TerminateSession"),
        ) { [weak self] in
            self?.perform { client in
                _ = try await client.send(TDNativeRequests.terminateSession(sessionId: id))
            } completion: { [weak self] in
                guard let self else { return }
                let onTerminated = onTerminated
                dismiss(animated: true) { onTerminated() }
            }
        }
    }

    @objc private func closePressed() {
        dismiss(animated: true)
    }
}
