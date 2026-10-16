// ComposeContacts.swift

import TDLibKit
import UIKit

// MARK: - ComposeFlowScreen

/// A screen of Telegram's compose flow (New Message, New Group, New Secret Chat, New Channel, New Contact). What the
/// flow opens takes its place in the stack (NavigationStorage.replaceComposeFlow), as Telegram replaces its compose
/// controllers with the chat.
@MainActor protocol ComposeFlowScreen: UIViewController {}

// MARK: - ComposeContact

/// A person in Telegram's contact lists (ContactListNode): the name, presence and avatar.
struct ComposeContact {
    let userID: Int64
    let firstName: String
    let lastName: String
    let status: UserStatus
    let isBot: Bool
    let username: String?
    /// The number the account sees, without the plus; empty when the person hides it.
    let phoneNumber: String
    let peer: SettingsPeer

    var title: String {
        peer.title
    }

    /// Telegram's peerTokenTitle for a selected person's chip: the first name, else the whole name.
    var tokenTitle: String {
        firstName.isEmpty ? title : firstName
    }

    /// ContactListNode's subtitle: the presence, or "bot".
    var statusText: (text: String, isOnline: Bool) {
        isBot ? (text: L10n.telegram("Bot.GenericBotStatus"), isOnline: false) : UserPresenceText.text(for: status)
    }

    init(user: User) {
        self.userID = user.id
        self.firstName = user.firstName
        self.lastName = user.lastName
        self.status = user.status
        self.isBot =
            if case .userTypeBot = user.type {
                true
            } else {
                false
            }
        self.username = user.usernames?.activeUsernames.first
        self.phoneNumber = user.phoneNumber
        let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        self.peer = SettingsPeer(
            id: user.id,
            title: name.isEmpty ? L10n.telegram("User.DeletedAccount") : name,
            file: user.profilePhoto?.small,
            minithumbnail: user.profilePhoto?.minithumbnail,
            placeholder: user.telegramAvatarPlaceholder,
        )
    }

    /// The person's row: the avatar, the name and the presence, blue while online.
    func row(accessory: SettingsRow.Accessory = .none, action: (() -> Void)?) -> SettingsRow {
        let status = statusText
        return SettingsRow(
            title: title,
            detail: status.text,
            detailColor: status.isOnline ? .systemBlue : nil,
            style: .peer(peer),
            accessory: accessory,
            action: action,
        )
    }
}

// MARK: - ComposeFoundChat

/// A chat found on the server (ContactsSearchContainerNode's Global Search): a person or a public group or channel.
struct ComposeFoundChat {
    let chatID: Int64
    let peer: SettingsPeer
    let detail: String?
    /// The person, for a private chat.
    let user: ComposeContact?
}

// MARK: - ComposeContactSort

/// Telegram's contact list orders (ContactsSortOrder): by name with letter sections, or by last seen time.
enum ComposeContactSort: String {
    case name
    case presence

    private static let storageKey = "Compose.ContactSortOrder"

    /// The compose list starts by name, as Telegram's ComposeController shows its contacts.
    static var saved: ComposeContactSort {
        get { UserDefaults.standard.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .name }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) }
    }
}

// MARK: - ComposeContactSection

struct ComposeContactSection {
    let title: String?
    /// The section index letter, in the name order.
    let indexTitle: String?
    let contacts: [ComposeContact]

