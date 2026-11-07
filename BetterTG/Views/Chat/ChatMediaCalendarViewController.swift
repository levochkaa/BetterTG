// ChatMediaCalendarViewController.swift

import TDLibKit
import UIKit

// MARK: - ChatMediaCalendarViewController

/// Telegram's CalendarMessageScreen for a chat, opened from a date header: the chat's months from the newest at the
/// bottom, each a seven-column grid of days, where a day with photos or videos shows the first one in its circle
/// (the sparse calendar of getChatMessageCalendar, loaded page by page), today is in the accent and days to come are
/// dimmed. A day opens the chat at its first message, an empty one too, as in the chat's calendar. TDLib has no such
/// calendar for a forum topic or a message thread, whose days stay plain. With `onClearRange` (a private chat's
/// enableMessageRangeDeletion) Select picks a day, a range or a month whose history the bottom button clears.
final class ChatMediaCalendarViewController: UIViewController, UIScrollViewDelegate {
    private static let monthSpacing: CGFloat = 16

    /// CalendarMessageScreen's `previewDay`: holding a day opens a preview of the chat there, with the menu the opener
    /// gives for it. It gets the day and its first photo or video, if any, and may look the day's message up first; nil
    /// leaves the day without a preview (Shared Media's empty days).
    var previewDay: (@MainActor (Date, Message?) async -> (
        preview: UIViewController,
        actions: [TelegramContextMenuAction],
    )?)?

    /// CalendarMessageScreen's completedWithRemoveMessagesInRange, asked from its selection toolbar: the selected days
    /// and their count; the opener asks how to clear them. Nil leaves out Select.
    var onClearRange: ((ClosedRange<Date>, Int) -> Void)?

    private var previewTask: Task<Void, Never>?

    /// SelectionState: nil outside Select, then the selected days, if any.
    private var isSelecting = false
    private var selectedDays: ClosedRange<Date>?
    private let selectionToolbar = ChatCalendarSelectionToolbar()

    private let chatID: Int64
    private let topic: MessageTopic?
    private let client: TDLibClient
    private let initialDate: Date
    private let onSelectDay: (Date) -> Void
    /// The media the circles show: photos and videos, or one kind, as Shared Media's pane shows them.
    private let filter: SearchMessagesFilter
    /// CalendarMessageScreen's `canNavigateToEmptyDays`: the chat's calendar opens any past day, Shared Media's only
    /// a day with media.
    private let selectsEmptyDays: Bool
    private let scrollView = ChatCalendarScrollView()
    private let calendar = Calendar.current
    private var months = [ChatCalendarMonth]()
    private var monthFrames = [CGRect]()
    private var monthViews = [Int: ChatCalendarMonthView]()
    private var laidOutSize = CGSize.zero
    private var laidOutInsets = UIEdgeInsets.zero
    /// The first photo or video of each day, by the day's start.
    private var mediaByDay = [Date: Message]()
    private var loadTask: Task<Void, Never>?

    /// The selected days that have come, as the toolbar counts them.
    private var selectedCount: Int {
        guard let selectedDays else { return 0 }
        let today = calendar.startOfDay(for: Date())
        let last = min(selectedDays.upperBound, today)
        guard last >= selectedDays.lowerBound else { return 0 }
        return (calendar.dateComponents([.day], from: selectedDays.lowerBound, to: last).day ?? 0) + 1
    }

