// ChatViewModel.swift

import SwiftUI
import Combine
import TDLibKit
import CollectionConcurrencyKit
import PhotosUI

class ChatViewModel: ObservableObject {

    let chat: Chat
    
    @Published var text = ""
    @Published var editMessageText = ""
    
    @Published var bottomAreaState: BottomAreaState = .message {
        didSet {
            switch bottomAreaState {
                case .message:
                    withAnimation {
                        text = ""
                        editMessageText = ""
                        replyMessage = nil
                        editMessage = nil
                        displayedPhotos = []
                    }
                case .caption, .reply, .edit:
                    break
            }
        }
    }
    
    var loadedAlbums = [TdInt64]()
    @Published var displayedPhotos = [SelectedImage]() {
        didSet {
            if !displayedPhotos.isEmpty {
                bottomAreaState = .caption
            }
        }
    }
    @Published var selectedPhotos = [PhotosPickerItem]() {
        didSet {
            Task {
                await loadPhotos()
            }
        }
    }
    
    @Published var scrollViewProxy: ScrollViewProxy?
    @Published var isScrollToBottomButtonShown = false
    
    var initSavedFirstMessage: CustomMessage?
    @Published var savedFirstMessage: CustomMessage?
    
    @Published var savedNewMessages = [Message]()
    @Published var messages = [CustomMessage]()
    @Published var highlightedMessageId: Int64?
    
    @Published var loadingMessages = false
    @Published var initLoadingMessages = false
    
    var offset = 0
    var limit = 30
    
    @Published var editMessage: CustomMessage? {
        didSet {
            if editMessage != nil {
                bottomAreaState = .edit
                setEditMessageText(from: editMessage?.message)
            }
        }
    }
    @Published var replyMessage: CustomMessage? {
        didSet {
            if displayedPhotos.isEmpty && replyMessage != nil {
                bottomAreaState = .reply
            }
            Task {
                await updateDraft()
            }
        }
    }
    
    let tdApi: TdApi = .shared
    let logger = Logger(label: "ChatVM")
    let nc: NotificationCenter = .default
    
    init(chat: Chat) {
        self.chat = chat
        
        setPublishers()
        
        Task {
            await self.loadMessages(isInit: true)
            
            guard let draftMessage = chat.draftMessage else { return }
            await self.setDraft(draftMessage)
        }
    }
}
