import SwiftUI

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

    private var generation = 0

    /// Four pads you can tell apart by feel: single, double, triple, long buzz.
    static func taps(for pad: Int, at t: Double) -> (taps: [Tap], length: Double) {
        switch pad {
        case 0: return ([Tap(time: t, intensity: 1, sharpness: 0.9)], 0.25)
        case 1: return ([0, 0.12].map { Tap(time: t + $0, intensity: 1, sharpness: 0.9) }, 0.35)
        case 2: return ([0, 0.1, 0.2].map { Tap(time: t + $0, intensity: 1, sharpness: 0.9) }, 0.45)
        default: return ([Tap(time: t, intensity: 0.9, sharpness: 0.35, duration: 0.3)], 0.4)
        }
    }

    func start() {
        generation += 1
        sequence = [Int.random(in: 0..<4)]
        playSequence()
    }

    func stop() {
        generation += 1
        Haptics.shared.stop()
        phase = .idle
        lit = nil
        message = "Press Start, then feel the sequence."
    }

    private func after(_ seconds: Double, _ gen: Int, _ body: @escaping @MainActor (SimonGame) -> Void) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, self.generation == gen else { return }
            body(self)
        }
    }

    private func playSequence() {
        let gen = generation
        phase = .watching
        inputIndex = 0
        message = "Feel the sequence…"
        var taps: [Tap] = []
        var t = 0.3
        for pad in sequence {
            let (e, len) = Self.taps(for: pad, at: t)
            taps += e
            if showLights {
                after(t, gen) { $0.lit = pad }
                after(t + len, gen) { $0.lit = nil }
            }
            t += len + 0.35
        }
        Haptics.shared.play(HapticPattern(name: "Simon", taps: taps, length: t))
        after(t + 0.1, gen) { game in
            game.phase = .input
            game.message = "Your turn — repeat all \(game.sequence.count)."
        }
    }

    func tap(_ pad: Int) {
        guard phase != .watching else { return }
        let (e, len) = Self.taps(for: pad, at: 0)
        Haptics.shared.play(HapticPattern(name: "SimonPad", taps: e, length: len))
        guard phase == .input else { return }
        if pad == sequence[inputIndex] {
            inputIndex += 1
            if inputIndex == sequence.count {
                best = max(best, sequence.count)
                message = "Correct! Round \(sequence.count + 1) coming…"
                phase = .watching
                after(1.2, generation) { game in
                    game.sequence.append(Int.random(in: 0..<4))
                    game.playSequence()
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
        ScreenScroll {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        CardTitle(title: "Simon", subtitle: "Feel a sequence of buzzes, then repeat it on the pads. It grows by one each round.")
                        Spacer()
                        Pill(text: "Best \(game.best)", tint: .purple)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        ForEach(0..<4, id: \.self) { i in
                            Button { game.tap(i) } label: {
                                Text(names[i]).font(.headline).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 96)
                                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(colors[i].opacity(game.lit == i ? 1 : 0.55)))
                                    .scaleEffect(game.lit == i ? 1.04 : 1)
                                    .animation(.easeOut(duration: 0.1), value: game.lit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(game.message).font(.subheadline.weight(.medium))
                    Toggle("Show lights", isOn: $game.showLights)
                    if game.phase == .idle || game.phase == .over {
                        BigButton(title: game.phase == .over ? "Again" : "Start", symbol: "play.fill") { game.start() }
                    } else {
                        BigButton(title: "Quit", symbol: "xmark", tint: .red) { game.stop() }
                    }
                    Hint("Tap a pad any time between rounds to learn how it feels.")
                }
            }
        }
        .onDisappear { game.stop() }
    }
}

// MARK: - Hot & Cold: find the hidden spot by tap rate

@MainActor
final class HotColdGame: ObservableObject {
    @Published private(set) var target = HotColdGame.randomTarget()
    @Published private(set) var tries = 0
    @Published private(set) var found = 0
    @Published private(set) var message = "Touch the square and slide around. Faster, stronger taps mean warmer. Lift to guess."
    @Published private(set) var revealed = false

    private var interval = 0.4
    private var intensity: Float = 0.3
    private var ticker: Task<Void, Never>?
    private var last = CGPoint(x: 0.5, y: 0.5)

    static func randomTarget() -> CGPoint { CGPoint(x: .random(in: 0.12...0.88), y: .random(in: 0.12...0.88)) }

    func touch(_ p: CGPoint) {
        last = p
        let d = hypot(p.x - target.x, p.y - target.y)
        let closeness = max(0, 1 - d / 1.1)
        interval = 0.03 + 0.4 * (1 - pow(closeness, 1.5))
        intensity = Float(0.3 + 0.7 * closeness)
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                Haptics.shared.tap(self.intensity, sharpness: 0.8)
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            }
        }
    }

    /// The finger lifted: stop the ticks and count it as a guess.
    func lift() {
        ticker?.cancel(); ticker = nil
        tries += 1
        if hypot(last.x - target.x, last.y - target.y) <= 0.08 {
            found += 1
            revealed = true
            message = "Found it! New spot hidden."
            Haptics.shared.play(Presets.doubleTap)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 900_000_000)
                self?.revealed = false
                self?.target = Self.randomTarget()
            }
        } else {
            message = "Not there. Try again."
        }
    }

    func cancel() { ticker?.cancel(); ticker = nil }

    func reveal() {
        revealed = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self?.revealed = false
            self?.target = Self.randomTarget()
        }
    }
}

