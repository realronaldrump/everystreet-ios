import SwiftUI

struct TripsTabView: View {
    @Bindable var appModel: AppModel
    @State private var viewModel: TripsTabViewModel

    private let repository: TripsRepository

    init(appModel: AppModel, repository: TripsRepository) {
        _appModel = Bindable(appModel)
        _viewModel = State(initialValue: TripsTabViewModel(repository: repository))
        self.repository = repository
    }

    var body: some View {
        ZStack {
            LinearGradient.appBackground.ignoresSafeArea()

            if viewModel.isLoading && viewModel.trips.isEmpty {
                loadingView
            } else if viewModel.groupedTrips.isEmpty && !viewModel.isLoading {
                emptyStateView
            } else {
                tripsList
            }
        }
        .safeAreaInset(edge: .top, spacing: AppTheme.spacingSM) {
            GlobalFilterBar(appModel: appModel) {
                Task { await viewModel.load(query: appModel.activeQuery, appModel: appModel) }
            }
            .padding(.horizontal, AppTheme.spacingLG)
        }
        .navigationTitle("Trips")
        .searchable(text: $viewModel.searchText, prompt: "Search places or trip id")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refresh(query: appModel.activeQuery) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                        .symbolEffect(.rotate, isActive: viewModel.isLoading)
                }
            }
        }
        .task {
            if viewModel.trips.isEmpty {
                await viewModel.load(query: appModel.activeQuery, appModel: appModel)
            }
        }
    }

    // MARK: - Trips List

    private var tripsList: some View {
        List {
            ForEach(viewModel.groupedTrips, id: \.day) { section in
                Section {
                    ForEach(section.trips) { trip in
                        NavigationLink {
                            TripDetailView(tripID: trip.transactionId, repository: repository)
                        } label: {
                            tripRow(trip)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: AppTheme.spacingXS, leading: AppTheme.spacingLG, bottom: AppTheme.spacingXS, trailing: AppTheme.spacingLG))
                    }
                } header: {
                    sectionHeader(section.day)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Section Header

    private func sectionHeader(_ date: Date) -> some View {
        HStack(spacing: AppTheme.spacingSM) {
            Circle()
                .fill(AppTheme.accent.opacity(0.4))
                .frame(width: 6, height: 6)

            Text(date, style: .date)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .padding(.vertical, AppTheme.spacingXS)
    }

    // MARK: - Trip Row

    private func tripRow(_ trip: TripSummary) -> some View {
        HStack(spacing: 0) {
            // Accent strip
            RoundedRectangle(cornerRadius: 1.5)
                .fill(AppTheme.accent.opacity(0.5))
                .frame(width: 3)
                .padding(.vertical, AppTheme.spacingXS)

            VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                // Time + Distance
                HStack(alignment: .firstTextBaseline) {
                    Text(trip.startTime, style: .time)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer()

                    Text(distanceText(trip.distance))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                }

                // Destination
                Text(trip.destination ?? trip.startLocation ?? "Unknown route")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)

                // Metric chips
                HStack(spacing: AppTheme.spacingSM) {
                    MetricChipView(icon: "clock", label: "Duration", value: durationText(trip.duration))
                    MetricChipView(icon: "gauge.high", label: "Max", value: speedText(trip.maxSpeed))
                    if let label = trip.vehicleLabel {
                        MetricChipView(icon: "car.fill", label: "Vehicle", value: label)
                    }
                }
            }
            .padding(.leading, AppTheme.spacingMD)
        }
        .padding(AppTheme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Empty & Loading States

    private var loadingView: some View {
        VStack(spacing: AppTheme.spacingLG) {
            ProgressView()
                .controlSize(.large)
                .tint(AppTheme.accent)
            Text("Loading trips\u{2026}")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: AppTheme.spacingLG) {
            Image(systemName: "road.lanes")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.textTertiary)
            Text("No trips found")
                .font(.headline)
                .foregroundStyle(AppTheme.textSecondary)
            Text("Adjust your filters or date range")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    // MARK: - Formatters

    private func distanceText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f mi", value)
    }

    private func durationText(_ value: Double?) -> String {
        guard let value else { return "--" }
        let minutes = Int(value / 60)
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    private func speedText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f mph", value)
    }
}
