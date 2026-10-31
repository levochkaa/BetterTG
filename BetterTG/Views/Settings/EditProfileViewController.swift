// EditProfileViewController.swift

import PhotosUI
import TDLibKit
import UIKit

// MARK: - EditProfileViewController

/// Telegram's Edit Profile (PeerInfoScreen editing the account): photo, first and last name, bio with its character
/// limit, date of birth and username. Done saves the name and bio; the photo, birthday and username save from their
/// own actions.
final class EditProfileViewController: SettingsListViewController, PHPickerViewControllerDelegate,
UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private var me: User?
    private var savedBio = ""
    private var birthdate: TDNativeBirthdate?
    private var firstName = ""
    private var lastName = ""
    private var bio = ""
    private var bioLimit = 70
    private var isLoaded = false
    private var isSaving = false
    private var photoTask: Task<Void, Never>?
    private let headerView = EditProfileHeaderView()

    deinit {
        photoTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("EditProfile.Title")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Done"), style: .prominent, target: self, action: #selector(donePressed),
        )
        navigationItem.rightBarButtonItem?.isEnabled = false
        headerView.onSetPhoto = { [weak self] source in self?.presentPhotoMenu(from: source) }
        headerView.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: EditProfileHeaderView.height)
        tableView.tableHeaderView = headerView
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        load()
    }

    override func makeSections() -> [SettingsSection] {
        guard isLoaded else { return [] }
        var sections = [
            SettingsSection(footer: L10n.telegram("EditProfile.NameAndPhotoHelp"), rows: [
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
            SettingsSection(footer: L10n.telegram("Settings.About.PrivacyHelp").withoutTelegramLinks, rows: [
                SettingsRow(title: "", style: .input(SettingsTextInput(
                    text: bio,
                    placeholder: L10n.telegram("UserInfo.About.Placeholder"),
                    maxLength: bioLimit,
                    isMultiline: true,
                ) { [weak self] text in
                    self?.bio = text
                    self?.updateDoneButton()
                })),
            ]),
        ]
        var birthdayRows = [SettingsRow(
            title: L10n.telegram("Settings.Birthday"),
            detail: birthdate.map(Self.birthdateText) ?? L10n.telegram("Settings.Birthday.Add"),
            accessory: .disclosure,
        ) { [weak self] in self?.presentBirthdayPicker() }]
        if birthdate != nil {
            birthdayRows.append(SettingsRow(
                title: L10n.telegram("Settings.Birthday.Remove"),
                style: .action(destructive: true),
            ) { [weak self] in self?.removeBirthdate() })
        }
        sections.append(SettingsSection(
            footer: L10n.telegram("Settings.Birthday.Help").withoutTelegramLinks,
            rows: birthdayRows,
        ))
        let username = me?.usernames?.editableUsername ?? ""
        sections.append(SettingsSection(rows: [SettingsRow(
            title: L10n.telegram("Settings.Username"),
            detail: username.isEmpty ? L10n.telegram("Settings.UsernameEmpty") : "@\(username)",
            accessory: .disclosure,
        ) { [weak self] in
            self?.navigationController?.pushViewController(UsernameSetupViewController(), animated: true)
        }]))
        return sections
    }

    private static func squareJPEG(_ image: UIImage) -> Data? {
        let side = min(image.size.width, image.size.height)
        guard side > 0 else { return nil }
        let target = min(side, 1280)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format)
        let scale = target / side
        let squared = renderer.image { _ in
            image.draw(in: CGRect(
                x: -(image.size.width - side) / 2 * scale,
                y: -(image.size.height - side) / 2 * scale,
                width: image.size.width * scale,
                height: image.size.height * scale,
            ))
        }
        return squared.jpegData(compressionQuality: 0.9)
    }

    private static func birthdayFailureText(_ error: Error) -> String? {
        let message = (error as? TDLibError)?.message ?? ""
        return message.contains("FLOOD") || message.contains("TOO_FREQUENT")
            ? L10n.telegram("Birthday.FloodError")
            : nil
    }

    private static func birthdateText(_ value: TDNativeBirthdate) -> String {
        var components = DateComponents()
        components.day = value.day
        components.month = value.month
        components.year = value.year > 0 ? value.year : 2000
        guard let date = Calendar(identifier: .gregorian).date(from: components) else { return "" }
        return value.year > 0
            ? date.formatted(date: .long, time: .omitted)
            : date.formatted(.dateTime.day().month(.wide))
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            let image = object as? UIImage
            DispatchQueue.main.async {
                guard let image else { return }
                self?.uploadPhoto(image)
            }
        }
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any],
    ) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { return }
        uploadPhoto(image)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    // MARK: Loading

    private func load() {
        guard contextIsCurrent else { return }
        let client = client
        Task { [weak self] in
            guard let me = try? await client.getMe() else { return }
            let fullInfo = try? await client.getUserFullInfo(userId: me.id)
            let limit: Int? =
                if case .optionValueInteger(let value) = try? await client.getOption(name: "bio_length_max") {
                    Int(clamping: value.value)
                } else {
                    nil
                }
            guard let self, contextIsCurrent else { return }
            let wasLoaded = isLoaded
            self.me = me
            savedBio = fullInfo?.bio?.text ?? ""
            birthdate = fullInfo?.birthdate
            if let limit, limit > 0 { bioLimit = limit }
            if !wasLoaded {
                firstName = me.firstName
                lastName = me.lastName
                bio = savedBio
                isLoaded = true
                reload()
            } else {
                // Keep the fields being edited; refresh the photo, birthday and username rows.
                reload(sections: IndexSet([2, 3]))
            }
            headerView.configure(user: me, client: client, accountID: accountID)
            updateDoneButton()
        }
    }

    private func updateDoneButton() {
        guard let me else { return }
        let changed = firstName != me.firstName || lastName != me.lastName || bio != savedBio
        let valid = !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        navigationItem.rightBarButtonItem?.isEnabled = changed && valid && !isSaving
    }

    // MARK: Name and bio

    /// Telegram's Done: the name and the bio that changed, then back to Settings.
    @objc private func donePressed() {
        guard let me, !isSaving, contextIsCurrent else { return }
        view.endEditing(true)
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameChanged = first != me.firstName || last != me.lastName
        let bioText = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let bioChanged = bioText != savedBio
        isSaving = true
        updateDoneButton()
        let client = client
        Task { [weak self] in
            do {
                if nameChanged {
                    _ = try await client.send(TDNativeRequests.setName(firstName: first, lastName: last))
                }
                if bioChanged {
                    _ = try await client.send(TDNativeRequests.setBio(bio: bioText))
                }
                guard let self, contextIsCurrent else { return }
                navigationController?.popViewController(animated: true)
            } catch {
                // A failure leaves the screen open for another try.
                guard let self else { return }
                isSaving = false
                updateDoneButton()
                if contextIsCurrent { presentChatListActionFailure() }
            }
        }
    }

    // MARK: Photo

    private func presentPhotoMenu(from source: UIView) {
        guard contextIsCurrent, photoTask == nil else { return }
        var actions = [
            TelegramContextMenuAction(
                title: L10n.telegram("Common.TakePhoto"),
                image: UIImage(systemName: "camera"),
            ) { [weak self] in self?.presentCamera() },
            TelegramContextMenuAction(
                title: L10n.telegram("Common.ChoosePhoto"),
                image: UIImage(systemName: "photo.on.rectangle"),
            ) { [weak self] in self?.presentLibrary() },
        ]
        if let photo = me?.profilePhoto {
            let photoID = photo.id
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("GroupInfo.SetGroupPhotoDelete"),
                image: UIImage(systemName: "trash"),
                isDestructive: true,
                startsNewSection: true,
            ) { [weak self] in self?.confirmPhotoDeletion(photoID: photoID) })
        }
        presentTelegramContextMenu(sourceView: source, actions: actions, presentationStyle: .menuOnly)
    }

    private func presentLibrary() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            presentAlert(title: L10n.betterTG("Chat.CameraUnavailable"), message: nil)
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = self
        present(picker, animated: true)
    }

    /// Telegram crops a new profile photo to a square; this takes the centre and uploads it as
    /// `inputChatPhotoStatic`.
    private func uploadPhoto(_ image: UIImage) {
        guard contextIsCurrent, photoTask == nil, let data = Self.squareJPEG(image) else { return }
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bettertg-profile-photo-\(UUID().uuidString).jpg")
        guard (try? data.write(to: url)) != nil else { return }
        let client = client
        headerView.setUploading(true)
        photoTask = Task { [weak self] in
            let photo = TDNativeInputChatPhoto.inputChatPhotoStatic(TDNativeInputChatPhotoStatic(
                photo: .inputFileLocal(InputFileLocal(path: url.path)),
            ))
            let succeeded = await (try? client.send(TDNativeRequests.setProfilePhoto(photo: photo, isPublic: false)))
                != nil
            try? FileManager.default.removeItem(at: url)
            guard let self else { return }
            photoTask = nil
            headerView.setUploading(false)
            guard contextIsCurrent else { return }
            if succeeded {
                load()
            } else {
                presentChatListActionFailure()
            }
        }
    }

    private func confirmPhotoDeletion(photoID: Int64) {
        confirm(message: nil, actionTitle: L10n.telegram("GroupInfo.SetGroupPhotoDelete")) { [weak self] in
            self?.perform { client in
                _ = try await client.send(TDNativeRequests.deleteProfilePhoto(profilePhotoId: photoID))
            } completion: { [weak self] in
                self?.load()
            }
        }
    }

    // MARK: Birthday

    private func presentBirthdayPicker() {
        guard contextIsCurrent, presentedViewController == nil else { return }
        let picker = BirthdayPickerViewController(birthdate: birthdate) { [weak self] birthdate in
            self?.saveBirthdate(birthdate)
        }
        let navigation = UINavigationController(rootViewController: picker)
        navigation.sheetPresentationController?.detents = [.medium()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        present(navigation, animated: true)
    }

    private func saveBirthdate(_ value: TDNativeBirthdate) {
        perform(failureText: Self.birthdayFailureText) { client in
            _ = try await client.send(TDNativeRequests.setBirthdate(birthdate: value))
        } completion: { [weak self] in
            self?.showToast(L10n.telegram("Birthday.Added"))
            self?.load()
        }
    }

    private func removeBirthdate() {
        confirm(message: nil, actionTitle: L10n.telegram("Settings.Birthday.Remove")) { [weak self] in
            self?.perform(failureText: Self.birthdayFailureText) { client in
                _ = try await client.send(TDNativeRequests.setBirthdate(birthdate: nil))
            } completion: { [weak self] in
                self?.load()
            }
        }
    }
}

