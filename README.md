# Ghost Window

A tiny experimental macOS menu-bar utility that toggles the **real** opacity of the frontmost application window with **⌘⇧G**.

Press once and the focused window is faded to the configured opacity (default **50%**). Press again and it is restored to the opacity it had before Ghost Window touched it.

This is **not** an App Store app. It uses private WindowServer / SkyLight APIs.

## What it does

1. Finds the frontmost app and its focused window (Accessibility + `CGWindowListCopyWindowInfo`).
2. Resolves that window’s WindowServer ID (`CGWindowID` / `_AXUIElementGetWindow`).
3. Calls SkyLight to set **actual window alpha** (`SLSSetWindowAlpha`) and the compositor’s opaque flag (`SLSSetWindowOpacity`).
4. If WindowServer silently ignores the write, falls back to a **labelled overlay approximation** (ScreenCaptureKit). That fallback does **not** modify the real window.

Ghost Window never writes application preferences and never captures a screenshot as the primary implementation.

## How to build

Requires a Mac with Xcode 16+ and the macOS 14+ SDK (developed for macOS 26).

```bash
open GhostWindow.xcodeproj
```

Select the **GhostWindow** scheme, destination **My Mac**, then Run.

Or from a terminal on macOS:

```bash
xcodebuild -project GhostWindow.xcodeproj -scheme GhostWindow -configuration Debug -destination 'platform=macOS' build
```

Ad-hoc code signing is enough for local use. Do not enable App Sandbox; private WindowServer calls need an unsandboxed binary.

After building, drag `GhostWindow.app` to `/Applications` if you want Launch at Login to work reliably.

## Continuous integration

Pull requests and pushes to `main` run on GitHub-hosted **macOS 26 Apple Silicon** runners (`macos-26`). The workflow:

1. Prints `sw_vers` and the selected Xcode/SDK
2. Runs `scripts/discover-skylight.sh` against the runner’s SkyLight.framework
3. Builds `GhostWindow.xcodeproj`
4. Runs `GhostWindowTests` (including a check that `SLSSetWindowAlpha` actually `dlsym`s)

See [`.github/workflows/ci.yml`](.github/workflows/ci.yml). macOS runners are billed at a higher minute multiplier than Linux; this repo uses a single job.

To run the same commands locally:

