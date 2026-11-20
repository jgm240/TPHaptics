import SwiftUI
import EventKit
import IOKit.ps

/// Event-driven buzzes: charger, low battery, hourly chime, countdown, calendar.
@MainActor
final class Automations: ObservableObject {
    static let shared = Automations()

    @Published private(set) var batteryText = "—"
    @Published private(set) var calendarStatus = "Off"
    @Published private(set) var nextEventText: String?
    @Published private(set) var countdownEnd: Date?

    private let defaults = UserDefaults.standard
    private let eventPlayer = PatternPlayer()
    private let countdownPlayer = PatternPlayer()
    private let store = EKEventStore()
    private var started = false
    private var timer: Timer?
    private var notified = Set<String>()
    private var lastChimeKey = ""
    private var lastOnAC: Bool?
    private var lowArmed = true
    private var calendarRequested = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        installPowerMonitor()
        powerChanged(initial: true)
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.defaultsChanged() }
        }
        defaultsChanged()
    }

    private func fire(_ patternName: String) {
        guard patternName != AppModel.silentName else { return }
        eventPlayer.play(AppModel.shared.resolvePattern(patternName), loop: false)
    }

    private func name(_ key: String, _ fallback: String) -> String { defaults.string(forKey: key) ?? fallback }

    // MARK: Power

    private struct PowerState { var onAC: Bool; var percent: Int?; var charging: Bool }

    private func readPower() -> PowerState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        var percent: Int?
        var charging = false
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey as String] as? String == kIOPSInternalBatteryType else { continue }
            if let cur = d[kIOPSCurrentCapacityKey as String] as? Int, let mx = d[kIOPSMaxCapacityKey as String] as? Int, mx > 0 {
                percent = Int((Double(cur) / Double(mx) * 100).rounded())
            }
            charging = d[kIOPSIsChargingKey as String] as? Bool ?? false
        }
        let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        return PowerState(onAC: source == kIOPMACPowerKey, percent: percent, charging: charging)
    }

    private func installPowerMonitor() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            let me = Unmanaged<Automations>.fromOpaque(ctx).takeUnretainedValue()
            Task { @MainActor in me.powerChanged(initial: false) }
        }
        if let src = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }

    private func powerChanged(initial: Bool) {
        guard let s = readPower() else { return }
        batteryText = (s.percent.map { "\($0)% " } ?? "") + (s.onAC ? "on power" : "on battery")
        if !initial, let last = lastOnAC, last != s.onAC, defaults.bool(forKey: "auto.charger") {
            fire(s.onAC ? name("auto.plugPattern", "Double Tap") : name("auto.unplugPattern", "Knock Knock"))
        }
        lastOnAC = s.onAC

        if defaults.bool(forKey: "auto.lowBattery"), let pct = s.percent {
            let threshold = defaults.object(forKey: "auto.lowBatteryPct") as? Int ?? 20
            if !s.onAC && pct <= threshold && lowArmed {
                lowArmed = false
                fire(name("auto.lowBatteryPattern", "Heartbeat"))
            }
            if s.onAC || pct > threshold + 5 { lowArmed = true }
        }
    }

    // MARK: Periodic checks (chime, calendar)

    private func tick() {
        chimeIfDue()
        checkCalendar()
    }

    private func defaultsChanged() {
        if defaults.bool(forKey: "auto.calendar") {
            if !calendarRequested { requestCalendar() }
        } else {
            calendarStatus = "Off"
            nextEventText = nil
        }
        powerChanged(initial: true)   // refresh text / re-arm thresholds
    }

    // MARK: Hourly chime

    private func chimeIfDue() {
        guard defaults.bool(forKey: "auto.chime") else { return }
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        guard c.minute == 0, let hour = c.hour else { return }
        let from = defaults.object(forKey: "auto.chimeFrom") as? Int ?? 9
        let to = defaults.object(forKey: "auto.chimeTo") as? Int ?? 21
        guard hour >= from && hour <= to else { return }
        let key = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)-\(hour)"
        guard key != lastChimeKey else { return }
        lastChimeKey = key
        let count = hour % 12 == 0 ? 12 : hour % 12
        let events = (0..<count).map { HapticEvent(time: Double($0) * 0.35, actuation: Strength.strong.id) }
        eventPlayer.play(HapticPattern(name: "Chime", detail: "", events: events, length: Double(count) * 0.35), loop: false)
    }

    // MARK: Calendar

    private var calendarAuthorized: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) { return status == .fullAccess }
        return status == .authorized
    }

    private func requestCalendar() {
        calendarRequested = true
        calendarStatus = "Waiting for permission…"
        let handler: (Bool, Error?) -> Void = { [weak self] granted, _ in
            Task { @MainActor in
                self?.calendarStatus = granted ? "Watching your calendar"
                                               : "Calendar access denied — allow it in System Settings → Privacy & Security → Calendars"
                if granted { self?.checkCalendar() }
            }
        }
        if #available(macOS 14.0, *) { store.requestFullAccessToEvents(completion: handler) }
        else { store.requestAccess(to: .event, completion: handler) }
    }

    private func checkCalendar() {
        guard defaults.bool(forKey: "auto.calendar"), calendarAuthorized else { return }
        let minutes = Double(max(1, defaults.object(forKey: "auto.calendarMinutes") as? Int ?? 5))
        let now = Date()

        let upcoming = store.events(matching: store.predicateForEvents(withStart: now, end: now.addingTimeInterval(24 * 3600), calendars: nil))
            .filter { !$0.isAllDay && $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }
        if let e = upcoming.first {
            let f = DateFormatter(); f.timeStyle = .short
            nextEventText = "\(e.title ?? "Event") at \(f.string(from: e.startDate))"
        } else {
            nextEventText = nil
        }

        for e in upcoming where e.startDate.timeIntervalSince(now) <= minutes * 60 {
            let key = "\(e.eventIdentifier ?? e.title ?? "")|\(e.startDate.timeIntervalSince1970)"
            guard !notified.contains(key) else { continue }
            notified.insert(key)
            fire(name("auto.calendarPattern", "Wave"))
            break
        }
    }

    // MARK: Countdown

    /// Gentle tick each minute, a tick per second for the last 10 s, quicker ticks in the last 3 s, then a triple knock.
    nonisolated static func countdownPattern(seconds total: Double) -> HapticPattern {
        var events: [HapticEvent] = []
        var remaining = 60.0                 // a soft tick at 1:00, 2:00… left
        while remaining < total {
            events.append(HapticEvent(time: total - remaining, actuation: Strength.light.id))
            remaining += 60
        }
        var s = min(10.0, total).rounded(.down)
        while s >= 1 {
            if s > 3 { events.append(HapticEvent(time: total - s, actuation: 3)) }
            else {
                for k in 0..<4 { events.append(HapticEvent(time: total - s + Double(k) * 0.25, actuation: 5)) }
            }
            s -= 1
        }
        for k in 0..<3 { events.append(HapticEvent(time: total + Double(k) * 0.18, actuation: Strength.max.id)) }
        events.sort { $0.time < $1.time }
        return HapticPattern(name: "Countdown", detail: "", events: events, length: total + 0.8)
    }

    func startCountdown(seconds: Double) {
        guard seconds > 0 else { return }
        countdownEnd = Date().addingTimeInterval(seconds)
        countdownPlayer.play(Self.countdownPattern(seconds: seconds), loop: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 1) { [weak self] in
            Task { @MainActor in
                if let end = self?.countdownEnd, end <= Date() { self?.countdownEnd = nil }
            }
        }
    }

    func cancelCountdown() {
        countdownPlayer.stop()
        countdownEnd = nil
    }
}

