// AccountFreezeInfoViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - AccountFreezeStore

/// updateFreezeState for each account's client: whether the account is frozen, until when it may appeal, and where.
@MainActor final class AccountFreezeStore {
    static let shared = AccountFreezeStore()

    let changes = PassthroughSubject<Void, Never>()

    /// Each account's latest state with the client that sent it.
    private var states = [UUID: (clientID: Int32, state: UpdateFreezeState)]()

    func receive(_ state: UpdateFreezeState, source: TdUpdateSource) {
        states[source.accountID] = (source.clientID, state)
        changes.send()
    }

    /// The account's freeze, nil while it isn't frozen.
    func freeze(for source: TdUpdateSource?) -> UpdateFreezeState? {
        #if DEBUG
            // `-ui-probe-account-frozen`: a made-up freeze with a month left to appeal through @SpamBot.
            if ProcessInfo.processInfo.arguments.contains("-ui-probe-account-frozen") {
                return TDNativeUpdateFreezeState(
                    isFrozen: true,
                    freezingDate: Int(Date().timeIntervalSince1970),
                    deletionDate: Int(Date().addingTimeInterval(30 * 24 * 3600).timeIntervalSince1970),
                    appealLink: "https://t.me/spambot",
                )
            }
        #endif
        guard let source, let entry = states[source.accountID], entry.clientID == source.clientID,
              entry.state.isFrozen else { return nil }
        return entry.state
    }

    /// ChatInterfaceStateInputPanels' freezeAppealUrl check: the appeal bot's own chat stays writable.
    func isAppealChat(username: String?, source: TdUpdateSource?) -> Bool {
        guard let username, !username.isEmpty, let link = freeze(for: source)?.appealLink,
              let last = link.split(separator: "/").last else { return false }
        return last.caseInsensitiveCompare(username) == .orderedSame
    }
}

// MARK: - AccountFreezeInfoViewController

/// Telegram's AccountFreezeInfoScreen: Your Account is Frozen over Violation of Terms, Read-Only Mode and Appeal
/// Before Deactivation with the date the account will be deleted, then Submit an Appeal, which opens the appeal link,
/// and Understood.
final class AccountFreezeInfoViewController: SettingsListViewController {
    private let freeze: UpdateFreezeState

    init(freeze: UpdateFreezeState) {
        self.freeze = freeze
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("FrozenAccount.Title")
    }

    override func makeSections() -> [SettingsSection] {
        let date = Date(timeIntervalSince1970: TimeInterval(freeze.deletionDate))
            .formatted(date: .long, time: .omitted)
        return [
            SettingsSection(rows: [
                SettingsRow(
                    title: L10n.telegram("FrozenAccount.Violation.Title"),
                    detail: L10n.telegram("FrozenAccount.Violation.TextNew").withoutTelegramLinks,
                    style: .subtitle,
                    symbol: "hand.raised.fill",
                ),
                SettingsRow(
                    title: L10n.telegram("FrozenAccount.ReadOnly.Title"),
                    detail: L10n.telegram("FrozenAccount.ReadOnly.Text"),
                    style: .subtitle,
                    symbol: "lock.fill",
                ),
                SettingsRow(
                    title: L10n.telegram("FrozenAccount.Appeal.Title"),
                    detail: L10n.telegram("FrozenAccount.Appeal.Text", date).withoutTelegramLinks,
                    style: .subtitle,
                    symbol: "hourglass",
                ),
            ]),
            SettingsSection(rows: [
                SettingsRow(
                    title: L10n.telegram("FrozenAccount.SubmitAppeal"),
                    style: .action(destructive: false),
                ) { [weak self] in self?.submitAppeal() },
                SettingsRow(
                    title: L10n.telegram("FrozenAccount.Understood"),
                    style: .action(destructive: false),
                ) { [weak self] in self?.dismiss(animated: true) },
            ]),
        ]
    }

    /// The sheet over the screen that asked for it.
    static func present(_ freeze: UpdateFreezeState, from presenter: UIViewController) {
        let navigation = UINavigationController(rootViewController: AccountFreezeInfoViewController(freeze: freeze))
        navigation.sheetPresentationController?.detents = [.medium(), .large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        presenter.present(navigation, animated: true)
    }

    /// The appeal link opens as Telegram's own link, usually @SpamBot's chat.
    private func submitAppeal() {
        guard let url = URL(string: freeze.appealLink) else { return }
        let presenter = presentingViewController
        dismiss(animated: true) {
            guard let presenter else { return }
            TelegramLinkRouter.shared.open(url, from: presenter.chatListTopPresenter)
        }
    }
}
