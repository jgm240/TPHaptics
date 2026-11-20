import AppIntents
import AppKit

// Shortcuts actions for TPHaptics.
//
// These only appear in the Shortcuts app when the app is built with Xcode (build-xcode.sh), because
// Xcode is what extracts the metadata Shortcuts reads. With the plain ./build.sh build they compile but stay
// invisible; the tphaptics:// links (Shortcuts' "Open URLs" action) cover the same ground there.

enum ShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case message(String)
    var localizedStringResource: LocalizedStringResource {
        switch self { case .message(let m): return "\(m)" }
    }
}

// MARK: - Patterns as a pick-list

struct PatternEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Pattern"
    static let defaultQuery = PatternQuery()
    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

/// Every built-in pattern plus the user's saved ones, so "custom buttons" can be built from a list.
struct PatternQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PatternEntity] {
        await MainActor.run { identifiers.filter { AppModel.shared.pattern(named: $0) != nil }.map { PatternEntity(id: $0) } }
    }
    func entities(matching string: String) async throws -> [PatternEntity] {
        await MainActor.run {
            AppModel.shared.allPatternNames.filter { $0.localizedCaseInsensitiveContains(string) }.map { PatternEntity(id: $0) }
        }
    }
    func suggestedEntities() async throws -> [PatternEntity] {
        await MainActor.run { AppModel.shared.allPatternNames.map { PatternEntity(id: $0) } }
    }
}

// MARK: - Screens

enum ScreenOption: String, AppEnum {
    case patterns, sequencer, paint, editor, buzz, pad, notifications, automations, audio, morse, breathe, games, typing, screen

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Screen"
    static let caseDisplayRepresentations: [ScreenOption: DisplayRepresentation] = [
        .patterns: "Patterns", .sequencer: "Sequencer", .paint: "Paint", .editor: "Pattern Editor", .buzz: "Buzz",
        .pad: "Feel Pad", .notifications: "Notifications", .automations: "Automations", .audio: "Audio to Haptics",
        .morse: "Morse", .breathe: "Breathing", .games: "Games", .typing: "Typing & Scroll", .screen: "Feel the Screen",
    ]
    var section: AppSection? { AppSection(rawValue: rawValue) }
}

// MARK: - Intents

struct PlayPatternIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Pattern"
    static let description = IntentDescription("Plays a haptic pattern on the trackpad, with no finger needed.")
    static var parameterSummary: some ParameterSummary { Summary("Play \(\.$pattern)") }

    @Parameter(title: "Pattern") var pattern: PatternEntity
    @Parameter(title: "Loop", default: false) var loop: Bool

    @MainActor func perform() async throws -> some IntentResult {
        guard let p = AppModel.shared.pattern(named: pattern.id) else { throw ShortcutError.message("There's no pattern called “\(pattern.id)”.") }
        AppModel.shared.player.play(p, loop: loop)
        return .result()
    }
}

struct ListPatternsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Patterns"
    static let description = IntentDescription("Returns every pattern, so you can pick one with “Choose from List” and build your own buttons.")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[PatternEntity]> {
        .result(value: AppModel.shared.allPatternNames.map { PatternEntity(id: $0) })
    }
}

struct PlayMorseIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Morse"
    static let description = IntentDescription("Feels text as Morse code on the trackpad.")
    static var parameterSummary: some ParameterSummary { Summary("Feel \(\.$text) in Morse") }

    @Parameter(title: "Text") var text: String
    @Parameter(title: "Words per minute", default: 15) var wpm: Int

    @MainActor func perform() async throws -> some IntentResult {
        guard !Morse.encode(text).isEmpty else { throw ShortcutError.message("There's nothing in that text to send in Morse.") }
        AppModel.shared.player.play(Morse.pattern(text: text, wpm: Double(min(40, max(5, wpm)))), loop: false)
        return .result()
    }
}

struct BuzzIntent: AppIntent {
    static let title: LocalizedStringResource = "Buzz"
    static let description = IntentDescription("A steady train of taps with an interval you choose.")
    static var parameterSummary: some ParameterSummary { Summary("Buzz every \(\.$intervalMS) ms for \(\.$seconds) seconds") }

    @Parameter(title: "Interval (ms)", default: 20) var intervalMS: Int
    @Parameter(title: "Seconds", default: 2.0) var seconds: Double

