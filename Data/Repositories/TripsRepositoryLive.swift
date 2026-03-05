import Foundation
import SwiftData

@MainActor
final class TripsRepositoryLive: TripsRepository {
    private let container: ModelContainer
    private let dateFormatter: DateFormatter
    private let mapBundleCache = MapBundleCacheStore()

    init(container: ModelContainer) {
        self.container = container
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        self.dateFormatter = formatter
    }

    func loadTrips(query: TripQuery) async throws -> [TripSummary] {
        let cached = try cachedTrips(query: query)
        let lastSync = await lastSyncDate(for: query)

        if !cached.isEmpty {
            if !CachePolicy.isFresh(lastSyncDate: lastSync, interval: query.dateRange) {
                Task {
                    do {
                        _ = try await self.refresh(query: query)
                    } catch {
                        AppLogger.repository.error("Background refresh failed: \(error.localizedDescription)")
                    }
                }
            }
            return cached
        }

        return try await refresh(query: query)
    }

    func loadTripDetail(id: String) async throws -> TripDetail {
        let client = makeClient()
        let data = try await TaskRetry.run {
            try await client.get(path: "api/trips/\(id)")
        }
        return try TripAPIParser.parseTripDetail(data: data)
    }

    func loadTripMapBundle(query: TripQuery) async throws -> TripMapBundle {
        if query.isCoverageClipped {
            return try await loadTripMapBundleFromGeoJSON(query: query)
        }

        let client = makeClient()
        let queryItems = mapBundleQueryItems(for: query)

        let cacheKey = "trip-map-bundle|\(query.cacheKey)"
        let cached = mapBundleCache.load(key: cacheKey)
        var headers: [String: String] = [:]
        if let cached {
            headers["If-None-Match"] = cached.etag
        }

        let payload = try await TaskRetry.run {
            try await client.get(
                path: "api/map/trips/bundle",
                query: queryItems,
                headers: headers,
                allowNotModified: true
            )
        }

        if payload.statusCode == 304, let cached {
            return try TripAPIParser.parseTripMapBundle(data: cached.payload)
        }

        let data = payload.data
        if let etag = payload.headerValue("ETag"), !etag.isEmpty {
            mapBundleCache.store(key: cacheKey, payload: data, etag: etag)
        }
        return try TripAPIParser.parseTripMapBundle(data: data)
    }

    func prefetch(range: DateInterval) async {
        let query = TripQuery(dateRange: range, imei: nil, source: .rawTripsOnly)
        do {
            _ = try await refresh(query: query)
        } catch {
            AppLogger.repository.error("Prefetch failed: \(error.localizedDescription)")
        }
    }

    func refresh(query: TripQuery) async throws -> [TripSummary] {
        let windows = query.dateRange.isLargeWindow ? query.dateRange.monthlyWindows() : [query.dateRange]
        var mergedByID: [String: TripSummary] = [:]

        for window in windows {
            let remote = try await remoteTrips(for: window, imei: query.imei)
            try store(trips: remote)
            try storeWindow(window: window, imei: query.imei, count: remote.count)
            for trip in remote {
                mergedByID[trip.transactionId] = trip
            }
        }

        let merged = Array(mergedByID.values).sorted { $0.startTime > $1.startTime }

        if merged.isEmpty {
            return try cachedTrips(query: query)
        }

        return merged
    }

    func loadVehicles(forceRefresh: Bool) async throws -> [Vehicle] {
        let cached = try cachedVehicles()
        if !forceRefresh, !cached.isEmpty {
            return cached
        }

        let client = makeClient()
        let data = try await TaskRetry.run {
            try await client.get(path: "api/vehicles", query: [URLQueryItem(name: "active_only", value: "true")])
        }
        let vehicles = try AppAPIParser.parseVehicles(data: data)
        try store(vehicles: vehicles)
        return vehicles
    }

