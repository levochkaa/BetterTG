// AnimatedFileDemand.swift

import Combine
import Foundation
import TDLibKit

/// Shared whole-image/animated-file demand. VOD ranges have a separate owner and must not
/// enter this pool: changing downloadFile's offset/limit supersedes their request.
@MainActor final class AnimatedFileDemand {
    struct Key: Hashable {
        let accountID: UUID
        let clientID: Int32
        let fileID: Int

        init(source: TdUpdateSource, fileID: Int) {
            self.accountID = source.accountID
            self.clientID = source.clientID
            self.fileID = fileID
        }
    }

    struct Token {
        let key: Key
        let id: UUID
    }

    private struct Consumer {
        let backend: AnimatedFileDownload.Backend
        let receive: (File?) -> Void
    }

    private final class Entry {
        enum Phase { case idle, starting, waiting, cancelling, finished }

        let key: Key
        var consumers = [UUID: Consumer]()
        var phase = Phase.idle
        var cancellationInFlight = false
        var latest: File?
        var revision: UInt64 = 0
        var backend: AnimatedFileDownload.Backend?

        init(key: Key, file: File) {
            self.key = key
            self.latest = file
        }
    }

    static let shared = AnimatedFileDemand(center: nc)

    private var entries = [Key: Entry]()
    private var subscriptions = Set<AnyCancellable>()

    #if DEBUG
        var entryCount: Int { entries.count }
    #endif

    init(center: NotificationCenter) {
        center.scopedPublisher(&subscriptions, for: .updateFile) { [weak self] event in
            guard let self,
                  let entry = entries[Key(source: event.source, fileID: event.value.file.id)],
                  !entry.cancellationInFlight
            else { return }
            entry.revision &+= 1
            receive(event.value.file, entry: entry)
        }
    }

    func acquire(
        file: File,
        source: TdUpdateSource,
        backend: AnimatedFileDownload.Backend,
        receive: @escaping (File?) -> Void,
    ) -> Token {
        let key = Key(source: source, fileID: file.id)
        let entry = entries[key] ?? Entry(key: key, file: file)
        entries[key] = entry
        let token = Token(key: key, id: UUID())
        entry.consumers[token.id] = Consumer(backend: backend, receive: receive)
        // A new demand is an explicit retry after failure; there is no retry timer.
        if entry.phase == .finished, entry.latest?.local.isDownloadingCompleted != true {
            entry.phase = .idle
        }
        Task { [weak self, weak entry] in
            guard let self, let entry, entries[key] === entry,
                  let consumer = entry.consumers[token.id]
            else { return }
            if entry.phase != .cancelling, let file = entry.latest { consumer.receive(file) }
            drive(entry)
        }
        return token
    }

    func release(_ token: Token) {
        guard let entry = entries[token.key], entry.consumers.removeValue(forKey: token.id) != nil else { return }
        drive(entry)
    }

    private func drive(_ entry: Entry) {
        guard entries[entry.key] === entry else { return }
        if entry.consumers.isEmpty {
            switch entry.phase {
            case .finished,
                 .idle:
                entries.removeValue(forKey: entry.key)
            case .waiting:
                if entry.latest?.local.isDownloadingCompleted == true {
                    entries.removeValue(forKey: entry.key)
                } else {
                    cancel(entry)
                }
            case .cancelling,
                 .starting:
                // A start RPC returns its immediate state before cancellation. A
                // replacement download waits for the old cancellation's reply.
                break
            }
            return
        }
        guard entry.phase == .idle else { return }
        if entry.latest?.local.isDownloadingCompleted == true {
            entry.phase = .finished
            return
        }
        guard let backend = entry.consumers.values.first?.backend else { return }
        entry.phase = .starting
        entry.backend = backend
        Task { [weak self, weak entry] in
            guard let self, let entry, entries[entry.key] === entry else { return }
            guard !entry.consumers.isEmpty else {
                entry.phase = .idle
                drive(entry)
                return
            }
            let revision = entry.revision
            let file = await backend.download(entry.key.fileID)
            guard entries[entry.key] === entry else { return }
            entry.phase = .waiting
            // An update accepted while the RPC was suspended is newer than its
            // initial-state reply, including a fully downloaded file.
            if file == nil, entry.latest?.local.isDownloadingCompleted != true {
                entry.phase = .finished
                notify(nil, entry: entry)
            } else if entry.revision == revision {
                if let file, file.id == entry.key.fileID {
                    receive(file, entry: entry)
                } else {
                    entry.phase = .finished
                    notify(nil, entry: entry)
                }
            }
            if let latest = entry.latest,
               latest.local.isDownloadingCompleted || !latest.local.isDownloadingActive,
               entry.phase == .waiting
            {
                entry.phase = .finished
                if !latest.local.isDownloadingCompleted { notify(nil, entry: entry) }
            }
            drive(entry)
        }
    }

    private func receive(_ file: File, entry: Entry) {
        entry.latest = file
        if entry.phase == .waiting,
           file.local.isDownloadingCompleted || !file.local.isDownloadingActive { entry.phase = .finished }
        notify(file, entry: entry)
        if entry.phase == .finished, !file.local.isDownloadingCompleted { notify(nil, entry: entry) }
        drive(entry)
    }

    private func notify(_ file: File?, entry: Entry) {
        // A callback may synchronously release its lease or another consumer.
        for id in Array(entry.consumers.keys) {
            entry.consumers[id]?.receive(file)
        }
    }

    private func cancel(_ entry: Entry) {
        guard let backend = entry.backend else { return }
        entry.phase = .cancelling
        Task { [weak self, weak entry] in
            guard let self, let entry, entries[entry.key] === entry else { return }
            if !entry.consumers.isEmpty || entry.latest?.local.isDownloadingCompleted == true {
                entry.phase = .waiting
                if let file = entry.latest { receive(file, entry: entry) }
                drive(entry)
                return
            }
            entry.cancellationInFlight = true
            await backend.cancel(entry.key.fileID)
            guard entries[entry.key] === entry else { return }
            entry.cancellationInFlight = false
            entry.phase = .idle
            entry.backend = nil
            drive(entry)
        }
    }
}
