// +main.swift

import Foundation

extension Task where Failure == Error {
    static func main(
        priority: TaskPriority? = nil,
        @_implicitSelfCapture _ operation: @escaping @MainActor @Sendable () -> Success
    ) {
        Task { @MainActor in
            operation()
        }
    }
}
