// StoryComposer.swift

import PhotosUI
import TDLibKit
import UIKit

// MARK: - StoryComposer

/// ChatListController.openStoryCamera for the account's first story, from what BetterTG has: a photo from the library
/// (Telegram opens its camera with the gallery under it), its MediaEditorScreen preview on a 9:16 canvas with the
/// caption, then ShareWithPeersScreen's Share Story. Telegram's camera, video stories and the editor's drawing,
/// text, stickers and areas aren't ported.
@MainActor final class StoryComposer: NSObject, PHPickerViewControllerDelegate {
    private static var current: StoryComposer?

    private weak var host: UIViewController?
    private let client: TDLibClient
    private let accountID: UUID?

    private init(host: UIViewController, client: TDLibClient, accountID: UUID?) {
        self.host = host
        self.client = client
        self.accountID = accountID
    }

    static func start(from host: UIViewController, client: TDLibClient, accountID: UUID?) {
        let composer = StoryComposer(host: host, client: client, accountID: accountID)
        current = composer
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = composer
        host.present(picker, animated: true)
    }

    /// MediaEditor's 1080 by 1920 canvas: the photo fitted in the middle over MediaEditor's gradient from the
    /// photo's top and bottom colours.
    static func canvas(_ image: UIImage) -> UIImage {
        let size = CGSize(width: 1080, height: 1920)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let (top, bottom) = edgeColors(image)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [
                0,
                1,
            ]) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: 0, y: size.height),
                    options: [],
                )
            }
            image.draw(in: aspectRect(image.size, in: size, filling: false))
        }
    }

    /// The photo's mean colours of its top and bottom halves, read from a 1 by 2 RGBA buffer.
    private static func edgeColors(_ image: UIImage) -> (UIColor, UIColor) {
        guard let cgImage = image.cgImage else { return (.black, .black) }
        var pixels = [UInt8](repeating: 0, count: 8)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 2))
            return true
        }
        guard drawn else { return (.black, .black) }
        // The buffer's first row is the image's top.
        let color: (Int) -> UIColor = { offset in
            UIColor(
                red: CGFloat(pixels[offset]) / 255,
                green: CGFloat(pixels[offset + 1]) / 255,
                blue: CGFloat(pixels[offset + 2]) / 255,
                alpha: 1,
            )
        }
        return (color(0), color(4))
    }

    private static func aspectRect(_ imageSize: CGSize, in size: CGSize, filling: Bool) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGRect(origin: .zero, size: size) }
        let scale = filling
            ? max(size.width / imageSize.width, size.height / imageSize.height)
            : min(size.width / imageSize.width, size.height / imageSize.height)
        let scaled = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (size.width - scaled.width) / 2,
            y: (size.height - scaled.height) / 2,
            width: scaled.width,
            height: scaled.height,
        )
    }

    nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        let provider = results.first?.itemProvider
        Task { @MainActor in
            picker.dismiss(animated: true)
            guard let provider, provider.canLoadObject(ofClass: UIImage.self) else {
                Self.current = nil
                return
            }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                let image = object as? UIImage
                Task { @MainActor in
                    guard let image else {
                        Self.current = nil
                        return
                    }
                    self.openPreview(image)
                }
            }
        }
    }

    private func openPreview(_ image: UIImage) {
        guard let host else {
            Self.current = nil
            return
        }
        let preview = StoryPreviewViewController(image: Self.canvas(image), client: client, accountID: accountID)
        let navigation = TelegramNavigationController(rootViewController: preview)
        navigation.modalPresentationStyle = .fullScreen
        host.present(navigation, animated: true)
        Self.current = nil
    }
}

// MARK: - StoryPreviewViewController

/// MediaEditorScreen's preview: the story on black with 12 pt corners, Close and Next in the bar, and the caption
/// field over the story's bottom (Add a caption...); Next goes on to Share Story.
private final class StoryPreviewViewController: UIViewController, UITextViewDelegate {
    private let image: UIImage
    private let client: TDLibClient
    private let accountID: UUID?
    private let imageView = UIImageView()
    private let captionView = UITextView()
    private let placeholder = UILabel()
    /// MediaEditorScreen's timeout button: the hours the story stays, 24 unless Premium picks 6, 12 or 48.
    private let timerButton = UIButton(type: .system)
    private var hours = 24
    private var isPremium = false

