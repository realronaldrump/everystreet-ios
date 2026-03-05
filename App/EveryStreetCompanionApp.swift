import SwiftUI
import SwiftData

@main
struct EveryStreetCompanionApp: App {
    @State private var appModel: AppModel
    private let container: AppContainer

    init() {
        do {
            let container = try AppContainer()
            self.container = container
            _appModel = State(initialValue: AppModel(tripsRepository: container.tripsRepository))
        } catch {
            fatalError("Failed to initialize app container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(container: container)
                .environment(appModel)
                .task {
                    await appModel.bootstrap()
                }
        }
        .modelContainer(container.modelContainer)
    }
}
