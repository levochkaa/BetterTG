// WebAppBridge.swift

import TDLibKit
import UIKit

// MARK: - WebAppBridge

/// What the Web App's device features need from its screen: the bot, the account its permissions belong to, the way
/// back to the page and the controller presenting their screens and alerts.
@MainActor struct WebAppBridge {
    let botUserID: Int64
    let botName: String
    let botUsername: String?
    let client: TDLibClient
    /// The account the bot's permissions and biometric token belong to.
    let accountKey: String
    let send: (String, [String: Any]?) -> Void
    let presenter: () -> UIViewController?
    /// The view showing the Web App's toasts.
    let toastHost: () -> UIView?

    init(
        launch: WebAppLaunch,
        send: @escaping (String, [String: Any]?) -> Void,
        presenter: @escaping () -> UIViewController?,
        toastHost: @escaping () -> UIView?,
    ) {
        self.botUserID = launch.botUserID
        self.botName = launch.botName
        self.botUsername = launch.botUsername
        self.client = launch.client
        // The account that opened the Web App, which can differ from the active one.
        self.accountKey = (launch.accountID ?? TDLib.shared.activeAccountID)?.uuidString ?? "none"
        self.send = send
        self.presenter = presenter
        self.toastHost = toastHost
    }

    /// Telegram's `**bold**` spans over `font`.
    static func attributed(_ text: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let bold = UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        let result = NSMutableAttributedString()
        for (index, part) in text.components(separatedBy: "**").enumerated() {
            result.append(NSAttributedString(string: part, attributes: [
                .font: index.isMultiple(of: 2) ? font : bold,
                .foregroundColor: color,
            ]))
        }
        return result
    }

    /// The controller on top of the Web App, which presents the next screen.
    func topPresenter() -> UIViewController? {
        var top = presenter()
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
