// WebAppLaunchProbe.swift

#if DEBUG
    import TDLibKit
    import UIKit

    /// Launch with `-ui-probe-attach-bots` to open the attachment sheet with three made-up attachment menu bots after
    /// Gallery: Shop (not added, with a PNG icon), Games (added, with a PNG icon) and Probe (added, the generic glyph
    /// until an icon is on disk). The bots show in every chat's attachment sheet as well. Shop's tab runs the terms
    /// first; each tab then opens the Web App probe page at half height.
    /// Launch with `-ui-probe-main-web-app` to open the profile of the first bot chat, or else the first chat, with
    /// Open App under its bio; the button runs the terms and opens the probe page at full size.
    /// Launch with `-ui-probe-bot-menu-button` to open the first bot chat, or else the first chat, with an "Open
    /// Probe" Web App menu button in place of Menu; the button shows the launch confirmation and then the probe page at
    /// half height.
    /// In all of them, WebAppLauncher puts the probe page in place of every launch and adding a bot only closes the
    /// terms: no openWebApp, getMainWebApp or toggleBotIsAddedToAttachmentMenu reaches TDLib and nothing is sent.
    @MainActor enum WebAppLaunchProbe {
        private static var launcher: WebAppLauncher?

        static func runIfRequested(in window: UIWindow) {
            let arguments = ProcessInfo.processInfo.arguments
            let showsAttachBots = arguments.contains("-ui-probe-attach-bots")
            let showsMainWebApp = arguments.contains("-ui-probe-main-web-app")
            let showsMenuButton = arguments.contains("-ui-probe-bot-menu-button")
            guard showsAttachBots || showsMainWebApp || showsMenuButton else { return }
            WebAppLauncher.probeHTML = WebAppProbe.page
            PeerProfileViewController.probeShowsOpenApp = showsMainWebApp
            if showsAttachBots { AttachmentMenuBotStore.shared.setProbeEntries(probeEntries()) }
            Task { @MainActor in
                for _ in 0..<60 where TDLib.shared.activeAccountID == nil {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                guard let accountID = TDLib.shared.activeAccountID else { return }
                try? await Task.sleep(for: .seconds(2))
                guard let presenter = topController(in: window) else { return }
                if showsMenuButton {
                    await presentMenuButtonChat()
                } else if showsMainWebApp {
                    await presentProfile(accountID: accountID, window: window, from: presenter)
                } else {
                    presentAttachmentSheet(accountID: accountID, window: window, from: presenter)
                }
            }
        }

        private static func probeChats() async -> [CustomChat] {
            var chats = [CustomChat]()
            for _ in 0..<20 {
                var seen = Set<Int64>()
                chats = RootVM.shared.allFolders.flatMap(\.chats).filter {
                    seen.insert($0.id).inserted && !$0.isSavedMessages
                }
                if !chats.isEmpty { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            return chats
        }

        /// The chat's composer shows the made-up menu button; its tap goes to WebAppLauncher's probe path.
        private static func presentMenuButtonChat() async {
            let chats = await probeChats()
            guard let chat = chats.first(where: { $0.bot != nil }) ?? chats.first else { return }
            ChatVM.probeBotMenuButton = (
                chat.id,
                TDNativeBotMenuButton(text: "Open Probe", url: "https://bettertg.probe/"),
            )
            let client = TDLib.shared.activeClient
            NavigationStorage.shared.navigationController.pushViewController(
                ChatViewController(customChat: chat, location: .current(chatID: chat.id, client: client)),
                animated: true,
            )
        }

        private static func probeEntries() -> [AttachmentMenuBotStore.Entry] {
            let bots: [(id: Int64, name: String, symbol: String?, isAdded: Bool)] = [
                (-101, "Shop", "cart.fill", false),
                (-102, "Games", "gamecontroller.fill", true),
                (-103, "Probe", nil, true),
            ]
            return bots.map { item in
                AttachmentMenuBotStore.Entry(
                    bot: TDNativeAttachmentMenuBot(
                        botUserId: item.id,
                        supportsSelfChat: true,
                        supportsUserChats: true,
                        supportsBotChats: true,
                        supportsGroupChats: true,
                        supportsChannelChats: true,
                        requestWriteAccess: !item.isAdded,
                        isAdded: item.isAdded,
                        showInAttachmentMenu: true,
                        showInSideMenu: false,
                        showDisclaimerInSideMenu: false,
                        name: item.name,
                        nameColor: nil,
                        defaultIcon: nil,
                        iosStaticIcon: nil,
                        iosAnimatedIcon: nil,
                        iosSideMenuIcon: nil,
                        androidIcon: nil,
                        androidSideMenuIcon: nil,
                        macosIcon: nil,
                        macosSideMenuIcon: nil,
                        iconColor: nil,
                        webAppPlaceholder: nil,
                    ),
                    imageIconPath: item.symbol.flatMap { iconPath(symbol: $0) },
                )
            }
        }

        /// A side menu icon stand-in: the symbol drawn black on clear, which the panel tints as a template.
        private static func iconPath(symbol: String) -> String? {
            let configuration = UIImage.SymbolConfiguration(pointSize: 44, weight: .regular)
            guard let image = UIImage(systemName: symbol, withConfiguration: configuration) else { return nil }
            let data = UIGraphicsImageRenderer(size: image.size).pngData { _ in
                image.withTintColor(.black).draw(at: .zero)
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("attach-bot-probe-\(symbol).png")
            guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
            return url.path
        }

        private static func presentAttachmentSheet(
            accountID: UUID,
            window: UIWindow,
            from presenter: UIViewController,
        ) {
            let entries = AttachmentMenuBotStore.shared.probeEntries ?? []
            var tabs: [AttachmentSheetTab] = [.gallery]
            tabs += entries.map { entry in
                AttachmentSheetTab.app(AttachmentMenuBotButton(
                    botUserID: entry.bot.botUserId,
                    name: entry.bot.name,
                    animatedIconPath: entry.animatedIconPath,
                    imageIconPath: entry.imageIconPath,
                ))
            }
            tabs += [.file, .location, .poll, .contact, .sticker]
            let sheet = AttachmentSheetViewController(configuration: AttachmentSheetConfiguration(
                allowsPhotos: true,
                allowsVideos: true,
                tabs: tabs,
            ))
            let launcher = makeLauncher(accountID: accountID, window: window)
            sheet.onSelectTab = { tab in
                guard case .app(let bot) = tab,
                      let entry = entries.first(where: { $0.bot.botUserId == bot.botUserID })
                else { return }
                launcher.openAttachmentMenuBot(
                    botUserID: bot.botUserID,
                    name: bot.name,
                    isAdded: entry.bot.isAdded,
                    chatID: 0,
                    topic: nil,
                    replyTo: nil,
                )
            }
            presenter.present(sheet.makeNavigationController(), animated: true)
        }

        private static func presentProfile(accountID: UUID, window: UIWindow, from presenter: UIViewController) async {
            var chats = [CustomChat]()
            for _ in 0..<20 {
                var seen = Set<Int64>()
                chats = RootVM.shared
.allFolders
.flatMap(\.chats)
                    .filter { seen.insert($0.id).inserted && !$0.isSavedMessages }
                if !chats.isEmpty { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard let chat = chats.first(where: { $0.bot != nil }) ?? chats.first else { return }
            let profile = PeerProfileViewController(
                customChat: chat,
                topic: nil,
                client: TDLib.shared.activeClient,
                accountID: accountID,
            )
            if presenter === window.rootViewController, let navigation = firstNavigation(in: presenter) {
                navigation.pushViewController(profile, animated: true)
            } else {
                presenter.present(TelegramNavigationController(rootViewController: profile), animated: true)
            }
        }

        private static func makeLauncher(accountID: UUID, window: UIWindow) -> WebAppLauncher {
            let created = WebAppLauncher(host: .init(
                accountID: accountID,
                client: TDLib.shared.activeClient,
                presenter: { [weak window] in window.flatMap { topController(in: $0) } },
                isCurrent: { true },
                actions: .init(openTelegramLink: { _ in }, switchInline: { _, _ in }),
            ))
            launcher = created
            return created
        }

        private static func topController(in window: UIWindow) -> UIViewController? {
            var presenter = window.rootViewController
            while let presented = presenter?.presentedViewController {
                presenter = presented
            }
            return presenter
        }

        private static func firstNavigation(in controller: UIViewController?) -> UINavigationController? {
            guard let controller else { return nil }
            if let navigation = controller as? UINavigationController { return navigation }
            return controller.children.lazy.compactMap { firstNavigation(in: $0) }.first
        }
    }
#endif
