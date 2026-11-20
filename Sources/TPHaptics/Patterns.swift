import Foundation

/// A named strength level mapped to a MTActuator actuation ID.
/// Tweak the IDs here if your trackpad feels different.
struct Strength: Identifiable, Hashable {
    let id: Int32          // actuation ID
    let name: String

    static let light  = Strength(id: 1, name: "Light")
    static let medium = Strength(id: 3, name: "Medium")
    static let strong = Strength(id: 5, name: "Strong")
    static let max    = Strength(id: 6, name: "Max")

    /// Order used by the sequencer (index 0 in the grid = rest).
    static let all: [Strength] = [.light, .medium, .strong, .max]
}

struct HapticEvent {
    var time: Double        // seconds from pattern start
    var actuation: Int32?   // nil = rest (used for sequencer playhead)
}

struct HapticPattern: Identifiable {
    let id = UUID()
    var name: String
    var detail: String
    var events: [HapticEvent]
    var length: Double      // total seconds (loop point)
    /// true: the pattern's strongest tap plays at the master strength.
    /// false: taps are scaled against the actuator's absolute maximum.
    var normalize: Bool = true
}

enum Presets {
    static let all: [HapticPattern] = [
        doubleTap, heartbeat, knock, ramp, rain, buzz, sos, metronome, wave
    ]

    static let doubleTap = HapticPattern(
        name: "Double Tap", detail: "Two quick taps — the default notification buzz.",
        events: [
            .init(time: 0.00, actuation: Strength.max.id),
            .init(time: 0.15, actuation: Strength.max.id),
        ], length: 0.5)

    static let heartbeat = HapticPattern(
        name: "Heartbeat", detail: "Lub-dub, lub-dub.",
        events: [
            .init(time: 0.00, actuation: Strength.strong.id),
            .init(time: 0.17, actuation: Strength.medium.id),
            .init(time: 0.90, actuation: Strength.strong.id),
            .init(time: 1.07, actuation: Strength.medium.id),
        ], length: 1.8)

    static let knock = HapticPattern(
        name: "Knock Knock", detail: "Three firm knocks.",
        events: [0.0, 0.22, 0.44].map { .init(time: $0, actuation: Strength.max.id) },
        length: 1.4)

    static let ramp = HapticPattern(
        name: "Ramp Up", detail: "Accelerating taps that grow stronger.",
        events: {
            var t = 0.0, gap = 0.4
            let ids = [1, 1, 2, 3, 4, 5, 5, 6, 6, 6].map(Int32.init)
            return ids.map { id in defer { t += gap; gap = max(0.06, gap * 0.78) }
                return HapticEvent(time: t, actuation: id) }
        }(), length: 2.6)

    static let rain = HapticPattern(
        name: "Rain", detail: "Scattered light drops.",
        events: {
            var seed = SplitMix(state: 42)
            return (0..<28).map { _ in
                HapticEvent(time: Double(seed.next() % 3000) / 1000,
                            actuation: seed.next() % 2 == 0 ? Strength.light.id : 2)
            }.sorted { $0.time < $1.time }
        }(), length: 3.0)

    static let buzz = HapticPattern(
        name: "Buzz", detail: "Rapid-fire taps blur into a vibration.",
        events: (0..<40).map { .init(time: Double($0) * 0.025, actuation: Strength.medium.id) },
        length: 1.2)

    static let sos = HapticPattern(
        name: "SOS", detail: "··· −−− ··· in Morse.",
        events: {
            var ev: [HapticEvent] = []; var t = 0.0
            func dot()  { ev.append(.init(time: t, actuation: Strength.strong.id)); t += 0.14 }
            func dash() { for k in 0..<3 { ev.append(.init(time: t + Double(k) * 0.05, actuation: Strength.max.id)) }; t += 0.42 }
            for _ in 0..<3 { dot() }; t += 0.2
            for _ in 0..<3 { dash() }; t += 0.2
            for _ in 0..<3 { dot() }
            return ev
        }(), length: 3.0)

    static let metronome = HapticPattern(
        name: "Metronome 120", detail: "Accented tick every beat.",
        events: (0..<4).map { .init(time: Double($0) * 0.5,
                                    actuation: $0 == 0 ? Strength.max.id : Strength.light.id) },
        length: 2.0)

    static let wave = HapticPattern(
        name: "Wave", detail: "Swells up and falls away.",
        events: {
            let ids: [Int32] = [1, 2, 3, 4, 5, 6, 5, 4, 3, 2, 1]
            return ids.enumerated().map { HapticEvent(time: Double($0.offset) * 0.11, actuation: $0.element) }
        }(), length: 1.8)
}

/// Tiny deterministic RNG so "Rain" is the same every launch.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
