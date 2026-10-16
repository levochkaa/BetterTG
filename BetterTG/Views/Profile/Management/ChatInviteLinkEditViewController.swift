// ChatInviteLinkEditViewController.swift

import TDLibKit
import UIKit

// MARK: - ChatInviteLinkEditViewController

/// Telegram's InviteLinkEditController: the link's name, Request Admin Approval, a time limit (1 hour, 1 day, 1 week,
/// none, or an expiry date) and, without approval, a number of uses (1, 10, 100, none, or a custom number). Done
/// creates the link (createChatInviteLink) or saves it (editChatInviteLink); an existing link can be revoked here.
final class ChatInviteLinkEditViewController: SettingsListViewController {
    private enum TimeLimit: Equatable {
        case period(Int)
        case date(Int)
        case unlimited
    }

    /// ItemListInviteLinkTimeLimitItem's stops and ItemListInviteLinkUsageLimitItem's presets.
    private static let periods = [60 * 60, 24 * 60 * 60, 7 * 24 * 60 * 60]
    private static let usages = [1, 10, 100]
    private static let maxUsage = 99999
    private static let maxNameLength = 32

    var onSave: ((ChatInviteLink) -> Void)?

    private let target: ChatManagementTarget
    private let link: ChatInviteLink?
    private var name: String
    private var requestsApproval: Bool
    private var timeLimit: TimeLimit
    private var memberLimit: Int
    private var isSaving = false

    /// Approval is off for links of a public group that anyone may join without it.
    private var canRequestApproval: Bool {
        !(target.isPublic && !target.isChannel && target.supergroup?.joinByRequest != true)
    }

    private var expirationDate: Int {
        switch timeLimit {
        case .period(let seconds): ChatInviteLinkText.now + seconds
        case .date(let date): date
        case .unlimited: 0
        }
    }

