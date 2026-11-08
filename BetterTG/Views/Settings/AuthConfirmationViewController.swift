// AuthConfirmationViewController.swift

import TDLibKit
import UIKit

// MARK: - AuthConfirmationViewController

/// Telegram's AuthConfirmationScreen for an OAuth request (a "Log in with Telegram" link, or TDLib's
/// updateNewOauthRequest): the bot of the site with Log in to the site, or to a verified app (Unverified App
/// otherwise), what it will receive, the device and the IP address with its region, Allow Messages when the bot asks
/// for it, then Log In and Cancel. The emoji shown on the other device are picked first when TDLib asks for that, or
/// after Log In otherwise; a request for the phone number asks Deny or Allow. Log In accepts the request and opens the
/// link it returns, with Login Successful's toast; Cancel declines it.
final class AuthConfirmationViewController: SettingsListViewController {
    /// A probe's made-up request: Log In and Cancel never reach TDLib.
    var isProbe = false

    private let info: OauthLinkInfo
    private var bot: SettingsPeer?
    private var botName = ""
    private var allowsMessages = true
    private var isWorking = false
    private var matchCode = ""
    private var didFinish = false

    private var sourceTitle: String {
        guard info.fromApp else { return info.domain }
        return info.verifiedAppName.isEmpty ? L10n.telegram("AuthConfirmation.UnverifiedApp") : info.verifiedAppName
    }

    init(info: OauthLinkInfo) {
        self.info = info
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        isModalInPresentation = true
        let client = client
        let botID = info.botUserId
        Task { [weak self] in
            let peer = botID == 0 ? nil : await SettingsPeer.user(botID, client: client)
            guard let self else { return }
            bot = peer
            botName = peer?.title ?? ""
            reload()
            if info.matchCodeFirst, !info.matchCodes.isEmpty { askForMatchCode(first: true) }
        }
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [SettingsSection]()
        let title = L10n.telegram("AuthConfirmation.Title", sourceTitle).withoutTelegramMarkup
        let description = L10n.telegram(info.fromApp
            ? "AuthConfirmation.DescriptionApp"
            : "AuthConfirmation.Description")
            .withoutTelegramMarkup
        if let bot {
            sections.append(SettingsSection(
                footer: description,
                // The bot's photo beside the title, as AuthConfirmationScreen's avatar heads it.
                rows: [SettingsRow(title: title, style: .peer(SettingsPeer(
                    id: bot.id,
                    title: title,
                    file: bot.file,
                    minithumbnail: bot.minithumbnail,
                    placeholder: bot.placeholder,
                )))],
            ))
        } else {
            sections.append(SettingsSection(
                footer: description,
                rows: [SettingsRow(title: title, style: .subtitle)],
            ))
        }
        sections.append(SettingsSection(rows: [
            SettingsRow(
                title: L10n.telegram("AuthConfirmation.Device"),
                detail: [info.platform, info.browser].filter { !$0.isEmpty }.joined(separator: " · "),
                style: .subtitle,
            ),
            SettingsRow(
                title: info.ipAddress,
                detail: info.location,
                style: .subtitle,
            ),
        ]))
        if info.requestWriteAccess {
            sections.append(SettingsSection(
                footer: L10n.telegram("AuthConfirmation.AllowMessagesInfo", botName),
                rows: [SettingsRow(
                    title: L10n.telegram("AuthConfirmation.AllowMessages"),
                    accessory: .toggle(isOn: allowsMessages, onChange: { [weak self] isOn in
                        self?.allowsMessages = isOn
                    }),
                )],
            ))
        }
        sections.append(SettingsSection(rows: [
            SettingsRow(
                title: L10n.telegram("AuthConfirmation.LogIn"),
                style: .action(destructive: false),
                isEnabled: !isWorking,
            ) { [weak self] in self?.logInPressed() },
            SettingsRow(
                title: L10n.telegram("AuthConfirmation.Cancel"),
                style: .action(destructive: true),
                isEnabled: !isWorking,
            ) { [weak self] in self?.cancelPressed() },
        ]))
        return sections
    }

