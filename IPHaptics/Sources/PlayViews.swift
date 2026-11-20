import SwiftUI

// MARK: - Patterns

struct PatternsView: View {
    @ObservedObject private var haptics = Haptics.shared
    @ObservedObject private var library = PatternLibrary.shared
    @State private var loop = false

    var body: some View {
        ScreenScroll {
            Toggle("Loop", isOn: $loop).padding(.horizontal, 4)
            group("Built-in", Presets.all, deletable: false)
            if !library.patterns.isEmpty {
                group("My patterns", library.patterns, deletable: true)
            }
        }
    }

    private func group(_ title: String, _ items: [HapticPattern], deletable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ForEach(items) { p in
                let playing = haptics.playingName == p.name
                Card {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(p.name).font(.headline)
                            Text(p.detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            MiniWave(pattern: p, tint: playing ? .green : .accentColor)
                        }
                        RoundPlayButton(playing: playing) { playing ? haptics.stop() : haptics.play(p, loop: loop) }
                    }
                }
                .contextMenu {
                    if deletable {
                        Button(role: .destructive) { library.delete(p.id) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
    }
}

// MARK: - Sequencer

struct SequencerView: View {
    @ObservedObject private var haptics = Haptics.shared
    @State private var steps: [Int] = [4, 0, 1, 0, 3, 0, 1, 0, 4, 0, 1, 0, 3, 1, 2, 0]   // 0 = rest, 1…4 = strength
    @State private var bpm = 120.0
    @State private var startedAt = Date()

    private let levels: [Float] = [0, 0.3, 0.55, 0.8, 1.0]
    private var stepDur: Double { 60 / bpm / 4 }

    private var pattern: HapticPattern {
        HapticPattern(name: "Sequencer", detail: "",
                      taps: steps.enumerated().compactMap { i, v in
                          v == 0 ? nil : Tap(time: Double(i) * stepDur, intensity: levels[v], sharpness: 0.75)
                      },
                      length: Double(steps.count) * stepDur)
    }

    var body: some View {
        let playing = haptics.playingName == "Sequencer"
        ScreenScroll {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    CardTitle(title: "Steps", subtitle: "Tap a step to cycle: rest → light → medium → strong → max.")
                    TimelineView(.animation) { tl in
                        let head: Int? = playing
                            ? Int(tl.date.timeIntervalSince(startedAt) / stepDur) % steps.count : nil
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(0..<steps.count, id: \.self) { i in
                                StepCell(level: steps[i], isPlayhead: head == i)
                                    .onTapGesture {
                                        steps[i] = (steps[i] + 1) % levels.count
                                        if steps[i] > 0 { haptics.tap(levels[steps[i]], sharpness: 0.75) }
                                    }
                            }
                        }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { CardTitle(title: "Tempo"); Spacer(); BigValue(value: "\(Int(bpm))", unit: "BPM") }
                    Slider(value: $bpm, in: 40...240, step: 1)
                }
            }
            HStack {
                Button("Clear") { steps = Array(repeating: 0, count: 16) }
                Button("Randomize") { steps = (0..<16).map { _ in Int.random(in: 0...4) } }
                Spacer()
            }
            BigButton(title: playing ? "Stop" : "Play", symbol: playing ? "stop.fill" : "play.fill",
                      tint: playing ? .red : .accentColor) {
                if playing { haptics.stop() } else { startedAt = Date(); haptics.play(pattern, loop: true) }
            }
        }
        // Edits restart the loop so changes are heard straight away.
        .onChange(of: steps) { _ in if playing { startedAt = Date(); haptics.play(pattern, loop: true) } }
        .onChange(of: bpm) { _ in if playing { startedAt = Date(); haptics.play(pattern, loop: true) } }
    }
}

private struct StepCell: View {
    let level: Int
    let isPlayhead: Bool
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07))
            if level > 0 {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.55 + 0.1 * Double(level)))
                    .frame(height: 14 + 56 * CGFloat(level) / 4)
            }
        }
        .frame(height: 72)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(isPlayhead ? Color.primary : .clear, lineWidth: 2))
        .scaleEffect(isPlayhead ? 1.05 : 1)
        .animation(.easeOut(duration: 0.08), value: isPlayhead)
        .contentShape(Rectangle())
    }
}

