// ContactFormatProbe.swift

#if DEBUG
    import TDLibKit
    import UIKit

    /// Launch with `-ui-probe-contact-format`. Once an account is active it formats a few numbers with
    /// PhoneNumberFormat (TDLib's server country masks, as Telegram's formatPhoneNumber uses them), records each
    /// result in the log and in Documents/contact-format-probe.txt, and opens a received contact's details with a
    /// Russian header number and a British vCard number. Nothing is sent and the phonebook isn't read.
    @MainActor enum ContactFormatProbe {
        private static let numbers = ["+79991234567", "+442071234567", "14155550123", "+9955550101", "12"]

        static func runIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-contact-format") else { return }
            Task { @MainActor in
                for _ in 0..<60 where TDLib.shared.activeAccountID == nil {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                guard TDLib.shared.activeAccountID != nil else { return }
                try? await Task.sleep(for: .seconds(2))
                let client = TDLib.shared.activeClient
                var lines = [String]()
                for number in numbers {
                    let formatted = await PhoneNumberFormat.international(number, client: client)
                    let line = "contact-format-probe \(number) -> \(formatted ?? "nil")"
                    lines.append(line)
                    log(line)
                }
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(lines.joined(separator: "\n").utf8).write(
                        to: directory.appendingPathComponent("contact-format-probe.txt"),
                        options: .atomic,
                    )
                }
                var presenter = window.rootViewController
                while let presented = presenter?.presentedViewController {
                    presenter = presented
                }
                let contact = Contact(
                    firstName: "Ada",
                    lastName: "Lovelace",
                    phoneNumber: "+79991234567",
                    userId: 0,
                    vcard: "BEGIN:VCARD\nTEL:+442071234567\nEMAIL:ada@example.com\nEND:VCARD",
                )
                let details = TelegramContactDetailsViewController(contact: contact, client: client)
                let navigation = TelegramNavigationController(rootViewController: details)
                navigation.modalPresentationStyle = .pageSheet
                presenter?.present(navigation, animated: true)
            }
        }
    }
#endif