    init(
        chatID: Int64,
        topic: MessageTopic?,
        client: TDLibClient,
        initialDate: Date,
        filter: SearchMessagesFilter = .searchMessagesFilterPhotoAndVideo,
        selectsEmptyDays: Bool = true,
        onSelectDay: @escaping (Date) -> Void,
    ) {
        self.filter = filter
        self.selectsEmptyDays = selectsEmptyDays
        self.chatID = chatID
        self.topic = topic
        self.client = client
        self.initialDate = min(initialDate, Date())
        self.onSelectDay = onSelectDay
        super.init(nibName: nil, bundle: nil)
        self.months = Self.months(calendar: calendar, oldest: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = L10n.telegram("MessageCalendar.Title")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) },
        )
        // The newest month sits at the bottom: the scroll view is turned upside down and each month back, so older
        // months add to the far end without moving the visible ones.
        scrollView.transform = CGAffineTransform(rotationAngle: .pi)
        // The bars' edge effects would cover the turned content, as in the chat's inverted history.
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.scrollsToTop = false
        scrollView.delegate = self
        view.addSubview(scrollView)
        selectionToolbar.isHidden = true
        selectionToolbar.button.addAction(UIAction { [weak self] _ in self?.clearSelected() }, for: .touchUpInside)
        view.addSubview(selectionToolbar)
        updateSelectionChrome()
        load()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        // ToolbarNode: 49 pt over the bottom inset, 34 pt beside a side inset. The months keep clear of it through
        // the additional inset, which the toolbar itself leaves out.
        let systemBottom = view.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom
        let contentHeight: CGFloat = view.safeAreaInsets.left > 0 || view.safeAreaInsets.right > 0 ? 34 : 49
        selectionToolbar.contentHeight = contentHeight
        selectionToolbar.frame = CGRect(
            x: 0,
            y: view.bounds.height - contentHeight - systemBottom,
            width: view.bounds.width,
            height: contentHeight + systemBottom,
        )
        guard view.bounds.size != laidOutSize || view.safeAreaInsets != laidOutInsets else { return }
        let isFirstLayout = laidOutSize == .zero
        laidOutSize = view.bounds.size
        laidOutInsets = view.safeAreaInsets
        layoutMonths()
        if isFirstLayout { scrollToInitialMonth() }
        updateMonthViews()
    }

    // MARK: Layout

    /// CalendarMessageScreen's months: from this one back to the oldest message's, and to Telegram's August 2013
    /// before that is known.
    private static func months(calendar: Calendar, oldest: Date?) -> [ChatCalendarMonth] {
        let now = Date()
        guard let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return []
        }
        let floor = calendar.date(from: DateComponents(year: 2013, month: 8)) ?? currentMonth
        let oldestMonth = oldest.flatMap { calendar.date(from: calendar.dateComponents([.year, .month], from: $0)) }
        var result = [ChatCalendarMonth]()
        var month = currentMonth
        while month >= floor, month >= (oldestMonth ?? floor) {
            if let model = ChatCalendarMonth(firstDay: month, calendar: calendar, now: now) { result.append(model) }
            guard let previous = calendar.date(byAdding: .month, value: -1, to: month) else { break }
            month = previous
        }
        return result
    }

    func scrollViewDidScroll(_: UIScrollView) {
        updateMonthViews()
    }

    /// The day preview's Select: selection with that day.
    func selectDay(_ day: Date) {
        isSelecting = true
        let start = calendar.startOfDay(for: day)
        selectedDays = selectedDays == start...start ? nil : start...start
        updateSelectionChrome()
        updateMonthViews()
    }

    /// The day preview's Clear History: that day, straight to the question.
    func openClearHistory(_ day: Date) {
        let start = calendar.startOfDay(for: day)
        selectedDays = start...start
        clearSelected()
    }

    private func layoutMonths() {
        let width = view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right
        var height = view.safeAreaInsets.bottom
        monthFrames = months.map { month in
            let monthHeight = ChatCalendarMonthView.height(for: month, width: width)
            // The turned scroll view runs x from the right edge.
            let frame = CGRect(x: view.safeAreaInsets.right, y: height, width: width, height: monthHeight)
            height += monthHeight + Self.monthSpacing
            return frame
        }
        height += view.safeAreaInsets.top
        scrollView.contentSize = CGSize(width: view.bounds.width, height: height)
        // The indicator keeps to the visible right edge.
        scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(
            top: view.safeAreaInsets.bottom,
            left: 0,
            bottom: view.safeAreaInsets.top,
            right: view.bounds.width - 9,
        )
        for (index, monthView) in monthViews {
            guard monthFrames.indices.contains(index) else { continue }
            monthView.frame = monthFrames[index]
        }
    }

    /// The opening month centred, as CalendarMessageScreen's first layout does.
    private func scrollToInitialMonth() {
        guard let index = months.firstIndex(where: { initialDate >= $0.firstDay }),
              monthFrames.indices.contains(index) else { return }
        let maximum = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        let offset = min(max(0, floor(monthFrames[index].midY - scrollView.bounds.height / 2)), maximum)
        scrollView.contentOffset = CGPoint(x: 0, y: offset)
    }

    private func updateMonthViews() {
        let visible = scrollView.bounds.insetBy(dx: 0, dy: -200)
        var shown = Set<Int>()
        for (index, frame) in monthFrames.enumerated() where visible.intersects(frame) {
            shown.insert(index)
            let monthView: ChatCalendarMonthView
            if let existing = monthViews[index] {
                monthView = existing
            } else {
                monthView = ChatCalendarMonthView()
                monthView.transform = CGAffineTransform(rotationAngle: .pi)
                monthView.onSelectDay = { [weak self] day in self?.select(day) }
                monthView.onSelectMonth = { [weak self] range in self?.selectMonth(range) }
                monthView.onHoldDay = { [weak self] day, message, source, gesture in
                    self?.preview(day: day, message: message, source: source, gesture: gesture)
                }
                monthView.selectsEmptyDays = selectsEmptyDays
                monthViews[index] = monthView
                scrollView.addSubview(monthView)
            }
            monthView.bounds = CGRect(origin: .zero, size: frame.size)
            monthView.center = CGPoint(x: frame.midX, y: frame.midY)
            monthView.configure(
                month: months[index],
                media: mediaByDay,
                selectedDays: isSelecting ? selectedDays : nil,
                client: client,
                chatID: chatID,
            )
        }
        for index in monthViews.keys where !shown.contains(index) {
            monthViews.removeValue(forKey: index)?.removeFromSuperview()
        }
    }

    private func preview(day: Date, message: Message?, source: UIView, gesture: UIGestureRecognizer) {
        // The preview's gesture is off while selecting (contextGestureContainerNode.isGestureEnabled).
        guard let previewDay, !isSelecting else { return }
        previewTask?.cancel()
        previewTask = Task { [weak self, weak source, weak gesture] in
            let content = await previewDay(day, message)
            guard let self, !Task.isCancelled, let content, let source, source.window != nil else { return }
            previewTask = nil
            // A day whose message had to be looked up opens without the finger once it has lifted.
            let tracking = gesture.flatMap { [.began, .changed].contains($0.state) ? $0 : nil }
            presentTelegramContextMenu(
                sourceView: source,
                actions: content.actions,
                tracking: tracking,
                presentationStyle: .chatPreview,
                previewController: content.preview,
            )
        }
    }

    private func select(_ day: Date) {
        guard !isSelecting else {
            extendSelection(with: day)
            return
        }
        let onSelectDay = onSelectDay
        dismiss(animated: true) { onSelectDay(day) }
    }

    // MARK: Selection

    /// toggleSelectPressed: Select turns into Done and back.
    private func toggleSelecting() {
        isSelecting.toggle()
        selectedDays = nil
        updateSelectionChrome()
        updateMonthViews()
    }

    /// dayAction while selecting: a day starts a range, a second one ends it (either way), a range's end clears it
    /// and any other day starts again.
    private func extendSelection(with day: Date) {
        let day = calendar.startOfDay(for: day)
        selectedDays =
            if let range = selectedDays {
                if range.lowerBound == day || range.upperBound == day {
                    nil
                } else if range.lowerBound == range.upperBound {
                    min(day, range.lowerBound)...max(day, range.upperBound)
                } else {
                    day...day
                }
            } else {
                day...day
            }
        updateSelectionChrome()
        updateMonthViews()
    }

    /// monthAction: the whole month, or none when it was the selection.
    private func selectMonth(_ range: ClosedRange<Date>) {
        guard isSelecting else { return }
        selectedDays = selectedDays == range ? nil : range
        updateSelectionChrome()
        updateMonthViews()
    }

    /// The bar's Select or Done, the title's day count and the toolbar's Clear History.
    private func updateSelectionChrome() {
        if onClearRange != nil {
            navigationItem.rightBarButtonItem = isSelecting
                ? UIBarButtonItem(
                    systemItem: .done,
                    primaryAction: UIAction { [weak self] _ in self?.toggleSelecting() },
                )
                : UIBarButtonItem(
                    title: L10n.telegram("Common.Select"),
                    primaryAction: UIAction { [weak self] _ in self?.toggleSelecting() },
                )
        }
        let count = selectedCount
        title = isSelecting && count > 0
            ? L10n.telegramPlural("MessageCalendar.DaysSelectedTitle", count: count)
            : L10n.telegram("MessageCalendar.Title")
        selectionToolbar.isHidden = !isSelecting
        selectionToolbar.update(
            title: L10n.telegram(
                count == 0
                    ? "DialogList.ClearHistoryConfirmation"
                    : count == 1
                        ? "MessageCalendar.ClearHistoryForThisDay"
                        : "MessageCalendar.ClearHistoryForTheseDays",
            ),
            isActive: count > 0,
        )
        additionalSafeAreaInsets.bottom = isSelecting ? selectionToolbar.contentHeight : 0
    }

    /// selectionToolbarActionSelected: with nothing selected, EmptySelectionTooltip over the toolbar.
    private func clearSelected() {
        let count = selectedCount
        guard let selectedDays, count > 0 else {
            TelegramUndoToast.show(
                text: L10n.telegram("MessageCalendar.EmptySelectionTooltip"),
                in: view,
                bottomInset: 8,
                undo: nil,
            )
            return
        }
        onClearRange?(selectedDays, count)
    }

    // MARK: Loading

    /// SparseMessageCalendar: every page of the chat's photo and video calendar, newest first, and the oldest
    /// message's month as the first one shown.
    private func load() {
        let client = client
        let chatID = chatID
        let topic = topic
        loadTask = Task { [weak self] in
            let oldest = try? await client.getChatHistory(
                chatId: chatID,
                fromMessageId: 1,
                limit: 1,
                offset: -1,
                onlyLocal: false,
            )
            .messages
            .first?
            .date
            guard !Task.isCancelled, let self else { return }
            if let oldest { trimMonths(oldest: Date(timeIntervalSince1970: TimeInterval(oldest))) }
            // getChatMessageCalendar takes no forum topic or message thread: their days stay without media.
            switch topic {
            case .messageTopicForum,
                 .messageTopicThread: return
            default: break
            }
            var fromMessageID: Int64 = 0
            for _ in 0..<200 {
                guard let page = try? await client.send(TDNativeRequests.getChatMessageCalendar(
                    chatId: chatID,
                    topicId: topic,
                    filter: filter,
                    fromMessageId: fromMessageID,
                )), !Task.isCancelled else { return }
                let messages = page.days.map(\.message)
                guard let last = messages.last, last.id != fromMessageID else { break }
                for message in messages {
                    let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(message.date)))
                    if let shown = mediaByDay[day], shown.date <= message.date { continue }
                    mediaByDay[day] = message
                }
                updateMonthViews()
                fromMessageID = last.id
            }
        }
    }

    private func trimMonths(oldest: Date) {
        let trimmed = Self.months(calendar: calendar, oldest: min(oldest, initialDate))
        guard trimmed.count != months.count else { return }
        months = trimmed
        for view in monthViews.values {
            view.removeFromSuperview()
        }
        monthViews.removeAll()
        guard laidOutSize != .zero else { return }
        let offset = scrollView.contentOffset
        layoutMonths()
        scrollView.contentOffset = CGPoint(
            x: 0,
            y: min(offset.y, max(0, scrollView.contentSize.height - scrollView.bounds.height)),
        )
        updateMonthViews()
    }
}

