// FolderIcon.swift

import Combine
import TDLibKit
import UIKit

// MARK: - FolderIcon

/// A folder tab's icon, one of TDLib's chat folder icon names (`chatFolderIcon`). A chosen icon syncs as the folder's
/// emoticon, which Telegram Desktop shows; Telegram for iOS has no folder icons.
enum FolderIcon: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
    case unmuted = "Unmuted"
    case bots = "Bots"
    case channels = "Channels"
    case groups = "Groups"
    case `private` = "Private"
    case custom = "Custom"
    case setup = "Setup"
    case cat = "Cat"
    case crown = "Crown"
    case favorite = "Favorite"
    case flower = "Flower"
    case game = "Game"
    case home = "Home"
    case love = "Love"
    case mask = "Mask"
    case party = "Party"
    case sport = "Sport"
    case study = "Study"
    case trade = "Trade"
    case travel = "Travel"
    case work = "Work"
    case airplane = "Airplane"
    case book = "Book"
    case light = "Light"
    case like = "Like"
    case money = "Money"
    case note = "Note"
    case palette = "Palette"

    // MARK: Private

    private enum Source {
        /// Telegram's folder category glyph (`Chat List/Filters`), centred in a 40 pt canvas.
        case asset(String)
        case symbol(String)
    }

    // MARK: Internal

    /// The square a tab draws every icon in beside its 14 pt title, so each lays out alike.
    static let side: CGFloat = 18

    /// Telegram's glyphs span 17 to 23 pt of their 40 pt canvas.
    private static let assetScale: CGFloat = 0.75
    private static let symbolPointSize: CGFloat = 14
    @MainActor private static var images = [String: UIImage]()

    // MARK: Internal

    var title: String { L10n.betterTG("Folders.IconName.\(rawValue)") }

    /// A template image in a `side` square, tinted like the title beside it.
    @MainActor var image: UIImage? { image(side: Self.side) }

    private var source: Source {
        switch self {
        case .all: .asset("FolderAllIcon")
        case .unread: .asset("FolderUnreadIcon")
        case .unmuted: .symbol("bell.fill")
        case .bots: .asset("FolderBotsIcon")
        case .channels: .asset("FolderChannelsIcon")
        case .groups: .asset("FolderGroupsIcon")
        case .private: .asset("FolderPrivateIcon")
        case .custom: .symbol("folder.fill")
        case .setup: .symbol("list.clipboard.fill")
        case .cat: .symbol("cat.fill")
        case .crown: .symbol("crown.fill")
        case .favorite: .symbol("star.fill")
        case .flower: .symbol("camera.macro")
        case .game: .symbol("gamecontroller.fill")
        case .home: .symbol("house.fill")
        case .love: .symbol("heart.fill")
        case .mask: .symbol("theatermasks.fill")
        case .party: .symbol("party.popper.fill")
        case .sport: .symbol("soccerball")
        case .study: .symbol("graduationcap.fill")
        case .trade: .symbol("chart.line.uptrend.xyaxis")
        case .travel: .symbol("suitcase.rolling.fill")
        case .work: .symbol("briefcase.fill")
        case .airplane: .symbol("airplane")
        case .book: .symbol("book.fill")
        case .light: .symbol("lightbulb.fill")
        case .like: .symbol("hand.thumbsup.fill")
        case .money: .symbol("banknote.fill")
        case .note: .symbol("doc.text.fill")
        case .palette: .symbol("paintpalette.fill")
        }
    }

    init(peerType: CustomChat.CustomChatType) {
        self =
            switch peerType {
            case .user: .private
            case .bot: .bots
            case .group: .groups
            case .supergroup(let supergroup): supergroup.isChannel ? .channels : .groups
            }
    }

    /// The icon in a square of the given side, with the glyph scaled from the tab's.
    @MainActor func image(side: CGFloat) -> UIImage? {
        let key = "\(rawValue)@\(side)"
        if let image = Self.images[key] { return image }
        let scale = side / Self.side
        let glyph: UIImage
        let rect: CGRect
        switch source {
        case .asset(let name):
            guard let asset = UIImage(named: "ChatList/\(name)") else { return nil }
            let size = 40 * Self.assetScale * scale
            glyph = asset
            rect = CGRect(x: (side - size) / 2, y: (side - size) / 2, width: size, height: size)
        case .symbol(let name):
            let configuration = UIImage.SymbolConfiguration(pointSize: Self.symbolPointSize * scale, weight: .semibold)
            guard let symbol = UIImage(systemName: name, withConfiguration: configuration) else { return nil }
            let fit = min(1, side / max(symbol.size.width, symbol.size.height))
            let size = CGSize(width: symbol.size.width * fit, height: symbol.size.height * fit)
            glyph = symbol.withTintColor(.black, renderingMode: .alwaysOriginal)
            rect = CGRect(
                x: (side - size.width) / 2,
                y: (side - size.height) / 2,
                width: size.width,
                height: size.height,
            )
        }
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
            .image { _ in glyph.draw(in: rect) }
            .withRenderingMode(.alwaysTemplate)
        Self.images[key] = image
        return image
    }
}

// MARK: - FolderTabStyle

/// What a folder's tab shows. TDLib keeps no such setting, so it stays on this device.
enum FolderTabStyle: String, CaseIterable {
    case iconAndName
    case iconOnly
    case nameOnly

    var title: String {
        switch self {
        case .iconAndName: L10n.betterTG("Folders.Icon.IconAndName")
        case .iconOnly: L10n.betterTG("Folders.Icon.IconOnly")
        case .nameOnly: L10n.betterTG("Folders.Icon.NameOnly")
        }
    }
}

// MARK: - FolderTabAppearance

