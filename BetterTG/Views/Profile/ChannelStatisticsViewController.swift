// ChannelStatisticsViewController.swift

import TDLibKit
import UIKit

// MARK: - ChannelStatisticsViewController

/// ChannelStatsController's overview (StatsOverviewItem) for a channel (getChatStatistics): the period, then
/// Followers, Enabled Notifications, Views Per Post, Shares Per Post, Reactions Per Post and the story means, each with
/// its change over the period, green for growth and red for a fall; then its graphs in ChannelStatsController's order,
/// each under its title, an asynchronous one loading through getStatisticalGraph. While the server prepares the
/// statistics it shows Preparing stats.
final class ChannelStatisticsViewController: SettingsListViewController {
    private struct GraphEntry {
        let title: String
        let kind: StatisticsGraphKind
        let graph: KeyPath<TDNativeChatStatisticsChannel, TDNativeStatisticalGraph>
    }

    /// A post's views, shares and reactions (chatStatisticsInteractionInfo).
    private struct PostInteractions {
        let views: Int
        let forwards: Int
        let reactions: Int
    }

    /// channelStatsControllerEntries' graphs.
    private static let graphEntries = [
        GraphEntry(title: "Stats.GrowthTitle", kind: .lines, graph: \.memberCountGraph),
        GraphEntry(title: "Stats.FollowersTitle", kind: .lines, graph: \.joinGraph),
        GraphEntry(title: "Stats.NotificationsTitle", kind: .lines, graph: \.muteGraph),
        GraphEntry(title: "Stats.ViewsByHoursTitle", kind: .hourlyStep, graph: \.viewCountByHourGraph),
        GraphEntry(title: "Stats.ViewsBySourceTitle", kind: .bars, graph: \.viewCountBySourceGraph),
        GraphEntry(title: "Stats.FollowersBySourceTitle", kind: .bars, graph: \.joinBySourceGraph),
        GraphEntry(title: "Stats.LanguagesTitle", kind: .pie, graph: \.languageGraph),
        GraphEntry(title: "Stats.InteractionsTitle", kind: .twoAxisStep, graph: \.messageInteractionGraph),
        GraphEntry(
            title: "Stats.InstantViewInteractionsTitle",
            kind: .twoAxisStep,
            graph: \.instantViewInteractionGraph,
        ),
        GraphEntry(title: "Stats.ReactionsByEmotionTitle", kind: .bars, graph: \.messageReactionGraph),
        GraphEntry(title: "Stats.StoryInteractionsTitle", kind: .twoAxisStep, graph: \.storyInteractionGraph),
        GraphEntry(title: "Stats.StoryReactionsByEmotionTitle", kind: .bars, graph: \.storyReactionGraph),
    ]

    private let chat: Chat
    private var statistics: TDNativeChatStatisticsChannel?
    private var failed = false
    /// Each graph's state by its entry; a graph with no data or error text has none and no section.
    private var graphStates = [Int: StatisticsGraphView.State]()
    private var graphViews = [Int: StatisticsGraphView]()
    /// The entry each graph section shows.
    private var graphSections = [Int: Int]()
    /// RECENT POSTS: the channel's recent messages with their interactions, newest first.
    private var posts = [(Message, PostInteractions)]()
    private var postsSection: Int?

    init(chat: Chat, client _: TDLibClient) {
        self.chat = chat
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("ChannelInfo.Stats")
        load()
    }

