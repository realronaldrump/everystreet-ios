import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private let settings: AppSettingsStore
    private let tripsRepository: TripsRepository

    var selectedPreset: DateRangePreset
    var customDateRange: DateInterval
    var selectedIMEI: String?

    var vehicles: [Vehicle] = []
    var firstTripDate: Date?

    var isBootstrapping = false
    var bootstrapErrorMessage: String?

    var syncState: SyncState = .idle
    var lastUpdated: Date?

    init(tripsRepository: TripsRepository, settings: AppSettingsStore = .shared) {
        self.tripsRepository = tripsRepository
        self.settings = settings

        selectedPreset = settings.selectedPreset
        let now = Date()
        let savedStart = settings.customStartDate ?? Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let savedEnd = settings.customEndDate ?? now
        customDateRange = DateInterval(start: min(savedStart, savedEnd), end: max(savedStart, savedEnd))
        selectedIMEI = settings.selectedIMEI
    }

    var activeDateRange: DateInterval {
        if selectedPreset == .custom {
            return customDateRange
        }
        return selectedPreset.dateInterval(firstTripDate: firstTripDate)
    }

    var activeQuery: TripQuery {
        TripQuery(dateRange: activeDateRange, imei: selectedIMEI, source: .rawTripsOnly)
    }

    func bootstrap() async {
        guard !isBootstrapping else { return }
        isBootstrapping = true
        bootstrapErrorMessage = nil

        do {
            vehicles = try await tripsRepository.loadVehicles(forceRefresh: false)
            firstTripDate = try await tripsRepository.firstTripDate()
            lastUpdated = await tripsRepository.lastSyncDate(for: activeQuery)
            syncState = .idle
        } catch {
            bootstrapErrorMessage = error.localizedDescription
            syncState = .failed(message: error.localizedDescription)
        }

        isBootstrapping = false
    }

    func refreshVehicleList() async {
        do {
            vehicles = try await tripsRepository.loadVehicles(forceRefresh: true)
        } catch {
            bootstrapErrorMessage = error.localizedDescription
        }
    }

    func setPreset(_ preset: DateRangePreset) {
        selectedPreset = preset
        settings.selectedPreset = preset
    }

    func setCustomRange(start: Date, end: Date) {
        customDateRange = DateInterval(start: min(start, end), end: max(start, end))
        settings.customStartDate = customDateRange.start
        settings.customEndDate = customDateRange.end
        selectedPreset = .custom
        settings.selectedPreset = .custom
    }

    func setSelectedVehicle(_ imei: String?) {
        selectedIMEI = imei
        settings.selectedIMEI = imei
    }

    func markSyncStarted() {
        syncState = .syncing
    }

    func markSyncFinished(at date: Date = .now) {
        syncState = .idle
        lastUpdated = date
    }

    func markSyncStale() {
        syncState = .stale(lastUpdated: lastUpdated)
    }

    func markSyncFailure(_ message: String) {
        syncState = .failed(message: message)
    }
}
