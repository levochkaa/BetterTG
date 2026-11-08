// BusinessMessageViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - BusinessMessageViewController

/// AutomaticBusinessMessageSetupScreen for the greeting or the away message: Send Greeting Message (Send Away
/// Message), then the message itself, which lives in the hello or away quick reply shortcut (Create a Greeting
/// Message while it has none); for the away message SCHEDULE (Always Send, Outside of Business Hours, Custom Schedule
/// with its start and end) and Only if Offline; RECIPIENTS (`BusinessRecipientsEditor`); and for the greeting PERIOD
/// OF NO ACTIVITY. Leaving saves what changed (setBusinessGreetingMessageSettings, setBusinessAwayMessageSettings);
/// with no recipients or an incomplete custom schedule it saves nothing and says why.
final class BusinessMessageViewController: SettingsListViewController {
    enum Kind {
        case greeting, away

        var shortcutName: String {
            self == .greeting ? "hello" : "away"
        }
    }

    enum Schedule: Equatable {
        case always, outsideBusinessHours, custom
    }

    /// What the screen saves, compared with what it loaded so a visit alone changes nothing.
    private struct Draft: Equatable {
        var isOn = false
        var recipients = BusinessRecipients()
        var inactivityDays = 7
        var schedule = Schedule.always
        var start: Date?
        var end: Date?
        var offlineOnly = false
    }

    private static let inactivityValues = [7, 14, 21, 28]

    private let kind: Kind
    private var loaded: Draft?
    private var draft = Draft()
    private var cancellable: AnyCancellable?
    private lazy var recipientsEditor: BusinessRecipientsEditor = {
        let footer = kind == .greeting
            ? "BusinessMessageSetup.Recipients.GreetingMessageFooter"
            : "BusinessMessageSetup.Recipients.AwayMessageFooter"
        let editor = BusinessRecipientsEditor(
            screen: self,
            header: L10n.telegram("BusinessMessageSetup.RecipientsSectionHeader"),
            includedFooter: L10n.telegram(footer),
            excludedFooter: L10n.telegram(footer),
            listsExcludedPeople: false,
        )
        editor.onChange = { [weak self, weak editor] in
            guard let self, let editor else { return }
            draft.recipients = editor.recipients
            reload()
        }
        return editor
    }()

    private var shortcut: TDNativeQuickReplyShortcut? {
        QuickReplyStore.shared
            .shortcuts(for: TDLib.shared.activeUpdateSource)
            .first { $0.name == kind.shortcutName }
    }

    private var messageTitle: String {
        L10n.telegram(kind == .greeting
            ? "BusinessMessageSetup.TitleGreetingMessage"
            : "BusinessMessageSetup.TitleAwayMessage")
    }

    /// The shortcut's first message (and how many follow), or Create a Greeting Message.
    private var messageRow: SettingsRow {
        guard let shortcut else {
            return SettingsRow(
                title: L10n.telegram(kind == .greeting
                    ? "BusinessMessageSetup.CreateGreetingMessage"
                    : "BusinessMessageSetup.CreateAwayMessage"),
                style: .action(destructive: false),
                symbol: "plus.bubble",
            ) { [weak self] in self?.openMessage() }
        }
        let more = shortcut.messageCount > 1 ? " · +\(shortcut.messageCount - 1)" : ""
        return SettingsRow(
            title: QuickReplyStore.preview(shortcut.firstMessage.content) + more,
            accessory: .disclosure,
        ) { [weak self] in self?.openMessage() }
    }

    private var scheduleSection: SettingsSection {
        var rows = [
            scheduleRow("BusinessMessageSetup.ScheduleAlways", .always),
            scheduleRow("BusinessMessageSetup.ScheduleOutsideBusinessHours", .outsideBusinessHours),
            scheduleRow("BusinessMessageSetup.ScheduleCustom", .custom),
        ]
        if draft.schedule == .custom {
            rows.append(dateRow("BusinessMessageSetup.ScheduleStartTime", date: draft.start) { [weak self] date in
                self?.draft.start = date
            })
            rows.append(dateRow("BusinessMessageSetup.ScheduleEndTime", date: draft.end) { [weak self] date in
                self?.draft.end = date
            })
        }
        return SettingsSection(header: L10n.telegram("BusinessMessageSetup.ScheduleSectionHeader"), rows: rows)
    }

