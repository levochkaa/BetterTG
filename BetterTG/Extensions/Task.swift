// Task.swift

extension Task where Failure == Error {
    static func main(
        delay: Double? = nil,
        @_implicitSelfCapture _ operation: @escaping @MainActor @Sendable () -> Success
    ) {
        if let delay {
            Task { @MainActor in
                try await Task<Never, Never>.sleep(for: .seconds(delay))
                return operation()
            }
        } else {
            Task { @MainActor in
                operation()
            }
        }
    }
}
