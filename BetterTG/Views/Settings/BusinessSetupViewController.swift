// BusinessSetupViewController.swift

import TDLibKit
import UIKit

// MARK: - BusinessSetupViewController

/// PremiumIntroScreen in its business mode for a Premium account: Telegram Business with what it unlocks, the
/// features BetterTG sets up (Location, Opening Hours, Intro), MORE BUSINESS FEATURES (Set Emoji Status, Tag Your
/// Chats), and ADS IN CHANNELS' Do Not Hide Ads (toggleHasSponsoredMessagesEnabled).
final class BusinessSetupViewController: SettingsListViewController {
    private var me: User?
    private var info: TDNativeBusinessInfo?
    private var showsAds: Bool?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Business.Title")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        load()
    }

    override func makeSections() -> [SettingsSection] {
        [
            SettingsSection(
                footer: L10n.telegram("Business.SubscribedDescription").withoutTelegramMarkup,
                rows: [
                    feature(
                        "Business.Location",
                        "Business.LocationInfo",
                        symbol: "mappin.and.ellipse",
                        tint: .systemRed,
                    ) {
                        [weak self] in self?.openLocation()
                    },
                    feature(
                        "Business.OpeningHours",
                        "Business.OpeningHoursInfo",
                        symbol: "clock",
                        tint: .systemOrange,
                    ) {
                        [weak self] in self?.openHours()
                    },
                    feature(
                        "Business.QuickReplies",
                        "Business.QuickRepliesInfo",
                        symbol: "bubble.left.and.text.bubble.right",
                        tint: .systemGreen,
                    ) {
                        [weak self] in
                        self?.navigationController?.pushViewController(QuickRepliesViewController(), animated: true)
                    },
                    feature(
                        "Business.GreetingMessages",
                        "Business.GreetingMessagesInfo",
                        symbol: "hand.raised",
                        tint: .systemYellow,
                    ) {
                        [weak self] in
                        self?.navigationController?.pushViewController(
                            BusinessMessageViewController(kind: .greeting),
                            animated: true,
                        )
                    },
                    feature("Business.AwayMessages", "Business.AwayMessagesInfo", symbol: "moon", tint: .systemPurple) {
                        [weak self] in
                        self?.navigationController?.pushViewController(
                            BusinessMessageViewController(kind: .away),
                            animated: true,
                        )
                    },
                    feature("Business.Links", "Business.LinksInfo", symbol: "link", tint: .systemBlue) {
                        [weak self] in
                        self?.navigationController?.pushViewController(
                            BusinessLinksViewController(me: self?.me),
                            animated: true,
                        )
                    },
                    feature("Business.Intro", "Business.IntroInfo", symbol: "hand.wave", tint: .systemPink) {
                        [weak self] in self?.openIntro()
                    },
                    feature("Business.ChatbotsItem", "Business.ChatbotsInfo", symbol: "cpu", tint: .systemIndigo) {
                        [weak self] in
                        self?.navigationController?.pushViewController(ChatbotSetupViewController(), animated: true)
                    },
                ],
            ),
            SettingsSection(
                header: L10n.telegram("Business.MoreFeaturesTitle"),
                footer: L10n.telegram("Business.MoreFeaturesInfo"),
                rows: [
                    feature(
                        "Business.SetEmojiStatus",
                        "Business.SetEmojiStatusInfo",
                        symbol: "face.smiling",
                        tint: .systemBlue,
                    ) {
                        [weak self] in self?.openEmojiStatus()
                    },
                    feature("Business.TagYourChats", "Business.TagYourChatsInfo", symbol: "tag", tint: .systemCyan) {
                        [weak self] in
                        self?.navigationController?.pushViewController(
                            ChatFoldersViewController(rootVM: RootVM.shared),
                            animated: true,
                        )
                    },
                ],
            ),
            SettingsSection(
                header: L10n.telegram("Business.AdsTitle"),
                footer: L10n.telegram("Business.AdsInfo").withoutTelegramLinks,
                rows: [SettingsRow(
                    title: L10n.telegram("Business.DontHideAds"),
                    accessory: .toggle(isOn: showsAds ?? false) { [weak self] isOn in self?.setShowsAds(isOn) },
                    isEnabled: showsAds != nil,
                )],
            ),
        ]
    }

    private func feature(
        _ title: String,
        _ detail: String,
        symbol: String,
        tint: UIColor,
        action: @escaping () -> Void,
    ) -> SettingsRow {
        SettingsRow(
            title: L10n.telegram(title),
            detail: L10n.telegram(detail),
            style: .subtitle,
            symbol: symbol,
            symbolTint: tint,
            accessory: .disclosure,
            action: action,
        )
    }

    private func load() {
        let client = client
        Task { [weak self] in
            guard let me = try? await client.getMe() else { return }
            let full = try? await client.getUserFullInfo(userId: me.id)
            guard let self, contextIsCurrent else { return }
            self.me = me
            info = full?.businessInfo
            showsAds = full?.hasSponsoredMessagesEnabled
            reload()
        }
    }

    private func setShowsAds(_ isOn: Bool) {
        showsAds = isOn
        perform { client in
            _ = try await client.send(TDNativeRequests.toggleHasSponsoredMessagesEnabled(
                hasSponsoredMessagesEnabled: isOn,
            ))
        }
    }

    private func openLocation() {
        navigationController?.pushViewController(
            BusinessLocationViewController(location: info?.location, accountChatID: me?.id ?? 0),
            animated: true,
        )
    }

    private func openHours() {
        navigationController?.pushViewController(BusinessHoursViewController(hours: info?.openingHours), animated: true)
    }

    private func openIntro() {
        navigationController?.pushViewController(
            BusinessIntroViewController(startPage: info?.startPage),
            animated: true,
        )
    }

    private func openEmojiStatus() {
        guard let me else { return }
        let currentID: Int64? =
            if case .emojiStatusTypeCustomEmoji(let status)? = me.emojiStatus?.type {
                status.customEmojiId
            } else {
                nil
            }
        present(
            EmojiStatusPickerViewController(
                client: client,
                currentEmojiID: currentID,
                hasStatus: me.emojiStatus != nil,
            ),
            animated: true,
        )
    }
}