/// Each account's tab styles by folder ID, and the All Chats tab's chosen icon, which has no TDLib folder to sync
/// through. TDLib reuses a removed folder's ID, so the styles of folders that are gone are dropped.
@MainActor final class FolderTabAppearance {
    static let shared = FolderTabAppearance()

    let changes = PassthroughSubject<Void, Never>()

    private static func stylesKey(_ accountID: UUID) -> String {
        "BetterTG.folderTabStyles.\(accountID.uuidString)"
    }

    private static func mainIconKey(_ accountID: UUID) -> String {
        "BetterTG.folderTabMainIcon.\(accountID.uuidString)"
    }

    func style(of folderID: Int, accountID: UUID?) -> FolderTabStyle {
        guard let accountID else { return .iconAndName }
        return styles(accountID: accountID)[String(folderID)].flatMap(FolderTabStyle.init(rawValue:)) ?? .iconAndName
    }

    func setStyle(_ style: FolderTabStyle, of folderID: Int, accountID: UUID?) {
        guard let accountID, self.style(of: folderID, accountID: accountID) != style else { return }
        var styles = styles(accountID: accountID)
        styles[String(folderID)] = style == .iconAndName ? nil : style.rawValue
        UserDefaults.standard.set(styles, forKey: Self.stylesKey(accountID))
        changes.send()
    }

    /// The All Chats tab's icon; nil shows its automatic one.
    func mainIcon(accountID: UUID?) -> FolderIcon? {
        guard let accountID else { return nil }
        return UserDefaults.standard.string(forKey: Self.mainIconKey(accountID)).flatMap(FolderIcon.init(rawValue:))
    }

    func setMainIcon(_ icon: FolderIcon?, accountID: UUID?) {
        guard let accountID, mainIcon(accountID: accountID) != icon else { return }
        UserDefaults.standard.set(icon?.rawValue, forKey: Self.mainIconKey(accountID))
        changes.send()
    }

    /// Drops the styles of folders the account no longer has; All Chats (0) stays.
    func keepStyles(of folderIDs: Set<Int>, accountID: UUID?) {
        guard let accountID else { return }
        let styles = styles(accountID: accountID)
        let kept = styles.filter { key, _ in Int(key).map { $0 == 0 || folderIDs.contains($0) } ?? false }
        guard kept.count != styles.count else { return }
        UserDefaults.standard.set(kept, forKey: Self.stylesKey(accountID))
        changes.send()
    }

    private func styles(accountID: UUID) -> [String: String] {
        UserDefaults.standard.dictionary(forKey: Self.stylesKey(accountID)) as? [String: String] ?? [:]
    }
}

// MARK: - ChatFolder + FolderIcon

extension ChatFolder {
    /// The icon the user chose; nil leaves the folder to its automatic icon.
    var chosenIcon: FolderIcon? {
        icon.flatMap { FolderIcon(rawValue: $0.name) }
    }

    /// The icon until the user picks one, from the chats in TDLib's chat list store.
    @MainActor var automaticIcon: FolderIcon {
        automaticIcon(peerType: TelegramChatListStore.shared.peerType(chatID:))
    }

    /// TDLib's getChatFolderDefaultIconName answers Custom once a folder has chosen chats. Here the chat types decide:
    /// one kind of chat gives its icon whatever chats the folder also includes or excludes, and a folder of chosen
    /// chats alone takes the kind at least three in four of its known chats share.
    func automaticIcon(peerType: (Int64) -> CustomChat.CustomChatType?) -> FolderIcon {
        let types = Set(ChatFolderInclusion.allCases.filter(includes))
        if !types.isEmpty {
            if types.isSubset(of: [.contacts, .nonContacts]) { return .private }
            if types == [.groups] { return .groups }
            if types == [.channels] { return .channels }
            if types == [.bots] { return .bots }
        } else {
            var counts = [FolderIcon: Int]()
            for id in alwaysIncludedChatIDs {
                guard let type = peerType(id) else { continue }
                counts[FolderIcon(peerType: type), default: 0] += 1
            }
            let known = counts.values.reduce(0, +)
            if let (icon, count) = counts.max(by: { $0.value < $1.value }), count * 4 >= known * 3 {
                return icon
            }
        }
        if excludeRead { return .unread }
        if excludeMuted { return .unmuted }
        return types.count == ChatFolderInclusion.allCases.count ? .all : .custom
    }

    func replacingIcon(_ icon: FolderIcon?) -> ChatFolder {
        ChatFolder(
            colorId: colorId,
            excludeArchived: excludeArchived,
            excludeMuted: excludeMuted,
            excludeRead: excludeRead,
            excludedChatIds: excludedChatIds,
            icon: icon.map { ChatFolderIcon(name: $0.rawValue) },
            includeBots: includeBots,
            includeChannels: includeChannels,
            includeContacts: includeContacts,
            includeGroups: includeGroups,
            includeNonContacts: includeNonContacts,
            includedChatIds: includedChatIds,
            isShareable: isShareable,
            name: name,
            pinnedChatIds: pinnedChatIds,
        )
    }
}

// MARK: - CustomFolder + FolderIcon

extension CustomFolder {
    /// The folder's chosen or automatic icon, whether or not its tab shows it.
    var icon: FolderIcon? {
        switch type {
        case .main: FolderTabAppearance.shared.mainIcon(accountID: TDLib.shared.activeAccountID) ?? .all
        case .archive: nil
        case .folder(_, let definition): definition.chosenIcon ?? definition.automaticIcon
        }
    }

    var tabStyle: FolderTabStyle {
        FolderTabAppearance.shared.style(of: id, accountID: TDLib.shared.activeAccountID)
    }
}
