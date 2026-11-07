// DeviceContactAppender.swift

import Contacts
import ContactsUI
import UIKit

// MARK: - DeviceContactAppender

/// The phone menu's Add to Existing Contact (addContactToExisting): a phonebook person picked from the system's
/// contact picker gets the number appended (contactDataManager.appendContactData), unless the card already has it.
/// Telegram's picker also lists the account's contacts and matches them to cards by number; BetterTG picks from the
/// phonebook only.
@MainActor final class DeviceContactAppender: NSObject, CNContactPickerDelegate {
    private var number = ""
    private weak var host: UIViewController?

    /// The card with the number appended as mobile, unless it already has the number.
    private nonisolated static func save(_ number: String, to identifier: String) {
        let store = CNContactStore()
        let keys = [CNContactPhoneNumbersKey as CNKeyDescriptor]
        guard let contact = try? store.unifiedContact(withIdentifier: identifier, keysToFetch: keys),
              let mutable = contact.mutableCopy() as? CNMutableContact else { return }
        let digits = number.filter(\.isNumber)
        guard !mutable.phoneNumbers.contains(where: { $0.value.stringValue.filter(\.isNumber) == digits }) else {
            return
        }
        mutable.phoneNumbers.append(CNLabeledValue(
            label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: number),
        ))
        let request = CNSaveRequest()
        request.update(mutable)
        try? store.execute(request)
    }

    func present(number: String, from host: UIViewController) {
        self.number = number
        self.host = host
        let picker = CNContactPickerViewController()
        picker.delegate = self
        host.present(picker, animated: true)
    }

    nonisolated func contactPicker(_: CNContactPickerViewController, didSelect contact: CNContact) {
        let identifier = contact.identifier
        MainActor.assumeIsolated {
            append(to: identifier)
        }
    }

    private func append(to identifier: String) {
        let number = number
        Task { [weak self] in
            let granted = await (try? CNContactStore().requestAccess(for: .contacts)) ?? false
            guard granted else {
                self?.presentAccessDenied()
                return
            }
            await Task.detached { Self.save(number, to: identifier) }.value
        }
    }

    /// Telegram's contacts permission text, with Settings.
    private func presentAccessDenied() {
        guard let host else { return }
        let alert = UIAlertController(
            title: L10n.telegram("AccessDenied.Title"),
            message: L10n.telegram("AccessDenied.Contacts"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("AccessDenied.Settings"), style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        host.present(alert, animated: true)
    }
}
