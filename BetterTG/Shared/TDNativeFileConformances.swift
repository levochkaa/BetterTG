// TDNativeFileConformances.swift

import TDLibKit

// Compare immutable native file contents. Shared with the notification service extension.

// MARK: - TDNativeFile + @retroactive Hashable

extension TDNativeFile: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.size == rhs.size
            && lhs.expectedSize == rhs.expectedSize
            && lhs.local == rhs.local
            && lhs.remote == rhs.remote
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(size)
        hasher.combine(expectedSize)
        hasher.combine(local)
        hasher.combine(remote)
    }
}

// MARK: - TDNativeLocalFile + @retroactive Hashable

extension TDNativeLocalFile: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.path == rhs.path
            && lhs.canBeDownloaded == rhs.canBeDownloaded
            && lhs.canBeDeleted == rhs.canBeDeleted
            && lhs.isDownloadingActive == rhs.isDownloadingActive
            && lhs.isDownloadingCompleted == rhs.isDownloadingCompleted
            && lhs.downloadOffset == rhs.downloadOffset
            && lhs.downloadedPrefixSize == rhs.downloadedPrefixSize
            && lhs.downloadedSize == rhs.downloadedSize
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
        hasher.combine(canBeDownloaded)
        hasher.combine(canBeDeleted)
        hasher.combine(isDownloadingActive)
        hasher.combine(isDownloadingCompleted)
        hasher.combine(downloadOffset)
        hasher.combine(downloadedPrefixSize)
        hasher.combine(downloadedSize)
    }
}

// MARK: - TDNativeRemoteFile + @retroactive Hashable

extension TDNativeRemoteFile: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.uniqueId == rhs.uniqueId
            && lhs.isUploadingActive == rhs.isUploadingActive
            && lhs.isUploadingCompleted == rhs.isUploadingCompleted
            && lhs.uploadedSize == rhs.uploadedSize
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(uniqueId)
        hasher.combine(isUploadingActive)
        hasher.combine(isUploadingCompleted)
        hasher.combine(uploadedSize)
    }
}
