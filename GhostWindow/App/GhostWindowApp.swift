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

        if !Permissions.isAccessibilityTrusted {
            GhostLogger.log("Accessibility is not granted yet")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                try? Permissions.ensureAccessibility()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GhostLogger.log("Quitting; restoring modified windows")
        shortcut.unregister()
        windowManager.handleWillTerminate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func frontmostChanged() {
        windowManager.refreshFocusStatus()
    }
}
