import AppKit
import Foundation

/// Remembers the last frontmost app that was not Ghost Window itself.
///
/// Opening the menu-bar menu activates Ghost Window, so window resolution must
/// fall back to this tracker instead of treating Ghost Window as the target app.
enum FrontmostAppTracker {
    private static var lastNonSelfApp: NSRunningApplication?

    static func noteActivated(_ app: NSRunningApplication, selfBundleID: String?) {
        guard app.bundleIdentifier != selfBundleID else { return }
        lastNonSelfApp = app
    }

    static func frontmostApplication(selfBundleID: String?) -> NSRunningApplication? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            return lastNonSelfApp
        }
        if frontmost.bundleIdentifier == selfBundleID {
            return lastNonSelfApp
        }
        return frontmost
    }
}
