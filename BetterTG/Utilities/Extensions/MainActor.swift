// MainActor.swift

import Foundation

extension MainActor {
    public static func run<T: Sendable>(_ body: @MainActor @Sendable () throws -> T) async rethrows -> T {
        try await Self.run(body: {
            try body()
        })
    }
}
