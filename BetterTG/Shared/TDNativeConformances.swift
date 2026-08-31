// TDNativeConformances.swift

import TDLibKit

extension TDNativeChatList: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.chatListArchive, .chatListArchive), (.chatListMain, .chatListMain):
            true
        case (.chatListFolder(let lhs), .chatListFolder(let rhs)):
            lhs.chatFolderId == rhs.chatFolderId
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .chatListMain:
            hasher.combine(0)
        case .chatListArchive:
            hasher.combine(1)
        case .chatListFolder(let folder):
            hasher.combine(2)
            hasher.combine(folder.chatFolderId)
        }
    }
}
