// ServiceNotificationPresenter.swift

import TDLibKit
import UIKit

// MARK: - ServiceNotificationPresenter

/// updateServiceNotification, which the application must show as a popup: ApplicationContext's
/// serviceNotificationEvents alert with the notification's text and OK. TDLib's "AUTH_KEY_DROP_" notifications offer
/// Cancel and Log Out instead, the latter leaving the account as Settings' Log Out does.
@MainActor enum ServiceNotificationPresenter {
    static func present(_ notification: UpdateServiceNotification) {
        let text: String =
            if case .messageText(let message) = notification.content {
                message.text.text
            } else {
                MessageContentPresentation.make(notification.content).summary
            }
        guard !text.isEmpty, let presenter = topPresenter() else { return }
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        if notification.type.hasPrefix("AUTH_KEY_DROP_") {
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
            alert.addAction(UIAlertAction(title: L10n.telegram("Settings.Logout"), style: .destructive) { _ in
                try? TDLib.shared.logOutActiveAccount()
            })
        } else {
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        }
        presenter.present(alert, animated: true)
    }

    private static func topPresenter() -> UIViewController? {
        let window = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        return window?.rootViewController?.chatListTopPresenter
    }
}

#if DEBUG
    extension ServiceNotificationPresenter {
        /// `-ui-probe-service-notification` and `-ui-probe-service-notification-auth`: a made-up notification, plain
        /// or AUTH_KEY_DROP_, to look at the popups.
        static func presentProbeIfRequested() {
            let arguments = ProcessInfo.processInfo.arguments
            let auth = arguments.contains("-ui-probe-service-notification-auth")
            guard arguments.contains("-ui-probe-service-notification") || auth else { return }
            Task {
                try? await ProbeFixtures.waitForActiveAccount()
                try? await Task.sleep(for: .seconds(2))
                present(TDNativeUpdateServiceNotification(
                    type: auth ? "AUTH_KEY_DROP_PROBE" : "PROBE",
                    content: .messageText(TDNativeMessageText(
                        text: TDNativeFormattedText(text: "BetterTG service notification probe.", entities: []),
                        linkPreview: nil,
                        linkPreviewOptions: nil,
                    )),
                ))
            }
        }
    }
#endif
