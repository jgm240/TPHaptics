import SwiftUI

/// Handles `tphaptics://…` links, so scripts, Shortcuts and other apps can trigger buzzes.
///
///   tphaptics://play?pattern=Heartbeat&loop=1
///   tphaptics://morse?text=hello&wpm=15
///   tphaptics://buzz?interval=20&duration=2
///   tphaptics://breathe?cycles=4
///   tphaptics://countdown?minutes=5
///   tphaptics://strength?value=0.6
///   tphaptics://stop
@MainActor
enum URLRouter {
    static func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "tphaptics" else { return }
        let action = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        var q: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            q[item.name.lowercased()] = item.value ?? ""
        }
        let model = AppModel.shared
        let loop = ["1", "true", "yes"].contains((q["loop"] ?? "").lowercased())
        func num(_ key: String, _ fallback: Double) -> Double { q[key].flatMap(Double.init) ?? fallback }
        Diag.log("url \(url.absoluteString)")

        switch action {
        case "play":
            guard let name = q["pattern"], let p = model.pattern(named: name) else {
                Diag.log("url play: unknown pattern \(q["pattern"] ?? "(none)")"); return
            }
            model.player.play(p, loop: loop)

        case "morse":
            guard let text = q["text"], !text.isEmpty else { return }
            model.player.play(Morse.pattern(text: text, wpm: num("wpm", 15)), loop: loop)

        case "buzz":
            let interval = min(1000, max(AppModel.minBuzzIntervalMS, num("interval", 20)))
            let duration = min(30, max(0.1, num("duration", 1)))
            let n = max(1, Int(duration / (interval / 1000)))
            let p = HapticPattern(name: "Buzz", detail: "",
                                  events: (0..<n).map { HapticEvent(time: Double($0) * interval / 1000, actuation: Strength.max.id) },
                                  length: Double(n) * interval / 1000)
            model.player.play(p, loop: loop)

        case "breathe":
            let plan = BreathPlan(inhale: num("inhale", 4), hold1: num("hold", 4), exhale: num("exhale", 4),
                                  hold2: num("hold2", 4), cycles: Int(num("cycles", 4)))
            model.player.play(Breathing.pattern(plan), loop: false)

        case "countdown":
            let seconds = num("minutes", 0) * 60 + num("seconds", 0)
            guard seconds > 0 else { return }
            Automations.shared.startCountdown(seconds: seconds)

        case "strength":
            model.strength = min(1, max(0, num("value", model.strength)))

        case "stop":
            model.player.stop()
            model.notifPlayer.stop()
            Automations.shared.cancelCountdown()

        case "open":
            // tphaptics://open brings the app forward; ?screen=pad (or paint, patterns, …) lands on that screen.
            Navigator.shared.reveal(q["screen"].flatMap { AppSection(rawValue: $0.lowercased()) })

        case "feel":
            // tphaptics://feel?speed=70&strength=90&seconds=2 plays one point on the Feel Pad (0–100 each).
            let x = min(100, max(0, num("speed", 50))) / 100, y = min(100, max(0, num("strength", 80))) / 100
            let seconds = min(60, max(0.1, num("seconds", 1.5)))
            model.player.play(FeelPadMap.pattern(x: x, y: y), loop: true)
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if model.player.playingName == "Feel Pad" { model.player.stop() }
            }

        default:
            Diag.log("url: unknown action \(action)")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Diag.log("launch: \(RunInfo.summary) accessibilityTrusted=\(AXIsProcessTrusted())")
        Task { @MainActor in
            Automations.shared.start()
            InputFeel.shared.start()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls { Task { @MainActor in URLRouter.handle(u) } }
    }
}

// MARK: - Command-line helper

enum CLIScript {
    static let installURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/tphaptics")