    override func makeSections() -> [SettingsSection] {
        guard let statistics else {
            return [SettingsSection(
                footer: failed ? nil : L10n.telegram("Stats.LoadingText").replacing("\n", with: " "),
                rows: [SettingsRow(
                    title: L10n.telegram(failed ? "Login.UnknownError" : "Stats.LoadingTitle"),
                    style: .status(.secondaryLabel),
                    accessory: failed ? .none : .activity,
                )],
            )]
        }
        var rows = [
            row("Stats.Followers", statistics.memberCount),
            SettingsRow(
                title: L10n.telegram("Stats.EnabledNotifications"),
                detail: Self.percent(statistics.enabledNotificationsPercentage),
                style: .value,
            ),
            row("Stats.ViewsPerPost", statistics.meanMessageViewCount),
            row("Stats.SharesPerPost", statistics.meanMessageShareCount),
            row("Stats.ReactionsPerPost", statistics.meanMessageReactionCount),
        ]
        // The story means show once the channel has posted stories.
        if statistics.meanStoryViewCount.value > 0 || statistics.meanStoryViewCount.previousValue > 0 {
            rows += [
                row("Stats.ViewsPerStory", statistics.meanStoryViewCount),
                row("Stats.SharesPerStory", statistics.meanStoryShareCount),
                row("Stats.ReactionsPerStory", statistics.meanStoryReactionCount),
            ]
        }
        var sections = [SettingsSection(
            header: L10n.telegram("Stats.Overview") + "  " + Self.periodText(statistics.period),
            rows: rows,
        )]
        graphSections = [:]
        for (index, entry) in Self.graphEntries.enumerated() where graphStates[index] != nil {
            graphSections[sections.count] = index
            sections.append(SettingsSection(header: L10n.telegram(entry.title), rows: [SettingsRow(title: "")]))
        }
        postsSection = nil
        if !posts.isEmpty {
            postsSection = sections.count
            sections.append(SettingsSection(
                header: L10n.telegram("Stats.PostsTitle"),
                rows: posts.map { _ in SettingsRow(title: "") },
            ))
        }
        return sections
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == postsSection, posts.indices.contains(indexPath.row) {
            let (message, interaction) = posts[indexPath.row]
            let cell = StatisticsPostCell()
            cell.configure(
                message: message,
                views: interaction.views,
                forwards: interaction.forwards,
                reactions: interaction.reactions,
                client: client,
            )
            return cell
        }
        guard let index = graphSections[indexPath.section], let graphView = graphView(index) else {
            return super.tableView(tableView, cellForRowAt: indexPath)
        }
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        graphView.removeFromSuperview()
        graphView.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(graphView)
        NSLayoutConstraint.activate([
            graphView.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
            graphView.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
            graphView.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
            graphView.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
        ])
        return cell
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == postsSection {
            return StatisticsPostCell.height
        }
        guard let index = graphSections[indexPath.section], let state = graphStates[index] else {
            return UITableView.automaticDimension
        }
        let width = tableView.bounds.width - tableView.layoutMargins.left - tableView.layoutMargins.right
        return StatisticsGraphView.height(width: width, kind: Self.graphEntries[index].kind, state: state)
    }

