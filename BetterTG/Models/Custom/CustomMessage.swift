// CustomMessage.swift

import TDLibKit

struct CustomMessage: Identifiable, Equatable {
    var id = UUID()
    var message: Message
    var senderUser: User?
    var replyUser: User?
    var replyToMessage: Message?
    var album = [Message]()
    var sendFailed = false
    var forwardedFrom: String?
    
    mutating func update(
        message: Message? = nil,
        senderUser: User? = nil,
        replyUser: User? = nil,
        album: [Message]? = nil,
        sendFailed: Bool? = nil,
        replyToMessage: Message? = nil,
        forwardedFrom: String? = nil
    ) {
        if let message { self.message = message }
        if let senderUser { self.senderUser = senderUser }
        if let replyUser { self.replyUser = replyUser }
        if let replyToMessage { self.replyToMessage = replyToMessage }
        if let album { self.album = album }
        if let sendFailed { self.sendFailed = sendFailed }
        if let forwardedFrom { self.forwardedFrom = forwardedFrom }
        id = UUID()
    }
    
    mutating func appendAlbum(_ message: Message) {
        album.append(message)
        id = UUID()
    }
}
