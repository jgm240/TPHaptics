import CoreHaptics
import SwiftUI

// MARK: - Model

/// A point on an intensity curve, relative to the start of its event.
struct CurvePoint: Codable, Hashable {
    var time: Double
    var value: Float            // 0…1, multiplies the event's intensity
}

/// One haptic event. `duration == 0` is a transient tick; `duration > 0` is a continuous buzz,
/// optionally shaped by an intensity `curve`.
struct Tap: Codable, Hashable {
    var time: Double
    var intensity: Float        // 0…1
    var sharpness: Float = 0.5  // 0 = soft and round, 1 = crisp
    var duration: Double = 0
    var curve: [CurvePoint] = []
}

struct HapticPattern: Identifiable, Codable {
    var id = UUID()
    var name: String
    var detail: String = ""
    var taps: [Tap]
    var length: Double          // seconds, including any trailing silence (the loop point)
}

// MARK: - Engine

/// Plays patterns through Core Haptics. Haptics only play while the app is in the foreground.
@MainActor
final class Haptics: ObservableObject {
    static let shared = Haptics()

    /// false on iPads, the Simulator and anything without a Taptic Engine.
    let supported: Bool
    @Published private(set) var playingName: String?
    @Published private(set) var lastError: String?
    /// Master strength 0…1, applied to everything.
    @Published var strength: Double {
        didSet { UserDefaults.standard.set(strength, forKey: "strength") }
    }

    let hum = HumPlayer()
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var generation = 0

    private init() {
        supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        strength = UserDefaults.standard.object(forKey: "strength") as? Double ?? 1.0
    }

    func prepare() throws -> CHHapticEngine {
        if let engine { return engine }
        let e = try CHHapticEngine()
        e.playsHapticsOnly = true
        e.isAutoShutdownEnabled = true
        e.resetHandler = { [weak self] in Task { @MainActor in self?.engine = nil } }
        e.stoppedHandler = { [weak self] _ in Task { @MainActor in self?.engine = nil } }
        try e.start()
        engine = e
        return e
    }

    // MARK: Patterns

    func play(_ p: HapticPattern, loop: Bool = false) {
        stop()
        guard supported, !p.taps.isEmpty else { return }
        do {
            let engine = try prepare()
            let pattern = try Self.makePattern(p, strength: Float(strength))
            let pl = try engine.makeAdvancedPlayer(with: pattern)
            pl.loopEnabled = loop
            generation += 1
            let g = generation
            pl.completionHandler = { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == g else { return }
                    self.playingName = nil
                    self.player = nil
                }
            }
            try pl.start(atTime: CHHapticTimeImmediate)
            player = pl
            playingName = p.name
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        generation += 1
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        playingName = nil
        hum.end()
    }

    /// One transient tick, for event-driven features (games, audio).
    func tap(_ intensity: Float, sharpness: Float = 0.6) {
        guard supported, let engine = try? prepare() else { return }
        let level = min(1, max(0, intensity * Float(strength)))
        guard level > 0 else { return }
        do {
            let event = CHHapticEvent(eventType: .hapticTransient,
                                      parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: level),
                                                   CHHapticEventParameter(parameterID: .hapticSharpness, value: min(1, max(0, sharpness)))],
                                      relativeTime: 0)
            let player = try engine.makePlayer(with: try CHHapticPattern(events: [event], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            lastError = error.localizedDescription
        }
    }

    static func makePattern(_ p: HapticPattern, strength: Float) throws -> CHHapticPattern {
        var events: [CHHapticEvent] = []
        var curves: [CHHapticParameterCurve] = []
        var lastEnd = 0.0

        for t in p.taps {
            let level = min(1, max(0, t.intensity * strength))
            let params = [CHHapticEventParameter(parameterID: .hapticIntensity, value: level),
                          CHHapticEventParameter(parameterID: .hapticSharpness, value: min(1, max(0, t.sharpness)))]
            if t.duration > 0 {
                events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: params,
                                            relativeTime: t.time, duration: t.duration))
                lastEnd = max(lastEnd, t.time + t.duration)
            } else {
                events.append(CHHapticEvent(eventType: .hapticTransient, parameters: params, relativeTime: t.time))
                lastEnd = max(lastEnd, t.time)
            }
            // Core Haptics allows 16 control points per curve, so long curves are chained with one point of overlap.
            if t.curve.count >= 2 {
                var i = 0
                while i < t.curve.count - 1 {
                    let chunk = Array(t.curve[i..<min(t.curve.count, i + 16)])
                    let start = chunk[0].time
                    let points = chunk.map { CHHapticParameterCurve.ControlPoint(relativeTime: $0.time - start, value: min(1, max(0, $0.value))) }
                    curves.append(CHHapticParameterCurve(parameterID: .hapticIntensityControl,
                                                         controlPoints: points, relativeTime: t.time + start))
                    i += 15
                }
            }
        }
        // An inaudible event at the end keeps trailing silence when the pattern loops.
        if p.length > lastEnd + 0.002 {
            events.append(CHHapticEvent(eventType: .hapticTransient,
                                        parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 0),
                                                     CHHapticEventParameter(parameterID: .hapticSharpness, value: 0)],
                                        relativeTime: p.length - 0.001))
        }
        return try CHHapticPattern(events: events, parameterCurves: curves)
    }
}

// MARK: - Live, continuously adjustable vibration

/// A steady vibration whose intensity and sharpness can be changed while it runs
/// (the feel pad, live painting, loudness following).
@MainActor
final class HumPlayer {
    private var player: CHHapticAdvancedPatternPlayer?
    var isActive: Bool { player != nil }

    func begin(intensity: Float, sharpness: Float) {
        end()
        let haptics = Haptics.shared
        guard haptics.supported else { return }
        do {
            let engine = try haptics.prepare()
            let event = CHHapticEvent(eventType: .hapticContinuous,
                                      parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                                                   CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)],
                                      relativeTime: 0, duration: 30)
            let start = CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                                 value: Self.level(intensity), relativeTime: 0)
            let pattern = try CHHapticPattern(events: [event], parameters: [start])
            let pl = try engine.makeAdvancedPlayer(with: pattern)
            pl.loopEnabled = true
            try pl.start(atTime: CHHapticTimeImmediate)
            player = pl
            update(intensity: intensity, sharpness: sharpness)
        } catch {
            player = nil
        }
    }

    func update(intensity: Float, sharpness: Float) {
        try? player?.sendParameters([
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: Self.level(intensity), relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: min(0.5, max(-0.5, sharpness - 0.5)), relativeTime: 0),
        ], atTime: CHHapticTimeImmediate)
    }

    func end() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }

    private static func level(_ v: Float) -> Float { min(1, max(0, v * Float(Haptics.shared.strength))) }
}
