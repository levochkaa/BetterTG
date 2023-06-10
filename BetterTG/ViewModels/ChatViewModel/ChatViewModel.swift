// ChatViewModel.swift

import SwiftUI
import Combine
import TDLibKit
import PhotosUI
import MobileVLCKit
import Observation

@Observable final class ChatViewModel {
    @ObservationIgnored var customChat: CustomChat
    
    @ObservationIgnored var currentLiveActivityId: String = ""
    
    var onlineStatus = ""
    var actionStatus = ""
    
    @ObservationIgnored let textDebouncer = Debouncer()
    var text: AttributedString = ""
    var editMessageText: AttributedString = ""
    var showSendButton = false
    
    @ObservationIgnored var loadedAlbums = Set<Int64>()
    @ObservationIgnored var sentPhotosCount = 0
    @ObservationIgnored var toBeSentPhotosCount = 0
    @ObservationIgnored var savedAlbumMainMessageId: Int64 = 0
    @ObservationIgnored var savedAlbumMainMessageIdTemp: Int64 = 0
    @ObservationIgnored var savedPhotoMessages = [Message]()
    var fetchedImages = [ImageAsset]()
    var displayedImages = [SelectedImage]()
    var selectedImagesCount = 0
    var showBottomSheet = false
    var showCameraView = false
    
    var scrollViewProxy: ScrollViewProxy? = nil
    
    var savedNewMessages = [Message]()
    var messages = [CustomMessage]()
    var highlightedMessageId: Int64? = nil
    
    var loadingMessages = false
    var initLoadingMessages = false
    
    @ObservationIgnored var offset = 0
    @ObservationIgnored var limit = 30
    
    @ObservationIgnored var savedVoiceNoteUrl = URL(filePath: "")
    @ObservationIgnored var audioRecorder = AVAudioRecorder()
    @ObservationIgnored let audioSession = AVAudioSession.sharedInstance()
    @ObservationIgnored var mediaPlayer = VLCMediaPlayer()
    var duration = 0
    var recordingVoiceNote = false
    var isPlaying = false
    var savedMediaPath = ""
    var currentTime: Int32 = 0
    var timeSliderValue = 0.0
    var isSeeking = false
    
    var editCustomMessage: CustomMessage? = nil
    var replyMessage: CustomMessage? = nil
    
    var errorMessage = ""
    var errorShown = false
    
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
}
