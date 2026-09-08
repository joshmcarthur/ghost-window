#!/bin/bash
# Discover SkyLight / CGS window-opacity symbols on a Mac.
# Run this after a macOS update to see whether Ghost Window's private API
# names still exist.
set -euo pipefail

FRAMEWORK="/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
VERSIONED="/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
TBD_PATHS=(
  "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight.tbd"
  "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight.tbd"
)
HI_SERVICES="/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices"

echo "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
echo "arch: $(uname -m)"
echo

if [[ -f "$FRAMEWORK" ]]; then
  TARGET="$FRAMEWORK"
elif [[ -f "$VERSIONED" ]]; then
  TARGET="$VERSIONED"
else
  echo "SkyLight binary not found."
  exit 1
fi

echo "framework: $TARGET"
echo "file: $(file "$TARGET")"
echo

echo "== opacity / alpha symbols (nm) =="
nm -gU "$TARGET" 2>/dev/null | awk '{print $NF}' | grep -E 'WindowAlpha|WindowOpacity|SetWindowOpaque|TransactionSetWindow' || true
echo

echo "== candidate names (strings) =="
strings -a "$TARGET" | grep -E '^(SLS|CGS|_CGS).*Window(Alpha|Opacity)|_AXUIElementGetWindow' | sort -u || true
echo

echo "== otool dylib id =="
otool -D "$TARGET" || true
echo

for tbd in "${TBD_PATHS[@]}"; do
  if [[ -f "$tbd" ]]; then
    echo "== TBD: $tbd =="
    grep -E 'SLSSetWindowAlpha|CGSSetWindowAlpha|SLSSetWindowOpacity|SLSGetWindowAlpha|SLSTransactionSetWindowAlpha|_AXUIElementGetWindow' "$tbd" || true
    echo
  fi
done

if [[ -f "$HI_SERVICES" ]]; then
  echo "== HIServices _AXUIElementGetWindow =="
  nm -gU "$HI_SERVICES" 2>/dev/null | awk '{print $NF}' | grep '_AXUIElementGetWindow' || echo "missing"
fi

echo
echo "Done. Compare the printed names with SkyLightBridge.swift."
