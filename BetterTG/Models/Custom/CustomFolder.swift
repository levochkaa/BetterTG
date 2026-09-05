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
    let type: CustomFolderType

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
}
