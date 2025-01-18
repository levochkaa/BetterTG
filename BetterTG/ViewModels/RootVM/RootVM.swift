// RootVM.swift

import SwiftUI
import TDLibKit
import Combine

@Observable final class RootVM {
    @ObservationIgnored static let shared = RootVM()
    
    init() {
        setPublishers()
    }
    
    var confirmChatDelete = ConfirmChatDelete(chat: nil, show: false, forAll: false)
    
    @ObservationIgnored var cancellables = Set<AnyCancellable>()
    var loggedIn: Bool {
        get {
            access(keyPath: \.loggedIn)
            return UserDefaults.standard.bool(forKey: "loggedIn")
        }
        set {
            withMutation(keyPath: \.loggedIn) {
                UserDefaults.standard.set(newValue, forKey: "loggedIn")
            }
        }
    }
    var folders = [CustomFolder]()
    var mainFolder: CustomFolder? { folders.first(where: { $0.type == .main }) }
    var archive: CustomFolder?
    var showArchive = false
    var currentFolder = 0
    var query = ""
    
    var allChats: [CustomChat] {
        var chats = [CustomChat]()
        if let archive { chats.append(contentsOf: archive.chats) }
        if let mainFolder { chats.append(contentsOf: mainFolder.chats) }
        return chats
    }
}
