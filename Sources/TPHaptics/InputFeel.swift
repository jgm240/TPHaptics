import SwiftUI
import ApplicationServices

/// Taps in response to what you do: keystrokes, scrolling, and the pointer crossing
/// grid lines, window edges and screen edges. Uses event monitors (observe only).
final class InputFeel: ObservableObject {
    static let shared = InputFeel()

    @Published private(set) var accessibilityOK = AXIsProcessTrusted()

    private let d = UserDefaults.standard
    private var monitors: [Any] = []
    private var signature = ""
    private var started = false
    private var windowTimer: Timer?

    private var scrollAccum: CGFloat = 0
    private var lastGrid: (Int, Int)?
    private var windows: [(id: Int, rect: CGRect)] = []
    private var lastWindowID: Int?
    private var atEdge = false

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reconfigure()
        }
        reconfigure()
    }

    /// Adds or removes monitors to match the switches. Cheap when nothing changed.
    private func reconfigure() {
        accessibilityOK = AXIsProcessTrusted()
        let typing = d.bool(forKey: "feel.typing")
        let scroll = d.bool(forKey: "feel.scroll")
        let grid = d.bool(forKey: "feel.grid")
        let wins = d.bool(forKey: "feel.windows")
        let edges = d.bool(forKey: "feel.edges")
        let mouse = grid || wins || edges
        let sig = [typing, scroll, mouse, wins].map { $0 ? "1" : "0" }.joined()
        guard sig != signature else { return }
        signature = sig

        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        windowTimer?.invalidate(); windowTimer = nil

        if typing { observe(.keyDown) { [weak self] e in self?.key(e) } }
        if scroll { observe(.scrollWheel) { [weak self] e in self?.scrolled(e) } }
        if mouse {
            observe([.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in self?.moved() }
        }
        if wins {
            refreshWindows()
            windowTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshWindows() }
        }
        Diag.log("feel monitors: typing=\(typing) scroll=\(scroll) mouse=\(mouse) windows=\(wins) trusted=\(accessibilityOK)")
    }

    private func observe(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) {
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { handler($0); return $0 }) { monitors.append(l) }
    }

    // MARK: Typing and scrolling

    private func key(_ e: NSEvent) {
        switch e.keyCode {
        case 49: Haptics.tick(4)            // space
        case 36, 76: Haptics.tick(5)        // return / enter
        case 48, 51: Haptics.tick(3)        // tab / delete
        default: Haptics.tick(2)
        }
    }

    private func scrolled(_ e: NSEvent) {
        let delta = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * 10
        let step = CGFloat(max(10, d.object(forKey: "feel.scrollPx") as? Double ?? 60))
        scrollAccum += abs(delta)
        if scrollAccum >= step {
            scrollAccum = scrollAccum.truncatingRemainder(dividingBy: step)
            Haptics.tick(1)
        }
    }

    // MARK: Pointer

    private func moved() {
        let p = NSEvent.mouseLocation          // global, origin bottom-left
        let screens = NSScreen.screens

        if d.bool(forKey: "feel.grid") {
            let px = max(20, d.object(forKey: "feel.gridPx") as? Double ?? 100)
            let cell = (Int(floor(p.x / px)), Int(floor(p.y / px)))
            if let last = lastGrid, last != cell { Haptics.tick(1) }
            lastGrid = cell
        }

        if d.bool(forKey: "feel.windows"), let top = screens.first {
            let cg = CGPoint(x: p.x, y: top.frame.height - p.y)   // CG windows use a top-left origin
            let id = windows.first { $0.rect.contains(cg) }?.id ?? -1    // -1 = desktop
            if let last = lastWindowID, last != id { Haptics.tick(3) }
            lastWindowID = id
        }

        if d.bool(forKey: "feel.edges") {
            let union = screens.reduce(CGRect.null) { $0.union($1.frame) }
            let hit = p.x <= union.minX + 1 || p.x >= union.maxX - 2 || p.y <= union.minY + 1 || p.y >= union.maxY - 2
            if hit && !atEdge { Haptics.tick(5) }
            atEdge = hit
        }
    }

    private func refreshWindows() {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
        windows = info.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let id = w[kCGWindowNumber as String] as? Int,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  rect.width >= 60, rect.height >= 40 else { return nil }
            return (id, rect)
        }
    }
}

// MARK: - Screens

enum FeelKind { case typing, screen }

struct FeelView: View {
    let kind: FeelKind
    @ObservedObject private var feel = InputFeel.shared

    @AppStorage("feel.typing") private var typing = false
    @AppStorage("feel.scroll") private var scroll = false
    @AppStorage("feel.scrollPx") private var scrollPx = 60.0
    @AppStorage("feel.grid") private var grid = false
    @AppStorage("feel.gridPx") private var gridPx = 100.0
    @AppStorage("feel.windows") private var windows = false
    @AppStorage("feel.edges") private var edges = false

    var body: some View {
        Screen {
            switch kind {
            case .typing:
                Card {
                    toggleRow(title: "Typewriter", subtitle: "A tap for every key. Space, return and delete get their own strengths.", isOn: $typing)
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        toggleRow(title: "Scroll notches", subtitle: "A light tick every time you scroll a set distance, like a ratchet.", isOn: $scroll)
                        if scroll {
                            HStack {
                                Text("Notch every").frame(width: 90, alignment: .leading)
                                Slider(value: $scrollPx, in: 20...200, step: 5)
                                Text("\(Int(scrollPx)) pt").monospacedDigit().frame(width: 60, alignment: .trailing)
                            }
                        }
                    }
                }
                if typing && !feel.accessibilityOK {
                    permissionNote
                }
            case .screen:
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        toggleRow(title: "Grid lines", subtitle: "A tick each time the pointer crosses an invisible grid, so you can feel distance.", isOn: $grid)
                        if grid {
                            HStack {
                                Text("Spacing").frame(width: 90, alignment: .leading)
                                Slider(value: $gridPx, in: 30...400, step: 10)
                                Text("\(Int(gridPx)) pt").monospacedDigit().frame(width: 60, alignment: .trailing)
                            }
                        }
                    }
                }
                Card { toggleRow(title: "Window edges", subtitle: "A tap when the pointer moves from one window to another or onto the desktop.", isOn: $windows) }
                Card { toggleRow(title: "Screen edges", subtitle: "A firm tap when the pointer hits the edge of the display.", isOn: $edges) }
            }
            Hint("These taps respect the Strength slider. They are observe-only: TPHaptics never reads what you type, it only notices that a key was pressed.")
        }
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            CardTitle(title: title, subtitle: subtitle)
            Spacer()
            Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden()
        }
    }

    private var permissionNote: some View {
        Card {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Hint("Typing in other apps needs Accessibility access. Grant it on the Notifications screen; keys typed in this window work without it.")
            }
        }
    }
}
