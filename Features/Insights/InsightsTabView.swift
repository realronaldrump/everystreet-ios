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
                VStack(spacing: AppTheme.spacingLG) {
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
                        errorBanner(error)
                    }
                }
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.bottom, AppTheme.spacingXXL)
            }

            if viewModel.isLoading && viewModel.metrics == nil {
                loadingOverlay
            }
        }
        .navigationTitle("Insights")
        .task {
            if viewModel.metrics == nil {
                await viewModel.load(range: appModel.activeDateRange)
            }
        }
    }

    // MARK: - Metrics Grid

    private func metricsSection(_ metrics: MetricsSnapshot) -> some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: AppTheme.spacingMD) {
            StatCardView(title: "Total Trips", value: "\(metrics.totalTrips)", icon: "road.lanes", color: AppTheme.statDistance)
            StatCardView(title: "Distance", value: String(format: "%.1f mi", metrics.totalDistance), icon: "point.topleft.down.to.point.bottomright.curvepath", color: AppTheme.statDuration)
            StatCardView(title: "Avg Speed", value: String(format: "%.1f mph", metrics.avgSpeed), icon: "gauge.medium", color: AppTheme.statSpeed)
            StatCardView(title: "Max Speed", value: String(format: "%.1f mph", metrics.maxSpeed), icon: "gauge.high", color: AppTheme.statMaxSpeed)
        }
    }

    // MARK: - Charts

    private func weekdayChart(_ analytics: TripAnalyticsSnapshot) -> some View {
        chartCard(title: "Weekday Distribution", icon: "calendar") {
            Chart(analytics.weekdayDistribution) { point in
                BarMark(
                    x: .value("Day", point.label),
                    y: .value("Trips", point.count)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.accent, AppTheme.accent.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(AppTheme.spacingXS)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(AppTheme.divider)
                    AxisValueLabel()
                        .foregroundStyle(AppTheme.textTertiary)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .foregroundStyle(AppTheme.textSecondary)
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .frame(height: 180)
        }
    }

    private func hourlyChart(_ analytics: TripAnalyticsSnapshot) -> some View {
        chartCard(title: "Hourly Distribution", icon: "clock") {
            Chart(analytics.timeDistribution) { point in
                AreaMark(
                    x: .value("Hour", point.label),
                    y: .value("Trips", point.count)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.accentWarm.opacity(0.3), AppTheme.accentWarm.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Hour", point.label),
                    y: .value("Trips", point.count)
                )
                .foregroundStyle(AppTheme.accentWarm)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(AppTheme.divider)
                    AxisValueLabel()
                        .foregroundStyle(AppTheme.textTertiary)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .foregroundStyle(AppTheme.textSecondary)
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .frame(height: 180)
        }
    }

    private func dailyDistanceChart(_ analytics: TripAnalyticsSnapshot) -> some View {
        chartCard(title: "Daily Distance", icon: "chart.bar.fill") {
            Chart(analytics.dailyDistances.prefix(30)) { point in
                BarMark(
                    x: .value("Date", point.label),
                    y: .value("Miles", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.routeRecent, AppTheme.routeRecent.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(2)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(AppTheme.divider)
                    AxisValueLabel()
                        .foregroundStyle(AppTheme.textTertiary)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel()
                        .foregroundStyle(AppTheme.textTertiary)
                        .font(.system(size: 9, weight: .medium))
                }
            }
            .frame(height: 180)
        }
    }

    // MARK: - Behavior Section

    private func behaviorSection(_ behavior: DriverBehaviorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingLG) {
            SectionHeaderView("Driver Behavior", icon: "steeringwheel")

            HStack(spacing: AppTheme.spacingSM) {
                behaviorStat(
                    title: "Hard Brake",
                    value: "\(behavior.hardBrakingCount ?? 0)",
                    icon: "exclamationmark.triangle.fill",
                    color: AppTheme.error
                )
                behaviorStat(
                    title: "Hard Accel",
                    value: "\(behavior.hardAccelerationCount ?? 0)",
                    icon: "bolt.fill",
                    color: AppTheme.accentWarm
                )
                behaviorStat(
                    title: "Idle",
                    value: formatMinutes(behavior.totalIdleDuration),
                    icon: "pause.circle.fill",
                    color: AppTheme.statIdle
                )
            }

            if !behavior.monthlySeries.isEmpty {
                Chart(behavior.monthlySeries) { point in
                    LineMark(
                        x: .value("Month", point.label),
                        y: .value("Distance", point.value)
                    )
                    .foregroundStyle(AppTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Month", point.label),
                        y: .value("Distance", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.accent.opacity(0.2), AppTheme.accent.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(AppTheme.divider)
                        AxisValueLabel()
                            .foregroundStyle(AppTheme.textTertiary)
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .foregroundStyle(AppTheme.textTertiary)
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .frame(height: 160)
            }
        }
        .glassCard()
    }

    // MARK: - Helpers

    private func chartCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
            SectionHeaderView(title, icon: icon)
            content()
        }
        .glassCard()
    }

    private func behaviorStat(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: AppTheme.spacingSM) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(value)
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacingMD)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous))
    }

    private var loadingOverlay: some View {
        VStack(spacing: AppTheme.spacingLG) {
            ProgressView()
                .controlSize(.large)
                .tint(AppTheme.accent)
            Text("Loading insights\u{2026}")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: AppTheme.spacingSM) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(AppTheme.error)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: AppTheme.spacingMD)
    }

    private func formatMinutes(_ value: Double?) -> String {
        guard let value else { return "--" }
        let minutes = Int(value / 60)
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}
