// TDImageOrigin.swift

import Combine
import Foundation
import TDLibKitDynamic

/// Authority comes from the client that supplied a file, never from its numeric ID.
@MainActor struct TDImageOrigin {
    let source: TdUpdateSource
    let backend: AnimatedFileDownload.Backend
    let demand: AnimatedFileDemand
    let currentSource: () -> TdUpdateSource?
    let changes: AnyPublisher<TdUpdateSource, Never>

    var isCurrent: Bool { currentSource() == source }

    static func captured(client: TDLibClient, accountID: UUID? = nil) -> Self? {
        guard let source = TDLib.shared.activeUpdateSource, source.clientID == client.id,
              accountID == nil || accountID == source.accountID else { return nil }
        return Self(
            source: source,
            backend: .init(
                download: { id in
                    guard TDLib.shared.activeUpdateSource == source else { return nil }
                    return try? await client.downloadFile(
                        fileId: id,
                        limit: 0,
                        offset: 0,
                        priority: 1,
                        synchronous: false,
                    )
                },
                cancel: { _ = try? await client.cancelDownloadFile(fileId: $0, onlyIfPending: true) },
            ),
            demand: .shared, currentSource: { TDLib.shared.activeUpdateSource },
            changes: TDLib.shared.activeClientChanges,
        )
    }

    func request(fileID: Int) -> AnimatedFileDownload {
        AnimatedFileDownload(
            fileID: fileID, source: source, backend: backend, demand: demand,
            currentSource: currentSource, sourceChanges: changes,
        )
    }
}
