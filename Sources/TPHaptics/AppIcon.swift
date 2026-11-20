import SwiftUI
import AppKit

/// The app icon: a trackpad with haptic ripples spreading out from a tap.
/// Drawn in code so it can be regenerated at any size (see make-icon.sh).
struct AppIconView: View {
    private let body1 = Color(red: 0.36, green: 0.27, blue: 0.96)
    private let body2 = Color(red: 0.05, green: 0.68, blue: 0.82)

    var body: some View {
        ZStack {
            // Icon body, using the standard macOS inset (824 pt on a 1024 pt canvas)
            RoundedRectangle(cornerRadius: 188, style: .continuous)
                .fill(LinearGradient(colors: [body1, body2], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.32), radius: 22, y: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 188, style: .continuous)
                        .stroke(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.0)],
                                               startPoint: .top, endPoint: .center), lineWidth: 5)
                        .frame(width: 824, height: 824)
                )

            // Trackpad
            ZStack {
                RoundedRectangle(cornerRadius: 78, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.10)],
                                         startPoint: .top, endPoint: .bottom))

                // Haptic ripples
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .stroke(Color.white.opacity(0.80 - Double(i) * 0.17), lineWidth: 14 - CGFloat(i) * 2.5)
                        .frame(width: 120 + CGFloat(i) * 150, height: 120 + CGFloat(i) * 150)
                }

                // The tap
                Circle()
                    .fill(Color.white)
                    .frame(width: 70, height: 70)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)

                RoundedRectangle(cornerRadius: 78, style: .continuous)
                    .stroke(Color.white.opacity(0.65), lineWidth: 7)
            }
            .frame(width: 600, height: 430)
            .clipShape(RoundedRectangle(cornerRadius: 78, style: .continuous))
            .offset(y: 8)
        }
        .frame(width: 1024, height: 1024)
    }
}

enum AppIconRenderer {
    private static let sizes: [(name: String, px: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]

    /// Writes the PNGs of an `.iconset` folder; `iconutil` turns it into an `.icns`.
    @MainActor
    static func writeIconset(to dir: String) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let renderer = ImageRenderer(content: AppIconView())
        renderer.scale = 1
        guard let master = renderer.cgImage else { print("icon render failed"); return }

        for (name, px) in sizes {
            guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.interpolationQuality = .high
            ctx.draw(master, in: CGRect(x: 0, y: 0, width: px, height: px))
            guard let scaled = ctx.makeImage(),
                  let png = NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }
        print("wrote iconset to \(dir)")
    }
}
