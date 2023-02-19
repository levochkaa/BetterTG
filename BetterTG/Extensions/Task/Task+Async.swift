// Task+Async.swift

import SwiftUI

extension Task where Success == Never, Failure == Never {
    static func async(
        after time: TimeInterval,
        @_implicitSelfCapture _ execute: @MainActor @Sendable @escaping @convention(block) () -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + time, execute: execute)
    }
}
