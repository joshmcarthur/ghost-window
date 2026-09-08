import CoreGraphics
import Foundation

/// High-level operations on a WindowServer window using symbols from `SkyLightBridge`.
///
/// Visual transparency requires two distinct WindowServer properties:
/// 1. **Alpha** (`SLSSetWindowAlpha`) — the 0...1 fade applied to the window.
/// 2. **Opacity flag** (`SLSSetWindowOpacity`) — a boolean "isOpaque" hint. If this
///    stays `true`, WindowServer may skip blending and ignore alpha < 1.
enum SkyLightWindow {
    struct Snapshot: Equatable {
        var alpha: Float
        var isOpaque: Bool
    }

    enum OperationError: Error, Equatable {
        case bridgeUnavailable
        case connectionUnavailable
        case callFailed(symbol: String, code: SkyLightBridge.CGErrorCode)
        case readFailed
        case windowMissing
        case alphaNotApplied(expected: Float, actual: Float)
    }

    static func currentSnapshot(windowID: SkyLightBridge.WindowID) throws -> Snapshot {
        let cid = try requireConnection()
        let alpha = try readAlpha(cid: cid, windowID: windowID)
        let isOpaque = readIsOpaque(cid: cid, windowID: windowID) ?? (alpha >= 0.999)
        return Snapshot(alpha: alpha, isOpaque: isOpaque)
    }

    static func setVisualAlpha(_ alpha: Float, windowID: SkyLightBridge.WindowID, makeOpaqueWhenFull: Bool) throws {
        let cid = try requireConnection()
        let clamped = min(max(alpha, 0), 1)
        let wantsTransparency = clamped < 0.999

        if wantsTransparency {
            try setOpaqueFlag(false, cid: cid, windowID: windowID)
            try setAlpha(clamped, cid: cid, windowID: windowID)
        } else {
            try setAlpha(1, cid: cid, windowID: windowID)
            if makeOpaqueWhenFull {
                try setOpaqueFlag(true, cid: cid, windowID: windowID)
            }
        }

        try verifyAlpha(clamped, cid: cid, windowID: windowID)
    }

    static func restore(_ snapshot: Snapshot, windowID: SkyLightBridge.WindowID) throws {
        let cid = try requireConnection()
        let clamped = min(max(snapshot.alpha, 0), 1)
        if snapshot.isOpaque && clamped >= 0.999 {
            try setAlpha(1, cid: cid, windowID: windowID)
            try setOpaqueFlag(true, cid: cid, windowID: windowID)
        } else {
            try setOpaqueFlag(false, cid: cid, windowID: windowID)
            try setAlpha(clamped, cid: cid, windowID: windowID)
        }
        try verifyAlpha(clamped, cid: cid, windowID: windowID)
    }

    static func exists(windowID: SkyLightBridge.WindowID) -> Bool {
        guard let cid = SkyLightBridge.connection() else {
            return cgWindowListContains(windowID)
        }
        if let windowIsOrderedIn = SkyLightBridge.windowIsOrderedIn {
            var ordered: UInt8 = 0
            if windowIsOrderedIn(cid, windowID, &ordered) == SkyLightBridge.success {
                return ordered != 0 || cgWindowListContains(windowID)
            }
        }
        if let getWindowAlpha = SkyLightBridge.getWindowAlpha {
            var alpha: Float = 0
            if getWindowAlpha(cid, windowID, &alpha) == SkyLightBridge.success {
                return true
            }
        }
        return cgWindowListContains(windowID)
    }

    static func bounds(windowID: SkyLightBridge.WindowID) -> CGRect? {
        if let cid = SkyLightBridge.connection(), let getWindowBounds = SkyLightBridge.getWindowBounds {
            var rect = CGRect.zero
            if getWindowBounds(cid, windowID, &rect) == SkyLightBridge.success, rect.width > 0, rect.height > 0 {
                return rect
            }
        }
        return cgWindowListBounds(windowID)
    }

    static func level(windowID: SkyLightBridge.WindowID) -> Int32? {
        guard let cid = SkyLightBridge.connection(), let getWindowLevel = SkyLightBridge.getWindowLevel else {
            return nil
        }
        var level: Int32 = 0
        guard getWindowLevel(cid, windowID, &level) == SkyLightBridge.success else { return nil }
        return level
    }

    static func cgWindowListAlpha(windowID: SkyLightBridge.WindowID) -> Float? {
        guard let info = cgWindowListInfo(windowID) else { return nil }
        return (info[kCGWindowAlpha as String] as? NSNumber)?.floatValue
    }

    // MARK: - Internals

    private static func requireConnection() throws -> SkyLightBridge.ConnectionID {
        guard SkyLightBridge.setWindowAlpha != nil else {
            throw OperationError.bridgeUnavailable
        }
        guard let cid = SkyLightBridge.connection() else {
            throw OperationError.connectionUnavailable
        }
        return cid
    }

