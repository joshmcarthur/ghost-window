import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

/// Dynamically loaded SkyLight / CGS entry points.
///
/// All private WindowServer symbols used by Ghost Window are resolved here via
/// `dlopen` / `dlsym`. Nothing else in the app should call `dlsym` for SkyLight.
///
/// Framework: `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight`
///
/// Historical CGS* names are aliases of the current SLS* names. We try SLS first,
/// then CGS, then a small number of underscored variants.
enum SkyLightBridge {
    static let frameworkPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    static let frameworkPathVersioned = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
    static let hiServicesPath = "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices"

    typealias ConnectionID = Int32
    typealias WindowID = UInt32
    typealias CGErrorCode = Int32

    static let success: CGErrorCode = 0

    private static let skyLightHandle: UnsafeMutableRawPointer? = {
        if let handle = dlopen(frameworkPath, RTLD_LAZY | RTLD_LOCAL) {
            return handle
        }
        return dlopen(frameworkPathVersioned, RTLD_LAZY | RTLD_LOCAL)
    }()

    private static let hiServicesHandle: UnsafeMutableRawPointer? = {
        dlopen(hiServicesPath, RTLD_LAZY | RTLD_LOCAL)
    }()

    private static func loadSymbol<T>(_ names: [String], from handle: UnsafeMutableRawPointer?) -> T? {
        guard let handle else { return nil }
        for name in names {
            dlerror()
            guard let symbol = dlsym(handle, name) else { continue }
            return unsafeBitCast(symbol, to: T.self)
        }
        return nil
    }

    // MARK: - Connection

    typealias MainConnectionIDFunc = @convention(c) () -> ConnectionID
    static let mainConnectionID: MainConnectionIDFunc? = loadSymbol(
        ["SLSMainConnectionID", "CGSMainConnectionID", "_CGSDefaultConnection"],
        from: skyLightHandle
    )

    typealias DefaultConnectionForThreadFunc = @convention(c) () -> ConnectionID
    static let defaultConnectionForThread: DefaultConnectionForThreadFunc? = loadSymbol(
        ["SLSDefaultConnectionForThread", "CGSDefaultConnectionForThread"],
        from: skyLightHandle
    )

    // MARK: - Alpha (visual opacity, 0...1)

    /// ABI matches yabai / Chromium: `float`, not `CGFloat`.
    typealias GetWindowAlphaFunc = @convention(c) (ConnectionID, WindowID, UnsafeMutablePointer<Float>) -> CGErrorCode
    static let getWindowAlpha: GetWindowAlphaFunc? = loadSymbol(
        ["SLSGetWindowAlpha", "CGSGetWindowAlpha"],
        from: skyLightHandle
    )

    typealias SetWindowAlphaFunc = @convention(c) (ConnectionID, WindowID, Float) -> CGErrorCode
    static let setWindowAlpha: SetWindowAlphaFunc? = loadSymbol(
        ["SLSSetWindowAlpha", "CGSSetWindowAlpha", "_CGSWindowSetAlpha"],
        from: skyLightHandle
    )

    // MARK: - Opacity (boolean "isOpaque" compositor flag, not visual alpha)

    typealias GetWindowOpacityFunc = @convention(c) (ConnectionID, WindowID, UnsafeMutablePointer<CBool>) -> CGErrorCode
    static let getWindowOpacity: GetWindowOpacityFunc? = loadSymbol(
        ["SLSGetWindowOpacity", "CGSGetWindowOpacity"],
        from: skyLightHandle
    )

    typealias SetWindowOpacityFunc = @convention(c) (ConnectionID, WindowID, CBool) -> CGErrorCode
    static let setWindowOpacity: SetWindowOpacityFunc? = loadSymbol(
        ["SLSSetWindowOpacity", "CGSSetWindowOpacity"],
        from: skyLightHandle
    )

    // MARK: - Transactions

    typealias TransactionCreateFunc = @convention(c) (ConnectionID) -> CFTypeRef?
    static let transactionCreate: TransactionCreateFunc? = loadSymbol(
        ["SLSTransactionCreate", "CGSTransactionCreate"],
        from: skyLightHandle
    )

    typealias TransactionCommitFunc = @convention(c) (CFTypeRef, Int32) -> CGErrorCode
    static let transactionCommit: TransactionCommitFunc? = loadSymbol(
        ["SLSTransactionCommit", "CGSTransactionCommit"],
        from: skyLightHandle
    )

    typealias TransactionSetWindowAlphaFunc = @convention(c) (CFTypeRef, WindowID, Float) -> CGErrorCode
    static let transactionSetWindowAlpha: TransactionSetWindowAlphaFunc? = loadSymbol(
        ["SLSTransactionSetWindowAlpha", "CGSTransactionSetWindowAlpha"],
        from: skyLightHandle
    )

