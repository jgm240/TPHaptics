import SwiftUI
import ApplicationServices

/// Taps in response to what you do: keystrokes, scrolling, gestures, clicks, and the pointer
/// crossing lines, edges, corners, displays and on-screen controls. Uses event monitors
/// (observe only): it never records or reads what you type.
final class InputFeel: ObservableObject {
    static let shared = InputFeel()

    @Published private(set) var accessibilityOK = AXIsProcessTrusted()
    /// Bumped whenever settings change, so the screens refresh.
    @Published private(set) var revision = 0

    private let d = UserDefaults.standard
    private var monitors: [Any] = []
    private var signature = ""
    private var started = false
    private var windowTimer: Timer?

    // Keyboard / scroll / gesture state
    private var lastFlags: NSEvent.ModifierFlags = []
    private var scrollY: CGFloat = 0
    private var scrollX: CGFloat = 0
    private var lastScrollSign = 0
    private var pinch: CGFloat = 0
    private var rotation: CGFloat = 0

    // Pointer state
    private var lastGrid: (Int, Int)?
    private var windows: [(id: Int, rect: CGRect)] = []
    private var lastWindowID: Int?
    private var atEdge = false
    private var atCorner = false
    private var lastDisplay: Int?
    private var lastCenter: (screen: Int, x: Bool, y: Bool)?
    private var travel: CGFloat = 0
    private var lastElement: AXUIElement?
    private var lastProbe = Date.distantPast
    private let axQueue = DispatchQueue(label: "tphaptics.ax", qos: .userInteractive)
    private let axLock = NSLock()
    private var axBusy = false

