// RichNotificationCache.swift

import Foundation
import ImageIO
import UIKit

enum RichNotificationPeerKind: String, Codable, Hashable {
    case privateChat = "private"
    case basicGroup
    case supergroup
}

struct RichNotificationPeerReference: Codable, Hashable {
    let kind: RichNotificationPeerKind
    let id: Int64

    var cacheKey: String { "\(kind.rawValue)-\(id)" }
}

struct RichNotificationMessageReference: Hashable {
    let peer: RichNotificationPeerReference
    let serverMessageID: Int64

    var cacheKey: String { "\(peer.cacheKey)-\(serverMessageID)" }
}

enum RichNotificationCache {
    static func avatarData(for peer: RichNotificationPeerReference) -> Data? {
        try? Data(contentsOf: avatarURL(for: peer))
    }

    static func cacheAvatar(_ data: Data, for peer: RichNotificationPeerReference) {
        writeJPEG(data, to: avatarURL(for: peer), maximumPixelSize: 256)
    }

    static func mediaURL(for message: RichNotificationMessageReference) -> URL? {
        let url = mediaDirectoryURL?.appendingPathComponent("\(message.cacheKey).jpg")
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static func cacheMedia(_ data: Data, for message: RichNotificationMessageReference) {
        guard let url = mediaDirectoryURL?.appendingPathComponent("\(message.cacheKey).jpg") else { return }
        writeJPEG(data, to: url, maximumPixelSize: 1280)
        trimMediaCache()
    }

    static func writeTemporaryAttachment(_ data: Data) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RichNotificationAttachments", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(UUID().uuidString).jpg")
            guard let jpeg = normalizedJPEG(data, maximumPixelSize: 1280) else { return nil }
            try jpeg.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func normalizedJPEG(_ data: Data, maximumPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary)
        else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.86)
    }

    private static var avatarDirectoryURL: URL? {
        directoryURL(named: "avatars")
    }

    private static var mediaDirectoryURL: URL? {
        directoryURL(named: "media")
    }

    private static func avatarURL(for peer: RichNotificationPeerReference) -> URL {
        avatarDirectoryURL?.appendingPathComponent("\(peer.cacheKey).jpg")
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("missing.jpg")
    }

    private static func directoryURL(named name: String) -> URL? {
        guard let container = BetterTGAppGroup.containerURL() else { return nil }
        let directory = container
            .appendingPathComponent("RichNotifications", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func writeJPEG(_ data: Data, to url: URL, maximumPixelSize: Int) {
        guard url.lastPathComponent != "missing.jpg",
              let jpeg = normalizedJPEG(data, maximumPixelSize: maximumPixelSize)
        else { return }
        do {
            try jpeg.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path,
            )
        } catch {}
    }

    private static func trimMediaCache() {
        guard let directory = mediaDirectoryURL,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: [.contentModificationDateKey],
                  options: [.skipsHiddenFiles],
              ), files.count > 128
        else { return }
        let sorted = files.sorted {
            let lhs = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let rhs = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return (lhs ?? .distantPast) < (rhs ?? .distantPast)
        }
        for url in sorted.prefix(files.count - 128) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