struct HotColdView: View {
    @StateObject private var game = HotColdGame()

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                CardTitle(title: "Hot & Cold", subtitle: game.message)
                Spacer()
            }
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [Color.blue.opacity(0.2), Color.orange.opacity(0.22)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.primary.opacity(0.1))
                    if game.revealed {
                        Circle().stroke(Color.green, lineWidth: 4).frame(width: side * 0.16, height: side * 0.16)
                            .position(x: game.target.x * side, y: game.target.y * side)
                    }
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let ox = (geo.size.width - side) / 2, oy = (geo.size.height - side) / 2
                        game.touch(CGPoint(x: min(1, max(0, (v.location.x - ox) / side)),
                                           y: min(1, max(0, (v.location.y - oy) / side))))
                    }
                    .onEnded { _ in game.lift() })
            }
            HStack {
                Pill(text: "Found \(game.found)", tint: .green)
                Pill(text: "Guesses \(game.tries)", tint: .secondary)
                Spacer()
                Button("Show me") { game.reveal() }
            }
        }
        .padding(16)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onDisappear { game.cancel() }
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

    private var onsets: [Double] = []
    private var taps: [Date] = []
    private var generation = 0

    func newRhythm() {
        let count = Int.random(in: 4...6)
        var t = 0.0
        onsets = [0]
        for _ in 1..<count {
            t += [0.25, 0.375, 0.5, 0.75].randomElement() ?? 0.5
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
        Haptics.shared.play(HapticPattern(name: "Rhythm",
                                          taps: onsets.map { Tap(time: $0, intensity: 1, sharpness: 0.85) },
                                          length: length))
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((length + 0.3) * 1_000_000_000))
            guard let self, self.generation == gen else { return }
            self.phase = .echo
            self.taps = []
            self.tapCount = 0
            self.message = "Your turn — tap it back (\(self.onsets.count) taps)."
        }
    }

    func tap() {
        guard phase == .echo else { return }
        Haptics.shared.tap(1, sharpness: 0.85)
        taps.append(Date())
        tapCount = taps.count
        guard taps.count == onsets.count else { return }
        var errSum = 0.0
        for i in 1..<taps.count {
            let mine = taps[i].timeIntervalSince(taps[i - 1])
            let target = onsets[i] - onsets[i - 1]
            errSum += abs(mine - target) / target
        }
        let err = errSum / Double(onsets.count - 1)
        let score = Int((max(0.0, 1.0 - err) * 100).rounded())
        accuracy = score
        phase = .done
        message = score >= 85 ? "Spot on!" : (score >= 60 ? "Close." : "Not quite — replay and try again.")
    }
}

struct RhythmEchoView: View {
    @StateObject private var game = RhythmGame()

    var body: some View {
        ScreenScroll {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        CardTitle(title: "Rhythm Echo", subtitle: "Feel a short rhythm, then tap it back. Only the spacing counts, not when you start.")
                        Spacer()
                        if let a = game.accuracy { BigValue(value: "\(a)", unit: "%") }
                    }
                    Button { game.tap() } label: {
                        Text(game.phase == .echo ? "Tap here (\(game.tapCount))" : "Tap pad")
                            .font(.title3.weight(.semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 150)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(game.phase == .echo ? Color.accentColor : Color.gray.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                    Text(game.message).font(.subheadline.weight(.medium))
                    HStack {
                        if game.phase == .done || game.phase == .echo { Button("Replay") { game.replay() } }
                        Spacer()
                    }
                    BigButton(title: "New Rhythm", symbol: "shuffle") { game.newRhythm() }
                }
            }
        }
    }
}
