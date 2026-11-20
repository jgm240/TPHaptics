import SwiftUI

// MARK: - Patterns

struct PatternsView: View {
    @Binding var loop: Bool
    @ObservedObject private var player = AppModel.shared.player
    @ObservedObject private var library = PatternLibrary.shared

    var body: some View {
        Screen {
            group("Built-in", Presets.all)
            if !library.patterns.isEmpty {
                group("My patterns", library.patterns.map(\.pattern))
            }
        }
    }

    private func group(_ title: String, _ items: [HapticPattern]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 12)], spacing: 12) {
                ForEach(items, id: \.name) { p in
                    let playing = player.playingName == p.name
                    Card {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(p.name).font(.headline)
                                Text(p.detail).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                                MiniWave(events: p.events, length: p.length, tint: playing ? .green : .accentColor)
                            }
                            RoundPlayButton(playing: playing) {
                                playing ? player.stop() : player.play(p, loop: loop)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Sequencer

struct SequencerView: View {
    @Binding var loop: Bool
    @ObservedObject private var player = AppModel.shared.player
    @State private var steps: [Int] = [4, 0, 1, 0, 3, 0, 1, 0, 4, 0, 1, 0, 3, 1, 2, 0]   // 0 = rest, 1…4 = strength
    @State private var bpm: Double = 120

    private var pattern: HapticPattern {
        let stepDur = 60.0 / bpm / 4.0
        return HapticPattern(
            name: "Sequencer", detail: "",
            events: steps.enumerated().map { i, v in
                HapticEvent(time: Double(i) * stepDur, actuation: v == 0 ? nil : Strength.all[v - 1].id)
            },
            length: Double(steps.count) * stepDur,
            normalize: false)
    }

    var body: some View {
        Screen {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    CardTitle(title: "Steps", subtitle: "Click a step to cycle: rest → light → medium → strong → max.")
                    HStack(spacing: 14) {
                        ForEach(0..<4, id: \.self) { group in
                            HStack(spacing: 6) {
                                ForEach(group * 4..<group * 4 + 4, id: \.self) { i in
                                    StepCell(level: steps[i],
                                             isPlayhead: player.playingName == "Sequencer" && player.playhead == i)
                                        .onTapGesture {
                                            steps[i] = (steps[i] + 1) % (Strength.all.count + 1)
                                            if steps[i] > 0 { Haptics.tick(Strength.all[steps[i] - 1].id) }
                                        }
                                }
                            }
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        CardTitle(title: "Tempo")
                        Spacer()
                        BigValue(value: "\(Int(bpm))", unit: "BPM")
                    }
                    Slider(value: $bpm, in: 40...240, step: 1)
                }
            }

            HStack {
                Button("Clear") { steps = Array(repeating: 0, count: 16) }
                Button("Randomize") { steps = (0..<16).map { _ in Int.random(in: 0...4) } }
                Spacer()
                let playing = player.playingName == "Sequencer"
                BigButton(title: playing ? "Stop" : "Play", symbol: playing ? "stop.fill" : "play.fill",
                          tint: playing ? .red : .accentColor) {
                    playing ? player.stop() : player.play(pattern, loop: loop)
                }
            }
        }
        .onChange(of: steps) { _ in if player.playingName == "Sequencer" { player.update(pattern) } }
        .onChange(of: bpm) { _ in if player.playingName == "Sequencer" { player.update(pattern) } }
    }
}

private struct StepCell: View {
    let level: Int
    let isPlayhead: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07))
            if level > 0 {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.55 + 0.1 * Double(level)))
                    .frame(height: 12 + 52 * CGFloat(level) / 4)
            }
        }
        .frame(width: 42, height: 64)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(isPlayhead ? Color.primary : .clear, lineWidth: 2))
        .scaleEffect(isPlayhead ? 1.06 : 1)
        .animation(.easeOut(duration: 0.08), value: isPlayhead)
        .contentShape(Rectangle())
    }
}

// MARK: - Buzz

struct BuzzView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var player = AppModel.shared.player

    /// Logarithmic slider so 1–10 ms gets as much travel as 100–1000 ms.
    private var intervalSlider: Binding<Double> {
        let lo = AppModel.minBuzzIntervalMS, hi = AppModel.maxBuzzIntervalMS
        return Binding(
            get: { log(min(hi, max(lo, model.buzzIntervalMS)) / lo) / log(hi / lo) },
            set: { t in
                let ms = lo * pow(hi / lo, t)
                model.buzzIntervalMS = ms >= 10 ? ms.rounded() : (ms * 10).rounded() / 10
            })
    }

    var body: some View {
        let rate = 1000 / max(1, model.buzzIntervalMS)
        let playing = player.playingName == "Buzz"
        Screen {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        CardTitle(title: "Interval", subtitle: "Time between taps. Short intervals blur into a vibration.")
                        Spacer()
                        BigValue(value: model.buzzIntervalMS >= 10 ? "\(Int(model.buzzIntervalMS))" : String(format: "%.1f", model.buzzIntervalMS),
                                 unit: "ms")
                    }
                    Slider(value: intervalSlider, in: 0...1)
                    HStack {
                        Text(String(format: "%.0f taps per second", rate)).foregroundStyle(.secondary)
                        Spacer()
                        Text("Exact value")
                        TextField("ms", value: $model.buzzIntervalMS, format: .number.precision(.fractionLength(0...1)))
                            .multilineTextAlignment(.trailing).frame(width: 64).textFieldStyle(.roundedBorder)
                    }
                    .font(.callout)
                    if model.buzzIntervalMS < 6 {
                        Pill(text: "At the actuator's top speed (~4–6 ms per click)", tint: .orange)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        CardTitle(title: "Duration")
                        Spacer()
                        Toggle("Continuous", isOn: $model.buzzContinuous).toggleStyle(.switch).controlSize(.small)
                    }
                    HStack {
                        Slider(value: $model.buzzDuration, in: 0.5...10, step: 0.5)
                        Text(String(format: "%.1f s", model.buzzDuration)).monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                    .disabled(model.buzzContinuous)
                    .opacity(model.buzzContinuous ? 0.4 : 1)
                }
            }

            HStack {
                Spacer()
                BigButton(title: playing ? "Stop Buzz" : "Start Buzz", symbol: playing ? "stop.fill" : "waveform",
                          tint: playing ? .red : .accentColor) {
                    playing ? player.stop() : player.play(model.buzzPattern(), loop: model.buzzContinuous)
                }
            }
        }
        .onChange(of: model.buzzIntervalMS) { _ in
            if playing && model.buzzContinuous { player.update(model.buzzPattern()) }
        }
    }
}

// MARK: - Actuation test

struct TestView: View {
    @ObservedObject private var player = AppModel.shared.player

    var body: some View {
        Screen {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    CardTitle(title: "Raw actuation IDs",
                              subtitle: "Fires one ID once, ignoring the Strength slider. On this trackpad IDs 1–6 click; 7–20 are accepted but silent.")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 10), spacing: 10) {
                        ForEach(1...20, id: \.self) { id in
                            Button { player.tap(Int32(id)) } label: {
                                Text("\(id)")
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(id <= 6 ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)))
                                    .foregroundStyle(id <= 6 ? Color.accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
