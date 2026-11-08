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
        return sections
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
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
