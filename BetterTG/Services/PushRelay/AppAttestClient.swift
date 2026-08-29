// AppAttestClient.swift

import CryptoKit
import DeviceCheck
import Foundation

actor AppAttestClient {
    // MARK: Lifecycle

    init(stateStore: PushRelayStateStore) {
        self.stateStore = stateStore
    }

    // MARK: Internal

    func signedInstallationRequest(
        api: PushRelayAPIClient,
        apnsToken: String,
    ) async throws -> RelaySignedRequest {
        let service = DCAppAttestService.shared
        guard service.isSupported else {
            log("App Attest is unsupported; creating unsigned installation request")
            return try RelaySignedRequest(
                body: encodeInstallation(apnsToken: apnsToken, challenge: nil),
                headers: [:],
            )
        }

        log("Generating App Attest assertion for installation request")
        let keyId = try await attestedKeyId(api: api, service: service)
        let challenge = try await api.challenge().challenge
        let body = try encodeInstallation(apnsToken: apnsToken, challenge: challenge)
        let clientDataHash = Data(SHA256.hash(data: body))
        let assertion = try await service.generateAssertion(keyId, clientDataHash: clientDataHash)
        return RelaySignedRequest(
            body: body,
            headers: [
                "X-App-Attest-Key-Id": keyId,
                "X-App-Attest-Assertion": assertion.base64EncodedString(),
            ],
        )
    }

    func resetKey() async throws {
        try await stateStore.update { $0.appAttestKeyId = nil }
    }

    // MARK: Private

    private let stateStore: PushRelayStateStore
    private let encoder = JSONEncoder()

    private func attestedKeyId(
        api: PushRelayAPIClient,
        service: DCAppAttestService,
    ) async throws -> String {
        if let keyId = try await stateStore.load().appAttestKeyId {
            log("Using existing App Attest key")
            return keyId
        }

        log("Creating and attesting a new App Attest key")
        let challenge = try await api.challenge().challenge
        let keyId = try await service.generateKey()
        let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))
        let attestation = try await service.attestKey(keyId, clientDataHash: clientDataHash)
        try await api.submitAttestation(
            RelayAttestationRequest(
                keyId: keyId,
                challenge: challenge,
                attestation: attestation.base64EncodedString(),
            ),
        )
        try await stateStore.update { $0.appAttestKeyId = keyId }
        log("App Attest key registered with push relay")
        return keyId
    }

    private func encodeInstallation(apnsToken: String, challenge: String?) throws -> Data {
        try encoder.encode(
            RelayCreateInstallationRequest(
                apnsToken: apnsToken,
                apnsEnvironment: .current,
                appVersion: Utils.applicationVersion,
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                attestChallenge: challenge,
            ),
        )
    }
}
