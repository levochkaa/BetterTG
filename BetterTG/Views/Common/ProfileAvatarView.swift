// ProfileAvatarView.swift

import Combine
import CoreText
import TDLibKit
import UIKit

// MARK: - ProfileAvatarView

final class ProfileAvatarView: TelegramContextMenuExtractableView {
    var onOpenProfile: (() -> Void)?
    var onSearch: (() -> Void)?

    // MARK: Private

    private let placeholderView = TelegramAvatarPlaceholderView()
    private let imageView = TDImageLoadingView()

    private var highResolutionTask: Task<Void, Never>?
    private var highResolutionFile: File?
    private var sourceFile: File?
    private var sourceMinithumbnailData: Data?
    private var sourceUsesPeerPhotoForSavedMessages = false
    private var sourceOrigin: TDImageOrigin?
    /// The client that produced `sourceOrigin`; profile and chat lookups from the avatar menu use it.
    private var sourceClient: TDLibClient?
    private var sourceAccountUserID: Int64?
    private var placeholder: TelegramAvatarPlaceholder?
    private var representedAccountID: UUID?
    private var representedClientID: Int32?
    private var representedPeerID: Int64?
    private var representedFile: File?
    private var representedMinithumbnailData: Data?
    private var representedIcon: TelegramAvatarIcon?
    private var cancellables = Set<AnyCancellable>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        extractedContentView.clipsToBounds = true
        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.isUserInteractionEnabled = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        extractedContentView.addSubview(placeholderView)
        extractedContentView.addSubview(imageView)
        isUserInteractionEnabled = true