    init(image: UIImage, client: TDLibClient, accountID: UUID?) {
        self.image = image
        self.client = client
        self.accountID = accountID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Close"),
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) },
        )
        imageView.image = image
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.layer.cornerCurve = .continuous
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)

        captionView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        captionView.layer.cornerRadius = 18
        captionView.font = .systemFont(ofSize: 17)
        captionView.textColor = .white
        captionView.textContainerInset = UIEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        captionView.isScrollEnabled = false
        captionView.delegate = self
        captionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captionView)
        placeholder.text = L10n.telegram("Story.Editor.InputPlaceholderAddCaption")
        placeholder.font = .systemFont(ofSize: 17)
        placeholder.textColor = UIColor.white.withAlphaComponent(0.6)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        captionView.addSubview(placeholder)
        timerButton.tintColor = .white
        timerButton.showsMenuAsPrimaryAction = true
        // Telegram's order from top to bottom, wherever the menu opens.
        timerButton.preferredMenuElementOrder = .fixed
        timerButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(timerButton)
        updateTimer()
        let client = client
        Task { [weak self] in
            let me = try? await client.send(TDNativeRequests.getMe())
            guard let self else { return }
            isPremium = me?.isPremium ?? false
            updateTimer()
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Story.Editor.Next"),
            primaryAction: UIAction { [weak self] _ in self?.next() },
        )

        let guide = view.safeAreaLayoutGuide
        // As tall as the safe area allows, 9:16.
        let imageHeight = imageView.heightAnchor.constraint(equalTo: guide.heightAnchor, constant: -16)
        imageHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            imageView.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualTo: guide.widthAnchor, constant: -16),
            imageView.bottomAnchor.constraint(lessThanOrEqualTo: guide.bottomAnchor, constant: -8),
            imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor, multiplier: 9 / 16),
            imageHeight,
            captionView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 10),
            captionView.trailingAnchor.constraint(equalTo: timerButton.leadingAnchor, constant: -6),
            timerButton.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -8),
            timerButton.centerYAnchor.constraint(equalTo: captionView.centerYAnchor),
            timerButton.widthAnchor.constraint(equalToConstant: 44),
            timerButton.heightAnchor.constraint(equalToConstant: 36),
            captionView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -10),
            captionView.bottomAnchor.constraint(
                lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor,
                constant: -10,
            ),
            captionView.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            placeholder.leadingAnchor.constraint(equalTo: captionView.leadingAnchor, constant: 15),
            placeholder.centerYAnchor.constraint(equalTo: captionView.centerYAnchor),
        ])
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholder.isHidden = !textView.text.isEmpty
    }

    /// presentTimeoutSetup: Choose how long the story will be visible, then 6, 12, 24 and 48 Hours with a check on
    /// the chosen one; without Premium all but 24 carry a lock and explain Premium instead.
    private func updateTimer() {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: "timer",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium),
        )
        configuration.imagePadding = 2
        configuration.title = "\(hours)"
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 12, weight: .semibold)
            return attributes
        }
        configuration.contentInsets = .zero
        timerButton.configuration = configuration
        timerButton.accessibilityLabel = L10n.telegramPlural("Story.Editor.ExpirationValue", count: hours)
        let options = [6, 12, 24, 48].map { value in
            let locked = value != 24 && !isPremium
            return UIAction(
                title: L10n.telegramPlural("Story.Editor.ExpirationValue", count: value),
                image: locked ? UIImage(systemName: "lock.fill") : nil,
                state: value == hours ? .on : .off,
            ) { [weak self] _ in
                guard let self else { return }
                if locked {
                    let alert = UIAlertController(
                        title: nil,
                        message: L10n.telegram("Story.Editor.TooltipPremiumExpiration")
                            .replacing("[", with: "")
                            .replacing("]()", with: ""),
                        preferredStyle: .alert,
                    )
                    alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
                    present(alert, animated: true)
                } else {
                    hours = value
                    updateTimer()
                }
            }
        }
        timerButton.menu = UIMenu(title: L10n.telegram("Story.Editor.ExpirationText"), children: options)
    }

    private func next() {
        captionView.resignFirstResponder()
        let share = StoryShareViewController(image: image, caption: captionView.text ?? "", hours: hours)
        navigationController?.pushViewController(share, animated: true)
    }
}

// MARK: - StoryShareViewController

