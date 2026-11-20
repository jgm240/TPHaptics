// Renders the 1200×630 social preview image used by the website (docs/og.png).
// swiftc IPHaptics/Tools/make-social-card.swift -o /tmp/card && /tmp/card docs/og.png IPHaptics/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import SwiftUI
import AppKit

struct Card: View {
    let icon: NSImage
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.42, green: 0.20, blue: 0.96),
                                    Color(red: 0.93, green: 0.28, blue: 0.58),
                                    Color(red: 1.00, green: 0.60, blue: 0.24)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .stroke(Color.white.opacity(0.30 - Double(i) * 0.04), lineWidth: 5)
                    .frame(width: 300 + CGFloat(i) * 150, height: 300 + CGFloat(i) * 150)
                    .position(x: 930, y: 315)
            }
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("IPHaptics").font(.system(size: 104, weight: .heavy, design: .rounded)).foregroundColor(.white)
                    Text("Feel your phone.").font(.system(size: 52, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.95))
                    Text("Haptic patterns for iPhone · free and open source")
                        .font(.system(size: 28, weight: .medium)).foregroundColor(.white.opacity(0.85)).padding(.top, 10)
                }
                .padding(.leading, 80)
                Spacer()
            }
            Image(nsImage: icon)
                .resizable().frame(width: 300, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 68, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 24, y: 14)
                .position(x: 930, y: 315)
        }
        .frame(width: 1200, height: 630)
    }
}

@MainActor func render(out: String, iconPath: String) {
    _ = NSApplication.shared
    guard let icon = NSImage(contentsOfFile: iconPath) else { print("no icon at \(iconPath)"); exit(1) }
    let r = ImageRenderer(content: Card(icon: icon))
    r.scale = 1
    guard let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
        print("render failed"); exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}

let args = CommandLine.arguments
MainActor.assumeIsolated {
    render(out: args.count > 1 ? args[1] : "og.png",
           iconPath: args.count > 2 ? args[2] : "AppIcon.png")
}
