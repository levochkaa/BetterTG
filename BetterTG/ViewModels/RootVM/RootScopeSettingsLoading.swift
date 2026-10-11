// RootScopeSettingsLoading.swift

import Foundation
import TDLibKit

/// Read revisions are reserved before dispatch. A newer load or accepted scope
/// update revokes only the affected reads; account/client authority stays with
/// the caller's captured RootListAuthority ticket.
@MainActor final class RootScopeSettingsLoading {
    struct Read {
        let scope: NotificationSettingsScope

        fileprivate let revision: UUID
    }

    private var revisions = [NotificationSettingsScope: UUID]()

    func reserveReads() -> [Read] {
        let scopes: [NotificationSettingsScope] = [
            .notificationSettingsScopePrivateChats,
            .notificationSettingsScopeGroupChats,
            .notificationSettingsScopeChannelChats,
        ]
        return scopes.map { scope in
            let revision = UUID()
            revisions[scope] = revision
            return Read(scope: scope, revision: revision)
        }
    }

    func invalidate(scope: NotificationSettingsScope) {
        revisions[scope] = nil
    }

    func invalidate() {
        revisions.removeAll()
    }

    func load(
        _ reads: [Read],
        accepts: () -> Bool,
        fetch: (NotificationSettingsScope) async throws -> ScopeNotificationSettings,
        publish: (NotificationSettingsScope, ScopeNotificationSettings) -> Void,
    ) async {
        for read in reads {
            guard !Task.isCancelled, accepts() else { return }
            guard revisions[read.scope] == read.revision else { continue }
            defer {
                if revisions[read.scope] == read.revision { revisions[read.scope] = nil }
            }
            guard let settings = try? await fetch(read.scope),
                  !Task.isCancelled, accepts(), revisions[read.scope] == read.revision
            else { continue }
            // Publish before reading another scope. Never merge an old batch
            // over values accepted while its later scopes were still loading.
            publish(read.scope, settings)
        }
    }
}
