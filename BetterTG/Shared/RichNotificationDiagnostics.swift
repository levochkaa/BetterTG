// RichNotificationDiagnostics.swift

import Darwin
import Foundation

// MARK: - RichNotificationDiagnosticEntry

struct RichNotificationDiagnosticEntry: Codable {
    let timestamp: Date
    let event: String
    let fields: [String: String]
}

// MARK: - RichNotificationDiagnostics

enum RichNotificationDiagnostics {
    private static let maximumEntries = 100

    static func record(_ event: String, fields: [String: String] = [:]) {
        withLockedEntries { entries in
            entries.append(.init(timestamp: Date(), event: event, fields: fields))
            if entries.count > maximumEntries {
                entries.removeFirst(entries.count - maximumEntries)
            }
        }
    }

    static func drain() -> [RichNotificationDiagnosticEntry] {
        var drained = [RichNotificationDiagnosticEntry]()
        withLockedEntries { entries in
            drained = entries
            entries.removeAll()
        }
        return drained
    }

    private static func withLockedEntries(_ body: (inout [RichNotificationDiagnosticEntry]) -> Void) {
        guard let container = BetterTGAppGroup.containerURL() else { return }
        let lockURL = container.appendingPathComponent("rich-notification-diagnostics.lock")
        let dataURL = container.appendingPathComponent("rich-notification-diagnostics.json")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return }
        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        guard flock(descriptor, LOCK_EX) == 0 else { return }

        var entries = ((try? Data(contentsOf: dataURL))
            .flatMap { try? JSONDecoder().decode([RichNotificationDiagnosticEntry].self, from: $0) }) ?? []
        body(&entries)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: dataURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: dataURL.path,
        )
    }
}
