import SwiftUI

struct SettingsView: View {
    @Bindable var appModel: AppModel
    @State private var viewModel: SettingsViewModel
    private let placesRepository: PlacesRepository

    init(appModel: AppModel, tripsRepository: TripsRepository, settingsRepository: SettingsRepository, placesRepository: PlacesRepository) {
        _appModel = Bindable(appModel)
        _viewModel = State(initialValue: SettingsViewModel(tripsRepository: tripsRepository, settingsRepository: settingsRepository))
        self.placesRepository = placesRepository
    }

    var body: some View {
        ZStack {
            LinearGradient.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppTheme.spacingLG) {
                    // Quick links
                    quickLinksSection

                    apiSection
                    cacheSection
                    healthSection

                    if let status = viewModel.statusMessage {
                        statusBanner(status)
                    }
                }
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.bottom, AppTheme.spacingXXL)
            }
        }
        .navigationTitle("More")
        .task {
            if viewModel.cacheStats == nil {
                await viewModel.load()
            }
        }
    }

    // MARK: - Quick Links (Places moved here)

    private var quickLinksSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
            NavigationLink {
                PlacesTabView(appModel: appModel, repository: placesRepository)
            } label: {
                HStack(spacing: AppTheme.spacingMD) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.accentWarm)
                        .frame(width: 32, height: 32)
                        .background(AppTheme.accentWarmMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Places")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("Frequent destinations & visit history")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
        .glassCard()
    }

    // MARK: - API Section

    private var apiSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
            SectionHeaderView("API Endpoint", icon: "link")

            VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                Text("BASE URL")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .tracking(0.8)

                TextField("https://www.everystreet.me", text: $viewModel.apiBaseURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline.monospaced())
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(AppTheme.spacingMD)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous)
                                    .stroke(AppTheme.border, lineWidth: 0.5)
                            )
                    )
            }

            Button("Save URL") {
                viewModel.saveBaseURL()
            }
            .buttonStyle(.accent)
            .sensoryFeedback(.success, trigger: viewModel.statusMessage)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Cache Section

    private var cacheSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
            SectionHeaderView("Cache", icon: "internaldrive")

            if let stats = viewModel.cacheStats {
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: AppTheme.spacingSM) {
                    cacheStatRow(label: "Trips", value: "\(stats.tripCount)", icon: "road.lanes")
                    cacheStatRow(label: "Windows", value: "\(stats.windowCount)", icon: "calendar")
                    cacheStatRow(label: "Vehicles", value: "\(stats.vehicleCount)", icon: "car.fill")
                    cacheStatRow(label: "Storage", value: ByteCountFormatter.string(fromByteCount: stats.estimatedBytes, countStyle: .file), icon: "externaldrive.fill")
                }
            } else {
                Text("No cache data available")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Button(role: .destructive) {
                Task { await viewModel.clearCache() }
            } label: {
                HStack(spacing: AppTheme.spacingSM) {
                    Image(systemName: "trash")
                        .font(.caption.weight(.semibold))
                    Text("Clear Cache")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(AppTheme.error)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.spacingMD)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                        .fill(AppTheme.error.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                                .stroke(AppTheme.error.opacity(0.25), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Health Section

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
            HStack {
                SectionHeaderView("Server Health", icon: "server.rack")
                Spacer()
                Button {
                    Task { await viewModel.refreshHealth() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 30, height: 30)
                        .background(AppTheme.accentMuted, in: Circle())
                }
                .buttonStyle(.pressable)
            }

            if let health = viewModel.health {
                HStack(spacing: AppTheme.spacingMD) {
                    // Status indicator
                    Circle()
                        .fill(health.isHealthy ? AppTheme.success : AppTheme.warning)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .fill(health.isHealthy ? AppTheme.success : AppTheme.warning)
                                .frame(width: 10, height: 10)
                                .blur(radius: 4)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(health.overallStatus.capitalized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(health.isHealthy ? AppTheme.success : AppTheme.warning)

                        Text(health.message)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .padding(AppTheme.spacingMD)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                        .fill((health.isHealthy ? AppTheme.success : AppTheme.warning).opacity(0.06))
                )

                if let updated = health.lastUpdated {
                    Text("Last checked \(updated.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            } else {
                HStack(spacing: AppTheme.spacingSM) {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(AppTheme.textTertiary)
                    Text("Health data unavailable")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Helpers

    private func cacheStatRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: AppTheme.spacingSM) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 22, height: 22)
                .background(AppTheme.accentMuted, in: RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.3)
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spacingMD)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous))
    }

    private func statusBanner(_ message: String) -> some View {
        HStack(spacing: AppTheme.spacingSM) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(AppTheme.accent)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: AppTheme.spacingMD)
    }
}