    /// compactNumericCountString: 1234 reads 1.2K, under a thousand the whole number.
    private static func compact(_ value: Double) -> String {
        if value >= 1000 {
            return value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
        }
        return value.rounded() == value
            ? Int(value).formatted()
            : value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private static func percent(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1))))%"
    }

    /// The overview's period, as the header's dates.
    private static func periodText(_ period: TDNativeDateRange) -> String {
        let format: (Int) -> String = {
            Date(timeIntervalSince1970: TimeInterval($0)).formatted(.dateTime.month(.abbreviated).day())
        }
        return "\(format(period.startDate)) – \(format(period.endDate))".uppercased()
    }

    private func graphView(_ index: Int) -> StatisticsGraphView? {
        if let view = graphViews[index] {
            return view
        }
        guard let state = graphStates[index] else { return nil }
        let view = StatisticsGraphView(kind: Self.graphEntries[index].kind, state: state)
        graphViews[index] = view
        return view
    }

    /// StatsGraph from statisticalGraph: data to draw, an asynchronous graph to load by its token, or the server's
    /// text.
    private func setGraph(_ graph: TDNativeStatisticalGraph, at index: Int) {
        graphViews[index] = nil
        switch graph {
        case .statisticalGraphData(let data):
            graphStates[index] = StatisticsChartData(json: data.jsonData).map { .loaded($0) }
        case .statisticalGraphAsync(let async):
            graphStates[index] = .loading
            loadGraph(token: async.token, at: index)
        case .statisticalGraphError(let error):
            graphStates[index] = error.errorMessage.isEmpty ? nil : .failed(error.errorMessage)
        }
    }

    /// ChannelStatsContext's messages for recentInteractions; stories aren't listed yet.
    private func loadPosts(_ interactions: [TDNativeChatStatisticsInteractionInfo]) {
        var byMessage = [Int64: PostInteractions]()
        for interaction in interactions {
            if case .chatStatisticsObjectTypeMessage(let object) = interaction.objectType {
                byMessage[object.messageId] = PostInteractions(
                    views: interaction.viewCount,
                    forwards: interaction.forwardCount,
                    reactions: interaction.reactionCount,
                )
            }
        }
        let client = client
        let chatID = chat.id
        Task { [weak self] in
            #if DEBUG
                // `-ui-probe-stats-posts`: with no recent posts from the server, the channel's last messages stand in
                // with made-up counters, so the rows can be checked.
                if byMessage.isEmpty, ProcessInfo.processInfo.arguments.contains("-ui-probe-stats-posts"),
                   let history = try? await client.send(TDNativeRequests.getChatHistory(
                       chatId: chatID,
                       fromMessageId: 0,
                       offset: 0,
                       limit: 6,
                       onlyLocal: false,
                   ))
                {
                    for (index, message) in history.messages.compactMap(\.self).enumerated() {
                        byMessage[message.id] = PostInteractions(
                            views: [0, 141, 1250, 87, 12, 3400][index % 6],
                            forwards: [0, 2, 0, 1350, 0, 5][index % 6],
                            reactions: [0, 18, 4, 0, 0, 1200][index % 6],
                        )
                    }
                }
            #endif
            guard !byMessage.isEmpty else { return }
            let result = try? await client.send(TDNativeRequests.getMessages(
                chatId: chatID,
                messageIds: Array(byMessage.keys),
            ))
            guard let self, contextIsCurrent, let result else { return }
            posts = result.messages
                .compactMap(\.self)
                .compactMap { message in byMessage[message.id].map { (message, $0) } }
                .sorted { $0.0.date > $1.0.date }
            reload()
        }
    }

    private func loadGraph(token: String, at index: Int) {
        let client = client
        let chatID = chat.id
        Task { [weak self] in
            let result = try? await client.send(TDNativeRequests.getStatisticalGraph(
                chatId: chatID,
                token: token,
                x: 0,
            ))
            guard let self, contextIsCurrent else { return }
            if let result {
                setGraph(result, at: index)
            } else {
                graphViews[index] = nil
                graphStates[index] = nil
            }
            reload()
        }
    }

    private func load() {
        let client = client
        let chatID = chat.id
        let isDark = traitCollection.userInterfaceStyle == .dark
        Task { [weak self] in
            let result = try? await client.send(TDNativeRequests.getChatStatistics(chatId: chatID, isDark: isDark))
            guard let self, contextIsCurrent else { return }
            if case .chatStatisticsChannel(let channel)? = result {
                statistics = channel
                for (index, entry) in Self.graphEntries.enumerated() {
                    setGraph(channel[keyPath: entry.graph], at: index)
                }
                loadPosts(channel.recentInteractions)
            } else {
                failed = true
            }
            reload()
        }
    }

    /// StatsOverviewItem's cell: the value, then the change since the previous period as +12 (3.4%).
    private func row(_ key: String, _ value: TDNativeStatisticalValue) -> SettingsRow {
        let delta = value.value - value.previousValue
        let change: String? =
            if delta == 0 || value.previousValue == 0 && value.growthRatePercentage == 0 {
                nil
            } else {
                "\(delta > 0 ? "+" : "−")\(Self.compact(abs(delta))) (\(Self.percent(abs(value.growthRatePercentage))))"
            }
        let color: UIColor = delta >= 0 ? .systemGreen : .systemRed
        let text = NSMutableAttributedString(
            string: Self.compact(value.value),
            attributes: [.foregroundColor: UIColor.secondaryLabel, .font: UIFont.preferredFont(forTextStyle: .body)],
        )
        if let change {
            text.append(NSAttributedString(
                string: "  " + change,
                attributes: [.foregroundColor: color, .font: UIFont.preferredFont(forTextStyle: .subheadline)],
            ))
        }
        return SettingsRow(title: L10n.telegram(key), trailingView: SettingsTrailingView {
            let label = UILabel()
            label.attributedText = text
            return label
        })
    }
}

// MARK: - StatisticsPostCell

/// StatsMessageItem for a message: its photo or video frame, its text in semibold (what it is when it has none)
/// over its date, and on the right its views over its reactions and shares with Telegram's icons.
private final class StatisticsPostCell: UITableViewCell {
    /// 10 pt above and under the title and the date, 3 pt between them.
    static let height = 20 + ceil(titleFont.lineHeight) + 3 + ceil(labelFont.lineHeight)

    private static let titleFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
    private static let labelFont = UIFont.systemFont(ofSize: 13)

    private let thumbnailView = TDImageLoadingView()
    private let titleLabel = UILabel()
    private let dateLabel = UILabel()
    private let viewsLabel = UILabel()
    private let reactionsLabel = UILabel()
    private let forwardsLabel = UILabel()
    private let reactionsIcon = UIImageView(image: UIImage(named: "Chart/Reactions")?
        .withRenderingMode(.alwaysTemplate))
    private let forwardsIcon = UIImageView(image: UIImage(named: "Chart/Forwards")?.withRenderingMode(.alwaysTemplate))

