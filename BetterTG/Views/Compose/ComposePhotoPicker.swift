// ComposePhotoPicker.swift

import PhotosUI
import TDLibKit
import UIKit

// MARK: - ComposePhotoHeaderView

/// The photo of Telegram's create screens (ItemListAvatarAndNameInfoItem with a pending avatar): the picked photo or
/// a camera placeholder, with Set Group Photo or Set Channel Photo. An existing chat's photo shows the same way.
final class ComposePhotoHeaderView: UIView {
    static let height: CGFloat = 150

    var onSetPhoto: ((UIView) -> Void)?

    private let avatarView = ProfileAvatarView()
    private let photoView = UIImageView()
    private let placeholderView = UIImageView(image: UIImage(systemName: "camera.fill"))
    private let setPhotoButton = UIButton(type: .system)

    init(buttonTitle: String) {
        super.init(frame: .zero)
        for subview in [avatarView, photoView, setPhotoButton] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        avatarView.isUserInteractionEnabled = false
        avatarView.isHidden = true
        photoView.backgroundColor = .systemBlue.withAlphaComponent(0.15)
        photoView.contentMode = .scaleAspectFill
        photoView.layer.cornerRadius = 40
        photoView.clipsToBounds = true
        photoView.isUserInteractionEnabled = true
        photoView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(setPhotoPressed)))
        photoView.isAccessibilityElement = true
        photoView.accessibilityTraits = .button
        photoView.accessibilityLabel = buttonTitle
        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.tintColor = .systemBlue
        placeholderView.contentMode = .scaleAspectFit
        photoView.addSubview(placeholderView)
        setPhotoButton.setTitle(buttonTitle, for: .normal)
        setPhotoButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        setPhotoButton.addTarget(self, action: #selector(setPhotoPressed), for: .touchUpInside)
        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: photoView.topAnchor),
            avatarView.leadingAnchor.constraint(equalTo: photoView.leadingAnchor),
            avatarView.widthAnchor.constraint(equalTo: photoView.widthAnchor),
            avatarView.heightAnchor.constraint(equalTo: photoView.heightAnchor),
            photoView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            photoView.centerXAnchor.constraint(equalTo: centerXAnchor),
            photoView.widthAnchor.constraint(equalToConstant: 80),
            photoView.heightAnchor.constraint(equalToConstant: 80),
            placeholderView.centerXAnchor.constraint(equalTo: photoView.centerXAnchor),
            placeholderView.centerYAnchor.constraint(equalTo: photoView.centerYAnchor),
            placeholderView.widthAnchor.constraint(equalToConstant: 32),
            placeholderView.heightAnchor.constraint(equalToConstant: 32),
            setPhotoButton.topAnchor.constraint(equalTo: photoView.bottomAnchor, constant: 8),
            setPhotoButton.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPhoto(_ image: UIImage?) {
        photoView.image = image
        placeholderView.isHidden = image != nil || !avatarView.isHidden
        photoView.backgroundColor = avatarView.isHidden || image != nil
            ? .systemBlue.withAlphaComponent(0.15)
            : .clear
    }

    /// The chat's current photo, or its letters, under a newly picked one.
    func setCurrentPhoto(_ peer: SettingsPeer?, client: TDLibClient, accountID: UUID?) {
        avatarView.isHidden = peer == nil
        if let peer {
            avatarView.configure(
                file: peer.file,
                minithumbnail: peer.minithumbnail,
                placeholder: peer.placeholder,
                accountID: accountID,
                accountUserID: 0,
                client: client,
            )
        }
        setPhoto(photoView.image)
    }

    func setEnabled(_ enabled: Bool) {
        setPhotoButton.isEnabled = enabled
        photoView.isUserInteractionEnabled = enabled
    }

    @objc private func setPhotoPressed() {
        onSetPhoto?(setPhotoButton)
    }
}

// MARK: - ComposePhotoPicker

/// The photo menu of Telegram's create screens (Take Photo, Choose Photo, Delete Photo). The picked photo waits for
/// the new chat, as Telegram's CreatePendingPeerAvatar, and is set on it once the chat exists.
@MainActor final class ComposePhotoPicker: NSObject, PHPickerViewControllerDelegate,
UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    weak var host: UIViewController?
    /// Receives the picked photo, or nil after Delete Photo.
    var onChange: ((UIImage?) -> Void)?

    init(host: UIViewController) {
        self.host = host
        super.init()
    }

    /// setChatPhoto with the square photo as `inputChatPhotoStatic`; false when TDLib refused it.
    static func upload(_ image: UIImage, chatID: Int64, client: TDLibClient) async -> Bool {
        guard let data = squareJPEG(image) else { return false }
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bettertg-chat-photo-\(UUID().uuidString).jpg")
        guard (try? data.write(to: url)) != nil else { return false }
        let photo = TDNativeInputChatPhoto.inputChatPhotoStatic(TDNativeInputChatPhotoStatic(
            photo: .inputFileLocal(InputFileLocal(path: url.path)),
        ))
        let succeeded = await (try? client.send(TDNativeRequests.setChatPhoto(chatId: chatID, photo: photo))) != nil
        try? FileManager.default.removeItem(at: url)
        return succeeded
    }

    /// Telegram crops a new chat photo to a square; this takes the centre.
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

    func presentMenu(from source: UIView, hasPhoto: Bool) {
        guard let host else { return }
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
        if hasPhoto {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("GroupInfo.SetGroupPhotoDelete"),
                image: UIImage(systemName: "trash"),
                isDestructive: true,
                startsNewSection: true,
            ) { [weak self] in self?.onChange?(nil) })
        }
        host.view.endEditing(true)
        host.presentTelegramContextMenu(sourceView: source, actions: actions, presentationStyle: .menuOnly)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            let image = object as? UIImage
            DispatchQueue.main.async {
                guard let image else { return }
                self?.onChange?(image)
            }
        }
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any],
    ) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { return }
        onChange?(image)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    private func presentLibrary() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        host?.present(picker, animated: true)
    }

    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            let alert = UIAlertController(
                title: L10n.betterTG("Chat.CameraUnavailable"),
                message: nil,
                preferredStyle: .alert,
            )
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
            host?.present(alert, animated: true)
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = self
        host?.present(picker, animated: true)
    }
}
