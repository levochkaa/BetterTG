// CustomFolder.swift

import SwiftUI
import TDLibKit

@Observable class CustomFolder {
    init(chats: [CustomChat], type: CustomFolderType) {
        self.chats = chats
        self.type = type
    }
    
    var chats: [CustomChat]
    var type: CustomFolderType
    var rect: CGRect = .zero
    
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
    
    var info: ChatFolderInfo? {
        switch type {
        case .folder(let info, _): info
        default: nil
        }
    }
    
    var folder: ChatFolder? {
        switch type {
        case .folder(_, let folder): folder
        default: nil
        }
    }
    
    enum CustomFolderType: Equatable, Hashable {
        case main
        case archive
        case folder(ChatFolderInfo, ChatFolder)
    }
}

extension CustomFolder: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(chats)
        hasher.combine(type)
    }
}

extension CustomFolder: Identifiable {
    var id: Int {
        switch type {
            case .main: 0
            case .archive: -1
            case .folder(let info, _): info.id
        }
    }
}

extension CustomFolder: Equatable {
    static func == (lhs: CustomFolder, rhs: CustomFolder) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
}
