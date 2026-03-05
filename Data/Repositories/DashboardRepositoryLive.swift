import Foundation
import SwiftData

@MainActor
final class DashboardRepositoryLive: DashboardRepository {
    private let container: ModelContainer
    private let dateFormatter: DateFormatter

    init(container: ModelContainer) {
        self.container = container
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        self.dateFormatter = formatter
    }

    func loadMetrics(range: DateInterval) async throws -> MetricsSnapshot {
        let endpoint = "metrics"
        if let cached: MetricsSnapshot = try cachedSnapshot(endpoint: endpoint, range: range),
           CachePolicy.isFresh(lastSyncDate: try snapshotDate(endpoint: endpoint, range: range), interval: range)
        {
            return cached
        }

        do {
            let client = makeClient()
            let data = try await client.get(path: "api/metrics", query: queryItems(for: range))
            let value = try DashboardAPIParser.parseMetrics(data: data)
            try storeSnapshot(value, endpoint: endpoint, range: range)
            return value
        } catch {
            if let cached: MetricsSnapshot = try cachedSnapshot(endpoint: endpoint, range: range) {
                return cached
            }
            throw error
        }
    }

    func loadTripAnalytics(range: DateInterval) async throws -> TripAnalyticsSnapshot {
        let endpoint = "trip-analytics"
        if let cached: TripAnalyticsSnapshot = try cachedSnapshot(endpoint: endpoint, range: range),
           CachePolicy.isFresh(lastSyncDate: try snapshotDate(endpoint: endpoint, range: range), interval: range)
        {
            return cached
        }

        do {
            let client = makeClient()
            let data = try await client.get(path: "api/trip-analytics", query: queryItems(for: range))
            let value = try DashboardAPIParser.parseTripAnalytics(data: data)
            try storeSnapshot(value, endpoint: endpoint, range: range)
            return value
        } catch {
            if let cached: TripAnalyticsSnapshot = try cachedSnapshot(endpoint: endpoint, range: range) {
                return cached
            }
            throw error
        }
    }

    func loadDriverBehavior(range: DateInterval) async throws -> DriverBehaviorSnapshot {
        let endpoint = "driver-behavior"
        if let cached: DriverBehaviorSnapshot = try cachedSnapshot(endpoint: endpoint, range: range),
           CachePolicy.isFresh(lastSyncDate: try snapshotDate(endpoint: endpoint, range: range), interval: range)
        {
            return cached
        }

        do {
            let client = makeClient()
            let data = try await client.get(path: "api/driver-behavior", query: queryItems(for: range))
            let value = try DashboardAPIParser.parseDriverBehavior(data: data)
            try storeSnapshot(value, endpoint: endpoint, range: range)
            return value
        } catch {
            if let cached: DriverBehaviorSnapshot = try cachedSnapshot(endpoint: endpoint, range: range) {
                return cached
            }
            throw error
        }
    }

    private func makeClient() -> APIClient {
        let baseURL = AppSettingsStore.shared.apiBaseURL
        return APIClient(baseURL: baseURL)
    }

    private func queryItems(for range: DateInterval) -> [URLQueryItem] {
        [
            URLQueryItem(name: "start_date", value: dateFormatter.string(from: range.start)),
            URLQueryItem(name: "end_date", value: dateFormatter.string(from: range.end))
        ]
    }

    private func snapshotKey(endpoint: String, range: DateInterval) -> String {
        "\(endpoint)|\(Int(range.start.timeIntervalSince1970))|\(Int(range.end.timeIntervalSince1970))|all"
    }

    private func snapshotDate(endpoint: String, range: DateInterval) throws -> Date? {
        let context = ModelContext(container)
        let key = snapshotKey(endpoint: endpoint, range: range)
        let descriptor = FetchDescriptor<CachedDashboardSnapshot>(
            predicate: #Predicate { $0.key == key }
        )
        return try context.fetch(descriptor).first?.updatedAt
    }

    private func cachedSnapshot<T: Decodable>(endpoint: String, range: DateInterval) throws -> T? {
        let context = ModelContext(container)
        let key = snapshotKey(endpoint: endpoint, range: range)
        let descriptor = FetchDescriptor<CachedDashboardSnapshot>(
            predicate: #Predicate { $0.key == key }
        )

        guard let row = try context.fetch(descriptor).first else { return nil }
        return try? JSONDecoder().decode(T.self, from: row.payloadData)
    }

    private func storeSnapshot<T: Encodable>(_ value: T, endpoint: String, range: DateInterval) throws {
        let context = ModelContext(container)
        let key = snapshotKey(endpoint: endpoint, range: range)
        let descriptor = FetchDescriptor<CachedDashboardSnapshot>(
            predicate: #Predicate { $0.key == key }
        )

        let payload = try JSONEncoder().encode(value)

        if let existing = try context.fetch(descriptor).first {
            existing.payloadData = payload
            existing.updatedAt = .now
        } else {
            context.insert(
                CachedDashboardSnapshot(
                    key: key,
                    endpoint: endpoint,
                    startDate: range.start,
                    endDate: range.end,
                    imei: nil,
                    payloadData: payload,
                    updatedAt: .now
                )
            )
        }

        try context.save()
    }
}
