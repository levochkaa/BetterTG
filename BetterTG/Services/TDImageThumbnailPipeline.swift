// TDImageThumbnailPipeline.swift

import Foundation
import ImageIO
import TDLibKit
import UIKit

// MARK: - TDImageThumbnailKey

struct TDImageThumbnailKey: Hashable {
    let accountID: UUID?
    let clientID: Int32
    let fileID: Int
    let maximumPixelSize: Int

    var cacheKey: NSString {
        let accountNamespace = accountID?.uuidString ?? "unknown-account"
        return "\(accountNamespace):\(clientID):\(fileID):\(maximumPixelSize)" as NSString
    }

    func placeholderCacheKey(data: Data) -> NSString {
        "\(cacheKey):placeholder:\(data.hashValue)" as NSString
    }
}

// MARK: - PreparedCGImage

final class PreparedCGImage: NSObject, @unchecked Sendable {
    let image: CGImage

    var cost: Int {
        image.bytesPerRow * image.height
    }

    init(_ image: CGImage) {
        self.image = image
    }
}

// MARK: - TDImageThumbnailPipeline

final class TDImageThumbnailPipeline: @unchecked Sendable {
    // MARK: Private

    private enum Source: @unchecked Sendable {
        case file(String)
        case data(Data)
    }

    private actor DecodeRegistry {
        private var tasks = [String: Task<PreparedCGImage?, Never>]()

        func image(
            identifier: String,
            operation: @escaping @Sendable () async -> PreparedCGImage?,
        ) async -> PreparedCGImage? {
            if let task = tasks[identifier] {
                return await task.value
            }
            let task = Task { await operation() }
            tasks[identifier] = task
            let result = await task.value
            tasks[identifier] = nil
            return result
        }
    }

    // MARK: Internal

    static let shared = TDImageThumbnailPipeline()

    private let cache: NSCache<NSString, PreparedCGImage> = {
        let cache = NSCache<NSString, PreparedCGImage>()
        cache.countLimit = 240
        cache.totalCostLimit = 72 * 1024 * 1024
        return cache
    }()

    private let decodeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.bettertg.thumbnail-decoding"
        queue.qualityOfService = .utility
        return queue
    }()

    private let decodeRegistry = DecodeRegistry()

    private init() {}

    private static func decode(source: Source, maximumPixelSize: Int) -> PreparedCGImage? {
        let imageSource: CGImageSource?
        switch source {
        case .file(let path):
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
        case .data(let data):
            imageSource = CGImageSourceCreateWithData(data as CFData, nil)
        }
        guard let imageSource,
              let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: max(maximumPixelSize, 1),
                  kCGImageSourceShouldCache: true,
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary)
        else { return nil }
        return PreparedCGImage(image)
    }

    func cachedImage(for key: NSString) -> PreparedCGImage? {
        cache.object(forKey: key)
    }

    func image(
        at path: String,
        key: TDImageThumbnailKey,
    ) async -> PreparedCGImage? {
        await preparedImage(
            cacheKey: key.cacheKey,
            source: .file(path),
            maximumPixelSize: key.maximumPixelSize,
        )
    }

    func placeholderImage(
        data: Data,
        key: TDImageThumbnailKey,
    ) async -> PreparedCGImage? {
        await preparedImage(
            cacheKey: key.placeholderCacheKey(data: data),
            source: .data(data),
            maximumPixelSize: key.maximumPixelSize,
        )
    }

    func standalonePlaceholderImage(
        data: Data,
        maximumPixelSize: Int,
    ) async -> PreparedCGImage? {
        await preparedImage(
            cacheKey: "standalone:\(maximumPixelSize):\(data.hashValue)" as NSString,
            source: .data(data),
            maximumPixelSize: maximumPixelSize,
        )
    }

    private func preparedImage(
        cacheKey: NSString,
        source: Source,
        maximumPixelSize: Int,
    ) async -> PreparedCGImage? {
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let decodeQueue = decodeQueue
        let result = await decodeRegistry.image(identifier: cacheKey as String) {
            await withCheckedContinuation { continuation in
                decodeQueue.addOperation {
                    continuation.resume(returning: Self.decode(
                        source: source,
                        maximumPixelSize: maximumPixelSize,
                    ))
                }
            }
        }
        if let result {
            cache.setObject(result, forKey: cacheKey, cost: result.cost)
        }
        return result
    }
}

// MARK: - TDImagePrefetcher

enum TDImagePrefetcher {
    static func prefetch(file: File?, maximumPixelSize: Int) async {
        guard let file, !Task.isCancelled else { return }
        let client = td
        let key = TDImageThumbnailKey(
            accountID: TDLib.shared.activeAccountID,
            clientID: client.id,
            fileID: file.id,
            maximumPixelSize: maximumPixelSize,
        )
        if TDImageThumbnailPipeline.shared.cachedImage(for: key.cacheKey) != nil {
            return
        }

        let resolvedFile: File? =
            if file.local.isDownloadingCompleted, !file.local.path.isEmpty {
                file
            } else {
                try? await client.downloadFile(
                    fileId: file.id,
                    limit: 0,
                    offset: 0,
                    priority: 1,
                    synchronous: true,
                )
            }
        guard !Task.isCancelled,
              let resolvedFile,
              resolvedFile.local.isDownloadingCompleted,
              !resolvedFile.local.path.isEmpty
        else { return }
        _ = await TDImageThumbnailPipeline.shared.image(at: resolvedFile.local.path, key: key)
    }
}
