// BusinessLinksViewController.swift

import TDLibKit
import UIKit

// MARK: - BusinessLinksViewController

/// BusinessLinksSetupScreen: Create a Link to Chat over the simple t.me links to the account, then LINKS TO CHAT, each
/// with its name (or the link), its message (or No text) and its clicks. A link opens its editor; swiping or holding it
/// offers Share and Delete. createBusinessChatLink makes an empty link and opens it, as Telegram does.
final class BusinessLinksViewController: SettingsListViewController {
    private let me: User?
    private var links: [TDNativeBusinessChatLink]?
    private var isCreating = false

    /// You can also use a simple link: t.me/username, t.me/+phone, or both.
    private var simpleLinkInfo: String? {
        let username = me?.usernames?.activeUsernames.first
        let phone = me?.phoneNumber.isEmpty == false ? me?.phoneNumber : nil
        let text: String? =
            if let username, let phone {
                L10n.telegram("Business.Links.SimpleLinkInfoUsernamePhone", username, phone)
            } else if let username {
                L10n.telegram("Business.Links.SimpleLinkInfoUsername", username)
            } else if let phone {
                L10n.telegram("Business.Links.SimpleLinkInfoPhone", phone)
            } else {
                nil
            }
        return text?.withoutTelegramLinks.replacing("\\u{2060}", with: "")
    }

    init(me: User?) {
        self.me = me
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Business.Links")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        load()
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [
            SettingsSection(
                header: L10n.telegram("Business.Links.Text").withoutTelegramMarkup,
                footer: simpleLinkInfo,
                rows: [SettingsRow(
                    title: L10n.telegram("Business.Links.CreateAction"),
                    style: .action(destructive: false),
                    symbol: "link.badge.plus",
                    isEnabled: !isCreating && links != nil,
                ) { [weak self] in self?.create() }],
            ),
        ]
        if let links, !links.isEmpty {
            sections.append(SettingsSection(
                header: L10n.telegram("Business.Links.LinksSectionHeader"),
                rows: links.map { link in
                    SettingsRow(
                        title: Self.name(link),
                        detail: link.text.text.isEmpty ? L10n.telegram("Business.Links.ItemNoText") : link.text.text,
                        style: .subtitle,
                        symbol: "link",
                        symbolTint: .systemBlue,
                        action: { [weak self] in self?.open(link) },
                        swipeAction: (L10n.telegram("Common.Delete"), { [weak self] in self?.confirmDelete(link) }),
                        trailingView: SettingsTrailingView {
                            let label = UILabel()
                            label.font = .preferredFont(forTextStyle: .subheadline)
                            label.textColor = .secondaryLabel
                            label.text = link.viewCount == 0
                                ? L10n.telegram("Business.Links.ItemNoClicks")
                                // The English string writes its count as a bare %2.
                                : L10n.telegramPlural("Business.Links.ItemClickCount", count: link.viewCount)
                                    .replacing("%2", with: "\(link.viewCount)")
                            return label
                        },
                    )
                },
            ))
        }
        return sections
    }

