// WebAppViewController.swift

import TDLibKit
import UIKit
import WebKit

// MARK: - WebAppLaunch

/// One Web App launch: the page TDLib returned and what the bridge may do with it.
struct WebAppLaunch {
    enum Source {
        /// An inline button's `openWebApp`; closing it calls `closeWebApp` with the launch ID.
        case button(launchID: Int64)
        /// A reply keyboard button's `getWebAppUrl` (Telegram's simple web view): `web_app_data_send` sends the
        /// data to the bot with the button's text.
        case keyboard(buttonText: String)
        #if DEBUG
            /// A local page with no bot behind it.
            case probe(html: String)
        #endif
    }

    let source: Source
    let url: URL
    let requiresSameOrigin: Bool
    let botUserID: Int64
    let botName: String
    let botUsername: String?
    /// The account whose client opened the page; DeviceStorage and SecureStorage keep its keys apart.
    let accountID: UUID?
    let client: TDLibClient
}

// MARK: - WebAppViewController

/// Telegram's WebAppController for a button's Web App: the page in a sheet under the bot's header, with
/// TelegramWebviewProxy's events (main and secondary buttons, back and settings buttons, expansion, colours,
/// popups, haptics, links, closing confirmation, inline queries and keyboard data) and the theme, viewport and safe
/// area events back to the page.
@MainActor final class WebAppViewController: UIViewController, WKNavigationDelegate, WKUIDelegate,
UISheetPresentationControllerDelegate, UIAdaptivePresentationControllerDelegate {
    struct Actions {
        /// A t.me link the page opened (`web_app_open_tg_link`), after the Web App closed.
        let openTelegramLink: (URL) -> Void
        /// "@bot query" for this chat, or for a chat of the given kinds (`web_app_switch_inline_query`).
        let switchInline: (_ text: String, _ types: InlineTargetChatTypes?) -> Void
    }

    /// The button's state from `web_app_setup_main_button` or `web_app_setup_secondary_button`.
    private struct ButtonState: Equatable {
        var text = ""
        var color: UIColor?
        var textColor: UIColor?
        var isVisible = false
        var isEnabled = true
        var showsProgress = false
        var position = "left"
    }

    /// Records the last touch on the page: links and the clipboard open only right after one (`lastTouchTimestamp`).
    private final class TouchRecorder: UIGestureRecognizer {
        var lastTouch: CFTimeInterval?

        override func touchesBegan(_: Set<UITouch>, with _: UIEvent) {
            lastTouch = CACurrentMediaTime()
            state = .failed
        }
    }

    /// Keeps the content controller from retaining the screen.
    private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
        weak var target: WebAppViewController?

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            target?.receive(message)
        }
    }

    /// WebAppWebView's event proxy: the page's `TelegramWebviewProxy.postEvent` reaches `performAction`.
    private static let eventProxySource = """
    var TelegramWebviewProxyProto = function() {};
    TelegramWebviewProxyProto.prototype.postEvent = function(eventName, eventData) {
        window.webkit.messageHandlers.performAction.postMessage({'eventName': eventName, 'eventData': eventData});
    };
    window.TelegramWebviewProxy = new TelegramWebviewProxyProto();
    """

    let fullscreen = WebAppFullscreen()

    private let launch: WebAppLaunch
    private let actions: Actions
    private let proxy = ScriptMessageProxy()
    private let touchRecorder = TouchRecorder()
    private let headerView = UIView()
    private let leftButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let moreButton = UIButton(type: .system)
    private let bottomPanel = UIView()
    private let buttonStack = UIStackView()
    private let mainButton = UIButton(type: .system)
    private let secondaryButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private var webView: WKWebView!
    /// The header, page and bottom panel, which fullscreen moves over the sheet.
    private let contentView = UIView()
    /// QR scanner, biometry, location and motion sensors reach the page and present through this.
    private lazy var bridge = WebAppBridge(
        launch: launch,
        send: { [weak self] in self?.sendEvent($0, data: $1) },
        presenter: { [weak self] in self },
        toastHost: { [weak self] in self?.webView },
    )
    private lazy var qrScanner = WebAppQRScanner(bridge: bridge)
    private lazy var biometry = WebAppBiometry(bridge: bridge)
    private var bottomPanelHeight: NSLayoutConstraint!
    private var mainButtonState = ButtonState()
    private var secondaryButtonState = ButtonState()
    private var hasBackButton = false
    private var hasSettingsButton = false
    private var needsCloseConfirmation = false
    /// `web_app_setup_swipe_behavior`: Telegram's `isPanGestureEnabled` for the sheet.
    private var allowsVerticalSwipe = true
    private var headerColor: UIColor?
    private var headerColorKey: String?
    private var backgroundColor: UIColor?
    private var bottomBarColor: UIColor?
    private var lastExpansion: CFTimeInterval?
    private var lastViewport: (height: CGFloat, expanded: Bool)?
    private var didClose = false
    private var dataTask: Task<Void, Never>?

    private var trustedOrigin: String? {
        launch.url.host.map { "\(launch.url.scheme ?? "https")://\($0)" }
    }

    init(launch: WebAppLaunch, actions: Actions) {
        self.launch = launch
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    deinit {
        dataTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        presentationController?.delegate = self
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .large
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.delegate = self
        }

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let content = WKUserContentController()
        proxy.target = self
        content.add(proxy, name: "performAction")
        content.addUserScript(WKUserScript(
            source: Self.eventProxySource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
        ))
        configuration.userContentController = content
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.alpha = 0
        touchRecorder.cancelsTouchesInView = false
        touchRecorder.delaysTouchesBegan = false
        webView.addGestureRecognizer(touchRecorder)

        configureHeader()
        configureBottomPanel()
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.startAnimating()

        contentView.frame = view.bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(contentView)
        for subview in [webView!, headerView, bottomPanel, loadingIndicator] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        bottomPanelHeight = bottomPanel.heightAnchor.constraint(equalToConstant: 0)
        let webViewTop = webView.topAnchor.constraint(equalTo: headerView.bottomAnchor)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 56),
            webViewTop,
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomPanel.topAnchor),
            bottomPanel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bottomPanel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomPanel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bottomPanelHeight,
            loadingIndicator.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
        ])
        fullscreen.attach(to: self, configuration: .init(
            title: launch.botName,
            contentView: contentView,
            headerView: headerView,
            webView: webView,
            webViewTopToHeader: webViewTop,
            menu: { [weak self] in self?.menuActions() ?? [] },
            back: { [weak self] in self?.leftButtonTapped() },
            send: { [weak self] in self?.sendEvent($0, data: $1) },
            layoutChanged: { [weak self] force in
                self?.updateBottomPanelHeight()
                self?.sendViewport(force: force)
            },
        ))
        updateColors()
        updateHeaderButtons()
        load()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.updateColors()
            self.sendThemeChanged()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateBottomPanelHeight()
        sendViewport(force: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed { fullscreen.disappear(alongside: transitionCoordinator) }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil { finish() }
    }

    // MARK: Theme

    /// generateWebAppThemeParams for the trait collection: TDLib's ThemeParameters for the launch and the page's
    /// `theme_changed` colours.
    static func themeColors(for traits: UITraitCollection) -> [(key: String, color: UIColor)] {
        let accent = UIColor.tintColor.resolvedColor(with: traits)
        return [
            ("bg_color", .systemBackground),
            ("secondary_bg_color", .systemGroupedBackground),
            ("text_color", .label),
            ("hint_color", .secondaryLabel),
            ("link_color", accent),
            ("button_color", accent),
            ("button_text_color", .white),
            ("header_bg_color", .systemBackground),
            ("bottom_bar_bg_color", .secondarySystemBackground),
            ("accent_text_color", accent),
            ("section_bg_color", .secondarySystemGroupedBackground),
            ("section_header_text_color", .secondaryLabel),
            ("subtitle_text_color", .secondaryLabel),
            ("destructive_text_color", .systemRed),
            ("section_separator_color", .separator),
        ].map { ($0.0, $0.1.resolvedColor(with: traits)) }
    }

    static func themeParameters(for traits: UITraitCollection) -> TDNativeThemeParameters {
        let colors = Dictionary(uniqueKeysWithValues: themeColors(for: traits).map { ($0.key, $0.color.rgbValue) })
        return TDNativeThemeParameters(
            backgroundColor: colors["bg_color"] ?? 0,
            secondaryBackgroundColor: colors["secondary_bg_color"] ?? 0,
            headerBackgroundColor: colors["header_bg_color"] ?? 0,
            bottomBarBackgroundColor: colors["bottom_bar_bg_color"] ?? 0,
            sectionBackgroundColor: colors["section_bg_color"] ?? 0,
            sectionSeparatorColor: colors["section_separator_color"] ?? 0,
            textColor: colors["text_color"] ?? 0,
            accentTextColor: colors["accent_text_color"] ?? 0,
            sectionHeaderTextColor: colors["section_header_text_color"] ?? 0,
            subtitleTextColor: colors["subtitle_text_color"] ?? 0,
            destructiveTextColor: colors["destructive_text_color"] ?? 0,
            hintColor: colors["hint_color"] ?? 0,
            linkColor: colors["link_color"] ?? 0,
            buttonColor: colors["button_color"] ?? 0,
            buttonTextColor: colors["button_text_color"] ?? 0,
        )
    }

    /// A stored value: a string, or null to remove the key; anything else is invalid.
    private static func storageValue(_ value: Any?) -> String?? {
        if let string = value as? String { return .some(string) }
        if value is NSNull { return .some(nil) }
        return nil
    }

    // MARK: Sheet

    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_: UISheetPresentationController) {
        sendViewport(force: true)
    }

    func presentationControllerShouldDismiss(_: UIPresentationController) -> Bool {
        !needsCloseConfirmation && allowsVerticalSwipe
    }

    func presentationControllerDidAttemptToDismiss(_: UIPresentationController) {
        if allowsVerticalSwipe { confirmClose() }
    }

    func presentationControllerDidDismiss(_: UIPresentationController) {
        finish()
    }

    // MARK: WKNavigationDelegate

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        loadingIndicator.stopAnimating()
        revealPage()
        sendThemeChanged()
        sendViewport(force: true)
    }

    func webView(
        _: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void,
    ) {
        // Telegram links inside the page go through the app, other schemes than the web's are dropped.
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() {
            if scheme == "tg" || InlineKeyboardActionPerformer.isTrusted(url) && url.host?.contains("t.me") == true,
               navigationAction.targetFrame?.isMainFrame != false, url != launch.url
            {
                decisionHandler(.cancel)
                close { [actions] in actions.openTelegramLink(url) }
                return
            }
            if !["http", "https", "about", "data", "blob"].contains(scheme) {
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    // MARK: WKUIDelegate

    func webView(
        _: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping @MainActor () -> Void,
    ) {
        let alert = UIAlertController(title: launch.botName, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(
        _: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping @MainActor (Bool) -> Void,
    ) {
        let alert = UIAlertController(title: launch.botName, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel) { _ in
            completionHandler(false)
        })
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default) { _ in
            completionHandler(true)
        })
        present(alert, animated: true)
    }

    // MARK: Private

    private func load() {
        #if DEBUG
            if case .probe(let html) = launch.source {
                webView.loadHTMLString(html, baseURL: launch.url)
                return
            }
        #endif
        webView.load(URLRequest(url: launch.url))
    }

    private func configureHeader() {
        leftButton.addAction(UIAction { [weak self] _ in self?.leftButtonTapped() }, for: .touchUpInside)
        titleLabel.text = launch.botName
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        moreButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        moreButton.accessibilityLabel = L10n.telegram("Common.More")
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] completion in
            completion(self?.menuActions() ?? [])
        }])
        for subview in [leftButton, titleLabel, moreButton] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            leftButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            leftButton.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 10),
            leftButton.heightAnchor.constraint(equalToConstant: 44),
            moreButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            moreButton.centerYAnchor.constraint(equalTo: leftButton.centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 44),
            moreButton.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: leftButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leftButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: moreButton.leadingAnchor, constant: -8),
        ])
    }

    private func configureBottomPanel() {
        buttonStack.spacing = 10
        buttonStack.distribution = .fillEqually
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        bottomPanel.clipsToBounds = true
        bottomPanel.addSubview(buttonStack)
        for (button, event) in [(mainButton, "main_button_pressed"), (secondaryButton, "secondary_button_pressed")] {
            button.layer.cornerRadius = 10
            button.layer.cornerCurve = .continuous
            button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.heightAnchor.constraint(equalToConstant: 50).isActive = true
            button.isHidden = true
            button.addAction(UIAction { [weak self] _ in self?.sendEvent(event) }, for: .touchUpInside)
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.tag = 1
            spinner.hidesWhenStopped = true
            spinner.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
            buttonStack.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            buttonStack.topAnchor.constraint(equalTo: bottomPanel.topAnchor, constant: 10),
            buttonStack.leadingAnchor.constraint(equalTo: bottomPanel.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            buttonStack.trailingAnchor.constraint(
                equalTo: bottomPanel.safeAreaLayoutGuide.trailingAnchor,
                constant: -16,
            ),
        ])
    }

    private func updateBottomPanelHeight() {
        let rows: CGFloat =
            switch (mainButtonState.isVisible, secondaryButtonState.isVisible) {
            case (false, false): 0
            case (true, true): buttonStack.axis == .vertical ? 2 : 1
            default: 1
            }
        let height = rows == 0 ? 0 : 10 + rows * 50 + (rows - 1) * 10 + max(view.safeAreaInsets.bottom, 10)
        if bottomPanelHeight.constant != height { bottomPanelHeight.constant = height }
    }

    private func applyButtons() {
        let accent = UIColor.tintColor
        for (button, state) in [(mainButton, mainButtonState), (secondaryButton, secondaryButtonState)] {
            button.isHidden = !state.isVisible
            button.setTitle(state.showsProgress ? "" : state.text, for: .normal)
            let fill = state.color ?? (button === mainButton ? accent : .secondarySystemFill)
            button.backgroundColor = fill
            button.setTitleColor(state.textColor ?? (button === mainButton ? .white : accent), for: .normal)
            button.isEnabled = state.isEnabled && !state.showsProgress
            button.alpha = state.isEnabled ? 1 : 0.6
            if let spinner = button.viewWithTag(1) as? UIActivityIndicatorView {
                spinner.color = state.textColor ?? .white
                if state.showsProgress { spinner.startAnimating() } else { spinner.stopAnimating() }
            }
        }
        // TelegramBottomPanel's secondary position: beside the main button, or above or below it.
        let position = secondaryButtonState.position
        buttonStack.axis = position == "top" || position == "bottom" ? .vertical : .horizontal
        let secondaryFirst = position == "left" || position == "top"
        if (buttonStack.arrangedSubviews.first === secondaryButton) != secondaryFirst {
            buttonStack.removeArrangedSubview(secondaryButton)
            buttonStack.insertArrangedSubview(secondaryButton, at: secondaryFirst ? 0 : 1)
        }
        updateBottomPanelHeight()
        UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
    }

    private func updateHeaderButtons() {
        let symbol = hasBackButton ? "chevron.backward" : "xmark"
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
        )
        configuration.title = hasBackButton ? L10n.telegram("Common.Back") : nil
        configuration.imagePadding = 4
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        leftButton.configuration = configuration
        leftButton.accessibilityLabel = hasBackButton ? L10n.telegram("Common.Back") : L10n.telegram("Common.Close")
        fullscreen.hasBack = hasBackButton
    }

    private func updateColors() {
        let traits = traitCollection
        let header = resolvedHeaderColor().resolvedColor(with: traits)
        headerView.backgroundColor = header
        let foreground: UIColor = header.isLight ? .black : .white
        titleLabel.textColor = foreground
        leftButton.tintColor = foreground
        moreButton.tintColor = foreground
        fullscreen.usesDarkContent = header.isLight
        let background = (backgroundColor ?? .systemBackground).resolvedColor(with: traits)
        view.backgroundColor = background
        contentView.backgroundColor = background
        webView?.backgroundColor = background
        webView?.scrollView.backgroundColor = background
        bottomPanel.backgroundColor = (bottomBarColor ?? .secondarySystemBackground).resolvedColor(with: traits)
    }

    private func resolvedHeaderColor() -> UIColor {
        if let headerColor { return headerColor }
        if headerColorKey == "secondary_bg_color" { return .systemGroupedBackground }
        if headerColorKey == "bg_color" { return backgroundColor ?? .systemBackground }
        return .systemBackground
    }

    private func revealPage() {
        guard webView.alpha == 0 else { return }
        loadingIndicator.stopAnimating()
        UIView.animate(withDuration: 0.2) { self.webView.alpha = 1 }
    }

    private func menuActions() -> [UIMenuElement] {
        var items = [UIMenuElement]()
        if let username = launch.botUsername, !username.isEmpty, let url = URL(string: "https://t.me/\(username)") {
            items.append(UIAction(
                title: L10n.telegram("WebApp.OpenBot"),
                image: UIImage(systemName: "bubble.left"),
            ) { [weak self] _ in
                self?.close { [actions = self?.actions] in actions?.openTelegramLink(url) }
            })
        }
        items.append(UIAction(
            title: L10n.telegram("WebApp.ReloadPage"),
            image: UIImage(systemName: "arrow.clockwise"),
        ) { [weak self] _ in
            self?.webView.reload()
        })
        if hasSettingsButton {
            items.append(UIAction(
                title: L10n.telegram("WebApp.Settings"),
                image: UIImage(systemName: "gearshape"),
            ) { [weak self] _ in
                self?.sendEvent("settings_button_pressed")
            })
        }
        items.append(UIAction(
            title: L10n.telegram("WebApp.PrivacyPolicy"),
            image: UIImage(systemName: "doc.text"),
        ) { [weak self] _ in
            self?.openPrivacyPolicy()
        })
        return items
    }

    /// The bot's own privacy policy when it has one, Telegram's mini app policy otherwise.
    private func openPrivacyPolicy() {
        let launch = launch
        Task { [weak self] in
            let info = try? await launch.client.getUserFullInfo(userId: launch.botUserID)
            let custom = info?.botInfo?.privacyPolicyUrl ?? ""
            guard self != nil,
                  let url = URL(string: custom.isEmpty ? L10n.telegram("WebApp.PrivacyPolicy_URL") : custom)
            else { return }
            await UIApplication.shared.open(url)
        }
    }

    private func leftButtonTapped() {
        if hasBackButton { return sendEvent("back_button_pressed") }
        if needsCloseConfirmation { return confirmClose() }
        close(completion: nil)
    }

    private func confirmClose() {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: launch.botName,
            message: L10n.telegram("WebApp.CloseConfirmation"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert
            .addAction(UIAlertAction(title: L10n.telegram("WebApp.CloseAnyway"), style: .destructive) { [weak self] _ in
                self?.close(completion: nil)
            })
        present(alert, animated: true)
    }

    private func close(completion: (() -> Void)?) {
        finish()
        presentingViewController?.dismiss(animated: true, completion: completion) ?? completion?()
    }

    /// The launch ends with `closeWebApp` once, however the sheet went away.
    private func finish() {
        guard !didClose else { return }
        didClose = true
        fullscreen.tearDown()
        if case .button(let launchID) = launch.source {
            let client = launch.client
            Task { _ = try? await client.closeWebApp(webAppLaunchId: launchID) }
        }
    }

    // MARK: Bridge

    private func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, !didClose else { return }
        if launch.requiresSameOrigin {
            let origin = message.frameInfo.securityOrigin
            guard trustedOrigin == "\(origin.protocol)://\(origin.host)" else { return }
        }
        guard let body = message.body as? [String: Any], let eventName = body["eventName"] as? String else { return }
        let eventData = body["eventData"] as? String
        let json = eventData
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        handle(eventName, json: json, rawData: eventData)
    }

    private func handle(_ eventName: String, json: [String: Any]?, rawData: String?) {
        switch eventName {
        case "web_app_ready":
            revealPage()
        case "web_app_expand":
            let now = CACurrentMediaTime()
            guard lastExpansion.map({ now >= $0 + 1 }) ?? true else { return }
            lastExpansion = now
            sheetPresentationController?.animateChanges {
                if !allowsVerticalSwipe { sheetPresentationController?.detents = [.large()] }
                sheetPresentationController?.selectedDetentIdentifier = .large
            }
            sendViewport(force: true)
        case "web_app_close":
            close(completion: nil)
        case "web_app_request_theme":
            sendThemeChanged()
        case "web_app_request_content_safe_area", "web_app_request_safe_area", "web_app_request_viewport":
            sendViewport(force: true)
        case "web_app_setup_main_button":
            if let state = buttonState(json, current: mainButtonState) { mainButtonState = state
                applyButtons()
            }
        case "web_app_setup_secondary_button":
            if let state = buttonState(json, current: secondaryButtonState) { secondaryButtonState = state
                applyButtons()
            }
        case "web_app_setup_back_button":
            if let isVisible = json?["is_visible"] as? Bool { hasBackButton = isVisible
                updateHeaderButtons()
            }
        case "web_app_setup_settings_button":
            if let isVisible = json?["is_visible"] as? Bool { hasSettingsButton = isVisible }
        case "web_app_setup_closing_behavior":
            if let needsConfirmation = json?["need_confirmation"] as? Bool {
                needsCloseConfirmation = needsConfirmation
                updateSwipeBehavior()
            }
        case "web_app_setup_swipe_behavior":
            if let allows = json?["allow_vertical_swipe"] as? Bool {
                allowsVerticalSwipe = allows
                updateSwipeBehavior()
            }
        case "web_app_set_header_color":
            if let key = json?["color_key"] as? String, ["bg_color", "secondary_bg_color"].contains(key) {
                headerColor = nil
                headerColorKey = key
            } else if let hex = json?["color"] as? String, let color = UIColor(webAppHex: hex) {
                headerColor = color
                headerColorKey = nil
            }
            UIView.animate(withDuration: 0.2) { self.updateColors() }
        case "web_app_set_background_color":
            if let hex = json?["color"] as? String, let color = UIColor(webAppHex: hex) {
                backgroundColor = color
                UIView.animate(withDuration: 0.2) { self.updateColors() }
            }
        case "web_app_set_bottom_bar_color":
            if let hex = json?["color"] as? String, let color = UIColor(webAppHex: hex) {
                bottomBarColor = color
                UIView.animate(withDuration: 0.2) { self.updateColors() }
            }
        case "web_app_trigger_haptic_feedback":
            triggerHaptic(json)
        case "web_app_open_popup":
            presentPopup(json)
        case "web_app_open_link":
            openLink(json)
        case "web_app_open_tg_link":
            guard let path = json?["path_full"] as? String, let url = URL(string: "https://t.me" + path) else { return }
            close { [actions] in actions.openTelegramLink(url) }
        case "web_app_read_text_from_clipboard":
            // Telegram fills the text only for attachment menu bots; a button's Web App gets none.
            guard let requestID = json?["req_id"] as? String else { return }
            sendEvent("clipboard_text_received", data: ["req_id": requestID])
        case "web_app_switch_inline_query":
            switchInline(json)
        case "web_app_data_send":
            sendKeyboardData(rawData)
        case "web_app_hide_keyboard":
            view.window?.endEditing(true)
        case "web_app_request_write_access":
            requestWriteAccess()
        case "web_app_request_phone":
            shareAccountContact()
        case "web_app_invoke_custom_method":
            invokeCustomMethod(json)
        case "web_app_device_storage_clear", "web_app_device_storage_get_key", "web_app_device_storage_save_key":
            handleDeviceStorage(eventName, json: json)
        case "web_app_secure_storage_clear", "web_app_secure_storage_get_key", "web_app_secure_storage_restore_key",
             "web_app_secure_storage_save_key":
            handleSecureStorage(eventName, json: json)
        case "web_app_request_fullscreen":
            fullscreen.setActive(true)
        case "web_app_exit_fullscreen":
            fullscreen.setActive(false)
        case "web_app_toggle_orientation_lock":
            if let locked = json?["locked"] as? Bool { fullscreen.setOrientationLocked(locked) }
        case "web_app_open_scan_qr_popup":
            qrScanner.open(json)
        case "web_app_close_scan_qr_popup":
            qrScanner.close()
        case "web_app_biometry_get_info":
            biometry.sendInfo()
        case "web_app_biometry_request_access":
            biometry.requestAccess(json)
        case "web_app_biometry_request_auth":
            biometry.requestAuth()
        case "web_app_biometry_update_token":
            biometry.updateToken(json)
        case "web_app_biometry_open_settings":
            if consumeRecentTouch() { biometry.openSettings() }
        default:
            break
        }
    }

    /// Without the vertical swipe the sheet neither resizes nor closes by dragging, as Telegram's disabled pan.
    private func updateSwipeBehavior() {
        isModalInPresentation = needsCloseConfirmation || !allowsVerticalSwipe
        guard let sheet = sheetPresentationController else { return }
        let current = sheet.selectedDetentIdentifier ?? .large
        sheet.detents = allowsVerticalSwipe
            ? [.medium(), .large()]
            : [current == .medium ? .medium() : .large()]
        sheet.prefersGrabberVisible = allowsVerticalSwipe
    }

    private func buttonState(_ json: [String: Any]?, current: ButtonState) -> ButtonState? {
        guard let json, var isVisible = json["is_visible"] as? Bool else { return nil }
        let text = json["text"] as? String ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { isVisible = false }
        var state = current
        state.text = text
        state.isVisible = isVisible
        state.color = (json["color"] as? String).flatMap(UIColor.init(webAppHex:))
        state.textColor = (json["text_color"] as? String).flatMap(UIColor.init(webAppHex:))
        state.isEnabled = json["is_active"] as? Bool ?? true
        state.showsProgress = json["is_progress_visible"] as? Bool ?? false
        if let position = json["position"] as? String { state.position = position }
        return state
    }

    private func triggerHaptic(_ json: [String: Any]?) {
        switch json?["type"] as? String {
        case "impact":
            let style: UIImpactFeedbackGenerator.FeedbackStyle? =
                switch json?["impact_style"] as? String {
                case "light": .light
                case "medium": .medium
                case "heavy": .heavy
                case "rigid": .rigid
                case "soft": .soft
                default: nil
                }
            if let style { UIImpactFeedbackGenerator(style: style).impactOccurred() }
        case "notification":
            let type: UINotificationFeedbackGenerator.FeedbackType? =
                switch json?["notification_type"] as? String {
                case "success": .success
                case "error": .error
                case "warning": .warning
                default: nil
                }
            if let type { UINotificationFeedbackGenerator().notificationOccurred(type) }
        case "selection_change":
            UISelectionFeedbackGenerator().selectionChanged()
        default:
            break
        }
    }

    /// AlertScreen for `web_app_open_popup`: up to three buttons, `popup_closed` with the chosen ID.
    private func presentPopup(_ json: [String: Any]?) {
        guard presentedViewController == nil, let json, let message = json["message"] as? String,
              let buttons = json["buttons"] as? [[String: Any]] else { return }
        let alert = UIAlertController(title: json["title"] as? String, message: message, preferredStyle: .alert)
        for button in buttons {
            guard let id = button["id"] as? String, let type = button["type"] as? String else { continue }
            let text = button["text"] as? String
            let (title, style): (String?, UIAlertAction.Style) =
                switch type {
                case "default": (text, .default)
                case "destructive": (text, .destructive)
                case "ok": (L10n.telegram("Common.OK"), .default)
                case "cancel": (L10n.telegram("Common.Cancel"), .cancel)
                case "close": (L10n.telegram("Common.Close"), .cancel)
                default: (nil, .default)
                }
            guard let title else { continue }
            let fixedStyle = style == .cancel && alert.actions.contains { $0.style == .cancel } ? .default : style
            alert.addAction(UIAlertAction(title: title, style: fixedStyle) { [weak self] _ in
                self?.sendEvent("popup_closed", data: ["button_id": id])
            })
        }
        guard !alert.actions.isEmpty else { return }
        present(alert, animated: true)
    }

    /// `web_app_open_link` leaves for the browser, only right after a touch on the page.
    private func openLink(_ json: [String: Any]?) {
        guard let string = json?["url"] as? String,
              let escaped = string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
              ?? Optional(string),
              let url = URL(string: string) ?? URL(string: escaped),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let lastTouch = touchRecorder.lastTouch, CACurrentMediaTime() < lastTouch + 10
        else { return }
        touchRecorder.lastTouch = nil
        UIApplication.shared.open(url)
    }

    /// lastTouchTimestamp: settings open only within 10 s of a touch on the page, once per touch.
    private func consumeRecentTouch() -> Bool {
        guard let lastTouch = touchRecorder.lastTouch, CACurrentMediaTime() < lastTouch + 10 else { return false }
        touchRecorder.lastTouch = nil
        return true
    }

    private func switchInline(_ json: [String: Any]?) {
        guard let query = json?["query"] as? String, let username = launch.botUsername, !username.isEmpty
        else { return }
        let names = json?["chat_types"] as? [String] ?? []
        let types = names.isEmpty
            ? nil
            : InlineTargetChatTypes(
                users: names.contains("users"),
                bots: names.contains("bots"),
                groups: names.contains("groups"),
                channels: names.contains("channels"),
            )
        let text = "@\(username) \(query)"
        close { [actions] in actions.switchInline(text, types) }
    }

    /// handleSendData: a keyboard button's Web App sends `{"data": …}` to the bot with the button's text and
    /// closes.
    private func sendKeyboardData(_ rawData: String?) {
        guard case .keyboard(let buttonText) = launch.source, dataTask == nil,
              let raw = rawData?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: raw, options: .fragmentsAllowed) as? [String: Any],
              let value = object["data"]
        else { return }
        let data: String
        if let string = value as? String {
            data = string
        } else if let encoded = try? JSONSerialization.data(withJSONObject: value),
                  let string = String(data: encoded, encoding: .utf8)
        {
            data = string
        } else { return }
        let launch = launch
        dataTask = Task {
            _ = try? await launch.client.sendWebAppData(botUserId: launch.botUserID, buttonText: buttonText, data: data)
        }
        close(completion: nil)
    }

    private func sendThemeChanged() {
        let colors = Self.themeColors(for: traitCollection).map { ($0.key, $0.color.webAppHex) }
        sendEvent("theme_changed", data: ["theme_params": Dictionary(uniqueKeysWithValues: colors)])
    }

    // MARK: Access and storage

    /// requestWriteAccess: "allowed" at once when the bot may already message the user, otherwise after the user
    /// agrees in WebApp.AllowWriteTitle's alert.
    private func requestWriteAccess() {
        let launch = launch
        Task { [weak self] in
            let canSend = await (try? launch.client.send(
                TDNativeRequests.canBotSendMessages(botUserId: launch.botUserID),
            )) != nil
            guard let self, !didClose else { return }
            guard !canSend else { return sendWriteAccess(allowed: true) }
            guard presentedViewController == nil else { return sendWriteAccess(allowed: false) }
            let alert = UIAlertController(
                title: L10n.telegram("WebApp.AllowWriteTitle"),
                message: L10n.telegram("WebApp.AllowWriteConfirmation", launch.botName)
                    .replacingOccurrences(of: "**", with: ""),
                preferredStyle: .alert,
            )
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel) { [weak self] _ in
                self?.sendWriteAccess(allowed: false)
            })
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default) { [weak self] _ in
                Task { [weak self] in
                    let allowed = await (try? launch.client.send(
                        TDNativeRequests.allowBotToSendMessages(botUserId: launch.botUserID),
                    )) != nil
                    self?.sendWriteAccess(allowed: allowed)
                }
            })
            present(alert, animated: true)
        }
    }

    private func sendWriteAccess(allowed: Bool) {
        sendEvent("write_access_requested", data: ["status": allowed ? "allowed" : "cancelled"])
    }

    /// shareAccountContact: after the user agrees, the account's own contact goes to the bot's chat, unblocking the
    /// bot first when needed.
    private func shareAccountContact() {
        let launch = launch
        Task { [weak self] in
            let isBlocked = await (try? launch.client.getUserFullInfo(userId: launch.botUserID))?.blockList != nil
            guard let self, !didClose else { return }
            guard presentedViewController == nil else { return sendPhoneRequested(sent: false) }
            let key = isBlocked ? "WebApp.SharePhoneConfirmationUnblock" : "WebApp.SharePhoneConfirmation"
            let alert = UIAlertController(
                title: L10n.telegram("WebApp.SharePhoneTitle"),
                message: L10n.telegram(key, launch.botName).replacingOccurrences(of: "**", with: ""),
                preferredStyle: .alert,
            )
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel) { [weak self] _ in
                self?.sendPhoneRequested(sent: false)
            })
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default) { [weak self] _ in
                self?.sendAccountContact(unblocking: isBlocked)
            })
            present(alert, animated: true)
        }
    }

    private func sendAccountContact(unblocking: Bool) {
        let launch = launch
        Task { [weak self] in
            do {
                let client = launch.client
                let me = try await client.getMe()
                guard !me.phoneNumber.isEmpty else { return }
                if unblocking {
                    _ = try await client.send(TDNativeRequests.setMessageSenderBlockList(
                        senderId: .messageSenderUser(.init(userId: launch.botUserID)),
                        blockList: nil,
                    ))
                }
                let chat = try await client.createPrivateChat(force: false, userId: launch.botUserID)
                _ = try await client.sendMessage(
                    chatId: chat.id,
                    inputMessageContent: .inputMessageContact(TDNativeInputMessageContact(contact: TDNativeContact(
                        phoneNumber: me.phoneNumber,
                        firstName: me.firstName,
                        lastName: me.lastName,
                        vcard: "",
                        userId: me.id,
                    ))),
                    options: nil,
                    replyMarkup: nil,
                    replyTo: nil,
                    topicId: nil,
                )
                self?.sendPhoneRequested(sent: true)
            } catch {
                self?.sendPhoneRequested(sent: false)
            }
        }
    }

    private func sendPhoneRequested(sent: Bool) {
        sendEvent("phone_requested", data: ["status": sent ? "sent" : "cancelled"])
    }

    /// invokeCustomMethod: the bot's answer goes back as JSON, or an empty object when it is not JSON.
    private func invokeCustomMethod(_ json: [String: Any]?) {
        guard let json, let requestID = json["req_id"] as? String, let method = json["method"] as? String,
              let params = json["params"] else { return }
        let parameters: String =
            if let string = params as? String {
                string
            } else if let data = try? JSONSerialization.data(withJSONObject: params, options: .fragmentsAllowed),
                      let string = String(data: data, encoding: .utf8)
            {
                string
            } else {
                "{}"
            }
        let launch = launch
        Task { [weak self] in
            guard let response = try? await launch.client.send(TDNativeRequests.sendWebAppCustomRequest(
                botUserId: launch.botUserID,
                method: method,
                parameters: parameters,
            )) else { return }
            let result = response.result
                .data(using: .utf8)
                .flatMap { try? JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed) }
                ?? [String: Any]()
            self?.sendEvent("custom_method_invoked", data: ["req_id": requestID, "result": result])
        }
    }

    /// DeviceStorage: `device_storage_key_saved`, `device_storage_key_received`, `device_storage_cleared` or
    /// `device_storage_failed` with Telegram's error codes.
    private func handleDeviceStorage(_ eventName: String, json: [String: Any]?) {
        guard let requestID = json?["req_id"] as? String else { return }
        let fail = { (error: String) in
            self.sendEvent("device_storage_failed", data: ["req_id": requestID, "error": error])
        }
        guard let accountID = launch.accountID else { return fail("UNKNOWN_ERROR") }
        let botUserID = launch.botUserID
        if eventName == "web_app_device_storage_clear" {
            try? WebAppDeviceStorage.clear(accountID: accountID, botUserID: botUserID)
            return sendEvent("device_storage_cleared", data: ["req_id": requestID])
        }
        guard let key = json?["key"] as? String else { return fail("KEY_INVALID") }
        if eventName == "web_app_device_storage_get_key" {
            let value = WebAppDeviceStorage.value(accountID: accountID, botUserID: botUserID, key: key)
            return sendEvent("device_storage_key_received", data: ["req_id": requestID, "value": value ?? NSNull()])
        }
        guard let value = Self.storageValue(json?["value"]) else { return fail("VALUE_INVALID") }
        do {
            try WebAppDeviceStorage.setValue(value, accountID: accountID, botUserID: botUserID, key: key)
            sendEvent("device_storage_key_saved", data: ["req_id": requestID])
        } catch {
            fail(error == .quotaExceeded ? "QUOTA_EXCEEDED" : "UNKNOWN_ERROR")
        }
    }

    /// SecureStorage: as DeviceStorage in the Keychain, plus restoring keys an account that is gone left behind.
    private func handleSecureStorage(_ eventName: String, json: [String: Any]?) {
        guard let requestID = json?["req_id"] as? String else { return }
        let fail = { (error: String) in
            self.sendEvent("secure_storage_failed", data: ["req_id": requestID, "error": error])
        }
        guard let accountID = launch.accountID else { return fail("UNKNOWN_ERROR") }
        let botUserID = launch.botUserID
        let activeAccountIDs = TDLib.shared.accounts.map(\.id)
        if eventName == "web_app_secure_storage_clear" {
            WebAppSecureStorage.clear(accountID: accountID, botUserID: botUserID)
            return sendEvent("secure_storage_cleared", data: ["req_id": requestID])
        }
        guard let key = json?["key"] as? String else {
            // Telegram ignores a restore without a key.
            if eventName != "web_app_secure_storage_restore_key" { fail("KEY_INVALID") }
            return
        }
        switch eventName {
        case "web_app_secure_storage_get_key":
            var data: [String: Any] = ["req_id": requestID, "value": NSNull()]
            do {
                let value = try WebAppSecureStorage.value(
                    accountID: accountID,
                    activeAccountIDs: activeAccountIDs,
                    botUserID: botUserID,
                    key: key,
                )
                if let value { data["value"] = value }
            } catch {
                if error == .canRestore { data["canRestore"] = true }
            }
            sendEvent("secure_storage_key_received", data: data)
        case "web_app_secure_storage_restore_key":
            do {
                let keys = try WebAppSecureStorage.restorableKeys(
                    accountID: accountID,
                    activeAccountIDs: activeAccountIDs,
                    botUserID: botUserID,
                    key: key,
                )
                guard !keys.isEmpty else { return fail("RESTORE_UNAVAILABLE") }
                openSecureStorageTransfer(requestID: requestID, key: key, keys: keys, accountID: accountID)
            } catch {
                fail(error == .storageNotEmpty ? "STORAGE_NOT_EMPTY" : "UNKNOWN_ERROR")
            }
        default:
            guard let value = Self.storageValue(json?["value"]) else { return fail("VALUE_INVALID") }
            do {
                try WebAppSecureStorage.setValue(
                    value,
                    accountID: accountID,
                    accountName: TDLib.shared.accounts.first { $0.id == accountID }?.title ?? "",
                    botUserID: botUserID,
                    key: key,
                )
                sendEvent("secure_storage_key_saved", data: ["req_id": requestID])
            } catch {
                fail(error == .quotaExceeded ? "QUOTA_EXCEEDED" : "UNKNOWN_ERROR")
            }
        }
    }

    /// openSecureBotStorageTransfer: Import moves the chosen account's keys into this one and gives the page the
    /// restored value; closing fails with RESTORE_CANCELLED.
    private func openSecureStorageTransfer(
        requestID: String,
        key: String,
        keys: [WebAppSecureStorage.ExistingKey],
        accountID: UUID,
    ) {
        guard presentedViewController == nil else {
            return sendEvent("secure_storage_failed", data: ["req_id": requestID, "error": "RESTORE_CANCELLED"])
        }
        let botUserID = launch.botUserID
        let transfer = WebAppSecureStorageTransferViewController(
            keys: keys,
            botUserID: botUserID,
            botName: launch.botName,
            accountID: accountID,
            client: launch.client,
        ) { [weak self] uuid in
            guard let self else { return }
            guard let uuid else {
                return sendEvent("secure_storage_failed", data: ["req_id": requestID, "error": "RESTORE_CANCELLED"])
            }
            WebAppSecureStorage.transferAllValues(fromUUID: uuid, accountID: accountID, botUserID: botUserID)
            let value = try? WebAppSecureStorage.value(
                accountID: accountID,
                activeAccountIDs: TDLib.shared.accounts.map(\.id),
                botUserID: botUserID,
                key: key,
            )
            sendEvent("secure_storage_key_restored", data: ["req_id": requestID, "value": value ?? NSNull()])
        }
        present(transfer, animated: true)
    }

    private func sendViewport(force: Bool) {
        guard let webView, webView.bounds.height > 0 else { return }
        let height = webView.bounds.height
        let expanded = sheetPresentationController?.selectedDetentIdentifier != .medium
        if !force, let lastViewport, lastViewport.height == height, lastViewport.expanded == expanded { return }
        lastViewport = (height, expanded)
        sendEvent("viewport_changed", data: ["height": height, "is_expanded": expanded, "is_state_stable": true])
        let bottom = mainButtonState.isVisible || secondaryButtonState.isVisible ? 0 : view.safeAreaInsets.bottom
        let insets: [String: Any] = [
            "top": fullscreen.safeAreaTop,
            "bottom": bottom,
            "left": view.safeAreaInsets.left,
            "right": view.safeAreaInsets.right,
        ]
        sendEvent("safe_area_changed", data: insets)
        let contentTop = fullscreen.contentSafeAreaTop
        sendEvent("content_safe_area_changed", data: ["top": contentTop, "bottom": 0, "left": 0, "right": 0])
    }

    /// WebAppWebView's sendEvent: `TelegramGameProxy.receiveEvent`, only to the launch's origin when it must stay
    /// the same.
    private func sendEvent(_ name: String, data: [String: Any]? = nil) {
        guard let webView, !didClose else { return }
        if launch.requiresSameOrigin, let url = webView.url,
           url.host.map({ "\(url.scheme ?? "https")://\($0)" }) != trustedOrigin { return }
        let payload = data
            .flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            .flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        let script = "window.TelegramGameProxy && window.TelegramGameProxy.receiveEvent && "
            + "window.TelegramGameProxy.receiveEvent(\"\(name)\", \(payload))"
        webView.evaluateJavaScript(script)
    }
}

// MARK: - UIColor + Web App

extension UIColor {
    /// "#rrggbb" or "#rgb" from the page.
    convenience init?(webAppHex hex: String) {
        var string = hex.trimmingCharacters(in: .whitespaces)
        if string.hasPrefix("#") { string.removeFirst() }
        if string.count == 3 { string = string.map { "\($0)\($0)" }.joined() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1,
        )
    }

    fileprivate var rgbValue: Int {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let clamp = { (value: CGFloat) in Int((min(max(value, 0), 1) * 255).rounded()) }
        return clamp(red) << 16 | clamp(green) << 8 | clamp(blue)
    }

    fileprivate var webAppHex: String {
        String(format: "#%06x", rgbValue)
    }

    fileprivate var isLight: Bool {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return 0.299 * red + 0.587 * green + 0.114 * blue > 0.6
    }
}
