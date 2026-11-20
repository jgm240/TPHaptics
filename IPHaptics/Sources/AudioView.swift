import SwiftUI
import AVFoundation

enum AudioBand: Int, CaseIterable {
    case bass, mids, highs

    var title: String {
        switch self {
        case .bass: return "Bass"
        case .mids: return "Mids"
        case .highs: return "Highs"
        }
    }
    var detail: String {
        switch self {
        case .bass: return "kicks, bass notes"
        case .mids: return "voice, guitar, snares"
        case .highs: return "hi-hats, clicks, s-sounds"
        }
    }
    var bit: Int { 1 << rawValue }
    /// Bass is firm and round; highs are light and crisp.
    func feel(strength s: Float) -> (intensity: Float, sharpness: Float) {
        switch self {
        case .bass: return (0.5 + 0.5 * s, 0.25)
        case .mids: return (0.4 + 0.4 * s, 0.55)
        case .highs: return (0.25 + 0.35 * s, 0.95)
        }
    }
}

struct AudioResult {
    var hit: (band: AudioBand, strength: Float)?
    var level: Float            // 0…1, loudness relative to what the source has recently done
}

/// Splits sound into bass / mids / highs and finds hits in each ("louder than the recent average"),
/// or reports overall loudness for the continuous mode.
final class OnsetDetector {
    private let lock = NSLock()
    private var _ratio = 1.8
    private var _mask = 7
    var ratio: Double { get { locked { _ratio } } set { locked { _ratio = newValue } } }
    var mask: Int { get { locked { _mask } } set { locked { _mask = newValue } } }
    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    private struct BandState { var avg: Float = 0; var prev: Float = 0; var since = 1.0 }
    private var states = [BandState](repeating: BandState(), count: 3)
    private let refractory: [Double] = [0.09, 0.07, 0.05]
    private let floorLevel: [Float] = [0.004, 0.003, 0.002]

    private let sampleRate: Double
    private let aLow: Float
    private let aMid: Float
    private var lpLow: Float = 0
    private var lpMid: Float = 0
    private var peak: Float = 0.02

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        aLow = Float(1 - exp(-2 * Double.pi * 200 / sampleRate))
        aMid = Float(1 - exp(-2 * Double.pi * 2500 / sampleRate))
    }

    func process(_ samples: UnsafePointer<Float>, count: Int) -> AudioResult {
        guard count > 0 else { return AudioResult(hit: nil, level: 0) }
        var e: [Float] = [0, 0, 0]
        var eAll: Float = 0
        for i in 0..<count {
            let x = samples[i]
            lpLow += aLow * (x - lpLow)
            lpMid += aMid * (x - lpMid)
            let low = lpLow, mid = lpMid - lpLow, high = x - lpMid
            e[0] += low * low; e[1] += mid * mid; e[2] += high * high
            eAll += x * x
        }
        let n = Float(count)
        let dt = Double(count) / sampleRate
        let overall = (eAll / n).squareRoot()
        peak = max(0.02, max(peak * 0.9995, overall))
        let level: Float = overall < 0.004 ? 0 : min(1, overall / peak)

        let ratio = self.ratio, mask = self.mask
        var best: (band: AudioBand, strength: Float)?
        for b in 0..<3 {
            let r = (e[b] / n).squareRoot()
            var s = states[b]
            s.since += dt
            s.avg = s.avg * 0.96 + r * 0.04
            let threshold = s.avg * Float(ratio) + floorLevel[b]
            if r > threshold && r > s.prev && s.since > refractory[b] {
                s.since = 0
                if mask & (1 << b) != 0 {
                    let strength = min(1, max(0.2, (r / threshold - 1) * 1.5 + 0.4))
                    if best == nil || strength > best!.strength { best = (AudioBand(rawValue: b)!, strength) }
                }
            }
            s.prev = r
            states[b] = s
        }
        return AudioResult(hit: best, level: level)
    }
}

final class AudioHaptics: ObservableObject {
    static let shared = AudioHaptics()

    @Published private(set) var running = false
    @Published private(set) var status = "Off"
    @Published private(set) var level: Double = 0
    @Published private(set) var hits = 0
    @Published var ratio: Double { didSet { defaults.set(ratio, forKey: "audio.ratio"); detector?.ratio = ratio } }
    @Published var bandMask: Int { didSet { defaults.set(bandMask, forKey: "audio.bands"); detector?.mask = bandMask } }
    /// false = taps for hits in the chosen bands; true = a continuous vibration that follows loudness.
    @Published var followLoudness: Bool {
        didSet {
            defaults.set(followLoudness, forKey: "audio.follow")
            followFlag.value = followLoudness
            guard running else { return }
            Task { @MainActor in
                if self.followLoudness { Haptics.shared.hum.begin(intensity: 0, sharpness: 0.4) } else { Haptics.shared.hum.end() }
            }
        }
    }