// MARK: - ChatCalendarScrollView

/// CalendarMessageScreen's Scroller: a drag that starts on a day scrolls the months instead of pressing the day.
private final class ChatCalendarScrollView: UIScrollView {
    override func touchesShouldCancel(in _: UIView) -> Bool {
        true
    }
}

// MARK: - ChatCalendarMonth

/// CalendarMessageScreen's MonthModel.
struct ChatCalendarMonth {
    let firstDay: Date
    let year: Int
    let month: Int
    let numberOfDays: Int
    /// The grid column of the first day.
    let firstColumn: Int
    /// The columns' weekdays, Calendar's 1 (Sunday) to 7, from the locale's first weekday.
    let weekdays: [Int]
    /// Today's day of the month in this month, and the last day that isn't to come.
    let today: Int?
    let lastEnabledDay: Int

    var rowCount: Int {
        (firstColumn + numberOfDays + 6) / 7
    }

    /// stringForMonth(ofYear:): "January 2024".
    var title: String {
        L10n.telegram("Time.MonthOfYear_m\(month)", String(year))
    }

    init?(firstDay: Date, calendar: Calendar, now: Date) {
        guard let days = calendar.range(of: .day, in: .month, for: firstDay)?.count else { return nil }
        self.firstDay = firstDay
        self.year = calendar.component(.year, from: firstDay)
        self.month = calendar.component(.month, from: firstDay)
        self.numberOfDays = days
        let firstWeekday = calendar.firstWeekday
        self.firstColumn = (calendar.component(.weekday, from: firstDay) - firstWeekday + 7) % 7
        self.weekdays = (0..<7).map { (firstWeekday - 1 + $0) % 7 + 1 }
        let isCurrentMonth = calendar.isDate(firstDay, equalTo: now, toGranularity: .month)
        self.today = isCurrentMonth ? calendar.component(.day, from: now) : nil
        self.lastEnabledDay = today ?? (firstDay > now ? 0 : days)
    }

