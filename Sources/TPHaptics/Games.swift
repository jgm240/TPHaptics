import SwiftUI

struct GamesView: View {
    @State private var game = 0

    var body: some View {
        Screen {
            Picker("", selection: $game) {
                Text("Simon").tag(0)
                Text("Hot & Cold").tag(1)
                Text("Rhythm Echo").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)

            switch game {
            case 0: SimonView()
            case 1: HotColdView()
            default: RhythmEchoView()
            }
        }
    }
}

// MARK: - Simon: repeat a sequence of four distinct buzzes

@MainActor
final class SimonGame: ObservableObject {
    enum Phase { case idle, watching, input, over }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var sequence: [Int] = []
    @Published private(set) var inputIndex = 0
    @Published private(set) var lit: Int?
    @Published private(set) var message = "Press Start, then feel the sequence."
    @Published private(set) var best = 0
    @Published var showLights = false

    private let player = PatternPlayer()
    private var generation = 0

    /// Four pads you can tell apart by feel: single, double, triple, buzz.
    static func events(for pad: Int, at t: Double) -> (events: [HapticEvent], length: Double) {
        let id = Strength.max.id
        switch pad {
        case 0: return ([HapticEvent(time: t, actuation: id)], 0.25)
        case 1: return ([0, 0.12].map { HapticEvent(time: t + $0, actuation: id) }, 0.35)
        case 2: return ([0, 0.1, 0.2].map { HapticEvent(time: t + $0, actuation: id) }, 0.45)
        default: return ((0..<25).map { HapticEvent(time: t + Double($0) * 0.01, actuation: id) }, 0.3)
        }
    }

    func start() {
        generation += 1
        sequence = [Int.random(in: 0..<4)]
        playSequence()
    }

    func stop() {
        generation += 1
        player.stop()
        phase = .idle
        lit = nil
        message = "Press Start, then feel the sequence."
    }

    private func playSequence() {
        let gen = generation
        phase = .watching
        inputIndex = 0
        message = "Feel the sequence…"
        var events: [HapticEvent] = []
        var t = 0.3
        for pad in sequence {
            let (e, len) = Self.events(for: pad, at: t)
            events += e
            if showLights {
                DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                    guard let self, self.generation == gen else { return }
                    self.lit = pad
                    DispatchQueue.main.asyncAfter(deadline: .now() + len) { [weak self] in
                        if self?.generation == gen { self?.lit = nil }
                    }
                }
            }
            t += len + 0.35
        }
        player.play(HapticPattern(name: "Simon", detail: "", events: events, length: t), loop: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + t + 0.1) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.phase = .input
            self.message = "Your turn — repeat all \(self.sequence.count)."
        }
    }

    func tap(_ pad: Int) {
        guard phase != .watching else { return }
        let (e, len) = Self.events(for: pad, at: 0)
        player.play(HapticPattern(name: "SimonPad", detail: "", events: e, length: len), loop: false)
        guard phase == .input else { return }
        if pad == sequence[inputIndex] {
            inputIndex += 1
            if inputIndex == sequence.count {
                best = max(best, sequence.count)
                message = "Correct! Round \(sequence.count + 1) coming…"
                phase = .watching
                let gen = generation
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    guard let self, self.generation == gen else { return }
                    self.sequence.append(Int.random(in: 0..<4))
                    self.playSequence()
                }
            }
        } else {
            phase = .over
            message = "Wrong pad. You cleared \(sequence.count - 1) round\(sequence.count == 2 ? "" : "s")."
        }
    }
}

struct SimonView: View {
    @StateObject private var game = SimonGame()
    private let colors: [Color] = [.red, .blue, .green, .orange]
    private let names = ["Single", "Double", "Triple", "Buzz"]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    CardTitle(title: "Simon", subtitle: "Feel a sequence of buzzes, then repeat it on the pads. It gets one longer each round.")
                    Spacer()
                    Pill(text: "Best: \(game.best)", tint: .purple)
                }
                HStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { i in
                        Button { game.tap(i) } label: {
                            VStack(spacing: 6) {
                                Text(names[i]).font(.headline)
                                Text("pad \(i + 1)").font(.caption).opacity(0.8)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 90)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(colors[i].opacity(game.lit == i ? 1 : 0.55)))
                            .scaleEffect(game.lit == i ? 1.04 : 1)
                            .animation(.easeOut(duration: 0.1), value: game.lit)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Text(game.message).font(.callout.weight(.medium))
                    Spacer()
                    Toggle("Show lights", isOn: $game.showLights).toggleStyle(.switch).controlSize(.small)
                    if game.phase == .idle || game.phase == .over {
                        BigButton(title: game.phase == .over ? "Again" : "Start", symbol: "play.fill") { game.start() }
                    } else {
                        BigButton(title: "Quit", symbol: "xmark", tint: .red) { game.stop() }
                    }
                }
                Hint("Tap a pad any time between rounds to learn how it feels.")
            }
        }
        .onDisappear { game.stop() }
    }
}

// MARK: - Hot & Cold: find the hidden spot by click rate

@MainActor
final class HotColdGame: ObservableObject {
    static let size: CGFloat = 340
    @Published private(set) var target = HotColdGame.randomTarget()
    @Published private(set) var tries = 0
    @Published private(set) var found = 0
    @Published private(set) var message = "Move the pointer over the square. Faster taps mean warmer."
    @Published private(set) var revealed = false

    private let player = PatternPlayer()
    private var lastInterval = 0.0

