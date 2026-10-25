// GalleryPlayableMessage.swift

import CoreGraphics
import Foundation
import TDLibKit

// MARK: - GalleryPlayableMessage

/// Immutable playback identity excludes changing local download progress.
struct GalleryPlayableMessage {
    enum Kind: Equatable { case video, animation }
    struct Identity: Equatable {
        let kind: Kind
        let fileID: Int
        let revision: Int
    }

    let identity: Identity
    let file: File
    let thumbnail: Thumbnail?
    let minithumbnail: Minithumbnail?
    let mimeType: String
    let fileName: String
    let supportsStreaming: Bool
    let isSecret: Bool
    let startTimestamp: TimeInterval

    var isAnimation: Bool { identity.kind == .animation }

    /// `startTimestamp` overrides the video's own start, as a caption's media timestamp does.
    @MainActor init?(message: Message, revealPermit: MediaRevealPermit? = nil, startTimestamp: TimeInterval? = nil) {
        guard MediaRevealPermit.allows(message, permit: revealPermit) else { return nil }
        let kind: Kind
        switch message.content {
        case .messageVideo(let value):
            kind = .video
            self.file = value.video.video
            self.thumbnail = value.video.thumbnail
            self.minithumbnail = value.video.minithumbnail
            self.mimeType = value.video.mimeType
            self.fileName = value.video.fileName
            self.supportsStreaming = value.video.supportsStreaming
            self.isSecret = value.isSecret
            self.startTimestamp = startTimestamp ?? TimeInterval(value.startTimestamp)
        case .messageAnimation(let value):
            guard !telegramAnimationUsesFFmpeg(value.animation) else { return nil }
            kind = .animation
            self.file = value.animation.animation
            self.thumbnail = value.animation.thumbnail
            self.minithumbnail = value.animation.minithumbnail
            self.mimeType = value.animation.mimeType
            self.fileName = value.animation.fileName
            // TDLib Animation has no streaming capability field.
            self.supportsStreaming = false
            self.isSecret = false
            self.startTimestamp = 0
        default:
            return nil
        }
        self.identity = Identity(kind: kind, fileID: file.id, revision: message.editDate)
    }
}

// MARK: - InlineMediaPlaybackPolicy

enum InlineMediaPlaybackPolicy {
    struct Candidate {
        let messageID: Int64
        let visibleArea: CGFloat
        let isAnimation: Bool
    }

    static func visibleMessageIDs(_ candidates: [Candidate]) -> Set<Int64> {
        let visible = candidates.filter { $0.visibleArea > 0 }
        var result = Set(visible.filter(\.isAnimation).map(\.messageID))
        if let video = visible.filter({ !$0.isAnimation }).max(by: { $0.visibleArea < $1.visibleArea }) {
            result.insert(video.messageID)
        }
        return result
    }
}
