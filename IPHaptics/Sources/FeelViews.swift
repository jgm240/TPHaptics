import SwiftUI

// MARK: - Feel pad

/// Touch anywhere on the pad: left to right changes sharpness, bottom to top changes intensity.
struct FeelPadView: View {
    @ObservedObject private var haptics = Haptics.shared
    @State private var touch: CGPoint?        // normalized, y up

    init() {
        if UserDefaults.standard.bool(forKey: "marketing") { _touch = State(initialValue: CGPoint(x: 0.68, y: 0.62)) }
    }

    var body: some View {
        VStack(spacing: 14) {
            Hint("Put a finger on the pad and slide. Up is stronger, right is crisper, and the vibration follows you.")
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [Color.pink.opacity(0.18), Color.orange.opacity(0.22)],
                                             startPoint: .bottomLeading, endPoint: .topTrailing))
                    RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.primary.opacity(0.1))
                    if let t = touch {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .stroke(Color.pink.opacity(0.55 - Double(i) * 0.15), lineWidth: 3)
                                .frame(width: 50 + CGFloat(i) * 46 * (0.4 + t.y), height: 50 + CGFloat(i) * 46 * (0.4 + t.y))
                                .position(x: t.x * side, y: (1 - t.y) * side)
                        }
                        Circle().fill(Color.pink).frame(width: 30, height: 30)
                            .position(x: t.x * side, y: (1 - t.y) * side)
                    }
                    VStack {
                        Text("stronger").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        HStack { Text("soft").font(.caption); Spacer(); Text("crisp").font(.caption) }
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let origin = CGPoint(x: (geo.size.width - side) / 2, y: (geo.size.height - side) / 2)
                        let p = CGPoint(x: min(1, max(0, (v.location.x - origin.x) / side)),
                                        y: min(1, max(0, 1 - (v.location.y - origin.y) / side)))
                        if touch == nil { haptics.hum.begin(intensity: Float(p.y), sharpness: Float(p.x)) }
                        touch = p
                        haptics.hum.update(intensity: Float(p.y), sharpness: Float(p.x))
                    }
                    .onEnded { _ in touch = nil; haptics.hum.end() })
            }
            if let t = touch {
                Text("Intensity \(Int(t.y * 100))%  ·  Sharpness \(Int(t.x * 100))%")
                    .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onDisappear { haptics.hum.end() }
    }
}

// MARK: - Morse

struct MorseView: View {
    @ObservedObject private var haptics = Haptics.shared
    @State private var text = "HELLO WORLD"
    @State private var wpm = 12.0
    @State private var sharpness = 0.5
    @State private var loop = false

    var body: some View {
        let playing = haptics.playingName == "Morse"
        let encoded = Morse.encode(text)
        ScreenScroll {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    CardTitle(title: "Message", subtitle: "Letters, numbers and basic punctuation.")
                    TextField("Type something…", text: $text)
                        .textFieldStyle(.roundedBorder).font(.title3)
                        .textInputAutocapitalization(.characters)
                    Text(encoded.isEmpty ? "—" : encoded)
                        .font(.system(.title3, design: .monospaced).weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .textSelection(.enabled)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("Speed"); Slider(value: $wpm, in: 5...25, step: 1); Text("\(Int(wpm)) wpm").monospacedDigit().frame(width: 70, alignment: .trailing) }
                    HStack { Text("Feel"); Slider(value: $sharpness, in: 0...1); Text(sharpness < 0.34 ? "soft" : (sharpness > 0.66 ? "crisp" : "medium")).frame(width: 70, alignment: .trailing) }
                    Toggle("Loop", isOn: $loop)
                }
            }
            BigButton(title: playing ? "Stop" : "Send", symbol: playing ? "stop.fill" : "paperplane.fill",
                      tint: playing ? .red : .accentColor) {
                playing ? haptics.stop() : haptics.play(Morse.pattern(text: text, wpm: wpm, sharpness: Float(sharpness)), loop: loop)
            }
            .opacity(encoded.isEmpty ? 0.4 : 1).disabled(encoded.isEmpty)
        }
    }
}

// MARK: - Breathing

struct BreathPlan: Equatable {
    var inhale = 4.0
    var hold1 = 4.0
    var exhale = 4.0
    var hold2 = 4.0
    var cycles = 6
    var cycleLength: Double { inhale + hold1 + exhale + hold2 }
    var totalLength: Double { cycleLength * Double(cycles) }
}

