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
                VStack(spacing: AppTheme.spacingXL) {
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
        VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
            SectionHeaderView("Overview", icon: "chart.bar.xaxis")

            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: AppTheme.spacingSM) {
                StatCardView(title: "Total Trips", value: "\(metrics.totalTrips)", icon: "road.lanes", color: AppTheme.statDistance)
                StatCardView(title: "Distance", value: String(format: "%.1f mi", metrics.totalDistance), icon: "point.topleft.down.to.point.bottomright.curvepath", color: AppTheme.statDuration)
                StatCardView(title: "Avg Speed", value: String(format: "%.1f mph", metrics.avgSpeed), icon: "gauge.medium", color: AppTheme.statSpeed)
                StatCardView(title: "Max Speed", value: String(format: "%.1f mph", metrics.maxSpeed), icon: "gauge.high", color: AppTheme.statMaxSpeed)
            }
        }
    }

    // MARK: - Charts

    private func weekdayChart(_ analytics: TripAnalyticsSnapshot) -> some View {
        chartCard(title: "Trips by Day", icon: "calendar") {
            Chart(analytics.weekdayDistribution) { point in
                BarMark(
                    x: .value("Day", point.label),
                    y: .value("Trips", point.count)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.chartPrimary, AppTheme.chartPrimary.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4, dash: [5, 4]))
                        .foregroundStyle(AppTheme.divider)
                    AxisValueLabel {
                        if let intVal = value.as(Int.self) {
                            Text("\(intVal)")
                                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let str = value.as(String.self) {
                            Text(abbreviateDay(str))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
            .chartPlotStyle { plot in
                plot.padding(.top, 8)
            }
            .frame(height: 200)
        }
    }

    private func hourlyChart(_ analytics: TripAnalyticsSnapshot) -> some View {
        chartCard(title: "Time of Day", icon: "clock") {
            Chart(analytics.timeDistribution) { point in
                AreaMark(
                    x: .value("Hour", point.label),
                    y: .value("Trips", point.count)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.accentWarm.opacity(0.25), AppTheme.accentWarm.opacity(0.02)],
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
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4, dash: [5, 4]))
                        .foregroundStyle(AppTheme.divider)
                    AxisValueLabel {
                        if let intVal = value.as(Int.self) {
                            Text("\(intVal)")
                                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisValueLabel {
                        if let str = value.as(String.self) {
                            Text(abbreviateHour(str))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                }
            }
            .chartPlotStyle { plot in
                plot.padding(.top, 8)
            }
            .frame(height: 200)
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
                        colors: [AppTheme.chartTertiary, AppTheme.chartTertiary.opacity(0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4, dash: [5, 4]))
                        .foregroundStyle(AppTheme.divider)
                    AxisValueLabel {
                        if let doubleVal = value.as(Double.self) {
                            Text(doubleVal < 10 ? String(format: "%.1f", doubleVal) : String(format: "%.0f", doubleVal))
                                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisValueLabel {
                        if let str = value.as(String.self) {
                            Text(abbreviateDate(str))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                }
            }
            .chartPlotStyle { plot in
                plot.padding(.top, 8)
            }
            .frame(height: 200)
        }
    }

    // MARK: - Helpers

    private func chartCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
            SectionHeaderView(title, icon: icon)
            content()
        }
        .glassCard()
    }

    /// Shorten day labels like "Monday" -> "Mon", "Tuesday" -> "Tue"
    private func abbreviateDay(_ day: String) -> String {
        if day.count > 3 { return String(day.prefix(3)) }
        return day
    }

    /// Shorten hour labels to concise format
    private func abbreviateHour(_ hour: String) -> String {
        let trimmed = hour.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 5 { return trimmed }
        if let num = Int(trimmed) {
            let suffix = num >= 12 ? "p" : "a"
            let display = num == 0 ? 12 : (num > 12 ? num - 12 : num)
            return "\(display)\(suffix)"
        }
        return String(trimmed.prefix(5))
    }

    /// Shorten date labels like "2025-03-01" -> "Mar 1"
    private func abbreviateDate(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        if parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) {
            let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            if month >= 1, month <= 12 {
                return "\(months[month]) \(day)"
            }
        }
        if dateStr.count > 6 { return String(dateStr.suffix(5)) }
        return dateStr
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
}
