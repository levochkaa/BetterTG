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

enum SelectedDocumentFileStore {
    private struct Lease: Codable {
        let accountID: UUID?
        let chatID: Int64
        let createdAt: Date
        let fileName: String
        var messageID: Int64
    }

    private static let fileManager = FileManager.default
    private static let lock = NSLock()

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
        guard let fileName = validatedFileNames([url]).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        lock.lock()
        defer { lock.unlock() }
        var leases = loadLeases()
        leases.removeAll {
            $0.accountID == accountID && $0.chatID == chatID && $0.messageID == messageID
        }
        leases.append(Lease(
            accountID: accountID,
            chatID: chatID,
            createdAt: Date(),
            fileName: fileName,
            messageID: messageID,
        ))
        try saveLeases(leases)
    }

    static func replaceMessageID(
        accountID: UUID?,
        chatID: Int64,
        old: Int64,
        new: Int64,
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        var leases = loadLeases()
        var changed = false
        for index in leases.indices
            where leases[index].accountID == accountID
            && leases[index].chatID == chatID
            && leases[index].messageID == old
        {
            leases[index].messageID = new
            changed = true
        }
        guard changed else { throw CocoaError(.fileNoSuchFile) }
        try saveLeases(leases)
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
        guard !completed.isEmpty else { return }
        leases.removeAll {
            $0.accountID == accountID && $0.chatID == chatID && $0.messageID == messageID
        }
        for lease in completed {
            try? fileManager.removeItem(at: directory.appendingPathComponent(lease.fileName))
        }
        try? saveLeases(leases)
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
