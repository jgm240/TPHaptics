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
    /// Strongest actuation level (0…5) a band may use, so highs feel crisp and light.
    var maxRank: Int {
        switch self {
        case .bass: return 5
        case .mids: return 4
        case .highs: return 2
        }
    }
}

struct AudioHit {
    var band: AudioBand
    var strength: Float      // 0…1
}

struct AudioResult {
    var hit: AudioHit?       // beat mode: a new hit, in the strongest band that fired
    var followRank: Int?     // loudness mode: tap now, at this actuation level (0…5)
    var level: Float         // 0…1 for the meter
}

/// Splits sound into bass / mids / highs and finds hits in each ("louder than recent average"),
/// or follows overall loudness as a click rate.
final class OnsetDetector {
    private let lock = NSLock()
    private var _ratio = 1.8
    private var _mask = 7
    private var _follow = false

    /// How far above the recent average a hit must rise. Lower = more sensitive.
    var ratio: Double { get { locked { _ratio } } set { locked { _ratio = newValue } } }
    /// Which bands count (bit set of `AudioBand.bit`).
    var mask: Int { get { locked { _mask } } set { locked { _mask = newValue } } }
    /// true = follow loudness instead of finding hits.
    var follow: Bool { get { locked { _follow } } set { locked { _follow = newValue } } }

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    private struct BandState { var avg: Float = 0; var prev: Float = 0; var since = 1.0 }
    private var states = [BandState](repeating: BandState(), count: 3)
    private let refractory: [Double] = [0.09, 0.07, 0.05]
    private let floorLevel: [Float] = [0.004, 0.003, 0.002]

    private let sampleRate: Double
    private let aLow: Float      // ~200 Hz low-pass
    private let aMid: Float      // ~2.5 kHz low-pass
    private var lpLow: Float = 0
    private var lpMid: Float = 0

    private var peak: Float = 0.02
    private var phase = 0.0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        aLow = Float(1 - exp(-2 * Double.pi * 200 / sampleRate))
        aMid = Float(1 - exp(-2 * Double.pi * 2500 / sampleRate))
    }

    func process(_ samples: UnsafePointer<Float>, count: Int) -> AudioResult {
        guard count > 0 else { return AudioResult(hit: nil, followRank: nil, level: 0) }
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

        // Loudness relative to what this source has recently done (auto gain).
        peak = max(0.02, max(peak * 0.9995, overall))
        let normalized: Float = overall < 0.004 ? 0 : min(1, overall / peak)

        let (follow, ratio, mask) = (self.follow, self.ratio, self.mask)

        if follow {
            guard normalized > 0 else { phase = 0; return AudioResult(hit: nil, followRank: nil, level: 0) }
            phase += dt * (6 + 54 * Double(normalized))          // 6…60 taps per second
            if phase >= 1 {
                phase = phase.truncatingRemainder(dividingBy: 1)
                return AudioResult(hit: nil, followRank: min(5, Int(normalized * 6)), level: normalized)
            }
            return AudioResult(hit: nil, followRank: nil, level: normalized)
        }

        var best: AudioHit?
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
                    if best == nil || strength > best!.strength {
                        best = AudioHit(band: AudioBand(rawValue: b)!, strength: strength)
                    }
                }
            }
            s.prev = r
            states[b] = s
        }
        return AudioResult(hit: best, followRank: nil, level: normalized)
    }
}

final class AudioHaptics: ObservableObject {
    static let shared = AudioHaptics()

    @Published private(set) var running = false
    @Published private(set) var status = "Off"
    @Published private(set) var level: Double = 0
    @Published private(set) var hits = 0

    /// Lower = more sensitive.
    @Published var ratio: Double { didSet { defaults.set(ratio, forKey: "audio.ratio"); detector?.ratio = ratio } }
    /// Bit set of `AudioBand.bit`.
    @Published var bandMask: Int { didSet { defaults.set(bandMask, forKey: "audio.bands"); detector?.mask = bandMask } }
    /// false = hits in the chosen bands, true = follow loudness.
    @Published var followLoudness: Bool { didSet { defaults.set(followLoudness, forKey: "audio.follow"); detector?.follow = followLoudness } }

    private let defaults = UserDefaults.standard
    private var engine: AVAudioEngine?
    private var detector: OnsetDetector?
    private var blocks = 0

