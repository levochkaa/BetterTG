// VideoNotePlaybackBackend.swift

import Combine
import TDLibKitDynamic
import UIKit

/// One displayed message never follows a replacement TDLib client.
@MainActor struct VideoNotePlaybackBackend {
    let source: TdUpdateSource
    let center: NotificationCenter
    let clientChanges: AnyPublisher<TdUpdateSource, Never>
    let lifecycle: AnyPublisher<Foundation.Notification, Never>
    let isCurrent: () -> Bool
    let download: (Int, Bool) async throws -> File
    let cancelDownload: (Int) async -> Void
    let message: (Int64, Int64) async throws -> Message
    let open: (Int64, Int64) async throws -> Void
    let now: () -> TimeInterval
    let sleep: (TimeInterval) async throws -> Void
    let takePlayback: () -> Void

    static func captured(client: TDLibClient, context: MediaGalleryPlaybackContext?) -> Self? {
        guard let source = TDLib.shared.activeUpdateSource, source.clientID == client.id,
              context?.isCurrent != false else { return nil }
        return Self(
            source: source, center: nc, clientChanges: TDLib.shared.activeClientChanges,
            lifecycle: NotificationCenter.default
                .mergeMany([
                    UIApplication.willResignActiveNotification, UIScene.willDeactivateNotification,
                    UIApplication.didBecomeActiveNotification,
                ])
                .eraseToAnyPublisher(),
            isCurrent: { TDLib.shared.activeUpdateSource == source && context?.isCurrent != false },
            download: { try await client.downloadFile(fileId: $0, limit: 0, offset: 0, priority: 2, synchronous: $1) },
            cancelDownload: { _ = try? await client.cancelDownloadFile(fileId: $0, onlyIfPending: true) },
            message: { try await client.getMessage(chatId: $0, messageId: $1) },
            open: { _ = try await client.openMessageContent(chatId: $0, messageId: $1) },
            now: { ProcessInfo.processInfo.systemUptime },
            sleep: { try await Task.sleep(for: .seconds(max(0, $0))) },
            takePlayback: { Media.shared.beginExclusivePlayback() },
        )
    }

    /// TDLib accepts updates on main. Revoke pixels in that turn, before delayed UI hydration.
    func observe<T>(
        _ bindings: inout Set<AnyCancellable>,
        for name: TdNotification<T>,
        _ perform: @escaping @MainActor (TdScopedUpdate<T>) -> Void,
    ) {
        center.publisher(for: name.name)
            .compactMap { TdScopedUpdate<T>(notification: $0) }
            .sink { event in
                if Thread.isMainThread { MainActor.assumeIsolated { perform(event) } }
                else { Task { @MainActor in perform(event) } }
            }
            .store(in: &bindings)
    }
}
