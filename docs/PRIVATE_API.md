# Ghost Window private API notes

This document is the Phase 1 discovery record plus the ABI Ghost Window actually uses.

## Development machine that produced this tree

- OS: Ubuntu 24.04.4 (Linux 6.12) Cursor cloud agent
- SkyLight.framework: **not installed**
- `nm` / `otool` / `strings` on SkyLight: **could not be run here**
- Re-run `scripts/discover-skylight.sh` on a Mac after every macOS update

## What we were looking for

Historical names:

- `CGSSetWindowOpacity` / `_CGSSetWindowOpacity` / `SLSSetWindowOpacity`
- `CGSSetWindowAlpha` / `SLSSetWindowAlpha`

These are **two different properties**:

| API | Argument | Meaning |
| --- | --- | --- |
| `SLSSetWindowOpacity` | `bool isOpaque` | Compositor hint. `true` = treat as fully opaque; WindowServer may ignore alpha. |
| `SLSSetWindowAlpha` | `float 0...1` | Visual fade of the window. This is the ghost effect. |

Making a foreign window see-through requires:

1. `SLSSetWindowOpacity(cid, wid, false)`
2. `SLSSetWindowAlpha(cid, wid, 0.5)`

Restoring a previously opaque window:

1. `SLSSetWindowAlpha(cid, wid, original)`
2. `SLSSetWindowOpacity(cid, wid, true)` if it was opaque

## Framework path

```
/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight
/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight
```

TBD (SDK, useful when the binary is stripped):

```
$SDKROOT/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight.tbd
```

HIServices (window ID from AX):

```
/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices
```

Ghost Window never links SkyLight at build time. It `dlopen`s the path above and `dlsym`s each symbol.

## Discovered symbols and signatures

Sources, in preference order:

