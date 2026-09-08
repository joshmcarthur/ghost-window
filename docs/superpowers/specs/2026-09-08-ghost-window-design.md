# Ghost Window design

Menu-bar macOS utility that toggles real WindowServer window alpha via SkyLight, with an overlay approximation only if the private write does not apply.

## Approach chosen

Load SkyLight with `dlopen`/`dlsym`, resolve the frontmost window’s `CGWindowID`, call `SLSSetWindowOpacity(false)` + `SLSSetWindowAlpha(ghostOpacity)`, store the original snapshot, restore on second press / Restore All / quit.

Rejected: screenshot-as-primary (does not change the real window). Rejected: Dock injection (SIP off) — out of scope for a small menu-bar app.

## Components

- `SkyLightBridge` / `SkyLightWindow` — private API isolation
- `WindowGhostBackend` — `SkyLightBackend` then `OverlayBackend`
- `FrontmostWindowResolver` + exclusions
- `WindowManager` + `GhostStateStore`
- `GlobalShortcut` (Carbon ⌘⇧G)
- SwiftUI `MenuBarExtra`
