// PeerContactEditViewController.swift

import TDLibKit
import UIKit

// MARK: - PeerContactEditViewController

/// PeerInfoScreen's edit mode for a contact: the first and last name the account keeps for them, the notes only it
/// sees (Add Notes, "Notes are only visible to you."), and Delete Contact behind its sheet. Done saves the name and
/// notes as the contact (addContact with the importedContact's note), then returns.
final class PeerContactEditViewController: SettingsListViewController {
    var onDeleted: (() -> Void)?

    private let user: User
    private var firstName: String
    private var lastName: String
    private var note = ""
    private var savedNote = ""
    private var isSaving = false

    init(user: User) {
        self.user = user
        self.firstName = user.firstName
        self.lastName = user.lastName
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Common.Edit")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Done"), style: .prominent, target: self, action: #selector(donePressed),
        )
        updateDoneButton()
        let client = client
        let userID = user.id
        Task { [weak self] in
            let info = try? await client.getUserFullInfo(userId: userID)
            guard let self, contextIsCurrent else { return }
            savedNote = info?.note?.text ?? ""
            note = savedNote
            reload()
        }
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
                ) { [weak self] text in
                    self?.lastName = text
                    self?.updateDoneButton()
                })),
            ]),
            SettingsSection(footer: L10n.telegram("PeerInfo.AddNotesInfo"), rows: [
                SettingsRow(title: "", style: .input(SettingsTextInput(
                    text: note,
                    placeholder: L10n.telegram("PeerInfo.AddNotesPlaceholder"),
                    isMultiline: true,
                ) { [weak self] text in
                    self?.note = text
                    self?.updateDoneButton()
                })),
            ]),
            SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("UserInfo.DeleteContact"),
                style: .action(destructive: true),
            ) { [weak self] in self?.confirmDelete() }]),
        ]
    }

    private func updateDoneButton() {
        let changed = firstName != user.firstName || lastName != user.lastName || note != savedNote
        let valid = !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        navigationItem.rightBarButtonItem?.isEnabled = changed && valid && !isSaving
    }

    @objc private func donePressed() {
        guard !isSaving else { return }
        view.endEditing(true)
        isSaving = true
        updateDoneButton()
        let contact = TDNativeImportedContact(
            phoneNumber: user.phoneNumber,
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            note: FormattedText(entities: [], text: note.trimmingCharacters(in: .whitespacesAndNewlines)),
        )
        let userID = user.id
        perform(failureText: { [weak self] _ in
            self?.isSaving = false
            self?.updateDoneButton()
            return nil
        }) { client in
            _ = try await client.send(TDNativeRequests.addContact(
                userId: userID, contact: contact, sharePhoneNumber: false,
            ))
        } completion: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }

    /// requestDeleteContact: the sheet's Delete Contact removes them (removeContacts), then the profile hears it.
    private func confirmDelete() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L10n.telegram("UserInfo.DeleteContact"), style: .destructive) {
            [weak self] _ in
            guard let self else { return }
            let userID = user.id
            perform { client in
                _ = try await client.send(TDNativeRequests.removeContacts(userIds: [userID]))
            } completion: { [weak self] in
                guard let self else { return }
                let onDeleted = onDeleted
                navigationController?.popViewController(animated: true)
                onDeleted?()
            }
        })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        present(sheet, animated: true)
    }
}
