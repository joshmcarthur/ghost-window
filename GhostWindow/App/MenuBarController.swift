import AppKit
import SwiftUI

struct MenuBarController: View {
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var windowManager: WindowManager
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Text(statusLine)
            .foregroundStyle(.secondary)
            .onAppear {
                launchAtLogin = LaunchAtLogin.isEnabled
                windowManager.refreshFocusStatus()
            }
        if let error = windowManager.lastError {
            Text(error)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if windowManager.focusedOwnerName == "Accessibility required" {
            Button("Open Accessibility Settings…") {
                Permissions.openAccessibilitySettings()
            }
        }
        Divider()
        Button(windowManager.focusedIsGhosted ? "Restore Current Window" : "Ghost Current Window") {
            windowManager.toggleFrontmost()
        }
        .keyboardShortcut("g", modifiers: [.command, .shift])

        Menu("Opacity") {
            ForEach(Settings.opacityOptions, id: \.self) { value in
                Button {
                    settings.ghostOpacity = value
                    windowManager.applyOpacitySettingToGhostedWindows()
                } label: {
                    opacityLabel(value)
                }
            }
        }

        Button("Restore All Windows") {
            windowManager.restoreAll()
        }
        .disabled(windowManager.ghostedWindowIDs.isEmpty)

        Divider()

        Toggle("Launch at Login", isOn: launchAtLoginBinding)

        Button("Copy Window Diagnostics") {
            windowManager.copyDiagnostics()
        }

        Divider()

        Button("Quit Ghost Window") {
            NSApp.terminate(nil)
        }
    }

    private var statusLine: String {
        if windowManager.focusedOwnerName == "Accessibility required" {
            return "Grant Accessibility in Privacy settings"
        }
        if windowManager.focusedOwnerName == "None" {
            return "No focused window"
        }
        let state = windowManager.focusedIsGhosted ? "Ghosted" : "Normal"
        return "\(windowManager.focusedOwnerName) — \(state)"
    }

    private func opacityLabel(_ value: Float) -> some View {
        let percent = Int((value * 100).rounded())
        let selected = abs(settings.ghostOpacity - value) < 0.001
        return HStack {
            Text("\(percent)%")
            if selected {
                Spacer()
                Text("✓")
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                do {
                    try LaunchAtLogin.setEnabled(newValue)
                    launchAtLogin = LaunchAtLogin.isEnabled
                } catch {
                    GhostLogger.log("Launch at login failed: \(error.localizedDescription)")
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
            }
        )
    }
}