/// ShareWithPeersScreen for a new story: WHO CAN VIEW THIS STORY (Everyone, Contacts, Close Friends with their list,
/// Selected Contacts once chosen), Allow Screenshots and Keep on My Page with its note, and Post Story, which posts
/// it from Saved Messages for a day (postStory).
private final class StoryShareViewController: SettingsListViewController {
    private enum Audience {
        case everyone
        case contacts
        case closeFriends
        case selected
    }

    private let image: UIImage
    private let caption: String
    private let hours: Int
    private var audience = Audience.everyone
    private var selectedUserIDs = [Int64]()
    /// The people left out under Everyone and Contacts (exceptUserIds).
    private var excludedFromEveryone = [Int64]()
    private var excludedFromContacts = [Int64]()
    /// The account's close friends (getCloseFriends), edited with setCloseFriends.
    private var closeFriendIDs = [Int64]()
    private var firstNames = [Int64: String]()
    private var allowsScreenshots = true
    private var keepsOnPage = true
    private var isPosting = false

    private var privacy: TDNativeStoryPrivacySettings {
        switch audience {
        case .everyone:
            .storyPrivacySettingsEveryone(TDNativeStoryPrivacySettingsEveryone(exceptUserIds: excludedFromEveryone))
        case .contacts:
            .storyPrivacySettingsContacts(TDNativeStoryPrivacySettingsContacts(exceptUserIds: excludedFromContacts))
        case .closeFriends: .storyPrivacySettingsCloseFriends
        case .selected:
            .storyPrivacySettingsSelectedUsers(TDNativeStoryPrivacySettingsSelectedUsers(userIds: selectedUserIDs))
        }
    }

    init(image: UIImage, caption: String, hours: Int) {
        self.image = image
        self.caption = caption
        self.hours = hours
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Story.Privacy.ShareStory")
        let client = client
        Task { [weak self] in
            let users = try? await client.send(TDNativeRequests.getCloseFriends())
            guard let self, contextIsCurrent, let users else { return }
            closeFriendIDs = users.userIds
            reload()
        }
    }

