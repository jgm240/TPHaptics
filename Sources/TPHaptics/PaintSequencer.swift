import SwiftUI

/// Turns painted lines into taps. x is time (0…1 across the pattern), y is strength (0…1, 1 = top).
/// The pattern is sampled every `interval` seconds; where a line passes, a tap fires at the line's height.
enum PaintPattern {
    /// Heights below this are "off": the line there plays nothing.
    static let silentBelow = 0.08

    /// The actuation ID for a painted height, or nil in the silent strip.
    static func actuation(for v: Double) -> Int32? {
        guard v >= silentBelow else { return nil }
        let ladder = TrackpadActuator.ladder
        let rank = min(ladder.count - 1, Int((v - silentBelow) / (1 - silentBelow) * Double(ladder.count)))
        return ladder[rank]
    }

    static func events(strokes: [[CGPoint]], length: Double, interval: Double) -> [HapticEvent] {
        let n = max(1, Int((length / interval).rounded(.down)))
        var level = [Double?](repeating: nil, count: n)

        func mark(_ bin: Int, _ y: Double) {
            guard bin >= 0, bin < n else { return }
            level[bin] = max(level[bin] ?? 0, y)
        }

        for stroke in strokes {
            guard let first = stroke.first else { continue }
            if stroke.count == 1 { mark(Int(first.x * CGFloat(n)), Double(first.y)); continue }
            for i in 1..<stroke.count {
                var a = stroke[i - 1], b = stroke[i]
                if a.x > b.x { swap(&a, &b) }                       // lines may be drawn right to left
                let b0 = max(0, Int(floor(a.x * CGFloat(n))))
                let b1 = max(b0, Int(floor(b.x * CGFloat(n))))
                for bin in b0...b1 {
                    let center = (CGFloat(bin) + 0.5) / CGFloat(n)
                    let t: CGFloat = b.x > a.x ? min(1, max(0, (center - a.x) / (b.x - a.x))) : 0
                    mark(bin, Double(a.y + (b.y - a.y) * t))
                }
            }
        }

        return level.enumerated().compactMap { i, v in
            guard let v, let id = actuation(for: v) else { return nil }
            return HapticEvent(time: Double(i) * interval, actuation: id)
        }
    }

    static func pattern(strokes: [[CGPoint]], length: Double, interval: Double, name: String = "Paint") -> HapticPattern {
        HapticPattern(name: name, detail: "Painted pattern",
                      events: events(strokes: strokes, length: length, interval: interval),
                      length: length,
                      normalize: false)       // heights map to absolute strengths; the master slider still scales them
    }

    /// Starting points to paint over.
    static let examples: [(name: String, strokes: [[CGPoint]])] = {
        func curve(_ f: (Double) -> Double) -> [CGPoint] {
            (0...60).map { i in let x = Double(i) / 60; return CGPoint(x: x, y: min(1, max(0, f(x)))) }
        }
        return [
            ("Ramp up", [curve { 0.12 + 0.88 * $0 }]),
            ("Swell", [curve { 0.1 + 0.9 * sin(Double.pi * $0) }]),
            ("Wobble", [curve { 0.55 + 0.38 * sin(6 * Double.pi * $0) }]),
            ("Staircase", [curve { 0.15 + 0.85 * floor($0 * 6) / 5 }]),
            ("Pulses", (0..<5).map { k in
                let x0 = 0.04 + Double(k) * 0.19
                return [CGPoint(x: x0, y: 0.92), CGPoint(x: x0 + 0.09, y: 0.92)]
            }),
        ]
    }()
}

struct PaintView: View {
    @Binding var loop: Bool
    @ObservedObject private var player = AppModel.shared.player
    @ObservedObject private var library = PatternLibrary.shared

    @State private var strokes: [[CGPoint]] = []
    @State private var length = 4.0
    @State private var interval = 0.025
    @State private var name = "My Painting"
    @State private var startedAt: Date?
    @State private var lastTick = Date.distantPast
    @State private var message: String?

    private let canvasHeight: CGFloat = 300

    private var pattern: HapticPattern { PaintPattern.pattern(strokes: strokes, length: length, interval: interval) }

    var body: some View {
        let playing = player.playingName == "Paint"
        let tapCount = PaintPattern.events(strokes: strokes, length: length, interval: interval).count
        Screen {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        CardTitle(title: "Paint a line",
                                  subtitle: "Left to right is time, height is strength. Gaps are silence, and the bottom strip is off. You feel each strength as you paint.")
                        Spacer()
                        Menu {
                            ForEach(PaintPattern.examples, id: \.name) { ex in
                                Button(ex.name) { strokes = ex.strokes }
                            }
                        } label: { Label("Start from…", systemImage: "wand.and.stars") }
                        .fixedSize()
                    }
                    canvas
                    HStack(spacing: 18) {
                        HStack {
                            Text("Length")
                            Slider(value: $length, in: 1...10, step: 0.5).frame(width: 150)
                            Text(String(format: "%.1f s", length)).monospacedDigit().frame(width: 48, alignment: .trailing)
                        }
                        HStack {
                            Text("Tap spacing")
                            Slider(value: $interval, in: 0.005...0.1, step: 0.005).frame(width: 150)
                            Text("\(Int((interval * 1000).rounded())) ms").monospacedDigit().frame(width: 48, alignment: .trailing)
                        }
                        Spacer()
                        Text("\(tapCount) taps").foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }

            HStack(spacing: 10) {
                Button { if !strokes.isEmpty { strokes.removeLast() } } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .disabled(strokes.isEmpty)
                Button { strokes = [] } label: { Label("Clear", systemImage: "trash") }
                    .disabled(strokes.isEmpty)
                Spacer()
                if let m = message { Text(m).font(.callout).foregroundStyle(.secondary) }
                TextField("Name", text: $name).textFieldStyle(.roundedBorder).frame(width: 160)
                Button { save() } label: { Label("Save", systemImage: "tray.and.arrow.down") }
                    .disabled(tapCount == 0 || name.trimmingCharacters(in: .whitespaces).isEmpty)
                BigButton(title: playing ? "Stop" : "Play", symbol: playing ? "stop.fill" : "play.fill",
                          tint: playing ? .red : .accentColor) {
                    if playing { player.stop() }
                    else { startedAt = Date(); player.play(pattern, loop: loop) }
                }
                .disabled(tapCount == 0)
            }

            Hint("Draw as many lines as you like; where lines overlap in time, the higher one wins. Lower the tap spacing for a denser, smoother feel (about 5 ms is the actuator's limit). Saved paintings appear on the Patterns screen.")
        }
        .onChange(of: strokes) { _ in if playing { player.update(pattern) } }
        .onChange(of: length) { _ in if playing { player.update(pattern) } }
        .onChange(of: interval) { _ in if playing { player.update(pattern) } }
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    drawBackground(ctx, size)
                    drawStems(ctx, size)
                    for stroke in strokes where !stroke.isEmpty {
                        var path = Path()
                        path.move(to: point(stroke[0], size))
                        if stroke.count == 1 { path.addLine(to: point(stroke[0], size)) }
                        for p in stroke.dropFirst() { path.addLine(to: point(p, size)) }
                        ctx.stroke(path, with: .color(.orange),
                                   style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    }
                }

