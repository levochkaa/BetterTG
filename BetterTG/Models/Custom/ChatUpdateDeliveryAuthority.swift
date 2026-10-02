// ChatUpdateDeliveryAuthority.swift

import Combine
import Foundation

/// Authority of an accepted TDLib UI update. It never rebinds to a replacement
/// client and is separate from durable draft outcomes owned by an account.
struct ChatUpdateDeliveryAuthority {
    let source: TdUpdateSource
    let location: ChatLocation

    init?(source: TdUpdateSource?, location: ChatLocation) {
        guard let source, source.matches(location) else { return nil }
        self.source = source
        self.location = location
    }

    @MainActor static func observe<Value>(
        _ notification: TdNotification<Value>,
        center: NotificationCenter,
        subscriptions: inout Set<AnyCancellable>,
        location: ChatLocation,
        currentLocation: @escaping () -> ChatLocation?,
        currentSource: @escaping () -> TdUpdateSource?,
        ownerIsCurrent: @escaping () -> Bool,
        perform: @escaping (Value, Self) -> Void,
    ) {
        center.scopedPublisher(&subscriptions, for: notification) { event in
            guard let authority = Self(source: event.source, location: location),
                  authority.permits(
                      currentLocation: currentLocation(), currentSource: currentSource(),
                      ownerIsCurrent: ownerIsCurrent(),
                  )
            else { return }
            perform(event.value, authority)
        }
    }

    func permits(currentLocation: ChatLocation?, currentSource: TdUpdateSource?, ownerIsCurrent: Bool) -> Bool {
        ownerIsCurrent && currentLocation == location && currentSource == source
    }
}
