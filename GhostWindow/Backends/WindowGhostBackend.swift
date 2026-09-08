import Foundation

protocol WindowGhostBackend: AnyObject {
    var kind: BackendKind { get }
    var isUsable: Bool { get }
    var requiresScreenRecording: Bool { get }

    func setOpacity(_ opacity: Float, for window: WindowReference) throws
    func restore(window: WindowReference) throws
}

enum GhostBackendError: Error, Equatable {
    case backendUnavailable
    case windowNotModifiable(reason: String)
    case operationFailed(String)
    case screenRecordingRequired
    case overlayApproximationFailed(String)
    case alphaNotApplied

    var userMessage: String {
        switch self {
        case .backendUnavailable:
            return "The WindowServer opacity API is not available."
        case .windowNotModifiable:
            return "This window cannot be made transparent."
        case .operationFailed:
            return "This window cannot be made transparent."
        case .screenRecordingRequired:
            return "Screen Recording permission is required for the overlay fallback."
        case .overlayApproximationFailed:
            return "This window cannot be made transparent."
        case .alphaNotApplied:
            return "WindowServer ignored the opacity change."
        }
    }
}

enum GhostError: Error, Equatable {
    case accessibilityDenied
    case noFrontmostApp
    case noFocusedWindow
    case excluded(String)
    case backend(GhostBackendError)
    case restoreFailed(String)

    var userMessage: String {
        switch self {
        case .accessibilityDenied:
            return "Ghost Window needs Accessibility permission to identify the frontmost window."
        case .noFrontmostApp:
            return "No frontmost application was found."
        case .noFocusedWindow:
            return "This window cannot be made transparent."
        case .excluded:
            return "This window cannot be made transparent."
        case .backend(let error):
            return error.userMessage
        case .restoreFailed:
            return "Some windows could not be restored."
        }
    }
}
