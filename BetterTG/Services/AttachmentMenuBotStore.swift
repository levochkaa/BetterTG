// AttachmentMenuBotStore.swift

import Combine
import Foundation
import TDLibKit

// MARK: - AttachmentMenuBotStore

/// Telegram's `attachMenuBots()`: the attachment and side menu bots TDLib lists in `updateAttachmentMenuBots`, kept
/// per account for the client that sent them. As the list arrives their iOS icons are downloaded: the attachment
/// panel's animated TGS, and the side menu PNG that stands in for the SVG icons BetterTG can't draw.
@MainActor final class AttachmentMenuBotStore {
    struct Entry {
        let bot: TDNativeAttachmentMenuBot
        /// The bot's `iosAnimatedIcon` once on disk.
        var animatedIconPath: String?
        /// The bot's `iosSideMenuIcon` once on disk.
        var imageIconPath: String?
    }

    private struct List {
        let source: TdUpdateSource
        var entries: [Entry]
    }

    static let shared = AttachmentMenuBotStore()

    /// Any change to an account's list, its icons or an accepted side menu disclaimer; Settings' bot rows reload.
    let changes = PassthroughSubject<Void, Never>()

    #if DEBUG
        /// `-ui-probe-attach-bots`: made-up bots in place of every account's.
        private(set) var probeEntries: [Entry]?
    #endif

    private var lists = [UUID: List]()
    private var iconTasks = [UUID: Task<Void, Never>]()
    private var cancellables = Set<AnyCancellable>()

    static func disclaimerKey(accountID: UUID, botUserID: Int64) -> String {
        "bettertg.webAppSideMenuDisclaimer.\(accountID.uuidString).\(botUserID)"
    }

    private static func localPath(of file: File?, client: TDLibClient) async -> String? {
        guard let file else { return nil }
        if file.local.isDownloadingCompleted, !file.local.path.isEmpty { return file.local.path }
        let downloaded = try? await client.downloadFile(
            fileId: file.id,
            limit: 0,
            offset: 0,
            priority: 1,
            synchronous: true,
        )
        guard let downloaded, downloaded.local.isDownloadingCompleted, !downloaded.local.path.isEmpty else {
            return nil
        }
        return downloaded.local.path
    }

    func start() {
        guard cancellables.isEmpty else { return }
        nc.scopedPublisher(&cancellables, for: .updateAttachmentMenuBots) { [weak self] update in
            self?.update(update.value.bots, source: update.source)
        }
    }

    func entries(for source: TdUpdateSource) -> [Entry] {
        #if DEBUG
            if let probeEntries { return probeEntries }
        #endif
        guard let list = lists[source.accountID], list.source == source else { return [] }
        return list.entries
    }

    func entry(botUserID: Int64, source: TdUpdateSource) -> Entry? {
        entries(for: source).first { $0.bot.botUserId == botUserID }
    }

    /// WebAppController's `attachMenuBot`: listed and activated (`!flags.contains(.notActivated)`).
    func isAdded(botUserID: Int64, source: TdUpdateSource) -> Bool {
        entry(botUserID: botUserID, source: source)?.bot.isAdded == true
    }

    /// AttachMenuBots' `.showInSettingsDisclaimer` until `acceptAttachMenuBotDisclaimer` clears it from Telegram's
    /// cached list. TDLib keeps no such state, so the acceptance is kept per account and bot.
    func showsSideMenuDisclaimer(for bot: TDNativeAttachmentMenuBot, accountID: UUID) -> Bool {
        bot.showDisclaimerInSideMenu
            && !UserDefaults.standard.bool(forKey: Self.disclaimerKey(accountID: accountID, botUserID: bot.botUserId))
    }

    func acceptSideMenuDisclaimer(botUserID: Int64, accountID: UUID) {
        UserDefaults.standard.set(true, forKey: Self.disclaimerKey(accountID: accountID, botUserID: botUserID))
        changes.send()
    }

    #if DEBUG
        func setProbeEntries(_ entries: [Entry]) {
            probeEntries = entries
            changes.send()
        }
    #endif

    private func update(_ bots: [TDNativeAttachmentMenuBot], source: TdUpdateSource) {
        let previous = lists[source.accountID].flatMap { $0.source == source ? $0.entries : nil } ?? []
        lists[source.accountID] = List(source: source, entries: bots.map { bot in
            var entry = Entry(bot: bot)
            if let old = previous.first(where: { $0.bot.botUserId == bot.botUserId }) {
                if old.bot.iosAnimatedIcon?.id == bot.iosAnimatedIcon?
                    .id { entry.animatedIconPath = old.animatedIconPath }
                if old.bot.iosSideMenuIcon?.id == bot.iosSideMenuIcon?.id { entry.imageIconPath = old.imageIconPath }
            }
            return entry
        })
        changes.send()
        downloadIcons(source: source)
    }

    private func downloadIcons(source: TdUpdateSource) {
        iconTasks[source.accountID]?.cancel()
        guard let client = TDLib.shared.authorizationClient(for: source) else { return }
        let missing = entries(for: source).filter { $0.animatedIconPath == nil || $0.imageIconPath == nil }
        guard !missing.isEmpty else { return }
        iconTasks[source.accountID] = Task { [weak self] in
            for entry in missing {
                let animated = await Self.localPath(of: entry.bot.iosAnimatedIcon, client: client)
                let image = await Self.localPath(of: entry.bot.iosSideMenuIcon, client: client)
                guard !Task.isCancelled, let self else { return }
                setIcons(animated: animated, image: image, botUserID: entry.bot.botUserId, source: source)
            }
        }
    }

    private func setIcons(animated: String?, image: String?, botUserID: Int64, source: TdUpdateSource) {
        guard var list = lists[source.accountID], list.source == source,
              let index = list.entries.firstIndex(where: { $0.bot.botUserId == botUserID }) else { return }
        list.entries[index].animatedIconPath = animated
        list.entries[index].imageIconPath = image
        lists[source.accountID] = list
        changes.send()
    }
}
