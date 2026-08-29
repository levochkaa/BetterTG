// PushRelayModels.swift

import Foundation

// MARK: - RelayAPNsEnvironment

enum RelayAPNsEnvironment: String, Codable {
    case sandbox
    case production

    // MARK: Internal

    static var current: Self {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }
}

// MARK: - RelayInstallationCredentials

struct RelayInstallationCredentials: Codable, Equatable {
    let installationId: String
    let managementSecret: String
}

// MARK: - RelayTelegramSubscription

struct RelayTelegramSubscription: Codable, Equatable {
    let subscriptionId: String
    let endpoint: String
    let p256dhBase64url: String
    let authBase64url: String
}

// MARK: - PushRelayPersistentState

struct PushRelayPersistentState: Codable, Equatable {
    // MARK: Lifecycle

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.appAttestKeyId = try container.decodeIfPresent(String.self, forKey: .appAttestKeyId)
        self.installation = try container.decodeIfPresent(RelayInstallationCredentials.self, forKey: .installation)
        self.subscription = try container.decodeIfPresent(RelayTelegramSubscription.self, forKey: .subscription)
        self.apnsToken = try container.decodeIfPresent(String.self, forKey: .apnsToken)
        self.installationIdempotencyKey = try container.decodeIfPresent(
            String.self,
            forKey: .installationIdempotencyKey,
        )
        self.lastTDLibRegistrationAt = try container.decodeIfPresent(Date.self, forKey: .lastTDLibRegistrationAt)
        self.registeredTelegramUserId = try container.decodeIfPresent(Int64.self, forKey: .registeredTelegramUserId)
        self.pushReceiverId = try container.decodeIfPresent(Int64.self, forKey: .pushReceiverId)
        self.pendingSubscriptionRevocation = try container.decodeIfPresent(
            Bool.self,
            forKey: .pendingSubscriptionRevocation,
        ) ?? false
    }

    // MARK: Internal

    var appAttestKeyId: String?
    var installation: RelayInstallationCredentials?
    var subscription: RelayTelegramSubscription?
    var apnsToken: String?
    var installationIdempotencyKey: String?
    var lastTDLibRegistrationAt: Date?
    var registeredTelegramUserId: Int64?
    var pushReceiverId: Int64?
    var pendingSubscriptionRevocation = false
}

// MARK: - RelayChallenge

struct RelayChallenge: Decodable {
    let challenge: String
}

// MARK: - RelayAttestationRequest

struct RelayAttestationRequest: Encodable {
    let keyId: String
    let challenge: String
    let attestation: String
}

// MARK: - RelayCreateInstallationRequest

struct RelayCreateInstallationRequest: Encodable {
    let apnsToken: String
    let apnsEnvironment: RelayAPNsEnvironment
    let appVersion: String
    let osVersion: String
    let attestChallenge: String?
}

// MARK: - RelayUpdateAPNsTokenRequest

struct RelayUpdateAPNsTokenRequest: Encodable {
    let apnsToken: String
    let apnsEnvironment: RelayAPNsEnvironment
    let appVersion: String
    let osVersion: String
}

// MARK: - RelaySignedRequest

struct RelaySignedRequest {
    let body: Data
    let headers: [String: String]
}

// MARK: - PushRelayConfiguration

struct PushRelayConfiguration {
    static var current: Self? {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-push-relay-url"),
           arguments.indices.contains(index + 1),
           let url = URL(string: arguments[index + 1])
        {
            return Self(baseURL: url)
        }
        guard let value = Bundle.main.object(forInfoDictionaryKey: "BetterTGRelayBaseURL") as? String,
              !value.isEmpty,
              let url = URL(string: value)
        else { return nil }
        return Self(baseURL: url)
    }

    let baseURL: URL
}

// MARK: - RelayAPIError

struct RelayAPIError: Error, LocalizedError {
    let statusCode: Int

    var errorDescription: String? {
        "Push relay returned HTTP \(statusCode)"
    }
}
