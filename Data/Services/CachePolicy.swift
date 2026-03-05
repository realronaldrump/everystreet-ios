import Foundation
import CryptoKit

enum CachePolicy {
    static let recentFreshness: TimeInterval = 60 * 60 * 6
    static let historicalFreshness: TimeInterval = 60 * 60 * 24 * 7

    static func maxAge(for interval: DateInterval, now: Date = .now) -> TimeInterval {
        let thirtyDaysAgo = now.addingTimeInterval(-60 * 60 * 24 * 30)
        if interval.end >= thirtyDaysAgo {
            return recentFreshness
        }
        return historicalFreshness
    }

    static func isFresh(lastSyncDate: Date?, interval: DateInterval, now: Date = .now) -> Bool {
        guard let lastSyncDate else { return false }
        let maxAge = maxAge(for: interval, now: now)
        return now.timeIntervalSince(lastSyncDate) <= maxAge
    }
}

struct CachedMapBundle {
    let etag: String
    let payload: Data
}

final class MapBundleCacheStore {
    private let directoryURL: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let path = base.appendingPathComponent("map-bundles", isDirectory: true)
        self.directoryURL = path
        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    }

    func load(key: String) -> CachedMapBundle? {
        let hashed = hashedKey(key)
        let payloadURL = directoryURL.appendingPathComponent("\(hashed).json")
        let etagURL = directoryURL.appendingPathComponent("\(hashed).etag")

        guard let payload = try? Data(contentsOf: payloadURL),
              let etagData = try? Data(contentsOf: etagURL),
              let etag = String(data: etagData, encoding: .utf8)
        else {
            return nil
        }

        return CachedMapBundle(etag: etag, payload: payload)
    }

    func store(key: String, payload: Data, etag: String) {
        let hashed = hashedKey(key)
        let payloadURL = directoryURL.appendingPathComponent("\(hashed).json")
        let etagURL = directoryURL.appendingPathComponent("\(hashed).etag")
        try? payload.write(to: payloadURL, options: .atomic)
        if let etagData = etag.data(using: .utf8) {
            try? etagData.write(to: etagURL, options: .atomic)
        }
    }

    private func hashedKey(_ key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
