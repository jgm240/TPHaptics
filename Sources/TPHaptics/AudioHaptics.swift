import SwiftUI
import AVFoundation

/// Finds bass hits in an audio stream: low-pass → energy → "louder than recent average".
final class OnsetDetector {
    private let lock = NSLock()
    private var _ratio = 1.8
    /// How far above the recent average a hit must rise. Lower = more sensitive.
    var ratio: Double {
        get { lock.lock(); defer { lock.unlock() }; return _ratio }
        set { lock.lock(); _ratio = newValue; lock.unlock() }
    }

    private let sampleRate: Double
    private let alpha: Float
    private var lp: Float = 0
    private var avg: Float = 0
    private var prev: Float = 0
    private var sinceOnset = 1.0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        alpha = Float(1 - exp(-2 * Double.pi * 160 / sampleRate))   // ~160 Hz low-pass
    }

    /// Returns a hit strength in 0…1 when this block starts a new bass hit, plus the block's level.
    func process(_ samples: UnsafePointer<Float>, count: Int) -> (onset: Float?, level: Float) {
        guard count > 0 else { return (nil, 0) }
        var e: Float = 0
        for i in 0..<count {
            lp += alpha * (samples[i] - lp)
            e += lp * lp
        }
        let rms = (e / Float(count)).squareRoot()
        sinceOnset += Double(count) / sampleRate
        defer { prev = rms }
        avg = avg * 0.96 + rms * 0.04
        let threshold = avg * Float(ratio) + 0.004
        if rms > threshold && rms > prev && sinceOnset > 0.09 {
            sinceOnset = 0
            return (min(1, max(0.2, (rms / threshold - 1) * 1.5 + 0.4)), rms)
        }
        return (nil, rms)
    }
}

final class AudioHaptics: ObservableObject {
    static let shared = AudioHaptics()

    @Published private(set) var running = false
    @Published private(set) var status = "Off"
    @Published private(set) var level: Double = 0
    @Published private(set) var hits = 0
    @Published var ratio: Double {
        didSet { UserDefaults.standard.set(ratio, forKey: "audio.ratio"); detector?.ratio = ratio }
    }

    private var engine: AVAudioEngine?
    private var detector: OnsetDetector?
    private var blocks = 0

    private init() {
        ratio = UserDefaults.standard.object(forKey: "audio.ratio") as? Double ?? 1.8
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
        input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            guard let self, let ch = buffer.floatChannelData?[0] else { return }
            let r = det.process(ch, count: Int(buffer.frameLength))
            if let s = r.onset {
                Haptics.tick(TrackpadActuator.ladder[min(5, Int(s * 6))])
                DispatchQueue.main.async { self.hits += 1 }
            }
            self.blocks += 1
            if self.blocks % 4 == 0 {
                DispatchQueue.main.async { self.level = Double(min(1, r.level * 10)) }
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

    /// Synthetic check: eight 60 Hz kicks, half a second apart, over a little noise.
    static func selfTest() -> (hits: Int, expected: Int) {
        let rate = 44_100.0
        let det = OnsetDetector(sampleRate: rate)
        var hits = 0
        let total = Int(rate * 5)
        var buf = [Float](repeating: 0, count: 512)
        var i = 0
        var seed: UInt64 = 1
        while i + 512 <= total {
            for k in 0..<512 {
                let t = Double(i + k) / rate
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let noise = Float(Int64(bitPattern: seed >> 11) % 2000) / 2000 * 0.002
                var s = noise
                let phase = (t - 0.5).truncatingRemainder(dividingBy: 0.5)
                if t >= 0.5 && phase >= 0 { s += Float(0.6 * exp(-phase / 0.06) * sin(2 * Double.pi * 60 * phase)) }
                buf[k] = s
            }
            if buf.withUnsafeBufferPointer({ det.process($0.baseAddress!, count: 512).onset }) != nil { hits += 1 }
            i += 512
        }
        return (hits, 9)
    }
}

struct AudioHapticsView: View {
    @ObservedObject private var audio = AudioHaptics.shared

    /// Slider 0…1 where 1 is the most sensitive.
    private var sensitivity: Binding<Double> {
        Binding(get: { (3.2 - audio.ratio) / 2.0 }, set: { audio.ratio = 3.2 - $0 * 2.0 })
    }

    var body: some View {
        Screen {
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        CardTitle(title: "Listen for beats",
                                  subtitle: "Uses the microphone to find bass hits and taps them out, stronger for louder hits.")
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

                    HStack(spacing: 14) {
                        Text("Sensitivity").frame(width: 80, alignment: .leading)
                        Slider(value: sensitivity, in: 0...1)
                        Text("\(audio.hits) hits").monospacedDigit().foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
                    }
                }
            }
            Hint("The microphone hears your speakers, so play music out loud. To react to a specific app's sound without a mic, route it through a loopback audio device and make that the Mac's input. TPHaptics asks for microphone permission the first time.")
        }
    }
}
