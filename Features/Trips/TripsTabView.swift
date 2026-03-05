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
        .searchable(text: $viewModel.searchText, prompt: "Search destinations or trip ID")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refresh(query: appModel.activeQuery) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
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
            Text(date, style: .date)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            VStack { Divider().background(AppTheme.divider) }
        }
        .padding(.vertical, AppTheme.spacingXS)
    }

    // MARK: - Trip Row

    private func tripRow(_ trip: TripSummary) -> some View {
        HStack(spacing: AppTheme.spacingMD) {
            // Time column
            VStack(spacing: 2) {
                Text(trip.startTime, style: .time)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .frame(width: 52, alignment: .leading)

            // Accent line
            RoundedRectangle(cornerRadius: 1.5)
                .fill(AppTheme.accent.opacity(0.4))
                .frame(width: 2.5)
                .padding(.vertical, AppTheme.spacingXS)

            // Content
            VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                Text(trip.destination ?? trip.startLocation ?? "Unknown route")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: AppTheme.spacingSM) {
                    MetricChipView(icon: "road.lanes", label: "Dist", value: distanceText(trip.distance))
                    MetricChipView(icon: "clock", label: "Dur", value: durationText(trip.duration))
                    if let label = trip.vehicleLabel {
                        MetricChipView(icon: "car.fill", label: "Vehicle", value: label)
                    }
                }
            }

            Spacer(minLength: 0)

            // Distance badge
            Text(distanceText(trip.distance))
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.accent)
        }
        .padding(.vertical, AppTheme.spacingSM)
        .padding(.horizontal, AppTheme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
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
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.textTertiary)
            Text("No Trips Found")
                .font(.title3.weight(.semibold))
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
