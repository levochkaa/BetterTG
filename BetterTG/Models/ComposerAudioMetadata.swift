// ComposerAudioMetadata.swift

import AVFoundation
import UIKit

// MARK: - ComposerAudioMetadata

/// Telegram's iCloudFileDescription for a picked file: an mp3, m4a or flac file with a duration goes as music, with
/// its title and performer tags and its artwork scaled to 256 pt as the album cover; anything else stays a document.
struct ComposerAudioMetadata {
    private static let musicExtensions: Set = ["mp3", "m4a", "flac"]
    private static let coverSide = CGFloat(256)

    let duration: Int
    let title: String
    let performer: String
    /// A JPEG of the artwork in the temporary directory, for TDLib's album cover thumbnail.
    let coverURL: URL?
    let coverSize: CGSize

    /// Reads the tags off the main actor; nil for a file Telegram wouldn't send as music.
    static func read(_ url: URL) async -> ComposerAudioMetadata? {
        guard musicExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return await Task.detached(priority: .userInitiated) { await Self.load(url) }.value
    }

    private static func load(_ url: URL) async -> ComposerAudioMetadata? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0 else {
            return nil
        }
        var title = ""
        var performer = ""
        var artwork: Data?
        for item in await (try? asset.load(.metadata)) ?? [] {
            if item.commonKey == .commonKeyTitle, title.isEmpty {
                title = await (try? item.load(.stringValue)) ?? ""
            } else if item.commonKey == .commonKeyArtist, performer.isEmpty {
                performer = await (try? item.load(.stringValue)) ?? ""
            } else if item.commonKey == .commonKeyArtwork, artwork == nil {
                artwork = try? await item.load(.dataValue)
            }
        }
        let cover = artwork.flatMap(writeCover)
        return ComposerAudioMetadata(
            duration: Int(duration.seconds.rounded()),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            performer: performer.trimmingCharacters(in: .whitespacesAndNewlines),
            coverURL: cover?.url,
            coverSize: cover?.size ?? .zero,
        )
    }

    /// The artwork fitted in 256 × 256 as a JPEG at Telegram's 0.5 quality.
    private static func writeCover(_ data: Data) -> (url: URL, size: CGSize)? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, coverSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = scaled.jpegData(compressionQuality: 0.5) else { return nil }
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bettertg-album-cover-\(UUID().uuidString).jpg")
        guard (try? jpeg.write(to: url)) != nil else { return nil }
        return (url, size)
    }
}
