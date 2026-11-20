// Renders the 1200×630 social preview for the website's root page (docs/og.png): both apps together.
// swiftc Tools/make-og-card.swift -o /tmp/og && /tmp/og docs/og.png docs/icon-mac.png docs/icon.png
import SwiftUI
import AppKit

struct Card: View {
    let mac: NSImage
    let phone: NSImage

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.27, blue: 0.96), Color(red: 0.18, green: 0.48, blue: 0.91),
                                    Color(red: 0.93, green: 0.28, blue: 0.58), Color(red: 1.0, green: 0.60, blue: 0.24)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ForEach(0..<5, id: \.self) { i in
                Circle().stroke(Color.white.opacity(0.26 - Double(i) * 0.04), lineWidth: 5)
                    .frame(width: 280 + CGFloat(i) * 150, height: 280 + CGFloat(i) * 150).position(x: 940, y: 315)
            }
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Haptics, on your")
                        .font(.system(size: 64, weight: .heavy, design: .rounded)).foregroundColor(.white)
                    Text("Mac and iPhone.")
                        .font(.system(size: 64, weight: .heavy, design: .rounded)).foregroundColor(.white)
                    Text("TPHaptics plays your trackpad with no finger on it. IPHaptics plays your iPhone. Free and open source.")
                        .font(.system(size: 27, weight: .medium)).foregroundColor(.white.opacity(0.92))
                        .frame(width: 560, alignment: .leading).padding(.top, 14)
                }
                .padding(.leading, 70)
                Spacer()
            }
            HStack(spacing: 34) {
                VStack(spacing: 14) {
                    Image(nsImage: mac).resizable().frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 18, y: 10)
                    Text("TPHaptics").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(.white)
                }
                VStack(spacing: 14) {
                    Image(nsImage: phone).resizable().frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 18, y: 10)
                    Text("IPHaptics").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(.white)
                }
            }
            .position(x: 940, y: 315)
        }
        .frame(width: 1200, height: 630)
    }
}

@MainActor func render(out: String, mac: String, phone: String) {
    _ = NSApplication.shared
    guard let m = NSImage(contentsOfFile: mac), let p = NSImage(contentsOfFile: phone) else { print("missing icon"); exit(1) }
    let r = ImageRenderer(content: Card(mac: m, phone: p))
    r.scale = 1
    guard let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
        print("render failed"); exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}

let a = CommandLine.arguments
MainActor.assumeIsolated {
    render(out: a.count > 1 ? a[1] : "og.png", mac: a.count > 2 ? a[2] : "icon-mac.png", phone: a.count > 3 ? a[3] : "icon.png")
}
