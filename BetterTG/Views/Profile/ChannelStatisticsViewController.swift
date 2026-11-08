// ChannelStatisticsViewController.swift

import TDLibKit
import UIKit

// MARK: - ChannelStatisticsViewController

/// ChannelStatsController's overview (StatsOverviewItem) for a channel (getChatStatistics): the period, then
/// Followers, Enabled Notifications, Views Per Post, Shares Per Post, Reactions Per Post and the story means, each with
/// its change over the period, green for growth and red for a fall; then its graphs in ChannelStatsController's order,
/// each under its title, an asynchronous one loading through getStatisticalGraph. While the server prepares the
/// statistics it shows Preparing stats.
///
/// For a channel post it is MessageStatsController (getMessageStatistics): Message Statistics with the post's Views,
/// Public Shares, Reactions and Private Shares, its interactions and reactions graphs and the channels that shared it
/// publicly (getMessagePublicForwards).
final class ChannelStatisticsViewController: SettingsListViewController {
    private struct GraphEntry {
        let title: String
        let kind: StatisticsGraphKind
    }

    /// A public share's channel and the shared message.
    private struct PublicShare {
        let message: Message
        let chat: Chat
    }

    /// A post's views, shares and reactions (chatStatisticsInteractionInfo).
    private struct PostInteractions {
        let views: Int
        let forwards: Int
        let reactions: Int
    }

    /// A group's top members, admins and inviters, each list's people by id.
    private enum TopList: CaseIterable {
        case posters
        case admins
        case inviters
    }

    /// channelStatsControllerEntries' graphs.
    private static let channelGraphEntries = [
        GraphEntry(title: "Stats.GrowthTitle", kind: .lines),
        GraphEntry(title: "Stats.FollowersTitle", kind: .lines),
        GraphEntry(title: "Stats.NotificationsTitle", kind: .lines),
        GraphEntry(title: "Stats.ViewsByHoursTitle", kind: .hourlyStep),
        GraphEntry(title: "Stats.ViewsBySourceTitle", kind: .bars),
        GraphEntry(title: "Stats.FollowersBySourceTitle", kind: .bars),
        GraphEntry(title: "Stats.LanguagesTitle", kind: .pie),
        GraphEntry(title: "Stats.InteractionsTitle", kind: .twoAxisStep),
        GraphEntry(title: "Stats.InstantViewInteractionsTitle", kind: .twoAxisStep),
        GraphEntry(title: "Stats.ReactionsByEmotionTitle", kind: .bars),
        GraphEntry(title: "Stats.StoryInteractionsTitle", kind: .twoAxisStep),
        GraphEntry(title: "Stats.StoryReactionsByEmotionTitle", kind: .bars),
    ]

    /// messageStatsControllerEntries' graphs, with uppercased titles.
    private static let messageGraphEntries = [
        GraphEntry(title: "Stats.MessageInteractionsTitle", kind: .twoAxisStep),
        GraphEntry(title: "Stats.MessageReactionsTitle", kind: .bars),
    ]

    /// groupStatsControllerEntries' graphs.
    private static let groupGraphEntries = [
        GraphEntry(title: "Stats.GroupGrowthTitle", kind: .lines),
        GraphEntry(title: "Stats.GroupMembersTitle", kind: .lines),
        GraphEntry(title: "Stats.GroupNewMembersBySourceTitle", kind: .bars),
        GraphEntry(title: "Stats.GroupLanguagesTitle", kind: .pie),
        GraphEntry(title: "Stats.GroupMessagesTitle", kind: .bars),
        GraphEntry(title: "Stats.GroupActionsTitle", kind: .lines),
        GraphEntry(title: "Stats.GroupTopHoursTitle", kind: .hourlyStep),
        GraphEntry(title: "Stats.GroupTopWeekdaysTitle", kind: .pie),
    ]