    /// Log In: the emoji first when TDLib asks for them after the confirmation, then the phone number's question.
    private func logInPressed() {
        guard !isWorking else { return }
        if !info.matchCodeFirst, !info.matchCodes.isEmpty, matchCode.isEmpty {
            askForMatchCode(first: false)
            return
        }
        guard info.requestPhoneNumberAccess else {
            accept(sharePhoneNumber: false)
            return
        }
        let phone = TDLib.shared.activeAccount?.phoneNumber.map { "+" + $0 } ?? ""
        let alert = UIAlertController(
            title: L10n.telegram("AuthConfirmation.PhoneNumberConfirmation.Title"),
            message: L10n.telegram("AuthConfirmation.PhoneNumberConfirmation.Text", sourceTitle, phone)
                .withoutTelegramMarkup,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(
            title: L10n.telegram("AuthConfirmation.PhoneNumberConfirmation.Deny"),
            style: .cancel,
        ) {
            [weak self] _ in self?.accept(sharePhoneNumber: false)
        })
        alert.addAction(UIAlertAction(
            title: L10n.telegram("AuthConfirmation.PhoneNumberConfirmation.Allow"),
            style: .default,
        ) {
            [weak self] _ in self?.accept(sharePhoneNumber: true)
        })
        present(alert, animated: true)
    }

    /// The emoji page: Tap the emoji shown on your other device, each code a choice.
    private func askForMatchCode(first: Bool) {
        let sheet = UIAlertController(
            title: L10n.telegram("AuthConfirmation.Emoji.Title").replacing("\n", with: " "),
            message: first
                ? L10n.telegram("AuthConfirmation.Emoji.DescriptionFirst", sourceTitle).withoutTelegramMarkup
                : L10n.telegram("AuthConfirmation.Emoji.Description"),
            preferredStyle: .alert,
        )
        for code in info.matchCodes.shuffled() {
            sheet.addAction(UIAlertAction(title: code, style: .default) { [weak self] _ in
                self?.matchCodeChosen(code, first: first)
            })
        }
        sheet
            .addAction(UIAlertAction(title: L10n.telegram("AuthConfirmation.Cancel"), style: .cancel) { [weak self] _ in
                if first { self?.cancelPressed() }
            })
        present(sheet, animated: true)
    }

    private func matchCodeChosen(_ code: String, first: Bool) {
        matchCode = code
        guard first else {
            logInPressed()
            return
        }
        // checkOauthRequestMatchCode: a wrong emoji ends the request.
        let client = client
        let url = info.url
        guard !isProbe else { return }
        isWorking = true
        reload()
        Task { [weak self] in
            let checked = await (try? client.send(TDNativeRequests.checkOauthRequestMatchCode(
                url: url,
                matchCode: code,
            )))
                != nil
            guard let self else { return }
            isWorking = false
            reload()
            if !checked { finish(success: false, link: nil) }
        }
    }

    private func accept(sharePhoneNumber: Bool) {
        guard !isWorking else { return }
        isWorking = true
        reload()
        let client = client
        let url = info.url
        let code = matchCode
        let allowsMessages = info.requestWriteAccess && allowsMessages
        if isProbe {
            finish(success: false, link: nil)
            return
        }
        Task { [weak self] in
            let result = try? await client.send(TDNativeRequests.acceptOauthRequest(
                url: url,
                matchCode: code,
                allowWriteAccess: allowsMessages,
                allowPhoneNumberAccess: sharePhoneNumber,
                tonConnectConnectData: nil,
            ))
            guard let self else { return }
            finish(success: result != nil, link: result?.url, sharedPhone: sharePhoneNumber)
        }
    }

