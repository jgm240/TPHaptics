import Foundation

/// Levels used by the sequencer and games.
enum Level {
    static let light: Float = 0.3
    static let medium: Float = 0.55
    static let strong: Float = 0.8
    static let max: Float = 1.0
}

private func tick(_ t: Double, _ i: Float, _ s: Float = 0.7) -> Tap { Tap(time: t, intensity: i, sharpness: s) }
private func buzz(_ t: Double, _ d: Double, _ i: Float, _ s: Float = 0.5, curve: [CurvePoint] = []) -> Tap {
    Tap(time: t, intensity: i, sharpness: s, duration: d, curve: curve)
}

enum Presets {
    static let all: [HapticPattern] = [doubleTap, heartbeat, knock, rampUp, rain, hum, rapid, sos, metronome, swell, rumble]

    static let doubleTap = HapticPattern(
        name: "Double Tap", detail: "Two quick, crisp taps.",
        taps: [tick(0, 1, 0.9), tick(0.15, 1, 0.9)], length: 0.5)

    static let heartbeat = HapticPattern(
        name: "Heartbeat", detail: "Lub-dub, lub-dub.",
        taps: [tick(0, 0.9, 0.25), tick(0.17, 0.6, 0.2), tick(0.9, 0.9, 0.25), tick(1.07, 0.6, 0.2)], length: 1.8)

    static let knock = HapticPattern(
        name: "Knock Knock", detail: "Three firm knocks.",
        taps: [0, 0.22, 0.44].map { tick($0, 1, 0.85) }, length: 1.4)

    static let rampUp = HapticPattern(
        name: "Ramp Up", detail: "Accelerating taps that grow stronger.",
        taps: {
            var out: [Tap] = []
            var t = 0.0, gap = 0.4
            for k in 0..<12 {
                out.append(tick(t, 0.2 + 0.8 * Float(k) / 11, 0.6))
                t += gap; gap = max(0.05, gap * 0.78)
            }
            return out
        }(), length: 2.8)

    static let rain = HapticPattern(
        name: "Rain", detail: "Scattered light drops.",
        taps: {
            var rng = SplitMix(state: 42)
            return (0..<28).map { _ in
                tick(Double(rng.next() % 3000) / 1000, 0.25 + Float(rng.next() % 20) / 100, 0.95)
            }.sorted { $0.time < $1.time }
        }(), length: 3.0)

    static let hum = HapticPattern(
        name: "Hum", detail: "A steady, true vibration.",
        taps: [buzz(0, 1.2, 0.8, 0.45)], length: 1.4)

    static let rapid = HapticPattern(
        name: "Rapid Taps", detail: "Fast ticks that blur into a vibration.",
        taps: (0..<40).map { tick(Double($0) * 0.03, 0.8, 0.8) }, length: 1.3)

    static let sos = Morse.pattern(text: "SOS", wpm: 12, sharpness: 0.6, name: "SOS", detail: "··· −−− ··· in Morse.")

    static let metronome = HapticPattern(
        name: "Metronome 120", detail: "Accented tick every beat.",
        taps: (0..<4).map { tick(Double($0) * 0.5, $0 == 0 ? 1 : 0.4, $0 == 0 ? 0.9 : 0.6) }, length: 2.0)

    static let swell = HapticPattern(
        name: "Swell", detail: "Builds up and falls away, smoothly.",
        taps: [buzz(0, 2.0, 1, 0.35, curve: [CurvePoint(time: 0, value: 0.05), CurvePoint(time: 1.0, value: 1), CurvePoint(time: 2.0, value: 0.05)])],
        length: 2.4)

    static let rumble = HapticPattern(
        name: "Rumble", detail: "A low engine that revs up.",
        taps: [buzz(0, 2.4, 1, 0.05, curve: [CurvePoint(time: 0, value: 0.2), CurvePoint(time: 1.6, value: 0.7), CurvePoint(time: 2.0, value: 1), CurvePoint(time: 2.4, value: 0.3)])],
        length: 2.8)
}

/// Small deterministic generator so "Rain" is the same every time.
struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Morse

enum Morse {
    static let table: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.", "G": "--.", "H": "....",
        "I": "..", "J": ".---", "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---", "P": ".--.",
        "Q": "--.-", "R": ".-.", "S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-",
        "Y": "-.--", "Z": "--..",
        "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        ".": ".-.-.-", ",": "--..--", "?": "..--..", "!": "-.-.--", "/": "-..-.", "-": "-....-", "'": ".----.",
    ]

    /// "SOS NOW" → "... --- ... / -. --- .--"
    static func encode(_ text: String) -> String {
        text.uppercased().split(separator: " ")
            .map { word in word.compactMap { table[$0] }.joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    /// Dots and dashes are short and long vibrations. Standard timing: dash = 3 dots, 1 dot between
    /// symbols, 3 between letters, 7 between words.
    static func pattern(text: String, wpm: Double, sharpness: Float = 0.5,
                        name: String = "Morse", detail: String = "") -> HapticPattern {
        let unit = 1.2 / max(1, wpm)
        var taps: [Tap] = []
        var t = 0.0
        let words = text.uppercased().split(separator: " ").map { $0.compactMap { table[$0] } }.filter { !$0.isEmpty }
        for (wi, word) in words.enumerated() {
            for (li, letter) in word.enumerated() {
                for (si, symbol) in letter.enumerated() {
                    let dur = (symbol == "." ? 1.0 : 3.0) * unit
                    taps.append(Tap(time: t, intensity: 0.95, sharpness: sharpness, duration: dur))
                    t += dur
                    if si < letter.count - 1 { t += unit }
                }
                if li < word.count - 1 { t += 3 * unit }
            }
            if wi < words.count - 1 { t += 7 * unit }
        }
        return HapticPattern(name: name, detail: detail, taps: taps, length: t)
    }
}

// MARK: - Saved patterns

@MainActor
final class PatternLibrary: ObservableObject {
    static let shared = PatternLibrary()
    @Published private(set) var patterns: [HapticPattern] = []
    private let key = "savedPatterns"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([HapticPattern].self, from: data) {
            patterns = list
        }
    }

    func save(_ p: HapticPattern) {
        if let i = patterns.firstIndex(where: { $0.name.caseInsensitiveCompare(p.name) == .orderedSame }) {
            var q = p; q.id = patterns[i].id
            patterns[i] = q
        } else {
            patterns.append(p)
        }
        persist()
    }

    func delete(_ id: UUID) {
        patterns.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(patterns) { UserDefaults.standard.set(data, forKey: key) }
    }

    func pattern(named name: String) -> HapticPattern? {
        (Presets.all + patterns).first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