    private let chat: Chat
    /// The post whose statistics show, or nil for the channel's.
    private let message: Message?
    private var statistics: TDNativeChatStatisticsChannel?
    private var messageLoaded = false
    /// getMessagePublicForwards: the total and the channels' messages.
    private var publicShareCount: Int?
    private var publicShares = [PublicShare]()
    private var publicSharesSection: Int?
    /// getMessagePublicForwards' next offset; empty when every share is listed.
    private var publicSharesOffset = ""
    private var loadsPublicShares = false
    private var failed = false
    /// StatsOverviewItem's values, in reading order.
    private var overviewItems = [StatisticsOverviewCell.Item]()
    /// Each graph's state by its entry; a graph with no data or error text has none and no section.
    private var graphStates = [Int: StatisticsGraphView.State]()
    private var graphViews = [Int: StatisticsGraphView]()
    private var zoomTokens = [Int: String]()
    /// The entry each graph section shows.
    private var graphSections = [Int: Int]()
    /// RECENT POSTS: the channel's recent messages with their interactions, newest first.
    private var posts = [(Message, PostInteractions)]()
    private var postsSection: Int?

    private var groupStatistics: TDNativeChatStatisticsSupergroup?
    private var topPeers = [Int64: SettingsPeer]()
    private var expandedTopLists = Set<TopList>()

    /// The group as its management screens see it, for Actions and Promote.
    private var managementTarget: ChatManagementTarget?

    private var graphEntries: [GraphEntry] {
        message != nil ? Self.messageGraphEntries : isGroup ? Self.groupGraphEntries : Self.channelGraphEntries
    }

    /// GroupStatsController: a group's statistics, with the top lists after the graphs.
    private var isGroup: Bool {
        if case .chatTypeSupergroup(let type) = chat.type {
            !type.isChannel
        } else {
            false
        }
    }

    private var canPromote: Bool {
        managementTarget?.isCreator == true || managementTarget?.rights?.canPromoteMembers == true
    }

    init(chat: Chat, client _: TDLibClient) {
        self.chat = chat
        self.message = nil
        super.init()
    }

    /// A channel post's statistics.
    init(message: Message, chat: Chat) {
        self.chat = chat
        self.message = message
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram(message == nil ? "ChannelInfo.Stats" : "Stats.MessageTitle")
        if message == nil {
            load()
        } else {
            loadMessage()
        }
    }

    override func makeSections() -> [SettingsSection] {
        if let message {
            return messageSections(message)
        }
        if isGroup {
            return groupSections()
        }
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
        overviewItems = channelOverviewItems(statistics)
        var sections = [SettingsSection(
            header: L10n.telegram("Stats.Overview") + "  " + Self.periodText(statistics.period),
            rows: [SettingsRow(title: "")],
        )]
        appendGraphSections(to: &sections)
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
        if indexPath.section == 0, !overviewItems.isEmpty {
            let cell = StatisticsOverviewCell()
            cell.items = overviewItems
            return cell
        }
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
        if indexPath.section == 0, !overviewItems.isEmpty {
            return StatisticsOverviewCell.height(itemCount: overviewItems.count)
        }
        if indexPath.section == postsSection {
            return StatisticsPostCell.height
        }
        guard let index = graphSections[indexPath.section], let state = graphStates[index] else {
            return UITableView.automaticDimension
        }
        let width = tableView.bounds.width - tableView.layoutMargins.left - tableView.layoutMargins.right
        return StatisticsGraphView.height(width: width, kind: graphEntries[index].kind, state: state)
    }

