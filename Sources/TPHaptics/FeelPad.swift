import SwiftUI

/// Maps a point on the pad to a click train. The actuator has no smooth intensity, so the two axes are
/// the two things it does have: strength (six click levels) and click rate.
///   up    = stronger
///   right = faster (a slow thump on the left, a near-continuous buzz on the right)
enum FeelPadMap {
    static let slowest = 0.25     // seconds between clicks at the left edge (4 per second)
    static let fastest = 0.006    // right edge: about the fastest the actuator can follow

    static func interval(x: Double) -> Double {
        slowest * pow(fastest / slowest, min(1, max(0, x)))
    }

    /// 0…5, an index into `TrackpadActuator.ladder`.
    static func level(y: Double) -> Int {
        min(5, max(0, Int(min(1, max(0, y)) * 6)))
    }

    static func pattern(x: Double, y: Double) -> HapticPattern {
        let id = TrackpadActuator.ladder[level(y: y)]
        return HapticPattern(name: "Feel Pad", detail: "",
                             events: [HapticEvent(time: 0, actuation: id)],
                             length: interval(x: x),
                             normalize: false)      // levels are absolute; the Strength slider still scales them
    }
}

struct FeelPadView: View {
    @ObservedObject private var player = AppModel.shared.player
    @State private var point: CGPoint?          // normalized, y up
    @State private var playOnHover = false
    @State private var lastRestart = Date.distantPast
    @State private var lastInterval = FeelPadMap.slowest

    private let padHeight: CGFloat = 330

    var body: some View {
        Screen {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        CardTitle(title: "Slide to shape a buzz",
                                  subtitle: "Press and drag on the pad. Up is stronger, right is faster. Left is a slow thump; far right is a continuous buzz.")
                        Spacer()
                        Toggle("Play on hover", isOn: $playOnHover).toggleStyle(.switch).controlSize(.small)
                    }
                    pad
                    HStack(spacing: 10) {
                        readout(title: "Strength", value: point.map { "\(FeelPadMap.level(y: $0.y) + 1) of 6" } ?? "—")
                        readout(title: "Speed", value: point.map { String(format: "%.0f taps/s", 1 / FeelPadMap.interval(x: $0.x)) } ?? "—")
                        Spacer()
                    }
                }
            }
            Hint(playOnHover
                 ? "Hover mode: it plays as soon as the pointer is over the pad, with nothing to hold down. Move off the pad to stop."
                 : "Hold the click as you move, and let go to stop. Turn on “Play on hover” to play with no click at all.")
        }
        .onDisappear { end() }
    }

    private var pad: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Color.purple.opacity(0.20), Color.teal.opacity(0.24)],
                                         startPoint: .bottomLeading, endPoint: .topTrailing))
                RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.cardStroke)
                if let p = point {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(Color.pink.opacity(0.55 - Double(i) * 0.15), lineWidth: 3)
                            .frame(width: 44 + CGFloat(i) * 40 * (0.5 + p.y), height: 44 + CGFloat(i) * 40 * (0.5 + p.y))
                            .position(x: p.x * w, y: (1 - p.y) * h)
                    }
                    Circle().fill(Color.pink).frame(width: 26, height: 26).position(x: p.x * w, y: (1 - p.y) * h)
                }
                VStack {
                    Text("stronger ↑").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    HStack { Text("← slow thump"); Spacer(); Text("fast buzz →") }.font(.caption).foregroundStyle(.secondary)
                }
                .padding(10)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { move($0.location, w, h) }
                .onEnded { _ in end() })
            .onContinuousHover { phase in
                guard playOnHover else { return }
                switch phase {
                case .active(let loc): move(loc, w, h)
                case .ended: end()
                }
            }
        }
        .frame(height: padHeight)
    }

    private func readout(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold).monospacedDigit())
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    private func move(_ location: CGPoint, _ w: CGFloat, _ h: CGFloat) {
        let x = min(1, max(0, Double(location.x / w)))
        let y = min(1, max(0, Double(1 - location.y / h)))
        point = CGPoint(x: x, y: y)
        let p = FeelPadMap.pattern(x: x, y: y)
        if player.playingName == "Feel Pad" {
            player.update(p)           // takes effect on the next click…
            // …so when speeding up from a slow rate, restart right away instead of waiting out a long gap.
            if lastInterval > 0.08, p.length < lastInterval * 0.5, Date().timeIntervalSince(lastRestart) > 0.08 {
                player.play(p, loop: true); lastRestart = Date()
            }
        } else {
            player.play(p, loop: true); lastRestart = Date()
        }
        lastInterval = p.length
    }

    private func end() {
        point = nil
        if player.playingName == "Feel Pad" { player.stop() }
    }
}