    static let text = #"""
    #!/bin/zsh
    # tphaptics — trigger TPHaptics from the shell. Needs TPHaptics.app installed.
    usage() {
      cat <<'EOF'
    Usage:
      tphaptics play <pattern> [loop]      e.g. tphaptics play Heartbeat
      tphaptics morse "<text>" [wpm]       e.g. tphaptics morse "build done" 18
      tphaptics buzz <interval-ms> [secs]  e.g. tphaptics buzz 20 2
      tphaptics breathe [cycles]
      tphaptics countdown <minutes>
      tphaptics strength <0-1>
      tphaptics stop
    EOF
    }
    enc() {
      local s="$1" out="" c i
      for (( i = 1; i <= ${#s}; i++ )); do
        c="${s[i]}"
        case "$c" in
          [a-zA-Z0-9.~_-]) out+="$c" ;;
          *) out+=$(printf '%%%02X' "'$c") ;;
        esac
      done
      print -r -- "$out"
    }
    send() { open -g "tphaptics://$1"; }
    case "$1" in
      play)      [[ -n "$2" ]] || { usage; exit 1; }; send "play?pattern=$(enc "$2")${3:+&loop=1}" ;;
      morse)     [[ -n "$2" ]] || { usage; exit 1; }; send "morse?text=$(enc "$2")${3:+&wpm=$3}" ;;
      buzz)      [[ -n "$2" ]] || { usage; exit 1; }; send "buzz?interval=$2${3:+&duration=$3}" ;;
      breathe)   send "breathe${2:+?cycles=$2}" ;;
      countdown) [[ -n "$2" ]] || { usage; exit 1; }; send "countdown?minutes=$2" ;;
      strength)  [[ -n "$2" ]] || { usage; exit 1; }; send "strength?value=$2" ;;
      stop)      send "stop" ;;
      *)         usage; exit 1 ;;
    esac
    """#

    /// The raw script with the leading indentation of the Swift literal removed.
    static var script: String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix("    ") ? String($0.dropFirst(4)) : String($0) }
            .joined(separator: "\n") + "\n"
    }

    static func install() throws {
        let dir = installURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try script.write(to: installURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installURL.path)
    }
}

// MARK: - Screen

struct IntegrationsView: View {
    @State private var installMessage: String?
    @State private var installOK = false

    private let examples: [(String, String)] = [
        ("Play a pattern", "tphaptics://play?pattern=Heartbeat"),
        ("Loop a pattern", "tphaptics://play?pattern=Wave&loop=1"),
        ("Send Morse", "tphaptics://morse?text=done&wpm=18"),
        ("Custom buzz", "tphaptics://buzz?interval=20&duration=2"),
        ("Breathing guide", "tphaptics://breathe?cycles=4"),
        ("Countdown", "tphaptics://countdown?minutes=5"),
        ("Set strength", "tphaptics://strength?value=0.6"),
        ("Open the Feel Pad", "tphaptics://open?screen=pad"),
        ("Play a Feel Pad point", "tphaptics://feel?speed=70&strength=90&seconds=2"),
        ("Stop everything", "tphaptics://stop"),
    ]

    var body: some View {
        Screen {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle(title: "Shortcuts actions",
                              subtitle: "Play Pattern, Get Patterns (pick from a list to build your own buttons), Play Morse, Buzz, Feel Pad Point, Set Strength, Stop Haptics, Start Haptic Countdown, Open Screen and Open Feel Pad.")
                    Hint("These show up in the Shortcuts app only when TPHaptics is built with Xcode (./build-xcode.sh). With the regular build, use the “Open URLs” action with the links below. They cover the same ground, including opening the Feel Pad.")
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    CardTitle(title: "Command line",
                              subtitle: "Install a tphaptics command so scripts can buzz your trackpad, for example when a build finishes.")
                    Text("make && tphaptics play Heartbeat")
                        .font(.system(.callout, design: .monospaced))
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
                    HStack {
                        BigButton(title: "Install command", symbol: "terminal.fill") {
                            do {
                                try CLIScript.install()
                                installOK = true
                                installMessage = "Installed at ~/.local/bin/tphaptics. Add ~/.local/bin to your PATH if needed."
                            } catch {
                                installOK = false
                                installMessage = "Couldn't install: \(error.localizedDescription)"
                            }
                        }
                        if let m = installMessage {
                            Text(m).font(.callout).foregroundStyle(installOK ? .green : .red)
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    CardTitle(title: "Links",
                              subtitle: "Any app can open these. In Shortcuts, use the “Open URLs” action. Names come from the Patterns screen.")
                    ForEach(examples, id: \.1) { title, url in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(title).font(.callout.weight(.medium))
                                Text(url).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Try") { if let u = URL(string: url) { URLRouter.handle(u) } }
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url, forType: .string)
                            } label: { Image(systemName: "doc.on.doc") }
                            .help("Copy link")
                        }
                        if url != examples.last?.1 { Divider() }
                    }
                }
            }

            Hint("In a terminal, put the link in quotes: open \"tphaptics://buzz?interval=20&duration=2\". Or install the command above and use tphaptics buzz 20 2.")
            Hint("Anything on this Mac that can open a link can trigger these, including web pages that you allow to open TPHaptics. Links can only play haptics; they can't change anything else.")
        }
    }
}