// MARK: - Buzz

struct BuzzView: View {
    @ObservedObject private var haptics = Haptics.shared
    @State private var mode = 0                       // 0 = rapid taps, 1 = continuous hum
    @State private var intervalMS = 50.0
    @State private var duration = 2.0
    @State private var continuous = false
    @State private var humIntensity = 0.8
    @State private var humSharpness = 0.5
    @State private var humOn = false

    private var tapPattern: HapticPattern {
        let interval = max(0.01, intervalMS / 1000)
        if continuous {
            return HapticPattern(name: "Buzz", taps: [Tap(time: 0, intensity: 0.9, sharpness: 0.8)], length: interval)
        }
        let n = max(1, Int(duration / interval))
        return HapticPattern(name: "Buzz", taps: (0..<n).map { Tap(time: Double($0) * interval, intensity: 0.9, sharpness: 0.8) },
                             length: Double(n) * interval)
    }

    var body: some View {
        let playing = haptics.playingName == "Buzz"
        ScreenScroll {
            Picker("", selection: $mode) {
                Text("Rapid taps").tag(0)
                Text("Continuous hum").tag(1)
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _ in haptics.stop(); humOn = false }

            if mode == 0 {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { CardTitle(title: "Interval", subtitle: "Time between taps."); Spacer()
                            BigValue(value: "\(Int(intervalMS))", unit: "ms") }
                        Slider(value: $intervalMS, in: 10...1000, step: 5)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { CardTitle(title: "Duration"); Spacer()
                            Toggle("Continuous", isOn: $continuous).labelsHidden(); Text("Continuous").font(.footnote) }
                        HStack {
                            Slider(value: $duration, in: 0.5...10, step: 0.5)
                            Text(String(format: "%.1f s", duration)).monospacedDigit().frame(width: 52, alignment: .trailing)
                        }
                        .disabled(continuous).opacity(continuous ? 0.4 : 1)
                    }
                }
                BigButton(title: playing ? "Stop Buzz" : "Start Buzz", symbol: playing ? "stop.fill" : "waveform",
                          tint: playing ? .red : .accentColor) {
                    playing ? haptics.stop() : haptics.play(tapPattern, loop: continuous)
                }
            } else {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        CardTitle(title: "A steady vibration",
                                  subtitle: "The iPhone's motor can run continuously, with intensity and sharpness you can change while it runs.")
                        sliderRow("Intensity", $humIntensity)
                        sliderRow("Sharpness", $humSharpness, low: "soft", high: "crisp")
                    }
                }
                BigButton(title: humOn ? "Stop Hum" : "Start Hum", symbol: humOn ? "stop.fill" : "waveform.path",
                          tint: humOn ? .red : .accentColor) {
                    if humOn { haptics.hum.end() } else { haptics.hum.begin(intensity: Float(humIntensity), sharpness: Float(humSharpness)) }
                    humOn.toggle()
                }
                .onChange(of: humIntensity) { _ in if humOn { haptics.hum.update(intensity: Float(humIntensity), sharpness: Float(humSharpness)) } }
                .onChange(of: humSharpness) { _ in if humOn { haptics.hum.update(intensity: Float(humIntensity), sharpness: Float(humSharpness)) } }
            }
        }
        .onDisappear { haptics.hum.end(); humOn = false }
    }

    private func sliderRow(_ title: String, _ value: Binding<Double>, low: String = "", high: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue * 100))%").foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: value, in: 0...1)
            if !low.isEmpty { HStack { Text(low); Spacer(); Text(high) }.font(.caption).foregroundStyle(.secondary) }
        }
    }
}
