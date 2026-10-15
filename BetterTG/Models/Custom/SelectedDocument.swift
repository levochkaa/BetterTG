// SelectedDocument.swift

import Foundation

// MARK: - SelectedDocument

struct SelectedDocument: Identifiable, Equatable {
    let id: UUID
    let name: String
    let size: Int64
    let url: URL
}

// MARK: - SelectedDocumentFileStore

/// The app's copies of composer attachments: documents, photos, Live Photo motion and videos. A file the composer
/// holds is unleased; a sent file is leased to its message until TDLib sends it or the message is deleted. A
/// failed message keeps its files for Resend.
enum SelectedDocumentFileStore {
    private struct Lease: Codable {
        let accountID: UUID?
        let chatID: Int64
        let createdAt: Date
        let fileName: String
        var messageID: Int64
        /// Media outlives its send for a while: a sent photo's bubble keeps drawing the uploaded original
        /// (`telegramLocalPhotoFile`).
        var defersRemoval: Bool?
    }

    private struct MessageKey: Hashable {
        let accountID: UUID?
        let chatID: Int64
        let messageID: Int64
    }

    /// What TDLib reported for a message before its files were leased to it: the send or resend call that leases them
    /// had not returned yet.
    private enum EarlyOutcome {
        case finished
        case replaced(by: Int64)
    }

    private static let fileManager = FileManager.default
    private static let lock = NSLock()
    /// As long as the sent bubble keeps the composer's preview (`MediaUploadProgressRegistry.rememberSentPreview`).
    private static let deferredRemovalDelay: TimeInterval = 120
    private static let earlyOutcomeLifetime: TimeInterval = 300
    private static let earlyOutcomeCapacity = 512
    private static var earlyOutcomes = [MessageKey: (outcome: EarlyOutcome, recordedAt: Date)]()

    static var directory: URL {
        fileManager.temporaryDirectory.appendingPathComponent(
            "BetterTGSelectedDocuments",
            isDirectory: true,
        )
    }

    private static var leaseManifestURL: URL {
        directory.appendingPathComponent("upload-leases.json")
    }

