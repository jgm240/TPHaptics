import SwiftUI

@main
struct IPHapticsApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { URLRouter.handle($0) }
        }
    }
}

/// `iphaptics://` links, for Shortcuts ("Open URLs") and other apps. The app opens in the
/// foreground, which iOS requires for haptics.
///   iphaptics://play?pattern=Heartbeat&loop=1
///   iphaptics://morse?text=hello&wpm=15
///   iphaptics://stop
@MainActor
enum URLRouter {
    static func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "iphaptics" else { return }
        let action = (url.host ?? "").lowercased()
        var q: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            q[item.name.lowercased()] = item.value ?? ""
        }
        let haptics = Haptics.shared
        let loop = ["1", "true", "yes"].contains((q["loop"] ?? "").lowercased())
        switch action {
        case "play":
            if let name = q["pattern"], let p = PatternLibrary.shared.pattern(named: name) { haptics.play(p, loop: loop) }
        case "morse":
            if let text = q["text"], !text.isEmpty {
                haptics.play(Morse.pattern(text: text, wpm: Double(q["wpm"] ?? "") ?? 15), loop: loop)
            }
        case "strength":
            if let v = Double(q["value"] ?? "") { haptics.strength = min(1, max(0, v)) }
        case "stop":
            haptics.stop()
        default:
            break
        }
    }
}