    @MainActor func perform() async throws -> some IntentResult {
        let interval = max(AppModel.minBuzzIntervalMS, Double(intervalMS)) / 1000
        let duration = min(60, max(0.1, seconds))
        let n = max(1, Int(duration / interval))
        let p = HapticPattern(name: "Buzz", detail: "",
                              events: (0..<n).map { HapticEvent(time: Double($0) * interval, actuation: Strength.max.id) },
                              length: Double(n) * interval)
        AppModel.shared.player.play(p, loop: false)
        return .result()
    }
}

/// A point on the Feel Pad, as an action: build your own pads and buttons out of these.
struct FeelPadPointIntent: AppIntent {
    static let title: LocalizedStringResource = "Feel Pad Point"
    static let description = IntentDescription("Buzzes at one point on the Feel Pad: speed from slow thump to fast buzz, and strength from weak to strong. Waits until it's done.")
    static var parameterSummary: some ParameterSummary { Summary("Feel \(\.$speed)% speed at \(\.$strength)% strength for \(\.$seconds) s") }

    @Parameter(title: "Speed (0–100)", default: 50) var speed: Int
    @Parameter(title: "Strength (0–100)", default: 80) var strength: Int
    @Parameter(title: "Seconds", default: 1.5) var seconds: Double

    @MainActor func perform() async throws -> some IntentResult {
        let x = Double(min(100, max(0, speed))) / 100, y = Double(min(100, max(0, strength))) / 100
        AppModel.shared.player.play(FeelPadMap.pattern(x: x, y: y), loop: true)
        try await Task.sleep(nanoseconds: UInt64(min(60, max(0.1, seconds)) * 1_000_000_000))
        if AppModel.shared.player.playingName == "Feel Pad" { AppModel.shared.player.stop() }
        return .result()
    }
}

struct SetStrengthIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Strength"
    static let description = IntentDescription("Sets the master Strength slider, from 0 (off) to 100 (Max Power of Actuator).")
    static var parameterSummary: some ParameterSummary { Summary("Set strength to \(\.$percent)%") }

    @Parameter(title: "Percent", default: 100) var percent: Int

    @MainActor func perform() async throws -> some IntentResult {
        AppModel.shared.strength = Double(min(100, max(0, percent))) / 100
        return .result()
    }
}

struct StopHapticsIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Haptics"
    static let description = IntentDescription("Stops whatever TPHaptics is playing.")

    @MainActor func perform() async throws -> some IntentResult {
        AppModel.shared.player.stop()
        AppModel.shared.notifPlayer.stop()
        Automations.shared.cancelCountdown()
        return .result()
    }
}

struct StartCountdownIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Haptic Countdown"
    static let description = IntentDescription("A soft tick each minute, faster ticks at the end, then a triple knock.")
    static var parameterSummary: some ParameterSummary { Summary("Count down \(\.$minutes) minutes") }

    @Parameter(title: "Minutes", default: 5.0) var minutes: Double

    @MainActor func perform() async throws -> some IntentResult {
        Automations.shared.startCountdown(seconds: min(180, max(0.1, minutes)) * 60)
        return .result()
    }
}

struct OpenScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Screen"
    static let description = IntentDescription("Brings TPHaptics forward on a screen, such as the Feel Pad.")
    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$screen) in TPHaptics") }
    static let openAppWhenRun = true

    @Parameter(title: "Screen", default: .pad) var screen: ScreenOption

    @MainActor func perform() async throws -> some IntentResult {
        Navigator.shared.reveal(screen.section)
        return .result()
    }
}

struct OpenFeelPadIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Feel Pad"
    static let description = IntentDescription("Pulls up the Feel Pad: press and drag, up is stronger, right is faster.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        Navigator.shared.reveal(.pad)
        return .result()
    }
}

// MARK: - Siri, Spotlight and the Shortcuts gallery

struct TPHapticsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayPatternIntent(),
                    phrases: ["Play \(\.$pattern) in \(.applicationName)", "Feel \(\.$pattern) with \(.applicationName)"],
                    shortTitle: "Play Pattern", systemImageName: "waveform")
        AppShortcut(intent: OpenFeelPadIntent(),
                    phrases: ["Open the Feel Pad in \(.applicationName)"],
                    shortTitle: "Open Feel Pad", systemImageName: "hand.point.up.left.fill")
        AppShortcut(intent: StopHapticsIntent(),
                    phrases: ["Stop \(.applicationName)"],
                    shortTitle: "Stop Haptics", systemImageName: "stop.fill")
    }
}
