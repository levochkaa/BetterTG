// CommunityCreateViewController.swift

import TDLibKit
import UIKit

// MARK: - CommunitiesViewController

/// Telegram 13's CommunitiesScreen for a group or channel the account owns: the chat's photo, Community and what a
/// community is for, then Create Community. Telegram also lists the account's communities to add the chat to, which
/// TDLib 1.8.69 can't do (it creates a community around a chat, and nothing more).
final class CommunitiesViewController: SettingsListViewController {
    private let chat: Chat
    private let isChannel: Bool
    private let memberCount: Int
    private let header = CommunitiesHeaderView()

    init(chat: Chat, isChannel: Bool, memberCount: Int) {
        self.chat = chat
        self.isChannel = isChannel
        self.memberCount = memberCount
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        header.configure(
            peer: SettingsPeer(chat: chat),
            subtitle: L10n.telegram(isChannel ? "Community.List.SubtitleChannel" : "Community.List.SubtitleGroup"),
            client: client,
            accountID: accountID,
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = tableView.bounds.width
        let height = header.height(for: width)
        if tableView.tableHeaderView !== header || header.frame.size != CGSize(width: width, height: height) {
            header.frame = CGRect(x: 0, y: 0, width: width, height: height)
            tableView.tableHeaderView = header
        }
    }

    override func makeSections() -> [SettingsSection] {
        [SettingsSection(rows: [SettingsRow(
            title: L10n.telegram("Community.List.CreateCommunity"),
            style: .action(destructive: false),
            symbol: "plus.circle",
        ) { [weak self] in self?.openCreate() }])]
    }

    /// openCreateCommunity: CommunityEditScreen's create mode as a modal; once the community exists both close.
    private func openCreate() {
        let create = CommunityCreateViewController(chat: chat, isChannel: isChannel, memberCount: memberCount)
        create.onCreated = { [weak self] in
            self?.dismiss(animated: true)
            self?.navigationController?.popViewController(animated: false)
        }
        present(TelegramNavigationController(rootViewController: create), animated: true)
    }
}

// MARK: - CommunitiesHeaderView

/// CommunitiesScreen's head: the chat's 100 pt photo in a rounded square, 18 pt to Community in 24 pt bold, 13 pt to
/// the explanation in 15 pt, centred.
private final class CommunitiesHeaderView: UIView {
    private let avatar = ProfileAvatarView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    /// The safe area's band, where an iPhone Duo's side column leaves room.
    private var band: CGRect {
        bounds.inset(by: UIEdgeInsets(top: 0, left: safeAreaInsets.left, bottom: 0, right: safeAreaInsets.right))
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        avatar.isUserInteractionEnabled = false
        avatar.isSquare = true
        avatar.layer.cornerRadius = 30
        avatar.layer.cornerCurve = .continuous
        avatar.clipsToBounds = true
        addSubview(avatar)
        titleLabel.text = L10n.telegram("Community.List.Title")
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textAlignment = .center
        addSubview(titleLabel)
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        addSubview(subtitleLabel)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let band = band
        avatar.frame = CGRect(x: band.midX - 50, y: 8, width: 100, height: 100)
        titleLabel.frame = CGRect(
            x: band.minX + 16,
            y: avatar.frame.maxY + 18,
            width: band.width - 32,
            height: ceil(titleLabel.font.lineHeight),
        )
        let textWidth = band.width - 32 - 48
        let subtitleHeight = subtitleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
            .height
        subtitleLabel.frame = CGRect(
            x: band.midX - textWidth / 2,
            y: titleLabel.frame.maxY + 13,
            width: textWidth,
            height: subtitleHeight,
        )
    }

    func configure(peer: SettingsPeer, subtitle: String, client: TDLibClient, accountID: UUID?) {
        avatar.configure(
            file: peer.file,
            minithumbnail: peer.minithumbnail,
            placeholder: peer.placeholder,
            accountID: accountID,
            client: client,
        )
        subtitleLabel.text = subtitle
        setNeedsLayout()
    }

    func height(for width: CGFloat) -> CGFloat {
        let textWidth = width - safeAreaInsets.left - safeAreaInsets.right - 32 - 48
        let subtitleHeight = subtitleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
            .height
        return 8 + 100 + 18 + ceil(titleLabel.font.lineHeight) + 13 + subtitleHeight + 27 - 8
    }
}

// MARK: - CommunityCreateViewController

/// CommunityEditScreen's create mode, from what createCommunity takes: the photo, the name, Who Can Add Chats and the
/// chat the community starts with, visible or hidden (CommunityAddScreen's choice, fixed once made). Done creates the
/// community, then sets its photo and, for Only Admins, its permissions.
final class CommunityCreateViewController: SettingsListViewController {
    var onCreated: (() -> Void)?

