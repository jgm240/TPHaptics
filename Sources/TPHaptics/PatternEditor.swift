import SwiftUI
import UniformTypeIdentifiers

/// Draw taps on a timeline: click to add, drag to move, height sets strength.
struct PatternEditorView: View {
    @Binding var loop: Bool
    @ObservedObject private var player = AppModel.shared.player
    @ObservedObject private var library = PatternLibrary.shared

    @State private var draft = UserPattern(name: "My Pattern", length: 1.5, taps: [])
    @State private var selected: UUID?
    @State private var dragging: UUID?
    @State private var snap = 0.025
    @State private var message: String?

    private let canvasHeight: CGFloat = 220
    private let levels = 6

    private var playable: HapticPattern {
        var p = draft.pattern
        p.name = "Editor"
        return p
    }

    var body: some View {
        let playing = player.playingName == "Editor"
        Screen {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("Name", text: $draft.name)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                        Spacer()
                        Menu {
                            if library.patterns.isEmpty { Text("No saved patterns") }
                            ForEach(library.patterns) { p in
                                Button(p.name) { draft = p; selected = nil }
                            }
                        } label: { Label("Open", systemImage: "folder") }
                        .fixedSize()
                        Button { importPattern() } label: { Label("Import", systemImage: "square.and.arrow.down") }
                        Button { exportPattern() } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    }

                    canvas

                    HStack(spacing: 16) {
                        HStack {
                            Text("Length")
                            Slider(value: $draft.length, in: 0.2...10)
                                .frame(width: 160)
                            Text(String(format: "%.1f s", draft.length)).monospacedDigit().frame(width: 50, alignment: .trailing)
                        }
                        Picker("Snap", selection: $snap) {
                            Text("5 ms").tag(0.005)
                            Text("10 ms").tag(0.010)
                            Text("25 ms").tag(0.025)
                            Text("50 ms").tag(0.050)
                            Text("100 ms").tag(0.100)
                        }
                        .frame(width: 140)
                        Spacer()
                        Text("\(draft.taps.count) taps").foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }

            HStack {
                Button(role: .destructive) {
                    if let s = selected { draft.taps.removeAll { $0.id == s }; selected = nil }
                } label: { Label("Delete tap", systemImage: "trash") }
                .disabled(selected == nil)
                Button("Clear") { draft.taps = []; selected = nil }
                    .disabled(draft.taps.isEmpty)
                Spacer()
                if let m = message { Text(m).font(.callout).foregroundStyle(.secondary) }
                Button {
                    library.save(draft)
                    message = "Saved “\(draft.name)”. It now appears in Patterns and every pattern picker."
                } label: { Label("Save", systemImage: "tray.and.arrow.down") }
                .disabled(draft.taps.isEmpty || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                BigButton(title: playing ? "Stop" : "Play", symbol: playing ? "stop.fill" : "play.fill",
                          tint: playing ? .red : .accentColor) {
                    playing ? player.stop() : player.play(playable, loop: loop)
                }
                .disabled(draft.taps.isEmpty)
            }

            Hint("Click empty space to add a tap, drag a tap to move it, and click one to select it. Higher means stronger. Taps closer than about 5 ms can't be played separately.")
        }
        .onChange(of: draft) { _ in
            if player.playingName == "Editor" { player.update(playable) }
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Canvas { ctx, size in
                    // Strength bands
                    let bandH = size.height / CGFloat(levels)
                    for i in 0..<levels where i % 2 == 0 {
                        ctx.fill(Path(CGRect(x: 0, y: CGFloat(i) * bandH, width: size.width, height: bandH)),
                                 with: .color(.primary.opacity(0.03)))
                    }
                    // Time grid
                    let step = draft.length > 4 ? 1.0 : (draft.length > 1.5 ? 0.5 : 0.1)
                    var t = 0.0
                    while t <= draft.length + 0.0001 {
                        let x = CGFloat(t / draft.length) * size.width
                        var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
                        ctx.stroke(line, with: .color(.primary.opacity(0.08)), lineWidth: 1)
                        if x < size.width - 28 {
                            ctx.draw(Text(String(format: "%.1f", t)).font(.system(size: 9)).foregroundColor(.secondary),
                                     at: CGPoint(x: x + 12, y: size.height - 8))
                        }
                        t += step
                    }
                    // Taps
                    for tap in draft.taps {
                        let x = CGFloat(tap.time / draft.length) * size.width
                        let h = CGFloat(tap.level) / CGFloat(levels) * size.height
                        let isSel = tap.id == selected
                        var stem = Path(); stem.move(to: CGPoint(x: x, y: size.height)); stem.addLine(to: CGPoint(x: x, y: size.height - h))
                        ctx.stroke(stem, with: .color(isSel ? .orange : .accentColor), style: StrokeStyle(lineWidth: isSel ? 3 : 2, lineCap: .round))
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 5, y: size.height - h - 5, width: 10, height: 10)),
                                 with: .color(isSel ? .orange : .accentColor))
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.cardStroke))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if dragging == nil {
                        if let hit = draft.taps.first(where: { abs(CGFloat($0.time / draft.length) * w - v.startLocation.x) <= 9 }) {
                            selected = hit.id
                            dragging = hit.id
                        } else {
                            let tap = UserTap(time: time(at: v.location.x, width: w), level: level(at: v.location.y))
                            draft.taps.append(tap)
                            selected = tap.id
                            dragging = tap.id
                            Haptics.tick(TrackpadActuator.ladder[tap.level - 1])
                        }
                    }
                    guard let id = dragging, let i = draft.taps.firstIndex(where: { $0.id == id }) else { return }
                    let newLevel = level(at: v.location.y)
                    if newLevel != draft.taps[i].level { Haptics.tick(TrackpadActuator.ladder[newLevel - 1]) }
                    draft.taps[i].time = time(at: v.location.x, width: w)
                    draft.taps[i].level = newLevel
                }
                .onEnded { _ in dragging = nil })
        }
        .frame(height: canvasHeight)
    }

    private func time(at x: CGFloat, width: CGFloat) -> Double {
        let raw = Double(min(max(0, x), width) / width) * draft.length
        return min(draft.length, max(0, (raw / snap).rounded() * snap))
    }

    private func level(at y: CGFloat) -> Int {
        let band = canvasHeight / CGFloat(levels)
        return min(levels, max(1, levels - Int(max(0, y) / band)))
    }

    // MARK: Files

    private func exportPattern() {
        guard let data = library.exportData(draft) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(draft.name).tphaptic"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do { try data.write(to: url); message = "Exported to \(url.lastPathComponent)." }
            catch { message = "Couldn't export: \(error.localizedDescription)" }
        }
    }

    private func importPattern() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let p = library.importData(data) else {
            message = "That file isn't a TPHaptics pattern."
            return
        }
        draft = p
        selected = nil
        message = "Imported “\(p.name)”. Press Save to keep it."
    }
}
