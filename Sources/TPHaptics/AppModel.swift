import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let actuator = TrackpadActuator.shared
    let player = PatternPlayer()          // user-triggered playback
    let notifPlayer = PatternPlayer()     // notification buzzes (independent)
    private let watcher = NotificationWatcher()
    private let defaults = UserDefaults.standard
    private let notifDelegate = BannerDelegate()

    // MARK: Strength

    /// 0 = off … 1 = Max Power of Actuator.
    @Published var strength: Double {
        didSet { actuator.strength = strength; defaults.set(strength, forKey: "strength") }
    }

    // MARK: System trackpad settings

    @Published private(set) var silentClicking = TrackpadSettings.silentClicking
    @Published private(set) var forceClickEnabled = TrackpadActuator.shared.forceClickEnabled ?? TrackpadSettings.forceClickPreference
    @Published var settingsMessage: String?

    var canToggleForceClick: Bool { actuator.canToggleForceClick }

    func setSilentClicking(_ on: Bool) {
        TrackpadSettings.setSilentClicking(on)
        silentClicking = TrackpadSettings.silentClicking
        settingsMessage = silentClicking == on
            ? "Silent Clicking \(on ? "on" : "off"). If your clicks don't change right away, log out and back in."
            : "macOS didn't accept the change."
    }

    func setForceClickEnabled(_ on: Bool) {
        let r = actuator.setForceClickEnabled(on)
        TrackpadSettings.setForceClickPreference(on)
        forceClickEnabled = actuator.forceClickEnabled ?? on
        settingsMessage = (r == 0 || r == -1) && forceClickEnabled == on
            ? nil
            : "Force Click switch returned 0x\(String(UInt32(bitPattern: r), radix: 16))."
    }

    /// Re-read both settings (they can also be changed in System Settings).
    func refreshSystemSettings() {
        silentClicking = TrackpadSettings.silentClicking
        forceClickEnabled = actuator.forceClickEnabled ?? TrackpadSettings.forceClickPreference
    }

    // MARK: Buzz

    /// Each actuation blocks for ~4–6 ms while the actuator plays the click, so
    /// anything below that simply runs at the hardware's top speed.
    static let minBuzzIntervalMS = 1.0
    static let maxBuzzIntervalMS = 1000.0

    @Published var buzzIntervalMS: Double { didSet { defaults.set(buzzIntervalMS, forKey: "buzzIntervalMS") } }
    @Published var buzzDuration: Double   { didSet { defaults.set(buzzDuration, forKey: "buzzDuration") } }
    @Published var buzzContinuous: Bool   { didSet { defaults.set(buzzContinuous, forKey: "buzzContinuous") } }

    /// A train of max-strength taps `buzzIntervalMS` apart.
    /// Continuous mode is a single tap that the player loops.
    func buzzPattern(forceFinite: Bool = false) -> HapticPattern {
        let interval = Swift.max(Self.minBuzzIntervalMS, buzzIntervalMS) / 1000
        let max = Strength.max.id
        if buzzContinuous && !forceFinite {
            return HapticPattern(name: "Buzz", detail: "",
                                 events: [.init(time: 0, actuation: max)], length: interval)
        }
        let duration = forceFinite && buzzContinuous ? 1.0 : buzzDuration
        let n = Swift.max(1, Int(duration / interval))
        return HapticPattern(name: "Buzz", detail: "",
                             events: (0..<n).map { .init(time: Double($0) * interval, actuation: max) },
                             length: Double(n) * interval)
    }

    // MARK: Notifications

    static let customBuzzName = "Custom Buzz (from Buzz tab)"

    @Published var notifyEnabled: Bool {
        didSet {
            defaults.set(notifyEnabled, forKey: "notifyEnabled")
            notifyEnabled ? startWatching() : stopWatching()
        }
    }
    @Published var notifyPatternName: String { didSet { defaults.set(notifyPatternName, forKey: "notifyPattern") } }
    @Published private(set) var notifyStatus = "Off"
    @Published private(set) var accessibilityTrusted = NotificationWatcher.isTrusted
    @Published var testNotificationMessage: String?

    static let silentName = "(silent)"

    var notifyPatternChoices: [String] { allPatternNames + [Self.customBuzzName] }

    // MARK: Pattern lookup (presets and saved patterns)

    var allPatternNames: [String] {
        Presets.all.map(\.name) + PatternLibrary.shared.patterns.map(\.name)
    }

    func pattern(named name: String) -> HapticPattern? {
        func same(_ a: String) -> Bool { a.caseInsensitiveCompare(name) == .orderedSame }
        if let p = Presets.all.first(where: { same($0.name) }) { return p }
        if let u = PatternLibrary.shared.patterns.first(where: { same($0.name) }) { return u.pattern }
        return nil
    }

    /// Like `pattern(named:)` but understands the Buzz-tab pseudo pattern and falls back to Double Tap.
    func resolvePattern(_ name: String) -> HapticPattern {
        if name == Self.customBuzzName { return buzzPattern(forceFinite: true) }
        return pattern(named: name) ?? Presets.doubleTap
    }

    func notificationPattern() -> HapticPattern { resolvePattern(notifyPatternName) }

    // MARK: Per-app / per-keyword rules

    @Published var rules: [NotificationRule] = [] {
        didSet { if let d = try? JSONEncoder().encode(rules) { defaults.set(d, forKey: "notifyRules") } }
    }
    @Published private(set) var recentNotifications: [SeenNotification] = []

    /// Called with the text found in a banner (app name, title, body…) shortly after it appears.
    func handleNotification(_ texts: [String]) {
        let haystack = texts.joined(separator: "\n").lowercased()
        let rule = rules.first { $0.enabled && !$0.match.isEmpty && haystack.contains($0.match.lowercased()) }
        recentNotifications.insert(SeenNotification(date: Date(), texts: texts, matchedRule: rule?.match), at: 0)
        if recentNotifications.count > 10 { recentNotifications.removeLast() }
        let name = rule?.patternName ?? notifyPatternName
        Diag.log("notification texts=\(texts) rule=\(rule?.match ?? "-") pattern=\(name)")
        guard name != Self.silentName else { return }
        notifPlayer.play(resolvePattern(name), loop: false)
    }

    func previewRule(_ rule: NotificationRule) {
        guard rule.patternName != Self.silentName else { return }
        notifPlayer.play(resolvePattern(rule.patternName), loop: false)
    }

    func previewNotificationBuzz() { notifPlayer.play(notificationPattern(), loop: false) }

    func requestAccessibility() { NotificationWatcher.requestTrust() }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Posts a real banner from this app, to exercise the whole detection path.
    func sendTestNotification() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = notifDelegate
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                guard granted else {
                    self.testNotificationMessage = "Notifications for TPHaptics are not allowed (System Settings → Notifications)."
                    return
                }
                self.testNotificationMessage = "Sent. The buzz fires when the banner appears."
                let c = UNMutableNotificationContent()
                c.title = "TPHaptics test"
                c.body = "If your trackpad buzzed, notification detection works."
                try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
            }
        }
    }

    private func startWatching() {
        watcher.onNotification = { [weak self] texts in
            Task { @MainActor in self?.handleNotification(texts) }
        }
        watcher.onStatus = { [weak self] text in
            Task { @MainActor in self?.notifyStatus = text }
        }
        watcher.start()
    }

    private func stopWatching() {
        watcher.stop()
        notifyStatus = "Off"
    }

    // MARK: Init

    private init() {
        let d = UserDefaults.standard
        strength = d.object(forKey: "strength") as? Double ?? 1.0
        buzzIntervalMS = d.object(forKey: "buzzIntervalMS") as? Double ?? 50
        buzzDuration = d.object(forKey: "buzzDuration") as? Double ?? 2
        buzzContinuous = d.object(forKey: "buzzContinuous") as? Bool ?? false
        notifyEnabled = d.object(forKey: "notifyEnabled") as? Bool ?? false
        notifyPatternName = d.string(forKey: "notifyPattern") ?? Presets.doubleTap.name
        actuator.strength = strength
        if let data = d.data(forKey: "notifyRules"),
           let saved = try? JSONDecoder().decode([NotificationRule].self, from: data) {
            rules = saved
        }

        if notifyEnabled { startWatching() }

        // Keep the permission badge fresh while the user is in System Settings.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.accessibilityTrusted = NotificationWatcher.isTrusted
                self?.refreshSystemSettings()
            }
        }
    }
}

/// "If a notification mentions `match`, play `patternName`."
struct NotificationRule: Codable, Identifiable, Hashable {
    var id = UUID()
    var match: String
    var patternName: String
    var enabled = true
}

struct SeenNotification: Identifiable {
    let id = UUID()
    let date: Date
    let texts: [String]
    let matchedRule: String?
}

/// Lets banners show even while TPHaptics is the frontmost app.
final class BannerDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
