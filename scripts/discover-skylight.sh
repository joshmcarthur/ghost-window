#!/bin/bash
# Discover SkyLight / CGS window-opacity symbols on a Mac.
# On modern macOS the SkyLight Mach-O often lives only in the dyld shared
# cache, so a missing on-disk binary is normal. dlopen/dlsym still works.
set -u

FRAMEWORK="/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
VERSIONED="/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
HI_SERVICES="/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
echo "arch: $(uname -m)"
echo

echo "== framework paths =="
ls -la /System/Library/PrivateFrameworks/SkyLight.framework 2>/dev/null || echo "SkyLight.framework directory not visible"
echo

TARGET=""
if [[ -e "$FRAMEWORK" ]]; then
  TARGET="$FRAMEWORK"
elif [[ -e "$VERSIONED" ]]; then
  TARGET="$VERSIONED"
fi

if [[ -n "$TARGET" ]]; then
  echo "on-disk image: $TARGET"
  echo "file: $(file "$TARGET" 2>/dev/null || true)"
  echo
  echo "== opacity / alpha symbols (nm) =="
  nm -gU "$TARGET" 2>/dev/null | awk '{print $NF}' | grep -E 'WindowAlpha|WindowOpacity|SetWindowOpaque|TransactionSetWindow' || echo "(nm produced no matches — image may be a stub)"
  echo
  echo "== otool dylib id =="
  otool -D "$TARGET" 2>/dev/null || true
  echo
else
  echo "No on-disk SkyLight Mach-O (expected on macOS 13+; image is in the dyld shared cache)."
  echo
fi

if command -v dyld_info >/dev/null 2>&1 || xcrun --find dyld_info >/dev/null 2>&1; then
  echo "== dyld_info exports (shared cache aware) =="
  xcrun dyld_info -exports "${TARGET:-$FRAMEWORK}" 2>/dev/null \
    | grep -E 'WindowAlpha|WindowOpacity|SetWindowOpaque|TransactionSetWindow' \
    || echo "(dyld_info produced no matches)"
  echo
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
TBD_PATHS=(
  "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight.tbd"
  "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight.tbd"
)
if [[ -n "$SDK_PATH" ]]; then
  TBD_PATHS+=("$SDK_PATH/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight.tbd")
fi

found_tbd=0
for tbd in "${TBD_PATHS[@]}"; do
  if [[ -f "$tbd" ]]; then
    found_tbd=1
    echo "== TBD: $tbd =="
    grep -E 'SLSSetWindowAlpha|CGSSetWindowAlpha|SLSSetWindowOpacity|SLSGetWindowAlpha|SLSTransactionSetWindowAlpha|_AXUIElementGetWindow' "$tbd" || true
    echo
  fi
done
if [[ "$found_tbd" -eq 0 ]]; then
  echo "No SkyLight.tbd in the public SDK (typical; the framework is private)."
  echo
fi

if [[ -e "$HI_SERVICES" ]]; then
  echo "== HIServices _AXUIElementGetWindow (nm) =="
  nm -gU "$HI_SERVICES" 2>/dev/null | awk '{print $NF}' | grep '_AXUIElementGetWindow' || echo "not in on-disk nm"
  echo
fi

echo "== dlopen / dlsym probe (source of truth) =="
PROBE="$(mktemp -t ghost-window-skylight-probe)"
trap 'rm -f "$PROBE"' EXIT
cc -o "$PROBE" "$SCRIPT_DIR/probe-skylight.c" || exit 1
"$PROBE"
status=$?

echo
if [[ "$status" -eq 0 ]]; then
  echo "Done. SLS/CGS window-alpha symbols resolved. Compare names with SkyLightBridge.swift."
else
  echo "Done. Required symbols did not resolve."
fi
exit "$status"
