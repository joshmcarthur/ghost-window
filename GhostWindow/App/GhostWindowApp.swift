import AppKit
import SwiftUI

@main
struct GhostWindowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Ghost Window", systemImage: menuImage) {
            MenuBarController()
                .environmentObject(appDelegate.settings)
                .environmentObject(appDelegate.windowManager)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuImage: String {
        appDelegate.windowManager.focusedIsGhosted ? "rectangle.on.rectangle.dashed" : "rectangle.dashed"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let settings = Settings()
    lazy var windowManager = WindowManager(settings: settings)
    private let shortcut = GlobalShortcut()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        GhostLogger.log("Starting")
        GhostLogger.log(SkyLightBridge.loadedSymbolReport().replacingOccurrences(of: "\n", with: " | "))

        guard RuntimeEnvironment.shouldRegisterLaunchSideEffects else {
            GhostLogger.log("Skipping shortcut and permission prompts (tests or CI)")
            return
        }

        AppNotifications.requestAuthorization()
        shortcut.register { [weak self] in
            self?.windowManager.toggleFrontmost()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        logAccessibilityStatus()
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            FrontmostAppTracker.noteActivated(frontmost, selfBundleID: Bundle.main.bundleIdentifier)
        }
        windowManager.refreshFocusStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GhostLogger.log("Quitting; restoring modified windows")
        shortcut.unregister()
        windowManager.handleWillTerminate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func frontmostChanged(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            FrontmostAppTracker.noteActivated(app, selfBundleID: Bundle.main.bundleIdentifier)
        }
        windowManager.refreshFocusStatus()
    }

    @objc private func applicationDidBecomeActive() {
        logAccessibilityStatus()
        windowManager.refreshFocusStatus()
    }

    private func logAccessibilityStatus() {
        let trusted = Permissions.isAccessibilityTrusted
        let path = Bundle.main.bundlePath
        GhostLogger.log("Accessibility trusted: \(trusted) | bundle: \(path)")
        if !trusted {
            GhostLogger.log("Grant Accessibility for this build in System Settings, then reopen Ghost Window")
        }
    }
}