// MARK: - Screen

struct AutomationsView: View {
    @ObservedObject private var auto = Automations.shared

    @AppStorage("auto.charger") private var charger = false
    @AppStorage("auto.plugPattern") private var plugPattern = "Double Tap"
    @AppStorage("auto.unplugPattern") private var unplugPattern = "Knock Knock"
    @AppStorage("auto.lowBattery") private var lowBattery = false
    @AppStorage("auto.lowBatteryPct") private var lowPct = 20
    @AppStorage("auto.lowBatteryPattern") private var lowPattern = "Heartbeat"
    @AppStorage("auto.chime") private var chime = false
    @AppStorage("auto.chimeFrom") private var chimeFrom = 9
    @AppStorage("auto.chimeTo") private var chimeTo = 21
    @AppStorage("auto.calendar") private var calendar = false
    @AppStorage("auto.calendarMinutes") private var calendarMinutes = 5
    @AppStorage("auto.calendarPattern") private var calendarPattern = "Wave"

    @State private var cdMinutes = 5
    @State private var cdSeconds = 0

    var body: some View {
        Screen {
            // Power
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        CardTitle(title: "Power", subtitle: "Know when the charger changes without looking.")
                        Spacer()
                        Pill(text: auto.batteryText, tint: .secondary)
                    }
                    row(title: "Charger plugged in or out", isOn: $charger) {
                        PatternPicker(title: "Plugged in", name: $plugPattern).frame(width: 240)
                        PatternPicker(title: "Unplugged", name: $unplugPattern).frame(width: 240)
                    }
                    Divider()
                    row(title: "Low battery", isOn: $lowBattery) {
                        Stepper("At \(lowPct)%", value: $lowPct, in: 5...50, step: 5).frame(width: 130)
                        PatternPicker(title: "Pattern", name: $lowPattern).frame(width: 240)
                    }
                }
            }

            // Chime
            Card {
                row(title: "Hourly chime", subtitle: "Taps once for each hour, 1 to 12, on the hour.", isOn: $chime) {
                    Stepper("From \(hourLabel(chimeFrom))", value: $chimeFrom, in: 0...23).frame(width: 150)
                    Stepper("To \(hourLabel(chimeTo))", value: $chimeTo, in: 0...23).frame(width: 150)
                }
            }

            // Countdown
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    CardTitle(title: "Countdown",
                              subtitle: "A soft tick each minute, one per second for the last 10, faster for the last 3, then a triple knock.")
                    HStack(spacing: 16) {
                        Stepper("\(cdMinutes) min", value: $cdMinutes, in: 0...180).frame(width: 130)
                        Stepper("\(cdSeconds) sec", value: $cdSeconds, in: 0...59, step: 5).frame(width: 130)
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                            if let end = auto.countdownEnd, end > ctx.date {
                                BigValue(value: remainingText(end.timeIntervalSince(ctx.date)))
                            }
                        }
                        if auto.countdownEnd != nil {
                            BigButton(title: "Cancel", symbol: "xmark", tint: .red) { auto.cancelCountdown() }
                        } else {
                            BigButton(title: "Start", symbol: "timer") {
                                auto.startCountdown(seconds: Double(cdMinutes * 60 + cdSeconds))
                            }
                        }
                    }
                }
            }

            // Calendar
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    row(title: "Calendar reminders", subtitle: "A buzz shortly before each event starts.", isOn: $calendar) {
                        Stepper("\(calendarMinutes) min before", value: $calendarMinutes, in: 1...60).frame(width: 170)
                        PatternPicker(title: "Pattern", name: $calendarPattern).frame(width: 240)
                    }
                    if calendar {
                        HStack {
                            Pill(text: auto.calendarStatus,
                                 tint: auto.calendarStatus.hasPrefix("Watching") ? .green : .orange)
                            if let n = auto.nextEventText { Text("Next: \(n)").font(.callout).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
    }

    private func row<Trailing: View>(title: String, subtitle: String? = nil, isOn: Binding<Bool>,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardTitle(title: title, subtitle: subtitle)
                Spacer()
                Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden()
            }
            if isOn.wrappedValue {
                HStack(spacing: 16) { trailing(); Spacer() }
            }
        }
    }

    private func hourLabel(_ h: Int) -> String {
        let hh = h % 12 == 0 ? 12 : h % 12
        return "\(hh)\(h < 12 ? "am" : "pm")"
    }

    private func remainingText(_ s: TimeInterval) -> String {
        let t = Int(s.rounded(.up))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
