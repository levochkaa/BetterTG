// FileDownloads.swift

import TDLibKit

// MARK: - FileDownloads

/// TDLib's file download list, which stands in for Telegram's DownloadManager: a file the user downloads from a
/// message joins it with that message (addFileToDownloads), and the chat list search's Downloads tab lists it
/// while it downloads and after.
@MainActor enum FileDownloads {
    /// The message a file came from.
    struct Source: Equatable {
        let chatID: Int64
        let messageID: Int64
    }

    /// Telegram's interactive fetch priority for a file the user asked for.
    static let priority = 16

    /// Starts the file's download in the list; nil when TDLib can't (a message not on the server).
    static func add(fileID: Int, source: Source, client: TDLibClient) async -> File? {
        try? await client.send(TDNativeRequests.addFileToDownloads(
            fileId: fileID,
            chatId: source.chatID,
            messageId: source.messageID,
            priority: priority,
        ))
    }

    /// Whether the list has any file, which shows the Downloads tab.
    static func hasDownloads(client: TDLibClient) async -> Bool {
        guard let found = try? await client.send(TDNativeRequests.searchFileDownloads(
            query: "",
            onlyActive: false,
            onlyCompleted: false,
            offset: "",
            limit: 1,
        )) else { return false }
        let counts = found.totalCounts
        return counts.activeCount + counts.pausedCount + counts.completedCount > 0
    }
}
