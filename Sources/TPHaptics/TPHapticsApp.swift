import SwiftUI

@main
struct TPHapticsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let args = CommandLine.arguments
        // `--selftest` prints actuator status, fires a few taps, and exits.
        if args.contains("--selftest") {
            let a = TrackpadActuator.shared
            print("direct=\(a.isDirect)")
            print("status=\(a.status)")
            for id in [1, 3, 5, 6] as [Int32] {
                a.actuate(id)
                print("actuate(\(id)) -> \(a.lastResult)")
                usleep(300_000)
            }
            // `--selftest-speed` measures how fast actuate() can be called back to back.
            if args.contains("--selftest-speed") {
                let n = 300
                let t0 = DispatchTime.now().uptimeNanoseconds
                for _ in 0..<n { a.actuate(6) }
                let dt = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
                print(String(format: "%d actuations in %.1f ms (%.3f ms each)", n, dt, dt / Double(n)))
            }
            // `--selftest-notify` watches Notification Center for 8 s while a test banner is posted.
            if args.contains("--selftest-notify") {
                Diag.echo = true
                print("accessibilityTrusted=\(NotificationWatcher.isTrusted)")
                let w = NotificationWatcher()
                w.onStatus = { print("status: \($0)") }
                w.onNotification = { print(">>> NOTIFICATION DETECTED: \($0)") }
                w.start()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                    p.arguments = ["-e", "display notification \"TPHaptics detection test\" with title \"TPHaptics\""]
                    try? p.run()
                }
                RunLoop.main.run(until: Date().addingTimeInterval(8))
                exit(0)
            }
            // `--selftest-settings` round-trips both system switches and restores them.
            if args.contains("--selftest-settings") {
                let silent0 = TrackpadSettings.silentClicking
                let force0 = a.forceClickEnabled
                let pref0 = TrackpadSettings.forceClickPreference
                print("start: silent=\(silent0) force=\(String(describing: force0)) forcePref=\(pref0)")
                TrackpadSettings.setSilentClicking(!silent0)
                print("silent flipped -> \(TrackpadSettings.silentClicking) (expect \(!silent0))")
                TrackpadSettings.setSilentClicking(silent0)
                print("silent restored -> \(TrackpadSettings.silentClicking)")
                let r = a.setForceClickEnabled(!(force0 ?? true))
                TrackpadSettings.setForceClickPreference(!pref0)
                print("force flipped rc=\(r) -> \(String(describing: a.forceClickEnabled)) pref=\(TrackpadSettings.forceClickPreference)")
                a.setForceClickEnabled(force0 ?? true)
                TrackpadSettings.setForceClickPreference(pref0)
                print("force restored -> \(String(describing: a.forceClickEnabled)) pref=\(TrackpadSettings.forceClickPreference)")
            }
            // `--selftest-player` runs a 1 ms-interval, 1 s buzz through the real player.
            if args.contains("--selftest-player") {
                MainActor.assumeIsolated {
                    let model = AppModel.shared
                    model.buzzIntervalMS = 1
                    model.buzzDuration = 1
                    model.buzzContinuous = false
                    let before = a.actuationCount
                    let t0 = Date()
                    model.player.play(model.buzzPattern(), loop: false)
                    while model.player.isPlaying && Date().timeIntervalSince(t0) < 5 {
                        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                    }
                    let dt = Date().timeIntervalSince(t0)
                    print(String(format: "player: %d actuations in %.2f s, isPlaying=%@",
                                 a.actuationCount - before, dt, model.player.isPlaying ? "true" : "false"))
                    // Continuous mode must stop on request.
                    model.buzzContinuous = true
                    model.player.play(model.buzzPattern(), loop: true)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
                    let c1 = a.actuationCount
                    model.player.stop()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                    print("continuous: \(c1 - before) actuations; after stop +\(a.actuationCount - c1), isPlaying=\(model.player.isPlaying)")
                }
            }
            // `--snapshot-dir <path>` renders every screen to PNG files.
            if let i = args.firstIndex(of: "--snapshot-dir"), i + 1 < args.count {
                SelfTests.snapshots(into: args[i + 1])
            }
            // `--selftest-features` exercises the logic of the newer features and prints results.
            if args.contains("--selftest-features") {
                SelfTests.features()
            }
            exit(a.isDirect ? 0 : 1)
        }
    }

    var body: some Scene {
        WindowGroup("TPHaptics", id: "main") {
            ContentView()
        }
        .defaultSize(width: 1120, height: 780)
        .handlesExternalEvents(matching: [])     // tphaptics:// links go to AppDelegate, not new windows

        MenuBarExtra("TPHaptics", systemImage: "hand.tap") {
            MenuContent()
        }
    }
}

private struct MenuContent: View {
    @ObservedObject private var model = AppModel.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Buzz on notifications", isOn: $model.notifyEnabled)
        Divider()
        Button("Show Window") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit TPHaptics") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
