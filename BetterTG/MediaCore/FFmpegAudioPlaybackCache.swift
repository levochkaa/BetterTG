// FFmpegAudioPlaybackCache.swift

import AVFoundation
import CryptoKit
import FFmpegBridge
import Foundation

// MARK: - FFmpegAudioDecodeJobHandle

private final class FFmpegAudioDecodeJobHandle: @unchecked Sendable {
    // MARK: Internal

    let pointer: OpaquePointer

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        BetterTGFFmpegAudioDecodeJobDestroy(pointer)
    }

    func run() -> Int32 {
        BetterTGFFmpegAudioDecodeJobRun(pointer)
    }

    func cancel() {
        BetterTGFFmpegAudioDecodeJobCancel(pointer)
    }
}

// MARK: - FFmpegAudioDecoder

enum FFmpegAudioDecoder {
    enum DecoderError: Error {
        case couldNotCreateJob
        case decodingFailed(Int32)
    }

    static func decodeToWAV(
        sourceURL: URL,
        outputURL: URL,
        maximumOutputBytes: Int64 = 64 * 1024 * 1024,
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)
        guard let pointer = sourceURL.path.withCString({ inputPath in
            outputURL.path.withCString { outputPath in
                BetterTGFFmpegAudioDecodeJobCreate(inputPath, outputPath, maximumOutputBytes)
            }
        }) else {
            throw DecoderError.couldNotCreateJob
        }
        let job = FFmpegAudioDecodeJobHandle(pointer: pointer)
        let result = await withTaskCancellationHandler {
            await Task.detached(priority: .userInitiated) {
                job.run()
            }.value
        } onCancel: {
            job.cancel()
        }
        guard !Task.isCancelled else {
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        }
        guard result == 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            throw DecoderError.decodingFailed(result)
        }
    }
}

// MARK: - FFmpegAudioPlaybackCache

actor FFmpegAudioPlaybackCache {
    // MARK: Internal

    static let shared = FFmpegAudioPlaybackCache()

    // MARK: Private

    private let fileManager = FileManager.default
    private let maximumDecodedFileBytes: Int64 = 64 * 1024 * 1024
    private let maximumCacheBytes: Int64 = 128 * 1024 * 1024
    private var activePartialURLs = Set<URL>()
    private lazy var directoryURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("FFmpegAudioPlayback", isDirectory: true)

    func playableURL(for sourceURL: URL) async -> URL {
        guard sourceURL.isFileURL else { return sourceURL }
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            removeAbandonedPartialFiles()
            let cacheURL = directoryURL.appendingPathComponent(cacheKey(for: sourceURL) + ".wav")
            if isValidCacheFile(cacheURL),
               await (try? validateDecodedFile(cacheURL)) == true
            {
                try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: cacheURL.path)
                pruneCache(keeping: cacheURL)
                return cacheURL
            }
            if fileManager.fileExists(atPath: cacheURL.path) {
                try fileManager.removeItem(at: cacheURL)
            }
            let isOggOpus = await Task.detached(priority: .utility) {
                sourceURL.path.withCString { BetterTGFFmpegIsOggOpusFile($0) == 1 }
            }.value
            try Task.checkCancellation()
            guard isOggOpus else { return sourceURL }

            let temporaryURL = directoryURL.appendingPathComponent(
                cacheURL.lastPathComponent + ".\(UUID().uuidString).partial",
            )
            activePartialURLs.insert(temporaryURL)
            defer { activePartialURLs.remove(temporaryURL) }
            do {
                try await FFmpegAudioDecoder.decodeToWAV(
                    sourceURL: sourceURL,
                    outputURL: temporaryURL,
                    maximumOutputBytes: maximumDecodedFileBytes - 44,
                )
                try Task.checkCancellation()
                guard try await validateDecodedFile(temporaryURL) else {
                    throw FFmpegAudioDecoder.DecoderError.decodingFailed(-1)
                }
                if fileManager.fileExists(atPath: cacheURL.path) {
                    if await (try? validateDecodedFile(cacheURL)) == true {
                        try? fileManager.removeItem(at: temporaryURL)
                    } else {
                        try fileManager.removeItem(at: cacheURL)
                        try fileManager.moveItem(at: temporaryURL, to: cacheURL)
                    }
                } else {
                    try fileManager.moveItem(at: temporaryURL, to: cacheURL)
                }
                pruneCache(keeping: cacheURL)
                return cacheURL
            } catch {
                try? fileManager.removeItem(at: temporaryURL)
                throw error
            }
        } catch is CancellationError {
            return sourceURL
        } catch {
            log("FFmpeg audio fallback failed: \(error)")
            return sourceURL
        }
    }

    private func cacheKey(for sourceURL: URL) -> String {
        let attributes = try? fileManager.attributesOfItem(atPath: sourceURL.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? -1
        let modificationDate = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
        let signature = "\(sourceURL.standardizedFileURL.path)|\(fileSize)|\(modificationDate)"
        return SHA256.hash(data: Data(signature.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func isValidCacheFile(_ url: URL) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else { return false }
        return size.int64Value > 44 && size.int64Value <= maximumDecodedFileBytes
    }

    private func validateDecodedFile(_ url: URL) async throws -> Bool {
        try await Task.detached(priority: .utility) {
            let file = try AVAudioFile(forReading: url)
            return file.length > 0
                && file.processingFormat.sampleRate == 48000
                && (1...2).contains(Int(file.processingFormat.channelCount))
        }.value
    }

    private func pruneCache(keeping retainedURL: URL) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
        ) else { return }
        let entries = files.compactMap { url -> (URL, Int64, Date)? in
            guard url.pathExtension == "wav",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else { return nil }
            return (url, Int64(size), values.contentModificationDate ?? .distantPast)
        }
        var totalBytes = entries.reduce(Int64.zero) { $0 + $1.1 }
        for entry in entries.sorted(by: { $0.2 < $1.2 })
            where totalBytes > maximumCacheBytes && entry.0 != retainedURL
        {
            if (try? fileManager.removeItem(at: entry.0)) != nil {
                totalBytes -= entry.1
            }
        }
    }

    private func removeAbandonedPartialFiles() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
        ) else { return }
        for file in files where file.pathExtension == "partial" && !activePartialURLs.contains(file) {
            try? fileManager.removeItem(at: file)
        }
    }
}
