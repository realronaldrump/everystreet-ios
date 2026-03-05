import Foundation
import OSLog

enum AppLogger {
    static let subsystem = "com.everystreet.companion"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let repository = Logger(subsystem: subsystem, category: "repository")
    static let cache = Logger(subsystem: subsystem, category: "cache")
    static let map = Logger(subsystem: subsystem, category: "map")
}