        addGestureRecognizer(ContextMenuPressGestureRecognizer(target: self, action: #selector(longPressed(_:))))

        NSLayoutConstraint.activate([
            placeholderView.topAnchor.constraint(equalTo: extractedContentView.topAnchor),
            placeholderView.leadingAnchor.constraint(equalTo: extractedContentView.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: extractedContentView.trailingAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: extractedContentView.bottomAnchor),
            imageView.topAnchor.constraint(equalTo: extractedContentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: extractedContentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: extractedContentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: extractedContentView.bottomAnchor),
        ])

        nc.publisher(&cancellables, for: .telegramAvatarColorsChanged) { [weak self] _ in
            self?.updatePlaceholder()
        }
        nc.mergeMany(&cancellables, [.telegramAccountsChanged, .activeTelegramAccountChanged]) { [weak self] _ in
            self?.updatePlaceholder()
            self?.updateImageIfNeeded()
        }
        TDLib.shared
            .activeClientChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateImageIfNeeded()
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func layoutSubviews() {
        super.layoutSubviews()
        guard extractedContentView.superview === self else { return }
        extractedContentView.layer.cornerRadius = bounds.width / 2
    }

    func configure(
        file: File?,
        largeFile: File? = nil,
        minithumbnail: Minithumbnail?,
        placeholder: TelegramAvatarPlaceholder,
        usesPeerPhotoForSavedMessages: Bool = false,
        accountID: UUID? = nil,
        accountUserID: Int64? = nil,
        client: TDLibClient,
    ) {
        if self.placeholder?.peerID != placeholder.peerID || sourceFile?.id != file?.id {
            highResolutionTask?.cancel()
        }
        highResolutionFile = largeFile
        sourceFile = file
        sourceMinithumbnailData = minithumbnail?.data
        sourceUsesPeerPhotoForSavedMessages = usesPeerPhotoForSavedMessages
        sourceOrigin = .captured(client: client, accountID: accountID)
        sourceClient = client
        sourceAccountUserID = accountUserID ?? (sourceOrigin?.isCurrent == true
            ? TDLib.shared.activeAccount?.userID
            : nil)
        self.placeholder = placeholder
        updatePlaceholder()
        updateImageIfNeeded()
    }

    func prepareForReuse() {
        highResolutionTask?.cancel()
        highResolutionTask = nil
        highResolutionFile = nil
        onOpenProfile = nil
        onSearch = nil
        imageView.cancel()
        sourceFile = nil
        sourceMinithumbnailData = nil
        sourceUsesPeerPhotoForSavedMessages = false
        sourceOrigin = nil
        sourceClient = nil
        sourceAccountUserID = nil
        placeholder = nil
        representedAccountID = nil
        representedClientID = nil
        representedPeerID = nil
        representedFile = nil
        representedMinithumbnailData = nil
        representedIcon = nil
        imageView.image = nil
        placeholderView.reset()
    }

    // MARK: Private

    private func updatePlaceholder() {
        guard let placeholder else { return }
        let icon = displayedIcon(for: placeholder)
        let colors = AvatarColorPalette.shared.gradient(
            for: placeholder,
            icon: icon,
        )
        placeholderView.configure(colors: colors, letters: placeholder.letters, icon: icon)
    }

    private func updateImageIfNeeded() {
        guard let placeholder else { return }
        guard let sourceOrigin, sourceOrigin.isCurrent else {
            imageView.cancel()
            imageView.image = nil
            representedAccountID = nil
            representedClientID = nil
            representedPeerID = nil
            representedFile = nil
            representedMinithumbnailData = nil
            representedIcon = nil
            return
        }
        let icon = displayedIcon(for: placeholder)
        let file = icon == .none ? sourceFile : nil
        let minithumbnailData = icon == .none ? sourceMinithumbnailData : nil
        let accountID = sourceOrigin.source.accountID
        let clientID = sourceOrigin.source.clientID
        guard representedAccountID != accountID
            || representedClientID != clientID
            || representedPeerID != placeholder.peerID
            || representedFile?.id != file?.id
            || representedMinithumbnailData != minithumbnailData
            || representedIcon != icon
        else { return }

        imageView.cancel()
        imageView.image = nil
        representedAccountID = accountID
        representedClientID = clientID
        representedPeerID = placeholder.peerID
        representedFile = file
        representedMinithumbnailData = minithumbnailData
        representedIcon = icon
        if let file {
            imageView.load(
                file: file,
                placeholderData: minithumbnailData,
                maximumPixelSize: 160,
                origin: sourceOrigin,
            )
        } else {
            imageView.loadPlaceholder(data: minithumbnailData, maximumPixelSize: 160, origin: sourceOrigin)
        }
    }

    private func displayedIcon(for placeholder: TelegramAvatarPlaceholder) -> TelegramAvatarIcon {
        let icon = placeholder.icon(accountUserID: sourceAccountUserID)
        if sourceUsesPeerPhotoForSavedMessages,
           sourceFile != nil,
           icon == .savedMessages
        {
            return .none
        }
        return icon
    }

    @objc private func longPressed(_ gesture: ContextMenuPressGestureRecognizer) {
        guard gesture.state == .began, let hostController = nearestViewController else { return }
        loadHighResolutionPreview()
        hostController.presentTelegramContextMenu(sourceView: self, actions: [
            TelegramContextMenuAction(
                title: L10n.telegram("Conversation.ContextMenuOpenProfile"),
                image: UIImage(systemName: "person.crop.circle"),
            ) { [weak self, weak hostController] in
                guard let self else { return }
                if let onOpenProfile { onOpenProfile() }
                else { openPeer(from: hostController, search: false) }
            },
            TelegramContextMenuAction(
                title: L10n.telegram("PeerInfo.ButtonSearch"),
                image: UIImage(systemName: "magnifyingglass"),
            ) { [weak self, weak hostController] in
                guard let self else { return }
                if let onSearch { onSearch() }
                else { openPeer(from: hostController, search: true) }
            },
            TelegramContextMenuAction(
                title: L10n.telegram("Gallery.SaveImage"),
                image: UIImage(systemName: "square.and.arrow.down"),
            ) { [weak self] in
                guard let image = self?.imageView.image else { return }
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            },
        ], tracking: gesture, presentationStyle: .avatar)
    }

    private func loadHighResolutionPreview() {
        guard let placeholder, displayedIcon(for: placeholder) == .none,
              let origin = sourceOrigin, origin.isCurrent, let client = sourceClient
        else { return }
        let peerID = placeholder.peerID
        let file = highResolutionFile
        highResolutionTask?.cancel()
        highResolutionTask = Task { [weak self] in
            let resolvedFile: File? =
                if let file {
                    file
                } else if peerID > 0 {
                    try? await client.getUser(userId: peerID).profilePhoto?.big
                } else {
                    try? await client.getChat(chatId: peerID).photo?.big
                }
            guard let self, !Task.isCancelled, self.placeholder?.peerID == peerID, origin.isCurrent,
                  let resolvedFile else { return }
            imageView.load(
                file: resolvedFile,
                maximumPixelSize: 1280,
                origin: origin,
                preservingImage: true,
                transitionDuration: 0.2,
            )
        }
    }

    private func openPeer(from host: UIViewController?, search: Bool) {
        guard let host, let peerID = placeholder?.peerID, let origin = sourceOrigin, origin.isCurrent,
              let client = sourceClient
        else { return }
        let accountID = origin.source.accountID
        Task { [weak host] in
            let chatID: Int64
            if peerID > 0 {
                guard let chat = try? await client.createPrivateChat(force: false, userId: peerID) else { return }
                chatID = chat.id
            } else {
                chatID = peerID
            }
            guard let chat = await RootVM.shared.getCustomChatForNavigation(from: chatID, client: client),
                  origin.isCurrent, let host, let navigation = host.navigationController else { return }
            if search {
                let controller = ChatViewController(customChat: chat)
                navigation.pushViewController(controller, animated: true)
                if let coordinator = navigation.transitionCoordinator {
                    coordinator.animate(alongsideTransition: nil) { _ in controller.beginMessageSearch() }
                } else {
                    controller.beginMessageSearch()
                }
            } else {
                let profile = PeerProfileViewController(
                    customChat: chat,
                    topic: nil,
                    client: client,
                    accountID: accountID,
                )
                profile.onSearch = { [weak profile] in
                    guard let navigation = profile?.navigationController else { return }
                    let controller = ChatViewController(customChat: chat)
                    navigation.pushViewController(controller, animated: true)
                    navigation.transitionCoordinator?
                        .animate(alongsideTransition: nil) { _ in controller.beginMessageSearch() }
                }
                navigation.pushViewController(profile, animated: true)
            }
        }
    }
}

// MARK: - TelegramAvatarPlaceholderView

private final class TelegramAvatarPlaceholderView: UIView {
    // MARK: Private

    private static let savedMessagesIcon = UIImage(named: "Avatar/SavedMessagesIcon")?
        .withTintColor(.white, renderingMode: .alwaysOriginal)
    private static let repliesIcon = UIImage(named: "Avatar/RepliesMessagesIcon")?
        .withTintColor(.white, renderingMode: .alwaysOriginal)
    private static let anonymousSavedMessagesIcon = UIImage(named: "Avatar/AnonymousSenderIcon")?
        .withTintColor(.white, renderingMode: .alwaysOriginal)
    private static let deletedIcon = UIImage(named: "Avatar/DeletedIcon")

    private var colors = [UIColor.clear, UIColor.clear]
    private var letters = [String]()
    private var icon = TelegramAvatarIcon.none

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        contentMode = .redraw
        layer.drawsAsynchronously = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        drawGradient(in: context)
        if let image = image(for: icon) {
            drawIcon(image)
        } else {
            drawLetters(in: context)
        }
    }

    // MARK: Internal

    func configure(colors: [UIColor], letters: [String], icon: TelegramAvatarIcon) {
        self.colors = colors
        self.letters = letters
        self.icon = icon
        setNeedsDisplay()
    }

    func reset() {
        colors = [.clear, .clear]
        letters = []
        icon = .none
        setNeedsDisplay()
    }

    // MARK: Private

    private func drawGradient(in context: CGContext) {
        let cgColors = colors.map(\.cgColor) as CFArray
        var locations: [CGFloat] = [1, 0]
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: cgColors,
            locations: &locations,
        ) else { return }
        context.drawLinearGradient(
            gradient,
            start: .zero,
            end: CGPoint(x: 0, y: bounds.height),
            options: [],
        )
    }