    typealias TransactionSetWindowSystemAlphaFunc = @convention(c) (CFTypeRef, WindowID, Float) -> CGErrorCode
    static let transactionSetWindowSystemAlpha: TransactionSetWindowSystemAlphaFunc? = loadSymbol(
        ["SLSTransactionSetWindowSystemAlpha", "CGSTransactionSetWindowSystemAlpha"],
        from: skyLightHandle
    )

    typealias TransactionSetWindowOpaqueFunc = @convention(c) (CFTypeRef, WindowID, CBool) -> CGErrorCode
    static let transactionSetWindowOpaque: TransactionSetWindowOpaqueFunc? = loadSymbol(
        ["SLSTransactionSetWindowOpaque", "SLSTransactionSetWindowOpacity"],
        from: skyLightHandle
    )

    // MARK: - Window queries

    typealias GetWindowBoundsFunc = @convention(c) (ConnectionID, WindowID, UnsafeMutablePointer<CGRect>) -> CGErrorCode
    static let getWindowBounds: GetWindowBoundsFunc? = loadSymbol(
        ["SLSGetWindowBounds", "CGSGetWindowBounds"],
        from: skyLightHandle
    )

    typealias GetWindowLevelFunc = @convention(c) (ConnectionID, WindowID, UnsafeMutablePointer<Int32>) -> CGErrorCode
    static let getWindowLevel: GetWindowLevelFunc? = loadSymbol(
        ["SLSGetWindowLevel", "CGSGetWindowLevel"],
        from: skyLightHandle
    )

    typealias WindowIsOrderedInFunc = @convention(c) (ConnectionID, WindowID, UnsafeMutablePointer<UInt8>) -> CGErrorCode
    static let windowIsOrderedIn: WindowIsOrderedInFunc? = loadSymbol(
        ["SLSWindowIsOrderedIn", "CGSWindowIsOrderedIn"],
        from: skyLightHandle
    )

    typealias DisableUpdateFunc = @convention(c) (ConnectionID) -> CGErrorCode
    static let disableUpdate: DisableUpdateFunc? = loadSymbol(
        ["SLSDisableUpdate", "CGSDisableUpdate"],
        from: skyLightHandle
    )

    typealias ReenableUpdateFunc = @convention(c) (ConnectionID) -> CGErrorCode
    static let reenableUpdate: ReenableUpdateFunc? = loadSymbol(
        ["SLSReenableUpdate", "CGSReenableUpdate"],
        from: skyLightHandle
    )

    // MARK: - Accessibility window ID (HIServices, not SkyLight)

    typealias AXUIElementGetWindowFunc = @convention(c) (AXUIElement, UnsafeMutablePointer<WindowID>) -> Int32
    static let axUIElementGetWindow: AXUIElementGetWindowFunc? = {
        if let loaded: AXUIElementGetWindowFunc = loadSymbol(["_AXUIElementGetWindow"], from: hiServicesHandle) {
            return loaded
        }
        dlerror()
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else {
            return nil
        }
        return unsafeBitCast(symbol, to: AXUIElementGetWindowFunc.self)
    }()

    // MARK: - Status

    static var isAvailable: Bool {
        skyLightHandle != nil && connection() != nil && setWindowAlpha != nil
    }

    static func connection() -> ConnectionID? {
        if let mainConnectionID {
            return mainConnectionID()
        }
        if let defaultConnectionForThread {
            return defaultConnectionForThread()
        }
        return nil
    }

    static func loadedSymbolReport() -> String {
        func mark(_ loaded: Bool) -> String { loaded ? "loaded" : "missing" }
        return """
        framework: \(frameworkPath)
        handle: \(skyLightHandle == nil ? "FAILED" : "ok")
        SLSMainConnectionID: \(mark(mainConnectionID != nil))
        SLSGetWindowAlpha: \(mark(getWindowAlpha != nil))
        SLSSetWindowAlpha: \(mark(setWindowAlpha != nil))
        SLSGetWindowOpacity: \(mark(getWindowOpacity != nil))
        SLSSetWindowOpacity: \(mark(setWindowOpacity != nil))
        SLSTransactionCreate: \(mark(transactionCreate != nil))
        SLSTransactionCommit: \(mark(transactionCommit != nil))
        SLSTransactionSetWindowAlpha: \(mark(transactionSetWindowAlpha != nil))
        SLSTransactionSetWindowSystemAlpha: \(mark(transactionSetWindowSystemAlpha != nil))
        SLSTransactionSetWindowOpaque: \(mark(transactionSetWindowOpaque != nil))
        SLSGetWindowBounds: \(mark(getWindowBounds != nil))
        SLSGetWindowLevel: \(mark(getWindowLevel != nil))
        SLSWindowIsOrderedIn: \(mark(windowIsOrderedIn != nil))
        _AXUIElementGetWindow: \(mark(axUIElementGetWindow != nil))
        """
    }
}
