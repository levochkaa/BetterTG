// ChatBlockPeerSheetViewController.swift

import UIKit

// MARK: - ChatBlockPeerSheetViewController

/// ChatControllerReport.reportPeer's sheet for a person: "Do you want to block …?" (left out for a deleted account),
/// Report Spam and Delete this Chat, both checked, and Block in red. Nothing happens until Block.
final class ChatBlockPeerSheetViewController: SettingsListViewController {
    private let name: String
    private let isDeleted: Bool
    private let onBlock: (_ reportingSpam: Bool, _ deletingChat: Bool) -> Void
    private var reportsSpam = true
    private var deletesChat = true

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private init(name: String, isDeleted: Bool, onBlock: @escaping (Bool, Bool) -> Void) {
        self.name = name
        self.isDeleted = isDeleted
        self.onBlock = onBlock
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"),
            style: .plain,
            target: self,
            action: #selector(cancel),
        )
    }

    override func makeSections() -> [SettingsSection] {
        [
            SettingsSection(
                header: isDeleted ? nil : L10n.telegram("UserInfo.BlockConfirmationTitle", name),
                rows: [
                    option(L10n.telegram("Conversation.Moderate.Report"), isOn: reportsSpam) { sheet in
                        sheet.reportsSpam.toggle()
                    },
                    option(L10n.telegram("ReportSpam.DeleteThisChat"), isOn: deletesChat) { sheet in
                        sheet.deletesChat.toggle()
                    },
                ],
            ),
            SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("UserInfo.BlockActionTitle", name),
                style: .action(destructive: true),
            ) { [weak self] in self?.block() }]),
        ]
    }

    static func present(
        name: String,
        isDeleted: Bool,
        from presenter: UIViewController,
        onBlock: @escaping (_ reportingSpam: Bool, _ deletingChat: Bool) -> Void,
    ) {
        let navigation = TelegramNavigationController(
            rootViewController: ChatBlockPeerSheetViewController(name: name, isDeleted: isDeleted, onBlock: onBlock),
        )
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
        presenter.present(navigation, animated: true)
    }

    private func option(
        _ title: String,
        isOn: Bool,
        toggle: @escaping (ChatBlockPeerSheetViewController) -> Void,
    ) -> SettingsRow {
        SettingsRow(title: title, accessory: isOn ? .checkmark : .none) { [weak self] in
            guard let self else { return }
            toggle(self)
            reload()
        }
    }

    private func block() {
        let reportsSpam = reportsSpam
        let deletesChat = deletesChat
        let onBlock = onBlock
        dismiss(animated: true) { onBlock(reportsSpam, deletesChat) }
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }
}
