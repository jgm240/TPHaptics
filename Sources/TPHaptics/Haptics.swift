import Foundation

/// Fire-and-forget single taps for features that react to events (typing,
/// scrolling, audio beats…). Runs off the caller's thread because one actuation
/// blocks for ~5 ms, and drops taps when the actuator is already backed up.
enum Haptics {
    private static let queue = DispatchQueue(label: "tphaptics.tick", qos: .userInteractive)
    private static let lock = NSLock()
    private static var pending = 0

    /// `id` is an authored actuation ID (1…6); the master Strength slider scales it.
    static func tick(_ id: Int32) {
        lock.lock()
        if pending >= 2 { lock.unlock(); return }
        pending += 1
        lock.unlock()
        queue.async {
            if let scaled = TrackpadActuator.shared.scaledID(authored: id, peak: id, normalize: false) {
                TrackpadActuator.shared.actuate(scaled)
            }
            lock.lock(); pending -= 1; lock.unlock()
        }
    }
}
