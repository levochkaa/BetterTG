// CustomFolder.swift

import Combine
import TDLibKit

@MainActor final class CustomFolder: ObservableObject {
    // MARK: Internal

    enum CustomFolderType {
        case main
        case archive
        case folder(ChatFolderInfo, ChatFolder)
    }

    @Published var chats: [CustomChat]
    @Published var isLoading = false
    @Published var loadError: String?
    var hasMoreChats = true
    let chatDidChange = PassthroughSubject<Int64, Never>()
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
        self.type = type
    }

    /// Takes the folder's new definition from TDLib. Only a folder keeps its identity; main and archive don't change.
    func update(info: ChatFolderInfo, definition: ChatFolder) {
        guard case .folder(let current, _) = type, current.id == info.id else { return }
        type = .folder(info, definition)
        objectWillChange.send()
    }
}
