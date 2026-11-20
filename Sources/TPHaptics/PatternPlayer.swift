import Foundation
import SwiftUI
import Darwin

/// Thread-safe holder so a running loop can be edited live.
final class PatternBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: HapticPattern
    init(_ v: HapticPattern) { _value = v }
    var value: HapticPattern {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}

/// Cancellation flag shared with the timing thread.
final class RunToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
    func cancel() { lock.lock(); _cancelled = true; lock.unlock() }
}

@MainActor
final class PatternPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var playhead: Int? = nil
    @Published private(set) var playingName: String? = nil

    private var token: RunToken?
    private var box: PatternBox?
    private let actuator = TrackpadActuator.shared

    /// Patterns with more events than this don't report a playhead
    /// (so fast buzzes don't spam the UI thread).
    private static let playheadEventLimit = 64

    func play(_ pattern: HapticPattern, loop: Bool) {
        stop()
        let box = PatternBox(pattern)
        let token = RunToken()
        self.box = box
        self.token = token
        isPlaying = true
        playingName = pattern.name
        let actuator = self.actuator

        // A dedicated thread with absolute mach deadlines keeps sub-millisecond
        // spacing accurate, which Swift's async sleep can't do.
        let thread = Thread { [weak self] in
            var tb = mach_timebase_info_data_t()
            mach_timebase_info(&tb)
            func ticks(_ seconds: Double) -> UInt64 {
                UInt64(max(0, seconds) * 1_000_000_000 * Double(tb.denom) / Double(tb.numer))
            }
            let lateLimit = ticks(0.015)
            // Long waits (countdowns, breathing) are sliced so Stop reacts quickly.
            func wait(until deadline: UInt64) {
                let chunk = ticks(0.05)
                while !token.cancelled {
                    let now = mach_absolute_time()
                    if now >= deadline { return }
                    mach_wait_until(min(deadline, now &+ chunk))
                }
            }
            repeat {
                let p = box.value           // re-read each pass → live edits
                let peak = p.events.compactMap(\.actuation).max() ?? 1
                let reportPlayhead = p.events.count <= Self.playheadEventLimit
                let start = mach_absolute_time()
                for (i, e) in p.events.enumerated() {
                    let deadline = start + ticks(e.time)
                    wait(until: deadline)
                    if token.cancelled { break }
                    // The actuator plays one click at a time (~4–6 ms each). If a
                    // tap is already too late, drop it so the pattern keeps its
                    // real duration instead of dragging on.
                    let now = mach_absolute_time()
                    let isLate = now > deadline && now - deadline > lateLimit
                    if !isLate, let a = e.actuation,
                       let id = actuator.scaledID(authored: a, peak: peak, normalize: p.normalize) {
                        actuator.actuate(id)
                    }
                    if reportPlayhead { Task { @MainActor in self?.setPlayhead(i, token) } }
                }
                if token.cancelled { break }
                wait(until: start + ticks(p.length))
            } while loop && !token.cancelled
            Task { @MainActor in self?.finished(token) }
        }
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Swap the running pattern (takes effect at the next loop pass).
    func update(_ pattern: HapticPattern) { box?.value = pattern }

    func stop() {
        token?.cancel()
        token = nil
        isPlaying = false
        playhead = nil
        playingName = nil
    }

    private func setPlayhead(_ i: Int, _ t: RunToken) {
        if token === t { playhead = i }
    }

    /// Called when a run ends on its own; ignored if a newer run has started.
    private func finished(_ t: RunToken) {
        guard token === t else { return }
        token = nil
        isPlaying = false
        playhead = nil
        playingName = nil
    }

    /// One-shot raw tap (unscaled), used by the actuation-ID tester.
    func tap(_ id: Int32) { actuator.actuate(id) }
}
