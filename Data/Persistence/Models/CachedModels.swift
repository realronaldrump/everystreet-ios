import Foundation
import SwiftData

@Model
final class CachedTripRecord {
    @Attribute(.unique) var transactionId: String

    var imei: String
    var vin: String?
    var vehicleLabel: String?
    var startTime: Date
    var endTime: Date?
    var distance: Double?
    var duration: Double?
    var maxSpeed: Double?
    var totalIdleDuration: Double?
    var fuelConsumed: Double?
    var estimatedCost: Double?
    var startLocation: String?
    var destination: String?
    var status: String?
    var previewPath: String?

    var minLat: Double?
    var maxLat: Double?
    var minLon: Double?
    var maxLon: Double?

    @Attribute(.externalStorage) var fullGeometryData: Data?
    @Attribute(.externalStorage) var mediumGeometryData: Data?
    @Attribute(.externalStorage) var lowGeometryData: Data?

    var updatedAt: Date

    init(
        transactionId: String,
        imei: String,
        vin: String?,
        vehicleLabel: String?,
        startTime: Date,
        endTime: Date?,
        distance: Double?,
        duration: Double?,
        maxSpeed: Double?,
        totalIdleDuration: Double?,
        fuelConsumed: Double?,
        estimatedCost: Double?,
        startLocation: String?,
        destination: String?,
        status: String?,
        previewPath: String?,
        minLat: Double?,
        maxLat: Double?,
        minLon: Double?,
        maxLon: Double?,
        fullGeometryData: Data?,
        mediumGeometryData: Data?,
        lowGeometryData: Data?,
        updatedAt: Date
    ) {
        self.transactionId = transactionId
        self.imei = imei
        self.vin = vin
        self.vehicleLabel = vehicleLabel
        self.startTime = startTime
        self.endTime = endTime
        self.distance = distance
        self.duration = duration
        self.maxSpeed = maxSpeed
        self.totalIdleDuration = totalIdleDuration
        self.fuelConsumed = fuelConsumed
        self.estimatedCost = estimatedCost
        self.startLocation = startLocation
        self.destination = destination
        self.status = status
        self.previewPath = previewPath
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLon = minLon
        self.maxLon = maxLon
        self.fullGeometryData = fullGeometryData
        self.mediumGeometryData = mediumGeometryData
        self.lowGeometryData = lowGeometryData
        self.updatedAt = updatedAt
    }
}

@Model
final class CachedVehicleRecord {
    @Attribute(.unique) var imei: String

    var vin: String?
    var customName: String?
    var nickName: String?
    var make: String?
    var model: String?
    var year: Int?
    var isActive: Bool
    var updatedAt: Date

    init(
        imei: String,
        vin: String?,
        customName: String?,
        nickName: String?,
        make: String?,
        model: String?,
        year: Int?,
        isActive: Bool,
        updatedAt: Date
    ) {
        self.imei = imei
        self.vin = vin
        self.customName = customName
        self.nickName = nickName
        self.make = make
        self.model = model
        self.year = year
        self.isActive = isActive
        self.updatedAt = updatedAt
    }
}

@Model
final class CachedWindowRecord {
    @Attribute(.unique) var key: String
    var startDate: Date
    var endDate: Date
    var imei: String?
    var recordCount: Int
    var lastSyncedAt: Date

    init(key: String, startDate: Date, endDate: Date, imei: String?, recordCount: Int, lastSyncedAt: Date) {
        self.key = key
        self.startDate = startDate
        self.endDate = endDate
        self.imei = imei
        self.recordCount = recordCount
        self.lastSyncedAt = lastSyncedAt
    }
}

@Model
final class CachedDashboardSnapshot {
    @Attribute(.unique) var key: String
    var endpoint: String
    var startDate: Date
    var endDate: Date
    var imei: String?
    @Attribute(.externalStorage) var payloadData: Data
    var updatedAt: Date

    init(key: String, endpoint: String, startDate: Date, endDate: Date, imei: String?, payloadData: Data, updatedAt: Date) {
        self.key = key
        self.endpoint = endpoint
        self.startDate = startDate
        self.endDate = endDate
        self.imei = imei
        self.payloadData = payloadData
        self.updatedAt = updatedAt
    }
}
