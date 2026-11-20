import AppKit
import ApplicationServices

/// Appends diagnostics to ~/Library/Logs/TPHaptics.log (and stdout in self-tests).
enum Diag {
    static var echo = false
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/TPHaptics.log")

    static func log(_ s: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
        if echo { print(line, terminator: "") }
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}

/// Detects notification banners system-wide by watching Notification Center's
/// accessibility tree. macOS has no public API for observing other apps'
/// notifications, so this needs the Accessibility permission.
///
/// Banners are shown only when Focus / Do Not Disturb allows them, so a muted
/// notification will not buzz.
final class NotificationWatcher {
    /// Called ~0.25 s after a banner appears, with every piece of text found in it.
    var onNotification: (([String]) -> Void)?
    /// Called with diagnostic text ("Watching…", "Last event: …").
    var onStatus: ((String) -> Void)?

    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var timer: Timer?
    private var lastFire = Date.distantPast
    private var loggedUntrusted = false

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func start() {
        stop()
        attach()
        // Re-attach if Notification Center restarts or permission is granted later.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.attach() }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        detach()
    }

    // MARK: Attach / detach

    private func attach() {
        guard AXIsProcessTrusted() else {
            if observer != nil || !loggedUntrusted { Diag.log("attach: Accessibility NOT trusted"); loggedUntrusted = true }
            detach()
            onStatus?("Waiting for Accessibility permission")
            return
        }
        loggedUntrusted = false
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else {
            detach()
            onStatus?("Notification Center is not running")
            return
        }
        if observer != nil, observedPID == app.processIdentifier { return }
        detach()

        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            Unmanaged<NotificationWatcher>.fromOpaque(refcon).takeUnretainedValue()
                .handle(element, notification as String)
        }
        var obs: AXObserver?
        guard AXObserverCreate(app.processIdentifier, callback, &obs) == .success, let obs else {
            onStatus?("Could not observe Notification Center")
            return
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let a = AXObserverAddNotification(obs, appElement, kAXWindowCreatedNotification as CFString, refcon)
        let b = AXObserverAddNotification(obs, appElement, kAXCreatedNotification as CFString, refcon)
        Diag.log("attach: pid \(app.processIdentifier) windowCreated=\(a.rawValue) created=\(b.rawValue)")
        guard a == .success || b == .success else {
            onStatus?("Could not subscribe to Notification Center events (\(a.rawValue))")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observer = obs
        observedPID = app.processIdentifier
        onStatus?("Watching Notification Center")
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedPID = 0
    }

    // MARK: Events

    private func handle(_ element: AXUIElement, _ notification: String) {
        Diag.log("event \(notification): \(describeChain(element))")
        guard let (subrole, banner) = bannerElement(of: element) else { return }
        onStatus?("Last event: \(notification) / \(subrole)")
        let now = Date()
        guard now.timeIntervalSince(lastFire) > 1.0 else { return }   // one buzz per banner
        lastFire = now
        // Banner text fills in a moment after the window appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.onNotification?(self.collectTexts(banner))
        }
    }

    /// Returns the subrole and element if it (or an ancestor) is a notification banner/alert.
    private func bannerElement(of element: AXUIElement) -> (String, AXUIElement)? {
        var el: AXUIElement? = element
        for _ in 0..<5 {
            guard let cur = el else { return nil }
            // Older macOS labelled banners "AXNotificationCenterBanner"; macOS 26 reports "AXSystemDialog".
            if let s = copyString(cur, kAXSubroleAttribute),
               s.hasPrefix("AXNotificationCenter") || s == "AXSystemDialog" { return (s, cur) }
            el = copyParent(cur)
        }
        return nil
    }

    /// Every title / value / description in the banner's subtree (app name, title, body…).
    func collectTexts(_ root: AXUIElement) -> [String] {
        var out: [String] = []
        func add(_ s: String?) {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, !out.contains(t) else { return }
            out.append(t)
        }
        func walk(_ el: AXUIElement, _ depth: Int) {
            guard depth < 7, out.count < 16 else { return }
            add(copyString(el, kAXTitleAttribute))
            add(copyString(el, kAXValueAttribute))
            add(copyString(el, kAXDescriptionAttribute))
            var v: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &v) == .success,
               let kids = v as? [AXUIElement] {
                for k in kids { walk(k, depth + 1) }
            }
        }
        walk(root, 0)
        return Self.cleanTexts(out)
    }

    /// macOS 26 banners expose a generic window title ("Notification Center") plus one combined
    /// description ("App, title, subtitle, body") next to the individual pieces. Drop the title and
    /// the combined string, and put the app name (its first part) in front.
    static func cleanTexts(_ raw: [String]) -> [String] {
        var t = raw.filter { $0 != "Notification Center" }
        if t.count > 2,
           let combined = t.first(where: { c in t.filter { $0 != c }.allSatisfy { c.contains($0) } }) {
            t.removeAll { $0 == combined }
            if let app = combined.components(separatedBy: ", ").first, !app.isEmpty, !t.contains(app) {
                t.insert(app, at: 0)
            }
        }
        return t
    }

    /// "AXWindow/AXNotificationCenterBanner <- AXApplication/-" style trace for the log.
    private func describeChain(_ element: AXUIElement) -> String {
        var parts: [String] = []
        var el: AXUIElement? = element
        for _ in 0..<5 {
            guard let cur = el else { break }
            parts.append("\(copyString(cur, kAXRoleAttribute) ?? "?")/\(copyString(cur, kAXSubroleAttribute) ?? "-")")
            el = copyParent(cur)
        }
        return parts.joined(separator: " <- ")
    }

    private func copyString(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private func copyParent(_ el: AXUIElement) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &v) == .success,
              let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }
}
