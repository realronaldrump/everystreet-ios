import CoreLocation
import Foundation

final class LRUCoordinateCache {
    private final class CoordinateBox: NSObject {
        let value: [CLLocationCoordinate2D]

        init(value: [CLLocationCoordinate2D]) {
            self.value = value
        }
    }

    private let cache = NSCache<NSString, CoordinateBox>()

    init(memoryLimitBytes: Int = 120 * 1024 * 1024) {
        cache.totalCostLimit = memoryLimitBytes
        cache.countLimit = 3_000
    }

    func value(for key: String) -> [CLLocationCoordinate2D]? {
        cache.object(forKey: key as NSString)?.value
    }

    func set(_ value: [CLLocationCoordinate2D], for key: String) {
        let perPointBytes = MemoryLayout<Double>.size * 2
        let estimated = max(value.count * perPointBytes, 1)
        cache.setObject(CoordinateBox(value: value), forKey: key as NSString, cost: estimated)
    }

    func clear() {
        cache.removeAllObjects()
    }
}
