// CustomFolder.swift

import SwiftUI
import TDLibKit

struct CustomFolder: Identifiable, Equatable, Hashable {
    var id: Int {
        return switch type {
        case .main: 0
        case .archive: -1
        case .folder(let info, _): info.id
        }
    }
    var chats: [CustomChat]
    var type: CustomFolderType
    var chatList: ChatList {
        switch type {
        case .main: .chatListMain
        case .archive: .chatListArchive
        case .folder(let info, _): .chatListFolder(.init(chatFolderId: info.id))
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