    private func image(for icon: TelegramAvatarIcon) -> UIImage? {
        switch icon {
        case .none:
            nil
        case .savedMessages:
            Self.savedMessagesIcon
        case .replies:
            Self.repliesIcon
        case .anonymousSavedMessages:
            Self.anonymousSavedMessagesIcon
        case .deleted:
            Self.deletedIcon
        }
    }

    private func drawIcon(_ image: UIImage) {
        let scale = bounds.width / 60
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(
            x: floor((bounds.width - size.width) / 2),
            y: floor((bounds.height - size.height) / 2),
            width: size.width,
            height: size.height,
        ))
    }

    private func drawLetters(in context: CGContext) {
        var displayedLetters = Array(letters.prefix(2))
        if displayedLetters.count == 2, displayedLetters.allSatisfy(\.isSingleEmoji) {
            displayedLetters.removeLast()
        }
        let text = displayedLetters.joined()
        guard !text.isEmpty else { return }

        let fontSize = floor(bounds.width * 26 / 60)
        let systemFont = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let font = systemFont.fontDescriptor
            .withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: fontSize) } ?? systemFont
        let attributedText = NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: UIColor.white],
        )
        let line = CTLineCreateWithAttributedString(attributedText)
        let lineBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let displayScale = traitCollection.displayScale
        let offsetX: CGFloat = text == "B" ? 1 : 0
        let origin = CGPoint(
            x: floorToPixels(-lineBounds.origin.x + (bounds.width - lineBounds.width) / 2, scale: displayScale)
                + offsetX,
            y: floorToPixels(-lineBounds.origin.y + (bounds.height - lineBounds.height) / 2, scale: displayScale),
        )

        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -bounds.midX, y: -bounds.midY)
        context.translateBy(x: origin.x, y: origin.y)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func floorToPixels(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        floor(value * scale) / scale
    }
}

private extension String {
    var isSingleEmoji: Bool {
        guard count == 1 else { return false }
        return unicodeScalars.contains {
            $0.properties.isEmojiPresentation || $0.value == 0xFE0F || $0.value == 0x200D
        }
    }
}
