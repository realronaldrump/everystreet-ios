import Foundation
import Observation

enum SessionState: Equatable {
    case checking
    case unauthenticated
    case authenticated
}

@MainActor
@Observable
final class AppModel {
    private let settings: AppSettingsStore
    private let tripsRepository: TripsRepository
    @ObservationIgnored private let authRepository: AuthRepository
    @ObservationIgnored private var unauthorizedNotificationTask: Task<Void, Never>?

    var selectedPreset: DateRangePreset
    var customDateRange: DateInterval
    var firstTripDate: Date?

    var sessionState: SessionState = .checking
    var sessionMessage: String?
    var isBootstrapping = false
    var isAuthenticating = false
    var bootstrapErrorMessage: String?

    var syncState: SyncState = .idle
    var lastUpdated: Date?

    init(
        tripsRepository: TripsRepository,
        authRepository: AuthRepository,
        settings: AppSettingsStore = .shared
    ) {
        self.tripsRepository = tripsRepository
        self.authRepository = authRepository
        self.settings = settings

        selectedPreset = settings.selectedPreset
        let now = Date()
        let savedStart = settings.customStartDate ?? Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let savedEnd = settings.customEndDate ?? now
        customDateRange = DateInterval(start: min(savedStart, savedEnd), end: max(savedStart, savedEnd))

        unauthorizedNotificationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .apiClientUnauthorized) {
                await MainActor.run {
                    self?.transitionToUnauthenticated(message: "Your session expired. Sign in again.")
                }
            }
        }
    }

    deinit {
        unauthorizedNotificationTask?.cancel()
    }

    var activeDateRange: DateInterval {
        if selectedPreset == .custom {
            return customDateRange
        }
        return selectedPreset.dateInterval(firstTripDate: firstTripDate)
    }

    var activeQuery: TripQuery {
        TripQuery(dateRange: activeDateRange, imei: nil, source: .rawTripsOnly)
    }

    var isAuthenticated: Bool {
        sessionState == .authenticated
    }

    func bootstrap() async {
        guard !isBootstrapping else { return }
        isBootstrapping = true
        bootstrapErrorMessage = nil
        sessionMessage = nil

        if sessionState != .authenticated {
            sessionState = .checking
        }

        do {
            let hasSession = try await authRepository.hasActiveSession()
            guard hasSession else {
                transitionToUnauthenticated(message: "Sign in with the owner password to access Every Street.")
                isBootstrapping = false
                return
            }

            sessionState = .authenticated
            await refreshBootstrapState()
        } catch {
            bootstrapErrorMessage = error.localizedDescription
            sessionMessage = error.localizedDescription
            sessionState = .unauthenticated
            syncState = .failed(message: error.localizedDescription)
        }

        isBootstrapping = false
    }

    func signIn(password: String) async {
        guard !isAuthenticating else { return }

        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPassword.isEmpty else {
            sessionMessage = "Enter the owner password."
            return
        }

        isAuthenticating = true
        sessionMessage = nil
        bootstrapErrorMessage = nil

        do {
            try await authRepository.login(password: trimmedPassword)
            sessionState = .authenticated
            await refreshBootstrapState()
        } catch {
            transitionToUnauthenticated(message: error.localizedDescription)
        }

        isAuthenticating = false
    }

    func clearSession() {
        authRepository.clearSession()
        transitionToUnauthenticated(message: "Saved session cleared.")
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

    private func refreshBootstrapState() async {
        do {
            firstTripDate = try await tripsRepository.firstTripDate()
            lastUpdated = await tripsRepository.lastSyncDate(for: activeQuery)
            syncState = .idle
            bootstrapErrorMessage = nil
            sessionMessage = nil
        } catch let error as APIError where error.isUnauthorized {
            transitionToUnauthenticated(message: "Your session expired. Sign in again.")
        } catch {
            bootstrapErrorMessage = error.localizedDescription
            syncState = .failed(message: error.localizedDescription)
        }
    }

    private func transitionToUnauthenticated(message: String?) {
        sessionState = .unauthenticated
        firstTripDate = nil
        lastUpdated = nil
        bootstrapErrorMessage = nil
        sessionMessage = message
        syncState = .idle
    }
}
