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
                CoverageAreasTabView(repository: container.coverageRepository)
            }
            .tabItem {
                Label("Coverage", systemImage: "square.3.layers.3d.top.filled")
            }

            NavigationStack {
                SettingsView(
                    tripsRepository: container.tripsRepository,
                    settingsRepository: container.settingsRepository
                )
            }
            .tabItem {
                Label("More", systemImage: "ellipsis")
            }
        }
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
    }
}