    static func randomTarget() -> CGPoint {
        CGPoint(x: .random(in: 30...(size - 30)), y: .random(in: 30...(size - 30)))
    }

    func hover(_ p: CGPoint) {
        let d = hypot(p.x - target.x, p.y - target.y)
        let closeness = max(0, 1 - d / (Self.size * 1.1))
        let interval = 0.012 + 0.25 * (1 - pow(closeness, 1.5))
        let pattern = HapticPattern(name: "Hot & Cold", detail: "",
                                    events: [HapticEvent(time: 0, actuation: Strength.max.id)], length: interval)
        if !player.isPlaying { player.play(pattern, loop: true); lastInterval = interval }
        else if abs(interval - lastInterval) / lastInterval > 0.05 { player.update(pattern); lastInterval = interval }
    }

    func leave() { player.stop(); lastInterval = 0 }

    func tap(_ p: CGPoint) {
        tries += 1
        if hypot(p.x - target.x, p.y - target.y) <= 24 {
            found += 1
            revealed = true
            message = "Found it in \(tries) tries total! New spot hidden."
            player.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.revealed = false
                self?.target = Self.randomTarget()
            }
        } else {
            message = "Not there. Keep moving."
        }
    }

    func giveUp() { revealed = true; DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
        self?.revealed = false; self?.target = Self.randomTarget() } }
}

struct HotColdView: View {
    @StateObject private var game = HotColdGame()

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [Color.blue.opacity(0.18), Color.orange.opacity(0.18)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    if game.revealed {
                        Circle().stroke(Color.green, lineWidth: 3).frame(width: 48, height: 48)
                            .position(game.target)
                    }
                }
                .frame(width: HotColdGame.size, height: HotColdGame.size)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.cardStroke))
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p): game.hover(p)
                    case .ended: game.leave()
                    }
                }
                .gesture(SpatialTapGesture().onEnded { game.tap($0.location) })

                VStack(alignment: .leading, spacing: 12) {
                    CardTitle(title: "Hot & Cold", subtitle: "A spot is hidden in the square. The closer your pointer, the faster the taps. Click when you think you're on it.")
                    Text(game.message).font(.callout.weight(.medium))
                    HStack(spacing: 8) {
                        Pill(text: "Found: \(game.found)", tint: .green)
                        Pill(text: "Clicks: \(game.tries)", tint: .secondary)
                    }
                    Button("Show me") { game.giveUp() }
                }
            }
        }
        .onDisappear { game.leave() }
    }
}

// MARK: - Rhythm Echo: feel a rhythm, tap it back

@MainActor
final class RhythmGame: ObservableObject {
    enum Phase { case idle, playing, echo, done }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var message = "Press New Rhythm."
    @Published private(set) var accuracy: Int?
    @Published private(set) var tapCount = 0

    private let player = PatternPlayer()
    private var onsets: [Double] = []
    private var taps: [Date] = []
    private var generation = 0

    func newRhythm() {
        let count = Int.random(in: 4...6)
        var t = 0.0
        onsets = [0]
        for _ in 1..<count {
            t += [0.25, 0.375, 0.5, 0.75].randomElement()!
            onsets.append(t)
        }
        replay()
    }

    func replay() {
        guard !onsets.isEmpty else { return }
        generation += 1
        let gen = generation
        phase = .playing
        accuracy = nil
        message = "Feel the rhythm…"
        let length = (onsets.last ?? 0) + 0.4
        player.play(HapticPattern(name: "Rhythm", detail: "",
                                  events: onsets.map { HapticEvent(time: $0, actuation: Strength.max.id) },
                                  length: length), loop: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + length + 0.3) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.phase = .echo
            self.taps = []
            self.tapCount = 0
            self.message = "Your turn — tap it back (\(self.onsets.count) taps)."
        }
    }

    func tap() {
        guard phase == .echo else { return }
        Haptics.tick(Strength.max.id)
        taps.append(Date())
        tapCount = taps.count
        guard taps.count == onsets.count else { return }
        var mine: [Double] = []
        var target: [Double] = []
        for i in 1..<taps.count {
            mine.append(taps[i].timeIntervalSince(taps[i - 1]))
            target.append(onsets[i] - onsets[i - 1])
        }
        var errSum = 0.0
        for i in 0..<target.count { errSum += abs(mine[i] - target[i]) / target[i] }
        let err = errSum / Double(target.count)
        let score = Int((max(0.0, 1.0 - err) * 100).rounded())
        accuracy = score
        phase = .done
        message = score >= 85 ? "Spot on!" : score >= 60 ? "Close." : "Not quite — replay and try again."
    }
}

struct RhythmEchoView: View {
    @StateObject private var game = RhythmGame()

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    CardTitle(title: "Rhythm Echo", subtitle: "Feel a short rhythm, then tap it back on the pad. Only the spacing counts, not when you start.")
                    Spacer()
                    if let a = game.accuracy { BigValue(value: "\(a)", unit: "%") }
                }
                Button { game.tap() } label: {
                    Text(game.phase == .echo ? "Tap here  (\(game.tapCount))" : "Tap pad")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 110)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(game.phase == .echo ? Color.accentColor : Color.gray.opacity(0.5)))
                }
                .buttonStyle(.plain)
                HStack {
                    Text(game.message).font(.callout.weight(.medium))
                    Spacer()
                    if game.phase == .done || game.phase == .echo { Button("Replay") { game.replay() } }
                    BigButton(title: "New Rhythm", symbol: "shuffle") { game.newRhythm() }
                }
            }
        }
    }
}
