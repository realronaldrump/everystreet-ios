import Foundation

enum TaskRetry {
    @MainActor
    static func run<T>(
        retries: Int = 2,
        initialDelayNanoseconds: UInt64 = 250_000_000,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var delay = initialDelayNanoseconds

        while true {
            do {
                return try await operation()
            } catch {
                if attempt >= retries {
                    throw error
                }
                attempt += 1
                try? await Task.sleep(nanoseconds: delay)
                delay *= 2
            }
        }
    }
}
