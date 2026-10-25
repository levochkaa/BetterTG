// ArchiveSettingsViewController.swift

import TDLibKit
import UIKit

// MARK: - ArchiveSettingsViewController

/// Telegram's ArchiveSettingsController on TDLib's archiveChatListSettings: Always Keep Archived for unmuted chats,
/// and while that is off, for chats from folders. Archiving chats from unknown users is a Premium setting and is not
/// offered.
final class ArchiveSettingsViewController: SettingsListViewController {
    private var settings: TDNativeArchiveChatListSettings?
    private var loadTask: Task<Void, Never>?

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("ArchiveSettings.Title")
        let client = client
        loadTask = Task { [weak self] in
            let settings = try? await client.send(TDNativeRequests.getArchiveChatListSettings())
            guard let self, !Task.isCancelled, contextIsCurrent else { return }
            self.settings = settings
            reload()
        }
    }

    override func makeSections() -> [SettingsSection] {
        guard let settings else { return [] }
        var sections = [SettingsSection(
            header: L10n.telegram("ArchiveSettings.UnmutedChatsHeader"),
            footer: L10n.telegram("ArchiveSettings.UnmutedChatsFooter"),
            rows: [SettingsRow(
                title: L10n.telegram("ArchiveSettings.KeepArchived"),
                accessory: .toggle(isOn: settings.keepUnmutedChatsArchived) { [weak self] isOn in
                    self?.update(keepUnmuted: isOn)
                },
            )],
        )]
        if !settings.keepUnmutedChatsArchived {
            sections.append(SettingsSection(
                header: L10n.telegram("ArchiveSettings.FolderChatsHeader"),
                footer: L10n.telegram("ArchiveSettings.FolderChatsFooter"),
                rows: [SettingsRow(
                    title: L10n.telegram("ArchiveSettings.KeepArchived"),
                    accessory: .toggle(isOn: settings.keepChatsFromFoldersArchived) { [weak self] isOn in
                        self?.update(keepFolders: isOn)
                    },
                )],
            ))
        }
        return sections
    }

    /// updateAccountKeepArchivedUnmuted and updateAccountKeepArchivedFolders, kept on screen at once.
    private func update(keepUnmuted: Bool? = nil, keepFolders: Bool? = nil) {
        guard let current = settings, contextIsCurrent else { return }
        let updated = TDNativeArchiveChatListSettings(
            archiveAndMuteNewChatsFromUnknownUsers: current.archiveAndMuteNewChatsFromUnknownUsers,
            keepUnmutedChatsArchived: keepUnmuted ?? current.keepUnmutedChatsArchived,
            keepChatsFromFoldersArchived: keepFolders ?? current.keepChatsFromFoldersArchived,
        )
        settings = updated
        reload()
        let client = client
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.setArchiveChatListSettings(settings: updated))
            } catch {
                guard let self, contextIsCurrent else { return }
                settings = current
                reload()
            }
        }
    }
}

// MARK: - ArchiveInfoViewController

/// ArchiveInfoScreen: the archive's 90 pt gradient circle, "This is Your Archive", how new messages move archived chats
/// with a link to Archive Settings, Telegram's three notes on archived chats, hiding the archive and stories, and Got
/// it.
final class ArchiveInfoViewController: UIViewController {
    private let keepsUnmutedArchived: Bool
    private let openSettings: () -> Void