    /// BusinessLinkListItemComponent's long press: Share and Delete.
    override func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard indexPath.section == 1, let link = links?[safe: indexPath.row] else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(
                    title: L10n.telegram("Business.Links.ItemActionShare"),
                    image: UIImage(systemName: "square.and.arrow.up"),
                ) { _ in self?.share(link, from: tableView.cellForRow(at: indexPath)) },
                UIAction(
                    title: L10n.telegram("Common.Delete"),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive,
                ) { _ in self?.confirmDelete(link) },
            ])
        })
    }

    /// The link's name, or the link without its scheme.
    static func name(_ link: TDNativeBusinessChatLink) -> String {
        link.title.isEmpty ? link.link.replacing("https://", with: "") : link.title
    }

    private func load() {
        let client = client
        Task { [weak self] in
            let links = await (try? client.send(TDNativeRequests.getBusinessChatLinks()))?.links
            guard let self, contextIsCurrent else { return }
            self.links = links ?? []
            reload()
        }
    }

    private func create() {
        guard !isCreating else { return }
        isCreating = true
        reload()
        let client = client
        Task { [weak self] in
            let result: Result<TDNativeBusinessChatLink, Error>
            do {
                result = try await .success(client.send(TDNativeRequests.createBusinessChatLink(
                    linkInfo: TDNativeInputBusinessChatLink(
                        text: TDNativeFormattedText(text: "", entities: []),
                        title: "",
                    ),
                )))
            } catch {
                result = .failure(error)
            }
            guard let self, contextIsCurrent else { return }
            isCreating = false
            switch result {
            case .success(let link):
                links = (links ?? []) + [link]
                reload()
                open(link)
            case .failure(let error):
                reload()
                let tooMany = "\(error)".contains("LIMIT") || "\(error)".contains("TOO_MANY")
                let alert = UIAlertController(
                    title: nil,
                    message: tooMany
                        ? L10n.telegram("Business.Links.ErrorTooManyLinks")
                        : L10n.telegram("Login.UnknownError"),
                    preferredStyle: .alert,
                )
                alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    private func open(_ link: TDNativeBusinessChatLink) {
        navigationController?.pushViewController(BusinessLinkEditViewController(link: link), animated: true)
    }

    private func share(_ link: TDNativeBusinessChatLink, from source: UIView?) {
        guard let url = URL(string: link.link) else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = source ?? view
        present(activity, animated: true)
    }

    /// openDeleteLink: Delete Link over Cancel.
    private func confirmDelete(_ link: TDNativeBusinessChatLink) {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(
            title: L10n.telegram("Business.Links.DeleteItemConfirmationAction"),
            style: .destructive,
        ) { [weak self] _ in
            self?.links?.removeAll { $0.link == link.link }
            self?.reload()
            self?.perform { client in
                _ = try await client.send(TDNativeRequests.deleteBusinessChatLink(link: link.link))
            } completion: {}
        })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        // On a regular width the sheet stands on the link's row.
        let row = links?.firstIndex { $0.link == link.link }
        sheet.popoverPresentationController?.sourceView =
            row.flatMap { tableView.cellForRow(at: IndexPath(row: $0, section: 1)) } ?? view
        present(sheet, animated: true)
    }
}

// MARK: - BusinessLinkEditViewController

/// A link's editor, in place of Telegram's chat-style one: the message the link enters in a customer's input field
/// (Business.Links.PreviewText), the name only the account sees, and the link, which a tap copies. Done saves both
/// (editBusinessChatLink) with Preset message saved.
final class BusinessLinkEditViewController: SettingsListViewController {
    private let link: TDNativeBusinessChatLink
    private var message: String
    private var name: String

    init(link: TDNativeBusinessChatLink) {
        self.link = link
        self.message = link.text.text
        self.name = link.title
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Business.Links.EditLinkTitle")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Done"),
            primaryAction: UIAction { [weak self] _ in self?.save() },
        )
    }

    override func makeSections() -> [SettingsSection] {
        [
            SettingsSection(
                header: L10n.telegram("Business.Links.PreviewTitle").uppercased(),
                footer: L10n.telegram("Business.Links.PreviewText"),
                rows: [SettingsRow(title: "", style: .input(SettingsTextInput(
                    text: message,
                    placeholder: L10n.telegram("Conversation.InputTextPlaceholder"),
                    maxLength: 4096,
                    isMultiline: true,
                ) { [weak self] text in self?.message = text }))],
            ),
            SettingsSection(
                header: L10n.telegram("Business.Links.LinkNameTitle").uppercased(),
                footer: L10n.telegram("Business.Links.LinkNameText"),
                rows: [SettingsRow(title: "", style: .input(SettingsTextInput(
                    text: name,
                    placeholder: L10n.telegram("Business.Links.LinkNameInputPlaceholder"),
                    maxLength: 32,
                ) { [weak self] text in self?.name = text }))],
            ),
            SettingsSection(rows: [SettingsRow(
                title: link.link.replacing("https://", with: ""),
                style: .action(destructive: false),
                symbol: "doc.on.doc",
            ) { [weak self] in self?.copyLink() }]),
        ]
    }

    private func copyLink() {
        UIPasteboard.general.string = link.link
        TelegramUndoToast.show(text: L10n.telegram("Conversation.LinkCopied"), in: view, bottomInset: 12, undo: nil)
    }

    private func save() {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message != link.text.text || name != link.title else {
            navigationController?.popViewController(animated: true)
            return
        }
        let info = TDNativeInputBusinessChatLink(text: TDNativeFormattedText(text: message, entities: []), title: name)
        let url = link.link
        perform { client in
            _ = try await client.send(TDNativeRequests.editBusinessChatLink(link: url, linkInfo: info))
        } completion: { [weak self] in
            guard let self else { return }
            let container = navigationController?.view
            navigationController?.popViewController(animated: true)
            if let container {
                TelegramUndoToast.show(
                    text: L10n.telegram("Business.Links.EditLinkToastSaved"),
                    in: container,
                    bottomInset: 12,
                    undo: nil,
                )
            }
        }
    }
}
