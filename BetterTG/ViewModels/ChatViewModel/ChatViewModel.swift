// ChatViewModel.swift

import SwiftUI
import Combine
import TDLibKit
import CollectionConcurrencyKit
import PhotosUI
import MobileVLCKit

class ChatViewModel: ObservableObject {

    let chat: Chat
    
    @Published var text = ""
    @Published var editMessageText = ""
    
    @Published var bottomAreaState: BottomAreaState = .voice {
        didSet {
            switch bottomAreaState {
                case .voice:
                    withAnimation {
                        text = ""
                        editMessageText = ""
                        replyMessage = nil
                        editMessage = nil
                        displayedPhotos = []
                        selectedPhotos = []
                    }
                case .caption, .reply, .edit, .message:
                    break
            }
        }
    }
    
    var loadedAlbums = Set<Int64>()
    var sentPhotosCount = 0
    var toBeSentPhotosCount = 0
    var savedAlbumMainMessageId: Int64 = 0
    var savedAlbumMainMessageIdTemp: Int64 = 0
    var savedPhotoMessages = [Message]()
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
    
    var savedVoiceNoteUrl = URL(filePath: "")
    var audioRecorder = AVAudioRecorder()
    let audioSession = AVAudioSession.sharedInstance()
    var mediaPlayer = VLCMediaPlayer()
    @Published var recordingVoiceNote = false
    @Published var isPlaying = false
    @Published var savedMediaPath = ""
    @Published var currentTime: Int32 = 0
    @Published var timeSliderValue = 0.0
    @Published var isSeeking = false
    
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
    
    @Published var errorMessage = ""
    @Published var errorShown = false
    
    let tdApi: TdApi = .shared
    let logger = Logger("ChatVM")
    let nc: NotificationCenter = .default
    var cancellable = Set<AnyCancellable>()
    
    init(chat: Chat) {
        self.chat = chat
        
        setPublishers()
        
        Task {
            await self.loadMessages(isInit: true)
            
            guard let draftMessage = chat.draftMessage else { return }
            await self.setDraft(draftMessage)
        }
    }
    
    deinit {
        cancellable.forEach { $0.cancel() }
    }
}