    private let chat: Chat
    private let isChannel: Bool
    private let memberCount: Int
    private lazy var photoHeader = ComposePhotoHeaderView(buttonTitle: L10n.telegram("Settings.SetPhoto"))
    private lazy var photoPicker = ComposePhotoPicker(host: self)
    private var photo: UIImage?
    private var name = ""
    private var membersCanAddChats = true
    private var isChatVisible = true
    private var isSaving = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(chat: Chat, isChannel: Bool, memberCount: Int) {
        self.chat = chat
        self.isChannel = isChannel
        self.memberCount = memberCount
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Close"),
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) },
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem.telegramDone(target: self, action: #selector(donePressed))
        photoHeader.onSetPhoto = { [weak self] source in
            guard let self, !isSaving else { return }
            photoPicker.presentMenu(from: source, hasPhoto: photo != nil)
        }
        photoPicker.onChange = { [weak self] image in
            self?.photo = image
            self?.photoHeader.setPhoto(image)
        }
        photoHeader.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: ComposePhotoHeaderView.height)
        tableView.tableHeaderView = photoHeader
        updateDoneButton()
    }

    override func makeSections() -> [SettingsSection] {
        let members = L10n.telegramPlural(
            isChannel ? "Conversation.StatusSubscribers" : "Conversation.StatusMembers",
            count: memberCount,
        )
        return [
            SettingsSection(rows: [SettingsRow(title: "", style: .input(SettingsTextInput(
                text: name,
                placeholder: L10n.telegram("Community.Edit.CommunityNamePlaceholder"),
                maxLength: 128,
            ) { [weak self] text in
                self?.name = text
                self?.updateDoneButton()
            }))]),
            SettingsSection(
                header: L10n.telegram("Community.Edit.WhoCanAddChats"),
                rows: [true, false].map { allMembers in
                    SettingsRow(
                        title: L10n.telegram(allMembers
                            ? "Community.Edit.PermissionAllMembers"
                            : "Community.Edit.PermissionOnlyAdmins"),
                        detail: L10n.telegram(allMembers
                            ? "Community.Edit.PermissionAllMembersInfo"
                            : "Community.Edit.PermissionOnlyAdminsInfo"),
                        style: .subtitle,
                        accessory: membersCanAddChats == allMembers ? .checkmark : .none,
                        isEnabled: !isSaving,
                    ) { [weak self] in
                        self?.membersCanAddChats = allMembers
                        self?.reload()
                    }
                },
            ),
            // draftChatItem: the chat with its members, Hidden while it is, opening its visibility.
            SettingsSection(
                header: L10n.telegramPlural("Community.Edit.ChatsHeader", count: 1),
                rows: [SettingsRow(
                    title: chat.title,
                    titleSuffix: isChatVisible ? nil : L10n.telegram("Community.Add.VisibilityHidden"),
                    detail: memberCount > 0 ? members : nil,
                    style: .peer(SettingsPeer(chat: chat)),
                    isEnabled: !isSaving,
                ) { [weak self] in self?.openVisibility() }],
            ),
        ]
    }

    private func updateDoneButton() {
        navigationItem.rightBarButtonItem?.isEnabled = !trimmedName.isEmpty && !isSaving
    }

    private func openVisibility() {
        let screen = CommunityChatVisibilityViewController(isVisible: isChatVisible) { [weak self] visible in
            self?.isChatVisible = visible
            self?.reload()
        }
        navigationController?.pushViewController(screen, animated: true)
    }

    /// save(): createCommunity with the chat, then the photo and the permissions.
    @objc private func donePressed() {
        let name = trimmedName
        guard !name.isEmpty, !isSaving, contextIsCurrent else { return }
        isSaving = true
        updateDoneButton()
        photoHeader.setEnabled(false)
        reload()
        let client = client
        let chatID = chat.id
        let isHidden = !isChatVisible
        let photo = photo
        let membersCanAddChats = membersCanAddChats
        Task { [weak self] in
            do {
                let community = try await client.send(TDNativeRequests.createCommunity(
                    name: name,
                    chatId: chatID,
                    isChatHidden: isHidden,
                ))
                if let photo {
                    _ = await ComposePhotoPicker.upload(photo) { input in
                        await (try? client.send(TDNativeRequests.setCommunityPhoto(
                            communityId: community.id,
                            photo: input,
                        ))) != nil
                    }
                }
                if !membersCanAddChats {
                    _ = try? await client.send(TDNativeRequests.setCommunityPermissions(
                        communityId: community.id,
                        permissions: TDNativeCommunityPermissions(canEditChatList: false),
                    ))
                }
                guard let self, contextIsCurrent else { return }
                onCreated?()
            } catch {
                guard let self else { return }
                isSaving = false
                updateDoneButton()
                photoHeader.setEnabled(true)
                reload()
                if contextIsCurrent { presentAlert(title: nil, message: ChatManagementRows.failureText(error)) }
            }
        }
    }
}

// MARK: - CommunityChatVisibilityViewController

/// CommunityAddScreen for the chat a new community starts with: CHAT VISIBILITY, Visible or Hidden with their notes,
/// and that it can't change later.
private final class CommunityChatVisibilityViewController: SettingsListViewController {
    private var isVisible: Bool
    private let onChange: (Bool) -> Void

    init(isVisible: Bool, onChange: @escaping (Bool) -> Void) {
        self.isVisible = isVisible
        self.onChange = onChange
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Community.Add.Title")
    }

    override func makeSections() -> [SettingsSection] {
        [SettingsSection(
            header: L10n.telegram("Community.Add.VisibilityHeader"),
            footer: L10n.telegram("Community.Add.VisibilityInfo"),
            rows: [true, false].map { visible in
                SettingsRow(
                    title: L10n
                        .telegram(visible ? "Community.Add.VisibilityVisible" : "Community.Add.VisibilityHidden"),
                    detail: L10n.telegram(visible
                        ? "Community.Add.VisibilityVisibleInfo"
                        : "Community.Add.VisibilityHiddenInfo"),
                    style: .subtitle,
                    accessory: isVisible == visible ? .checkmark : .none,
                ) { [weak self] in
                    guard let self else { return }
                    isVisible = visible
                    onChange(visible)
                    navigationController?.popViewController(animated: true)
                }
            },
        )]
    }
}
