// OldChannelsViewController.swift

import TDLibKit
import UIKit

// MARK: - OldChannelsViewController

/// Telegram's OldChannelsController for the "CHANNELS_TOO_MUCH" error: Limit Reached, the limit's explanation, and
/// MOST INACTIVE (getInactiveSupergroupChats) with each chat's kind, members and how long it has been quiet, any of
/// which can be checked and left at once (Leave N Chats). BetterTG offers no Premium, so the explanation is Telegram's
/// text for Premium being unavailable, and its final text once even Premium's limit is reached.
final class OldChannelsViewController: SettingsListViewController {
    /// OldChannelsControllerIntent: what the limit stopped.
    enum Intent {
        case join
        case create
        case upgrade
    }

    private struct InactiveChat {
        let chat: Chat
        let isChannel: Bool
        let memberCount: Int
    }

    private let intent: Intent
    private let onLeft: (() -> Void)?
    private var chats: [InactiveChat]?
    private var selected = Set<Int64>()
    private var limit = 500
    private var premiumLimit = 1000
    private var isLeaving = false

    init(intent: Intent, onLeft: (() -> Void)? = nil) {
        self.intent = intent
        self.onLeft = onLeft
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("OldChannels.Title")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(closePressed),
        )
        navigationItem.leftBarButtonItem?.accessibilityLabel = L10n.telegram("Common.Close")
        load()
    }

    override func makeSections() -> [SettingsSection] {
        guard let chats else { return [SettingsSection(rows: [ChatManagementRows.loading])] }
        var sections = [SettingsSection(rows: [SettingsRow(title: infoText(count: chats.count), style: .subtitle)])]
        if !chats.isEmpty {
            let now = Int(Date().timeIntervalSince1970)
            sections.append(SettingsSection(
                header: L10n.telegram("OldChannels.ChannelsHeader"),
                rows: chats.map { inactive in
                    SettingsRow(
                        title: inactive.chat.title,
                        detail: Self.subtitle(for: inactive, now: now),
                        style: .peer(SettingsPeer(chat: inactive.chat)),
                        accessory: selected.contains(inactive.chat.id) ? .checkmark : .none,
                    ) { [weak self] in self?.toggle(inactive.chat.id) }
                },
            ))
        }
        return sections
    }

    /// inactiveDescription: "channel, " or "N members, " and how long since the chat's last message, in weeks this
    /// month, months this year, else years (a year and a half counting as two).
    private static func subtitle(for inactive: InactiveChat, now: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(inactive.chat.lastMessage?.date ?? now))
        let calendar = Calendar.current
        let then = calendar.dateComponents([.year, .month, .day], from: date)
        let today = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: TimeInterval(now)))
        var text: String
        if then.year == today.year, then.month == today.month {
            let weeks = Int((Float((today.day ?? 0) - (then.day ?? 0)) / 7).rounded())
            text = L10n.telegramPlural("OldChannels.InactiveWeek", count: weeks)
        } else if then.year == today.year {
            text = L10n.telegramPlural("OldChannels.InactiveMonth", count: (today.month ?? 0) - (then.month ?? 0))
        } else {
            var years = (today.year ?? 0) - (then.year ?? 0)
            if (today.month ?? 0) - (then.month ?? 0) > 6 { years += 1 }
            text = L10n.telegramPlural("OldChannels.InactiveYear", count: years)
        }
        if inactive.isChannel {
            return L10n.telegram("OldChannels.ChannelFormat") + text
        }
        if inactive.memberCount > 0 {
            return L10n.telegramPlural("OldChannels.GroupFormat", count: inactive.memberCount) + ", " + text
        }
        return L10n.telegram("OldChannels.GroupEmptyFormat") + ", " + text
    }

    /// oldChannelsEntries' text: the final one past Premium's limit, otherwise Premium-unavailable's.
    private func infoText(count chatCount: Int) -> String {
        let count = max(limit, chatCount)
        if count >= premiumLimit {
            let key =
                switch intent {
                case .create: "OldChannels.TooManyCommunitiesCreateFinalText"
                case .upgrade: "OldChannels.TooManyCommunitiesUpgradeFinalText"
                case .join: "OldChannels.TooManyCommunitiesFinalText"
                }
            return L10n.telegram(key, "\(premiumLimit)").withoutTelegramMarkup
        }
        return switch intent {
        case .create: L10n.telegram("OldChannels.TooManyCommunitiesCreateNoPremiumText", "\(premiumLimit)")
            .withoutTelegramMarkup
        case .upgrade: L10n.telegram("OldChannels.TooManyCommunitiesUpgradeNoPremiumText", "\(premiumLimit)")
            .withoutTelegramMarkup
        case .join: L10n.telegram("OldChannels.TooManyCommunitiesNoPremiumText", "\(count)").withoutTelegramMarkup
        }
    }

    private func load() {
        let client = client
        Task { [weak self] in
            if let value = try? await client.send(TDNativeRequests.getPremiumLimit(
                limitType: .premiumLimitTypeSupergroupCount,
            )) {
                self?.limit = value.defaultValue
                self?.premiumLimit = value.premiumValue
            }
            let ids = await (try? client.send(TDNativeRequests.getInactiveSupergroupChats()))?.chatIds ?? []
            var loaded = [InactiveChat]()
            for id in ids {
                guard let chat = try? await client.getChat(chatId: id) else { continue }
                var isChannel = false
                var memberCount = 0
                if case .chatTypeSupergroup(let type) = chat.type {
                    isChannel = type.isChannel
                    memberCount = await (try? client.send(TDNativeRequests.getSupergroup(
                        supergroupId: type.supergroupId,
                    )))?.memberCount ?? 0
                }
                loaded.append(InactiveChat(chat: chat, isChannel: isChannel, memberCount: memberCount))
            }
            // inactiveChannelList sorts the quietest first.
            loaded.sort { ($0.chat.lastMessage?.date ?? 0) < ($1.chat.lastMessage?.date ?? 0) }
            guard let self, contextIsCurrent else { return }
            chats = loaded
            reload()
        }
    }

    private func toggle(_ id: Int64) {
        guard !isLeaving else { return }
        if selected.remove(id) == nil { selected.insert(id) }
        refreshRowsInPlace()
        updateLeaveButton()
    }

    /// IncreaseLimitFooterItem: Leave N Chats under the list while chats are chosen.
    private func updateLeaveButton() {
        guard !selected.isEmpty else {
            navigationController?.setToolbarHidden(true, animated: true)
            return
        }
        let title = L10n.telegramPlural(
            "OldChannels.LeaveCommunities",
            count: selected.count,
            formattedCount: selected.count.formatted(.number),
        )
        let button = UIBarButtonItem(title: title, style: .prominent, target: self, action: #selector(leavePressed))
        button.tintColor = .systemRed
        button.isEnabled = !isLeaving
        toolbarItems = [.flexibleSpace(), button, .flexibleSpace()]
        navigationController?.setToolbarHidden(false, animated: true)
    }

    @objc private func leavePressed() {
        leaveSelected()
    }

    /// leaveActionImpl: every chosen chat is left (removePeerChats), then the screen closes.
    private func leaveSelected() {
        guard !isLeaving, contextIsCurrent else { return }
        isLeaving = true
        updateLeaveButton()
        let client = client
        let ids = Array(selected)
        Task { [weak self] in
            for id in ids {
                _ = try? await client.send(TDNativeRequests.leaveChat(chatId: id))
            }
            guard let self else { return }
            onLeft?()
            closePressed()
        }
    }

    @objc private func closePressed() {
        if let navigationController, navigationController.viewControllers.first !== self {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
}

#if DEBUG
    extension OldChannelsViewController {
        /// `-ui-probe-old-channels`: the screen as a join over the limit opens it, to look at it without reaching the
        /// limit.
        static func presentIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-old-channels") else { return }
            Task {
                try? await ProbeFixtures.waitForActiveAccount()
                var top = window.rootViewController
                while let presented = top?.presentedViewController {
                    top = presented
                }
                top?.present(
                    UINavigationController(rootViewController: OldChannelsViewController(intent: .join)),
                    animated: true,
                )
            }
        }
    }
#endif
