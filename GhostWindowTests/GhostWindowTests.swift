import Foundation
import XCTest
@testable import GhostWindow

final class WindowExclusionsTests: XCTestCase {
    func testExcludesDockAndControlCenterBundles() {
        XCTAssertTrue(WindowExclusions.isExcludedBundleID("com.apple.dock"))
        XCTAssertTrue(WindowExclusions.isExcludedBundleID("com.apple.controlcenter"))
        XCTAssertTrue(WindowExclusions.isExcludedBundleID("com.apple.notificationcenterui"))
        XCTAssertFalse(WindowExclusions.isExcludedBundleID("com.apple.Safari"))
        XCTAssertFalse(WindowExclusions.isExcludedBundleID("com.google.Chrome"))
    }

    func testExcludesSystemProcessNames() {
        XCTAssertTrue(WindowExclusions.isExcludedProcessName("Dock"))
        XCTAssertTrue(WindowExclusions.isExcludedProcessName("WindowServer"))
        XCTAssertFalse(WindowExclusions.isExcludedProcessName("Safari"))
    }

    func testExcludesOwnProcess() {
        let window = WindowReference(
            windowID: 1,
            ownerPID: 42,
            ownerName: "Ghost Window",
            layer: 0,
            bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600),
            isOnScreen: true,
            sharingState: 1
        )
        let reason = WindowExclusions.exclusionReason(
            for: window,
            frontmostBundleID: "com.joshmcarthur.GhostWindow",
            selfPID: 42,
            selfBundleID: "com.joshmcarthur.GhostWindow"
        )
        XCTAssertEqual(reason, "Ghost Window’s own window")
    }

    func testDoesNotExcludeNormalWindowsWithSharingDisabled() {
        let window = WindowReference(
            windowID: 2,
            ownerPID: 99,
            ownerName: "Google Chrome",
            layer: 0,
            bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600),
            isOnScreen: true,
            sharingState: 0
        )
        let reason = WindowExclusions.exclusionReason(
            for: window,
            frontmostBundleID: "com.google.Chrome",
            selfPID: 42,
            selfBundleID: "com.joshmcarthur.GhostWindow"
        )
        XCTAssertNil(reason)
    }
}

final class GhostStateStoreTests: XCTestCase {
    func testSaveRestoreAndPrune() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ghost-state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GhostStateStore(url: url)
        let window = WindowReference(
            windowID: 99,
            ownerPID: 7,
            ownerName: "TextEdit",
            layer: 0,
            bounds: WindowBounds(x: 10, y: 20, width: 300, height: 200),
            isOnScreen: true,
            sharingState: 1
        )
        store.save(
            GhostedWindowRecord(
                window: window,
                originalAlpha: 1,
                originalIsOpaque: true,
                appliedAlpha: 0.5
            )
        )
        XCTAssertTrue(store.isGhosted(99))

        let reloaded = GhostStateStore(url: url)
        XCTAssertEqual(reloaded.record(for: 99)?.appliedAlpha, 0.5)

        reloaded.pruneMissing { $0 != 99 }
        XCTAssertFalse(reloaded.isGhosted(99))
    }
}

final class SettingsTests: XCTestCase {
    func testDefaultOpacityIsFiftyPercent() {
        XCTAssertEqual(Settings.defaultOpacity, 0.50)
        XCTAssertTrue(Settings.opacityOptions.contains(0.50))
        XCTAssertEqual(Settings.opacityOptions.count, 5)
    }
}

final class GhostErrorTests: XCTestCase {
    func testBackendErrorsAreExhaustiveAndUserFacing() {
        let errors: [GhostBackendError] = [
            .backendUnavailable,
            .windowNotModifiable(reason: "system"),
            .operationFailed("fail"),
            .alphaNotApplied
        ]
        for error in errors {
            XCTAssertFalse(error.userMessage.isEmpty)
        }
    }
}

final class SkyLightBridgeTests: XCTestCase {
    func testSkyLightFrameworkLoadsOnMac() {
        XCTAssertTrue(
            SkyLightBridge.isAvailable,
            "SkyLight must load on the CI Mac. Report:\n\(SkyLightBridge.loadedSymbolReport())"
        )
        XCTAssertNotNil(SkyLightBridge.connection())
        XCTAssertNotNil(SkyLightBridge.setWindowAlpha)
        XCTAssertNotNil(SkyLightBridge.getWindowAlpha)
        XCTAssertNotNil(SkyLightBridge.setWindowOpacity)
        XCTAssertNotNil(SkyLightBridge.mainConnectionID)
    }

    func testAXWindowLookupSymbolLoads() {
        XCTAssertNotNil(
            SkyLightBridge.axUIElementGetWindow,
            "_AXUIElementGetWindow should resolve from HIServices"
        )
    }
}

final class RuntimeEnvironmentTests: XCTestCase {
    func testTestRunDoesNotPromptForPermissions() {
        XCTAssertTrue(RuntimeEnvironment.isRunningTests)
        XCTAssertFalse(RuntimeEnvironment.shouldPromptForPermissions)
        XCTAssertFalse(RuntimeEnvironment.shouldRegisterLaunchSideEffects)
    }
}
