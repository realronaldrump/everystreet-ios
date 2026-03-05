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
            return "Request failed (\(status)): \(body)"
        case let .decodingFailed(context):
            return "Decoding failed: \(context)"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}
