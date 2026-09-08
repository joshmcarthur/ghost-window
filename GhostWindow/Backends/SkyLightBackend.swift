import Foundation

final class SkyLightBackend: WindowGhostBackend {
    let kind: BackendKind = .skyLight
    var requiresScreenRecording: Bool { false }

    var isUsable: Bool {
        SkyLightBridge.isAvailable
    }

    private var originals: [UInt32: SkyLightWindow.Snapshot] = [:]

    func originalSnapshot(for windowID: UInt32) -> SkyLightWindow.Snapshot? {
        originals[windowID]
    }

    func setOpacity(_ opacity: Float, for window: WindowReference) throws {
        guard isUsable else { throw GhostBackendError.backendUnavailable }

        let windowID = window.windowID
        if originals[windowID] == nil {
            do {
                originals[windowID] = try SkyLightWindow.currentSnapshot(windowID: windowID)
            } catch {
                throw GhostBackendError.operationFailed("Unable to read current opacity.")
            }
        }

        do {
            try SkyLightWindow.setVisualAlpha(opacity, windowID: windowID, makeOpaqueWhenFull: false)
        } catch SkyLightWindow.OperationError.alphaNotApplied {
            throw GhostBackendError.alphaNotApplied
        } catch SkyLightWindow.OperationError.bridgeUnavailable {
            throw GhostBackendError.backendUnavailable
        } catch {
            throw GhostBackendError.operationFailed(String(describing: error))
        }
    }

    func restore(window: WindowReference) throws {
        let windowID = window.windowID
        guard let snapshot = originals.removeValue(forKey: windowID) else {
            try SkyLightWindow.setVisualAlpha(1, windowID: windowID, makeOpaqueWhenFull: true)
            return
        }
        do {
            try SkyLightWindow.restore(snapshot, windowID: windowID)
        } catch SkyLightWindow.OperationError.alphaNotApplied {
            throw GhostBackendError.alphaNotApplied
        } catch {
            originals[windowID] = snapshot
            throw GhostBackendError.operationFailed(String(describing: error))
        }
    }

    func forget(windowID: UInt32) {
        originals.removeValue(forKey: windowID)
    }
}
