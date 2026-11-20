# IPHaptics

TPHaptics for iPhone. It plays haptic patterns on the iPhone's Taptic Engine, using Apple's public
**Core Haptics** framework (no private APIs).

Compared with the Mac app, the iPhone's motor is far more capable: instead of six fixed click strengths
it has continuous **intensity** and **sharpness**, and it can run as a true continuous vibration. IPHaptics
uses that throughout.

**Website:** <https://jgm240.github.io/TPHaptics/#iphone>

## Screens

- **Patterns**: eleven built-in patterns (taps, heartbeat, a smooth swell, an engine rumble…) plus your own
- **Sequencer**: a 16-step grid of taps
- **Paint**: draw a line; left to right is time, height is strength. *Smooth* turns the line into one continuous
  vibration that follows it, *Taps* samples it into ticks. You feel the strength under your finger as you paint,
  and can save paintings to Patterns
- **Buzz**: rapid taps with a custom interval, or a continuous hum you can reshape while it runs
- **Feel Pad**: slide a finger; up is stronger, right is crisper
- **Breathing**: a swell-and-fade guide with an on-screen circle
- **Morse**: text as short and long vibrations
- **Audio to Haptics**: microphone hit detection across bass, mids and highs, or a continuous vibration that
  follows loudness
- **Games**: Simon, Hot & Cold, Rhythm Echo
- **Strength** slider and **Stop** are always at the bottom

`iphaptics://play?pattern=Heartbeat&loop=1`, `iphaptics://morse?text=hello`, `iphaptics://stop` and
`iphaptics://strength?value=0.6` work from Shortcuts ("Open URLs") and other apps.

## Shortcuts and Siri

IPHaptics adds Shortcuts actions: **Play Pattern** (built-in and saved paintings), **Get Patterns** (pick one with
"Choose from List" to make your own buttons), **Play Morse**, **Buzz**, **Feel Point** (vibrate at a chosen intensity and
sharpness: build your own Feel Pad from several), **Start Breathing Guide**, **Set Strength**, **Stop Haptics**,
**Open Screen** and **Open Feel Pad**, plus Siri phrases such as "Play Heartbeat in IPHaptics". Actions that vibrate open
the app first, because iOS only allows haptics while an app is on screen.

Links work too: `iphaptics://open?screen=pad` and `iphaptics://feel?intensity=70&sharpness=50&seconds=2`.

## Limits

- **Foreground only.** iOS only lets an app vibrate while it's open on screen, so there's no buzzing in the
  background, on notifications, or for typing in other apps (the things the Mac app does).
- **iPhone 8 or later.** iPads and the Simulator have no Taptic Engine; the app opens but nothing vibrates.
- Haptics are muted when **Low Power Mode** is on or **System Haptics** is off in Settings → Sounds & Haptics.

## Install the unsigned IPA

The release IPA is **unsigned**, so iOS won't run it as is. Sign and install it with a sideloading tool that uses
your own Apple ID or certificate, for example AltStore, Sideloadly or SideStore (or TrollStore on supported iOS
versions). Free Apple IDs expire the install after 7 days; the tool can refresh it.

Download `IPHaptics-unsigned.ipa` from the
[Releases](https://github.com/jgm240/TPHaptics/releases) page.

## Build it yourself

You need a Mac with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
cd IPHaptics
xcodegen generate
open IPHaptics.xcodeproj          # then run on a device with your own signing team
```

Or produce an unsigned IPA from the command line:

```sh
xcodebuild -project IPHaptics.xcodeproj -scheme IPHaptics -sdk iphoneos -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
mkdir Payload && cp -R build/Build/Products/Release-iphoneos/IPHaptics.app Payload/
zip -qry IPHaptics-unsigned.ipa Payload
```

The repository's GitHub Actions workflow (`.github/workflows/iphaptics-ipa.yml`) does exactly this on a macOS
runner and attaches the IPA to a release whenever a tag like `iphaptics-v1.0` is pushed.

The icon is drawn in SwiftUI by `Tools/make-icon.swift` (run it on a Mac to regenerate the PNG).

## Licence

[MIT](../LICENSE), like TPHaptics. Not affiliated with Apple.
