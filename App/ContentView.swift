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
                    coordinateCache: container.coordinateCache
                )
            }
            .tabItem {
                Label("Map", systemImage: "map")
            }

            NavigationStack {
                TripsTabView(appModel: appModel, repository: container.tripsRepository)
            }
            .tabItem {
                Label("Trips", systemImage: "list.bullet.rectangle")
            }

            NavigationStack {
                InsightsTabView(appModel: appModel, repository: container.dashboardRepository)
            }
            .tabItem {
                Label("Insights", systemImage: "chart.line.uptrend.xyaxis")
            }

            NavigationStack {
                PlacesTabView(appModel: appModel, repository: container.placesRepository)
            }
            .tabItem {
                Label("Places", systemImage: "mappin.and.ellipse")
            }

            NavigationStack {
                SettingsView(appModel: appModel, tripsRepository: container.tripsRepository, settingsRepository: container.settingsRepository)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .tint(AppTheme.accent)
        .background(LinearGradient.appBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
