import Foundation
import Observation

@MainActor
@Observable
final class CoverageAreasViewModel {
    private let repository: CoverageRepository

    var areas: [CoverageArea] = []
    var isLoading = false
    var errorMessage: String?

    init(repository: CoverageRepository) {
        self.repository = repository
    }

    func load(force: Bool = false) async {
        guard force || areas.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        do {
            areas = try await repository.loadCoverageAreas()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
