// CustomFolder.swift

import Combine
import TDLibKit

// MARK: - CustomFolder

@MainActor final class CustomFolder: ObservableObject {
    // MARK: Internal

    enum CustomFolderType {
        case main
        case archive
        case folder(ChatFolderInfo, ChatFolder)
    }

    @Published var chats: [CustomChat] {
        didSet {
            chatsByID = Self.index(chats)
            chatsGeneration += 1
        }
    }

    /// The folder's chats by ID, so a chat update finds its row without walking the list.
    private(set) var chatsByID: [Int64: CustomChat]
    /// Grows whenever `chats` is set, so a page rebuilds what it derives from the membership only when it changed.
    private(set) var chatsGeneration = 0
    @Published var isLoading = false
    @Published var loadError: String?
    var hasMoreChats = true
    let chatsDidChange = PassthroughSubject<Set<Int64>, Never>()
    /// A folder's definition can change (name, included chats); the object, its page and its rows stay.
    private(set) var type: CustomFolderType

    var id: Int {
        switch type {
        case .main: 0
        case .archive: -1
        case .folder(let info, _): Int(info.id)
        }
    }

    var chatList: ChatList {
        switch type {
        case .main: .chatListMain
        case .archive: .chatListArchive
        case .folder(let info, _): .chatListFolder(ChatListFolder(chatFolderId: info.id))
        }
    }

    var name: String {
        switch type {
        case .main: L10n.telegram("ChatList.Tabs.All")
        case .archive: L10n.telegram("ChatList.Context.Archive")
        case .folder(let info, _): info.name.text.text
        }
    }

    init(chats: [CustomChat], type: CustomFolderType) {
        self.chats = chats
        self.chatsByID = Self.index(chats)
        self.type = type
    }

    private static func index(_ chats: [CustomChat]) -> [Int64: CustomChat] {
        Dictionary(chats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Takes the folder's new definition from TDLib. Only a folder keeps its identity; main and archive don't change.
    func update(info: ChatFolderInfo, definition: ChatFolder) {
        guard case .folder(let current, _) = type, current.id == info.id else { return }
        type = .folder(info, definition)
        objectWillChange.send()
    }
}

@MainActor extension [CustomChat] {
    /// TDLib's list order. A row's order goes through `@Published` and the native object, so it's read once per row.
    func sortedByListOrder() -> [CustomChat] {
        let rows: [(chat: CustomChat, order: Int64)] = map { ($0, $0.position.order) }
        return rows
            .sorted { $0.order == $1.order ? $0.chat.id > $1.chat.id : $0.order > $1.order }
            .map(\.chat)
    }
}
