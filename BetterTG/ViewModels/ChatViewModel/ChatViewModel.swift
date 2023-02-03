// ChatViewModel.swift

import SwiftUI
import Combine
import TDLibKit
import PhotosUI
import MobileVLCKit

class ChatViewModel: ObservableObject {

    let customChat: CustomChat
    
    @Published var onlineStatus = ""
    @Published var actionStatus = ""
    
    @Published var text = ""
    @Published var editMessageText = ""
    
    var loadedAlbums = Set<Int64>()
    var sentPhotosCount = 0
    var toBeSentPhotosCount = 0
    var savedAlbumMainMessageId: Int64 = 0
    var savedAlbumMainMessageIdTemp: Int64 = 0
    var savedPhotoMessages = [Message]()
    @Published var fetchedImages = [ImageAsset]()
    @Published var displayedImages = [SelectedImage]()
    @Published var selectedImagesCount = 0
    
    @Published var scrollViewProxy: ScrollViewProxy?
    
    @Published var savedNewMessages = [Message]()
    @Published var messages = [CustomMessage]()
    @Published var highlightedMessageId: Int64?
    
    @Published var loadingMessages = false
    @Published var initLoadingMessages = false
    
    var offset = 0
    var limit = 30
    
    var savedVoiceNoteUrl = URL(filePath: "")
    var audioRecorder = AVAudioRecorder()
    let audioSession = AVAudioSession.sharedInstance()
    var mediaPlayer = VLCMediaPlayer()
    @Published var duration = 0
    @Published var recordingVoiceNote = false
    @Published var isPlaying = false
    @Published var savedMediaPath = ""
    @Published var currentTime: Int32 = 0
    @Published var timeSliderValue = 0.0
    @Published var isSeeking = false
    
    @Published var editCustomMessage: CustomMessage? {
        didSet {
            if editCustomMessage != nil {
                setEditMessageText(from: editCustomMessage?.message)
            }
        }
    }
    @Published var replyMessage: CustomMessage? {
        didSet {
            Task {
                await updateDraft()
            }
        }
    }
    
    @Published var errorMessage = ""
    @Published var errorShown = false
    
    var cancellable = Set<AnyCancellable>()
    
    init(customChat: CustomChat) {
        self.customChat = customChat
        
        self.userStatus(customChat.user.status)
        
        setPublishers()
        
        Task {
            await self.loadMessages(isInit: true)
            
            guard let draftMessage = customChat.chat.draftMessage else { return }
            await self.setDraft(draftMessage)
        }
    }
    
    deinit {
        cancellable.forEach { $0.cancel() }
    }
}
