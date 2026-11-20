# TPHaptics

Play haptic patterns on a Mac trackpad, **without a finger on it**.

TPHaptics drives the Taptic Engine directly through the private `MultitouchSupport` framework
(`MTActuator*`), so it can buzz the trackpad on its own, unlike the public `NSHapticFeedbackManager`,
which only works while you're touching the trackpad.

> **Private API.** The symbols are looked up at runtime with `dlsym`. Apple can change or remove them in
> any macOS release, and the app can't ship on the App Store. If they're missing it falls back to the
> public API (finger required). Developed and tested on macOS 26 with a built-in Force Touch trackpad.

**Website:** <https://jgm240.github.io/TPHaptics/> (try the patterns from your browser, install IPHaptics)

> **On iPhone?** See [IPHaptics](IPHaptics/), a port built on Core Haptics (public APIs), with an unsigned IPA on the
> [Releases](https://github.com/jgm240/TPHaptics/releases) page.

## What it does

- **Patterns, sequencer, pattern editor** – built-in patterns, a 16-step grid, and a timeline editor with save/import/export
- **Buzz** – a steady click train with a custom interval (1 ms to 1 s); the actuator tops out around 175–250 clicks/s
- **Strength slider** – Off to "Max Power of Actuator"
- **Notifications** – buzz on banners, with per-app/keyword rules (needs Accessibility permission)
- **Automations** – charger, low battery, hourly chime, countdown, calendar reminders
- **Audio to haptics** – microphone hit detection across bass, mids and highs, or a loudness-following tap rate
- **Morse**, **breathing guide**, **games** (Simon, Hot & Cold, Rhythm Echo)
- **Feel Pad** – press and drag on a pad: up is stronger (the six click levels), right is faster (from a slow thump to a continuous buzz)
- **Typing & scroll** – taps per key, word or sentence; modifier and Caps Lock clicks; scroll notches (vertical and sideways), direction bumps; pinch, rotate and swipe steps
- **Feel the screen** – grid lines, window edges, screen edges and corners, display crossings, center lines, a pointer-speed ratchet, click echo, and a different tap for buttons, links, fields and menus under the pointer
- **Silent Clicking / Force Click** switches for the system trackpad settings
- **Triggers from anywhere** – `tphaptics://` links and a `tphaptics` shell command

## Build

Requires Xcode command line tools (Swift 5.9+), macOS 13+.

```sh
./build.sh          # builds and signs build/TPHaptics.app
open build/TPHaptics.app
```

Use `./run.sh` (build, then relaunch the app) rather than `swift run`: macOS can only grant Accessibility
to a signed app bundle, never to a loose executable. If the app says Accessibility isn't granted
even though you enabled it, remove any stale TPHaptics entry in System Settings → Privacy & Security →
Accessibility (or run `tccutil reset Accessibility com.tphaptics.app`), then press **Request Access…**
on the Notifications screen. The Notifications screen also shows which copy you're running and how it's signed.

`build.sh` signs with an Apple Development / Developer ID identity if one is in your keychain (set
`SIGN_IDENTITY` to choose one, or `-` for ad-hoc). A stable signature matters: macOS ties the
Accessibility permission to the app's signature, and an ad-hoc signature changes on every build.

The app icon is drawn in SwiftUI (`Sources/TPHaptics/AppIcon.swift`); run `./make-icon.sh` after
changing it to regenerate `Resources/AppIcon.icns`, which `build.sh` bundles.

## Triggers

```text
tphaptics://play?pattern=Heartbeat&loop=1
tphaptics://morse?text=hello&wpm=15
tphaptics://buzz?interval=20&duration=2
tphaptics://breathe?cycles=4
tphaptics://countdown?minutes=5
tphaptics://strength?value=0.6
tphaptics://stop
```

To try one from the terminal, **quote the link**: zsh treats `?` as a wildcard and `&` as "run in the background".

```sh
open "tphaptics://buzz?interval=20&duration=2"
```

The **Shortcuts & CLI** screen installs a `tphaptics` command that wraps these with no quoting needed, e.g.
`tphaptics buzz 20 2` or `make && tphaptics play Heartbeat`.

## Hardware notes

- Actuation IDs 1–6 click; 7–20 are accepted but silent on the machine this was built on.
- Each click blocks for roughly 4–6 ms, which sets the maximum click rate.
- `MTActuatorSetSystemActuationsEnabled` (disabling the trackpad's own click haptic) is refused with
  `kIOReturnNotPermitted`, even as root, so there is no "disable click haptics" switch.

## Disclaimer

TPHaptics is an independent project and is not affiliated with or endorsed by Apple. It contains no Apple
code. It calls undocumented functions that already exist on your Mac, found by listing the framework's
exported symbol names and probing them; nothing is copied, decrypted or bypassed. Apple's own guidance is
that private APIs are unsupported and can change at any time, so use it at your own risk.

## License

[MIT](LICENSE)

## Self-tests

```sh
build/TPHaptics.app/Contents/MacOS/TPHaptics --selftest --selftest-features
```

Other flags: `--selftest-speed`, `--selftest-player`, `--selftest-settings`, `--selftest-notify`,
`--snapshot-dir <path>` (renders every screen to PNG).
