#!/bin/zsh
# Builds TPHaptics.app with Xcode so its Shortcuts actions (Play Pattern, Feel Pad Point, Open Feel Pad…)
# show up in the Shortcuts app. Needs Xcode (not just the command line tools) and XcodeGen:
#   brew install xcodegen
# The result replaces build/TPHaptics.app, so ./run.sh-style launching still works.
set -euo pipefail
cd "$(dirname "$0")"

command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }
xcodebuild -version >/dev/null 2>&1 || { echo "This needs Xcode (the full app), not just the command line tools."; exit 1; }

( cd Mac && xcodegen generate )

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development|Developer ID Application/ {print $2; exit}')}"
IDENTITY="${IDENTITY:--}"

xcodebuild -project Mac/TPHaptics.xcodeproj -scheme TPHaptics -configuration Release \
  -derivedDataPath build/xcode CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual build 2>&1 | tail -n 5

rm -rf build/TPHaptics.app
cp -R build/xcode/Build/Products/Release/TPHaptics.app build/TPHaptics.app
echo "Built build/TPHaptics.app with Shortcuts actions. Open it once, then look in the Shortcuts app under TPHaptics."
