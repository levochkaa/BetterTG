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

    struct Quality: Equatable {
        let height: Int
        let file: File
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
    /// The video's own quality, which Auto plays.
    var height = 0
    /// TDLib's alternativeVideos that AVPlayer decodes (H.264 and HEVC), one per quality, highest first, as Telegram's
    /// HLSQualitySet offers them in the quality menu. A quality is the shorter side, as HLSQualitySet keys them, so a
    /// portrait 720×1280 video is 720p.
    var qualities = [Quality]()

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
            self.height = min(value.video.width, value.video.height)
            if !value.isSecret {
                var seen = Set<Int>()
                self.qualities = value.alternativeVideos
                    .filter { ["h264", "avc", "h265", "hevc"].contains($0.codec.lowercased()) }
                    .map { Quality(height: min($0.width, $0.height), file: $0.video) }
                    .filter { $0.height > 0 }
                    .sorted { $0.height > $1.height }
                    .filter { seen.insert($0.height).inserted }
            }
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