    static func copy(_ urls: [URL]) -> [SelectedDocument] {
        cleanupExpiredFiles()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return urls.compactMap { source in
            let accessing = source.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    source.stopAccessingSecurityScopedResource()
                }
            }
            let name = source.lastPathComponent.isEmpty ? "File" : source.lastPathComponent
            let destination = directory.appendingPathComponent("\(UUID().uuidString)-\(name)")
            do {
                try fileManager.copyItem(at: source, to: destination)
                let attributes = try fileManager.attributesOfItem(atPath: destination.path)
                let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                return SelectedDocument(id: UUID(), name: name, size: size, url: destination)
            } catch {
                try? fileManager.removeItem(at: destination)
                return nil
            }
        }
    }

    /// A new file name in the store for a photo, Live Photo motion or video the composer will hold.
    static func makeFileURL(named name: String) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(UUID().uuidString)-\(name)")
    }

    /// Removes unleased files left for a day, as a document pick does before copying.
    static func removeExpiredFiles() {
        cleanupExpiredFiles()
    }

    static func remove(_ urls: [URL]) {
        lock.lock()
        defer { lock.unlock() }
        var leases = loadLeases()
        let names = Set(validatedFileNames(urls))
        leases.removeAll { names.contains($0.fileName) }
        for name in names {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
        try? saveLeases(leases)
    }

    static func removeUnleased(_ urls: [URL]) {
        lock.lock()
        defer { lock.unlock() }
        let leasedNames = Set(loadLeases().map(\.fileName))
        for name in validatedFileNames(urls) where !leasedNames.contains(name) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    static func lease(
        _ url: URL,
        accountID: UUID?,
        chatID: Int64,
        messageID: Int64,
    ) throws {
        try lease([url], accountID: accountID, chatID: chatID, messageID: messageID, defersRemoval: false)
    }

    /// Leases every file one message sends, replacing the message's previous leases.
    static func lease(
        _ urls: [URL],
        accountID: UUID?,
        chatID: Int64,
        messageID: Int64,
        defersRemoval: Bool,
    ) throws {
        let fileNames = validatedFileNames(urls)
        guard !fileNames.isEmpty, fileNames.count == urls.count else {
            throw CocoaError(.fileNoSuchFile)
        }
        lock.lock()
        defer { lock.unlock() }
        var leases = loadLeases()
        leases.removeAll {
            $0.accountID == accountID && $0.chatID == chatID && $0.messageID == messageID
        }
        let created = fileNames.map {
            Lease(
                accountID: accountID,
                chatID: chatID,
                createdAt: Date(),
                fileName: $0,
                messageID: messageID,
                defersRemoval: defersRemoval ? true : nil,
            )
        }
        guard let owner = currentMessage(for: MessageKey(accountID: accountID, chatID: chatID, messageID: messageID))
        else {
            try saveLeases(leases)
            removeFiles(of: created)
            return
        }
        leases += created.map {
            var lease = $0
            lease.messageID = owner.messageID
            return lease
        }
        try saveLeases(leases)
    }

    /// Moves leases to another message. When TDLib already finished that message, its files are released now.
    static func replaceMessageID(
        accountID: UUID?,
        chatID: Int64,
        old: Int64,
        new: Int64,
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        var leases = loadLeases()
        let matches: (Lease) -> Bool = {
            $0.accountID == accountID && $0.chatID == chatID && $0.messageID == old
        }
        guard leases.contains(where: matches) else {
            recordEarlyOutcome(
                .replaced(by: new),
                for: MessageKey(accountID: accountID, chatID: chatID, messageID: old),
            )
            throw CocoaError(.fileNoSuchFile)
        }
        if let owner = currentMessage(for: MessageKey(accountID: accountID, chatID: chatID, messageID: new)) {
            for index in leases.indices where matches(leases[index]) {
                leases[index].messageID = owner.messageID
            }
            try saveLeases(leases)
        } else {
            let finished = leases.filter(matches)
            leases.removeAll(where: matches)
            try saveLeases(leases)
            removeFiles(of: finished)
        }
    }

    static func unlease(
        accountID: UUID?,
        chatID: Int64,
        messageID: Int64,
    ) {
        lock.lock()
        defer { lock.unlock() }
        var leases = loadLeases()
        let previousCount = leases.count
        leases.removeAll {
            $0.accountID == accountID && $0.chatID == chatID && $0.messageID == messageID
        }
        if leases.count != previousCount {
            try? saveLeases(leases)
        }
    }

    static func complete(
        accountID: UUID?,
        chatID: Int64,
        messageID: Int64,
    ) {
        lock.lock()
        defer { lock.unlock() }
        var leases = loadLeases()
        let completed = leases.filter {
            $0.accountID == accountID && $0.chatID == chatID && $0.messageID == messageID
        }
        guard !completed.isEmpty else {
            recordEarlyOutcome(.finished, for: MessageKey(accountID: accountID, chatID: chatID, messageID: messageID))
            return
        }
        leases.removeAll {
            $0.accountID == accountID && $0.chatID == chatID && $0.messageID == messageID
        }
        try? saveLeases(leases)
        removeFiles(of: completed)
    }

    /// The message a lease for `key` belongs to after the replacements TDLib already reported, or nil when it
    /// already finished. Called with the lock held.
    private static func currentMessage(for key: MessageKey) -> MessageKey? {
        let now = Date()
        var current = key
        var visited = Set<MessageKey>()
        while visited.insert(current).inserted,
              let early = earlyOutcomes[current],
              now.timeIntervalSince(early.recordedAt) < earlyOutcomeLifetime
        {
            switch early.outcome {
            case .finished:
                return nil
            case .replaced(let messageID):
                current = MessageKey(accountID: current.accountID, chatID: current.chatID, messageID: messageID)
            }
        }
        return current
    }

    /// Called with the lock held.
    private static func recordEarlyOutcome(_ outcome: EarlyOutcome, for key: MessageKey) {
        let now = Date()
        earlyOutcomes = earlyOutcomes.filter { now.timeIntervalSince($0.value.recordedAt) < earlyOutcomeLifetime }
        if earlyOutcomes.count >= earlyOutcomeCapacity,
           let oldest = earlyOutcomes.min(by: { $0.value.recordedAt < $1.value.recordedAt })?.key
        {
            earlyOutcomes[oldest] = nil
        }
        earlyOutcomes[key] = (outcome, now)
    }

    /// Removes released files; media files wait until a sent bubble no longer draws them.
    private static func removeFiles(of leases: [Lease]) {
        var deferred = [URL]()
        for lease in leases {
            let url = directory.appendingPathComponent(lease.fileName)
            if lease.defersRemoval == true {
                deferred.append(url)
            } else {
                try? fileManager.removeItem(at: url)
            }
        }
        guard !deferred.isEmpty else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + deferredRemovalDelay) {
            removeUnleased(deferred)
        }
    }

    private static func cleanupExpiredFiles() {
        lock.lock()
        defer { lock.unlock() }
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles],
        ) else { return }
        var leases = loadLeases()
        let staleLeaseCutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let staleLeases = leases.filter { $0.createdAt < staleLeaseCutoff }
        leases.removeAll { $0.createdAt < staleLeaseCutoff }
        for lease in staleLeases {
            if let url = managedURL(fileName: lease.fileName) {
                try? fileManager.removeItem(at: url)
            }
        }
        try? saveLeases(leases)
        let leasedNames = Set(leases.map(\.fileName))
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for url in urls where url.lastPathComponent != leaseManifestURL.lastPathComponent
            && !leasedNames.contains(url.lastPathComponent)
        {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if modified.map({ $0 < cutoff }) ?? true {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private static func validatedFileNames(_ urls: [URL]) -> [String] {
        urls.compactMap { url in
            guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else {
                return nil
            }
            let name = url.lastPathComponent
            return managedURL(fileName: name) == nil ? nil : name
        }
    }

    private static func managedURL(fileName: String) -> URL? {
        guard fileName != ".", fileName != "..",
              fileName.count > 37,
              fileName[fileName.index(fileName.startIndex, offsetBy: 36)] == "-",
              UUID(uuidString: String(fileName.prefix(36))) != nil,
              URL(fileURLWithPath: fileName).lastPathComponent == fileName
        else { return nil }
        let url = directory.appendingPathComponent(fileName).standardizedFileURL
        guard url.deletingLastPathComponent() == directory.standardizedFileURL else { return nil }
        return url
    }

    private static func loadLeases() -> [Lease] {
        guard let data = try? Data(contentsOf: leaseManifestURL),
              let leases = try? JSONDecoder().decode([Lease].self, from: data)
        else { return [] }
        return leases.filter {
            guard let url = managedURL(fileName: $0.fileName) else { return false }
            return fileManager.fileExists(atPath: url.path)
        }
    }

    private static func saveLeases(_ leases: [Lease]) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if leases.isEmpty {
            try? fileManager.removeItem(at: leaseManifestURL)
        } else {
            let data = try JSONEncoder().encode(leases)
            try data.write(to: leaseManifestURL, options: .atomic)
        }
    }
}
