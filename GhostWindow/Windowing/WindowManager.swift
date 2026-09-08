import AppKit
import ApplicationServices
import Foundation

final class WindowManager: ObservableObject {
    @Published private(set) var ghostedWindowIDs: [UInt32] = []
    @Published private(set) var lastStatus: String = "Idle"
    @Published private(set) var lastError: String?
    @Published private(set) var focusedIsGhosted: Bool = false
    @Published private(set) var focusedOwnerName: String = "None"

    private let settings: Settings
    private let store: GhostStateStore
    private let skyLightBackend = SkyLightBackend()
    private var pruneTimer: Timer?

    init(settings: Settings, store: GhostStateStore = GhostStateStore()) {
        self.settings = settings
        self.store = store
        ghostedWindowIDs = store.all.map(\.window.windowID)
        restorePersistedStateIfNeeded()
        startPruneTimer()
        refreshFocusStatus()
    }

    func toggleFrontmost() {
        do {
            try Permissions.ensureAccessibility(prompt: true)
            let window = try FrontmostWindowResolver.resolveFrontmost(
                selfPID: ProcessInfo.processInfo.processIdentifier,
                selfBundleID: Bundle.main.bundleIdentifier
            )
            if store.isGhosted(window.windowID) {
                try restore(window)
                lastStatus = "Restored \(window.ownerName)"
                lastError = nil
            } else {
                try ghost(window)
                lastStatus = "Ghosted \(window.ownerName)"
                lastError = nil
            }
        } catch let error as GhostError {
            GhostLogger.log("Toggle failed: \(error.userMessage)")
            lastStatus = error.userMessage
            lastError = error.userMessage
            AppNotifications.notify(error.userMessage)
        } catch {
            lastStatus = "This window cannot be made transparent."
            lastError = lastStatus
            AppNotifications.notify("This window cannot be made transparent.")
        }
        refreshFocusStatus()
    }

    func restoreAll() {
        let records = store.all
        for record in records {
            do {
                try skyLightBackend.restore(window: record.window)
                store.remove(record.window.windowID)
            } catch {
                GhostLogger.log("Restore failed for \(record.window.windowID): \(error.localizedDescription)")
            }
        }
        ghostedWindowIDs = store.all.map(\.window.windowID)
        lastStatus = "Restored all windows"
        lastError = nil
        refreshFocusStatus()
    }

    func applyOpacitySettingToGhostedWindows() {
        for record in store.all {
            var updated = record
            updated.appliedAlpha = settings.ghostOpacity
            do {
                try skyLightBackend.setOpacity(settings.ghostOpacity, for: record.window)
                store.save(updated)
            } catch {
                GhostLogger.log("Failed to update ghosted window \(record.window.windowID)")
            }
        }
    }

    func isGhosted(_ windowID: UInt32) -> Bool {
        store.isGhosted(windowID)
    }

    func refreshFocusStatus() {
        guard AXIsProcessTrusted() else {
            focusedIsGhosted = false
            focusedOwnerName = "Accessibility required"
            return
        }
        do {
            let window = try FrontmostWindowResolver.resolveFrontmost(
                selfPID: ProcessInfo.processInfo.processIdentifier,
                selfBundleID: Bundle.main.bundleIdentifier
            )
            focusedOwnerName = window.ownerName.isEmpty ? "Unknown" : window.ownerName
            focusedIsGhosted = store.isGhosted(window.windowID)
        } catch let error as GhostError {
            GhostLogger.log("Focus refresh failed: \(error)")
            focusedIsGhosted = false
            focusedOwnerName = "None"
        } catch {
            GhostLogger.log("Focus refresh failed: \(error.localizedDescription)")
            focusedIsGhosted = false
            focusedOwnerName = "None"
        }
    }

    func copyDiagnostics() {
        let report = Diagnostics.currentReport(settings: settings, manager: self)
        Diagnostics.copyToClipboard(report)
        lastStatus = "Copied diagnostics"
        GhostLogger.log("Copied window diagnostics")
    }

    func handleWillTerminate() {
        restoreAll()
    }

    private func ghost(_ window: WindowReference) throws {
        if let alpha = SkyLightWindow.cgWindowListAlpha(windowID: window.windowID) {
            GhostLogger.log("Current opacity: \(alpha)")
        } else if let snapshot = try? SkyLightWindow.currentSnapshot(windowID: window.windowID) {
            GhostLogger.log("Current opacity: \(snapshot.alpha)")
        }

        GhostLogger.log("Setting opacity: \(settings.ghostOpacity)")

        let snapshot = try? SkyLightWindow.currentSnapshot(windowID: window.windowID)

        guard skyLightBackend.isUsable else {
            throw GhostError.backend(.backendUnavailable)
        }
        do {
            try skyLightBackend.setOpacity(settings.ghostOpacity, for: window)
            GhostLogger.log("Success")
        } catch let error as GhostBackendError {
            GhostLogger.log("SkyLight opacity change failed: \(error)")
            throw GhostError.backend(error)
        }

        let record = GhostedWindowRecord(
            window: window,
            originalAlpha: snapshot?.alpha ?? 1,
            originalIsOpaque: snapshot?.isOpaque ?? true,
            appliedAlpha: settings.ghostOpacity
        )
        store.save(record)
        ghostedWindowIDs = store.all.map(\.window.windowID)
    }

    private func restore(_ window: WindowReference) throws {
        try skyLightBackend.restore(window: window)
        skyLightBackend.forget(windowID: window.windowID)
        store.remove(window.windowID)
        ghostedWindowIDs = store.all.map(\.window.windowID)
        GhostLogger.log("Restored window \(window.windowID)")
    }

    private func restorePersistedStateIfNeeded() {
        store.pruneMissing(exists: FrontmostWindowResolver.windowExists)
        for record in store.all {
            do {
                try skyLightBackend.restore(window: record.window)
                store.remove(record.window.windowID)
                GhostLogger.log("Restored persisted window \(record.window.windowID)")
            } catch {
                GhostLogger.log("Could not restore persisted window \(record.window.windowID)")
            }
        }
        ghostedWindowIDs = store.all.map(\.window.windowID)
    }

    private func startPruneTimer() {
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.prune()
            }
        }
        if let pruneTimer {
            RunLoop.main.add(pruneTimer, forMode: .common)
        }
    }

    private func prune() {
        let before = store.all.map(\.window.windowID)
        store.pruneMissing(exists: FrontmostWindowResolver.windowExists)
        let after = Set(store.all.map(\.window.windowID))
        for windowID in before where !after.contains(windowID) {
            skyLightBackend.forget(windowID: windowID)
        }
        ghostedWindowIDs = store.all.map(\.window.windowID)
        refreshFocusStatus()
    }
}
