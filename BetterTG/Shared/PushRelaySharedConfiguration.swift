// PushRelaySharedConfiguration.swift

import Foundation

enum PushRelaySharedConfiguration {
    static var baseURL: URL? {
        guard let value = BetterTGAppGroup.defaults?.string(forKey: baseURLKey) else { return nil }
        return URL(string: value)
    }

    static func store(baseURL: URL) {
        BetterTGAppGroup.defaults?.set(baseURL.absoluteString, forKey: baseURLKey)
    }

    private static let baseURLKey = "push-relay-base-url"
}
