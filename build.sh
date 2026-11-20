#!/bin/zsh
# Builds TPHaptics.app (ad-hoc signed, not sandboxed — required for the private actuator API).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/TPHaptics"

APP="build/TPHaptics.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TPHaptics"

[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.tphaptics.app</string>
    <key>CFBundleName</key><string>TPHaptics</string>
    <key>CFBundleDisplayName</key><string>TPHaptics</string>
    <key>CFBundleExecutable</key><string>TPHaptics</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSUserNotificationAlertStyle</key><string>banner</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>com.tphaptics.app</string>
            <key>CFBundleURLSchemes</key><array><string>tphaptics</string></array>
        </dict>
    </array>
    <key>NSMicrophoneUsageDescription</key><string>TPHaptics listens for beats in the sound around you so it can tap them out on the trackpad. Audio is analysed live and never recorded or stored.</string>
    <key>NSCalendarsUsageDescription</key><string>TPHaptics buzzes your trackpad shortly before calendar events start.</string>
    <key>NSCalendarsFullAccessUsageDescription</key><string>TPHaptics buzzes your trackpad shortly before calendar events start.</string>
</dict>
</plist>
PLIST

# Sign with a real identity when one exists: it gives the app a stable identity, so
# macOS keeps the Accessibility permission across rebuilds (an ad-hoc signature changes
# every build and silently revokes it). Override with SIGN_IDENTITY="..."; "-" = ad-hoc.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development|Developer ID Application/ {print $2; exit}')}"
IDENTITY="${IDENTITY:--}"
codesign --force --sign "$IDENTITY" "$APP"
if [[ "$IDENTITY" == "-" ]]; then
    echo "Signed ad-hoc: Accessibility permission must be re-granted after every rebuild."
else
    echo "Signed with a stable identity: Accessibility permission survives rebuilds."
fi
echo "Built $APP"
