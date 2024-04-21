// Task.swift

extension Task where Failure == Error {
    @discardableResult static func main(
        delay: Double? = nil,
        priority: TaskPriority? = nil,
        @_implicitSelfCapture _ operation: @escaping @MainActor @Sendable () async throws -> Success
    ) -> Task {
        if let delay {
            Task(priority: priority) { @MainActor in
                try await Task<Never, Never>.sleep(for: .seconds(delay))
                return try await operation()
            }
        } else {
            Task(priority: priority) { @MainActor in
                try await operation()
            }
        }
    }
    
    @discardableResult static func background(
        delay: Double? = nil,
        priority: TaskPriority? = nil,
        _ operation: @escaping @Sendable () async throws -> Success
    ) -> Task {
        if let delay {
            Task.detached(priority: priority) {
                try await Task<Never, Never>.sleep(for: .seconds(delay))
                return try await operation()
            }
        } else {
            Task.detached(priority: priority) {
                try await operation()
            }
        }
    }
}

extension Task where Success == Void, Failure == Never {
    static func sleep(_ seconds: Double?) async throws {
        if let seconds {
            try await Task<Never, Never>.sleep(for: .seconds(seconds))
        }
    }
}

func main<Value>(delay: Double? = nil, _ operation: @escaping @Sendable () throws -> Value) async throws -> Value {
    try await Task.sleep(delay)
    return try await MainActor.run(resultType: Value.self) {
        try operation()
    }
}

func main<Value>(delay: Double? = nil, _ operation: @escaping @Sendable () -> Value) async -> Value {
    try? await Task.sleep(delay)
    return await MainActor.run(resultType: Value.self) {
        operation()
    }
}