    init(keepsUnmutedArchived: Bool, openSettings: @escaping () -> Void) {
        self.keepsUnmutedArchived = keepsUnmutedArchived
        self.openSettings = openSettings
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        let icon = ArchiveInfoIconView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        let title = UILabel()
        title.text = L10n.telegram("ArchiveInfo.Title")
        title.font = .systemFont(ofSize: 19, weight: .semibold)
        title.textAlignment = .center
        title.numberOfLines = 0

        let text = UILabel()
        let raw = L10n.telegram(keepsUnmutedArchived
            ? "ArchiveInfo.TextKeepArchivedUnmuted"
            : "ArchiveInfo.TextKeepArchivedDefault")
        text.attributedText = Self.mainText(raw)
        text.numberOfLines = 0
        text.isUserInteractionEnabled = true
        text.accessibilityTraits = .link
        text.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(textTapped)))

        let items = UIStackView(arrangedSubviews: [
            Self.item("archivebox", L10n.telegram("ArchiveInfo.ChatsTitle"), L10n.telegram("ArchiveInfo.ChatsText")),
            Self.item("eye.slash", L10n.telegram("ArchiveInfo.HideTitle"), L10n.telegram("ArchiveInfo.HideText")),
            Self.item(
                "circle.dashed",
                L10n.telegram("ArchiveInfo.StoriesTitle"),
                L10n.telegram("ArchiveInfo.StoriesText"),
            ),
        ])
        items.axis = .vertical
        items.spacing = 24

        var configuration = UIButton.Configuration.filled()
        configuration.title = L10n.telegram("ArchiveInfo.CloseAction")
        configuration.cornerStyle = .large
        configuration.buttonSize = .large
        let close = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })

        let stack = UIStackView(arrangedSubviews: [icon, title, text, items, close])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.setCustomSpacing(15, after: icon)
        stack.setCustomSpacing(24, after: text)
        stack.setCustomSpacing(32, after: items)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.heightAnchor.constraint(equalToConstant: 90),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
    }

    /// The text in 15 pt, its "[Tap to change >]()" link semibold in the accent colour.
    private static func mainText(_ raw: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let pattern = /\[(.*?)\]\(\)/
        var rest = Substring(raw)
        while let match = rest.firstMatch(of: pattern) {
            result.append(NSAttributedString(string: String(rest[..<match.range.lowerBound]), attributes: [
                .font: UIFont.systemFont(ofSize: 15),
                .foregroundColor: UIColor.label,
            ]))
            result.append(NSAttributedString(string: String(match.1).replacing(" >", with: " ›"), attributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: UIColor.systemBlue,
            ]))
            rest = rest[match.range.upperBound...]
        }
        result.append(NSAttributedString(string: String(rest), attributes: [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: UIColor.label,
        ]))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }

    /// An item: its icon in the left slot, the semibold title and the secondary text 2 pt under it.
    private static func item(_ symbol: String, _ title: String, _ text: String) -> UIView {
        let icon = UIImageView(image: UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular),
        ))
        icon.tintColor = .systemBlue
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.numberOfLines = 0
        let textLabel = UILabel()
        textLabel.text = text
        textLabel.font = .systemFont(ofSize: 15)
        textLabel.textColor = .secondaryLabel
        textLabel.numberOfLines = 0
        let labels = UIStackView(arrangedSubviews: [titleLabel, textLabel])
        labels.axis = .vertical
        labels.spacing = 2
        let row = UIStackView(arrangedSubviews: [icon, labels])
        row.alignment = .top
        row.spacing = 16
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 28),
        ])
        return row
    }

    /// The text's link opens Archive Settings once the sheet is gone.
    @objc private func textTapped() {
        let openSettings = openSettings
        dismiss(animated: true) { openSettings() }
    }
}

// MARK: - ArchiveInfoIconView

/// The pinned archive avatar's gradient in a 90 pt circle with the archive glyph.
private final class ArchiveInfoIconView: UIView {
    private let gradient = CAGradientLayer()
    private let glyph = UIImageView(image: UIImage(
        systemName: "archivebox.fill",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 38, weight: .regular),
    ))

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradient.colors = [UIColor(rgb: 0x72D5FD).cgColor, UIColor(rgb: 0x2A9EF1).cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(gradient)
        glyph.tintColor = .white
        addSubview(glyph)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(90, bounds.height)
        let circle = CGRect(x: (bounds.width - side) / 2, y: 0, width: side, height: side)
        gradient.frame = circle
        gradient.cornerRadius = side / 2
        glyph.sizeToFit()
        glyph.center = CGPoint(x: circle.midX, y: circle.midY)
    }
}