    init(target: ChatManagementTarget, link: ChatInviteLink?) {
        self.target = target
        self.link = link
        self.name = link?.name ?? ""
        self.requestsApproval = link?.createsJoinRequest ?? false
        let expiration = link?.expirationDate ?? 0
        self.timeLimit = expiration == 0 ? .unlimited : .date(expiration)
        self.memberLimit = link?.memberLimit ?? 0
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram(link == nil ? "InviteLink.Create.Title" : "InviteLink.Create.EditTitle")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Done"), style: .prominent, target: self, action: #selector(donePressed),
        )
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [SettingsSection(
            header: L10n.telegram("InviteLink.Create.LinkNameTitle"),
            footer: L10n.telegram("InviteLink.Create.LinkNameInfo"),
            rows: [SettingsRow(title: "", style: .input(SettingsTextInput(
                text: name,
                placeholder: L10n.telegram("InviteLink.Create.LinkName"),
                maxLength: Self.maxNameLength,
            ) { [weak self] text in self?.name = text }))],
        )]
        if !target.isPublic || !target.isChannel {
            let approvalTitle = target.isChannel
                ? "Channel.Setup.ApproveNewSubscribers"
                : "Group.Setup.ApproveNewMembers"
            sections.append(SettingsSection(
                footer: L10n.telegram(canRequestApproval
                    ? "InviteLink.Create.RequestApprovalInfo"
                    : "InviteLink.Create.RequestApprovalPublicGroupUnavailable"),
                rows: [SettingsRow(
                    title: L10n.telegram(approvalTitle),
                    accessory: .toggle(isOn: requestsApproval && canRequestApproval, onChange: { [weak self] isOn in
                        self?.requestsApproval = isOn
                        self?.reload()
                    }),
                    isEnabled: canRequestApproval && !isSaving,
                )],
            ))
        }
        sections.append(timeSection())
        if !requestsApproval || !canRequestApproval {
            sections.append(usageSection())
        }
        if link != nil {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("InviteLink.Create.Revoke"),
                style: .action(destructive: true),
            ) { [weak self] in self?.revoke() }]))
        }
        return sections
    }

    private func timeSection() -> SettingsSection {
        var rows = Self.periods.map { period in
            SettingsRow(
                title: SettingsFormatting.timeInterval(seconds: period),
                accessory: timeLimit == .period(period) ? .checkmark : .none,
            ) { [weak self] in self?.setTimeLimit(.period(period)) }
        }
        rows.append(SettingsRow(
            title: L10n.telegram("InviteLink.Create.TimeLimitNoLimit"),
            accessory: timeLimit == .unlimited ? .checkmark : .none,
        ) { [weak self] in self?.setTimeLimit(.unlimited) })
        let expiration = expirationDate
        rows.append(SettingsRow(
            title: L10n.telegram("InviteLink.Create.TimeLimitExpiryDate"),
            detail: expiration == 0
                ? L10n.telegram("InviteLink.Create.TimeLimitExpiryDateNever")
                : Foundation.Date(timeIntervalSince1970: TimeInterval(expiration))
                    .formatted(date: .abbreviated, time: .shortened),
            accessory: .disclosure,
        ) { [weak self] in self?.pickExpiryDate() })
        return SettingsSection(
            header: L10n.telegram("InviteLink.Create.TimeLimit"),
            footer: L10n.telegram("InviteLink.Create.TimeLimitInfo"),
            rows: rows,
        )
    }

    private func usageSection() -> SettingsSection {
        var rows = Self.usages.map { usage in
            SettingsRow(
                title: usage.formatted(.number),
                accessory: memberLimit == usage ? .checkmark : .none,
            ) { [weak self] in self?.setMemberLimit(usage) }
        }
        rows.append(SettingsRow(
            title: L10n.telegram("InviteLink.Create.UsersLimitNoLimit"),
            accessory: memberLimit == 0 ? .checkmark : .none,
        ) { [weak self] in self?.setMemberLimit(0) })
        rows.append(SettingsRow(
            title: L10n.telegram("InviteLink.Create.UsersLimitNumberOfUsers"),
            detail: memberLimit == 0
                ? L10n.telegram("InviteLink.Create.UsersLimitNumberOfUsersUnlimited")
                : memberLimit.formatted(.number),
            accessory: .disclosure,
        ) { [weak self] in self?.pickMemberLimit() })
        return SettingsSection(
            header: L10n.telegram("InviteLink.Create.UsersLimit"),
            footer: L10n.telegram("InviteLink.Create.UsersLimitInfo"),
            rows: rows,
        )
    }

    private func setTimeLimit(_ value: TimeLimit) {
        guard !isSaving else { return }
        timeLimit = value
        reload()
    }

    private func setMemberLimit(_ value: Int) {
        guard !isSaving else { return }
        memberLimit = value
        reload()
    }

    /// The Expiry Date row's picker: a date and time from a minute ahead.
    private func pickExpiryDate() {
        guard !isSaving else { return }
        view.endEditing(true)
        let current = expirationDate
        let picker = ChatInviteLinkDateSheet(
            date: current == 0
                ? Foundation.Date().addingTimeInterval(24 * 60 * 60)
                : Foundation.Date(timeIntervalSince1970: TimeInterval(current)),
        ) { [weak self] date in
            self?.setTimeLimit(.date(Int(date.timeIntervalSince1970)))
        }
        picker.present(from: self)
    }

    /// The Number of Uses field, up to Telegram's 99,999.
    private func pickMemberLimit() {
        guard !isSaving else { return }
        view.endEditing(true)
        let alert = UIAlertController(
            title: L10n.telegram("InviteLink.Create.UsersLimitNumberOfUsers"),
            message: nil,
            preferredStyle: .alert,
        )
        let current = memberLimit
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.placeholder = L10n.telegram("InviteLink.Create.UsersLimitNumberOfUsersUnlimited")
            field.text = current > 0 ? String(current) : nil
        }
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Done"), style: .default) { [
            weak self,
            weak alert,
        ] _ in
            let value = Int(alert?.textFields?.first?.text ?? "") ?? 0
            self?.setMemberLimit(min(max(0, value), Self.maxUsage))
        })
        present(alert, animated: true)
    }

    @objc private func donePressed() {
        guard !isSaving, contextIsCurrent else { return }
        view.endEditing(true)
        if case .date(let date) = timeLimit, date <= ChatInviteLinkText.now {
            timeLimit = .unlimited
        }
        let chatID = target.chatID
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let expiration = expirationDate
        let approval = requestsApproval && canRequestApproval
        let limit = approval ? 0 : memberLimit
        let address = link?.inviteLink
        setSaving(true)
        let client = client
        Task { [weak self] in
            do {
                let saved =
                    if let address {
                        try await client.send(TDNativeRequests.editChatInviteLink(
                            chatId: chatID,
                            inviteLink: address,
                            name: name,
                            expirationDate: expiration,
                            memberLimit: limit,
                            createsJoinRequest: approval,
                        ))
                    } else {
                        try await client.send(TDNativeRequests.createChatInviteLink(
                            chatId: chatID,
                            name: name,
                            expirationDate: expiration,
                            memberLimit: limit,
                            createsJoinRequest: approval,
                        ))
                    }
                guard let self, contextIsCurrent else { return }
                onSave?(saved)
                navigationController?.popViewController(animated: true)
            } catch {
                guard let self else { return }
                setSaving(false)
                if contextIsCurrent { presentAlert(title: nil, message: ChatManagementRows.failureText(error)) }
            }
        }
    }

    private func setSaving(_ value: Bool) {
        isSaving = value
        navigationItem.rightBarButtonItem?.isEnabled = !value
        reload()
    }

    /// Revoke Link: the link stops working, and the list shows it under Revoked Links.
    private func revoke() {
        guard let address = link?.inviteLink, !isSaving else { return }
        ChatInviteLinkText.confirmRevoke(isChannel: target.isChannel, in: self) { [weak self] in
            guard let self else { return }
            let chatID = target.chatID
            perform(failureText: { ChatManagementRows.failureText($0) }) { client in
                _ = try await client.send(TDNativeRequests.revokeChatInviteLink(chatId: chatID, inviteLink: address))
            } completion: { [weak self] in
                guard let navigationController = self?.navigationController else { return }
                if let list = navigationController.viewControllers
                    .last(where: { $0 is ChatInviteLinksViewController })
                {
                    navigationController.popToViewController(list, animated: true)
                } else {
                    navigationController.popViewController(animated: true)
                }
            }
        }
    }
}

