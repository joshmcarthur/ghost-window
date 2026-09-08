import AppKit
import ApplicationServices
import Foundation

final class WindowManager: ObservableObject {
    @Published private(set) var ghostedWindowIDs: [UInt32] = []
    @Published private(set) var lastStatus: String = "Idle"
    @Published private(set) var focusedIsGhosted: Bool = false
    @Published private(set) var focusedOwnerName: String = "None"
    @Published private(set) var activeBackendKind: BackendKind = .skyLight
    @Published private(set) var usingOverlayApproximation: Bool = false

    private let settings: Settings
    private let store: GhostStateStore
    private let skyLightBackend = SkyLightBackend()
    private let overlayBackend = OverlayBackend()
    private var pruneTimer: Timer?

    init(settings: Settings, store: GhostStateStore = GhostStateStore()) {
        self.settings = settings
        self.store = store
        ghostedWindowIDs = store.all.map(\.window.windowID)
        usingOverlayApproximation = store.all.contains { $0.backend == .overlay }
        if usingOverlayApproximation {
            activeBackendKind = .overlay
        }
        restorePersistedStateIfNeeded()
        startPruneTimer()
        refreshFocusStatus()
    }

    func toggleFrontmost() {
        do {
            try Permissions.ensureAccessibility()
            let window = try FrontmostWindowResolver.resolveFrontmost(
                selfPID: ProcessInfo.processInfo.processIdentifier,
                selfBundleID: Bundle.main.bundleIdentifier
            )
            if store.isGhosted(window.windowID) {
                try restore(window)
                lastStatus = "Restored \(window.ownerName)"
            } else {
                try ghost(window)
                lastStatus = "Ghosted \(window.ownerName)"
            }
        } catch let error as GhostError {
            GhostLogger.log("Toggle failed: \(error.userMessage)")
            lastStatus = error.userMessage
            AppNotifications.notify(error.userMessage)
        } catch {
            lastStatus = "This window cannot be made transparent."
            AppNotifications.notify("This window cannot be made transparent.")
        }
        refreshFocusStatus()
    }

    func restoreAll() {
        let records = store.all
        for record in records {
            do {
                try backend(for: record.backend).restore(window: record.window)
                store.remove(record.window.windowID)
            } catch {
                GhostLogger.log("Restore failed for \(record.window.windowID): \(error.localizedDescription)")
            }
        }
        overlayBackend.restoreAll()
        ghostedWindowIDs = store.all.map(\.window.windowID)
        usingOverlayApproximation = false
        activeBackendKind = skyLightBackend.isUsable ? .skyLight : .overlay
        lastStatus = "Restored all windows"
        refreshFocusStatus()
    }

    func applyOpacitySettingToGhostedWindows() {
        for record in store.all {
            var updated = record
            updated.appliedAlpha = settings.ghostOpacity
            do {
                try backend(for: record.backend).setOpacity(settings.ghostOpacity, for: record.window)
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
        } catch {
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
        var kind: BackendKind = .skyLight

        do {
            guard skyLightBackend.isUsable else {
                throw GhostBackendError.backendUnavailable
            }
            try skyLightBackend.setOpacity(settings.ghostOpacity, for: window)
            GhostLogger.log("Success")
        } catch let error as GhostBackendError {
            switch error {
            case .windowNotModifiable:
                throw GhostError.backend(error)
            case .backendUnavailable, .operationFailed, .screenRecordingRequired, .overlayApproximationFailed, .alphaNotApplied:
                GhostLogger.log("SkyLight did not apply alpha (\(error)); trying overlay approximation")
                do {
                    try Permissions.ensureScreenRecording()
                    try overlayBackend.setOpacity(settings.ghostOpacity, for: window)
                } catch let overlayError as GhostBackendError {
                    throw GhostError.backend(overlayError)
                }
                kind = .overlay
                usingOverlayApproximation = true
                GhostLogger.log("Overlay approximation active")
            }
        }

        let record = GhostedWindowRecord(
            window: window,
            originalAlpha: snapshot?.alpha ?? 1,
            originalIsOpaque: snapshot?.isOpaque ?? true,
            appliedAlpha: settings.ghostOpacity,
            backend: kind
        )
        store.save(record)
        activeBackendKind = kind
        ghostedWindowIDs = store.all.map(\.window.windowID)
    }

    private func restore(_ window: WindowReference) throws {
        let kind = store.record(for: window.windowID)?.backend ?? .skyLight
        try backend(for: kind).restore(window: window)
        if kind == .skyLight {
            skyLightBackend.forget(windowID: window.windowID)
        } else {
            overlayBackend.forget(windowID: window.windowID)
        }
        store.remove(window.windowID)
        ghostedWindowIDs = store.all.map(\.window.windowID)
        usingOverlayApproximation = store.all.contains { $0.backend == .overlay }
        GhostLogger.log("Restored window \(window.windowID)")
    }

    private func backend(for kind: BackendKind) -> WindowGhostBackend {
        switch kind {
        case .skyLight:
            return skyLightBackend
        case .overlay:
            return overlayBackend
        }
    }

    private func restorePersistedStateIfNeeded() {
        store.pruneMissing(exists: FrontmostWindowResolver.windowExists)
        for record in store.all {
            do {
                try backend(for: record.backend).restore(window: record.window)
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
            overlayBackend.forget(windowID: windowID)
        }
        ghostedWindowIDs = store.all.map(\.window.windowID)
        usingOverlayApproximation = store.all.contains { $0.backend == .overlay }
        refreshFocusStatus()
    }
}
