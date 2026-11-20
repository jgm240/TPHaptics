import SwiftUI

enum AppScreen: String, CaseIterable, Identifiable, Hashable {
    case patterns, sequencer, paint, buzz
    case pad, breathe, morse
    case audio
    case simon, hotcold, rhythm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .patterns: return "Patterns"
        case .sequencer: return "Sequencer"
        case .paint: return "Paint"
        case .buzz: return "Buzz"
        case .pad: return "Feel Pad"
        case .breathe: return "Breathing"
        case .morse: return "Morse"
        case .audio: return "Audio to Haptics"
        case .simon: return "Simon"
        case .hotcold: return "Hot & Cold"
        case .rhythm: return "Rhythm Echo"
        }
    }

    var subtitle: String {
        switch self {
        case .patterns: return "Ready-made patterns, plus your own"
        case .sequencer: return "A 16-step grid of taps"
        case .paint: return "Draw a line: time across, strength up"
        case .buzz: return "Rapid taps or a true continuous hum"
        case .pad: return "Slide a finger to shape the vibration"
        case .breathe: return "A silent swell-and-fade guide"
        case .morse: return "Feel text as dots and dashes"
        case .audio: return "Turn sound around you into taps"
        case .simon: return "Repeat the sequence by feel"
        case .hotcold: return "Find the hidden spot"
        case .rhythm: return "Tap back the rhythm you feel"
        }
    }

    var icon: String {
        switch self {
        case .patterns: return "list.bullet"
        case .sequencer: return "square.grid.4x3.fill"
        case .paint: return "paintbrush.pointed.fill"
        case .buzz: return "waveform"
        case .pad: return "hand.point.up.left.fill"
        case .breathe: return "wind"
        case .morse: return "dot.radiowaves.left.and.right"
        case .audio: return "mic.fill"
        case .simon: return "circle.grid.2x2.fill"
        case .hotcold: return "thermometer.medium"
        case .rhythm: return "metronome.fill"
        }
    }

    var tint: Color {
        switch self {
        case .patterns: return .blue
        case .sequencer: return .indigo
        case .paint: return .orange
        case .buzz: return .teal
        case .pad: return .pink
        case .breathe: return .mint
        case .morse: return .cyan
        case .audio: return .green
        case .simon: return .purple
        case .hotcold: return .red
        case .rhythm: return .brown
        }
    }

    static let groups: [(name: String, items: [AppScreen])] = [
        ("Play", [.patterns, .sequencer, .paint, .buzz]),
        ("Feel", [.pad, .breathe, .morse]),
        ("Listen", [.audio]),
        ("Games", [.simon, .hotcold, .rhythm]),
    ]
}

struct RootView: View {
    @State private var path: [AppScreen]

    init() {
        // `-startScreen paint` as a launch argument opens that screen directly (used for screenshots).
        if let raw = UserDefaults.standard.string(forKey: "startScreen"), let s = AppScreen(rawValue: raw) {
            _path = State(initialValue: [s])
        } else {
            _path = State(initialValue: [])
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            HomeView()
                .navigationDestination(for: AppScreen.self) { ScreenView(screen: $0) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { ControlBar() }
    }
}

struct ScreenView: View {
    let screen: AppScreen
    var body: some View {
        Group {
            switch screen {
            case .patterns: PatternsView()
            case .sequencer: SequencerView()
            case .paint: PaintView()
            case .buzz: BuzzView()
            case .pad: FeelPadView()
            case .breathe: BreathingView()
            case .morse: MorseView()
            case .audio: AudioView()
            case .simon: SimonView()
            case .hotcold: HotColdView()
            case .rhythm: RhythmEchoView()
            }
        }
        .navigationTitle(screen.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HomeView: View {
    @ObservedObject private var haptics = Haptics.shared

    var body: some View {
        List {
            if !haptics.supported {
                Section {
                    Label("This device doesn't report a Taptic Engine (an iPad or the Simulator?). You can look around, but nothing will vibrate.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            ForEach(AppScreen.groups, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.items) { s in
                        NavigationLink(value: s) {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.title)
                                    Text(s.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                IconTile(symbol: s.icon, tint: s.tint)
                            }
                        }
                    }
                }
            }
            Section {
                Text("iOS only lets apps vibrate while they're open on screen, so IPHaptics can't buzz in the background or on notifications.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("IPHaptics")
    }
}

/// Master strength and Stop, always within reach.
struct ControlBar: View {
    @ObservedObject private var haptics = Haptics.shared

    private var label: String {
        if haptics.strength <= 0 { return "Off" }
        if haptics.strength >= 1 { return "Max" }
        return "\(Int((haptics.strength * 100).rounded()))%"
    }

    var body: some View {
        VStack(spacing: 8) {
            if let name = haptics.playingName {
                HStack {
                    Pill(text: "Playing · \(name)", tint: .green)
                    Spacer()
                    Button { haptics.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                        .buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "waveform.path").foregroundStyle(.secondary)
                Text("Strength").font(.subheadline.weight(.semibold))
                Slider(value: $haptics.strength, in: 0...1)
                Text(label).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