// MARK: - BusinessLocationViewController

/// BusinessLocationSetupScreen: the address shown on the account (setBusinessLocation), Delete Location while one is
/// set, and the unsaved changes' question when leaving. Choosing a point on the map isn't offered.
final class BusinessLocationViewController: SettingsListViewController {
    private let original: String
    private var address: String
    /// BusinessLocationSetupScreen's map pin, kept with the address.
    private var coordinate: TDNativeLocation?
    /// The account's own chat, where the map's venue search asks from.
    private let accountChatID: Int64

    init(location: TDNativeBusinessLocation?, accountChatID: Int64) {
        self.original = location?.address ?? ""
        self.address = original
        self.coordinate = location?.location
        self.accountChatID = accountChatID
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("BusinessLocationSetup.Title")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Done"),
            primaryAction: UIAction { [weak self] _ in self?.save() },
        )
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [SettingsSection(
            footer: L10n.telegram("BusinessLocationSetup.Text"),
            rows: [SettingsRow(title: "", style: .input(SettingsTextInput(
                text: address,
                placeholder: L10n.telegram("BusinessLocationSetup.AddressPlaceholder"),
                maxLength: 96,
                isMultiline: true,
            ) { [weak self] text in self?.address = text }))],
        )]
        sections.append(SettingsSection(rows: [SettingsRow(
            title: L10n.telegram("BusinessLocationSetup.SetLocationOnMap"),
            detail: coordinate.map { String(format: "%.5f, %.5f", $0.latitude, $0.longitude) },
            style: .subtitle,
            accessory: .toggle(isOn: coordinate != nil) { [weak self] isOn in
                guard let self else { return }
                if isOn {
                    pickCoordinate()
                } else {
                    coordinate = nil
                    reload()
                }
            },
        )]))
        if !original.isEmpty {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("BusinessLocationSetup.DeleteLocation"),
                style: .action(destructive: true),
            ) { [weak self] in
                self?.address = ""
                self?.coordinate = nil
                self?.save()
            }]))
        }
        return sections
    }

    /// LocationPickerController in its pick mode: the pin or place chosen on the map, whose address fills an empty
    /// field.
    private func pickCoordinate() {
        let picker = LocationPickerViewController(
            peerName: nil,
            allowsLiveLocation: false,
            client: client,
            chatID: accountChatID,
        ) { [weak self] content in
            guard let self else { return }
            switch content {
            case .inputMessageLocation(let location):
                coordinate = location.location
            case .inputMessageVenue(let venue):
                coordinate = venue.venue.location
                if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    address = [venue.venue.title, venue.venue.address].filter { !$0.isEmpty }.joined(separator: ", ")
                }
            default:
                break
            }
            reload()
        }
        picker.isPicking = true
        // A picker closed without a choice leaves the switch off.
        picker.onDismiss = { [weak self] in self?.reload() }
        present(UINavigationController(rootViewController: picker), animated: true)
    }

    private func save() {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let location: TDNativeBusinessLocation? = address.isEmpty
            ? nil
            : TDNativeBusinessLocation(location: coordinate, address: address)
        perform { client in
            _ = try await client.send(TDNativeRequests.setBusinessLocation(location: location))
        } completion: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }
}

