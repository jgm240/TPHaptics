import SwiftUI

// MARK: - Design system
// One small set of building blocks so every screen looks like it belongs to the same app.

extension Color {
    static let cardFill = Color(nsColor: .controlBackgroundColor)
    static let cardStroke = Color.primary.opacity(0.07)
}

/// Rounded surface that groups related controls.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.cardStroke))
    }
}

/// Bold card heading with an optional one-line explanation.
struct CardTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let subtitle { Hint(subtitle) }
        }
    }
}

/// Secondary explanatory text.
struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Coloured rounded-square icon, like System Settings.
struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.68)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white))
    }
}

struct Pill: View {
    let text: String
    var tint: Color = .accentColor
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

/// Circular play / stop button.
struct RoundPlayButton: View {
    let playing: Bool
    var size: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "stop.fill" : "play.fill")
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: playing ? 0 : 1)
                .frame(width: size, height: size)
                .background(Circle().fill(playing ? Color.red.opacity(0.85) : Color.accentColor))
        }
        .buttonStyle(.plain)
    }
}

/// Wide accent button for the main action of a screen.
struct BigButton: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 22).padding(.vertical, 10)
                .background(Capsule().fill(tint))
        }
        .buttonStyle(.plain)
    }
}

/// Tiny bar chart of a pattern's taps over time.
struct MiniWave: View {
    let events: [HapticEvent]
    let length: Double
    var tint: Color = .accentColor

    var body: some View {
        Canvas { ctx, size in
            guard length > 0, !events.isEmpty else { return }
            let stride = max(1, events.count / 400)
            var x: CGFloat = 0
            var path = Path()
            for (i, e) in events.enumerated() where i % stride == 0 {
                guard let a = e.actuation else { continue }
                x = CGFloat(e.time / length) * size.width
                let h = max(3, CGFloat(min(6, max(1, a))) / 6 * size.height)
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x, y: size.height - h))
            }
            ctx.stroke(path, with: .color(tint.opacity(0.85)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            var base = Path()
            base.move(to: CGPoint(x: 0, y: size.height))
            base.addLine(to: CGPoint(x: size.width, y: size.height))
            ctx.stroke(base, with: .color(.primary.opacity(0.12)), lineWidth: 1)
        }
        .frame(height: 26)
    }
}

/// Large numeric readout used on slider cards.
struct BigValue: View {
    let value: String
    var unit: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(unit).font(.title3).foregroundStyle(.secondary)
        }
    }
}

/// Standard wrapper for a screen's cards.
struct Screen<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
