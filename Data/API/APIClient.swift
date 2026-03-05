import Foundation

struct APIClient {
    struct Payload {
        let data: Data
        let statusCode: Int
        let headers: [AnyHashable: Any]

        func headerValue(_ name: String) -> String? {
            let match = headers.first { key, _ in
                guard let key = key as? String else { return false }
                return key.caseInsensitiveCompare(name) == .orderedSame
            }
            return match?.value as? String
        }
    }

    var baseURL: URL
    var session: URLSession = .shared

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func get(path: String, query: [URLQueryItem] = []) async throws -> Data {
        let payload = try await get(
            path: path,
            query: query,
            headers: [:],
            allowNotModified: false
        )
        return payload.data
    }

    func get(
        path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        allowNotModified: Bool
    ) async throws -> Payload {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }

        if !query.isEmpty {
            components.queryItems = query
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await session.data(for: request)
        let http = try validate(response: response, data: data, allowNotModified: allowNotModified)
        return Payload(data: data, statusCode: http.statusCode, headers: http.allHeaderFields)
    }

    func post(path: String, body: [String: Any]) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        _ = try validate(response: response, data: data, allowNotModified: false)
        return data
    }

    private func validate(
        response: URLResponse,
        data: Data,
        allowNotModified: Bool
    ) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if allowNotModified, http.statusCode == 304 {
            return http
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.requestFailed(status: http.statusCode, body: body)
        }
        return http
    }
}
