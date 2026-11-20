// Renders the IPHaptics app icon (1024×1024, opaque, full-bleed: iOS rounds the corners itself).
// Run on a Mac:  swiftc IPHaptics/Tools/make-icon.swift -o /tmp/make-icon && /tmp/make-icon IPHaptics/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import SwiftUI
import AppKit

struct IconView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.42, green: 0.20, blue: 0.96),
                                    Color(red: 0.93, green: 0.28, blue: 0.58),
                                    Color(red: 1.00, green: 0.60, blue: 0.24)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            // Haptic ripples
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .stroke(Color.white.opacity(0.55 - Double(i) * 0.09), lineWidth: 15 - CGFloat(i) * 1.8)
                    .frame(width: 330 + CGFloat(i) * 170, height: 330 + CGFloat(i) * 170)
            }

            // Phone
            ZStack {
                RoundedRectangle(cornerRadius: 92, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.34), Color.white.opacity(0.12)],
                                         startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 92, style: .continuous)
                    .stroke(Color.white.opacity(0.85), lineWidth: 12)
                Capsule().fill(Color.black.opacity(0.45)).frame(width: 120, height: 34).offset(y: -250)
                Circle().fill(Color.white).frame(width: 74, height: 74).shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            }
            .frame(width: 350, height: 640)
            .shadow(color: .black.opacity(0.25), radius: 26, y: 16)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func render(to path: String) {
    _ = NSApplication.shared
    let renderer = ImageRenderer(content: IconView())
    renderer.scale = 1
    guard let image = renderer.cgImage,
          let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        print("render failed"); exit(1)
    }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    guard let out = ctx.makeImage(),
          let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) else { print("encode failed"); exit(1) }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

MainActor.assumeIsolated { render(to: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png") }