    private func on(_ key: String) -> Bool { d.bool(forKey: key) }
    private func number(_ key: String, _ fallback: Double) -> Double { d.object(forKey: key) as? Double ?? fallback }

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reconfigure()
        }
        // Pick up a permission granted (or revoked) while the app is open, not only when a setting changes.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let ok = AXIsProcessTrusted()
            if ok != self.accessibilityOK { self.accessibilityOK = ok; Diag.log("accessibility trusted changed: \(ok)") }
        }
        reconfigure()
    }

    /// Adds or removes monitors to match the switches. Cheap when nothing changed.
    private func reconfigure() {
        accessibilityOK = AXIsProcessTrusted()
        revision += 1

        let typing = on("feel.typing")
        let mods = on("feel.modifiers")
        let scroll = on("feel.scroll") || on("feel.scrollHoriz") || on("feel.scrollReverse")
        let gestures = on("feel.pinch") || on("feel.rotate") || on("feel.swipe")
        let pointerKeys = ["feel.grid", "feel.windows", "feel.edges", "feel.corners", "feel.displays",
                           "feel.center", "feel.speed", "feel.elements"]
        let pointer = pointerKeys.contains(where: on)
        let clicks = on("feel.clicks")
        let wins = on("feel.windows")

        let sig = [typing, mods, scroll, gestures, pointer, clicks, wins].map { $0 ? "1" : "0" }.joined()
        guard sig != signature else { return }
        signature = sig

        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        windowTimer?.invalidate(); windowTimer = nil

        if typing { observe(.keyDown) { [weak self] e in self?.key(e) } }
        if mods { observe(.flagsChanged) { [weak self] e in self?.flags(e) } }
        if scroll { observe(.scrollWheel) { [weak self] e in self?.scrolled(e) } }
        if gestures { observe([.magnify, .rotate, .swipe]) { [weak self] e in self?.gesture(e) } }
        if pointer { observe([.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] e in self?.moved(e) } }
        if clicks { observe([.leftMouseDown, .leftMouseUp, .rightMouseDown]) { [weak self] e in self?.clicked(e) } }
        if wins {
            refreshWindows()
            windowTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshWindows() }
        }
        Diag.log("feel monitors: \(sig) trusted=\(accessibilityOK)")
    }

    private func observe(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) {
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { handler($0); return $0 }) { monitors.append(l) }
    }

    // MARK: Typing

    private func key(_ e: NSEvent) {
        let isReturn = e.keyCode == 36 || e.keyCode == 76
        switch d.string(forKey: "feel.typingStyle") ?? "every" {
        case "words":
            if e.keyCode == 49 || isReturn || e.keyCode == 48 { Haptics.tick(4) }
        case "sentences":
            let ends = (e.charactersIgnoringModifiers ?? "").contains { ".!?".contains($0) }
            if ends || isReturn { Haptics.tick(5) }
        default:
            switch e.keyCode {
            case 49: Haptics.tick(4)            // space
            case 36, 76: Haptics.tick(5)        // return / enter
            case 48, 51: Haptics.tick(3)        // tab / delete
            default: Haptics.tick(2)
            }
        }
    }

    private func flags(_ e: NSEvent) {
        let f = e.modifierFlags.intersection([.shift, .control, .option, .command, .capsLock])
        let added = f.subtracting(lastFlags)
        if f.contains(.capsLock) != lastFlags.contains(.capsLock) { Haptics.tick(5) }       // caps lock on or off
        else if !added.isEmpty { Haptics.tick(2) }                                            // a modifier pressed
        lastFlags = f
    }

    // MARK: Scrolling and gestures

    private func scrolled(_ e: NSEvent) {
        let scale: CGFloat = e.hasPreciseScrollingDeltas ? 1 : 10
        let dy = e.scrollingDeltaY * scale
        let dx = e.scrollingDeltaX * scale
        let step = CGFloat(max(10, number("feel.scrollPx", 60)))

        if on("feel.scrollReverse"), abs(dy) > 1 {
            let sign = dy > 0 ? 1 : -1
            if lastScrollSign != 0 && sign != lastScrollSign { Haptics.tick(4) }
            lastScrollSign = sign
        }
        if on("feel.scroll") {
            scrollY += abs(dy)
            if scrollY >= step { scrollY = scrollY.truncatingRemainder(dividingBy: step); Haptics.tick(1) }
        }
        if on("feel.scrollHoriz") {
            scrollX += abs(dx)
            if scrollX >= step { scrollX = scrollX.truncatingRemainder(dividingBy: step); Haptics.tick(2) }
        }
    }

    private func gesture(_ e: NSEvent) {
        switch e.type {
        case .magnify where on("feel.pinch"):
            if e.phase == .began { pinch = 0 }
            pinch += e.magnification
            if abs(pinch) >= 0.08 { pinch = 0; Haptics.tick(2) }
        case .rotate where on("feel.rotate"):
            if e.phase == .began { rotation = 0 }
            rotation += CGFloat(e.rotation)
            if abs(rotation) >= 15 { rotation = 0; Haptics.tick(3) }
        case .swipe where on("feel.swipe"):
            Haptics.tick(5)
        default:
            break
        }
    }

    private func clicked(_ e: NSEvent) {
        switch e.type {
        case .leftMouseDown: Haptics.tick(5)
        case .leftMouseUp: Haptics.tick(1)
        case .rightMouseDown: Haptics.tick(4)
        default: break
        }
    }

    // MARK: Pointer

    private func moved(_ e: NSEvent) {
        let p = NSEvent.mouseLocation          // global, origin bottom-left
        let screens = NSScreen.screens
        guard let primary = screens.first else { return }
        let cg = CGPoint(x: p.x, y: primary.frame.height - p.y)   // CG windows and AX use a top-left origin
        let current = screens.firstIndex { $0.frame.contains(p) }

        if on("feel.grid") {
            let px = max(20, number("feel.gridPx", 100))
            let cell = (Int(floor(p.x / px)), Int(floor(p.y / px)))
            if let last = lastGrid, last != cell { Haptics.tick(1) }
            lastGrid = cell
        }

        if on("feel.windows") {
            let id = windows.first { $0.rect.contains(cg) }?.id ?? -1    // -1 = desktop
            if let last = lastWindowID, last != id { Haptics.tick(3) }
            lastWindowID = id
        }

        if on("feel.edges") {
            let union = screens.reduce(CGRect.null) { $0.union($1.frame) }
            let hit = p.x <= union.minX + 1 || p.x >= union.maxX - 2 || p.y <= union.minY + 1 || p.y >= union.maxY - 2
            if hit && !atEdge { Haptics.tick(5) }
            atEdge = hit
        }

        if on("feel.corners"), let i = current {
            let f = screens[i].frame
            let zone: CGFloat = 10
            let nearX = p.x <= f.minX + zone || p.x >= f.maxX - zone
            let nearY = p.y <= f.minY + zone || p.y >= f.maxY - zone
            if nearX && nearY && !atCorner { Haptics.tick(6) }
            atCorner = nearX && nearY
        }

        if on("feel.displays"), let i = current {
            if let last = lastDisplay, last != i { Haptics.tick(4) }
            lastDisplay = i
        }

        if on("feel.center"), let i = current {
            let f = screens[i].frame
            let side = (screen: i, x: p.x >= f.midX, y: p.y >= f.midY)
            if let last = lastCenter, last.screen == i, last.x != side.x || last.y != side.y { Haptics.tick(2) }
            lastCenter = side
        }

        if on("feel.speed") {
            let step = CGFloat(max(10, number("feel.speedPx", 40)))
            let dist = hypot(e.deltaX, e.deltaY)
            travel += dist
            if travel >= step {
                travel = travel.truncatingRemainder(dividingBy: step)
                Haptics.tick(dist < 4 ? 1 : (dist < 15 ? 3 : 5))     // faster movement = firmer tap
            }
        }

        if on("feel.elements"), accessibilityOK, Date().timeIntervalSince(lastProbe) > 0.05 {
            lastProbe = Date()
            probeElement(at: cg)
        }
    }

    /// Looks up the control under the pointer off the main thread (a slow app can stall the lookup).
    private func probeElement(at point: CGPoint) {
        axLock.lock()
        if axBusy { axLock.unlock(); return }
        axBusy = true
        axLock.unlock()
        axQueue.async { [weak self] in
            defer { self?.axLock.lock(); self?.axBusy = false; self?.axLock.unlock() }
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, 0.05)
            var found: AXUIElement?
            guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &found) == .success,
                  let el = found else { return }
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
            let tap: Int32?
            switch role as? String ?? "" {
            case "AXButton", "AXPopUpButton", "AXMenuButton", "AXCheckBox", "AXRadioButton", "AXLink", "AXDisclosureTriangle":
                tap = 5
            case "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField":
                tap = 2
            case "AXMenuItem", "AXMenuBarItem", "AXTab", "AXTabGroup":
                tap = 3
            default:
                tap = nil
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if let last = self.lastElement, CFEqual(last, el) { return }
                self.lastElement = el
                if let tap { Haptics.tick(tap) }
            }
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

