// WebAppLocation.swift

import CoreLocation
import TDLibKit
import UIKit

// MARK: - WebAppLocation

/// WebAppController's location bridge (`web_app_check_location`, `web_app_request_location`,
/// `web_app_open_location_settings`): the system's When In Use access first, then the bot's own permission, asked once
/// with webAppLocationAlertController and changeable in the bot's settings, then a precise fix with its accuracy,
/// course and speed.
@MainActor final class WebAppLocation {
    private static let contentSelector = NSSelectorFromString("setContentViewController:")

    private let bridge: WebAppBridge
    private var isLoadingAlert = false

    init(bridge: WebAppBridge) {
        self.bridge = bridge
    }

    /// checkLocation.
    func check() {
        let location = load().location
        var data: [String: Any] = ["available": true, "access_requested": location?.isRequested ?? false]
        if let location, location.isRequested { data["access_granted"] = location.isAllowed }
        bridge.send("location_checked", data)
    }

    /// requestLocation: DeviceAccess.authorizeAccess(to: .location(.send)) first; denied access points to Settings and
    /// sends nothing.
    func request() {
        switch CLLocationManager().authorizationStatus {
        case .denied,
             .restricted:
            presentAccessDenied()
        case .notDetermined:
            Task { [weak self] in
                guard await WebAppLocationAuthorization.request() else { return }
                self?.requestAuthorized()
            }
        default:
            requestAuthorized()
        }
    }

    /// openLocationSettings: the bot's "Allow access to" switches.
    func openSettings() {
        WebAppBotSettingsViewController.present(.location, bridge: bridge)
    }

    // MARK: Private

    private func load() -> WebAppBotPermissions {
        WebAppBotPermissions.load(accountKey: bridge.accountKey, botUserID: bridge.botUserID)
    }

    private func requestAuthorized() {
        guard let location = load().location, location.isRequested else { return loadAlert() }
        guard location.isAllowed else {
            bridge.send("location_requested", ["available": false])
            return
        }
        Task { [weak self] in
            guard let fix = await OneShotLocation.fix(desiredAccuracy: kCLLocationAccuracyBest) else { return }
            self?.send(fix)
        }
    }

    private func send(_ fix: CLLocation) {
        bridge.send("location_requested", [
            "available": true,
            "latitude": fix.coordinate.latitude,
            "longitude": fix.coordinate.longitude,
            "altitude": fix.altitude,
            "course": fix.course,
            "speed": fix.speed,
            "horizontal_accuracy": fix.horizontalAccuracy,
            "vertical_accuracy": fix.verticalAccuracy,
            "course_accuracy": fix.courseAccuracy,
            "speed_accuracy": fix.speedAccuracy,
        ])
    }

    /// The account's and the bot's avatars for the alert.
    private func loadAlert() {
        guard !isLoadingAlert else { return }
        isLoadingAlert = true
        let client = bridge.client
        let botUserID = bridge.botUserID
        Task { [weak self] in
            let me = try? await client.getMe()
            let bot = try? await client.getUser(userId: botUserID)
            guard let self else { return }
            isLoadingAlert = false
            presentAlert(me: me, bot: bot)
        }
    }