                // Playhead
                TimelineView(.animation) { tl in
                    if player.playingName == "Paint", let s = startedAt {
                        let t = tl.date.timeIntervalSince(s)
                        let pos = loop ? t.truncatingRemainder(dividingBy: length) : t
                        if pos <= length {
                            Rectangle().fill(Color.primary.opacity(0.75)).frame(width: 2, height: h)
                                .offset(x: CGFloat(pos / length) * w - 1)
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.cardStroke))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let p = CGPoint(x: min(1, max(0, v.location.x / w)), y: min(1, max(0, 1 - v.location.y / h)))
                    if v.translation == .zero && v.location == v.startLocation { strokes.append([p]) }
                    else if let last = strokes.last?.last, hypot(last.x - p.x, last.y - p.y) > 0.002 {
                        strokes[strokes.count - 1].append(p)
                    }
                    // Feel the strength you're painting
                    if Date().timeIntervalSince(lastTick) > 0.06, let id = PaintPattern.actuation(for: Double(p.y)) {
                        lastTick = Date()
                        Haptics.tick(id)
                    }
                })
        }
        .frame(height: canvasHeight)
    }

    private func point(_ p: CGPoint, _ size: CGSize) -> CGPoint { CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height) }

    private func drawBackground(_ ctx: GraphicsContext, _ size: CGSize) {
        let silentH = CGFloat(PaintPattern.silentBelow) * size.height
        let levelH = (size.height - silentH) / 6
        let names = ["Max", "", "Strong", "", "Light", ""]
        for i in 0..<6 {
            let y = CGFloat(i) * levelH
            if i % 2 == 0 {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: levelH)), with: .color(.primary.opacity(0.035)))
            }
            if !names[i].isEmpty {
                ctx.draw(Text(names[i]).font(.system(size: 9, weight: .medium)).foregroundColor(.secondary),
                         at: CGPoint(x: 22, y: y + 9))
            }
        }
        // Silent strip
        ctx.fill(Path(CGRect(x: 0, y: size.height - silentH, width: size.width, height: silentH)), with: .color(.primary.opacity(0.07)))
        ctx.draw(Text("Off").font(.system(size: 9, weight: .medium)).foregroundColor(.secondary),
                 at: CGPoint(x: 16, y: size.height - silentH / 2))

        // Time grid
        let step = length > 5 ? 1.0 : 0.5
        var t = 0.0
        while t <= length + 0.0001 {
            let x = CGFloat(t / length) * size.width
            var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(line, with: .color(.primary.opacity(0.07)), lineWidth: 1)
            if x < size.width - 26 {
                ctx.draw(Text(String(format: "%.1f s", t)).font(.system(size: 9)).foregroundColor(.secondary),
                         at: CGPoint(x: x + 16, y: size.height - silentH - 8))
            }
            t += step
        }
    }

    /// Faint bars showing the taps the painting will actually play.
    private func drawStems(_ ctx: GraphicsContext, _ size: CGSize) {
        let ladder = TrackpadActuator.ladder
        let silentH = CGFloat(PaintPattern.silentBelow) * size.height
        let levelH = (size.height - silentH) / CGFloat(ladder.count)
        var path = Path()
        for e in PaintPattern.events(strokes: strokes, length: length, interval: interval) {
            guard let a = e.actuation, let rank = ladder.firstIndex(of: a) else { continue }
            let x = CGFloat(e.time / length) * size.width
            let top = size.height - silentH - CGFloat(rank + 1) * levelH
            path.move(to: CGPoint(x: x, y: size.height - silentH))
            path.addLine(to: CGPoint(x: x, y: top))
        }
        ctx.stroke(path, with: .color(.accentColor.opacity(0.4)), lineWidth: 2)
    }

    // MARK: Save

    private func save() {
        let ladder = TrackpadActuator.ladder
        let taps = PaintPattern.events(strokes: strokes, length: length, interval: interval).compactMap { e -> UserTap? in
            guard let a = e.actuation, let i = ladder.firstIndex(of: a) else { return nil }
            return UserTap(time: e.time, level: i + 1)
        }
        library.save(UserPattern(name: name.trimmingCharacters(in: .whitespaces), length: length, taps: taps))
        message = "Saved “\(name)” (\(taps.count) taps)."
    }
}