    func firstTripDate() async throws -> Date? {
        let client = makeClient()
        let data = try await TaskRetry.run {
            try await client.get(path: "api/first_trip_date")
        }
        return try AppAPIParser.parseFirstTripDate(data: data)
    }

    func lastSyncDate(for query: TripQuery) async -> Date? {
        do {
            let context = ModelContext(container)
            let windows = query.dateRange.isLargeWindow ? query.dateRange.monthlyWindows() : [query.dateRange]
            var dates: [Date] = []
            for window in windows {
                let key = windowKey(for: window, imei: query.imei)
                let descriptor = FetchDescriptor<CachedWindowRecord>(
                    predicate: #Predicate { $0.key == key }
                )
                if let record = try context.fetch(descriptor).first {
                    dates.append(record.lastSyncedAt)
                }
            }
            return dates.min()
        } catch {
            AppLogger.cache.error("lastSyncDate failed: \(error.localizedDescription)")
            return nil
        }
    }

    func cacheStats() async -> TripCacheStats {
        do {
            let context = ModelContext(container)
            let tripCount = try context.fetchCount(FetchDescriptor<CachedTripRecord>())
            let vehicleCount = try context.fetchCount(FetchDescriptor<CachedVehicleRecord>())
            let windowCount = try context.fetchCount(FetchDescriptor<CachedWindowRecord>())

            let trips = try context.fetch(FetchDescriptor<CachedTripRecord>())
            let byteEstimate = trips.reduce(into: Int64(0)) { partialResult, trip in
                partialResult += Int64(trip.fullGeometryData?.count ?? 0)
                partialResult += Int64(trip.mediumGeometryData?.count ?? 0)
                partialResult += Int64(trip.lowGeometryData?.count ?? 0)
                partialResult += 256
            }

            return TripCacheStats(
                tripCount: tripCount,
                windowCount: windowCount,
                vehicleCount: vehicleCount,
                estimatedBytes: byteEstimate
            )
        } catch {
            AppLogger.cache.error("cacheStats failed: \(error.localizedDescription)")
            return TripCacheStats(tripCount: 0, windowCount: 0, vehicleCount: 0, estimatedBytes: 0)
        }
    }

    func clearCache() async throws {
        let context = ModelContext(container)
        for item in try context.fetch(FetchDescriptor<CachedTripRecord>()) {
            context.delete(item)
        }
        for item in try context.fetch(FetchDescriptor<CachedVehicleRecord>()) {
            context.delete(item)
        }
        for item in try context.fetch(FetchDescriptor<CachedWindowRecord>()) {
            context.delete(item)
        }
        try context.save()
    }

    private func makeClient() -> APIClient {
        let baseURL = AppSettingsStore.shared.apiBaseURL
        return APIClient(baseURL: baseURL)
    }

    private func loadTripMapBundleFromGeoJSON(query: TripQuery) async throws -> TripMapBundle {
        let client = makeClient()
        let data = try await TaskRetry.run {
            try await client.get(path: "api/trips", query: self.tripsQueryItems(for: query))
        }

        let summaries = try TripAPIParser.parseTripFeatureCollection(data: data)
        return TripAPIParser.buildTripMapBundle(from: summaries, query: query)
    }

    private func remoteTrips(for interval: DateInterval, imei: String?) async throws -> [TripSummary] {
        let client = makeClient()
        var queryItems = [
            URLQueryItem(name: "start_date", value: dateFormatter.string(from: interval.start)),
            URLQueryItem(name: "end_date", value: dateFormatter.string(from: interval.end))
        ]

        if let imei, !imei.isEmpty {
            queryItems.append(URLQueryItem(name: "imei", value: imei))
        }

        let data = try await TaskRetry.run {
            try await client.get(path: "api/trips", query: queryItems)
        }

        do {
            return try TripAPIParser.parseTripFeatureCollection(data: data)
        } catch {
            AppLogger.network.error("Trip decoding failed. context=\(error.localizedDescription)")
            throw error
        }
    }