    func day(_ dayOfMonth: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: dayOfMonth - 1, to: firstDay) ?? firstDay
    }
}

// MARK: - ChatCalendarMonthView

/// CalendarMessageScreen's MonthComponent: the month's name, the weekday letters and the days in 46 pt rows.
final class ChatCalendarMonthView: UIView {
    private static let sideInset: CGFloat = 14
    private static let titleWeekdaysSpacing: CGFloat = 18
    private static let weekdayDaySpacing: CGFloat = 14
    private static let rowHeight: CGFloat = 46
    private static let rowSpacing: CGFloat = 6
    private static let titleFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
    private static let weekdayFont = UIFont.systemFont(ofSize: 10)

    private static var baseDayY: CGFloat {
        ceil(titleFont.lineHeight) + titleWeekdaysSpacing + ceil(weekdayFont.lineHeight) + weekdayDaySpacing
    }

    var onSelectDay: ((Date) -> Void)?
    var onHoldDay: ((Date, Message?, UIView, UIGestureRecognizer) -> Void)?
    /// MonthComponent's monthAction: a tap on the month's name while selecting takes the whole month.
    var onSelectMonth: ((ClosedRange<Date>) -> Void)?
    var selectsEmptyDays = true

    /// The selected days, by their starts.
    private var selectedDays: ClosedRange<Date>?
    /// The 10% accent bands under each row's selected days.
    private var bandLayers = [CALayer]()