// MARK: - ChatInviteLinkDateSheet

/// The expiry date and time picker Telegram shows under Expiry Date (ItemListDatePickerItem), in a sheet.
private final class ChatInviteLinkDateSheet: UIViewController {
    private let picker = UIDatePicker()
    private let initialDate: Foundation.Date
    private let onPick: (Foundation.Date) -> Void

    init(date: Foundation.Date, onPick: @escaping (Foundation.Date) -> Void) {
        self.initialDate = date
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = L10n.telegram("InviteLink.Create.TimeLimitExpiryDate")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"), style: .plain, target: self, action: #selector(cancelPressed),
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Done"), style: .prominent, target: self, action: #selector(donePressed),
        )
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .inline
        picker.minimumDate = Foundation.Date().addingTimeInterval(60)
        picker.date = max(initialDate, picker.minimumDate ?? initialDate)
        picker.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            picker.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            picker.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            picker.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
    }

    func present(from host: UIViewController) {
        let navigation = UINavigationController(rootViewController: self)
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.custom { context in min(context.maximumDetentValue, 560) }, .large()]
            sheet.prefersGrabberVisible = true
        }
        host.present(navigation, animated: true)
    }

    @objc private func cancelPressed() {
        dismiss(animated: true)
    }

    @objc private func donePressed() {
        onPick(picker.date)
        dismiss(animated: true)
    }
}