enum Breathing {
    /// Inhale: one smooth buzz swelling from faint to strong. Hold: a soft tick each second.
    /// Exhale: the buzz fades away.
    static func pattern(_ plan: BreathPlan) -> HapticPattern {
        var taps: [Tap] = []
        var t = 0.0
        func hold(_ seconds: Double) {
            var s = 0.0
            while s < seconds { taps.append(Tap(time: t + s, intensity: 0.25, sharpness: 0.2)); s += 1 }
            t += seconds
        }
        for _ in 0..<max(1, plan.cycles) {
            if plan.inhale > 0 {
                taps.append(Tap(time: t, intensity: 1, sharpness: 0.3, duration: plan.inhale,
                                curve: [CurvePoint(time: 0, value: 0.08), CurvePoint(time: plan.inhale, value: 0.95)]))
                t += plan.inhale
            }
            hold(plan.hold1)
            if plan.exhale > 0 {
                taps.append(Tap(time: t, intensity: 1, sharpness: 0.3, duration: plan.exhale,
                                curve: [CurvePoint(time: 0, value: 0.95), CurvePoint(time: plan.exhale, value: 0.05)]))
                t += plan.exhale
            }
            hold(plan.hold2)
        }
        return HapticPattern(name: "Breathing", taps: taps, length: t)
    }
}

struct BreathingView: View {
    @ObservedObject private var haptics = Haptics.shared
    @State private var plan = BreathPlan()
    @State private var started = Date()

    private let presets: [(String, BreathPlan)] = [
        ("Box 4-4-4-4", BreathPlan(inhale: 4, hold1: 4, exhale: 4, hold2: 4, cycles: 6)),
        ("Relax 4-7-8", BreathPlan(inhale: 4, hold1: 7, exhale: 8, hold2: 0, cycles: 4)),
        ("Calm 5-5", BreathPlan(inhale: 5, hold1: 0, exhale: 5, hold2: 0, cycles: 8)),
    ]

    private func phase(at date: Date, playing: Bool) -> (String, Double) {
        if UserDefaults.standard.bool(forKey: "marketing") { return ("Breathe in", 0.82) }   // website screenshots
        guard playing else { return ("Ready", 0.3) }
        let t = date.timeIntervalSince(started)
        guard t < plan.totalLength else { return ("Done", 0.3) }
        var c = t.truncatingRemainder(dividingBy: plan.cycleLength)
        if c < plan.inhale { return ("Breathe in", 0.3 + 0.7 * c / plan.inhale) }
        c -= plan.inhale
        if c < plan.hold1 { return ("Hold", 1) }
        c -= plan.hold1
        if c < plan.exhale { return ("Breathe out", 1 - 0.7 * c / plan.exhale) }
        return ("Hold", 0.3)
    }

    var body: some View {
        let playing = haptics.playingName == "Breathing"
        ScreenScroll {
            Card {
                VStack(spacing: 14) {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                        let (label, size) = phase(at: tl.date, playing: playing)
                        ZStack {
                            Circle().fill(Color.mint.opacity(0.15)).frame(width: 230, height: 230)
                            Circle()
                                .fill(RadialGradient(colors: [Color.mint.opacity(0.8), Color.teal.opacity(0.45)],
                                                     center: .center, startRadius: 4, endRadius: 115))
                                .frame(width: 230 * size, height: 230 * size)
                            Text(label).font(.title3.weight(.semibold)).foregroundStyle(.white).shadow(radius: 2)
                        }
                        .frame(width: 230, height: 230)
                    }
                    Hint("The vibration swells as you breathe in, ticks softly on holds, and fades as you breathe out.")
                }
                .frame(maxWidth: .infinity)
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Menu {
                        ForEach(presets, id: \.0) { p in Button(p.0) { plan = p.1 } }
                    } label: { Label("Presets", systemImage: "slider.horizontal.3") }
                    Stepper("Breathe in: \(Int(plan.inhale)) s", value: $plan.inhale, in: 1...12, step: 1)
                    Stepper("Hold: \(Int(plan.hold1)) s", value: $plan.hold1, in: 0...12, step: 1)
                    Stepper("Breathe out: \(Int(plan.exhale)) s", value: $plan.exhale, in: 1...16, step: 1)
                    Stepper("Hold: \(Int(plan.hold2)) s", value: $plan.hold2, in: 0...12, step: 1)
                    Stepper("\(plan.cycles) cycles · \(String(format: "%.1f", plan.totalLength / 60)) min", value: $plan.cycles, in: 1...30)
                }
            }
            BigButton(title: playing ? "Stop" : "Begin", symbol: playing ? "stop.fill" : "wind",
                      tint: playing ? .red : .accentColor) {
                if playing { haptics.stop() } else { started = Date(); haptics.play(Breathing.pattern(plan)) }
            }
        }
    }
}
