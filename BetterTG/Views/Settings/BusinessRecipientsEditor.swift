// BusinessRecipientsEditor.swift

import TDLibKit
import UIKit

// MARK: - BusinessRecipientCategory

/// TelegramBusinessRecipients.Categories: the chat categories a business bot or message reaches.
enum BusinessRecipientCategory: CaseIterable {
    case existingChats, newChats, contacts, nonContacts

    var title: String {
        switch self {
        case .existingChats: L10n.telegram("BusinessMessageSetup.Recipients.CategoryExistingChats")
        case .newChats: L10n.telegram("BusinessMessageSetup.Recipients.CategoryNewChats")
        case .contacts: L10n.telegram("BusinessMessageSetup.Recipients.CategoryContacts")
        case .nonContacts: L10n.telegram("BusinessMessageSetup.Recipients.CategoryNonContacts")
        }
    }

    var symbol: String {
        switch self {
        case .existingChats: "bubble.left.and.bubble.right.fill"
        case .newChats: "bubble.left.fill"
        case .contacts: "person.crop.circle.fill"
        case .nonContacts: "person.crop.circle.badge.questionmark.fill"
        }
    }
}

// MARK: - BusinessRecipients

/// TDLib's businessRecipients as the screens edit it: All 1-to-1 Chats Except… (`excludesSelected`) or Only Selected
/// Chats, the chosen categories and people, and with Only Selected Chats the people left out.
struct BusinessRecipients: Equatable {
    var excludesSelected = true
    var categories = Set<BusinessRecipientCategory>()
    var chatIDs = [Int64]()
    var excludedChatIDs = [Int64]()

    /// Only Selected Chats with nothing selected reaches nobody (BusinessMessageSetup.ErrorNoRecipients).
    var reachesNobody: Bool {
        !excludesSelected && categories.isEmpty && chatIDs.isEmpty
    }

    var peerIDs: [Int64] {
        chatIDs + excludedChatIDs
    }

    var native: TDNativeBusinessRecipients {
        TDNativeBusinessRecipients(
            chatIds: chatIDs,
            excludedChatIds: excludesSelected ? [] : excludedChatIDs,
            selectExistingChats: categories.contains(.existingChats),
            selectNewChats: categories.contains(.newChats),
            selectContacts: categories.contains(.contacts),
            selectNonContacts: categories.contains(.nonContacts),
            excludeSelected: excludesSelected,
        )
    }

    init() {}

    init(_ native: TDNativeBusinessRecipients) {
        self.excludesSelected = native.excludeSelected
        self.chatIDs = native.chatIds
        self.excludedChatIDs = native.excludedChatIds
        if native.selectExistingChats { categories.insert(.existingChats) }
        if native.selectNewChats { categories.insert(.newChats) }
        if native.selectContacts { categories.insert(.contacts) }
        if native.selectNonContacts { categories.insert(.nonContacts) }
    }

    /// Private chats must be known to TDLib before they can be named.
    static func prepareChats(_ ids: [Int64], client: TDLibClient) async {
        for id in ids {
            _ = try? await client.createPrivateChat(force: false, userId: id)
        }
    }
}

// MARK: - BusinessRecipientsEditor

/// The recipient sections Telegram's business screens share: the mode, then the included or excluded chats with
/// Include Chats… or Exclude Chats… (the missing categories, then people), and optionally the people left out of Only
/// Selected Chats. Rows are removed by swiping.
@MainActor final class BusinessRecipientsEditor {
    var recipients: BusinessRecipients {
        didSet { if recipients.peerIDs != oldValue.peerIDs { resolvePeers() } }
    }

    var onChange: (() -> Void)?

    private weak var screen: SettingsListViewController?
    private let header: String
    private let includedFooter: String
    private let excludedFooter: String
    /// ChatbotSetupScreen lists the people left out of Only Selected Chats; the message screens don't.
    private let listsExcludedPeople: Bool
    private var peers = [Int64: SettingsPeer]()
    private var firstSection = 0

    private var chatsSection: SettingsSection {
        let isExcluded = recipients.excludesSelected
        var rows = [SettingsRow(
            title: L10n.telegram(isExcluded
                ? "BusinessMessageSetup.Recipients.AddExclude"
                : "BusinessMessageSetup.Recipients.AddInclude"),
            style: .action(destructive: false),
            symbol: "plus",
        ) { [weak self] in self?.addChats() }]
        for category in BusinessRecipientCategory.allCases where recipients.categories.contains(category) {
            rows.append(SettingsRow(
                title: category.title,
                symbol: category.symbol,
                symbolTint: .systemBlue,
                swipeAction: (L10n.telegram("Common.Delete"), { [weak self] in
                    self?.recipients.categories.remove(category)
                    self?.onChange?()
                }),
            ))
        }
        rows += peerRows(recipients.chatIDs) { [weak self] id in self?.recipients.chatIDs.removeAll { $0 == id } }
        return SettingsSection(
            header: L10n.telegram(isExcluded
                ? "BusinessMessageSetup.Recipients.ExcludedSectionHeader"
                : "BusinessMessageSetup.Recipients.IncludedSectionHeader"),
            footer: (isExcluded ? excludedFooter : includedFooter).withoutTelegramMarkup,
            rows: rows,
        )
    }

