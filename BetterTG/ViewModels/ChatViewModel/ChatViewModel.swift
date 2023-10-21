// ChatViewModel.swift

import Combine
import TDLibKit
import PhotosUI
import MobileVLCKit
import Observation

@Observable final class ChatViewModel {
    @ObservationIgnored var customChat: CustomChat?
    
    var onlineStatus = ""
    var actionStatus = ""
    
    var text: AttributedString = ""
    var editMessageText: AttributedString = ""
    var showSendButton = false
    
    // @ObservationIgnored var lastAppearedMessageId: Int64? = nil
    // @ObservationIgnored var shouldWaitForMessageId: Int64? = nil
    
    @ObservationIgnored var loadedAlbums = Set<Int64>()
    @ObservationIgnored var sentPhotosCount = 0
    @ObservationIgnored var toBeSentPhotosCount = 0
    @ObservationIgnored var savedAlbumMainMessageId: Int64 = 0
    @ObservationIgnored var savedAlbumMainMessageIdTemp: Int64 = 0
    @ObservationIgnored var savedPhotoMessages = [Message]()
    var fetchedImages = [ImageAsset]()
    var displayedImages = [SelectedImage]()
    var showBottomSheet = false
    var showCameraView = false
    
    @ObservationIgnored var scrollViewProxy: ScrollViewProxy? = nil
    
    var messages = [CustomMessage]()
    var highlightedMessageId: UUID? = nil
    
    @ObservationIgnored var loadingMessages = false
    
    @ObservationIgnored var offset = 0
    @ObservationIgnored var limit = 30
    
    @ObservationIgnored var savedVoiceNoteUrl = URL(filePath: "")
    @ObservationIgnored var audioRecorder = AVAudioRecorder()
    @ObservationIgnored let audioSession = AVAudioSession.sharedInstance()
    @ObservationIgnored var mediaPlayer: VLCMediaPlayer!
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
    
    @ObservationIgnored var cancellables = Set<AnyCancellable>()
    
    func onAppear(customChat: CustomChat) {
        self.customChat = customChat
        self.mediaPlayer = VLCMediaPlayer()
        setPublishers()
        userStatus(customChat.user.status)
        
        guard let draftMessage = customChat.draftMessage else { return }
        setDraft(draftMessage)
    }
    
    func onDisappear() {
        mediaPlayer.stop()
        Task { await updateDraft() }
    }
}
