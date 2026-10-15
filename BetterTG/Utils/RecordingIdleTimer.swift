// RecordingIdleTimer.swift

import UIKit

/// Keeps the screen awake while any owner records, as Telegram's `pushIdleTimerExtension` does for voice and video
/// notes; a hands-free locked recording would otherwise be cut when the device auto-locks.
@MainActor enum RecordingIdleTimer {
    private static var owners = Set<ObjectIdentifier>()

    static func hold(_ owner: AnyObject) {
        owners.insert(ObjectIdentifier(owner))
        UIApplication.shared.isIdleTimerDisabled = true
    }

    static func release(_ owner: AnyObject) {
        guard owners.remove(ObjectIdentifier(owner)) != nil else { return }
        if owners.isEmpty { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
