import SwiftUI

struct SettingsView: View {
    @Bindable var appModel: AppModel
    @State private var viewModel: SettingsViewModel

    init(appModel: AppModel, tripsRepository: TripsRepository, settingsRepository: SettingsRepository) {
        _appModel = Bindable(appModel)
        _viewModel = State(initialValue: SettingsViewModel(tripsRepository: tripsRepository, settingsRepository: settingsRepository))
    }

    var body: some View {
        ZStack {
            LinearGradient.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    apiSection
                    cacheSection
                    healthSection

                    if let status = viewModel.statusMessage {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()
                    }
                }
                .padding(12)
            }
        }
        .navigationTitle("Settings")
        .task {
            if viewModel.cacheStats == nil {
                await viewModel.load()
            }
        }
    }

    private var apiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API Base URL")
                .font(.headline)

            TextField("https://www.everystreet.me", text: $viewModel.apiBaseURLText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button("Save URL") {
                viewModel.saveBaseURL()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var cacheSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cache")
                .font(.headline)

            if let stats = viewModel.cacheStats {
                Text("Trips: \(stats.tripCount)")
                Text("Windows: \(stats.windowCount)")
                Text("Vehicles: \(stats.vehicleCount)")
                Text("Storage: \(ByteCountFormatter.string(fromByteCount: stats.estimatedBytes, countStyle: .file))")
            } else {
                Text("No cache stats yet")
            }

            Button("Clear Cache", role: .destructive) {
                Task { await viewModel.clearCache() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Server Health")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    Task { await viewModel.refreshHealth() }
                }
            }

            if let health = viewModel.health {
                HStack {
                    Circle()
                        .fill(health.isHealthy ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(health.overallStatus.capitalized)
                }

                Text(health.message)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)

                if let updated = health.lastUpdated {
                    Text("Updated \(updated.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            } else {
                Text("Health data unavailable")
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