// MARK: - EditProfileHeaderView

/// The photo above Telegram's Edit Profile fields, with its Set Photo button.
private final class EditProfileHeaderView: UIView {
    static let height: CGFloat = 170

    var onSetPhoto: ((UIView) -> Void)?

    private let avatarView = ProfileAvatarView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let setPhotoButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        for subview in [avatarView, activityIndicator, setPhotoButton] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        avatarView.isUserInteractionEnabled = false
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = .white
        setPhotoButton.setTitle(L10n.telegram("Settings.SetProfilePhoto"), for: .normal)
        setPhotoButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        setPhotoButton.addTarget(self, action: #selector(setPhotoPressed), for: .touchUpInside)
        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            avatarView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 100),
            avatarView.heightAnchor.constraint(equalToConstant: 100),
            activityIndicator.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            setPhotoButton.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 8),
            setPhotoButton.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(user: User, client: TDLibClient, accountID: UUID?) {
        avatarView.configure(
            file: user.profilePhoto?.small,
            largeFile: user.profilePhoto?.big,
            minithumbnail: user.profilePhoto?.minithumbnail,
            placeholder: user.telegramAvatarPlaceholder,
            accountID: accountID,
            accountUserID: 0,
            client: client,
        )
    }

    func setUploading(_ uploading: Bool) {
        setPhotoButton.isEnabled = !uploading
        avatarView.alpha = uploading ? 0.5 : 1
        if uploading { activityIndicator.startAnimating() } else { activityIndicator.stopAnimating() }
    }

    @objc private func setPhotoPressed() {
        onSetPhoto?(setPhotoButton)
    }
}

