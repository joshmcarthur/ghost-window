import AppKit
import ApplicationServices
import Foundation

enum WindowExclusions {
    static let excludedBundlePrefixes = [
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.WindowManager",
        "com.apple.loginwindow",
        "com.apple.systemuiserver",
        "com.apple.Spotlight",
        "com.apple.siri",
        "com.apple.ControlCenter",
        "com.apple.UserNotificationCenter",
        "com.apple.OSDUIHelper",
        "com.apple.wallpaper",
        "com.apple.accessibility.AXVisualSupportAgent"
    ]

    static let excludedProcessNames: Set<String> = [
        "Dock",
        "Control Center",
        "Notification Center",
        "Window Server",
        "WindowServer",
        "SystemUIServer",
        "Spotlight",
        "loginwindow",
        "Wallpaper"
    ]

    static func exclusionReason(
        for window: WindowReference,
        frontmostBundleID: String?,
        selfPID: pid_t,
        selfBundleID: String?
    ) -> String? {
        if window.ownerPID == selfPID {
            return "Ghost Window’s own window"
        }
        if let selfBundleID, frontmostBundleID == selfBundleID {
            return "Ghost Window’s own window"
        }
        if let bundleID = frontmostBundleID, isExcludedBundleID(bundleID) {
            return "system UI (\(bundleID))"
        }
        if isExcludedProcessName(window.ownerName) {
            return "system process (\(window.ownerName))"
        }

        let menubarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        if window.layer >= menubarLevel || window.layer == statusLevel || window.layer == dockLevel {
            return "menu-bar or system layer \(window.layer)"
        }
        if window.layer < 0 {
            return "desktop-element layer"
        }
        if window.bounds.height < 24 && window.bounds.width > 200 {
            return "menu-bar sized window"
        }
        return nil
    }

    static func isExcludedBundleID(_ bundleID: String) -> Bool {
        let lowered = bundleID.lowercased()
        return excludedBundlePrefixes.contains { lowered.hasPrefix($0.lowercased()) }
    }

    static func isExcludedProcessName(_ name: String) -> Bool {
        excludedProcessNames.contains(name)
    }
}

enum FrontmostWindowResolver {
    static func resolveFrontmost(selfPID: pid_t, selfBundleID: String?) throws -> WindowReference {
        guard let app = FrontmostAppTracker.frontmostApplication(selfBundleID: selfBundleID) else {
            throw GhostError.noFrontmostApp
        }

        GhostLogger.log("Frontmost app: \(app.localizedName ?? app.bundleIdentifier ?? "unknown")")

        if let reason = WindowExclusions.exclusionReason(
            for: WindowReference(
                windowID: 0,
                ownerPID: app.processIdentifier,
                ownerName: app.localizedName ?? "",
                layer: 0,
                bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100),
                isOnScreen: true,
                sharingState: 1
            ),
            frontmostBundleID: app.bundleIdentifier,
            selfPID: selfPID,
            selfBundleID: selfBundleID
        ), reason.contains("Ghost Window") || reason.contains("system") {
            throw GhostError.excluded(reason)
        }

        let window: WindowReference
        if let axWindow = try focusedAXWindow(pid: app.processIdentifier) {
            GhostLogger.log("AX window identified")
            window = axWindow
        } else if let listed = frontmostListedWindow(pid: app.processIdentifier) {
            GhostLogger.log("CGWindowList fallback identified")
            window = listed
        } else {
            throw GhostError.noFocusedWindow
        }

        GhostLogger.log("CGWindowID: \(window.windowID)")

        if let reason = WindowExclusions.exclusionReason(
            for: window,
            frontmostBundleID: app.bundleIdentifier,
            selfPID: selfPID,
            selfBundleID: selfBundleID
        ) {
            throw GhostError.excluded(reason)
        }

        return window
    }

    static func windowReference(for windowID: UInt32) -> WindowReference? {
        guard let info = windowInfo(windowID: windowID) else { return nil }
        return makeReference(from: info)
    }

    static func windowExists(_ windowID: UInt32) -> Bool {
        windowInfo(windowID: windowID) != nil || SkyLightWindow.exists(windowID: windowID)
    }

    private static func focusedAXWindow(pid: pid_t) throws -> WindowReference? {
        let appElement = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focused)
        guard error == .success, let focused else {
            var windows: CFTypeRef?
            let windowsError = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows)
            guard windowsError == .success, let list = windows as? [AXUIElement], let first = list.first else {
                return nil
            }
            return windowReference(from: first, pid: pid)
        }
        return windowReference(from: focused as! AXUIElement, pid: pid)
    }

    private static func windowReference(from element: AXUIElement, pid: pid_t) -> WindowReference? {
        var windowID: SkyLightBridge.WindowID = 0
        if let getter = SkyLightBridge.axUIElementGetWindow {
            let code = getter(element, &windowID)
            if code == 0, windowID != 0, let listed = windowReference(for: windowID) {
                return listed
            }
        }
        return matchAXWindowAgainstWindowList(element: element, pid: pid)
    }

    private static func matchAXWindowAgainstWindowList(element: AXUIElement, pid: pid_t) -> WindowReference? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)

        var position = CGPoint.zero
        var size = CGSize.zero
        if let positionValue {
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        }
        if let sizeValue {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }

        let candidates = listedWindows(pid: pid)
        if size.width > 0, size.height > 0 {
            let match = candidates.first { candidate in
                abs(candidate.bounds.x - position.x) < 8
                    && abs(candidate.bounds.y - position.y) < 8
                    && abs(candidate.bounds.width - size.width) < 8
                    && abs(candidate.bounds.height - size.height) < 8
            }
            if let match { return match }
        }
        return candidates.first
    }

    private static func frontmostListedWindow(pid: pid_t) -> WindowReference? {
        listedWindows(pid: pid).first
    }

    private static func listedWindows(pid: pid_t) -> [WindowReference] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info -> WindowReference? in
            guard let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value == pid
            else {
                return nil
            }
            return makeReference(from: info)
        }
    }

    private static func windowInfo(windowID: UInt32) -> [String: Any]? {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        return list.first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }
    }

    private static func makeReference(from info: [String: Any]) -> WindowReference? {
        guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
        else {
            return nil
        }
        let boundsDict = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let bounds = WindowBounds(
            x: (boundsDict["X"] as? NSNumber)?.doubleValue ?? 0,
            y: (boundsDict["Y"] as? NSNumber)?.doubleValue ?? 0,
            width: (boundsDict["Width"] as? NSNumber)?.doubleValue ?? 0,
            height: (boundsDict["Height"] as? NSNumber)?.doubleValue ?? 0
        )
        return WindowReference(
            windowID: number,
            ownerPID: pid,
            ownerName: info[kCGWindowOwnerName as String] as? String ?? "",
            layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
            bounds: bounds,
            isOnScreen: (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false,
            sharingState: (info[kCGWindowSharingState as String] as? NSNumber)?.intValue ?? 1
        )
    }
}
