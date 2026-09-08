import Foundation

enum GhostLogger {
    static func log(_ message: String) {
        fputs("[Ghost Window] \(message)\n", stderr)
        NSLog("[Ghost Window] %@", message)
    }
}
