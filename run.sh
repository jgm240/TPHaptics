#!/bin/zsh
# Builds TPHaptics.app and (re)launches it. Always use this (or `open build/TPHaptics.app`) rather
# than `swift run`: macOS can only grant Accessibility to a signed app bundle, not a loose executable.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
pkill -x TPHaptics 2>/dev/null || true      # stops any older copy, including a bare `swift run` binary
sleep 1
open build/TPHaptics.app
echo "Launched build/TPHaptics.app"
