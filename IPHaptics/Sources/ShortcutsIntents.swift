import AppIntents

// Shortcuts actions for IPHaptics. They appear in the Shortcuts app under IPHaptics, and can be spoken to
// Siri. iOS only lets an app vibrate while it's on screen, so actions that play haptics open the app first.

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

/// Every built-in pattern plus saved paintings, so "custom buttons" can be built from a list.
struct PatternQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PatternEntity] {
        await MainActor.run { identifiers.filter { PatternLibrary.shared.pattern(named: $0) != nil }.map { PatternEntity(id: $0) } }
    }
    func entities(matching string: String) async throws -> [PatternEntity] {
        await MainActor.run {
            PatternLibrary.shared.allNames.filter { $0.localizedCaseInsensitiveContains(string) }.map { PatternEntity(id: $0) }
        }
    }
    func suggestedEntities() async throws -> [PatternEntity] {
        await MainActor.run { PatternLibrary.shared.allNames.map { PatternEntity(id: $0) } }
    }
}

// MARK: - Screens

enum ScreenOption: String, AppEnum {
    case patterns, sequencer, paint, buzz, pad, breathe, morse, audio, simon, hotcold, rhythm

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Screen"
    static let caseDisplayRepresentations: [ScreenOption: DisplayRepresentation] = [
        .patterns: "Patterns", .sequencer: "Sequencer", .paint: "Paint", .buzz: "Buzz", .pad: "Feel Pad",
        .breathe: "Breathing", .morse: "Morse", .audio: "Audio to Haptics",
        .simon: "Simon", .hotcold: "Hot & Cold", .rhythm: "Rhythm Echo",
    ]
    var screen: AppScreen? { AppScreen(rawValue: rawValue) }
}

// MARK: - Intents

struct PlayPatternIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Pattern"
    static let description = IntentDescription("Plays a haptic pattern on your iPhone.")
    static let openAppWhenRun = true
    static var parameterSummary: some ParameterSummary { Summary("Play \(\.$pattern)") }

    @Parameter(title: "Pattern") var pattern: PatternEntity
    @Parameter(title: "Loop", default: false) var loop: Bool

    @MainActor func perform() async throws -> some IntentResult {
        guard let p = PatternLibrary.shared.pattern(named: pattern.id) else {
            throw ShortcutError.message("There's no pattern called “\(pattern.id)”.")
        }
        Haptics.shared.play(p, loop: loop)
        return .result()
    }
}

struct ListPatternsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Patterns"
    static let description = IntentDescription("Returns every pattern, so you can pick one with “Choose from List” and build your own buttons.")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[PatternEntity]> {
        .result(value: PatternLibrary.shared.allNames.map { PatternEntity(id: $0) })
    }
}

struct PlayMorseIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Morse"
    static let description = IntentDescription("Feels text as Morse code.")
    static let openAppWhenRun = true
    static var parameterSummary: some ParameterSummary { Summary("Feel \(\.$text) in Morse") }

    @Parameter(title: "Text") var text: String
    @Parameter(title: "Words per minute", default: 12) var wpm: Int

    @MainActor func perform() async throws -> some IntentResult {
        guard !Morse.encode(text).isEmpty else { throw ShortcutError.message("There's nothing in that text to send in Morse.") }
        Haptics.shared.play(Morse.pattern(text: text, wpm: Double(min(30, max(5, wpm)))), loop: false)
        return .result()
    }
}

struct BuzzIntent: AppIntent {
    static let title: LocalizedStringResource = "Buzz"
    static let description = IntentDescription("A steady train of taps with an interval you choose.")
    static let openAppWhenRun = true
    static var parameterSummary: some ParameterSummary { Summary("Buzz every \(\.$intervalMS) ms for \(\.$seconds) seconds") }

    @Parameter(title: "Interval (ms)", default: 30) var intervalMS: Int
    @Parameter(title: "Seconds", default: 2.0) var seconds: Double

    @MainActor func perform() async throws -> some IntentResult {
        let interval = max(0.01, Double(intervalMS) / 1000)
        let n = max(1, Int(min(60, max(0.1, seconds)) / interval))
        let p = HapticPattern(name: "Buzz",
                              taps: (0..<n).map { Tap(time: Double($0) * interval, intensity: 0.9, sharpness: 0.8) },
                              length: Double(n) * interval)
        Haptics.shared.play(p, loop: false)
        return .result()
    }
}

/// A steady vibration at a chosen intensity and sharpness. Combine several to build your own Feel Pad.
struct HumIntent: AppIntent {
    static let title: LocalizedStringResource = "Feel Point"
    static let description = IntentDescription("Vibrates continuously at one point on the Feel Pad: intensity from weak to strong, sharpness from soft to crisp. Waits until it's done.")
    static let openAppWhenRun = true
    static var parameterSummary: some ParameterSummary { Summary("Feel \(\.$intensity)% intensity, \(\.$sharpness)% sharpness for \(\.$seconds) s") }

    @Parameter(title: "Intensity (0–100)", default: 70) var intensity: Int
    @Parameter(title: "Sharpness (0–100)", default: 50) var sharpness: Int
    @Parameter(title: "Seconds", default: 1.5) var seconds: Double

    @MainActor func perform() async throws -> some IntentResult {
        let i = Float(min(100, max(0, intensity))) / 100, s = Float(min(100, max(0, sharpness))) / 100
        Haptics.shared.hum.begin(intensity: i, sharpness: s)
        try await Task.sleep(nanoseconds: UInt64(min(30, max(0.1, seconds)) * 1_000_000_000))
        Haptics.shared.hum.end()
        return .result()
    }
}

struct BreatheIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Breathing Guide"
    static let description = IntentDescription("A silent swell-and-fade breathing guide.")
    static let openAppWhenRun = true
    static var parameterSummary: some ParameterSummary { Summary("Breathe for \(\.$cycles) cycles") }

    @Parameter(title: "Cycles", default: 4) var cycles: Int

    @MainActor func perform() async throws -> some IntentResult {
        var plan = BreathPlan()
        plan.cycles = min(30, max(1, cycles))
        Haptics.shared.play(Breathing.pattern(plan))
        Navigator.shared.request = .breathe
        return .result()
    }
}

struct SetStrengthIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Strength"
    static let description = IntentDescription("Sets the master Strength slider, from 0 (off) to 100 (max).")
    static var parameterSummary: some ParameterSummary { Summary("Set strength to \(\.$percent)%") }

    @Parameter(title: "Percent", default: 100) var percent: Int

    @MainActor func perform() async throws -> some IntentResult {
        Haptics.shared.strength = Double(min(100, max(0, percent))) / 100
        return .result()
    }
}

struct StopHapticsIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Haptics"
    static let description = IntentDescription("Stops whatever IPHaptics is playing.")

    @MainActor func perform() async throws -> some IntentResult {
        Haptics.shared.stop()
        return .result()
    }
}

struct OpenScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Screen"
    static let description = IntentDescription("Opens IPHaptics on a screen, such as the Feel Pad.")
    static let openAppWhenRun = true
    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$screen) in IPHaptics") }

    @Parameter(title: "Screen", default: .pad) var screen: ScreenOption

    @MainActor func perform() async throws -> some IntentResult {
        Navigator.shared.request = screen.screen
        return .result()
    }
}

struct OpenFeelPadIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Feel Pad"
    static let description = IntentDescription("Pulls up the Feel Pad: slide a finger, up is stronger, right is crisper.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        Navigator.shared.request = .pad
        return .result()
    }
}

// MARK: - Siri, Spotlight and the Shortcuts gallery

struct IPHapticsShortcuts: AppShortcutsProvider {
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
