import SwiftUI

// MARK: - Sections

enum AppSection: String, CaseIterable, Identifiable {
    case patterns, sequencer, paint, editor, buzz
    case notifications, automations, audio
    case morse, breathe, games
    case pad, typing, screen
    case test, integrations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .patterns: return "Patterns"
        case .sequencer: return "Sequencer"
        case .paint: return "Paint"
        case .editor: return "Pattern Editor"
        case .buzz: return "Buzz"
        case .notifications: return "Notifications"
        case .automations: return "Automations"
        case .audio: return "Audio to Haptics"
        case .morse: return "Morse"
        case .breathe: return "Breathing"
        case .games: return "Games"
        case .pad: return "Feel Pad"
        case .typing: return "Typing & Scroll"
        case .screen: return "Feel the Screen"
        case .test: return "Actuation Test"
        case .integrations: return "Shortcuts & CLI"
        }
    }

    var subtitle: String {
        switch self {
        case .patterns: return "Ready-made patterns. Press play and feel them."
        case .sequencer: return "A 16-step grid. Click steps to build a rhythm."
        case .paint: return "Paint a line: left to right is time, height is strength."
        case .editor: return "Draw your own pattern on a timeline and save it."
        case .buzz: return "A steady train of taps with an interval you choose."
        case .notifications: return "Buzz when a notification arrives, with rules per app."
        case .automations: return "Charger, battery, hourly chime, countdowns and calendar."
        case .audio: return "Turn the beat of any sound into taps."
        case .morse: return "Send text as dots and dashes you can feel."
        case .breathe: return "A silent guide: swell in, hold, fade out."
        case .games: return "Three games you play by feel."
        case .pad: return "Slide to shape a buzz: up is stronger, right is faster."
        case .typing: return "A tap for every keystroke and every scroll notch."
        case .screen: return "Feel grid lines, window edges and screen edges."
        case .test: return "Fire one raw actuation ID at a time."
        case .integrations: return "Trigger buzzes from scripts, Shortcuts and other apps."
        }
    }

    var icon: String {
        switch self {
        case .patterns: return "list.bullet"
        case .sequencer: return "square.grid.4x3.fill"
        case .paint: return "paintbrush.pointed.fill"
        case .editor: return "scribble.variable"
        case .buzz: return "waveform"
        case .notifications: return "bell.badge.fill"
        case .automations: return "bolt.fill"
        case .audio: return "mic.fill"
        case .morse: return "dot.radiowaves.left.and.right"
        case .breathe: return "wind"
        case .games: return "gamecontroller.fill"
        case .pad: return "hand.point.up.left.fill"
        case .typing: return "keyboard.fill"
        case .screen: return "cursorarrow.motionlines"
        case .test: return "number"
        case .integrations: return "link"
        }
    }

    var tint: Color {
        switch self {
        case .patterns: return .blue
        case .sequencer: return .indigo
        case .paint: return .orange
        case .editor: return .purple
        case .buzz: return .teal
        case .notifications: return .orange
        case .automations: return .yellow
        case .audio: return .green
        case .morse: return .cyan
        case .breathe: return .mint
        case .games: return .purple
        case .pad: return .pink
        case .typing: return .brown
        case .screen: return .blue
        case .test: return .gray
        case .integrations: return .gray
        }
    }

    static let groups: [(name: String, items: [AppSection])] = [
        ("Play", [.patterns, .sequencer, .paint, .editor, .buzz]),
        ("Triggers", [.notifications, .automations, .audio]),
        ("Fun", [.morse, .breathe, .games]),
        ("Feel", [.pad, .typing, .screen]),
        ("Tools", [.test, .integrations]),
    ]
}

// MARK: - Shell

struct ContentView: View {
    @ObservedObject private var player = AppModel.shared.player
    @ObservedObject private var navigator = Navigator.shared
    @State private var section: AppSection = .patterns
    @State private var loop = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 300)
        } detail: {
            detail
        }
        .frame(minWidth: 980, minHeight: 700)
        .onChange(of: section) { _ in player.stop() }
        // Links and Shortcuts actions can ask for a screen, including before the window first appears.
        .onChange(of: navigator.request) { request in
            if let request { section = request; navigator.request = nil }
        }
        .onAppear {
            if let request = navigator.request { section = request; navigator.request = nil }
        }
    }

    private var sidebar: some View {
        List(selection: $section) {
            ForEach(AppSection.groups, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.items) { s in
                        Label { Text(s.title) } icon: { IconTile(symbol: s.icon, tint: s.tint) }
                            .tag(s)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OutputPanel().padding(10)
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                content
                    .padding(24)
                    .frame(maxWidth: 860, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconTile(symbol: section.icon, tint: section.tint, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title).font(.title2.weight(.bold))
                Text(section.subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let name = player.playingName {
                Pill(text: "Playing · \(name)", tint: .green)
                Button { player.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            if [.patterns, .sequencer, .paint, .editor, .morse].contains(section) {
                Toggle("Loop", isOn: $loop).toggleStyle(.switch).controlSize(.small)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }

    private var content: some View { SectionBody(section: section, loop: $loop) }
}

/// The content of one screen. Separate from the shell so it can also be rendered on its own.
struct SectionBody: View {
    let section: AppSection
    @Binding var loop: Bool

    @ViewBuilder var body: some View {
        switch section {
        case .patterns: PatternsView(loop: $loop)
        case .sequencer: SequencerView(loop: $loop)
        case .paint: PaintView(loop: $loop)
        case .editor: PatternEditorView(loop: $loop)
        case .buzz: BuzzView()
        case .notifications: NotificationsView()
        case .automations: AutomationsView()
        case .audio: AudioHapticsView()
        case .morse: MorseView(loop: $loop)
        case .breathe: BreathingView()
        case .games: GamesView()
        case .pad: FeelPadView()
        case .typing: FeelView(kind: .typing)
        case .screen: FeelView(kind: .screen)
        case .test: TestView()
        case .integrations: IntegrationsView()
        }
    }
}

// MARK: - Sidebar output panel (strength + system trackpad settings)

struct OutputPanel: View {
    @ObservedObject private var model = AppModel.shared
    private let actuator = TrackpadActuator.shared

    private var strengthLabel: String {
        if model.strength <= 0 { return "Off" }
        if model.strength >= 1 { return "Max" }
        return "\(Int((model.strength * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(actuator.isDirect ? Color.green : Color.orange).frame(width: 8, height: 8)
                Text(actuator.isDirect ? "Trackpad ready · no touch needed" : "Needs a finger on the trackpad")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .help(actuator.status)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Strength").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(strengthLabel)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(model.strength >= 1 ? Color.accentColor : .secondary)
                }
                Slider(value: $model.strength, in: 0...1)
                HStack {
                    Text("Off")
                    Spacer()
                    Text("Max Power of Actuator")
                }
                .font(.caption2).foregroundStyle(.secondary)
            }

            Divider()

            Text("System trackpad settings").font(.caption).foregroundStyle(.secondary)
            Toggle("Silent Clicking", isOn: Binding(get: { model.silentClicking },
                                                    set: { model.setSilentClicking($0) }))
            Toggle("Force Click & haptics", isOn: Binding(get: { model.forceClickEnabled },
                                                          set: { model.setForceClickEnabled($0) }))
                .disabled(!model.canToggleForceClick)
            if let m = model.settingsMessage {
                Text(m).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.cardStroke))
    }
}