    init() {
        super.init(style: .default, reuseIdentifier: nil)
        selectionStyle = .none
        // bottomStripeNode starts at the 16 pt inset, under the thumbnail too.
        separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.cornerRadius = 6
        titleLabel.font = Self.titleFont
        dateLabel.font = Self.labelFont
        dateLabel.textColor = .secondaryLabel
        viewsLabel.font = Self.labelFont
        for label in [reactionsLabel, forwardsLabel] {
            label.font = Self.labelFont
            label.textColor = .secondaryLabel
        }
        for icon in [reactionsIcon, forwardsIcon] {
            icon.tintColor = .secondaryLabel
        }
        for view in [
            thumbnailView, titleLabel, dateLabel, viewsLabel, reactionsLabel, forwardsLabel, reactionsIcon,
            forwardsIcon,
        ] {
            contentView.addSubview(view)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// StatsMessageItemNode's layout: the 40 pt thumbnail 10 pt in and the text 46 pt further, the title 9 pt down,
    /// views on the right 13 pt down (centred when alone), shares at the right edge under them and reactions 10 pt
    /// before the shares, each count after its icon.
    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        let height = contentView.bounds.height
        let hasCounters = !reactionsIcon.isHidden || !forwardsIcon.isHidden
        thumbnailView.frame = CGRect(x: 10, y: ((height - 40) / 2).rounded(.down), width: 40, height: 40)
        let left: CGFloat = thumbnailView.isHidden ? 16 : 16 + 46
        let viewsSize = Self.size(of: viewsLabel)
        let reactionsSize = Self.size(of: reactionsLabel)
        let forwardsSize = Self.size(of: forwardsLabel)
        let additionalRightInset = max(viewsSize.width, reactionsSize.width + forwardsSize.width + 36) + 8
        let textWidth = max(0, width - left - 16 - additionalRightInset)
        titleLabel.frame = CGRect(x: left, y: 9, width: textWidth, height: ceil(Self.titleFont.lineHeight))
        dateLabel.frame = CGRect(
            x: left,
            y: titleLabel.frame.maxY + 3,
            width: textWidth,
            height: ceil(Self.labelFont.lineHeight),
        )
        let viewsY = hasCounters ? 13 : ((height - viewsSize.height) / 2).rounded(.down)
        viewsLabel.frame = CGRect(
            x: width - 16 - viewsSize.width,
            y: viewsY,
            width: viewsSize.width,
            height: viewsSize.height,
        )
        var right: CGFloat = 16
        let countersY = titleLabel.frame.maxY + 3
        let counters = [(forwardsLabel, forwardsSize, forwardsIcon), (reactionsLabel, reactionsSize, reactionsIcon)]
        for (label, size, icon) in counters where !icon.isHidden {
            label.frame = CGRect(x: width - right - size.width, y: countersY, width: size.width, height: size.height)
            let iconSize = icon.image?.size ?? .zero
            icon.frame = CGRect(
                x: label.frame.minX - iconSize.width - 3,
                y: countersY - 2,
                width: iconSize.width,
                height: iconSize.height,
            )
            right += iconSize.width + size.width + 3 + 10
        }
    }

    /// compactNumericCountString.
    private static func compact(_ value: Int) -> String {
        if value >= 1000 {
            Double(value).formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
        } else {
            String(value)
        }
    }

    private static func size(of label: UILabel) -> CGSize {
        label.text == nil ? .zero : label.sizeThatFits(CGSize(width: 128, height: CGFloat.greatestFiniteMagnitude))
    }

    func configure(message: Message, views: Int, forwards: Int, reactions: Int, client: TDLibClient) {
        let presentation = MessageContentPresentation.make(message)
        let text = presentation.formattedText?.text ?? ""
        // foldLineBreaks: the text on one line.
        titleLabel.text = (text.isEmpty ? presentation.summary : text)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let date = Date(timeIntervalSince1970: TimeInterval(message.date))
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMddyy")
        dateLabel.text = L10n.telegram(
            "Time.MediumDate",
            formatter.string(from: date),
            date.formatted(date: .omitted, time: .shortened),
        )
        viewsLabel.text = views == 0
            ? L10n.telegram("Stats.MessageViews.NoViews")
            : L10n.telegramPlural("Stats.MessageViews", count: views)
        reactionsLabel.text = reactions > 0 ? Self.compact(reactions) : nil
        forwardsLabel.text = forwards > 0 ? Self.compact(forwards) : nil
        reactionsIcon.isHidden = reactions == 0
        forwardsIcon.isHidden = forwards == 0
        if let thumbnail = MessageReplyThumbnail.make(for: message.content), !thumbnail.isRound {
            thumbnailView.isHidden = false
            thumbnailView.load(
                file: thumbnail.file,
                placeholderData: thumbnail.minithumbnailData,
                maximumPixelSize: 160,
                origin: .captured(client: client),
            )
        } else {
            thumbnailView.isHidden = true
        }
        setNeedsLayout()
    }
}
