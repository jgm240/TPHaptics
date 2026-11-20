import SwiftUI

// MARK: - Design system (shared look for every screen)

/// Rounded surface that groups related controls.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

/// Standard scrolling screen: grouped background, padded stack of cards.
struct ScreenScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }
}

struct CardTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
            if let subtitle { Hint(subtitle) }
        }
    }
}

struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 30
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.68)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
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
            .background(Capsule().fill(tint.opacity(0.15)))
    }
}

struct RoundPlayButton: View {
    let playing: Bool
    var size: CGFloat = 44
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "stop.fill" : "play.fill")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: playing ? 0 : 1)
                .frame(width: size, height: size)
                .background(Circle().fill(playing ? Color.red.opacity(0.9) : Color.accentColor))
        }
        .buttonStyle(.plain)
    }
}

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
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint))
        }
        .buttonStyle(.plain)
    }
}

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

/// Tiny preview of a pattern: ticks as lines, buzzes as filled shapes.
struct MiniWave: View {
    let pattern: HapticPattern
    var tint: Color = .accentColor

    var body: some View {
        Canvas { ctx, size in
            guard pattern.length > 0 else { return }
            let sx = size.width / pattern.length
            var ticks = Path()
            var fills = Path()
            for t in pattern.taps {
                let x = t.time * sx
                let h = CGFloat(t.intensity) * size.height
                if t.duration > 0 {
                    if t.curve.count >= 2 {
                        fills.move(to: CGPoint(x: (t.time + t.curve[0].time) * sx, y: size.height))
                        for c in t.curve {
                            fills.addLine(to: CGPoint(x: (t.time + c.time) * sx, y: size.height - CGFloat(c.value * t.intensity) * size.height))
                        }
                        fills.addLine(to: CGPoint(x: (t.time + (t.curve.last?.time ?? 0)) * sx, y: size.height))
                        fills.closeSubpath()
                    } else {
                        fills.addRoundedRect(in: CGRect(x: x, y: size.height - h, width: max(2, t.duration * sx), height: h),
                                             cornerSize: CGSize(width: 2, height: 2))
                    }
                } else {
                    ticks.move(to: CGPoint(x: x, y: size.height))
                    ticks.addLine(to: CGPoint(x: x, y: size.height - max(3, h)))
                }
            }
            ctx.fill(fills, with: .color(tint.opacity(0.5)))
            ctx.stroke(ticks, with: .color(tint.opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            var base = Path()
            base.move(to: CGPoint(x: 0, y: size.height)); base.addLine(to: CGPoint(x: size.width, y: size.height))
            ctx.stroke(base, with: .color(.primary.opacity(0.12)), lineWidth: 1)
        }
        .frame(height: 28)
    }
}
