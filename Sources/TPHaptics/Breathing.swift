import SwiftUI

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
    /// Inhale: taps speed up and strengthen. Hold: one soft tick a second.
    /// Exhale: taps slow and fade. Silence between cycles' empty holds.
    static func pattern(_ plan: BreathPlan) -> HapticPattern {
        var events: [HapticEvent] = []
        let ladder = TrackpadActuator.ladder

        func ramp(from r0: Double, to r1: Double, duration: Double, rising: Bool, start: Double) {
            guard duration > 0 else { return }
            var t = 0.0
            while t < duration {
                let f = t / duration
                let rate = r0 + (r1 - r0) * f
                let level = rising ? f : 1 - f
                events.append(HapticEvent(time: start + t, actuation: ladder[min(ladder.count - 1, Int(level * Double(ladder.count)))]))
                t += 1 / rate
            }
        }
        func hold(duration: Double, start: Double) {
            var t = 0.0
            while t < duration {
                events.append(HapticEvent(time: start + t, actuation: Strength.light.id))
                t += 1
            }
        }

        var t0 = 0.0
        for _ in 0..<max(1, plan.cycles) {
            ramp(from: 6, to: 45, duration: plan.inhale, rising: true, start: t0); t0 += plan.inhale
            hold(duration: plan.hold1, start: t0); t0 += plan.hold1
            ramp(from: 45, to: 6, duration: plan.exhale, rising: false, start: t0); t0 += plan.exhale
            hold(duration: plan.hold2, start: t0); t0 += plan.hold2
        }
        return HapticPattern(name: "Breathing", detail: "", events: events, length: t0)
    }
}

struct BreathingView: View {
    @ObservedObject private var player = AppModel.shared.player
    @State private var plan = BreathPlan()
    @State private var started: Date?

    private let presets: [(String, BreathPlan)] = [
        ("Box 4-4-4-4", BreathPlan(inhale: 4, hold1: 4, exhale: 4, hold2: 4, cycles: 6)),
        ("Relax 4-7-8", BreathPlan(inhale: 4, hold1: 7, exhale: 8, hold2: 0, cycles: 4)),
        ("Calm 5-5", BreathPlan(inhale: 5, hold1: 0, exhale: 5, hold2: 0, cycles: 8)),
    ]

    /// Current phase label and circle size (0…1) for the on-screen guide.
    private func phase(at date: Date) -> (String, Double) {
        guard let started, player.playingName == "Breathing" else { return ("Ready", 0.25) }
        let t = date.timeIntervalSince(started)
        guard t < plan.totalLength else { return ("Done", 0.25) }
        var c = t.truncatingRemainder(dividingBy: plan.cycleLength)
        if c < plan.inhale { return ("Breathe in", 0.25 + 0.75 * c / plan.inhale) }
        c -= plan.inhale
        if c < plan.hold1 { return ("Hold", 1) }
        c -= plan.hold1
        if c < plan.exhale { return ("Breathe out", 1 - 0.75 * c / plan.exhale) }
        return ("Hold", 0.25)
    }

    var body: some View {
        let playing = player.playingName == "Breathing"
        Screen {
            Card {
                HStack(spacing: 24) {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                        let (label, size) = phase(at: ctx.date)
                        ZStack {
                            Circle().fill(Color.mint.opacity(0.14)).frame(width: 220, height: 220)
                            Circle()
                                .fill(RadialGradient(colors: [Color.mint.opacity(0.75), Color.teal.opacity(0.45)],
                                                     center: .center, startRadius: 4, endRadius: 110))
                                .frame(width: 220 * size, height: 220 * size)
                            Text(label).font(.title3.weight(.semibold)).foregroundStyle(.white).shadow(radius: 2)
                        }
                        .frame(width: 220, height: 220)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        CardTitle(title: "Follow the taps",
                                  subtitle: "Taps quicken and strengthen as you breathe in, tick softly on holds, and fade as you breathe out.")
                        Menu {
                            ForEach(presets, id: \.0) { p in Button(p.0) { plan = p.1 } }
                        } label: { Label("Presets", systemImage: "slider.horizontal.3") }
                        .fixedSize()
                        stepper("Breathe in", $plan.inhale, 1...12)
                        stepper("Hold", $plan.hold1, 0...12)
                        stepper("Breathe out", $plan.exhale, 1...16)
                        stepper("Hold", $plan.hold2, 0...12)
                        Stepper("\(plan.cycles) cycles · \(String(format: "%.1f", plan.totalLength / 60)) min",
                                value: $plan.cycles, in: 1...30)
                    }
                }
            }

            HStack {
                Spacer()
                BigButton(title: playing ? "Stop" : "Begin", symbol: playing ? "stop.fill" : "wind",
                          tint: playing ? .red : .accentColor) {
                    if playing { player.stop(); started = nil }
                    else { started = Date(); player.play(Breathing.pattern(plan), loop: false) }
                }
            }
        }
    }

    private func stepper(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        Stepper("\(title): \(Int(value.wrappedValue)) s", value: value, in: range, step: 1)
    }
}
