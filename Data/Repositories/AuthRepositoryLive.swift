import Foundation

@MainActor
final class AuthRepositoryLive: AuthRepository {
    private enum AuthFailure: LocalizedError {
        case invalidPassword

        var errorDescription: String? {
            switch self {
            case .invalidPassword:
                return "Sign in failed. Check the owner password and try again."
            }
        }
    }

    func hasActiveSession() async throws -> Bool {
        let client = makeClient()

        do {
            _ = try await client.get(path: "api/first_trip_date")
            return true
        } catch let error as APIError where error.isUnauthorized {
            return false
        }
    }

    func login(password: String) async throws {
        let client = makeClient()
        _ = try await client.postForm(path: "login", fields: [
            "password": password,
            "next": "/"
        ])

        guard try await hasActiveSession() else {
            throw AuthFailure.invalidPassword
        }
    }

    func clearSession() {
        guard let host = AppSettingsStore.shared.apiBaseURL.host()?.lowercased() else { return }
        let cookieStorage = HTTPCookieStorage.shared

        cookieStorage.cookies?
            .filter { cookie in
                let domain = cookie.domain.lowercased()
                return domain == host || domain.hasSuffix("." + host)
            }
            .forEach(cookieStorage.deleteCookie)
    }

    private func makeClient() -> APIClient {
        APIClient(baseURL: AppSettingsStore.shared.apiBaseURL)
    }
}