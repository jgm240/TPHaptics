import SwiftUI

/// Turns painted lines into haptics. x is time (0…1 across the pattern), y is strength (0…1, 1 = top).
enum PaintBuilder {
    /// Heights below this are "off".
    static let silentBelow = 0.06

    /// Strongest painted height in each time bin, or nil where no line passes.
    static func levels(strokes: [[CGPoint]], bins n: Int) -> [Double?] {
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
                if a.x > b.x { swap(&a, &b) }                        // lines may be drawn right to left
                let b0 = max(0, Int(floor(a.x * CGFloat(n))))
                let b1 = max(b0, Int(floor(b.x * CGFloat(n))))
                for bin in b0...b1 {
                    let center = (CGFloat(bin) + 0.5) / CGFloat(n)
                    let t: CGFloat = b.x > a.x ? min(1, max(0, (center - a.x) / (b.x - a.x))) : 0
                    mark(bin, Double(a.y + (b.y - a.y) * t))
                }
            }
        }
        return level
    }

    /// `smooth`: one continuous vibration whose intensity follows the line (the iPhone's native feel).
    /// Otherwise: a tap every `spacing` seconds at the line's height.
    static func pattern(strokes: [[CGPoint]], length: Double, smooth: Bool,
                        spacing: Double, sharpness: Float, name: String = "Paint") -> HapticPattern {
        if smooth {
            let dt = 0.02
            let n = max(2, Int(length / dt))
            let lv = levels(strokes: strokes, bins: n)
            let points = lv.enumerated().map { i, v -> CurvePoint in
                let height = v ?? 0
                return CurvePoint(time: (Double(i) + 0.5) * dt, value: height >= silentBelow ? Float(height) : 0)
            }
            guard points.contains(where: { $0.value > 0 }) else { return HapticPattern(name: name, taps: [], length: length) }
            let tap = Tap(time: 0, intensity: 1, sharpness: sharpness, duration: length, curve: points)
            return HapticPattern(name: name, detail: "Painted pattern", taps: [tap], length: length)
        }
        let n = max(1, Int((length / spacing).rounded(.down)))
        let lv = levels(strokes: strokes, bins: n)
        let taps = lv.enumerated().compactMap { i, v -> Tap? in
            guard let v, v >= silentBelow else { return nil }
            return Tap(time: Double(i) * spacing, intensity: Float(v), sharpness: sharpness)
        }
        return HapticPattern(name: name, detail: "Painted pattern", taps: taps, length: length)
    }

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
    @ObservedObject private var haptics = Haptics.shared
    @ObservedObject private var library = PatternLibrary.shared

    @State private var strokes: [[CGPoint]] = []
    @State private var length = 4.0
    @State private var smooth = true
    @State private var spacing = 0.03
    @State private var sharpness = 0.5
    @State private var name = "My Painting"
    @State private var startedAt = Date()
    @State private var message: String?
    @State private var painting = false

    private var pattern: HapticPattern {
        PaintBuilder.pattern(strokes: strokes, length: length, smooth: smooth, spacing: spacing, sharpness: Float(sharpness))
    }

    var body: some View {
        let playing = haptics.playingName == "Paint"
        let hasContent = !pattern.taps.isEmpty
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Time →   Strength ↑").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach(PaintBuilder.examples, id: \.name) { ex in Button(ex.name) { strokes = ex.strokes } }
                    } label: { Label("Start from…", systemImage: "wand.and.stars").font(.footnote) }
                }
                canvas
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .frame(maxHeight: .infinity)

            controls(playing: playing, hasContent: hasContent)
        }
        .padding(16)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onChange(of: strokes) { _ in refresh(playing) }
        .onChange(of: length) { _ in refresh(playing) }
        .onChange(of: smooth) { _ in refresh(playing) }
        .onChange(of: spacing) { _ in refresh(playing) }
        .onChange(of: sharpness) { _ in refresh(playing) }
    }

    /// Restart a running loop so edits are felt straight away.
    private func refresh(_ playing: Bool) {
        guard playing else { return }
        if pattern.taps.isEmpty { haptics.stop() } else { startedAt = Date(); haptics.play(pattern, loop: true) }
    }

    private func controls(playing: Bool, hasContent: Bool) -> some View {
        VStack(spacing: 10) {
            Picker("", selection: $smooth) {
                Text("Smooth").tag(true)
                Text("Taps").tag(false)
            }
            .pickerStyle(.segmented)

            labeled("Length", String(format: "%.1f s", length)) { Slider(value: $length, in: 1...10, step: 0.5) }
            labeled("Feel", sharpness < 0.34 ? "soft" : (sharpness > 0.66 ? "crisp" : "medium")) { Slider(value: $sharpness, in: 0...1) }
            if !smooth {
                labeled("Spacing", "\(Int(spacing * 1000)) ms") { Slider(value: $spacing, in: 0.01...0.1, step: 0.005) }
            }

            HStack(spacing: 10) {
                Button { if !strokes.isEmpty { strokes.removeLast() } } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(strokes.isEmpty)
                Button { strokes = [] } label: { Image(systemName: "trash") }
                    .disabled(strokes.isEmpty)
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                Button {
                    library.save(HapticPattern(name: name.trimmingCharacters(in: .whitespaces), detail: "Painted pattern",
                                               taps: pattern.taps, length: length))
                    message = "Saved to Patterns"
                } label: { Image(systemName: "tray.and.arrow.down") }
                .disabled(!hasContent || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let m = message { Text(m).font(.caption).foregroundStyle(.secondary) }

            BigButton(title: playing ? "Stop" : "Play", symbol: playing ? "stop.fill" : "play.fill",
                      tint: playing ? .red : .accentColor) {
                if playing { haptics.stop() } else { startedAt = Date(); haptics.play(pattern, loop: true) }
            }
            .opacity(hasContent ? 1 : 0.4)
            .disabled(!hasContent)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func labeled<V: View>(_ title: String, _ value: String, @ViewBuilder _ control: () -> V) -> some View {
        HStack {
            Text(title).font(.subheadline).frame(width: 64, alignment: .leading)
            control()
            Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    background(ctx, size)
                    for stroke in strokes where !stroke.isEmpty {
                        var path = Path()
                        path.move(to: pt(stroke[0], size))
                        if stroke.count == 1 { path.addLine(to: pt(stroke[0], size)) }
                        for p in stroke.dropFirst() { path.addLine(to: pt(p, size)) }
                        ctx.stroke(path, with: .color(.orange), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    }
                }
                TimelineView(.animation) { tl in
                    if haptics.playingName == "Paint" {
                        let t = tl.date.timeIntervalSince(startedAt).truncatingRemainder(dividingBy: length)
                        Rectangle().fill(Color.primary.opacity(0.75)).frame(width: 2, height: h)
                            .offset(x: CGFloat(t / length) * w - 1)
                    }
                }
                .allowsHitTesting(false)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let p = CGPoint(x: min(1, max(0, v.location.x / w)), y: min(1, max(0, 1 - v.location.y / h)))
                    let strength = p.y >= PaintBuilder.silentBelow ? Float(p.y) : 0
                    if !painting {
                        painting = true
                        strokes.append([p])
                        haptics.hum.begin(intensity: strength, sharpness: Float(sharpness))   // feel what you paint
                    } else if let last = strokes.last?.last, hypot(last.x - p.x, last.y - p.y) > 0.002 {
                        strokes[strokes.count - 1].append(p)
                    }
                    haptics.hum.update(intensity: strength, sharpness: Float(sharpness))
                }
                .onEnded { _ in
                    painting = false
                    haptics.hum.end()
                })
        }
        .frame(minHeight: 220)
    }

    private func pt(_ p: CGPoint, _ size: CGSize) -> CGPoint { CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height) }

    private func background(_ ctx: GraphicsContext, _ size: CGSize) {
        let silentH = CGFloat(PaintBuilder.silentBelow) * size.height
        let bandH = (size.height - silentH) / 4
        for i in 0..<4 where i % 2 == 0 {
            ctx.fill(Path(CGRect(x: 0, y: CGFloat(i) * bandH, width: size.width, height: bandH)), with: .color(.primary.opacity(0.035)))
        }
        ctx.fill(Path(CGRect(x: 0, y: size.height - silentH, width: size.width, height: silentH)), with: .color(.primary.opacity(0.07)))
        ctx.draw(Text("Max").font(.system(size: 9, weight: .medium)).foregroundColor(.secondary), at: CGPoint(x: 18, y: 10))
        ctx.draw(Text("Off").font(.system(size: 9, weight: .medium)).foregroundColor(.secondary), at: CGPoint(x: 14, y: size.height - silentH / 2))
        let step = length > 5 ? 1.0 : 0.5
        var t = 0.0
        while t <= length + 0.0001 {
            let x = CGFloat(t / length) * size.width
            var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(line, with: .color(.primary.opacity(0.07)), lineWidth: 1)
            if x < size.width - 28 {
                ctx.draw(Text(String(format: "%.1f s", t)).font(.system(size: 9)).foregroundColor(.secondary),
                         at: CGPoint(x: x + 16, y: size.height - silentH - 8))
            }
            t += step
        }
    }
}