    private static func readAlpha(cid: SkyLightBridge.ConnectionID, windowID: SkyLightBridge.WindowID) throws -> Float {
        if let getWindowAlpha = SkyLightBridge.getWindowAlpha {
            var alpha: Float = 1
            let code = getWindowAlpha(cid, windowID, &alpha)
            if code == SkyLightBridge.success {
                return alpha
            }
        }
        if let listed = cgWindowListAlpha(windowID: windowID) {
            return listed
        }
        throw OperationError.readFailed
    }

    private static func readIsOpaque(cid: SkyLightBridge.ConnectionID, windowID: SkyLightBridge.WindowID) -> Bool? {
        guard let getWindowOpacity = SkyLightBridge.getWindowOpacity else { return nil }
        var opaque: CBool = true
        guard getWindowOpacity(cid, windowID, &opaque) == SkyLightBridge.success else { return nil }
        return Bool(opaque)
    }

    private static func setAlpha(_ alpha: Float, cid: SkyLightBridge.ConnectionID, windowID: SkyLightBridge.WindowID) throws {
        if try applyViaTransaction(alpha: alpha, opaque: nil, cid: cid, windowID: windowID) {
            return
        }
        guard let setWindowAlpha = SkyLightBridge.setWindowAlpha else {
            throw OperationError.bridgeUnavailable
        }
        let code = setWindowAlpha(cid, windowID, alpha)
        guard code == SkyLightBridge.success else {
            throw OperationError.callFailed(symbol: "SLSSetWindowAlpha", code: code)
        }
    }

    private static func setOpaqueFlag(_ isOpaque: Bool, cid: SkyLightBridge.ConnectionID, windowID: SkyLightBridge.WindowID) throws {
        if try applyViaTransaction(alpha: nil, opaque: isOpaque, cid: cid, windowID: windowID) {
            return
        }
        guard let setWindowOpacity = SkyLightBridge.setWindowOpacity else {
            return
        }
        let code = setWindowOpacity(cid, windowID, CBool(isOpaque))
        guard code == SkyLightBridge.success else {
            throw OperationError.callFailed(symbol: "SLSSetWindowOpacity", code: code)
        }
    }

    /// Batches alpha + opaque-flag updates when the transaction SPI is present.
    @discardableResult
    private static func applyViaTransaction(
        alpha: Float?,
        opaque: Bool?,
        cid: SkyLightBridge.ConnectionID,
        windowID: SkyLightBridge.WindowID
    ) throws -> Bool {
        guard let transactionCreate = SkyLightBridge.transactionCreate,
              let transactionCommit = SkyLightBridge.transactionCommit
        else {
            return false
        }
        guard let transaction = transactionCreate(cid) else { return false }
        defer { Unmanaged.passUnretained(transaction).release() }

        if let opaque {
            guard let setOpaque = SkyLightBridge.transactionSetWindowOpaque else {
                return false
            }
            let code = setOpaque(transaction, windowID, CBool(opaque))
            if code != SkyLightBridge.success {
                throw OperationError.callFailed(symbol: "SLSTransactionSetWindowOpaque", code: code)
            }
        }
        if let alpha {
            if let setAlpha = SkyLightBridge.transactionSetWindowAlpha {
                let code = setAlpha(transaction, windowID, alpha)
                if code != SkyLightBridge.success {
                    throw OperationError.callFailed(symbol: "SLSTransactionSetWindowAlpha", code: code)
                }
            } else if let setSystem = SkyLightBridge.transactionSetWindowSystemAlpha {
                let code = setSystem(transaction, windowID, alpha)
                if code != SkyLightBridge.success {
                    throw OperationError.callFailed(symbol: "SLSTransactionSetWindowSystemAlpha", code: code)
                }
            } else {
                return false
            }
        }

        let commit = transactionCommit(transaction, 1)
        guard commit == SkyLightBridge.success else {
            throw OperationError.callFailed(symbol: "SLSTransactionCommit", code: commit)
        }
        return true
    }

    private static func verifyAlpha(
        _ expected: Float,
        cid: SkyLightBridge.ConnectionID,
        windowID: SkyLightBridge.WindowID
    ) throws {
        let actual = (try? readAlpha(cid: cid, windowID: windowID)) ?? cgWindowListAlpha(windowID: windowID)
        guard let actual else { return }
        if abs(actual - expected) > 0.08 {
            throw OperationError.alphaNotApplied(expected: expected, actual: actual)
        }
    }

    private static func cgWindowListContains(_ windowID: SkyLightBridge.WindowID) -> Bool {
        cgWindowListInfo(windowID) != nil
    }

    private static func cgWindowListBounds(_ windowID: SkyLightBridge.WindowID) -> CGRect? {
        guard let info = cgWindowListInfo(windowID),
              let bounds = info[kCGWindowBounds as String] as? [String: Any]
        else {
            return nil
        }
        let rect = CGRect(
            x: (bounds["X"] as? NSNumber)?.doubleValue ?? 0,
            y: (bounds["Y"] as? NSNumber)?.doubleValue ?? 0,
            width: (bounds["Width"] as? NSNumber)?.doubleValue ?? 0,
            height: (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
        )
        return rect.width > 0 && rect.height > 0 ? rect : nil
    }

    private static func cgWindowListInfo(_ windowID: SkyLightBridge.WindowID) -> [String: Any]? {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        return list.first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }
    }
}