    /// ContactListNode's `.natural` order: by first then last name, under the first letter, with names that don't
    /// start with a letter under "#" at the end; `.orderedByPresence`: the most recently seen first.
    static func sections(_ contacts: [ComposeContact], sort: ComposeContactSort) -> [ComposeContactSection] {
        switch sort {
        case .presence:
            let sorted = contacts.sorted { lhs, rhs in
                let left = UserPresenceText.rank(lhs.status)
                let right = UserPresenceText.rank(rhs.status)
                if left != right { return left > right }
                return lhs.userID < rhs.userID
            }
            guard !sorted.isEmpty else { return [] }
            return [ComposeContactSection(
                title: L10n.telegram("Contacts.SortedByPresence"),
                indexTitle: nil,
                contacts: sorted,
            )]
        case .name:
            let sorted = contacts.sorted { lhs, rhs in
                let order = sortName(lhs).localizedStandardCompare(sortName(rhs))
                return order == .orderedSame ? lhs.userID < rhs.userID : order == .orderedAscending
            }
            var letters = [String]()
            var grouped = [String: [ComposeContact]]()
            for contact in sorted {
                let letter = indexLetter(contact)
                if grouped[letter] == nil { letters.append(letter) }
                grouped[letter, default: []].append(contact)
            }
            if let hash = letters.firstIndex(of: "#") {
                letters.append(letters.remove(at: hash))
            }
            return letters.map { ComposeContactSection(title: $0, indexTitle: $0, contacts: grouped[$0] ?? []) }
        }
    }

