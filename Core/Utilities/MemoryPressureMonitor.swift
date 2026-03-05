import Foundation

@MainActor
final class MemoryPressureMonitor {
    private(set) var didReceiveWarning = false

    init(onWarning _: @escaping @MainActor () -> Void) {
        // Placeholder hook for memory-pressure handling.
        // Expanded observer wiring can be added if needed.
    }

    func markWarningReceived() {
        didReceiveWarning = true
    }
}
