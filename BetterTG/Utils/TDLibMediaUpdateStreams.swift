// TDLibMediaUpdateStreams.swift

import Combine
import Foundation
@preconcurrency import TDLibKit

// MARK: - TDLibMediaUpdateStreams

/// Immutable client-generation transport. A retained publisher never follows account
/// switching or client replacement, even when their numeric file/message IDs collide.
final class TDLibMediaUpdateStreams {
    private let source: TdUpdateSource?
    private let files = PassthroughSubject<UpdateFile, Never>()
    private let deletions = PassthroughSubject<UpdateDeleteMessages, Never>()

    var fileUpdates: AnyPublisher<UpdateFile, Never> { files.eraseToAnyPublisher() }
    var deleteMessageUpdates: AnyPublisher<UpdateDeleteMessages, Never> { deletions.eraseToAnyPublisher() }

    init(source: TdUpdateSource?) {
        self.source = source
    }

    /// Called only after TDLib accepts the event from its active client. The source
    /// guard also rejects unscoped/bootstrap events instead of assigning an owner.
    func publish(_ update: Update, source: TdUpdateSource?) {
        guard let source, source == self.source else { return }
        switch update {
        case .updateFile(let value):
            files.send(value)
        case .updateDeleteMessages(let value):
            deletions.send(value)
        default:
            break
        }
    }
}

