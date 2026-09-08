import Foundation

enum RuntimeEnvironment {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var isCI: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["CI"] == "true" || env["GITHUB_ACTIONS"] == "true"
    }

    static var shouldPromptForPermissions: Bool {
        !isRunningTests && !isCI
    }

    static var shouldRegisterLaunchSideEffects: Bool {
        !isRunningTests && !isCI
    }
}