    // MARK: Saving

    /// The reason a draft can't be saved: no recipients, or a custom schedule that is missing or ends first.
    private var problem: String? {
        if draft.recipients.reachesNobody {
            return L10n.telegram("BusinessMessageSetup.ErrorNoRecipients.Text")
        }
        guard kind == .away, draft.schedule == .custom else { return nil }
        switch (draft.start, draft.end) {
        case (nil, nil): return L10n.telegram("BusinessMessageSetup.ErrorScheduleTimeMissing.Text")
        case (nil, _): return L10n.telegram("BusinessMessageSetup.ErrorScheduleStartTimeMissing.Text")
        case (_, nil): return L10n.telegram("BusinessMessageSetup.ErrorScheduleEndTimeMissing.Text")
        case (let start?, let end?) where start >= end:
            return L10n.telegram("BusinessMessageSetup.ErrorScheduleEndTimeBeforeStartTime.Text")
        default: return nil
        }
    }

    init(kind: Kind) {
        self.kind = kind
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = messageTitle
        cancellable = QuickReplyStore.shared
            .changes
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.reload() }
        load()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isLeavingNavigation else { return }
        save()
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [SettingsSection(
            header: L10n.telegram(kind == .greeting
                ? "BusinessMessageSetup.TextGreetingMessage"
                : "BusinessMessageSetup.TextAwayMessage"),
            rows: [SettingsRow(
                title: L10n.telegram(kind == .greeting
                    ? "BusinessMessageSetup.ToggleGreetingMessage"
                    : "BusinessMessageSetup.ToggleAwayMessage"),
                accessory: .toggle(isOn: draft.isOn) { [weak self] isOn in
                    self?.draft.isOn = isOn
                    self?.reload()
                },
                isEnabled: loaded != nil,
            )],
        )]
        guard draft.isOn else { return sections }
        sections.append(SettingsSection(
            header: L10n.telegram(kind == .greeting
                ? "BusinessMessageSetup.GreetingMessageSectionHeader"
                : "BusinessMessageSetup.AwayMessageSectionHeader"),
            rows: [messageRow],
        ))
        if kind == .away {
            sections.append(scheduleSection)
            sections.append(SettingsSection(
                footer: L10n.telegram("BusinessMessageSetup.SendWhenOfflineFooter"),
                rows: [SettingsRow(
                    title: L10n.telegram("BusinessMessageSetup.SendWhenOffline"),
                    accessory: .toggle(isOn: draft.offlineOnly) { [weak self] isOn in
                        self?.draft.offlineOnly = isOn
                    },
                )],
            ))
        }
        sections += recipientsEditor.sections(at: sections.count)
        if kind == .greeting {
            sections.append(SettingsSection(
                header: L10n.telegram("BusinessMessageSetup.InactivitySectionHeader"),
                footer: L10n.telegram("BusinessMessageSetup.InactivitySectionFooter"),
                rows: Self.inactivityValues.map { days in
                    SettingsRow(
                        title: L10n.telegramPlural("MessageTimer.Days", count: days),
                        accessory: draft.inactivityDays == days ? .checkmark : .none,
                    ) { [weak self] in
                        self?.draft.inactivityDays = days
                        self?.reload()
                    }
                },
            ))
        }
        return sections
    }

    private func load() {
        let client = client
        let kind = kind
        Task { [weak self] in
            _ = try? await client.send(TDNativeRequests.loadQuickReplyShortcuts())
            var draft = Draft()
            if let me = try? await client.getMe(),
               let info = try? await client.getUserFullInfo(userId: me.id).businessInfo
            {
                switch kind {
                case .greeting:
                    if let settings = info.greetingMessageSettings {
                        draft.isOn = true
                        draft.recipients = BusinessRecipients(settings.recipients)
                        draft.inactivityDays = settings.inactivityDays
                    }
                case .away:
                    if let settings = info.awayMessageSettings {
                        draft.isOn = true
                        draft.recipients = BusinessRecipients(settings.recipients)
                        draft.offlineOnly = settings.offlineOnly
                        switch settings.schedule {
                        case .businessAwayMessageScheduleAlways:
                            draft.schedule = .always
                        case .businessAwayMessageScheduleOutsideOfOpeningHours:
                            draft.schedule = .outsideBusinessHours
                        case .businessAwayMessageScheduleCustom(let custom):
                            draft.schedule = .custom
                            draft.start = Date(timeIntervalSince1970: TimeInterval(custom.startDate))
                            draft.end = Date(timeIntervalSince1970: TimeInterval(custom.endDate))
                        }
                    }
                }
            }
            guard let self, contextIsCurrent else { return }
            loaded = draft
            self.draft = draft
            recipientsEditor.recipients = draft.recipients
            reload()
        }
    }

    private func scheduleRow(_ key: String, _ schedule: Schedule) -> SettingsRow {
        SettingsRow(
            title: L10n.telegram(key),
            accessory: draft.schedule == schedule ? .checkmark : .none,
        ) { [weak self] in
            guard let self, draft.schedule != schedule else { return }
            draft.schedule = schedule
            reload()
        }
    }

    /// A start or end time with the system's compact date and time picker, or Set until one is chosen.
    private func dateRow(_ key: String, date: Date?, onChange: @escaping (Date) -> Void) -> SettingsRow {
        SettingsRow(title: L10n.telegram(key), trailingView: SettingsTrailingView {
            let picker = UIDatePicker()
            picker.datePickerMode = .dateAndTime
            picker.preferredDatePickerStyle = .compact
            picker.date = date ?? Date()
            if date == nil { onChange(picker.date) }
            picker.addAction(UIAction { [weak picker] _ in
                guard let picker else { return }
                onChange(picker.date)
            }, for: .valueChanged)
            return picker
        })
    }

    private func openMessage() {
        navigationController?.pushViewController(
            QuickReplyEditViewController(name: kind.shortcutName, shortcutID: shortcut?.id, displayTitle: messageTitle),
            animated: true,
        )
    }

    private func save() {
        // Choices made while the message stays off change nothing.
        guard let loaded, draft != loaded, draft.isOn || loaded.isOn else { return }
        let draft = draft
        let kind = kind
        let shortcutID = shortcut?.id
        if draft.isOn {
            // Telegram asks to reset; leaving here already happened, so nothing is saved and the reason shows.
            if let problem, let container = navigationController?.view {
                TelegramUndoToast.show(text: problem, in: container, bottomInset: 12, undo: nil)
                return
            }
            guard shortcutID != nil else { return }
        }
        let client = client
        Task {
            await BusinessRecipients.prepareChats(draft.recipients.peerIDs, client: client)
            let recipients = draft.recipients.native
            switch kind {
            case .greeting:
                let settings = draft.isOn
                    ? shortcutID.map { id in
                        TDNativeBusinessGreetingMessageSettings(
                            shortcutId: id,
                            recipients: recipients,
                            inactivityDays: draft.inactivityDays,
                        )
                    }
                    : nil
                _ = try? await client.send(TDNativeRequests.setBusinessGreetingMessageSettings(
                    greetingMessageSettings: settings,
                ))
            case .away:
                let schedule: TDNativeBusinessAwayMessageSchedule =
                    switch draft.schedule {
                    case .always:
                        .businessAwayMessageScheduleAlways
                    case .outsideBusinessHours:
                        .businessAwayMessageScheduleOutsideOfOpeningHours
                    case .custom:
                        .businessAwayMessageScheduleCustom(TDNativeBusinessAwayMessageScheduleCustom(
                            startDate: Int(draft.start?.timeIntervalSince1970 ?? 0),
                            endDate: Int(draft.end?.timeIntervalSince1970 ?? 0),
                        ))
                    }
                let settings = draft.isOn
                    ? shortcutID.map { id in
                        TDNativeBusinessAwayMessageSettings(
                            shortcutId: id,
                            recipients: recipients,
                            schedule: schedule,
                            offlineOnly: draft.offlineOnly,
                        )
                    }
                    : nil
                _ = try? await client.send(TDNativeRequests.setBusinessAwayMessageSettings(
                    awayMessageSettings: settings,
                ))
            }
        }
    }
}
