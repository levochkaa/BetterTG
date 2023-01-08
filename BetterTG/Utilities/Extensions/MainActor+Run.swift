// MainActor+Run.swift

import Foundation

extension MainActor {
    public static func run<T>(_ body: @MainActor @Sendable () throws -> T) async rethrows -> T where T : Sendable {
        try await Self.run(body: {
            try body()
        })
    }
}