    /// StatsMessageItem's action: a recent post opens its own statistics.
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == postsSection, posts.indices.contains(indexPath.row) else {
            super.tableView(tableView, didSelectRowAt: indexPath)
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        let controller = ChannelStatisticsViewController(message: posts[indexPath.row].0, chat: chat)
        navigationController?.pushViewController(controller, animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath,
    ) {
        super.tableView(tableView, willDisplay: cell, forRowAt: indexPath)
        if indexPath.section == publicSharesSection, indexPath.row >= publicShares.count - 5 {
            loadMorePublicShares()
        }
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

    /// The overview's period, as the header's dates.
    private static func periodText(_ period: TDNativeDateRange) -> String {
        let format: (Int) -> String = {
            Date(timeIntervalSince1970: TimeInterval($0)).formatted(.dateTime.month(.abbreviated).day())
        }
        return "\(format(period.startDate)) – \(format(period.endDate))".uppercased()
    }

    /// deltaText: the change as +12 (3.40%), or nothing while the previous period had none.
    private static func delta(_ value: TDNativeStatisticalValue) -> (String, UIColor)? {
        let change = value.value - value.previousValue
        guard change != 0, value.previousValue > 0 else { return nil }
        let percentage = String(format: "%.02f%%", abs(change / value.previousValue) * 100)
        let sign = change > 0 ? "+" : "-"
        return ("\(sign)\(compact(Double(abs(Int(change))))) (\(percentage))", change > 0 ? .systemGreen : .systemRed)
    }

    /// MessageStatsContext with ChannelStatsPublicForwardsContext's first page: the post's graphs, then the public
    /// shares and the channels they're in.
    /// A page of getMessagePublicForwards with each share's channel; story shares aren't listed yet.
    private static func publicShares(
        chatID: Int64,
        messageID: Int64,
        offset: String,
        client: TDLibClient,
    ) async -> (totalCount: Int, shares: [PublicShare], nextOffset: String)? {
        guard let page = try? await client.send(TDNativeRequests.getMessagePublicForwards(
            chatId: chatID,
            messageId: messageID,
            offset: offset,
            limit: 50,
        )) else { return nil }
        var shares = [PublicShare]()
        for forward in page.forwards {
            guard case .publicForwardMessage(let item) = forward,
                  let chat = try? await client.getChat(chatId: item.message.chatId)
            else { continue }
            shares.append(PublicShare(message: item.message, chat: chat))
        }
        return (page.totalCount, shares, page.nextOffset)
    }

    private func appendGraphSections(to sections: inout [SettingsSection]) {
        graphSections = [:]
        for (index, entry) in graphEntries.enumerated() where graphStates[index] != nil {
            graphSections[sections.count] = index
            sections.append(SettingsSection(
                header: L10n.telegram(entry.title).uppercased(),
                rows: [SettingsRow(title: "")],
            ))
        }
    }

    /// messageStatsControllerEntries: OVERVIEW with StatsOverviewItem's MessageStats values (Private Shares are the
    /// shares that aren't public, with a tilde), the graphs, then PUBLIC SHARES.
    private func messageSections(_ message: Message) -> [SettingsSection] {
        guard messageLoaded else {
            return [SettingsSection(rows: [SettingsRow(
                title: L10n.telegram(failed ? "Login.UnknownError" : "Stats.LoadingTitle"),
                style: .status(.secondaryLabel),
                accessory: failed ? .none : .activity,
            )])]
        }
        let info = message.interactionInfo
        let forwards = info?.forwardCount ?? 0
        let reactions = info?.reactions?.reactions.reduce(0) { $0 + $1.totalCount } ?? 0
        let item: (String, String) -> StatisticsOverviewCell.Item = { value, key in
            StatisticsOverviewCell.Item(value: value, title: L10n.telegram(key), delta: nil)
        }
        overviewItems = [
            item(Self.compact(Double(info?.viewCount ?? 0)), "Stats.Message.Views"),
            item(publicShareCount.map { Self.compact(Double($0)) } ?? "–", "Stats.Message.PublicShares"),
            item(Self.compact(Double(reactions)), "Stats.Message.Reactions"),
            item(
                publicShareCount.map { "~" + Self.compact(Double(max(0, forwards - $0))) } ?? "–",
                "Stats.Message.PrivateShares",
            ),
        ]
        var sections = [SettingsSection(
            header: L10n.telegram("Stats.MessageOverview").uppercased(),
            rows: [SettingsRow(title: "")],
        )]
        appendGraphSections(to: &sections)
        publicSharesSection = nil
        if !publicShares.isEmpty {
            publicSharesSection = sections.count
            sections.append(SettingsSection(
                header: L10n.telegram("Stats.MessagePublicForwardsTitle").uppercased(),
                rows: publicShares.map { share in
                    let views = share.message.interactionInfo?.viewCount ?? 0
                    return SettingsRow(
                        title: share.chat.title,
                        detail: views == 0
                            ? L10n.telegram("Stats.MessageViews.NoViews")
                            : L10n.telegramPlural("Stats.MessageViews", count: views),
                        style: .peer(SettingsPeer(chat: share.chat)),
                    ) { [weak self] in self?.openPublicShare(share) }
                },
            ))
        }
        return sections
    }

    private func graphView(_ index: Int) -> StatisticsGraphView? {
        if let view = graphViews[index] {
            return view
        }
        guard let state = graphStates[index] else { return nil }
        let view = StatisticsGraphView(kind: graphEntries[index].kind, state: state)
        // loadDetailedGraph: a graph with a zoom token loads a day's hours by the day's milliseconds.
        if let token = zoomTokens[index], !token.isEmpty {
            let client = client
            let chatID = chat.id
            view.zoomLoader = { date in
                let graph = try? await client.send(TDNativeRequests.getStatisticalGraph(
                    chatId: chatID,
                    token: token,
                    x: Int64(date * 1000),
                ))
                guard case .statisticalGraphData(let data)? = graph else { return nil }
                return StatisticsChartData(json: data.jsonData)
            }
        }
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
            zoomTokens[index] = data.zoomToken
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

    /// navigateToMessage: a public share opens its channel at the shared post.
    private func openPublicShare(_ share: PublicShare) {
        let client = client
        Task {
            guard let chat = await RootVM.shared.getCustomChatForNavigation(from: share.chat.id, client: client)
            else { return }
            NavigationStorage.shared.push(.customChat(chat, targetMessageID: share.message.id))
        }
    }

    /// ChannelStatsPublicForwardsContext.loadMore: the next page once the list's end comes into view.
    private func loadMorePublicShares() {
        guard let message, !publicSharesOffset.isEmpty, !loadsPublicShares else { return }
        loadsPublicShares = true
        let client = client
        let chatID = chat.id
        let offset = publicSharesOffset
        Task { [weak self] in
            let page = await Self.publicShares(chatID: chatID, messageID: message.id, offset: offset, client: client)
            guard let self, contextIsCurrent else { return }
            loadsPublicShares = false
            guard let page else { return }
            publicShares += page.shares
            publicSharesOffset = page.nextOffset
            reload()
        }
    }

    private func loadMessage() {
        guard let message else { return }
        let client = client
        let chatID = chat.id
        let isDark = traitCollection.userInterfaceStyle == .dark
        Task { [weak self] in
            async let statistics = try? client.send(TDNativeRequests.getMessageStatistics(
                chatId: chatID,
                messageId: message.id,
                isDark: isDark,
            ))
            async let forwards = Self.publicShares(chatID: chatID, messageID: message.id, offset: "", client: client)
            let (result, shares) = await (statistics, forwards)
            guard let self, contextIsCurrent else { return }
            if let result {
                messageLoaded = true
                setGraph(result.messageInteractionGraph, at: 0)
                setGraph(result.messageReactionGraph, at: 1)
                publicShareCount = shares?.totalCount
                publicShares = shares?.shares ?? []
                publicSharesOffset = shares?.nextOffset ?? ""
            } else {
                failed = true
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
            if case .chatStatisticsSupergroup(let group)? = result {
                groupStatistics = group
                let graphs = [
                    group.memberCountGraph, group.joinGraph, group.joinBySourceGraph, group.languageGraph,
                    group.messageContentGraph, group.actionGraph, group.dayGraph, group.weekGraph,
                ]
                for (index, graph) in graphs.enumerated() {
                    setGraph(graph, at: index)
                }
                loadTopPeers(group)
            } else if case .chatStatisticsChannel(let channel)? = result {
                statistics = channel
                let graphs = [
                    channel.memberCountGraph, channel.joinGraph, channel.muteGraph, channel.viewCountByHourGraph,
                    channel.viewCountBySourceGraph, channel.joinBySourceGraph, channel.languageGraph,
                    channel.messageInteractionGraph, channel.instantViewInteractionGraph, channel.messageReactionGraph,
                    channel.storyInteractionGraph, channel.storyReactionGraph,
                ]
                for (index, graph) in graphs.enumerated() {
                    setGraph(graph, at: index)
                }
                loadPosts(channel.recentInteractions)
            } else {
                failed = true
            }
            reload()
        }
    }

    // MARK: Group

    /// groupStatsControllerEntries: OVERVIEW with the period, the graphs, then TOP MEMBERS, TOP ADMINS and TOP
    /// INVITERS with the period, each list cut to ten with Show N More past twelve.
    private func groupSections() -> [SettingsSection] {
        guard let statistics = groupStatistics else {
            return [SettingsSection(
                footer: failed ? nil : L10n.telegram("Stats.LoadingText").replacing("\n", with: " "),
                rows: [SettingsRow(
                    title: L10n.telegram(failed ? "Login.UnknownError" : "Stats.LoadingTitle"),
                    style: .status(.secondaryLabel),
                    accessory: failed ? .none : .activity,
                )],
            )]
        }
        let period = Self.periodText(statistics.period)
        overviewItems = groupOverviewItems(statistics)
        var sections = [SettingsSection(
            header: L10n.telegram("Stats.GroupOverview") + "  " + period,
            rows: [SettingsRow(title: "")],
        )]
        appendGraphSections(to: &sections)
        guard !topPeers.isEmpty else { return sections }
        let posters = statistics.topSenders.filter { $0.sentMessageCount > 0 }.map { sender in
            var parts = [L10n.telegramPlural("Stats.GroupTopPosterMessages", count: sender.sentMessageCount)]
            if sender.averageCharacterCount > 0 {
                parts.append(L10n.telegramPlural("Stats.GroupTopPosterChars", count: sender.averageCharacterCount))
            }
            return (sender.userId, parts.joined(separator: ", "))
        }
        // TDLib's banned users are Telegram's kicks and its restricted users Telegram's bans.
        let admins = statistics.topAdministrators
            .filter { $0.deletedMessageCount + $0.bannedUserCount + $0.restrictedUserCount > 0 }
            .map { admin in
                var parts = [String]()
                if admin.deletedMessageCount > 0 {
                    parts.append(L10n.telegramPlural("Stats.GroupTopAdminDeletions", count: admin.deletedMessageCount))
                }
                if admin.bannedUserCount > 0 {
                    parts.append(L10n.telegramPlural("Stats.GroupTopAdminKicks", count: admin.bannedUserCount))
                }
                if admin.restrictedUserCount > 0 {
                    parts.append(L10n.telegramPlural("Stats.GroupTopAdminBans", count: admin.restrictedUserCount))
                }
                return (admin.userId, parts.joined(separator: ", "))
            }
        let inviters = statistics.topInviters.filter { $0.addedMemberCount > 0 }.map { inviter in
            (inviter.userId, L10n.telegramPlural("Stats.GroupTopInviterInvites", count: inviter.addedMemberCount))
        }
        let lists: [(TopList, String, String, [(Int64, String)])] = [
            (.posters, "Stats.GroupTopPostersTitle", "Stats.GroupShowMoreTopPosters", posters),
            (.admins, "Stats.GroupTopAdminsTitle", "Stats.GroupShowMoreTopAdmins", admins),
            (.inviters, "Stats.GroupTopInvitersTitle", "Stats.GroupShowMoreTopInviters", inviters),
        ]
        for (list, title, moreKey, entries) in lists {
            let known = entries.filter { topPeers[$0.0] != nil }
            guard !known.isEmpty else { continue }
            let isCut = known.count > 12 && !expandedTopLists.contains(list)
            var rows = (isCut ? Array(known.prefix(10)) : known).map { userID, detail in
                var row = SettingsRow(
                    title: topPeers[userID]?.title ?? "",
                    detail: detail,
                    style: .peer(topPeers[userID]!),
                ) { [weak self] in self?.openUser(userID) }
                row.swipeActions = topSwipeActions(list, userID: userID)
                row.detailLines = 1
                return row
            }
            if isCut {
                rows.append(SettingsRow(
                    title: L10n.telegramPlural(moreKey, count: known.count - 10),
                    style: .action(destructive: false),
                    symbol: "chevron.down",
                ) { [weak self] in
                    self?.expandedTopLists.insert(list)
                    self?.reload()
                })
            }
            sections.append(SettingsSection(header: L10n.telegram(title) + "  " + period, rows: rows))
        }
        return sections
    }

    /// StatsOverviewItem's GroupStats: Members and Messages, then Viewing and Posting Members while either has a
    /// value or a change.
    private func groupOverviewItems(_ statistics: TDNativeChatStatisticsSupergroup) -> [StatisticsOverviewCell.Item] {
        let item: (TDNativeStatisticalValue, String) -> StatisticsOverviewCell.Item = { value, key in
            StatisticsOverviewCell.Item(
                value: Self.compact(Double(Int(value.value))),
                title: L10n.telegram(key),
                delta: Self.delta(value),
            )
        }
        var items = [
            item(statistics.memberCount, "Stats.GroupMembers"),
            item(statistics.messageCount, "Stats.GroupMessages"),
        ]
        let hasDelta: (TDNativeStatisticalValue) -> Bool = { $0.value != $0.previousValue }
        if statistics.viewerCount.value > 0 || hasDelta(statistics.viewerCount)
            || statistics.senderCount.value > 0 || hasDelta(statistics.senderCount)
        {
            items += [
                item(statistics.viewerCount, "Stats.GroupViewers"),
                item(statistics.senderCount, "Stats.GroupPosters"),
            ]
        }
        return items
    }

    /// ItemListPeerItem's reveal options: History (an admin's Actions) in the accent, then Promote in grey where
    /// the account may add admins; none for a deleted account or the account itself.
    private func topSwipeActions(_ list: TopList, userID: Int64) -> [(
        title: String,
        color: UIColor,
        handler: () -> Void,
    )] {
        guard topPeers[userID]?.placeholder.isDeleted == false else { return [] }
        var actions: [(title: String, color: UIColor, handler: () -> Void)] =
            if list == .admins {
                [(
                    L10n.telegram("Stats.GroupTopAdmin.Actions"),
                    .tintColor,
                    { [weak self] in self?.openAdminActions(userID) },
                )]
            } else {
                [(
                    L10n.telegram("Stats.GroupTopPoster.History"),
                    .tintColor,
                    { [weak self] in self?.openHistory(userID) },
                )]
            }
        if canPromote, userID != TDLib.shared.activeAccount?.userID {
            actions.append((L10n.telegram("Stats.GroupTopPoster.Promote"), .systemGray, { [weak self] in
                self?.promote(userID)
            }))
        }
        return actions
    }

    /// openPeerHistory: the group with its search on the member's messages.
    private func openHistory(_ userID: Int64) {
        let client = client
        let chatID = chat.id
        Task {
            guard let chat = await RootVM.shared.getCustomChatForNavigation(from: chatID, client: client)
            else { return }
            NavigationStorage.shared.push(.customChat(chat)) { controller in
                (controller as? ChatViewController)?.pendingMemberSearchUserID = userID
            }
        }
    }

    /// openPeerAdminActions: the group's recent actions by that admin.
    private func openAdminActions(_ userID: Int64) {
        guard let managementTarget else { return }
        navigationController?.pushViewController(
            ChatRecentActionsViewController(target: managementTarget, adminUserID: userID),
            animated: true,
        )
    }

    /// promotePeer: the member's admin rights.
    private func promote(_ userID: Int64) {
        guard let managementTarget else { return }
        let client = client
        let chatID = chat.id
        Task { [weak self] in
            guard let member = try? await client.send(TDNativeRequests.getChatMember(
                chatId: chatID,
                memberId: .messageSenderUser(MessageSenderUser(userId: userID)),
            )),
                  let resolved = await ChatManagementMember.resolve([member], client: client).first,
                  let self, contextIsCurrent
            else { return }
            let isAdmin =
                switch member.status {
                case .chatMemberStatusAdministrator,
                     .chatMemberStatusCreator: true
                default: false
                }
            navigationController?.pushViewController(
                ChatAdminRightsViewController(target: managementTarget, member: resolved, isNew: !isAdmin),
                animated: true,
            )
        }
    }

    /// The top lists' people, for their names and photos.
    private func loadTopPeers(_ statistics: TDNativeChatStatisticsSupergroup) {
        let ids = Set(
            statistics.topSenders.map(\.userId) + statistics.topAdministrators.map(\.userId)
                + statistics.topInviters.map(\.userId),
        )
        let client = client
        let chatID = chat.id
        Task { [weak self] in
            var peers = [Int64: SettingsPeer]()
            for id in ids {
                peers[id] = await SettingsPeer.user(id, client: client)
            }
            let target = await ChatManagementTarget.load(chatID: chatID, client: client)
            guard let self, contextIsCurrent else { return }
            topPeers = peers
            managementTarget = target
            reload()
        }
    }

    /// openPeer: a top list's person opens their profile.
    private func openUser(_ userID: Int64) {
        let client = client
        let accountID = accountID
        Task { [weak self] in
            guard let chatID = try? await client.createPrivateChat(force: false, userId: userID).id,
                  let chat = await RootVM.shared.getCustomChatForNavigation(from: chatID, client: client),
                  let accountID,
                  let self, contextIsCurrent
            else { return }
            let profile = PeerProfileViewController(customChat: chat, topic: nil, client: client, accountID: accountID)
            profile.configureOpensChatItself()
            navigationController?.pushViewController(profile, animated: true)
        }
    }

    /// StatsOverviewItem's ChannelStats: Followers and Enabled Notifications, then the post means while the channel
    /// has posts and the story means while it has stories, the two kinds interleaved by column.
    private func channelOverviewItems(_ statistics: TDNativeChatStatisticsChannel) -> [StatisticsOverviewCell.Item] {
        let item: (TDNativeStatisticalValue, String) -> StatisticsOverviewCell.Item = { value, key in
            StatisticsOverviewCell.Item(
                value: Self.compact(Double(Int(value.value))),
                title: L10n.telegram(key),
                delta: Self.delta(value),
            )
        }
        let hasDelta: (TDNativeStatisticalValue) -> Bool = { $0.value != $0.previousValue }
        let hasMessages = statistics.meanMessageViewCount.value > 0 || hasDelta(statistics.meanMessageViewCount)
        let hasStories = statistics.meanStoryViewCount.value > 0 || hasDelta(statistics.meanStoryViewCount)
        var items = [Int: StatisticsOverviewCell.Item]()
        if hasMessages {
            items[0] = item(statistics.meanMessageViewCount, "Stats.ViewsPerPost")
            items[hasStories ? 2 : 1] = item(statistics.meanMessageShareCount, "Stats.SharesPerPost")
        }
        if statistics.meanMessageReactionCount.value > 0 || hasDelta(statistics.meanMessageReactionCount) {
            items[hasStories ? 4 : 2] = item(statistics.meanMessageReactionCount, "Stats.ReactionsPerPost")
        }
        if hasStories {
            items[items[0] == nil ? 0 : 1] = item(statistics.meanStoryViewCount, "Stats.ViewsPerStory")
            items[items[1] == nil ? 1 : 3] = item(statistics.meanStoryShareCount, "Stats.SharesPerStory")
            items[items[3] == nil ? 2 : 5] = item(statistics.meanStoryReactionCount, "Stats.ReactionsPerStory")
        }
        return [
            item(statistics.memberCount, "Stats.Followers"),
            StatisticsOverviewCell.Item(
                value: String(format: "%.02f%%", statistics.enabledNotificationsPercentage),
                title: L10n.telegram("Stats.EnabledNotifications"),
                delta: nil,
            ),
        ] + items.keys.sorted().compactMap { items[$0] }
    }
}

// MARK: - StatisticsOverviewCell

/// StatsOverviewItemNode: the values two to a row, each in semibold with its change after it and its title under it
/// in the header colour, 14 pt from the top and bottom and 18 pt between rows; the second column starts at the middle
/// or after the widest left value.
private final class StatisticsOverviewCell: UITableViewCell {
    struct Item {
        let value: String
        let title: String
        let delta: (String, UIColor)?
    }

    private struct ItemViews {
        let value = UILabel()
        let title = UILabel()
        let delta = UILabel()
    }

    private static let valueFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
    private static let smallFont = UIFont.systemFont(ofSize: 13)
    private static let itemHeight = ceil(valueFont.lineHeight) + ceil(smallFont.lineHeight)

    var items = [Item]() {
        didSet {
            for views in itemViews {
                [views.value, views.title, views.delta].forEach { $0.removeFromSuperview() }
            }
            itemViews = items.map { item in
                let views = ItemViews()
                views.value.font = Self.valueFont
                views.value.text = item.value
                views.title.font = Self.smallFont
                views.title.textColor = .secondaryLabel
                views.title.text = item.title
                views.delta.font = Self.smallFont
                views.delta.text = item.delta?.0
                views.delta.textColor = item.delta?
                    .1
                [views.value, views.title, views.delta]
                    .forEach { contentView.addSubview($0) }
                return views
            }
            setNeedsLayout()
        }
    }

    private var itemViews = [ItemViews]()

    init() {
        super.init(style: .default, reuseIdentifier: nil)
        selectionStyle = .none
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let firstX: CGFloat = 16
        let maxLeftWidth = itemViews.enumerated().filter { $0.offset % 2 == 0 }.map { width(of: $0.element) }.max() ?? 0
        let secondX = max(contentView.bounds.width / 2, firstX + maxLeftWidth + 4)
        let lineHeight = ceil(Self.smallFont.lineHeight)
        for (index, views) in itemViews.enumerated() {
            let x = index % 2 == 0 ? firstX : secondX
            let y = 14 + CGFloat(index / 2) * (Self.itemHeight + 18)
            let valueWidth = views.value.sizeThatFits(.zero).width
            views.value.frame = CGRect(x: x, y: y, width: valueWidth, height: ceil(Self.valueFont.lineHeight))
            views.title.frame = CGRect(
                x: x,
                y: views.value.frame.maxY,
                width: views.title.sizeThatFits(.zero).width,
                height: lineHeight,
            )
            views.delta.frame = CGRect(
                x: views.value.frame.maxX + 4,
                y: views.value.frame.maxY - lineHeight - 2,
                width: views.delta.sizeThatFits(.zero).width,
                height: lineHeight,
            )
        }
    }

    static func height(itemCount: Int) -> CGFloat {
        let rows = CGFloat((itemCount + 1) / 2)
        return 14 * 2 + itemHeight * rows + 18 * max(0, rows - 1)
    }

    private func width(of views: ItemViews) -> CGFloat {
        let delta = views.delta.text == nil ? 0 : views.delta.sizeThatFits(.zero).width + 4
        return max(views.value.sizeThatFits(.zero).width + delta, views.title.sizeThatFits(.zero).width)
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

#if DEBUG

    // MARK: - GroupStatisticsProbe

    /// `-ui-probe-group-statistics TITLE`: opens a group's statistics by its title without opening the group itself,
    /// so its messages stay unread. Statistics are only read.
    @MainActor enum GroupStatisticsProbe {
        static func runIfRequested() {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-ui-probe-group-statistics"), index + 1 < arguments.count
            else { return }
            let title = arguments[index + 1]
            Task {
                try? await ProbeFixtures.waitForActiveAccount()
                let client = TDLib.shared.activeClient
                guard let found = try? await client.send(TDNativeRequests.searchChats(
                    query: title,
                    typeFilter: nil,
                    limit: 10,
                )) else { return }
                for id in found.chatIds {
                    guard let chat = try? await client.send(TDNativeRequests.getChat(chatId: id)), chat.title == title
                    else { continue }
                    try? await Task.sleep(for: .seconds(1))
                    NavigationStorage.shared.navigationController.pushViewController(
                        ChannelStatisticsViewController(chat: chat, client: client),
                        animated: true,
                    )
                    return
                }
            }
        }
    }
#endif