```bash
./scripts/discover-skylight.sh
xcodebuild -project GhostWindow.xcodeproj -scheme GhostWindow -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

## How to grant Accessibility permission

Ghost Window needs Accessibility **only to identify** the focused window. It does not type, click, or read document contents.

1. Launch Ghost Window once. macOS should prompt.
2. If it does not: **System Settings → Privacy & Security → Accessibility**.
3. Enable **Ghost Window**.
4. Quit and reopen Ghost Window.

Until this is granted, ⌘⇧G cannot see the frontmost window and will show:

`Ghost Window needs Accessibility permission to identify the frontmost window.`

## How the global shortcut works

Default shortcut: **⌘⇧G**.

It is registered with Carbon `RegisterEventHotKey`, which is delivered even when another app is focused. Ghost Window itself does not need to be frontmost. The menu-bar extra is accessory (`LSUIElement`); there is no Dock icon.

The same command is in the menu as **Ghost Current Window**.

## Private APIs

All private calls live in:

- `GhostWindow/SkyLight/SkyLightBridge.swift` — `dlopen` / `dlsym`
- `GhostWindow/SkyLight/SkyLightWindow.swift` — get/set alpha and opaque flag

Framework:

```
/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight
```

Primary symbols (SLS first, CGS aliases as fallback):

| Symbol | Signature used | Purpose |
| --- | --- | --- |
| `SLSMainConnectionID` | `() -> Int32` | WindowServer connection |
| `SLSGetWindowAlpha` | `(Int32, UInt32, UnsafeMutablePointer<Float>) -> Int32` | Read visual alpha |
| `SLSSetWindowAlpha` | `(Int32, UInt32, Float) -> Int32` | Set visual alpha **0...1** |
| `SLSSetWindowOpacity` | `(Int32, UInt32, CBool) -> Int32` | Boolean **isOpaque** compositor flag |
| `SLSTransactionCreate` / `Commit` / `SetWindowAlpha` | batched updates | Preferred write path when present |
| `_AXUIElementGetWindow` | HIServices | AX window → `CGWindowID` |

`SLSSetWindowOpacity` is **not** the visual fade. It is a boolean. Visual transparency is `SLSSetWindowAlpha`. Both are applied: opaque flag off, then alpha.

See [docs/PRIVATE_API.md](docs/PRIVATE_API.md) for discovery notes, failure modes, and how to re-probe after a macOS update.

## macOS version

| Item | Value |
| --- | --- |
| Target | macOS 14.0+, Apple Silicon primary |
| Designed against | macOS 26 WindowServer / SkyLight |
| Agent that produced this tree | Linux (Ubuntu 24.04) — SkyLight.framework was **not** present, so `nm` / `otool` could not be run here |
| Symbol verification | Cross-checked against current yabai `extern.h`, CGSInternal, and Loop’s SkyLight loader (which still resolves SkyLight symbols on macOS 26.3) |

Run `scripts/discover-skylight.sh` **on a Mac** to dump the symbols actually exported by the installed framework.

## Updating private symbols after a macOS update

```bash
./scripts/discover-skylight.sh
```

Then compare the printed names with `SkyLightBridge.swift`. The bridge already tries, in order:

1. `SLS…`
2. `CGS…`
3. a few underscored historical names (`_CGSWindowSetAlpha`, `_CGSDefaultConnection`)

If a function is renamed, add the new name to the `loadSymbol([...])` list. Prefer `dlsym` over linking SkyLight.

## Limitations

- **SIP / process isolation.** Calling `SLSSetWindowAlpha` from a third-party process for *another* app’s windows has historically worked, and still works inside injected Dock payloads (yabai). On recent SIP-enabled macOS it may return success or still report alpha 1.0 with no visual change. Ghost Window **verifies** the read-back and, if the real window did not change, uses the overlay fallback.
- Overlay fallback is an **approximation**: a click-through ScreenCaptureKit composite. It does not change the real window. The menu labels it as such. Screen Recording is requested **only** for this path.
- Fullscreen spaces, Stage Manager, and some Electron / Metal windows may refuse alpha. Ghost Window fails with *This window cannot be made transparent.* It does **not** fake fullscreen with an overlay if the real window cannot be modified.
- System UI is excluded: Dock, Control Center, Notification Center, menu bar, Ghost Window’s own windows, and similar.
- A crash or `kill -9` can leave windows faded until Ghost Window is launched again (it persists original alpha and restores on startup and on Quit).
- Not signed for distribution. Gatekeeper may require a right-click → Open the first time.

## Why this is unsuitable for the Mac App Store

- Private WindowServer / SkyLight APIs
- Dynamic loading of a private framework
- Accessibility used to target other apps’ windows
- Must not be sandboxed for this technique
- Overlay path uses Screen Recording

App Review will reject it. Treat it as a personal / experimental tool.

## Disable / uninstall

1. Open the Ghost Window menu → **Restore All Windows** (or just Quit; quit restores too).
2. Turn off **Launch at Login** if it was enabled.
3. Quit Ghost Window.
4. Delete `GhostWindow.app`.
5. Optional cleanup:
   - **System Settings → Privacy & Security → Accessibility** — remove Ghost Window
   - **Screen Recording** — remove it if the overlay path was used
   - `~/Library/Application Support/GhostWindow/ghosted-windows.json`

## Menu

- Status line: focused app and whether it is Ghosted or Normal
- Ghost Current Window / Restore Current Window — ⌘⇧G
- Opacity: 25% / 40% / 50% / 60% / 75%
- Restore All Windows
- Launch at Login
- Copy Window Diagnostics (no window titles by default)
- Quit Ghost Window

## Logging

stderr / unified log, for example:

```
[Ghost Window] Frontmost app: Safari
[Ghost Window] AX window identified
[Ghost Window] CGWindowID: 1234
[Ghost Window] Current opacity: 1.0
[Ghost Window] Setting opacity: 0.5
[Ghost Window] Success
```

## Architecture

```
⌘⇧G
  → FrontmostWindowResolver (AX + CGWindowList)
  → WindowExclusions
  → WindowGhostBackend
       1. SkyLightBackend   real WindowServer alpha
       2. OverlayBackend    approximation only if (1) does not apply
  → GhostStateStore (original alpha, restore-all, crash recovery)
```

## Tests

On a Mac:

```bash
xcodebuild -project GhostWindow.xcodeproj -scheme GhostWindow -destination 'platform=macOS' test
```

Unit tests cover exclusions, persisted ghost state, opacity presets, error copy, and that SkyLight symbols resolve on macOS. They cannot prove that cross-process alpha writes succeed under SIP.
