// CustomFolder.swift

import Combine
import TDLibKitDynamic

@MainActor final class CustomFolder: ObservableObject {
    // MARK: Internal

    enum CustomFolderType: Equatable, Hashable {
        case main
        case archive
        case folder(ChatFolderInfo, ChatFolder)
    }

    @Published var chats: [CustomChat]
    let chatDidChange = PassthroughSubject<Int64, Never>()
    let type: CustomFolderType

    var id: Int {
        switch type {
        case .main: 0
        case .archive: -1
        case .folder(let info, _): info.id
        }
    }

    var chatList: ChatList {
        switch type {
        case .main: .chatListMain
        case .archive: .chatListArchive
        case .folder(let info, _): .chatListFolder(.init(chatFolderId: info.id))
        }
    }

    var name: String {
        switch type {
        case .main: "All"
        case .archive: "Archive"
        case .folder(let info, _): info.name.text.text
        }
    }

    init(chats: [CustomChat], type: CustomFolderType) {
        self.chats = chats
        self.type = type
    }
}
