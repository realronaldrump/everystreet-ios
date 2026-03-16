import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case requestFailed(status: Int, body: String)
    case decodingFailed(context: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case let .requestFailed(status, body):
            if status == 401, body.localizedCaseInsensitiveContains("owner session required") {
                return "Sign in required. Enter the owner password to create a session."
            }
            return "Request failed (\(status)): \(body)"
        case let .decodingFailed(context):
            return "Decoding failed: \(context)"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }

    var isUnauthorized: Bool {
        guard case let .requestFailed(status, _) = self else { return false }
        return status == 401
    }
}
