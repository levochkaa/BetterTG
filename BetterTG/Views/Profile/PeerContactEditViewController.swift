// PeerContactEditViewController.swift

import PhotosUI
import TDLibKit
import UIKit

// MARK: - PeerContactEditViewController

/// PeerInfoScreen's edit mode for a contact: the first and last name the account keeps for them, the notes only it
/// sees (Add Notes, "Notes are only visible to you."), Suggest Date of Birth and Suggest Photo (not for one who asks
/// for paid messages), Set Photo for them that only the account sees and its reset, and Delete Contact behind its
/// sheet. Done saves the name and notes as the contact (addContact with the importedContact's note), then returns.
final class PeerContactEditViewController: SettingsListViewController, PHPickerViewControllerDelegate {
    private enum PhotoPurpose {
        case suggest
        case personal
    }

    var onDeleted: (() -> Void)?

    private let user: User
    private var firstName: String
    private var lastName: String
    private var note = ""
    private var savedNote = ""
    private var isSaving = false
    private var hasBirthdate = true
    private var photoPurpose = PhotoPurpose.personal

    private var compactName: String {
        user.firstName.isEmpty ? user.lastName : user.firstName
    }

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
            hasBirthdate = info?.birthdate != nil
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
            photoSection(),
            SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("UserInfo.DeleteContact"),
                style: .action(destructive: true),
            ) { [weak self] in self?.confirmDelete() }]),
        ]
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            let image = object as? UIImage
            DispatchQueue.main.async {
                guard let image else { return }
                self?.confirmPhoto(image)
            }
        }
    }

    /// peerDataSettings: the suggestions and the photo only the account sees, with its note.
    private func photoSection() -> SettingsSection {
        var rows = [SettingsRow]()
        let suggests = user.paidMessageStarCount == 0
        if suggests, !hasBirthdate {
            rows.append(SettingsRow(
                title: L10n.telegram("UserInfo.SuggestBirthdate"),
                style: .action(destructive: false),
                symbol: "gift",
            ) { [weak self] in self?.suggestBirthdate() })
        }
        if suggests {
            rows.append(SettingsRow(
                title: L10n.telegram("UserInfo.SuggestPhoto", compactName),
                style: .action(destructive: false),
                symbol: "person.crop.circle.badge.plus",
            ) { [weak self] in self?.pickPhoto(.suggest) })
        }
        let isPersonal = user.profilePhoto?.isPersonal == true
        rows.append(SettingsRow(
            title: L10n.telegram(isPersonal ? "UserInfo.ChangeCustomPhoto" : "UserInfo.SetCustomPhoto", compactName),
            style: .action(destructive: false),
            symbol: "camera",
        ) { [weak self] in self?.pickPhoto(.personal) })
        if isPersonal {
            rows.append(SettingsRow(
                title: L10n.telegram("UserInfo.ResetCustomPhoto"),
                style: .action(destructive: false),
                symbol: "arrow.uturn.backward",
            ) { [weak self] in self?.confirmResetPhoto() })
        }
        return SettingsSection(footer: L10n.telegram("UserInfo.CustomPhotoInfo", compactName), rows: rows)
    }

    /// The birthday's picker titled with their name; Suggest sends it (suggestUserBirthdate).
    private func suggestBirthdate() {
        let userID = user.id
        let picker = BirthdayPickerViewController(birthdate: nil) { [weak self] birthdate in
            self?.perform { client in
                _ = try await client.send(TDNativeRequests.suggestUserBirthdate(userId: userID, birthdate: birthdate))
            } completion: {}
        }
        picker.loadViewIfNeeded()
        picker.title = L10n.telegram("SuggestBirthdate.Suggest.Title", compactName)
        let navigation = UINavigationController(rootViewController: picker)
        navigation.sheetPresentationController?.detents = [.medium()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        present(navigation, animated: true)
    }

    private func pickPhoto(_ purpose: PhotoPurpose) {
        photoPurpose = purpose
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    /// The suggestion's or the custom photo's question, then the photo goes up.
    private func confirmPhoto(_ image: UIImage) {
        let purpose = photoPurpose
        let (text, actionTitle) =
            switch purpose {
            case .suggest:
                (
                    L10n.telegram("UserInfo.SuggestPhoto.AlertPhotoText", compactName),
                    L10n.telegram("UserInfo.SuggestPhoto.AlertSuggest"),
                )
            case .personal:
                (
                    L10n.telegram("UserInfo.SetCustomPhoto.AlertPhotoText", compactName, compactName),
                    L10n.telegram("UserInfo.SetCustomPhoto.AlertSet"),
                )
            }
        confirm(message: text, actionTitle: actionTitle, isDestructive: false) { [weak self] in
            self?.upload(image, purpose: purpose)
        }
    }

    private func upload(_ image: UIImage, purpose: PhotoPurpose) {
        guard let data = EditProfileViewController.squareJPEG(image) else { return }
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bettertg-contact-photo-\(UUID().uuidString).jpg")
        guard (try? data.write(to: url)) != nil else { return }
        let userID = user.id
        let name = compactName
        perform { client in
            defer { try? FileManager.default.removeItem(at: url) }
            let photo = TDNativeInputChatPhoto.inputChatPhotoStatic(TDNativeInputChatPhotoStatic(
                photo: .inputFileLocal(InputFileLocal(path: url.path)),
            ))
            _ =
                switch purpose {
                case .suggest:
                    try await client.send(TDNativeRequests.suggestUserProfilePhoto(userId: userID, photo: photo))
                case .personal:
                    try await client.send(TDNativeRequests.setUserPersonalProfilePhoto(userId: userID, photo: photo))
                }
        } completion: { [weak self] in
            guard purpose == .personal else { return }
            self?.showToast(L10n.telegram("UserInfo.SetCustomPhoto.SuccessPhotoText", name).withoutTelegramMarkup)
        }
    }

    private func confirmResetPhoto() {
        let userID = user.id
        confirm(
            message: L10n.telegram("UserInfo.ResetToOriginalAlertText", compactName),
            actionTitle: L10n.telegram("UserInfo.ResetToOriginalAlertReset"),
        ) { [weak self] in
            self?.perform { client in
                _ = try await client.send(TDNativeRequests.setUserPersonalProfilePhoto(userId: userID, photo: nil))
            } completion: {}
        }
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
