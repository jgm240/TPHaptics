#!/bin/zsh
# Regenerates Resources/AppIcon.icns from the SwiftUI icon in Sources/TPHaptics/AppIcon.swift.
# Needs a built app first (./build.sh). build.sh then bundles the icon automatically.
set -euo pipefail
cd "$(dirname "$0")"

BIN="$(swift build -c release --show-bin-path)/TPHaptics"
SET="$(mktemp -d)/AppIcon.iconset"
"$BIN" --selftest --render-icon "$SET" >/dev/null
mkdir -p Resources
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
