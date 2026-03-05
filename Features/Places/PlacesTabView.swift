import SwiftUI

struct PlacesTabView: View {
    @Bindable var appModel: AppModel
    @State private var viewModel: PlacesViewModel

    init(appModel: AppModel, repository: PlacesRepository) {
        _appModel = Bindable(appModel)
        _viewModel = State(initialValue: PlacesViewModel(repository: repository))
    }

    var body: some View {
        ZStack {
            LinearGradient.appBackground.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(AppTheme.accent)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        placeHeader

                        ForEach(viewModel.places) { place in
                            Button {
                                Task { await viewModel.select(place: place) }
                            } label: {
                                placeRow(place)
                            }
                            .buttonStyle(.plain)
                        }

                        if let selected = viewModel.selectedPlace,
                           let snapshot = viewModel.selectedPlaceTrips
                        {
                            placeTripsSection(selected: selected, snapshot: snapshot)
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
            }
        }
        .navigationTitle("Places")
        .task {
            if viewModel.places.isEmpty {
                await viewModel.load()
            }
        }
    }

    private var placeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Frequent Destinations")
                .font(.headline)
            Text("Top places based on visit count and time spent.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func placeRow(_ place: PlaceSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(place.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    chip("Visits", value: "\(place.totalVisits ?? 0)")
                    chip("Avg Stay", value: place.averageTimeSpent ?? "--")
                }
            }

            Spacer()

            if viewModel.selectedPlace?.id == place.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .glassCard()
    }

    private func placeTripsSection(selected: PlaceSummary, snapshot: PlaceTripsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trips for \(selected.name)")
                .font(.headline)

            if snapshot.trips.isEmpty {
                Text("No trips recorded for this place.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(snapshot.trips.prefix(12)) { trip in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(trip.endTime ?? .now, style: .date)
                                .font(.subheadline.weight(.semibold))
                            Text(trip.timeSpent ?? "--")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Spacer()
                        Text(String(format: "%.1f mi", trip.distance ?? 0))
                            .font(.caption.weight(.semibold))
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .glassCard()
    }

    private func chip(_ title: String, value: String) -> some View {
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
}
