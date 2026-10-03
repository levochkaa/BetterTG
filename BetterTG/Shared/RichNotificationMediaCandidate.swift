// RichNotificationMediaCandidate.swift

import Foundation
import TDLibKitDynamic

struct RichNotificationMediaCandidate: Equatable {
    enum Kind: String, Codable { case photo, video, animation, videoNote, document, sticker }

    let file: File
    let placeholder: Data?
    let kind: Kind

    init?(message: Message) {
        guard RichNotificationMediaEligibility.allows(message) else { return nil }
        let thumbnail: Thumbnail?
        switch message.content {
        case .messagePhoto(let value):
            guard let size = value.photo.sizes.min(by: {
                abs(max($0.width, $0.height) - 1280) < abs(max($1.width, $1.height) - 1280)
            }) else { return nil }
            self.file = size.photo
            self.placeholder = value.photo.minithumbnail?.data
            self.kind = .photo
            return
        case .messageVideo(let value):
            thumbnail = value.video.thumbnail
            self.placeholder = value.video.minithumbnail?.data
            self.kind = .video
        case .messageAnimation(let value):
            thumbnail = value.animation.thumbnail
            self.placeholder = value.animation.minithumbnail?.data
            self.kind = .animation
        case .messageVideoNote(let value):
            thumbnail = value.videoNote.thumbnail
            self.placeholder = value.videoNote.minithumbnail?.data
            self.kind = .videoNote
        case .messageDocument(let value):
            thumbnail = value.document.thumbnail
            self.placeholder = value.document.minithumbnail?.data
            self.kind = .document
        case .messageSticker(let value):
            thumbnail = value.sticker.thumbnail
            self.placeholder = nil
            self.kind = .sticker
        default:
            return nil
        }
        guard let thumbnail else { return nil }
        self.file = thumbnail.file
    }
}