    private func cancelPressed() {
        guard !didFinish else { return }
        didFinish = true
        let client = client
        let url = info.url
        if !isProbe { Task { _ = try? await client.send(TDNativeRequests.declineOauthRequest(url: url)) } }
        dismiss(animated: true)
    }

    /// Login Successful or Login Failed over the screen the request came to, and the link the site returns.
    private func finish(success: Bool, link: String?, sharedPhone: Bool = true) {
        guard !didFinish else { return }
        didFinish = true
        let host = presentingViewController?.view
        let domain = info.domain
        let noNumber = info.requestPhoneNumberAccess && !sharedPhone
        dismiss(animated: true) {
            if let host {
                let text: String =
                    if success {
                        L10n.telegram(
                            noNumber
                                ? "AuthConfirmation.LoginSuccess.TextNoNumber"
                                : "AuthConfirmation.LoginSuccess.Text",
                            domain,
                        )
                        .withoutTelegramLinks
                    } else {
                        L10n.telegram("AuthConfirmation.LoginFail.Text", domain).withoutTelegramLinks
                    }
                TelegramUndoToast.show(
                    title: L10n.telegram(success
                        ? "AuthConfirmation.LoginSuccess.Title"
                        : "AuthConfirmation.LoginFail.Title"),
                    text: text,
                    in: host,
                    bottomInset: 80,
                    undo: nil,
                )
            }
            if success, let link, !link.isEmpty, let url = URL(string: link) {
                UIApplication.shared.open(url)
            }
        }
    }
}

// MARK: - AuthConfirmationPresenter

/// OpenResolvedUrl's `.oauth` and TDLib's updateNewOauthRequest: getOauthLinkInfo, then the confirmation as a sheet
/// over the active account's screens.
@MainActor enum AuthConfirmationPresenter {
    static func present(url: String, client: TDLibClient) {
        Task {
            guard let info = try? await client.send(TDNativeRequests.getOauthLinkInfo(url: url, inAppOrigin: "")),
                  let presenter = topPresenter()
            else { return }
            let navigation = UINavigationController(rootViewController: AuthConfirmationViewController(info: info))
            navigation.sheetPresentationController?.detents = [.large()]
            presenter.present(navigation, animated: true)
        }
    }

    fileprivate static func topPresenter() -> UIViewController? {
        let window = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        return window?.rootViewController?.chatListTopPresenter
    }
}

#if DEBUG
    extension AuthConfirmationPresenter {
        /// `-ui-probe-oauth`: a made-up request from BotFather's site with every permission asked, to look at the
        /// screen; its link is no real request, so Log In only fails.
        static func presentProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-oauth") else { return }
            Task {
                try? await ProbeFixtures.waitForActiveAccount()
                try? await Task.sleep(for: .seconds(2))
                _ = try? await TDLib.shared.activeClient.send(TDNativeRequests.searchPublicChat(username: "BotFather"))
                let info = TDNativeOauthLinkInfo(
                    userId: 0,
                    url: "https://oauth.telegram.org/probe",
                    domain: "example.org",
                    fromApp: false,
                    verifiedAppName: "",
                    botUserId: 93_372_553,
                    requestWriteAccess: true,
                    requestPhoneNumberAccess: true,
                    requestTonWalletAccess: false,
                    dappClientId: "",
                    tonConnectManifestUrl: "",
                    tonProofPayload: "",
                    browser: "Safari 27",
                    platform: "macOS",
                    ipAddress: "203.0.113.7",
                    location: "Tbilisi, Georgia",
                    matchCodeFirst: false,
                    matchCodes: ["🍏", "🚀", "🎲"],
                )
                guard let presenter = topPresenter() else { return }
                let controller = AuthConfirmationViewController(info: info)
                controller.isProbe = true
                let navigation = UINavigationController(rootViewController: controller)
                presenter.present(navigation, animated: true)
            }
        }
    }
#endif
