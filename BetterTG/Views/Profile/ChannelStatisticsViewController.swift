// ChannelStatisticsViewController.swift

import TDLibKit
import UIKit

// MARK: - ChannelStatisticsViewController

/// ChannelStatsController's overview (StatsOverviewItem) for a channel (getChatStatistics): the period, then
/// Followers, Enabled Notifications, Views Per Post, Shares Per Post, Reactions Per Post and the story means, each with
/// its change over the period, green for growth and red for a fall. While the server prepares the statistics it shows
/// Preparing stats.
final class ChannelStatisticsViewController: SettingsListViewController {
    private let chat: Chat
    private var statistics: TDNativeChatStatisticsChannel?
    private var failed = false

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
        return [SettingsSection(
            header: L10n.telegram("Stats.Overview") + "  " + Self.periodText(statistics.period),
            rows: rows,
        )]
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

    private func load() {
        let client = client
        let chatID = chat.id
        let isDark = traitCollection.userInterfaceStyle == .dark
        Task { [weak self] in
            let result = try? await client.send(TDNativeRequests.getChatStatistics(chatId: chatID, isDark: isDark))
            guard let self, contextIsCurrent else { return }
            if case .chatStatisticsChannel(let channel)? = result {
                statistics = channel
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
