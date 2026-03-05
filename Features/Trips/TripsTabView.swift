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
                        }
                    } header: {
                        Text(section.day, style: .date)
                            .font(.headline)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(AppTheme.accent)
            }
        }
        .safeAreaInset(edge: .top, spacing: 8) {
            GlobalFilterBar(appModel: appModel) {
                Task { await viewModel.load(query: appModel.activeQuery, appModel: appModel) }
            }
            .padding(.horizontal, 12)
        }
        .navigationTitle("Trips")
        .searchable(text: $viewModel.searchText, prompt: "Search places or trip id")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refresh(query: appModel.activeQuery) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            if viewModel.trips.isEmpty {
                await viewModel.load(query: appModel.activeQuery, appModel: appModel)
            }
        }
    }

    private func tripRow(_ trip: TripSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(trip.startTime, style: .time)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(distanceText(trip.distance))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }

            Text(trip.destination ?? trip.startLocation ?? "Unknown route")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)

            HStack(spacing: 12) {
                metricChip("Duration", value: durationText(trip.duration))
                metricChip("Max", value: speedText(trip.maxSpeed))
                if let label = trip.vehicleLabel {
                    metricChip("Vehicle", value: label)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func metricChip(_ title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    private func distanceText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f mi", value)
    }

    private func durationText(_ value: Double?) -> String {
        guard let value else { return "--" }
        let minutes = Int(value / 60)
        return "\(minutes)m"
    }

    private func speedText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f mph", value)
    }
}
