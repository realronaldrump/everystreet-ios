import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    let container: AppContainer

    var body: some View {
        TabView {
            NavigationStack {
                MapTabView(
                    appModel: appModel,
                    repository: container.tripsRepository,
                    coverageRepository: container.coverageRepository,
                    coordinateCache: container.coordinateCache
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            .tabItem {
                Label("Map", systemImage: "map.fill")
            }

            NavigationStack {
                TripsTabView(appModel: appModel, repository: container.tripsRepository)
            }
            .tabItem {
                Label("Trips", systemImage: "road.lanes")
            }

            NavigationStack {
                InsightsTabView(appModel: appModel, repository: container.dashboardRepository)
            }
            .tabItem {
                Label("Insights", systemImage: "chart.bar.fill")
            }

            NavigationStack {
                PlacesTabView(appModel: appModel, repository: container.placesRepository)
            }
            .tabItem {
                Label("Places", systemImage: "mappin.circle.fill")
            }

            NavigationStack {
                CoverageAreasTabView(repository: container.coverageRepository)
            }
            .tabItem {
                Label("Coverage", systemImage: "square.3.layers.3d.top.filled")
            }

            NavigationStack {
                SettingsView(appModel: appModel, tripsRepository: container.tripsRepository, settingsRepository: container.settingsRepository)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
    }
}
