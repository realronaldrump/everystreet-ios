import Charts
import SwiftUI

struct InsightsTabView: View {
    @Bindable var appModel: AppModel
    @State private var viewModel: InsightsViewModel

    init(appModel: AppModel, repository: DashboardRepository) {
        _appModel = Bindable(appModel)
        _viewModel = State(initialValue: InsightsViewModel(repository: repository))
    }

    var body: some View {
        ZStack {
            LinearGradient.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    GlobalFilterBar(appModel: appModel) {
                        Task { await viewModel.load(range: appModel.activeDateRange) }
                    }

                    if let metrics = viewModel.metrics {
                        metricsSection(metrics)
                    }

                    if let analytics = viewModel.analytics {
                        weekdayChart(analytics)
                        hourlyChart(analytics)
                        dailyDistanceChart(analytics)
                    }

                    if let behavior = viewModel.behavior {
                        behaviorSection(behavior)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()
                    }
                }
                .padding(12)
            }

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(AppTheme.accent)
            }
        }
        .navigationTitle("Insights")
        .task {
            if viewModel.metrics == nil {
                await viewModel.load(range: appModel.activeDateRange)
            }
        }
    }

    private func metricsSection(_ metrics: MetricsSnapshot) -> some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
            metricCard("Total Trips", value: "\(metrics.totalTrips)")
            metricCard("Total Distance", value: String(format: "%.1f mi", metrics.totalDistance))
            metricCard("Avg Speed", value: String(format: "%.1f mph", metrics.avgSpeed))
            metricCard("Max Speed", value: String(format: "%.1f mph", metrics.maxSpeed))
        }
    }

    private func weekdayChart(_ analytics: TripAnalyticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekday Distribution")
                .font(.headline)

            Chart(analytics.weekdayDistribution) { point in
                BarMark(
                    x: .value("Day", point.label),
                    y: .value("Trips", point.count)
                )
                .foregroundStyle(AppTheme.accent)
                .cornerRadius(4)
            }
            .frame(height: 180)
        }
        .glassCard()
    }

    private func hourlyChart(_ analytics: TripAnalyticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hourly Distribution")
                .font(.headline)

            Chart(analytics.timeDistribution) { point in
                LineMark(
                    x: .value("Hour", point.label),
                    y: .value("Trips", point.count)
                )
                .foregroundStyle(AppTheme.accentWarm)

                AreaMark(
                    x: .value("Hour", point.label),
                    y: .value("Trips", point.count)
                )
                .foregroundStyle(AppTheme.accentWarm.opacity(0.2))
            }
            .frame(height: 180)
        }
        .glassCard()
    }

    private func dailyDistanceChart(_ analytics: TripAnalyticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Distance")
                .font(.headline)

            Chart(analytics.dailyDistances.prefix(30)) { point in
                BarMark(
                    x: .value("Date", point.label),
                    y: .value("Miles", point.value)
                )
                .foregroundStyle(AppTheme.routeRecent)
            }
            .frame(height: 180)
        }
        .glassCard()
    }

    private func behaviorSection(_ behavior: DriverBehaviorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Driver Behavior")
                .font(.headline)

            HStack(spacing: 8) {
                metricPill("Hard Braking", value: "\(behavior.hardBrakingCount ?? 0)")
                metricPill("Hard Accel", value: "\(behavior.hardAccelerationCount ?? 0)")
                metricPill("Idle", value: formatMinutes(behavior.totalIdleDuration))
            }

            if !behavior.monthlySeries.isEmpty {
                Chart(behavior.monthlySeries) { point in
                    LineMark(
                        x: .value("Month", point.label),
                        y: .value("Distance", point.value)
                    )
                    .foregroundStyle(AppTheme.routeOld)
                }
                .frame(height: 160)
            }
        }
        .glassCard()
    }

    private func metricCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func metricPill(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    private func formatMinutes(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value / 60))m"
    }
}