    private static func sortName(_ contact: ComposeContact) -> String {
        [contact.firstName, contact.lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func indexLetter(_ contact: ComposeContact) -> String {
        let name = contact.firstName.isEmpty ? contact.lastName : contact.firstName
        guard let first = name.folding(options: .diacriticInsensitive, locale: .current).uppercased().first,
              first.isLetter, first.isUppercase
        else { return "#" }
        return String(first)
    }
}

// MARK: - UserPresenceText

/// Telegram's stringAndActivityForUserPresence (PresenceStrings) in its short form, and the presence order its
/// contact list sorts by.
enum UserPresenceText {
    static func text(
        for status: UserStatus,
        now: Int = Int(Foundation.Date().timeIntervalSince1970),
    ) -> (text: String, isOnline: Bool) {
        switch status {
        case .userStatusOnline(let online):
            if online.expires >= now { return (L10n.telegram("Presence.online"), true) }
            return (lastSeen(online.expires, now: now), false)
        case .userStatusOffline(let offline):
            return (lastSeen(offline.wasOnline, now: now), false)
        case .userStatusRecently:
            return (L10n.telegram("LastSeen.Lately"), false)
        case .userStatusLastWeek:
            return (L10n.telegram("LastSeen.WithinAWeek"), false)
        case .userStatusLastMonth:
            return (L10n.telegram("LastSeen.WithinAMonth"), false)
        case .userStatusEmpty:
            return (L10n.telegram("LastSeen.ALongTimeAgo"), false)
        }
    }

    /// EnginePeer.Presence.Status order: an exact time (the latest first), then recently, within a week, within a
    /// month and a long time ago.
    static func rank(_ status: UserStatus) -> (Int, Int) {
        switch status {
        case .userStatusOnline(let online): (5, online.expires)
        case .userStatusOffline(let offline): (5, offline.wasOnline)
        case .userStatusRecently: (4, 0)
        case .userStatusLastWeek: (3, 0)
        case .userStatusLastMonth: (2, 0)
        case .userStatusEmpty: (1, 0)
        }
    }

    private static func lastSeen(_ timestamp: Int, now: Int) -> String {
        let difference = now - timestamp
        if difference < 60 { return L10n.telegram("LastSeen.JustNow") }
        if difference < 60 * 60 {
            return L10n.telegramPlural("LastSeen.MinutesAgo", count: difference / 60)
        }
        let calendar = Calendar.current
        let date = Foundation.Date(timeIntervalSince1970: TimeInterval(timestamp))
        let current = Foundation.Date(timeIntervalSince1970: TimeInterval(now))
        let dateText = date.formatted(date: .numeric, time: .omitted)
        guard calendar.component(.year, from: date) == calendar.component(.year, from: current) else {
            return L10n.telegram("LastSeen.AtDate", dateText)
        }
        if calendar.isDate(date, inSameDayAs: current) {
            return L10n.telegramPlural("LastSeen.HoursAgo", count: difference / (60 * 60))
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: current),
           calendar.isDate(date, inSameDayAs: yesterday)
        {
            return L10n.telegram("LastSeen.YesterdayAt", date.formatted(date: .omitted, time: .shortened))
        }
        return L10n.telegram("LastSeen.AtDate", dateText)
    }
}

// MARK: - ComposeContacts

/// The requests behind Telegram's contact lists, on one client. A list keeps the order TDLib returns.
@MainActor enum ComposeContacts {
    private static let searchLimit = 50

    /// getContacts without the account itself.
    static func load(client: TDLibClient) async -> [ComposeContact]? {
        guard let ids = try? await client.send(TDNativeRequests.getContacts()).userIds else { return nil }
        let me = try? await client.getMe()
        return await users(ids.filter { $0 != me?.id }, client: client)
    }

    static func users(_ ids: [Int64], client: TDLibClient) async -> [ComposeContact] {
        var result = [ComposeContact]()
        var seen = Set<Int64>()
        for id in ids where seen.insert(id).inserted {
            guard !Task.isCancelled else { break }
            if let user = try? await client.getUser(userId: id) {
                result.append(ComposeContact(user: user))
            }
        }
        return result
    }

    /// ContactsSearchContainerNode: the contacts matching the query (searchContacts), then chats found on the server
    /// (searchPublicChats). `usersOnly` keeps the people, for the member pickers.
    static func search(
        _ query: String,
        usersOnly: Bool,
        client: TDLibClient,
    ) async -> (contacts: [ComposeContact], global: [ComposeFoundChat]) {
        let me = try? await client.getMe()
        let contactIDs = await (try? client.searchContacts(query: query, limit: searchLimit))?.userIds ?? []
        let contacts = await users(contactIDs.filter { $0 != me?.id }, client: client)
        let known = Set(contacts.map(\.userID))
        let chatIDs = await (try? client.searchPublicChats(query: query, typeFilter: nil))?.chatIds ?? []
        var global = [ComposeFoundChat]()
        for chatID in chatIDs {
            guard !Task.isCancelled else { break }
            guard let chat = try? await client.getChat(chatId: chatID) else { continue }
            switch chat.type {
            case .chatTypePrivate(let value):
                guard value.userId != me?.id, !known.contains(value.userId),
                      let user = try? await client.getUser(userId: value.userId)
                else { continue }
                let contact = ComposeContact(user: user)
                global.append(ComposeFoundChat(
                    chatID: chatID,
                    peer: contact.peer,
                    detail: contact.username.map { "@\($0)" },
                    user: contact,
                ))
            case .chatTypeSupergroup(let value):
                guard !usersOnly else { continue }
                let group = try? await client.getSupergroup(supergroupId: value.supergroupId)
                let count = group?.memberCount ?? 0
                let members = count > 0
                    ? L10n.telegramPlural(
                        value.isChannel ? "Conversation.StatusSubscribers" : "Conversation.StatusMembers",
                        count: count,
                        formattedCount: count.formatted(.number),
                    )
                    : nil
                let username = group?.usernames?.activeUsernames.first.map { "@\($0)" }
                let detail = [username, members].compactMap(\.self).joined(separator: ", ")
                global.append(ComposeFoundChat(
                    chatID: chatID,
                    peer: SettingsPeer(chat: chat),
                    detail: detail.isEmpty ? nil : detail,
                    user: nil,
                ))
            case .chatTypeBasicGroup, .chatTypeSecret:
                continue
            }
        }
        return (contacts, global)
    }

    /// Opens a chat in place of the compose flow; false when TDLib doesn't have it or the flow is no longer current.
    static func open(chatID: Int64, client: TDLibClient, isCurrent: () -> Bool) async -> Bool {
        guard let chat = await RootVM.shared.getCustomChatForNavigation(from: chatID, client: client),
              isCurrent()
        else { return false }
        NavigationStorage.shared.replaceComposeFlow(with: .customChat(chat))
        return true
    }

    /// The person's chat (createPrivateChat, which TDLib makes locally for a known user), in place of the flow.
    static func openPrivateChat(userID: Int64, client: TDLibClient, isCurrent: () -> Bool) async -> Bool {
        guard let chat = try? await client.createPrivateChat(force: false, userId: userID), isCurrent() else {
            return false
        }
        return await open(chatID: chat.id, client: client, isCurrent: isCurrent)
    }
}
