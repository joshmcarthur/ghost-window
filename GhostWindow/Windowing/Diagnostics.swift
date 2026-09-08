import AppKit
import ApplicationServices
import Foundation

enum Diagnostics {
    static func currentReport(
        settings: Settings,
        manager: WindowManager
    ) -> String {
        let app = NSWorkspace.shared.frontmostApplication
        let trusted = AXIsProcessTrusted()
        var lines: [String] = []
        lines.append("Ghost Window diagnostics")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Ghost Window PID: \(ProcessInfo.processInfo.processIdentifier)")
        lines.append("Accessibility trusted: \(trusted)")
        lines.append("Screen recording: \(CGPreflightScreenCaptureAccess())")
        lines.append("Active backend: \(manager.activeBackendKind.rawValue)")
        lines.append("Configured opacity: \(settings.ghostOpacity)")
        lines.append("Frontmost app name: \(app?.localizedName ?? "none")")
        lines.append("Frontmost bundle id: \(app?.bundleIdentifier ?? "none")")
        lines.append("Frontmost PID: \(app?.processIdentifier ?? 0)")
        if let window = try? FrontmostWindowResolver.resolveFrontmost(
            selfPID: ProcessInfo.processInfo.processIdentifier,
            selfBundleID: Bundle.main.bundleIdentifier
        ) {
            lines.append("CGWindowID: \(window.windowID)")
            lines.append("Layer: \(window.layer)")
            lines.append("Bounds: \(Int(window.bounds.x)),\(Int(window.bounds.y)) \(Int(window.bounds.width))x\(Int(window.bounds.height))")
            lines.append("On screen: \(window.isOnScreen)")
            lines.append("Ghosted: \(manager.isGhosted(window.windowID))")
            if let alpha = SkyLightWindow.cgWindowListAlpha(windowID: window.windowID) {
                lines.append("kCGWindowAlpha: \(alpha)")
            }
            if let snapshot = try? SkyLightWindow.currentSnapshot(windowID: window.windowID) {
                lines.append("SkyLight alpha: \(snapshot.alpha)")
                lines.append("SkyLight isOpaque: \(snapshot.isOpaque)")
            }
        } else {
            lines.append("Focused window: unavailable")
        }
        lines.append("")
        lines.append(SkyLightBridge.loadedSymbolReport())
        lines.append("")
        lines.append("Ghosted window IDs: \(manager.ghostedWindowIDs.map(String.init).joined(separator: ", "))")
        return lines.joined(separator: "\n")
    }

    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
