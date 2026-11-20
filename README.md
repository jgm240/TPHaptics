# TPHaptics

Play haptic patterns on a Mac trackpad, **without a finger on it**.

TPHaptics drives the Taptic Engine directly through the private `MultitouchSupport` framework
(`MTActuator*`), so it can buzz the trackpad on its own, unlike the public `NSHapticFeedbackManager`,
which only works while you're touching the trackpad.

> **Private API.** The symbols are looked up at runtime with `dlsym`. Apple can change or remove them in
> any macOS release, and the app can't ship on the App Store. If they're missing it falls back to the
> public API (finger required). Developed and tested on macOS 26 with a built-in Force Touch trackpad.

## What it does

- **Patterns, sequencer, pattern editor** – built-in patterns, a 16-step grid, and a timeline editor with save/import/export
- **Buzz** – a steady click train with a custom interval (1 ms to 1 s); the actuator tops out around 175–250 clicks/s
- **Strength slider** – Off to "Max Power of Actuator"
- **Notifications** – buzz on banners, with per-app/keyword rules (needs Accessibility permission)
- **Automations** – charger, low battery, hourly chime, countdown, calendar reminders
- **Audio to haptics** – microphone beat detection
- **Morse**, **breathing guide**, **games** (Simon, Hot & Cold, Rhythm Echo)
- **Typing, scroll and screen feel** – taps for keystrokes, scroll notches, grid lines, window and screen edges
- **Silent Clicking / Force Click** switches for the system trackpad settings
- **Triggers from anywhere** – `tphaptics://` links and a `tphaptics` shell command

## Build

Requires Xcode command line tools (Swift 5.9+), macOS 13+.

```sh
./build.sh          # builds and signs build/TPHaptics.app
open build/TPHaptics.app
```

`build.sh` signs with an Apple Development / Developer ID identity if one is in your keychain (set
`SIGN_IDENTITY` to choose one, or `-` for ad-hoc). A stable signature matters: macOS ties the
Accessibility permission to the app's signature, and an ad-hoc signature changes on every build.

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

The **Shortcuts & CLI** screen installs a `tphaptics` command that wraps these, e.g.
`make && tphaptics play Heartbeat`.

## Hardware notes

- Actuation IDs 1–6 click; 7–20 are accepted but silent on the machine this was built on.
- Each click blocks for roughly 4–6 ms, which sets the maximum click rate.
- `MTActuatorSetSystemActuationsEnabled` (disabling the trackpad's own click haptic) is refused with
  `kIOReturnNotPermitted`, even as root, so there is no "disable click haptics" switch.

## Self-tests

```sh
build/TPHaptics.app/Contents/MacOS/TPHaptics --selftest --selftest-features
```

Other flags: `--selftest-speed`, `--selftest-player`, `--selftest-settings`, `--selftest-notify`,
`--snapshot-dir <path>` (renders every screen to PNG).