    private let titleLabel = UILabel()
    private var media = [Date: Message]()
    private var weekdayLabels = [UILabel]()
    private var dayViews = [ChatCalendarDayView]()
    private var month: ChatCalendarMonth?

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = Self.titleFont
        titleLabel.textAlignment = .center
        titleLabel.accessibilityTraits = .header
        titleLabel.isUserInteractionEnabled = true
        titleLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(titleTapped)))
        addSubview(titleLabel)
        for _ in 0..<7 {
            let label = UILabel()
            label.font = Self.weekdayFont
            label.textAlignment = .center
            label.isAccessibilityElement = false
            addSubview(label)
            weekdayLabels.append(label)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let month else { return }
        let width = bounds.width
        let columnWidth = floor((width - Self.sideInset * 2) / 7)
        let usableWidth = floor((width - Self.sideInset * 2 - Self.rowSpacing * 6) / 7)
        let titleHeight = ceil(Self.titleFont.lineHeight)
        titleLabel.frame = CGRect(x: Self.sideInset, y: 0, width: width - Self.sideInset * 2, height: titleHeight)
        let weekdayY = titleHeight + Self.titleWeekdaysSpacing
        let weekdayHeight = ceil(Self.weekdayFont.lineHeight)
        for (column, label) in weekdayLabels.enumerated() {
            label.frame = CGRect(
                x: Self.sideInset + CGFloat(column) * columnWidth,
                y: weekdayY,
                width: columnWidth,
                height: weekdayHeight,
            )
        }
        let baseDayY = Self.baseDayY
        for (index, dayView) in dayViews.enumerated() {
            let gridIndex = month.firstColumn + index
            let x = Self.sideInset + CGFloat(gridIndex % 7) * columnWidth + floor((columnWidth - usableWidth) / 2)
            let y = baseDayY + CGFloat(gridIndex / 7) * (Self.rowHeight + Self.rowSpacing)
            dayView.frame = CGRect(x: x, y: y, width: usableWidth, height: Self.rowHeight)
        }
        layoutBands(month: month, columnWidth: columnWidth)
    }

    static func height(for month: ChatCalendarMonth, width _: CGFloat) -> CGFloat {
        baseDayY + CGFloat(month.rowCount) * (rowHeight + rowSpacing) - rowSpacing
    }

    func configure(
        month: ChatCalendarMonth,
        media: [Date: Message],
        selectedDays: ClosedRange<Date>? = nil,
        client: TDLibClient,
        chatID: Int64,
    ) {
        self.media = media
        self.selectedDays = selectedDays
        let calendar = Calendar.current
        if self.month?.firstDay != month.firstDay {
            self.month = month
            titleLabel.text = month.title
            let names = ["Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri"]
            for (column, label) in weekdayLabels.enumerated() {
                label.text = L10n.telegram("Calendar.Short" + names[month.weekdays[column] % 7])
            }
            while dayViews.count < month.numberOfDays {
                let dayView = ChatCalendarDayView()
                dayView.addTarget(self, action: #selector(dayTapped(_:)), for: .touchUpInside)
                let hold = ContextMenuPressGestureRecognizer(target: self, action: #selector(dayHeld(_:)))
                hold.castsShadow = false
                dayView.addGestureRecognizer(hold)
                addSubview(dayView)
                dayViews.append(dayView)
            }
            while dayViews.count > month.numberOfDays {
                dayViews.removeLast().removeFromSuperview()
            }
            setNeedsLayout()
        }
        let showsSensitive = SensitiveContentStore.shows(chatID: chatID, clientID: client.id)
        for (index, dayView) in dayViews.enumerated() {
            let dayOfMonth = index + 1
            let day = month.day(dayOfMonth, calendar: calendar)
            let message = media[day].flatMap { message in
                SensitiveContentStore.isSensitive(message) && !showsSensitive ? nil : message
            }
            dayView.tag = dayOfMonth
            let selection: ChatCalendarDayView.Selection =
                if let selectedDays, selectedDays.contains(day) {
                    day == selectedDays.lowerBound || day == selectedDays.upperBound ? .edge : .middle
                } else {
                    .none
                }
            dayView.configure(
                dayOfMonth: dayOfMonth,
                isToday: month.today == dayOfMonth,
                isEnabled: dayOfMonth <= month.lastEnabledDay,
                message: message,
                selection: selection,
                client: client,
            )
        }
        setNeedsLayout()
    }

    /// MonthComponent's line selections: in each row a band from the first selected day to the last, as round as a
    /// day, left out when the whole selection is one day.
    private func layoutBands(month: ChatCalendarMonth, columnWidth: CGFloat) {
        bandLayers.forEach { $0.removeFromSuperlayer() }
        bandLayers = []
        guard let selectedDays else { return }
        let calendar = Calendar.current
        var rows = [Int: ClosedRange<Int>]()
        var selected = [Date]()
        for dayOfMonth in 1...month.numberOfDays {
            let day = month.day(dayOfMonth, calendar: calendar)
            guard selectedDays.contains(day) else { continue }
            selected.append(day)
            let gridIndex = month.firstColumn + dayOfMonth - 1
            let column = gridIndex % 7
            let row = gridIndex / 7
            rows[row] = rows[row].map { min($0.lowerBound, column)...max($0.upperBound, column) } ?? column...column
        }
        if selectedDays.lowerBound == selectedDays.upperBound { return }
        let diameter = min(dayViews.first?.bounds.width ?? Self.rowHeight, Self.rowHeight)
        let color = tintColor.withAlphaComponent(0.1).cgColor
        for (row, columns) in rows {
            let inset = floor((columnWidth - diameter) / 2)
            let minX = Self.sideInset + CGFloat(columns.lowerBound) * columnWidth + inset
            let maxX = Self.sideInset + CGFloat(columns.upperBound + 1) * columnWidth - inset
            let y = Self.baseDayY + CGFloat(row) * (Self.rowHeight + Self.rowSpacing)
                + floor((Self.rowHeight - diameter) / 2)
            let band = CALayer()
            band.backgroundColor = color
            band.cornerRadius = diameter / 2
            band.frame = CGRect(x: minX, y: y, width: maxX - minX, height: diameter)
            layer.insertSublayer(band, at: 0)
            bandLayers.append(band)
        }
    }

    @objc private func titleTapped() {
        guard let month, let onSelectMonth else { return }
        let calendar = Calendar.current
        onSelectMonth(month.firstDay...month.day(month.numberOfDays, calendar: calendar))
    }

    @objc private func dayHeld(_ gesture: ContextMenuPressGestureRecognizer) {
        guard gesture.state == .began, onHoldDay != nil, let month, let dayView = gesture.view,
              dayView.tag <= month.lastEnabledDay else { return }
        let day = month.day(dayView.tag, calendar: Calendar.current)
        onHoldDay?(day, media[day], dayView, gesture)
    }

    @objc private func dayTapped(_ dayView: ChatCalendarDayView) {
        guard let month, dayView.tag <= month.lastEnabledDay else { return }
        let day = month.day(dayView.tag, calendar: Calendar.current)
        guard selectsEmptyDays || media[day] != nil else { return }
        onSelectDay?(day)
    }
}

// MARK: - ChatCalendarDayView

/// CalendarMessageScreen's DayComponent: the day's number, over its first photo or video in a circle dimmed by 20%
/// black when it has one; today's number in the accent, days to come greyed.
final class ChatCalendarDayView: UIControl {
    /// DayComponent's DaySelection: a range's first and last days in the accent circle (a 2 pt ring round a photo),
    /// the days between in semibold, and both with the photo drawn 8 pt smaller.
    enum Selection {
        case none
        case edge
        case middle
    }

    override var isHighlighted: Bool {
        didSet { imageView.alpha = isHighlighted && representedMessageID != nil ? 0.8 : 1 }
    }

    private let imageView = TDImageLoadingView()
    private let dimView = UIView()
    private let titleLabel = UILabel()
    private let selectionLayer = CAShapeLayer()
    private var selection = Selection.none
    private var representedMessageID: Int64?

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)
        dimView.backgroundColor = UIColor(white: 0, alpha: 0.2)
        dimView.isUserInteractionEnabled = false
        addSubview(dimView)
        layer.addSublayer(selectionLayer)
        titleLabel.textAlignment = .center
        titleLabel.isUserInteractionEnabled = false
        addSubview(titleLabel)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let diameter = min(bounds.width, bounds.height)
        let circle = CGRect(
            x: floor((bounds.width - diameter) / 2),
            y: floor((bounds.height - diameter) / 2),
            width: diameter,
            height: diameter,
        )
        imageView.frame = circle
        imageView.layer.cornerRadius = diameter / 2
        dimView.frame = circle
        dimView.layer.cornerRadius = diameter / 2
        let scale = selection == .none ? 1 : (diameter - 8) / diameter
        imageView.transform = CGAffineTransform(scaleX: scale, y: scale)
        dimView.transform = imageView.transform
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selectionLayer.frame = circle
        let hasMedia = !imageView.isHidden
        let ringWidth: CGFloat = 2
        selectionLayer.path = hasMedia
            ? UIBezierPath(ovalIn: CGRect(origin: .zero, size: circle.size).insetBy(
                dx: ringWidth / 2,
                dy: ringWidth / 2,
            ))
            .cgPath
            : UIBezierPath(ovalIn: CGRect(origin: .zero, size: circle.size)).cgPath
        selectionLayer.lineWidth = hasMedia ? ringWidth : 0
        selectionLayer.fillColor = hasMedia ? UIColor.clear.cgColor : tintColor.cgColor
        selectionLayer.strokeColor = tintColor.cgColor
        selectionLayer.isHidden = selection != .edge
        CATransaction.commit()
        bringSubviewToFront(titleLabel)
        titleLabel.frame = bounds
    }

    func configure(
        dayOfMonth: Int,
        isToday: Bool,
        isEnabled: Bool,
        message: Message?,
        selection: Selection = .none,
        client: TDLibClient,
    ) {
        self.selection = selection
        titleLabel.text = String(dayOfMonth)
        accessibilityLabel = String(dayOfMonth)
        let thumbnail = message.flatMap { MessageReplyThumbnail.make(for: $0.content) }
        if message?.id != representedMessageID {
            representedMessageID = message?.id
            imageView.cancel()
            imageView.image = nil
            if let thumbnail {
                imageView.load(
                    file: thumbnail.file,
                    placeholderData: thumbnail.minithumbnailData,
                    maximumPixelSize: 150,
                    client: client,
                )
            }
        }
        let hasMedia = thumbnail != nil
        imageView.isHidden = !hasMedia
        dimView.isHidden = !hasMedia
        titleLabel.font = .systemFont(
            ofSize: 17, weight: hasMedia || isToday || selection != .none ? .semibold : .regular,
        )
        titleLabel.textColor =
            if hasMedia || selection == .edge {
                .white
            } else if isToday {
                tintColor
            } else if isEnabled {
                .label
            } else {
                .tertiaryLabel
            }
        if isEnabled {
            accessibilityTraits.remove(.notEnabled)
        } else {
            accessibilityTraits.insert(.notEnabled)
        }
        if selection == .none {
            accessibilityTraits.remove(.selected)
        } else {
            accessibilityTraits.insert(.selected)
        }
        setNeedsLayout()
    }
}

// MARK: - ChatCalendarSelectionToolbar

/// ToolbarNode with a middle action: a hairline over the bar's background and the centred action in 17 pt, red with
/// days selected and grey without.
final class ChatCalendarSelectionToolbar: UIView {
    let button = UIButton(type: .system)
    var contentHeight: CGFloat = 49 {
        didSet { setNeedsLayout() }
    }

    private let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let separator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(background)
        separator.backgroundColor = .separator
        addSubview(separator)
        button.titleLabel?.font = .systemFont(ofSize: 17)
        addSubview(button)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        separator.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1 / max(1, traitCollection.displayScale))
        button.frame = CGRect(x: 16, y: 0, width: bounds.width - 32, height: contentHeight)
    }

    func update(title: String, isActive: Bool) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(isActive ? .systemRed : .tertiaryLabel, for: .normal)
    }
}
