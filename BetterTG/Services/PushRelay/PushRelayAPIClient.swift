// PushRelayAPIClient.swift

import Foundation

actor PushRelayAPIClient {
    // MARK: Private

    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)
    }

    // MARK: Internal

    func challenge() async throws -> RelayChallenge {
        try await send(path: "api/v1/app-attest/challenge", method: "GET")
    }

    func submitAttestation(_ request: RelayAttestationRequest) async throws {
        let body = try encoder.encode(request)
        _ = try await data(path: "api/v1/app-attest/attestations", method: "POST", body: body)
    }

    func createInstallation(
        signedRequest: RelaySignedRequest,
        idempotencyKey: String,
    ) async throws -> RelayInstallationCredentials {
        try await send(
            path: "api/v1/installations",
            method: "POST",
            body: signedRequest.body,
            headers: signedRequest.headers.merging(["Idempotency-Key": idempotencyKey]) { current, _ in current },
        )
    }

    func updateAPNsToken(
        installation: RelayInstallationCredentials,
        request: RelayUpdateAPNsTokenRequest,
    ) async throws {
        _ = try await data(
            path: "api/v1/installations/\(installation.installationId)/apns-token",
            method: "PUT",
            body: encoder.encode(request),
            headers: authorization(installation),
        )
    }

    func createTelegramSubscription(
        installation: RelayInstallationCredentials,
    ) async throws -> RelayTelegramSubscription {
        try await send(
            path: "api/v1/installations/\(installation.installationId)/telegram-subscriptions",
            method: "POST",
            headers: authorization(installation),
        )
    }

    /// Deletes the installation with its subscription and, when no other installation uses it, its App Attest key.
    func deleteInstallation(_ installation: RelayInstallationCredentials) async throws {
        _ = try await data(
            path: "api/v1/installations/\(installation.installationId)",
            method: "DELETE",
            headers: authorization(installation),
        )
    }

    func deleteTelegramSubscription(
        _ subscription: RelayTelegramSubscription,
        installation: RelayInstallationCredentials,
    ) async throws {
        _ = try await data(
            path: "api/v1/installations/\(installation.installationId)/telegram-subscriptions/\(subscription.subscriptionId)",
            method: "DELETE",
            headers: authorization(installation),
        )
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        body: Data? = nil,
        headers: [String: String] = [:],
    ) async throws -> Response {
        let responseData = try await data(path: path, method: method, body: body, headers: headers)
        return try decoder.decode(Response.self, from: responseData)
    }

    private func data(
        path: String,
        method: String,
        body: Data? = nil,
        headers: [String: String] = [:],
    ) async throws -> Data {
        let requestURL = url(path: path)
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        log("Push relay request started: \(method) \(requestURL.path)")
        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            log("Push relay request failed: \(method) \(requestURL.path), error=\(error.localizedDescription)")
            throw error
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        log("Push relay request completed: \(method) \(requestURL.path), status=\(statusCode)")
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode
        else {
            throw RelayAPIError(statusCode: statusCode)
        }
        return responseData
    }

    private func url(path: String) -> URL {
        path.split(separator: "/").reduce(baseURL) { url, component in
            url.appending(path: String(component))
        }
    }

    private func authorization(_ installation: RelayInstallationCredentials) -> [String: String] {
        ["Authorization": "Bearer \(installation.managementSecret)"]
    }
}
