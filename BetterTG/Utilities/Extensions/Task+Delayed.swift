// Task+Delayed.swift

import Foundation

extension Task where Failure == Error {
    static func delayed(
        by seconds: Int,
        priority: TaskPriority? = nil,
        @_implicitSelfCapture operation: @escaping @Sendable () async throws -> Success
    ) {
        Task(priority: priority) {
            try await Task<Never, Never>.sleep(for: .seconds(seconds))
            return try await operation()
        }
    }
}
