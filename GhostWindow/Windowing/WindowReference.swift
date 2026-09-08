import CoreGraphics
import Foundation

struct WindowBounds: Hashable, Codable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }
}

struct WindowReference: Hashable, Codable, Sendable {
    var windowID: UInt32
    var ownerPID: pid_t
    var ownerName: String
    var layer: Int
    var bounds: WindowBounds
    var isOnScreen: Bool
    var sharingState: Int

    var id: UInt32 { windowID }
}

struct GhostedWindowRecord: Hashable, Codable, Sendable {
    var window: WindowReference
    var originalAlpha: Float
    var originalIsOpaque: Bool
    var appliedAlpha: Float
    var backend: BackendKind
}

enum BackendKind: String, Codable, Sendable {
    case skyLight
    case overlay
}
