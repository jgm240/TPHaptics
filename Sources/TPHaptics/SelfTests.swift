import Foundation
import AppKit
import SwiftUI

/// Headless checks run with `TPHaptics --selftest --selftest-features`.
enum SelfTests {
    private static func spin(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Renders each screen (and the sidebar panel) to PNGs, for checking the layout without screen-recording access.
    static func snapshots(into dir: String) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        MainActor.assumeIsolated {
            @MainActor func save<V: View>(_ view: V, name: String, width: CGFloat) {
                let r = ImageRenderer(content: view.frame(width: width).background(Color(nsColor: .windowBackgroundColor)))
                r.scale = 2
                guard let img = r.nsImage, let tiff = img.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                    print("snapshot failed: \(name)"); return
                }
                try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
                print("snapshot \(name): \(Int(img.size.width))x\(Int(img.size.height))")
            }
            for s in AppSection.allCases {
                save(SectionBody(section: s, loop: .constant(false)).padding(24), name: s.rawValue, width: 880)
            }
            save(OutputPanel().padding(10), name: "sidebar-panel", width: 280)
        }
    }

    static func features() {
        let a = TrackpadActuator.shared

        // Morse
        print("morse encode: \(Morse.encode("SOS NOW"))   (expect ... --- ... / -. --- .--)")
        let sos = Morse.pattern(text: "SOS", wpm: 20)
        print(String(format: "morse SOS @20wpm: %d clicks, %.2f s (expect 1.62 s)", sos.events.count, sos.length))

        // Breathing
        let b = Breathing.pattern(BreathPlan(inhale: 4, hold1: 4, exhale: 4, hold2: 4, cycles: 2))
        print(String(format: "breathing 2 cycles of 4-4-4-4: %d taps over %.1f s (expect 32 s)", b.events.count, b.length))

        // Countdown
        let c = Automations.countdownPattern(seconds: 90)
        let first = c.events.prefix(3).map { String(format: "%.1f", $0.time) }.joined(separator: ", ")
        print("countdown 90 s: \(c.events.count) taps, first at [\(first)] s, length \(c.length)")

        // Audio: a kick, a mid blip and a treble tick every half second for 4.5 s (~9 of each)
        let bands = AudioHaptics.selfTestBands()
        print("audio hits by band: bass=\(bands[.bass] ?? 0) mids=\(bands[.mids] ?? 0) highs=\(bands[.highs] ?? 0) (expect about 8–9 each)")
        let follow = AudioHaptics.selfTestFollow()
        print("audio loudness follow: loud 2 s = \(follow.loud) taps, quiet 2 s = \(follow.quiet) taps (expect loud >> quiet)")

        // Banner text clean-up (the shape macOS 26 actually produced in a real test)
        let cleaned = NotificationWatcher.cleanTexts([
            "Notification Center", "Script Editor, TPHaptics test, from the agent, Detection test body",
            "TPHaptics test", "from the agent", "Detection test body",
        ])
        print("banner text: \(cleaned)  (expect app name first, no 'Notification Center')")

        // Paint sequencer: height becomes strength, x becomes time, gaps are silence
        let ramp = PaintPattern.events(strokes: [[CGPoint(x: 0, y: 0.1), CGPoint(x: 1, y: 1)]], length: 2, interval: 0.05)
        let rampIDs = ramp.compactMap(\.actuation)
        let rising = zip(rampIDs, rampIDs.dropFirst()).allSatisfy { $0 <= $1 }
        print("paint ramp: \(ramp.count) taps, strength \(rampIDs.first ?? 0) → \(rampIDs.last ?? 0), never decreasing = \(rising) (expect 40 taps, 1 → 6, true)")
        let gap = PaintPattern.events(strokes: [[CGPoint(x: 0.25, y: 0.9), CGPoint(x: 0.5, y: 0.9)]], length: 2, interval: 0.05)
        print(String(format: "paint gap: %d taps between %.2f s and %.2f s (expect 11 taps: the stroke's end bin counts, 0.50 to 1.00 s)",
                     gap.count, gap.first?.time ?? -1, gap.last?.time ?? -1))
        let flat = PaintPattern.events(strokes: [[CGPoint(x: 0, y: 0.04), CGPoint(x: 1, y: 0.04)]], length: 1, interval: 0.05)
        print("paint silent strip: \(flat.count) taps (expect 0)")
        let backwards = PaintPattern.events(strokes: [[CGPoint(x: 1, y: 0.9), CGPoint(x: 0, y: 0.9)]], length: 1, interval: 0.1)
        print("paint right-to-left: \(backwards.count) taps (expect 10)")

        // Tap-to-click detection (synthetic events, not posted): short = tap, long = physical press
        for ms in [8.0, 25.0, 60.0, 140.0] {
            print("tap-to-click \(Int(ms)) ms click -> \(InputFeel.shared.selfTestClick(durationMs: ms) ?? "n/a")  (expect tap under the \(Int(UserDefaults.standard.object(forKey: "feel.tapMaxMs") as? Double ?? 35)) ms threshold)")
            usleep(200_000)
        }

        // Pattern library round-trip
        MainActor.assumeIsolated {
            let lib = PatternLibrary.shared
            let probe = UserPattern(name: "__selftest__", length: 1,
                                    taps: [UserTap(time: 0, level: 6), UserTap(time: 0.5, level: 3)])
            lib.save(probe)
            let found = AppModel.shared.pattern(named: "__SELFTEST__")
            print("library: saved and found by name = \(found != nil), events = \(found?.events.count ?? 0) (expect 2)")
            if let data = lib.exportData(probe), let back = lib.importData(data) {
                print("library: export/import round-trip taps = \(back.taps.count) (expect 2)")
            }
            lib.delete(lib.patterns.first { $0.name == "__selftest__" }?.id ?? UUID())
            print("library: cleaned up = \(AppModel.shared.pattern(named: "__selftest__") == nil)")

            // Notification rules
            let model = AppModel.shared
            let saved = model.rules
            model.rules = [NotificationRule(match: "messages", patternName: Presets.heartbeat.name)]
            model.handleNotification(["Messages", "Alex", "hello"])
            model.handleNotification(["Mail", "Bob", "invoice"])
            let seen = model.recentNotifications.map { "\($0.texts.first ?? "?") -> \($0.matchedRule ?? "default")" }
            print("rules: \(Array(seen.reversed()))  (expect Messages -> messages, Mail -> default)")
            spin(2.2)
            model.notifPlayer.stop()
            model.rules = saved
        }

        // URL router
        MainActor.assumeIsolated {
            let before = a.actuationCount
            URLRouter.handle(URL(string: "tphaptics://play?pattern=Knock%20Knock")!)
            spin(1.8)
            print("url play Knock Knock: +\(a.actuationCount - before) actuations (expect 3)")
            let b2 = a.actuationCount
            URLRouter.handle(URL(string: "tphaptics://buzz?interval=20&duration=0.5")!)
            spin(0.9)
            print("url buzz 20ms/0.5s: +\(a.actuationCount - b2) actuations (expect about 25)")
            URLRouter.handle(URL(string: "tphaptics://play?pattern=NoSuchPattern")!)
            print("url unknown pattern handled without crashing")
        }

        // CLI script syntax
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tphaptics-cli-test")
        try? CLIScript.script.write(to: tmp, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-n", tmp.path]
        try? p.run(); p.waitUntilExit()
        print("cli script: zsh -n exit \(p.terminationStatus) (expect 0)")
        try? FileManager.default.removeItem(at: tmp)
    }
}