    private var excludedPeopleSection: SettingsSection {
        var rows = [SettingsRow(
            title: L10n.telegram("BusinessMessageSetup.Recipients.AddExclude"),
            style: .action(destructive: false),
            symbol: "minus",
        ) { [weak self] in self?.pickPeople(excluding: true) }]
        rows += peerRows(recipients.excludedChatIDs) { [weak self] id in
            self?.recipients.excludedChatIDs.removeAll { $0 == id }
        }
        return SettingsSection(
            header: L10n.telegram("BusinessMessageSetup.Recipients.ExcludedSectionHeader"),
            footer: excludedFooter.withoutTelegramMarkup,
            rows: rows,
        )
    }

    init(
        screen: SettingsListViewController,
        header: String,
        includedFooter: String,
        excludedFooter: String,
        listsExcludedPeople: Bool,
    ) {
        self.recipients = BusinessRecipients()
        self.screen = screen
        self.header = header
        self.includedFooter = includedFooter
        self.excludedFooter = excludedFooter
        self.listsExcludedPeople = listsExcludedPeople
    }

    /// The sections, which start at `index` in the screen's list.
    func sections(at index: Int) -> [SettingsSection] {
        firstSection = index
        var sections = [
            SettingsSection(header: header, rows: [
                modeRow("BusinessMessageSetup.RecipientsOptionAllExcept", excludes: true),
                modeRow("BusinessMessageSetup.RecipientsOptionOnly", excludes: false),
            ]),
            chatsSection,
        ]
        if listsExcludedPeople, !recipients.excludesSelected {
            sections.append(excludedPeopleSection)
        }
        return sections
    }

    private func modeRow(_ key: String, excludes: Bool) -> SettingsRow {
        SettingsRow(
            title: L10n.telegram(key),
            accessory: recipients.excludesSelected == excludes ? .checkmark : .none,
        ) { [weak self] in
            guard let self, recipients.excludesSelected != excludes else { return }
            // The chosen chats change meaning with the mode, so they start over.
            recipients = BusinessRecipients()
            recipients.excludesSelected = excludes
            onChange?()
        }
    }

    private func peerRows(_ ids: [Int64], remove: @escaping (Int64) -> Void) -> [SettingsRow] {
        ids.compactMap { id in
            guard let peer = peers[id] else { return nil }
            return SettingsRow(
                title: peer.title,
                style: .peer(peer),
                swipeAction: (L10n.telegram("Common.Delete"), { [weak self] in
                    remove(id)
                    self?.onChange?()
                }),
            )
        }
    }

    /// The categories not chosen yet, then the people.
    private func addChats() {
        guard let screen else { return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        for category in BusinessRecipientCategory.allCases where !recipients.categories.contains(category) {
            sheet.addAction(UIAlertAction(title: category.title, style: .default) { [weak self] _ in
                self?.recipients.categories.insert(category)
                self?.onChange?()
            })
        }
        sheet.addAction(UIAlertAction(title: L10n.telegram("ChatbotSetup.Recipients.AddUsers"), style: .default) {
            [weak self] _ in self?.pickPeople(excluding: false)
        })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView =
            screen.tableView.cellForRow(at: IndexPath(row: 0, section: firstSection + 1)) ?? screen.view
        screen.present(sheet, animated: true)
    }

    /// People only: business features reach private chats.
    private func pickPeople(excluding: Bool) {
        guard let screen, screen.presentedViewController == nil else { return }
        let picker = SettingsPeerPickerViewController(excludedUserIDs: Set(recipients.peerIDs), excludedChatIDs: [])
        picker.listsOnlyPeople = true
        picker.pickerTitle = L10n.telegram(excluding || recipients.excludesSelected
            ? "BusinessMessageSetup.Recipients.ExcludeSearchTitle"
            : "BusinessMessageSetup.Recipients.IncludeSearchTitle")
        picker.onDone = { [weak self] users, _ in
            guard let self else { return }
            if excluding {
                recipients.excludedChatIDs += users
            } else {
                recipients.chatIDs += users
            }
            onChange?()
        }
        screen.present(UINavigationController(rootViewController: picker), animated: true)
    }

    private func resolvePeers() {
        guard let client = screen?.client else { return }
        let missing = recipients.peerIDs.filter { peers[$0] == nil }
        guard !missing.isEmpty else { return }
        Task { [weak self] in
            var resolved = [Int64: SettingsPeer]()
            for id in missing {
                if let peer = await SettingsPeer.user(id, client: client) { resolved[id] = peer }
            }
            guard let self else { return }
            peers.merge(resolved) { $1 }
            onChange?()
        }
    }
}