    private func mapBundleQueryItems(for query: TripQuery) -> [URLQueryItem] {
        var queryItems = [
            URLQueryItem(name: "start_date", value: dateFormatter.string(from: query.dateRange.start)),
            URLQueryItem(name: "end_date", value: dateFormatter.string(from: query.dateRange.end))
        ]

        if let imei = query.imei, !imei.isEmpty {
            queryItems.append(URLQueryItem(name: "imei", value: imei))
        }

        return queryItems
    }

    private func tripsQueryItems(for query: TripQuery) -> [URLQueryItem] {
        var queryItems = mapBundleQueryItems(for: query)

        if query.isCoverageClipped, let areaID = query.coverageAreaID {
            queryItems.append(URLQueryItem(name: "clip_to_coverage", value: "true"))
            queryItems.append(URLQueryItem(name: "coverage_area_id", value: areaID))
        }

        return queryItems
    }

    private func cachedTrips(query: TripQuery) throws -> [TripSummary] {
        let context = ModelContext(container)
        let start = query.dateRange.start
        let end = query.dateRange.end
        let imei = query.imei

        let descriptor = FetchDescriptor<CachedTripRecord>(
            predicate: #Predicate<CachedTripRecord> { trip in
                trip.startTime >= start && trip.startTime <= end
            },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )

        let rows = try context.fetch(descriptor)
        let filtered = rows.filter { row in
            guard let imei else { return true }
            return row.imei == imei
        }