/// One switch with an optional control that appears when it's on.
private struct ModeRow<Extra: View>: View {
    let title: String
    let subtitle: String
    let key: String
    var needsAccessibility = false
    @ViewBuilder var extra: Extra

    @ObservedObject private var feel = InputFeel.shared

    private var isOn: Binding<Bool> {
        Binding(get: { UserDefaults.standard.bool(forKey: key) },
                set: { UserDefaults.standard.set($0, forKey: key) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.headline)
                        if needsAccessibility && !feel.accessibilityOK { Pill(text: "needs Accessibility", tint: .orange) }
                    }
                    Hint(subtitle)
                }
                Spacer()
                Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden()
            }
            if isOn.wrappedValue { extra }
        }
    }
}

private extension ModeRow where Extra == EmptyView {
    init(title: String, subtitle: String, key: String, needsAccessibility: Bool = false) {
        self.init(title: title, subtitle: subtitle, key: key, needsAccessibility: needsAccessibility) { EmptyView() }
    }
}

struct FeelView: View {
    let kind: FeelKind
    @ObservedObject private var feel = InputFeel.shared

    private func slider(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>, step: Double,
                        label: String, unit: String = "pt") -> some View {
        let value = Binding(get: { UserDefaults.standard.object(forKey: key) as? Double ?? fallback },
                            set: { UserDefaults.standard.set($0, forKey: key) })
        return HStack {
            Text(label).frame(width: 100, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text("\(Int(value.wrappedValue)) \(unit)").monospacedDigit().frame(width: 64, alignment: .trailing)
        }
    }

    private var typingStyle: Binding<String> {
        Binding(get: { UserDefaults.standard.string(forKey: "feel.typingStyle") ?? "every" },
                set: { UserDefaults.standard.set($0, forKey: "feel.typingStyle") })
    }

    var body: some View {
        let _ = feel.revision
        Screen {
            if !RunInfo.isBundled {
                Card {
                    Label("This is the bare executable, not TPHaptics.app, so macOS can't grant it Accessibility. Quit it and open build/TPHaptics.app (or run ./run.sh).",
                          systemImage: "exclamationmark.octagon.fill")
                        .font(.callout).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            switch kind {
            case .typing: typingScreens
            case .screen: screenScreens
            }
            Hint("These taps respect the Strength slider. They are observe-only: TPHaptics never reads or records what you type, it only notices that a key was pressed.")
        }
    }

    // MARK: Typing & Scroll

    @ViewBuilder private var typingScreens: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                ModeRow(title: "Typewriter", subtitle: "A tap as you type. Space, return, tab and delete get their own strengths.",
                        key: "feel.typing", needsAccessibility: true) {
                    Picker("Taps on", selection: typingStyle) {
                        Text("Every key").tag("every")
                        Text("Words (space & return)").tag("words")
                        Text("Sentences (. ! ? & return)").tag("sentences")
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 520)
                }
                Divider()
                ModeRow(title: "Modifier keys", subtitle: "A light tap for Shift, Control, Option and Command, and a firm click when Caps Lock flips.",
                        key: "feel.modifiers", needsAccessibility: true)
            }
        }
        Card {
            VStack(alignment: .leading, spacing: 16) {
                ModeRow(title: "Scroll notches", subtitle: "A light tick every time you scroll a set distance, like a ratchet.", key: "feel.scroll") {
                    slider("feel.scrollPx", 60, 20...200, step: 5, label: "Notch every")
                }
                Divider()
                ModeRow(title: "Sideways notches", subtitle: "The same for horizontal scrolling, with a slightly stronger tick.", key: "feel.scrollHoriz")
                Divider()
                ModeRow(title: "Direction change", subtitle: "A bump whenever you reverse the scroll direction.", key: "feel.scrollReverse")
            }
        }
        Card {
            VStack(alignment: .leading, spacing: 16) {
                ModeRow(title: "Pinch", subtitle: "A tick for each step as you pinch to zoom.", key: "feel.pinch")
                Divider()
                ModeRow(title: "Rotate", subtitle: "A tick every 15° of two-finger rotation.", key: "feel.rotate")
                Divider()
                ModeRow(title: "Swipes", subtitle: "A firm tap on multi-finger swipes (between pages and spaces).", key: "feel.swipe")
            }
        }
    }

