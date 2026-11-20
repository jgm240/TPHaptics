**IPHaptics** is TPHaptics for iPhone, built on Apple's public Core Haptics framework.

This is an **unsigned IPA**. iOS won't run it directly: sign and install it with a sideloading tool that uses
your own Apple ID or certificate (AltStore, Sideloadly, SideStore, or TrollStore on supported versions).
Needs an iPhone 8 or later on iOS 16+. Haptics only play while the app is open on screen.

### New in 1.1: Shortcuts and Siri
- **Shortcuts actions:** Play Pattern (built-in patterns and saved paintings), Get Patterns (pick one with
  "Choose from List" to make your own buttons), Play Morse, Buzz, Feel Point (vibrate at a chosen intensity and
  sharpness, so you can build your own Feel Pad), Start Breathing Guide, Set Strength, Stop Haptics, Open Screen
  and Open Feel Pad.
- **Siri phrases**, such as "Play Heartbeat in IPHaptics".
- **Links:** `iphaptics://open?screen=pad` opens a screen and `iphaptics://feel?intensity=70&sharpness=50&seconds=2`
  vibrates at one pad point, for Shortcuts' "Open URLs" action.
- Actions that vibrate open the app first, since iOS only allows haptics while an app is on screen.

### In 1.0 and 1.1
Eleven patterns including smooth swells and rumbles, a 16-step sequencer, a Paint screen where the height of a line
you draw becomes vibration strength, a continuous hum you can reshape live, a Feel Pad, Morse, a breathing guide,
microphone-to-haptics (bass, mids, highs or loudness), and three games.

Not tested on a physical iPhone before release: it was built and checked by CI only, including that Xcode extracts
all ten Shortcuts actions. Please report anything that doesn't feel right at
https://github.com/jgm240/TPHaptics/issues.
