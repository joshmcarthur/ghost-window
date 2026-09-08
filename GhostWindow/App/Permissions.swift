import AppKit
import ApplicationServices
import Foundation

enum Permissions {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func ensureAccessibility(prompt: Bool = false) throws {
        if AXIsProcessTrusted() { return }
        guard RuntimeEnvironment.shouldPromptForPermissions else {
            throw GhostError.accessibilityDenied
        }

        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            GhostLogger.log("Requested Accessibility permission")
        }
        throw GhostError.accessibilityDenied
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
