import os

/// Never log tokens or response bodies.
enum Log {
    static let subsystem = "io.github.vuxng.Agenty"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let refresh = Logger(subsystem: subsystem, category: "refresh")
}
