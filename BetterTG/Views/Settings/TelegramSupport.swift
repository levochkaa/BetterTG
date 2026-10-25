// TelegramSupport.swift

import UIKit

// MARK: - TelegramSupport

/// Telegram's ways to ask for help: PeerInfoScreen's `.support` note, the support chat and the FAQ. Settings and
/// account deletion's Contact Support use them.
@MainActor enum TelegramSupport {
    /// Settings.FAQ_Intro: volunteers answer; FAQ opens the FAQ, OK the support chat.
    static func alert(
        openFaq: @escaping @MainActor () -> Void,
        openChat: @escaping @MainActor () -> Void,
    ) -> UIAlertController {
        let alert = UIAlertController(title: nil, message: L10n.telegram("Settings.FAQ_Intro"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Settings.FAQ_Button"), style: .default) { _ in openFaq() })
        let ok = UIAlertAction(title: L10n.telegram("Common.OK"), style: .default) { _ in openChat() }
        alert.addAction(ok)
        alert.preferredAction = ok
        return alert
    }

    /// The chat with getSupportUser, while the account that asked is still the active one.
    static func openChat(from controller: UIViewController) {
        guard let accountID = TDLib.shared.activeAccountID else { return }
        let client = TDLib.shared.activeClient
        Task { [weak controller] in
            guard let user = try? await client.getSupportUser(),
                  let controller, TDLib.shared.activeAccountID == accountID
            else { return }
            TelegramLinkRouter.shared.openUser(user.id, from: controller)
        }
    }

    /// Settings.FAQ_URL in the chosen browser, as the in-app link to the FAQ section opens it.
    static func openFaq(from controller: UIViewController) {
        if let url = URL(string: L10n.telegram("Settings.FAQ_URL")) { WebBrowser.open(url, from: controller) }
    }
}