// MARK: - BirthdayPickerViewController

/// Telegram's BirthdayPickerScreen: a date picker with Save.
private final class BirthdayPickerViewController: UIViewController {
    private let datePicker = UIDatePicker()
    private let initial: TDNativeBirthdate?
    private let onSave: (TDNativeBirthdate) -> Void

    init(birthdate: TDNativeBirthdate?, onSave: @escaping (TDNativeBirthdate) -> Void) {
        self.initial = birthdate
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = L10n.telegram("Birthday.Title")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"), style: .plain, target: self, action: #selector(cancelPressed),
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Birthday.Save"), style: .prominent, target: self, action: #selector(savePressed),
        )
        datePicker.translatesAutoresizingMaskIntoConstraints = false
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .wheels
        datePicker.maximumDate = Date()
        if let initial, initial.year > 0 {
            var components = DateComponents()
            components.day = initial.day
            components.month = initial.month
            components.year = initial.year
            if let date = Calendar.current.date(from: components) { datePicker.date = date }
        }
        view.addSubview(datePicker)
        NSLayoutConstraint.activate([
            datePicker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            datePicker.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            datePicker.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])
    }

    @objc private func cancelPressed() {
        dismiss(animated: true)
    }

    @objc private func savePressed() {
        let components = Calendar.current.dateComponents([.day, .month, .year], from: datePicker.date)
        let birthdate = TDNativeBirthdate(
            day: components.day ?? 1,
            month: components.month ?? 1,
            year: components.year ?? 0,
        )
        let onSave = onSave
        dismiss(animated: true) { onSave(birthdate) }
    }
}