    // MARK: Screen

    @ViewBuilder private var screenScreens: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Lines and edges").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                ModeRow(title: "Grid lines", subtitle: "A tick each time the pointer crosses an invisible grid, so you can feel distance.", key: "feel.grid") {
                    slider("feel.gridPx", 100, 30...400, step: 10, label: "Spacing")
                }
                Divider()
                ModeRow(title: "Window edges", subtitle: "A tap when the pointer moves from one window to another or onto the desktop.", key: "feel.windows")
                Divider()
                ModeRow(title: "Screen edges", subtitle: "A firm tap when the pointer hits the edge of the display.", key: "feel.edges")
                Divider()
                ModeRow(title: "Screen corners", subtitle: "The strongest tap when the pointer lands in a corner, like feeling a hot corner.", key: "feel.corners")
                Divider()
                ModeRow(title: "Between displays", subtitle: "A tap when the pointer crosses from one display to another.", key: "feel.displays")
                Divider()
                ModeRow(title: "Center lines", subtitle: "A tick when the pointer crosses the middle of the screen, horizontally or vertically.", key: "feel.center")
            }
        }
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pointer").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                ModeRow(title: "Speed ratchet", subtitle: "A tap for every stretch the pointer travels. Fast flicks feel firmer than slow moves.", key: "feel.speed") {
                    slider("feel.speedPx", 40, 10...200, step: 5, label: "Tap every")
                }
                Divider()
                ModeRow(title: "Click echo", subtitle: "A firm tap when you press and a light one when you release, anywhere on screen.", key: "feel.clicks")
                Divider()
                ModeRow(title: "Buttons and fields", subtitle: "Feel what's under the pointer: firm for buttons and links, soft for text fields, medium for menus.",
                        key: "feel.elements", needsAccessibility: true)
            }
        }
    }
}