    private let defaults = UserDefaults.standard
    private var engine: AVAudioEngine?
    private var detector: OnsetDetector?
    private let followFlag = Flag()
    private var blocks = 0

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var _v = false
        var value: Bool { get { lock.lock(); defer { lock.unlock() }; return _v } set { lock.lock(); _v = newValue; lock.unlock() } }
    }

    private init() {
        ratio = defaults.object(forKey: "audio.ratio") as? Double ?? 1.8
        bandMask = defaults.object(forKey: "audio.bands") as? Int ?? 7
        followLoudness = defaults.object(forKey: "audio.follow") as? Bool ?? false
        followFlag.value = followLoudness
    }

    func start() {
        status = "Waiting for microphone permission…"
        AVAudioSession.sharedInstance().requestRecordPermission { ok in
            DispatchQueue.main.async {
                if ok { self.begin() } else { self.status = "Microphone access denied. Allow it in Settings → IPHaptics." }
            }
        }
    }

    private func begin() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers])
            // Without this, iOS silences haptics while the microphone is recording.
            try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try session.setActive(true)

            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { status = "No audio input available"; return }
            let det = OnsetDetector(sampleRate: format.sampleRate)
            det.ratio = ratio
            det.mask = bandMask
            let follow = followFlag
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self, let ch = buffer.floatChannelData?[0] else { return }
                let r = det.process(ch, count: Int(buffer.frameLength))
                if follow.value {
                    let level = r.level
                    Task { @MainActor in Haptics.shared.hum.update(intensity: level, sharpness: 0.4) }
                } else if let hit = r.hit {
                    let feel = hit.band.feel(strength: hit.strength)
                    Task { @MainActor in Haptics.shared.tap(feel.intensity, sharpness: feel.sharpness) }
                    DispatchQueue.main.async { self.hits += 1 }
                }
                self.blocks += 1
                if self.blocks % 3 == 0 {
                    let level = Double(r.level)
                    DispatchQueue.main.async { self.level = level }
                }
            }
            try engine.start()
            self.engine = engine
            detector = det
            running = true
            hits = 0
            status = "Listening"
            if followLoudness { Task { @MainActor in Haptics.shared.hum.begin(intensity: 0, sharpness: 0.4) } }
        } catch {
            status = "Couldn't start audio: \(error.localizedDescription)"
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        detector = nil
        running = false
        level = 0
        status = "Off"
        Task { @MainActor in Haptics.shared.hum.end() }
    }
}

struct AudioView: View {
    @ObservedObject private var audio = AudioHaptics.shared

    private var sensitivity: Binding<Double> {
        Binding(get: { (3.2 - audio.ratio) / 2.0 }, set: { audio.ratio = 3.2 - $0 * 2.0 })
    }

    private func band(_ b: AudioBand) -> Binding<Bool> {
        Binding(get: { audio.bandMask & b.bit != 0 },
                set: { on in audio.bandMask = on ? audio.bandMask | b.bit : audio.bandMask & ~b.bit })
    }

    var body: some View {
        ScreenScroll {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    CardTitle(title: "Listen to everything",
                              subtitle: "Uses the microphone and vibrates to what it hears: bass, voices, clicks and everything between.")
                    HStack {
                        Text("Input level").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Pill(text: audio.status, tint: audio.running ? .green : .secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(LinearGradient(colors: [.green, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, geo.size.width * audio.level))
                                .animation(.easeOut(duration: 0.08), value: audio.level)
                        }
                    }
                    .frame(height: 10)
                    BigButton(title: audio.running ? "Stop" : "Start Listening", symbol: audio.running ? "stop.fill" : "mic.fill",
                              tint: audio.running ? .red : .accentColor) {
                        audio.running ? audio.stop() : audio.start()
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    CardTitle(title: "How it responds")
                    Picker("", selection: $audio.followLoudness) {
                        Text("Hits").tag(false)
                        Text("Loudness").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if audio.followLoudness {
                        Hint("A continuous vibration that gets stronger as the sound gets louder, so speech, pads and ambience come through. Volume is judged against what you've been hearing.")
                    } else {
                        Hint("A tap for each new sound that stands out, tracked separately for each frequency range: bass is firm, highs are light and crisp.")
                        ForEach(AudioBand.allCases, id: \.self) { b in
                            Toggle(isOn: band(b)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(b.title)
                                    Text(b.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        HStack {
                            Text("Sensitivity")
                            Slider(value: sensitivity, in: 0...1)
                            Text("\(audio.hits)").monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }
            Hint("The microphone hears the room, so play sound out loud. Audio is analysed live and never recorded or stored. IPHaptics asks for microphone permission the first time.")
        }
    }
}