// MARK: - BusinessIntroViewController

/// BusinessIntroSetupScreen without its sticker: the title and text people see in an empty chat with the account
/// (setBusinessStartPage), the empty chat's defaults as placeholders, and Reset to Default.
final class BusinessIntroViewController: SettingsListViewController {
    private var titleText: String
    private var message: String
    private let hadIntro: Bool

    init(startPage: TDNativeBusinessStartPage?) {
        self.titleText = startPage?.title ?? ""
        self.message = startPage?.message ?? ""
        self.hadIntro = startPage != nil
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Business.Intro.Title")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Done"),
            primaryAction: UIAction { [weak self] _ in self?.save() },
        )
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [SettingsSection(
            header: L10n.telegram("Business.Intro.CustomizeSectionHeader"),
            footer: L10n.telegram("Business.Intro.CustomizeSectionFooter"),
            rows: [
                SettingsRow(title: "", style: .input(SettingsTextInput(
                    text: titleText,
                    placeholder: L10n.telegram("Conversation.EmptyPlaceholder"),
                    maxLength: 32,
                ) { [weak self] text in self?.titleText = text })),
                SettingsRow(title: "", style: .input(SettingsTextInput(
                    text: message,
                    placeholder: L10n.telegram("Conversation.GreetingText"),
                    maxLength: 70,
                    isMultiline: true,
                ) { [weak self] text in self?.message = text })),
            ],
        )]
        if hadIntro {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("Business.Intro.ResetToDefault"),
                style: .action(destructive: true),
            ) { [weak self] in
                self?.titleText = ""
                self?.message = ""
                self?.save()
            }]))
        }
        return sections
    }

    private func save() {
        let title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let page: TDNativeInputBusinessStartPage? = title.isEmpty && message.isEmpty
            ? nil
            : TDNativeInputBusinessStartPage(title: title, message: message, sticker: nil)
        perform { client in
            _ = try await client.send(TDNativeRequests.setBusinessStartPage(startPage: page))
        } completion: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }
}

// MARK: - BusinessHoursViewController

/// BusinessHoursSetupScreen: Show Business Hours, then each weekday as Open 24 Hours, Closed or its hours, and the
/// time zone (getTimeZones); a day opens its own screen. Done saves the week (setBusinessOpeningHours), or clears it
/// when the switch is off.
final class BusinessHoursViewController: SettingsListViewController {
    typealias Interval = (start: Int, end: Int)

    private static let dayMinutes = 24 * 60

