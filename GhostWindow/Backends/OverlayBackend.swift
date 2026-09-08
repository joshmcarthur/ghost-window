import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Approximate ghosting that does **not** change the real WindowServer window.
///
/// Used only when `SLSSetWindowAlpha` is missing or WindowServer silently ignores
/// the alpha write. A click-through overlay composites the window over the content
/// behind it at the requested opacity. Interaction still goes to the real window.
final class OverlayBackend: WindowGhostBackend {
    let kind: BackendKind = .overlay
    var requiresScreenRecording: Bool { true }

    var isUsable: Bool { true }

    private var overlays: [UInt32: OverlaySurface] = [:]
    private let lock = NSLock()

    func setOpacity(_ opacity: Float, for window: WindowReference) throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw GhostBackendError.screenRecordingRequired
        }

        lock.lock()
        let existing = overlays[window.windowID]
        lock.unlock()

        if let existing {
            existing.opacity = opacity
            existing.window = window
            existing.start()
            return
        }

        let surface = OverlaySurface(window: window, opacity: opacity)
        lock.lock()
        overlays[window.windowID] = surface
        lock.unlock()
        surface.start()
    }

    func restore(window: WindowReference) throws {
        lock.lock()
        let surface = overlays.removeValue(forKey: window.windowID)
        lock.unlock()
        surface?.stop()
    }

    func forget(windowID: UInt32) {
        lock.lock()
        let surface = overlays.removeValue(forKey: windowID)
        lock.unlock()
        surface?.stop()
    }

    func restoreAll() {
        lock.lock()
        let surfaces = overlays
        overlays.removeAll()
        lock.unlock()
        surfaces.values.forEach { $0.stop() }
    }
}

private final class OverlaySurface {
    var window: WindowReference
    var opacity: Float
    private var panel: NSPanel?
    private var imageView: NSImageView?
    private var timer: Timer?
    private var running = false

    init(window: WindowReference, opacity: Float) {
        self.window = window
        self.opacity = opacity
    }

    func start() {
        running = true
        ensurePanel()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        Task { await refresh() }
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        imageView = nil
    }

    private func ensurePanel() {
        if panel != nil { return }
        let panel = NSPanel(
            contentRect: cocoaRect(from: window.bounds.cgRect),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = NSWindow.Level(rawValue: max(window.layer + 1, Int(CGWindowLevelForKey(.floatingWindow))))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let imageView = NSImageView(frame: panel.contentView?.bounds ?? .zero)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        panel.contentView = imageView

        self.panel = panel
        self.imageView = imageView
        panel.orderFrontRegardless()
    }

    private func refresh() async {
        guard running else { return }
        guard let live = OverlayCapture.liveWindow(matching: window.windowID) else {
            stop()
            return
        }
        window = live
        ensurePanel()
        panel?.setFrame(cocoaRect(from: live.bounds.cgRect), display: true)
        do {
            if let image = try await OverlayCapture.compositeImage(for: live, opacity: opacity) {
                imageView?.image = image
                panel?.orderFrontRegardless()
            }
        } catch {
            GhostLogger.log("Overlay capture failed: \(error.localizedDescription)")
        }
    }
}

enum OverlayCapture {
    static func liveWindow(matching windowID: UInt32) -> WindowReference? {
        FrontmostWindowResolver.windowReference(for: windowID)
    }

    static func compositeImage(for window: WindowReference, opacity: Float) async throws -> NSImage? {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw GhostBackendError.overlayApproximationFailed(error.localizedDescription)
        }

        guard let scWindow = content.windows.first(where: { $0.windowID == window.windowID }) else {
            throw GhostBackendError.overlayApproximationFailed("Window is not shareable.")
        }

        let display = content.displays.first { display in
            CGRect(
                x: display.frame.origin.x,
                y: display.frame.origin.y,
                width: display.frame.width,
                height: display.frame.height
            ).intersects(window.bounds.cgRect)
        } ?? content.displays.first

        guard let display else {
            throw GhostBackendError.overlayApproximationFailed("No display for window.")
        }

        let behindFilter = SCContentFilter(display: display, excludingWindows: [scWindow])
        let windowFilter = SCContentFilter(desktopIndependentWindow: scWindow)

        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        let scale = max(NSScreen.main?.backingScaleFactor ?? 2, 1)
        let pixelWidth = max(Int(window.bounds.width * scale), 1)
        let pixelHeight = max(Int(window.bounds.height * scale), 1)
        configuration.width = pixelWidth
        configuration.height = pixelHeight

        let behind = try await SCScreenshotManager.captureImage(contentFilter: behindFilter, configuration: configuration)
        let foreground = try await SCScreenshotManager.captureImage(contentFilter: windowFilter, configuration: configuration)

        return composite(behind: behind, foreground: foreground, opacity: CGFloat(opacity), size: CGSize(width: window.bounds.width, height: window.bounds.height))
    }

    private static func composite(behind: CGImage, foreground: CGImage, opacity: CGFloat, size: CGSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        NSImage(cgImage: behind, size: size).draw(in: rect)
        NSImage(cgImage: foreground, size: size).draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: opacity
        )
        image.unlockFocus()
        return image
    }
}

func cocoaRect(from quartzRect: CGRect) -> CGRect {
    let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
    let maxY = primary?.frame.maxY ?? quartzRect.maxY
    return CGRect(
        x: quartzRect.origin.x,
        y: maxY - quartzRect.origin.y - quartzRect.height,
        width: quartzRect.width,
        height: quartzRect.height
    )
}