    override func makeSections() -> [SettingsSection] {
        let excluded: ([Int64]) -> String = { ids in
            ids.isEmpty
                ? L10n.telegram("Story.Privacy.ExcludePeople")
                : L10n.telegram("Story.Privacy.ExcludePeopleExceptNames", self.names(ids))
        }
        let audiences: [(Audience, String, String?)] = [
            (.everyone, "Story.Privacy.CategoryEveryone", excluded(excludedFromEveryone)),
            (.contacts, "Story.Privacy.CategoryContacts", excluded(excludedFromContacts)),
            (.closeFriends, "Story.Privacy.CategoryCloseFriends", L10n.telegram("Story.Privacy.EditList")),
            (
                .selected,
                "Story.Privacy.CategorySelectedContacts",
                selectedUserIDs.isEmpty ? L10n.telegram("Story.Privacy.Choose") : names(selectedUserIDs),
            ),
        ]
        return [
            SettingsSection(
                header: L10n.telegram("Story.Privacy.WhoCanViewHeader"),
                rows: audiences.map { audience, key, detail in
                    SettingsRow(
                        title: L10n.telegram(key),
                        detail: detail,
                        style: detail == nil ? .value : .subtitle,
                        accessory: self.audience == audience ? .checkmark : .none,
                        isEnabled: !isPosting,
                    ) { [weak self] in self?.choose(audience) }
                },
            ),
            SettingsSection(
                footer: L10n.telegram(
                    "Story.Privacy.KeepOnMyPageInfo",
                    L10n.telegramPlural("Story.Privacy.KeepOnMyPageHours", count: hours),
                ),
                rows: [
                    SettingsRow(
                        title: L10n.telegram("Story.Privacy.AllowScreenshots"),
                        accessory: .toggle(isOn: allowsScreenshots) { [weak self] value in
                            self?.allowsScreenshots = value
                        },
                    ),
                    SettingsRow(
                        title: L10n.telegram("Story.Privacy.KeepOnMyPage"),
                        accessory: .toggle(isOn: keepsOnPage) { [weak self] value in self?.keepsOnPage = value },
                    ),
                ],
            ),
            SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("Story.Privacy.PostStory"),
                style: .action(destructive: false),
                accessory: isPosting ? .activity : .none,
                isEnabled: !isPosting,
            ) { [weak self] in self?.post() }]),
        ]
    }

    /// ShareWithPeersScreen's category subtitles: exclude people or except the names, edit list, choose or the names.
    private func names(_ ids: [Int64]) -> String {
        ids.compactMap { firstNames[$0] }.joined(separator: ", ")
    }

    /// A tap chooses the category; on the chosen one it opens its list (Telegram's subtitle link): the people to
    /// leave out, the close friends or the selected contacts. Selected Contacts opens it at once while empty.
    private func choose(_ audience: Audience) {
        guard self.audience == audience || audience == .selected && selectedUserIDs.isEmpty else {
            self.audience = audience
            reload()
            return
        }
        let current: [Int64]
        let title: String
        switch audience {
        case .contacts,
             .everyone:
            current = audience == .everyone ? excludedFromEveryone : excludedFromContacts
            title = L10n.telegram("Story.Privacy.ExcludedPeople")
        case .closeFriends:
            current = closeFriendIDs
            title = L10n.telegram("Story.Privacy.CategoryCloseFriends")
        case .selected:
            current = selectedUserIDs
            title = L10n.telegram("Story.Privacy.CategorySelectedContacts")
        }
        let picker = SettingsPeerPickerViewController(excludedUserIDs: [], excludedChatIDs: [])
        picker.listsOnlyPeople = true
        picker.pickerTitle = title
        picker.initiallySelectedUserIDs = current
        picker.allowsEmptySelection = audience != .selected
        picker.onDone = { [weak self] userIDs, _ in self?.applyList(userIDs, to: audience) }
        present(TelegramNavigationController(rootViewController: picker), animated: true)
    }

    private func applyList(_ userIDs: [Int64], to audience: Audience) {
        switch audience {
        case .everyone: excludedFromEveryone = userIDs
        case .contacts: excludedFromContacts = userIDs
        case .closeFriends:
            // setCloseFriends: the list belongs to the account, not to this story.
            closeFriendIDs = userIDs
            let client = client
            Task { _ = try? await client.send(TDNativeRequests.setCloseFriends(userIds: userIDs)) }
        case .selected:
            selectedUserIDs = userIDs
            if !userIDs.isEmpty { self.audience = .selected }
        }
        reload()
        loadNames(userIDs)
    }

    private func loadNames(_ ids: [Int64]) {
        let missing = ids.filter { firstNames[$0] == nil }
        guard !missing.isEmpty else { return }
        let client = client
        Task { [weak self] in
            var found = [Int64: String]()
            for id in missing {
                guard let user = try? await client.getUser(userId: id) else { continue }
                found[id] = user.firstName.isEmpty ? user.lastName : user.firstName
            }
            guard let self, contextIsCurrent else { return }
            firstNames.merge(found) { $1 }
            reload()
        }
    }

    /// The canvas as a JPEG for postStory from the account's Saved Messages, active for a day.
    private func post() {
        guard !isPosting, contextIsCurrent, let ownID = TDLib.shared.activeAccount?.userID,
              let data = image.jpegData(compressionQuality: 0.9)
        else { return }
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bettertg-story-\(UUID().uuidString).jpg")
        guard (try? data.write(to: url)) != nil else { return }
        isPosting = true
        reload()
        let client = client
        let privacy = privacy
        let caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let keepsOnPage = keepsOnPage
        let allowsScreenshots = allowsScreenshots
        let activePeriod = hours * 3600
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.postStory(
                    chatId: ownID,
                    content: .inputStoryContentPhoto(TDNativeInputStoryContentPhoto(
                        photo: .inputFileLocal(InputFileLocal(path: url.path)),
                        addedStickerFileIds: [],
                    )),
                    areas: nil,
                    caption: caption.isEmpty ? nil : FormattedText(entities: [], text: caption),
                    privacySettings: privacy,
                    albumIds: [],
                    activePeriod: activePeriod,
                    fromStoryFullId: nil,
                    isPostedToChatPage: keepsOnPage,
                    protectContent: !allowsScreenshots,
                ))
                guard let self else { return }
                navigationController?.dismiss(animated: true)
            } catch {
                guard let self else { return }
                isPosting = false
                reload()
                if contextIsCurrent { presentAlert(title: nil, message: ChatManagementRows.failureText(error)) }
            }
        }
    }
}