    private init() {
        ratio = defaults.object(forKey: "audio.ratio") as? Double ?? 1.8
        bandMask = defaults.object(forKey: "audio.bands") as? Int ?? 7
        followLoudness = defaults.object(forKey: "audio.follow") as? Bool ?? false
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            begin()
        case .notDetermined:
            status = "Waiting for microphone permission…"
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async { ok ? self.begin() : self.deny() }
            }
        default:
            deny()
        }
    }

    private func deny() {
        status = "Microphone access denied — allow it in System Settings → Privacy & Security → Microphone"
    }

    private func begin() {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            status = "No audio input available"
            return
        }
        let det = OnsetDetector(sampleRate: format.sampleRate)
        det.ratio = ratio
        det.mask = bandMask
        det.follow = followLoudness
        let ladder = TrackpadActuator.ladder
        input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            guard let self, let ch = buffer.floatChannelData?[0] else { return }
            let r = det.process(ch, count: Int(buffer.frameLength))
            if let hit = r.hit {
                let rank = min(hit.band.maxRank, Int(hit.strength * 6))
                Haptics.tick(ladder[rank])
                DispatchQueue.main.async { self.hits += 1 }
            }
            if let rank = r.followRank { Haptics.tick(ladder[rank]) }
            self.blocks += 1
            if self.blocks % 4 == 0 {
                DispatchQueue.main.async { self.level = Double(r.level) }
            }
        }
        do {
            try engine.start()
            self.engine = engine
            detector = det
            running = true
            hits = 0
            status = "Listening"
        } catch {
            input.removeTap(onBus: 0)
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
    }

    // MARK: Synthetic checks

    private static func render(seconds: Double, rate: Double, sample: (Double) -> Float) -> [Float] {
        (0..<Int(seconds * rate)).map { sample(Double($0) / rate) }
    }

    private static func run(_ det: OnsetDetector, _ signal: [Float], _ visit: (AudioResult) -> Void) {
        var i = 0
        signal.withUnsafeBufferPointer { p in
            while i + 512 <= signal.count {
                visit(det.process(p.baseAddress! + i, count: 512))
                i += 512
            }
        }
    }

    /// Every half second: a 60 Hz kick, then 0.17 s later a 1 kHz blip, then 0.33 s later a 6 kHz tick.
    static func selfTestBands() -> [AudioBand: Int] {
        let rate = 44_100.0
        func burst(_ t: Double, start: Double, hz: Double, amp: Double, tau: Double) -> Float {
            let p = (t - start).truncatingRemainder(dividingBy: 0.5)
            guard t >= start, p >= 0 else { return 0 }
            return Float(amp * exp(-p / tau) * sin(2 * Double.pi * hz * p))
        }
        let signal = render(seconds: 5, rate: rate) { t in
            burst(t, start: 0.5, hz: 60, amp: 0.6, tau: 0.06)
                + burst(t, start: 0.67, hz: 1000, amp: 0.4, tau: 0.03)
                + burst(t, start: 0.83, hz: 6000, amp: 0.4, tau: 0.015)
        }
        let det = OnsetDetector(sampleRate: rate)
        var counts: [AudioBand: Int] = [:]
        run(det, signal) { if let h = $0.hit { counts[h.band, default: 0] += 1 } }
        return counts
    }

    /// Steady tone, loud for 2 s then quiet for 2 s: taps should be far more frequent while loud.
    static func selfTestFollow() -> (loud: Int, quiet: Int) {
        let rate = 44_100.0
        let signal = render(seconds: 4, rate: rate) { t in
            Float((t < 2 ? 0.5 : 0.05) * sin(2 * Double.pi * 440 * t))
        }
        let det = OnsetDetector(sampleRate: rate)
        det.follow = true
        var loud = 0, quiet = 0, block = 0
        run(det, signal) { r in
            if r.followRank != nil { Double(block) * 512 / rate < 2 ? (loud += 1) : (quiet += 1) }
            block += 1
        }
        return (loud, quiet)
    }
}

struct AudioHapticsView: View {
    @ObservedObject private var audio = AudioHaptics.shared

    /// Slider 0…1 where 1 is the most sensitive.
    private var sensitivity: Binding<Double> {
        Binding(get: { (3.2 - audio.ratio) / 2.0 }, set: { audio.ratio = 3.2 - $0 * 2.0 })
    }

    private func bandBinding(_ band: AudioBand) -> Binding<Bool> {
        Binding(get: { audio.bandMask & band.bit != 0 },
                set: { on in audio.bandMask = on ? audio.bandMask | band.bit : audio.bandMask & ~band.bit })
    }

    var body: some View {
        Screen {
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        CardTitle(title: "Listen to everything",
                                  subtitle: "Uses the microphone and taps out what it hears: bass, voices, clicks and everything between.")
                        Spacer()
                        BigButton(title: audio.running ? "Stop" : "Start Listening",
                                  symbol: audio.running ? "stop.fill" : "mic.fill",
                                  tint: audio.running ? .red : .accentColor) {
                            audio.running ? audio.stop() : audio.start()
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Input level").font(.callout).foregroundStyle(.secondary)
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
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260)

                    if audio.followLoudness {
                        Hint("A steady stream of taps that speeds up and strengthens as the sound gets louder, so even speech, pads and ambience come through. Volume is judged against what you've been hearing, so it adapts to quiet and loud sources.")
                    } else {
                        Hint("A tap for each new sound that stands out. Each frequency range is tracked separately: bass is firm, mids lighter, highs light and crisp.")
                        HStack(spacing: 22) {
                            ForEach(AudioBand.allCases, id: \.self) { band in
                                Toggle(isOn: bandBinding(band)) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(band.title)
                                        Text(band.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                        HStack(spacing: 14) {
                            Text("Sensitivity").frame(width: 80, alignment: .leading)
                            Slider(value: sensitivity, in: 0...1)
                            Text("\(audio.hits) hits").monospacedDigit().foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
                        }
                    }
                }
            }

            Hint("The microphone hears your speakers, so play sound out loud. To react to one app's audio without a mic, route it through a loopback audio device and make that the Mac's input. TPHaptics asks for microphone permission the first time and never records or stores audio.")
        }
    }
}
