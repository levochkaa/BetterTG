// NewContactViewController.swift

import TDLibKit
import UIKit

// MARK: - NewContactViewController

/// Telegram's NewContactScreen: first and last name and the phone number. The number is looked up while typing
/// (searchUserByPhoneNumber, as Telegram's resolvePeerByPhone) to say whether it is on Telegram, and a person found
/// can see the account's number with Share My Phone Number. Done (on its tap only) adds the person (addContact) or
/// imports the number (importContacts), then opens the person's chat, or returns when the number isn't on Telegram.
final class NewContactViewController: SettingsListViewController, ComposeFlowScreen {
    private enum Lookup: Equatable {
        case idle
        case resolving
        case found(userID: Int64, firstName: String, isContact: Bool)
        case notFound

        var isFound: Bool {
            if case .found = self {
                true
            } else {
                false
            }
        }
    }

    private static let lookupDelay = Duration.milliseconds(500)
    private static let statusSection = 2
    private static let shareSection = 3

    private var firstName = ""
    private var lastName = ""
    private var phoneNumber = ""
    private var lookup = Lookup.idle
    private var sharesPhoneNumber = false
    private var isSaving = false
    private var lookupTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    /// The number's digits; TDLib takes it in the international format.
    private var phoneDigits: String {
        phoneNumber.filter { $0.isASCII && $0.isNumber }
    }

    deinit {
        lookupTask?.cancel()
        saveTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("NewContact.Title")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Done"), style: .prominent, target: self, action: #selector(donePressed),
        )
        updateDoneButton()
    }

    override func makeSections() -> [SettingsSection] {
        [
            SettingsSection(rows: [
                SettingsRow(title: "", style: .input(SettingsTextInput(
                    text: firstName,
                    placeholder: L10n.telegram("UserInfo.FirstNamePlaceholder"),
                    autocapitalization: .words,
                ) { [weak self] text in
                    self?.firstName = text
                    self?.updateDoneButton()
                })),
                SettingsRow(title: "", style: .input(SettingsTextInput(
                    text: lastName,
                    placeholder: L10n.telegram("UserInfo.LastNamePlaceholder"),
                    autocapitalization: .words,
                ) { [weak self] text in self?.lastName = text })),
            ]),
            SettingsSection(rows: [SettingsRow(title: "", style: .input(SettingsTextInput(
                text: phoneNumber,
                placeholder: L10n.telegram("Contacts.PhoneNumber"),
                autocapitalization: .none,
                autocorrection: false,
                keyboardType: .phonePad,
            ) { [weak self] text in self?.phoneNumberChanged(text) }))]),
            SettingsSection(rows: statusRows()),
            shareSection(),
        ]
    }

    /// Telegram's footers carry a link action (View, Invite) BetterTG doesn't offer; the sentence stays.
    private static func withoutLinkAction(_ text: String) -> String {
        guard let range = text.range(of: " [") else { return text }
        return String(text[..<range.lowerBound])
    }

    private func statusRows() -> [SettingsRow] {
        let text: String? =
            switch lookup {
            case .idle, .resolving: nil
            case .found(_, _, let isContact):
                isContact
                    ? Self.withoutLinkAction(L10n.telegram("AddContact.PhoneNumber.IsContact"))
                    : L10n.telegram("AddContact.PhoneNumber.Registered")
            case .notFound: Self.withoutLinkAction(L10n.telegram("AddContact.PhoneNumber.NotRegistered"))
            }
        if lookup == .resolving {
            return [SettingsRow(title: "", style: .status(.secondaryLabel), accessory: .activity)]
        }
        return text.map { [SettingsRow(title: $0, style: .status(.secondaryLabel))] } ?? []
    }

    /// AddContact.SharedContactException for a person found who isn't a contact yet.
    private func shareSection() -> SettingsSection {
        guard case .found(_, let name, false) = lookup else { return SettingsSection(rows: []) }
        return SettingsSection(
            footer: L10n.telegram("AddContact.SharedContactExceptionInfo", name),
            rows: [SettingsRow(
                title: L10n.telegram("AddContact.SharedContactException"),
                accessory: .toggle(isOn: sharesPhoneNumber, onChange: { [weak self] isOn in
                    self?.sharesPhoneNumber = isOn
                }),
            )],
        )
    }

    private func phoneNumberChanged(_ text: String) {
        phoneNumber = text
        lookupTask?.cancel()
        lookupTask = nil
        let digits = phoneDigits
        updateDoneButton()
        guard digits.count >= 5, contextIsCurrent else {
            setLookup(.idle)
            return
        }
        setLookup(.resolving)
        let client = client
        lookupTask = Task { [weak self] in
            try? await Task.sleep(for: Self.lookupDelay)
            guard !Task.isCancelled else { return }
            let user = try? await client.send(TDNativeRequests.searchUserByPhoneNumber(
                phoneNumber: digits, onlyLocal: false,
            ))
            guard let self, !Task.isCancelled, contextIsCurrent, phoneDigits == digits else { return }
            lookupTask = nil
            let result = user.map { Lookup.found(userID: $0.id, firstName: $0.firstName, isContact: $0.isContact) }
            setLookup(result ?? .notFound)
        }
    }

    private func setLookup(_ value: Lookup) {
        guard value != lookup else { return }
        lookup = value
        if !value.isFound { sharesPhoneNumber = false }
        reload(sections: IndexSet([Self.statusSection, Self.shareSection]))
    }

    private func updateDoneButton() {
        let hasName = !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        navigationItem.rightBarButtonItem?.isEnabled = hasName && !phoneDigits.isEmpty && !isSaving
    }

    /// NewContactScreen.complete: addContact for a person found, otherwise importContacts.
    @objc private func donePressed() {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = phoneDigits
        guard !first.isEmpty, !digits.isEmpty, !isSaving, contextIsCurrent else { return }
        view.endEditing(true)
        isSaving = true
        updateDoneButton()
        let client = client
        let contact = ImportedContact(
            firstName: first,
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            note: FormattedText(entities: [], text: ""),
            phoneNumber: "+" + digits,
        )
        let foundUserID: Int64? =
            if case .found(let userID, _, _) = lookup {
                userID
            } else {
                nil
            }
        let sharesPhoneNumber = sharesPhoneNumber
        saveTask = Task { [weak self] in
            do {
                var userID = foundUserID
                if let foundUserID {
                    _ = try await client.addContact(
                        contact: contact,
                        sharePhoneNumber: sharesPhoneNumber,
                        userId: foundUserID,
                    )
                } else {
                    let imported = try await client.send(TDNativeRequests.importContacts(contacts: [contact]))
                    userID = imported.userIds.first { $0 != 0 }
                }
                guard let self else { return }
                saveTask = nil
                guard contextIsCurrent else { return }
                guard let userID else {
                    // Telegram keeps a number that isn't on Telegram as a contact and closes the screen.
                    navigationController?.popViewController(animated: true)
                    return
                }
                let opened = await ComposeContacts.openPrivateChat(userID: userID, client: client) {
                    self.contextIsCurrent
                }
                if !opened { navigationController?.popViewController(animated: true) }
            } catch {
                guard let self else { return }
                saveTask = nil
                isSaving = false
                updateDoneButton()
                if contextIsCurrent { presentAlert(title: nil, message: L10n.telegram("Login.UnknownError")) }
            }
        }
    }
}
