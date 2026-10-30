// ChatMediaCalendarViewController.swift

import TDLibKit
import UIKit

// MARK: - ChatMediaCalendarViewController

/// Telegram's CalendarMessageScreen for a chat, opened from a date header: the chat's months from the newest at the
/// bottom, each a seven-column grid of days, where a day with photos or videos shows the first one in its circle
/// (the sparse calendar of getChatMessageCalendar, loaded page by page), today is in the accent and days to come are
/// dimmed. A day opens the chat at its first message, an empty one too, as in the chat's calendar. TDLib has no such
/// calendar for a forum topic or a message thread, whose days stay plain. Telegram's range selection to clear history
/// and its day preview aren't ported.
final class ChatMediaCalendarViewController: UIViewController, UIScrollViewDelegate {
    private static let monthSpacing: CGFloat = 16

    private let chatID: Int64
    private let topic: MessageTopic?
    private let client: TDLibClient
    private let initialDate: Date
    private let onSelectDay: (Date) -> Void
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

    init(
        chatID: Int64,
        topic: MessageTopic?,
        client: TDLibClient,
        initialDate: Date,
        onSelectDay: @escaping (Date) -> Void,
    ) {
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
        load()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
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
                monthViews[index] = monthView
                scrollView.addSubview(monthView)
            }
            monthView.bounds = CGRect(origin: .zero, size: frame.size)
            monthView.center = CGPoint(x: frame.midX, y: frame.midY)
            monthView.configure(month: months[index], media: mediaByDay, client: client, chatID: chatID)
        }
        for index in monthViews.keys where !shown.contains(index) {
            monthViews.removeValue(forKey: index)?.removeFromSuperview()
        }
    }

    private func select(_ day: Date) {
        let onSelectDay = onSelectDay
        dismiss(animated: true) { onSelectDay(day) }
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
                    filter: .searchMessagesFilterPhotoAndVideo,
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

    private let titleLabel = UILabel()
    private var weekdayLabels = [UILabel]()
    private var dayViews = [ChatCalendarDayView]()
    private var month: ChatCalendarMonth?

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = Self.titleFont
        titleLabel.textAlignment = .center
        titleLabel.accessibilityTraits = .header
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
    }

    static func height(for month: ChatCalendarMonth, width _: CGFloat) -> CGFloat {
        baseDayY + CGFloat(month.rowCount) * (rowHeight + rowSpacing) - rowSpacing
    }

    func configure(month: ChatCalendarMonth, media: [Date: Message], client: TDLibClient, chatID: Int64) {
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
            dayView.configure(
                dayOfMonth: dayOfMonth,
                isToday: month.today == dayOfMonth,
                isEnabled: dayOfMonth <= month.lastEnabledDay,
                message: message,
                client: client,
            )
        }
    }

    @objc private func dayTapped(_ dayView: ChatCalendarDayView) {
        guard let month, dayView.tag <= month.lastEnabledDay else { return }
        onSelectDay?(month.day(dayView.tag, calendar: Calendar.current))
    }
}

// MARK: - ChatCalendarDayView

/// CalendarMessageScreen's DayComponent: the day's number, over its first photo or video in a circle dimmed by 20%
/// black when it has one; today's number in the accent, days to come greyed.
final class ChatCalendarDayView: UIControl {
    override var isHighlighted: Bool {
        didSet { imageView.alpha = isHighlighted && representedMessageID != nil ? 0.8 : 1 }
    }

    private let imageView = TDImageLoadingView()
    private let dimView = UIView()
    private let titleLabel = UILabel()
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
        titleLabel.frame = bounds
    }

    func configure(dayOfMonth: Int, isToday: Bool, isEnabled: Bool, message: Message?, client: TDLibClient) {
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
        titleLabel.font = .systemFont(ofSize: 17, weight: hasMedia || isToday ? .semibold : .regular)
        titleLabel.textColor =
            if hasMedia {
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
    }
}