#if DEBUG
    @MainActor enum TDLibMediaUpdateStreamsProbe {
        private enum ProbeFailure: Swift.Error {
            case check(String)
        }

        private final class Observations {
            var files = [Int: Int]()
            var deletions = [Int: Int]()
            var unexpectedCompletion = false
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-client-streams") else { return }
            Task {
                let result: String
                do {
                    try await verify()
                    result = "TD client streams probe: colliding-file-bytes-isolated=true, "
                        + "retained-delete-subscriptions-isolated=true, same-account-new-client=true, "
                        + "stale-and-unscoped-rejected=true, bootstrap-inert=true, user-stores-untouched=true"
                } catch {
                    result = "TD client streams probe failed: \(error)"
                }
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("client-streams-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func verify() async throws {
            let temporaryDirectory = FileManager.default.temporaryDirectory
            let directory = temporaryDirectory.appendingPathComponent(
                "bettertg-client-streams-\(UUID().uuidString)",
                isDirectory: true,
            )
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let accountA = UUID()
            let sources = [
                TdUpdateSource(accountID: accountA, clientID: 11),
                TdUpdateSource(accountID: UUID(), clientID: 22),
                TdUpdateSource(accountID: accountA, clientID: 33),
            ]
            let bootstrap = TDLibMediaUpdateStreams(source: nil)
            var activeStreams = bootstrap
            let observations = Observations()
            var subscriptions = Set<AnyCancellable>()
            var coordinators = [TDLibVODRangeCoordinator]()
            var leases = [TDLibVODRangeLease]()
            var expectedBytes = [Data]()
            observe(bootstrap, index: -1, observations: observations, subscriptions: &subscriptions)
            defer { subscriptions.removeAll() }
            do {
                for (index, source) in sources.enumerated() {
                    activeStreams = TDLibMediaUpdateStreams(source: source)
                    observe(activeStreams, index: index, observations: observations, subscriptions: &subscriptions)
                    let initialURL = directory.appendingPathComponent("initial-\(index).bin")
                    let updatedURL = directory.appendingPathComponent("updated-\(index).bin")
                    let bytes = Data(repeating: UInt8(65 + index), count: 64)
                    try Data(repeating: 0, count: bytes.count).write(to: initialURL)
                    try bytes.write(to: updatedURL)
                    expectedBytes.append(bytes)
                    let initialFile = makeFile(url: initialURL, size: Int64(bytes.count))
                    // Reads must be satisfied by the actual stream update. A backend
                    // getFile fallback cannot hide a missing or cross-client delivery.
                    let client = TDLibVODRangeClient(
                        cancel: { _ in throw ProbeFailure.check("unexpected cancellation") },
                        download: { _, _, _, _, _ in throw ProbeFailure.check("unexpected download") },
                        downloadedPrefixSize: { _, _ in throw ProbeFailure.check("unexpected prefix query") },
                        getFile: { _ in throw ProbeFailure.check("unexpected getFile") },
                        isNetworkAvailable: { false },
                    )
                    let coordinator = TDLibVODRangeCoordinator(
                        accountID: source.accountID.uuidString,
                        client: client,
                        updates: activeStreams.fileUpdates,
                    )
                    coordinators.append(coordinator)
                    let lease = await coordinator.acquire(file: initialFile)
                    leases.append(lease)
                    let update = Update.updateFile(.init(file: makeFile(url: updatedURL, size: Int64(bytes.count))))
                    let deletion = Update.updateDeleteMessages(.init(
                        chatId: 777,
                        fromCache: false,
                        isPermanent: true,
                        messageIds: [888],
                    ))
                    // The real accepted-update gate remains in TDLib. The stream's
                    // second fence rejects wrong provenance and missing provenance.
                    for rejected in [nil, sources[(index + 1) % sources.count]] {
                        activeStreams.publish(update, source: rejected)
                        activeStreams.publish(deletion, source: rejected)
                    }
                    bootstrap.publish(update, source: source)
                    bootstrap.publish(deletion, source: nil)
                    activeStreams.publish(update, source: source)
                    activeStreams.publish(deletion, source: source)
                    try await waitForBytes(bytes, source: lease.source)
                    for previous in 0...index {
                        let chunk = try await leases[previous].source.read(offset: 0, count: bytes.count)
                        guard chunk.data == expectedBytes[previous],
                              observations.files[previous] == 1,
                              observations.deletions[previous] == 1
                        else { throw ProbeFailure.check("generation \(index) changed retained owner \(previous)") }
                    }
                    guard observations.files[-1] == nil, observations.deletions[-1] == nil,
                          !observations.unexpectedCompletion
                    else { throw ProbeFailure.check("bootstrap publisher received or completed") }
                }
            } catch {
                for lease in leases {
                    await lease.invalidate()
                }
                throw error
            }
            for lease in leases {
                await lease.invalidate()
            }
            withExtendedLifetime(coordinators) {}
        }

        private static func observe(
            _ streams: TDLibMediaUpdateStreams,
            index: Int,
            observations: Observations,
            subscriptions: inout Set<AnyCancellable>,
        ) {
            let files = streams.fileUpdates.sink(
                receiveCompletion: { _ in observations.unexpectedCompletion = true },
                receiveValue: { _ in observations.files[index, default: 0] += 1 },
            )
            files.store(in: &subscriptions)
            let deletions = streams.deleteMessageUpdates.sink(
                receiveCompletion: { _ in observations.unexpectedCompletion = true },
                receiveValue: { _ in observations.deletions[index, default: 0] += 1 },
            )
            deletions.store(in: &subscriptions)
        }

        private static func waitForBytes(_ expected: Data, source: TDLibVODRangeSource) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(2))
            repeat {
                let chunk = try await source.read(offset: 0, count: expected.count)
                if chunk.data == expected { return }
                try await Task<Never, Never>.sleep(for: .milliseconds(10))
            } while clock.now < deadline
            throw ProbeFailure.check("own stream update did not reach its range source")
        }

        private static func makeFile(url: URL, size: Int64) -> File {
            File(
                expectedSize: size,
                id: 7777,
                local: LocalFile(
                    canBeDeleted: false,
                    canBeDownloaded: true,
                    downloadOffset: 0,
                    downloadedPrefixSize: size,
                    downloadedSize: size,
                    isDownloadingActive: false,
                    isDownloadingCompleted: true,
                    path: url.path,
                ),
                remote: RemoteFile(
                    id: "isolated-probe",
                    isUploadingActive: false,
                    isUploadingCompleted: true,
                    uniqueId: "isolated-probe",
                    uploadedSize: size,
                ),
                size: size,
            )
        }
    }
#endif