1. [yabai `src/misc/extern.h`](https://github.com/koekeishiya/yabai/blob/master/src/misc/extern.h) — live ABI used for window alpha on current macOS
2. [CGSInternal `CGSWindow.h`](https://github.com/NUIKit/CGSInternal/blob/master/CGSWindow.h)
3. Loop `SkyLightSymbolLoader` (macOS 26.0 / 26.3 comments; still `dlopen`s SkyLight)
4. Chromium constrained-window animation (`CGSSetWindowAlpha` with `float`)

### Connection

```
SLSMainConnectionID / CGSMainConnectionID / _CGSDefaultConnection
    () -> Int32
```

Loop types this as `UInt32`. yabai uses `int`. Connection IDs are small; Ghost Window uses `Int32` to match the opacity functions.

### Alpha

```
SLSGetWindowAlpha / CGSGetWindowAlpha
    (Int32 cid, UInt32 wid, float *outAlpha) -> CGError

SLSSetWindowAlpha / CGSSetWindowAlpha / _CGSWindowSetAlpha
    (Int32 cid, UInt32 wid, float alpha) -> CGError
```

**ABI note:** yabai and Chromium pass `float`, not `CGFloat`. On arm64 `CGFloat` is `Double`. Using the wrong width would smash the stack. Ghost Window uses `Float`.

### Opaque flag

```
SLSGetWindowOpacity / CGSGetWindowOpacity
    (Int32 cid, UInt32 wid, bool *outIsOpaque) -> CGError

SLSSetWindowOpacity / CGSSetWindowOpacity
    (Int32 cid, UInt32 wid, bool isOpaque) -> CGError
```

### Transactions

Preferred when present (WindowServer applies the batch together):

```
SLSTransactionCreate(cid) -> CFTypeRef
SLSTransactionSetWindowAlpha(transaction, wid, float alpha) -> CGError
SLSTransactionSetWindowSystemAlpha(transaction, wid, float alpha) -> CGError
SLSTransactionSetWindowOpaque(transaction, wid, bool) -> CGError
SLSTransactionCommit(transaction, int synchronous) -> CGError
```

yabai commits with `synchronous = 0` for animation; Ghost Window commits with `1` so the following read-back sees the new alpha.

### Window ID from Accessibility

```
_AXUIElementGetWindow(AXUIElementRef, uint32_t *wid) -> AXError
```

Fallback: match AX position/size against `CGWindowListCopyWindowInfo`.

## macOS 26 observations (from public sources, not this agent)

- SkyLight is still the private WindowServer client library.
- Loop (April 2026) still `dlopen`s SkyLight on macOS 26 and notes that `SLSWindowIteratorGetAttributes` always returns `0` as of 26.3. That is unrelated to alpha, but it confirms the framework is still the right place to look.
- ShiftPlus (July 2026) reports that several SkyLight **space-move** writes fail silently under SIP on macOS 15 and 26. Alpha may be in the same bucket.
- displaydeck / yabai still implement *other-app* transparency by injecting a payload into Dock and calling `SLSSetWindowAlpha` there. That requires SIP off + `arm64e` preview ABI. Ghost Window does **not** inject into Dock.

## Observed / expected behaviour

| Case | Expected |
| --- | --- |
| Symbols missing | SkyLight backend `isUsable == false` → overlay if Screen Recording allowed |
| `SLSSetWindowAlpha` returns non-zero | treat as failure → overlay |
| Call returns 0 but `SLSGetWindowAlpha` / `kCGWindowAlpha` still ~1.0 | `alphaNotApplied` → overlay |
| Own windows | almost certainly works (same connection owns the window) |
| Other apps, SIP on | **the open question**. App verifies; does not assume success |
| Fullscreen space | may be ignored by WindowServer. No overlay fake-fullscreen |
| Secondary display | window IDs are global; CGWindow bounds are used |
| Menu bar / Dock / Control Center | excluded before any SkyLight call |

## Failure modes

1. `dlopen` fails — framework path changed (unlikely).
2. `dlsym` fails — symbol renamed; add the new name.
3. Wrong ABI (`float` vs `CGFloat`, `Int32` vs `UInt32`) — crash. If a macOS update changes this, fix the typealias in `SkyLightBridge`.
4. Silent no-op under SIP — read-back catches it.
5. Transaction function present but wrong signature — we fall back to the direct `SLSSetWindowAlpha` if transaction apply returns false; a wrong signature can still crash. Transactions are attempted first only when create+commit+set symbols all load.
6. Leaving windows faded after `kill -9` — originals are written to `~/Library/Application Support/GhostWindow/ghosted-windows.json` and restored on next launch.

## How to re-discover after an update

```bash
./scripts/discover-skylight.sh
```

Useful extra commands on a Mac:

```bash
nm -gU /System/Library/PrivateFrameworks/SkyLight.framework/SkyLight \
  | grep -E 'WindowAlpha|WindowOpacity|TransactionSetWindow'

strings /System/Library/PrivateFrameworks/SkyLight.framework/SkyLight \
  | grep -E 'SLSSetWindowAlpha|SLSSetWindowOpacity'

# if you have the SDK
grep SLSSetWindowAlpha "$SDKROOT/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight.tbd"
```

On modern macOS the SkyLight Mach-O is often **only in the dyld shared cache**. `nm` on `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight` can fail even though `dlopen`/`dlsym` succeed. Ghost Window and `scripts/discover-skylight.sh` treat `dlsym` as the source of truth.

## Proof of concept (on a Mac)

Minimal sequence once Accessibility is granted:

1. Resolve focused `CGWindowID`.
2. `cid = SLSMainConnectionID()`.
3. `SLSSetWindowOpacity(cid, wid, false)`.
4. `SLSSetWindowAlpha(cid, wid, 0.5)`.
5. `SLSGetWindowAlpha(cid, wid, &alpha)` and/or read `kCGWindowAlpha`.

Ghost Window is that sequence plus restore, exclusions, and a global hotkey.

## Permissions

| Permission | SkyLight path | Overlay fallback |
| --- | --- | --- |
| Accessibility | **required** (identify window) | required |
| Screen Recording | **not** requested | required |
| Input Monitoring | not used | not used |
| Full Disk Access | not used | not used |
