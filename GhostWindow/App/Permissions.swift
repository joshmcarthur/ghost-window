import ApplicationServices
import CoreGraphics
import Foundation

enum Permissions {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func ensureAccessibility() throws {
        if AXIsProcessTrusted() { return }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        GhostLogger.log("Requested Accessibility permission")
        throw GhostError.accessibilityDenied
    }

    static var hasScreenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func ensureScreenRecording() throws {
        if CGPreflightScreenCaptureAccess() { return }
        _ = CGRequestScreenCaptureAccess()
        GhostLogger.log("Requested Screen Recording permission for overlay fallback")
        throw GhostBackendError.screenRecordingRequired
    }
}
