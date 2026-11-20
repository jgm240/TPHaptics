import Foundation

/// The two system trackpad preferences that soften or remove click haptics.
/// These are real System Settings → Trackpad values; changing them affects
/// every app, not just TPHaptics.
enum TrackpadSettings {
    private static let trackpadDomain = "com.apple.AppleMultitouchTrackpad" as CFString
    private static let forceClickKey = "com.apple.trackpad.forceClick" as CFString

    // MARK: Silent Clicking  (ActuationStrength: 0 = silent, 1 = normal)

    static var silentClicking: Bool {
        let v = CFPreferencesCopyAppValue("ActuationStrength" as CFString, trackpadDomain)
        return (v as? NSNumber)?.intValue == 0
    }

    static func setSilentClicking(_ on: Bool) {
        CFPreferencesSetValue("ActuationStrength" as CFString,
                              NSNumber(value: on ? 0 : 1) as CFNumber,
                              trackpadDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(trackpadDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        TrackpadActuator.shared.recacheProperties()
    }

    // MARK: Tap to Click (read only)

    /// Whether System Settings has Tap to Click on for the built-in trackpad.
    static var tapToClick: Bool {
        let v = CFPreferencesCopyAppValue("Clicking" as CFString, trackpadDomain)
        return (v as? NSNumber)?.boolValue ?? false
    }

    // MARK: Force Click & haptic feedback

    /// Persists the Force Click preference. The live switch is on `TrackpadActuator`.
    static var forceClickPreference: Bool {
        let v = CFPreferencesCopyAppValue(forceClickKey, kCFPreferencesAnyApplication)
        return (v as? NSNumber)?.boolValue ?? true
    }

    static func setForceClickPreference(_ on: Bool) {
        CFPreferencesSetValue(forceClickKey, NSNumber(value: on) as CFBoolean,
                              kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}