    /// webAppLocationAlertController: the account's avatar with a location badge, an arrow to the bot's avatar,
    /// Telegram's text, Decline and Allow. Allowing shows the toast and asks again after 0.1 s; declining sends
    /// `available: false`. Either way the answer is kept for the bot.
    private func presentAlert(me: User?, bot: User?) {
        guard let presenter = bridge.topPresenter() else { return }
        let botName = bridge.botName
        let text = L10n.telegram("WebApp.LocationPermission.Text", botName, botName)
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("WebApp.LocationPermission.Decline"), style: .default) {
            [weak self] _ in
            self?.answer(false)
        })
        let allow = UIAlertAction(title: L10n.telegram("WebApp.LocationPermission.Allow"), style: .default) {
            [weak self] _ in
            self?.answer(true)
        }
        alert.addAction(allow)
        alert.preferredAction = allow
        let content = WebAppLocationAlertContentViewController(
            me: me,
            bot: bot,
            botUserID: bridge.botUserID,
            botName: botName,
            text: text,
            client: bridge.client,
        )
        if UIAlertController.instancesRespond(to: Self.contentSelector) {
            typealias SetContent = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
            unsafeBitCast(alert.method(for: Self.contentSelector), to: SetContent.self)(
                alert,
                Self.contentSelector,
                content,
            )
        } else {
            alert.message = text.replacing("**", with: "")
        }
        presenter.present(alert, animated: true)
    }

    private func answer(_ allowed: Bool) {
        WebAppBotPermissions.update(accountKey: bridge.accountKey, botUserID: bridge.botUserID) { permissions in
            permissions.location = WebAppBotPermissions.Location(isRequested: true, isAllowed: allowed)
        }
        guard allowed else {
            bridge.send("location_requested", ["available": false])
            return
        }
        if let host = bridge.toastHost() {
            let text = L10n.telegram("WebApp.LocationPermission.Succeed", bridge.botName)
            TelegramUndoToast.show(
                text: text.replacing("**", with: ""),
                in: host,
                bottomInset: 8,
                actionTitle: L10n.telegram("WebApp.LocationPermission.Undo"),
                undo: {},
            )
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            self?.request()
        }
    }

    private func presentAccessDenied() {
        guard let presenter = bridge.topPresenter() else { return }
        let alert = UIAlertController(
            title: L10n.betterTG("Permissions.LocationTitle"),
            message: L10n.betterTG("Permissions.WebAppLocationMessage"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("Notifications.PermissionsOpenSettings"), style: .default) {
            _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        presenter.present(alert, animated: true)
    }
}

// MARK: - WebAppLocationAuthorization

/// When In Use access asked while it is undecided; true once the user allows it.
@MainActor private final class WebAppLocationAuthorization: NSObject, CLLocationManagerDelegate {
    /// Requests in flight stay alive until the user answers.
    private static var active = Set<WebAppLocationAuthorization>()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Bool, Never>?

    static func request() async -> Bool {
        let request = WebAppLocationAuthorization()
        active.insert(request)
        defer { active.remove(request) }
        return await withCheckedContinuation { continuation in
            request.continuation = continuation
            request.manager.delegate = request
            request.manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in self?.authorizationChanged(status) }
    }

    private func authorizationChanged(_ status: CLAuthorizationStatus) {
        guard status != .notDetermined, let continuation else { return }
        self.continuation = nil
        manager.delegate = nil
        continuation.resume(returning: status == .authorizedWhenInUse || status == .authorizedAlways)
    }
}

// MARK: - WebAppLocationAlertContentViewController

/// AlertTransferHeaderComponent over AlertTextComponent: 60 pt avatars 148 pt apart with an arrow between, the
/// account's with Telegram's location badge, then the text with its bold names.
private final class WebAppLocationAlertContentViewController: UIViewController {
    private let me: User?
    private let bot: User?
    private let botUserID: Int64
    private let botName: String
    private let text: String
    private let client: TDLibClient
    private let stack = UIStackView()

    init(me: User?, bot: User?, botUserID: Int64, botName: String, text: String, client: TDLibClient) {
        self.me = me
        self.bot = bot
        self.botUserID = botUserID
        self.botName = botName
        self.text = text
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        let userAvatar = avatar(for: me, isAccount: true)
        let botAvatar = avatar(for: bot, isAccount: false)
        let arrow = UIImageView(image: UIImage(
            systemName: "arrow.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold),
        ))
        arrow.tintColor = .secondaryLabel
        let badge = UIImageView(image: Self.locationBadge())
        badge.layer.cornerRadius = 14
        badge.layer.borderWidth = 2
        badge.layer.borderColor = UIColor.systemBackground.cgColor
        badge.clipsToBounds = true
        for subview in [userAvatar, botAvatar, arrow, badge] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalToConstant: 148),
            header.heightAnchor.constraint(equalToConstant: 60),
            userAvatar.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            userAvatar.topAnchor.constraint(equalTo: header.topAnchor),
            userAvatar.widthAnchor.constraint(equalToConstant: 60),
            userAvatar.heightAnchor.constraint(equalToConstant: 60),
            botAvatar.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            botAvatar.topAnchor.constraint(equalTo: header.topAnchor),
            botAvatar.widthAnchor.constraint(equalToConstant: 60),
            botAvatar.heightAnchor.constraint(equalToConstant: 60),
            arrow.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            arrow.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 28),
            badge.heightAnchor.constraint(equalToConstant: 28),
            badge.trailingAnchor.constraint(equalTo: userAvatar.trailingAnchor, constant: 4),
            badge.bottomAnchor.constraint(equalTo: userAvatar.bottomAnchor, constant: 4),
        ])

        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.attributedText = WebAppBridge.attributed(
            text,
            font: .preferredFont(forTextStyle: .footnote),
            color: .label,
        )

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 11
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(label)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            label.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let width = view.bounds.width > 0 ? view.bounds.width : 270
        let size = view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        )
        if preferredContentSize.height != size.height {
            preferredContentSize = CGSize(width: width, height: size.height)
        }
    }

    // MARK: Private

    /// generateLocationIcon: Telegram's green-to-blue gradient circle under a white location glyph.
    private static func locationBadge() -> UIImage {
        let size = CGSize(width: 28, height: 28)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [
                UIColor(red: 0x3C / 255, green: 0xA5 / 255, blue: 0xEB / 255, alpha: 1).cgColor,
                UIColor(red: 0x36 / 255, green: 0xC0 / 255, blue: 0x89 / 255, alpha: 1).cgColor,
            ]
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0, 1],
            ) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: [],
                )
            }
            let glyph = UIImage(
                systemName: "location.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold),
            )?.withTintColor(.white, renderingMode: .alwaysOriginal)
            if let glyph {
                glyph.draw(at: CGPoint(
                    x: (size.width - glyph.size.width) / 2,
                    y: (size.height - glyph.size.height) / 2,
                ))
            }
        }
    }

    private func avatar(for user: User?, isAccount: Bool) -> ProfileAvatarView {
        let view = ProfileAvatarView()
        view.showsContextMenu = false
        view.isUserInteractionEnabled = false
        let placeholder = user?.telegramAvatarPlaceholder ?? TelegramAvatarPlaceholder(
            peerID: isAccount ? 0 : botUserID,
            accentColorID: 0,
            upgradedGiftColors: nil,
            letters: isAccount ? [] : botName.telegramAvatarFirstLetter.map { [$0] } ?? [],
            isDeleted: false,
        )
        view.configure(
            file: user?.profilePhoto?.small,
            minithumbnail: user?.profilePhoto?.minithumbnail,
            placeholder: placeholder,
            usesPeerPhotoForSavedMessages: isAccount,
            client: client,
        )
        return view
    }
}
