import AppKit
import Darwin

/// Drives the trackpad's Taptic Engine directly through the private
/// `MultitouchSupport.framework` `MTActuator*` functions. Unlike
/// `NSHapticFeedbackManager`, this works with no finger on the trackpad.
///
/// The symbols are resolved at runtime with `dlsym`, so nothing private is
/// linked at build time and a missing symbol degrades gracefully.
final class TrackpadActuator: @unchecked Sendable {
    static let shared = TrackpadActuator()

    /// Actuation IDs ordered weakest → strongest. The last entry is treated
    /// as the "Max Power of Actuator". IDs 15 and 16 were tried and are silent
    /// on this trackpad, so 6 is the top. Use the Test tab to probe 7…14.
    static let ladder: [Int32] = [1, 2, 3, 4, 5, 6]

    // MARK: C function signatures (reverse-engineered)
    private typealias DeviceCreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias DeviceIsBuiltIn  = @convention(c) (UnsafeRawPointer) -> Bool
    private typealias DeviceGetID      = @convention(c) (UnsafeRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
    private typealias ActuatorCreate   = @convention(c) (UInt64) -> UnsafeMutableRawPointer?
    private typealias ActuatorOpen     = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias ActuatorClose    = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias ActuatorActuate  = @convention(c) (UnsafeMutableRawPointer, Int32, UInt32, Float, Float) -> Int32
    private typealias DeviceGetBool    = @convention(c) (UnsafeRawPointer) -> Bool
    private typealias DeviceSetBool    = @convention(c) (UnsafeRawPointer, Bool) -> Int32
    private typealias RecacheAll       = @convention(c) () -> Void

    private let lock = NSLock()
    private var actuator: UnsafeMutableRawPointer?
    private var fnActuate: ActuatorActuate?
    private var fnClose: ActuatorClose?

    // Device-level (system-wide) Force Click switch; kept alive for the app's lifetime.
    private var deviceList: CFArray?
    private var forceDevice: UnsafeRawPointer?
    private var fnGetForce: DeviceGetBool?
    private var fnSetForce: DeviceSetBool?
    private var fnRecache: RecacheAll?
    private var _strength: Double = 1.0

    /// True when the private actuator opened and can fire without a touch.
    private(set) var isDirect = false
    /// Human-readable description of how haptics are being driven.
    private(set) var status = "Not initialised"
    private(set) var lastResult: Int32 = 0
    /// Total actuations fired (used by the self-test).
    private(set) var actuationCount = 0

    private init() { setup() }

    // MARK: Strength

    /// Master strength 0…1. 0 = silent, 1 = Max Power of Actuator.
    var strength: Double {
        get { lock.lock(); defer { lock.unlock() }; return _strength }
        set { lock.lock(); _strength = min(1, max(0, newValue)); lock.unlock() }
    }

    private static func rank(of id: Int32) -> Int {
        var best = 0
        for (i, v) in ladder.enumerated() where abs(v - id) < abs(ladder[best] - id) { best = i }
        return best
    }

    /// Scales an authored actuation ID by the master strength.
    /// With `normalize`, the pattern's strongest tap (`peak`) plays at the master
    /// level and softer taps stay proportionally softer. Returns nil when muted.
    func scaledID(authored: Int32, peak: Int32, normalize: Bool) -> Int32? {
        let s = strength
        if s <= 0 { return nil }
        let top = Self.ladder.count - 1
        let peakRank = normalize ? Self.rank(of: peak) : top
        let ratio = peakRank == 0 ? 1.0 : Double(Self.rank(of: authored)) / Double(peakRank)
        let r = Int((s * Double(top) * min(1, ratio)).rounded())
        return Self.ladder[min(top, max(0, r))]
    }

    // MARK: Setup

    private func setup() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let h = dlopen(path, RTLD_NOW) else {
            status = "MultitouchSupport.framework could not be loaded — using public API (finger required)"
            return
        }
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let createList = sym("MTDeviceCreateList", DeviceCreateList.self),
              let create = sym("MTActuatorCreateFromDeviceID", ActuatorCreate.self),
              let open = sym("MTActuatorOpen", ActuatorOpen.self),
              let actuate = sym("MTActuatorActuate", ActuatorActuate.self)
        else {
            status = "MTActuator symbols not found on this macOS — using public API (finger required)"
            return
        }
        let isBuiltIn = sym("MTDeviceIsBuiltIn", DeviceIsBuiltIn.self)
        let getID = sym("MTDeviceGetDeviceID", DeviceGetID.self)

        // Collect candidate device IDs, built-in trackpad first.
        var candidates: [(id: UInt64, builtIn: Bool)] = []
        if let list = createList()?.takeRetainedValue(), let getID {
            deviceList = list
            for i in 0..<CFArrayGetCount(list) {
                guard let dev = CFArrayGetValueAtIndex(list, i) else { continue }
                var id: UInt64 = 0
                if getID(dev, &id) == 0 {
                    let builtIn = isBuiltIn?(dev) ?? false
                    candidates.append((id, builtIn))
                    if forceDevice == nil || builtIn { forceDevice = dev }
                }
            }
        }
        fnGetForce = sym("MTDeviceGetSystemForceResponseEnabled", DeviceGetBool.self)
        fnSetForce = sym("MTDeviceSetSystemForceResponseEnabled", DeviceSetBool.self)
        fnRecache = sym("MTDeviceForcePropertiesRecacheForAll", RecacheAll.self)
        candidates.sort { $0.builtIn && !$1.builtIn }

        var lastErr: Int32 = 0
        for c in candidates {
            guard let act = create(c.id) else { continue }
            let r = open(act)
            if r == 0 {
                actuator = act
                fnActuate = actuate
                fnClose = sym("MTActuatorClose", ActuatorClose.self)
                isDirect = true
                status = "Direct actuator open (\(c.builtIn ? "built-in" : "external") trackpad) — no touch needed"
                return
            }
            lastErr = r
        }
        status = candidates.isEmpty
            ? "No multitouch devices found — using public API (finger required)"
            : "MTActuatorOpen failed (0x\(String(UInt32(bitPattern: lastErr), radix: 16))) — using public API (finger required)"
    }

    // MARK: Actuation

    /// Fire one raw actuation. IDs 1…6 produce clicks here; 15/16 are accepted but silent.
    func actuate(_ id: Int32) {
        lock.lock(); defer { lock.unlock() }
        actuationCount += 1
        if isDirect, let actuator, let fnActuate {
            lastResult = fnActuate(actuator, id, 0, 0.0, 0.0)
        } else {
            DispatchQueue.main.async {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
        }
    }

    // MARK: Force Click (system-wide)

    var canToggleForceClick: Bool { forceDevice != nil && fnSetForce != nil && fnGetForce != nil }

    /// Whether Force Click (and its haptic taps) is enabled; nil if unavailable.
    var forceClickEnabled: Bool? {
        guard let forceDevice, let fnGetForce else { return nil }
        return fnGetForce(forceDevice)
    }

    /// Applies live and system-wide. Returns the raw status (0 = success, -1 = unavailable).
    @discardableResult
    func setForceClickEnabled(_ enabled: Bool) -> Int32 {
        guard let forceDevice, let fnSetForce else { return -1 }
        return fnSetForce(forceDevice, enabled)
    }

    /// Asks MultitouchSupport to re-read trackpad preferences (best effort).
    func recacheProperties() { fnRecache?() }

    func close() {
        lock.lock(); defer { lock.unlock() }
        if let actuator, let fnClose { _ = fnClose(actuator) }
        actuator = nil
        isDirect = false
    }
}