        return filtered.map(map(record:))
    }

    private func cachedVehicles() throws -> [Vehicle] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<CachedVehicleRecord>(sortBy: [SortDescriptor(\.customName, order: .forward)])
        let rows = try context.fetch(descriptor)

        return rows.map {
            Vehicle(
                imei: $0.imei,
                vin: $0.vin,
                customName: $0.customName,
                nickName: $0.nickName,
                make: $0.make,
                model: $0.model,
                year: $0.year,
                isActive: $0.isActive
            )
        }
    }

    private func store(trips: [TripSummary]) throws {
        let context = ModelContext(container)
        for trip in trips {
            let transactionId = trip.transactionId
            let existingDescriptor = FetchDescriptor<CachedTripRecord>(
                predicate: #Predicate { $0.transactionId == transactionId }
            )
            let existing = try context.fetch(existingDescriptor).first

            let bbox = trip.boundingBox
            let full = CoordinateCoding.encode(trip.fullGeometry)
            let medium = CoordinateCoding.encode(trip.mediumGeometry)
            let low = CoordinateCoding.encode(trip.lowGeometry)

            if let existing {
                existing.imei = trip.imei
                existing.vin = trip.vin
                existing.vehicleLabel = trip.vehicleLabel
                existing.startTime = trip.startTime
                existing.endTime = trip.endTime
                existing.distance = trip.distance
                existing.duration = trip.duration
                existing.maxSpeed = trip.maxSpeed
                existing.totalIdleDuration = trip.totalIdleDuration
                existing.fuelConsumed = trip.fuelConsumed
                existing.estimatedCost = trip.estimatedCost
                existing.startLocation = trip.startLocation
                existing.destination = trip.destination
                existing.status = trip.status
                existing.previewPath = trip.previewPath
                existing.minLat = bbox?.minLat
                existing.maxLat = bbox?.maxLat
                existing.minLon = bbox?.minLon
                existing.maxLon = bbox?.maxLon
                existing.fullGeometryData = full
                existing.mediumGeometryData = medium
                existing.lowGeometryData = low
                existing.updatedAt = .now
            } else {
                let row = CachedTripRecord(
                    transactionId: trip.transactionId,
                    imei: trip.imei,
                    vin: trip.vin,
                    vehicleLabel: trip.vehicleLabel,
                    startTime: trip.startTime,
                    endTime: trip.endTime,
                    distance: trip.distance,
                    duration: trip.duration,
                    maxSpeed: trip.maxSpeed,
                    totalIdleDuration: trip.totalIdleDuration,
                    fuelConsumed: trip.fuelConsumed,
                    estimatedCost: trip.estimatedCost,
                    startLocation: trip.startLocation,
                    destination: trip.destination,
                    status: trip.status,
                    previewPath: trip.previewPath,
                    minLat: bbox?.minLat,
                    maxLat: bbox?.maxLat,
                    minLon: bbox?.minLon,
                    maxLon: bbox?.maxLon,
                    fullGeometryData: full,
                    mediumGeometryData: medium,
                    lowGeometryData: low,
                    updatedAt: .now
                )
                context.insert(row)
            }
        }
        try context.save()
    }

    private func store(vehicles: [Vehicle]) throws {
        let context = ModelContext(container)
        for vehicle in vehicles {
            let imei = vehicle.imei
            let descriptor = FetchDescriptor<CachedVehicleRecord>(
                predicate: #Predicate { $0.imei == imei }
            )
            if let existing = try context.fetch(descriptor).first {
                existing.vin = vehicle.vin
                existing.customName = vehicle.customName
                existing.nickName = vehicle.nickName
                existing.make = vehicle.make
                existing.model = vehicle.model
                existing.year = vehicle.year
                existing.isActive = vehicle.isActive
                existing.updatedAt = .now
            } else {
                context.insert(
                    CachedVehicleRecord(
                        imei: vehicle.imei,
                        vin: vehicle.vin,
                        customName: vehicle.customName,
                        nickName: vehicle.nickName,
                        make: vehicle.make,
                        model: vehicle.model,
                        year: vehicle.year,
                        isActive: vehicle.isActive,
                        updatedAt: .now
                    )
                )
            }
        }
        try context.save()
    }

    private func storeWindow(window: DateInterval, imei: String?, count: Int) throws {
        let context = ModelContext(container)
        let key = windowKey(for: window, imei: imei)
        let descriptor = FetchDescriptor<CachedWindowRecord>(
            predicate: #Predicate { $0.key == key }
        )

        if let existing = try context.fetch(descriptor).first {
            existing.recordCount = count
            existing.lastSyncedAt = .now
        } else {
            context.insert(
                CachedWindowRecord(
                    key: key,
                    startDate: window.start,
                    endDate: window.end,
                    imei: imei,
                    recordCount: count,
                    lastSyncedAt: .now
                )
            )
        }

        try context.save()
    }

    private func map(record: CachedTripRecord) -> TripSummary {
        let full = CoordinateCoding.decode(record.fullGeometryData)
        let medium = CoordinateCoding.decode(record.mediumGeometryData)
        let low = CoordinateCoding.decode(record.lowGeometryData)

        let bbox: TripBoundingBox?
        if let minLat = record.minLat,
           let maxLat = record.maxLat,
           let minLon = record.minLon,
           let maxLon = record.maxLon
        {
            bbox = TripBoundingBox(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
        } else {
            bbox = nil
        }

        return TripSummary(
            transactionId: record.transactionId,
            imei: record.imei,
            vin: record.vin,
            vehicleLabel: record.vehicleLabel,
            startTime: record.startTime,
            endTime: record.endTime,
            distance: record.distance,
            duration: record.duration,
            maxSpeed: record.maxSpeed,
            totalIdleDuration: record.totalIdleDuration,
            fuelConsumed: record.fuelConsumed,
            estimatedCost: record.estimatedCost,
            startLocation: record.startLocation,
            destination: record.destination,
            status: record.status,
            previewPath: record.previewPath,
            boundingBox: bbox,
            fullGeometry: full,
            mediumGeometry: medium,
            lowGeometry: low
        )
    }

    private func windowKey(for interval: DateInterval, imei: String?) -> String {
        "\(Int(interval.start.timeIntervalSince1970))_\(Int(interval.end.timeIntervalSince1970))_\(imei ?? "all")"
    }
}