    /// Monday first, in the app's language.
    static var weekdayNames: [String] {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: MessageTranslation.appLanguageCode)
        let symbols = calendar.standaloneWeekdaySymbols.map(\.localizedCapitalized)
        return Array(symbols[1...]) + [symbols[0]]
    }

    private var isEnabled: Bool
    /// The intervals of each day, Monday first, in minutes from the day's start.
    private var days: [[Interval]]
    private var timeZoneID: String
    private var timeZones = [TDNativeTimeZone]()

    init(hours: TDNativeBusinessOpeningHours?) {
        self.isEnabled = hours != nil
        self.timeZoneID = hours?.timeZoneId ?? Foundation.TimeZone.current.identifier
        var days = Array(repeating: [Interval](), count: 7)
        for interval in hours?.openingHours ?? [] {
            let day = min(6, interval.startMinute / Self.dayMinutes)
            let start = interval.startMinute - day * Self.dayMinutes
            days[day].append((start, min(interval.endMinute - day * Self.dayMinutes, 2 * Self.dayMinutes)))
        }
        self.days = days
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("BusinessHoursSetup.Title")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Done"),
            primaryAction: UIAction { [weak self] _ in self?.save() },
        )
        let client = client
        Task { [weak self] in
            let zones = await (try? client.send(TDNativeRequests.getTimeZones()))?.timeZones ?? []
            self?.timeZones = zones
            self?.reload()
        }
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [SettingsSection(
            footer: L10n.telegram("BusinessHoursSetup.Text"),
            rows: [SettingsRow(
                title: L10n.telegram("BusinessHoursSetup.MainToggle"),
                accessory: .toggle(isOn: isEnabled) { [weak self] isOn in self?.setEnabled(isOn) },
            )],
        )]
        guard isEnabled else { return sections }
        let names = Self.weekdayNames
        sections.append(SettingsSection(
            header: L10n.telegram("BusinessHoursSetup.DaysSectionTitle"),
            rows: (0..<7).map { day in
                SettingsRow(
                    title: names[day],
                    detail: Self.summary(days[day]),
                    style: .subtitle,
                    accessory: .disclosure,
                ) { [weak self] in self?.openDay(day) }
            },
        ))
        let zoneName = timeZones.first { $0.id == timeZoneID }?.name ?? timeZoneID
        sections.append(SettingsSection(rows: [SettingsRow(
            title: L10n.telegram("BusinessHoursSetup.TimeZone"),
            detail: zoneName,
            accessory: .disclosure,
        ) { [weak self] in self?.chooseTimeZone() }]))
        return sections
    }

    /// Open 24 Hours, Closed, or the intervals' times.
    static func summary(_ intervals: [Interval]) -> String {
        if intervals.isEmpty { return L10n.telegram("BusinessHoursSetup.DayClosed") }
        if intervals.count == 1, intervals[0].start == 0, intervals[0].end >= dayMinutes {
            return L10n.telegram("BusinessHoursSetup.DayOpen24h")
        }
        return intervals.map { "\(time($0.start)) – \(time($0.end))" }.joined(separator: ", ")
    }

    static func time(_ minutes: Int) -> String {
        let date = Calendar.current.date(
            from: DateComponents(hour: (minutes / 60) % 24, minute: minutes % 60),
        ) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func setEnabled(_ isOn: Bool) {
        isEnabled = isOn
        // A week switched on starts open around the clock, as the screen's default.
        if isOn, days.allSatisfy(\.isEmpty) {
            days = Array(repeating: [(0, Self.dayMinutes)], count: 7)
        }
        reload()
    }

    private func openDay(_ day: Int) {
        let controller = BusinessHoursDayViewController(title: Self.weekdayNames[day], intervals: days[day])
        controller.onChange = { [weak self] intervals in
            self?.days[day] = intervals
            self?.reload()
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    /// TimezoneSelectionScreen: every zone TDLib knows, searchable, the chosen one checked.
    private func chooseTimeZone() {
        let picker = BusinessTimeZonePickerViewController(zones: timeZones, selectedID: timeZoneID)
        picker.onSelect = { [weak self] id in
            self?.timeZoneID = id
            self?.reload()
            self?.navigationController?.popViewController(animated: true)
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    private func save() {
        let hours: TDNativeBusinessOpeningHours? =
            if isEnabled {
                TDNativeBusinessOpeningHours(
                    timeZoneId: timeZoneID,
                    openingHours: days.enumerated().flatMap { day, intervals in
                        intervals.map { interval in
                            TDNativeBusinessOpeningHoursInterval(
                                startMinute: day * Self.dayMinutes + interval.start,
                                endMinute: day * Self.dayMinutes + interval.end,
                            )
                        }
                    },
                )
            } else {
                nil
            }
        perform { client in
            _ = try await client.send(TDNativeRequests.setBusinessOpeningHours(openingHours: hours))
        } completion: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }
}

// MARK: - BusinessHoursDayViewController

/// BusinessDaySetupScreen: Open On This Day, then each set of hours with its opening and closing times and Remove,
/// and Add a Set of Hours.
final class BusinessHoursDayViewController: SettingsListViewController {
    var onChange: (([BusinessHoursViewController.Interval]) -> Void)?

    private var intervals: [BusinessHoursViewController.Interval]

    init(title: String, intervals: [BusinessHoursViewController.Interval]) {
        self.intervals = intervals
        super.init()
        self.title = title
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [SettingsSection(rows: [SettingsRow(
            title: L10n.telegram("BusinessHoursSetup.DaySwitch"),
            accessory: .toggle(isOn: !intervals.isEmpty) { [weak self] isOn in
                guard let self else { return }
                intervals = isOn ? [(0, 24 * 60)] : []
                changed()
            },
        )])]
        for index in intervals.indices {
            sections.append(SettingsSection(rows: [
                timeRow("BusinessHoursSetup.DayIntervalStart", minutes: intervals[index].start) { [weak self] value in
                    self?.intervals[index].start = value
                    self?.onChange?(self?.intervals ?? [])
                },
                timeRow("BusinessHoursSetup.DayIntervalEnd", minutes: intervals[index].end) { [weak self] value in
                    self?.intervals[index].end = value == 0 ? 24 * 60 : value
                    self?.onChange?(self?.intervals ?? [])
                },
                SettingsRow(
                    title: L10n.telegram("BusinessHoursSetup.DayIntervalRemove"),
                    style: .action(destructive: true),
                ) { [weak self] in
                    self?.intervals.remove(at: index)
                    self?.changed()
                },
            ]))
        }
        if !intervals.isEmpty {
            sections.append(SettingsSection(
                footer: L10n.telegram("BusinessHoursSetup.AddSectionFooter"),
                rows: [SettingsRow(
                    title: L10n.telegram("BusinessHoursSetup.AddAction"),
                    style: .action(destructive: false),
                ) { [weak self] in
                    guard let self else { return }
                    let start = min((intervals.last?.end ?? 0) + 60, 23 * 60)
                    intervals.append((start, min(start + 60, 24 * 60)))
                    changed()
                }],
            ))
        }
        return sections
    }

    /// A time row with the system's compact time picker.
    private func timeRow(_ key: String, minutes: Int, onChange: @escaping (Int) -> Void) -> SettingsRow {
        SettingsRow(title: L10n.telegram(key), trailingView: SettingsTrailingView {
            let picker = UIDatePicker()
            picker.datePickerMode = .time
            picker.preferredDatePickerStyle = .compact
            picker.date = Calendar.current.date(
                from: DateComponents(hour: (minutes / 60) % 24, minute: minutes % 60),
            ) ?? Date()
            picker.addAction(UIAction { [weak picker] _ in
                guard let picker else { return }
                let parts = Calendar.current.dateComponents([.hour, .minute], from: picker.date)
                onChange((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            }, for: .valueChanged)
            return picker
        })
    }

    private func changed() {
        onChange?(intervals)
        reload()
    }
}

// MARK: - BusinessTimeZonePickerViewController

/// TimezoneSelectionScreen: the time zones from getTimeZones by UTC offset, each with its offset, filtered by the
/// search
/// field; a tap picks one.
final class BusinessTimeZonePickerViewController: SettingsListViewController, TelegramNavigationSearchProvider,
UISearchResultsUpdating {
    let telegramNavigationSearch = UISearchController(searchResultsController: nil)
    var onSelect: ((String) -> Void)?

    private let zones: [TDNativeTimeZone]
    private let selectedID: String
    private var query = ""

    init(zones: [TDNativeTimeZone], selectedID: String) {
        self.zones = zones.sorted { ($0.utcTimeOffset, $0.name) < ($1.utcTimeOffset, $1.name) }
        self.selectedID = selectedID
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("BusinessHoursSetup.TimeZone")
        telegramNavigationSearch.obscuresBackgroundDuringPresentation = false
        telegramNavigationSearch.searchResultsUpdater = self
        telegramNavigationSearch.searchBar.placeholder = L10n.telegram("Common.Search")
    }

    override func makeSections() -> [SettingsSection] {
        let normalized = query.trimmingCharacters(in: .whitespaces)
        let shown = normalized.isEmpty
            ? zones
            : zones.filter { $0.name.localizedCaseInsensitiveContains(normalized) }
        return [SettingsSection(rows: shown.map { zone in
            SettingsRow(
                title: zone.name,
                detail: Self.offsetText(zone.utcTimeOffset),
                accessory: zone.id == selectedID ? .checkmark : .none,
            ) { [weak self] in self?.onSelect?(zone.id) }
        })]
    }

    /// TimezoneListEntry's label: UTC +3, UTC -5:30.
    static func offsetText(_ seconds: Int) -> String {
        let sign = seconds >= 0 ? "+" : "-"
        let hours = abs(seconds) / 3600
        let minutes = abs(seconds) % 3600 / 60
        return minutes == 0 ? "UTC \(sign)\(hours)" : String(format: "UTC %@%d:%02d", sign, hours, minutes)
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        reload()
    }
}
