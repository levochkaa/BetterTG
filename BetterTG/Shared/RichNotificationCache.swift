// RichNotificationCache.swift

import Foundation
import ImageIO
import UIKit

// MARK: - RichNotificationPeerKind

enum RichNotificationPeerKind: String, Codable, Hashable {
    case privateChat = "private"
    case basicGroup
    case supergroup
}

// MARK: - RichNotificationPeerReference

struct RichNotificationPeerReference: Codable, Hashable {
    let kind: RichNotificationPeerKind
    let id: Int64

    var cacheKey: String { "\(kind.rawValue)-\(id)" }
}

// MARK: - RichNotificationMessageReference

struct RichNotificationMessageReference: Hashable {
    let peer: RichNotificationPeerReference
    let serverMessageID: Int64

    var cacheKey: String { "\(peer.cacheKey)-\(serverMessageID)" }
}

// MARK: - RichNotificationCache

enum RichNotificationCache {
    // MARK: Internal

    static func matchesAccount(_ accountID: Int64?, boundUserID: Int64?) -> Bool {
        guard let accountID, accountID > 0 else { return false }
        return accountID == boundUserID
    }

    static func avatarData(
        for peer: RichNotificationPeerReference, accountID: Int64?,
        containerURL: () -> URL? = { BetterTGAppGroup.containerURL() },
    ) -> Data? {
        guard let url = avatarURL(for: peer, accountID: accountID, containerURL: containerURL) else { return nil }
        return try? Data(contentsOf: url)
    }

    @discardableResult static func cacheAvatar(
        _ data: Data, for peer: RichNotificationPeerReference, accountID: Int64?,
        containerURL: () -> URL? = { BetterTGAppGroup.containerURL() },
        shouldWrite: () -> Bool = { true },
    ) -> Bool {
        guard let url = avatarURL(for: peer, accountID: accountID, containerURL: containerURL) else { return false }
        return writeJPEG(data, to: url, maximumPixelSize: 256, shouldWrite: shouldWrite)
    }

    static func mediaURL(
        for message: RichNotificationMessageReference, accountID: Int64?,
        containerURL: () -> URL? = { BetterTGAppGroup.containerURL() },
    ) -> URL? {
        let url = directoryURL(named: "media", accountID: accountID, containerURL: containerURL)?
            .appendingPathComponent("\(message.cacheKey).jpg")
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static func cacheMedia(
        _ data: Data, for message: RichNotificationMessageReference, accountID: Int64?,
        containerURL: () -> URL? = { BetterTGAppGroup.containerURL() },
    ) {
        guard let directory = directoryURL(named: "media", accountID: accountID, containerURL: containerURL)
        else { return }
        let url = directory.appendingPathComponent("\(message.cacheKey).jpg")
        writeJPEG(data, to: url, maximumPixelSize: 1280)
        trimMediaCache(in: directory)
    }

    static func writeTemporaryAttachment(_ data: Data) -> URL? {
        let directory = FileManager.default
            .temporaryDirectory
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

    private static func avatarURL(
        for peer: RichNotificationPeerReference, accountID: Int64?, containerURL: () -> URL?,
    ) -> URL? {
        directoryURL(named: "avatars", accountID: accountID, containerURL: containerURL)?
            .appendingPathComponent("\(peer.cacheKey).jpg")
    }

    private static func directoryURL(named name: String, accountID: Int64?, containerURL: () -> URL?) -> URL? {
        guard let accountID, accountID > 0, let containerURL = containerURL() else { return nil }
        // Logical peer identifiers also belong to Intents. Scope only disk paths;
        // unscoped legacy entries stay untouched and are never read as fallback.
        let directory = containerURL
            .appendingPathComponent("RichNotifications", isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent(String(accountID), isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @discardableResult private static func writeJPEG(
        _ data: Data, to url: URL, maximumPixelSize: Int, shouldWrite: () -> Bool = { true },
    ) -> Bool {
        guard let jpeg = normalizedJPEG(data, maximumPixelSize: maximumPixelSize), shouldWrite()
        else { return false }
        do {
            try jpeg.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path,
            )
            return true
        } catch {
            return false
        }
    }

    private static func trimMediaCache(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
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
