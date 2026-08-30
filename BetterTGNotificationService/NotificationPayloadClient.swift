// NotificationPayloadClient.swift

import Foundation

struct NotificationPayloadClient {
    enum PayloadError: Error {
        case unavailable
        case invalidResponse
        case invalidPayload
    }

    func fetch(token: String) async throws -> String {
        guard token.range(of: #"^[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil,
              let baseURL = PushRelaySharedConfiguration.baseURL
        else { throw PayloadError.unavailable }

        let url = baseURL
            .appendingPathComponent("notification-content")
            .appendingPathComponent("v1")
            .appendingPathComponent(token)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 7)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 7
        configuration.timeoutIntervalForResource = 7
        configuration.waitsForConnectivity = false
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw PayloadError.invalidResponse
        }
        guard data.count <= 64 * 1024,
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let canonical = try? JSONSerialization.data(withJSONObject: object),
              let payload = String(data: canonical, encoding: .utf8)
        else { throw PayloadError.invalidPayload }
        return payload
    }
}
