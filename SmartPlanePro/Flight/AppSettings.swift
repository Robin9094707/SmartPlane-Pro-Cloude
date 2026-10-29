import Foundation
import Observation

enum ControlMode: String, CaseIterable, Identifiable, Codable {
    case tilt
    case joystick

    var id: String { rawValue }
    var label: String {
        switch self {
        case .tilt: return "Neigen"
        case .joystick: return "Joystick"
        }
    }
    var symbol: String {
        switch self {
        case .tilt: return "iphone.gen3.radiowaves.left.and.right"
        case .joystick: return "gamecontroller"
        }
    }
}

/// User preferences, persisted in UserDefaults.
@Observable
final class AppSettings {
    private static let defaults = UserDefaults.standard

    var controlMode: ControlMode = .tilt { didSet { save("controlMode", controlMode.rawValue) } }
    var tiltMaxAngle: Double = 45 { didSet { save("tiltMaxAngle", tiltMaxAngle) } }
    var tiltOffset: Double = 0 { didSet { save("tiltOffset", tiltOffset) } }
    var deadzone: Double = 0.05 { didSet { save("deadzone", deadzone) } }
    var expo: Double = 0.25 { didSet { save("expo", expo) } }
    var rudderTrim: Double = 0 { didSet { save("rudderTrim", rudderTrim) } }
    var rudderRate: Double = 1.0 { didSet { save("rudderRate", rudderRate) } }
    var rudderReversed = false { didSet { save("rudderReversed", rudderReversed) } }
    var flightAssist = true { didSet { save("flightAssist", flightAssist) } }
    var leftRudderScale: Double = 0.75 { didSet { save("leftRudderScale", leftRudderScale) } }
    var turnBoost = true { didSet { save("turnBoost", turnBoost) } }
    var maxThrottle: Double = 1.0 { didSet { save("maxThrottle", maxThrottle) } }
    var throttleRampSeconds: Double = 0.25 { didSet { save("throttleRampSeconds", throttleRampSeconds) } }
    var sendRateHz: Double = 25 { didSet { save("sendRateHz", sendRateHz) } }
    var keepAlive = true { didSet { save("keepAlive", keepAlive) } }
    var haptics = true { didSet { save("haptics", haptics) } }
    var autoConnect = true { didSet { save("autoConnect", autoConnect) } }
    var autoConnectRSSI: Double = -75 { didSet { save("autoConnectRSSI", autoConnectRSSI) } }
    var preferredProfile = "auto" { didSet { save("preferredProfile", preferredProfile) } }
    var batteryCompensation = true { didSet { save("batteryCompensation", batteryCompensation) } }
    var labAutoReadAll = true { didSet { save("labAutoReadAll", labAutoReadAll) } }
    var requireZeroThrottleToArm = true { didSet { save("requireZeroThrottleToArm", requireZeroThrottleToArm) } }
    var gamepadEnabled = true { didSet { save("gamepadEnabled", gamepadEnabled) } }
    var lastPlaneID: String? = nil { didSet { save("lastPlaneID", lastPlaneID) } }
    var hasSeenOnboarding = false { didSet { save("hasSeenOnboarding", hasSeenOnboarding) } }

    init() {
        let d = Self.defaults
        if let raw = d.string(forKey: "controlMode"), let mode = ControlMode(rawValue: raw) { controlMode = mode }
        tiltMaxAngle = d.double(forKey: "tiltMaxAngle", default: tiltMaxAngle)
        tiltOffset = d.double(forKey: "tiltOffset", default: tiltOffset)
        deadzone = d.double(forKey: "deadzone", default: deadzone)
        expo = d.double(forKey: "expo", default: expo)
        rudderTrim = d.double(forKey: "rudderTrim", default: rudderTrim)
        rudderRate = d.double(forKey: "rudderRate", default: rudderRate)
        rudderReversed = d.bool(forKey: "rudderReversed", default: rudderReversed)
        flightAssist = d.bool(forKey: "flightAssist", default: flightAssist)
        leftRudderScale = d.double(forKey: "leftRudderScale", default: leftRudderScale)
        turnBoost = d.bool(forKey: "turnBoost", default: turnBoost)
        maxThrottle = d.double(forKey: "maxThrottle", default: maxThrottle)
        throttleRampSeconds = d.double(forKey: "throttleRampSeconds", default: throttleRampSeconds)
        sendRateHz = d.double(forKey: "sendRateHz", default: sendRateHz)
        keepAlive = d.bool(forKey: "keepAlive", default: keepAlive)
        haptics = d.bool(forKey: "haptics", default: haptics)
        autoConnect = d.bool(forKey: "autoConnect", default: autoConnect)
        autoConnectRSSI = d.double(forKey: "autoConnectRSSI", default: autoConnectRSSI)
        preferredProfile = d.string(forKey: "preferredProfile") ?? preferredProfile
        batteryCompensation = d.bool(forKey: "batteryCompensation", default: batteryCompensation)
        labAutoReadAll = d.bool(forKey: "labAutoReadAll", default: labAutoReadAll)
        requireZeroThrottleToArm = d.bool(forKey: "requireZeroThrottleToArm", default: requireZeroThrottleToArm)
        gamepadEnabled = d.bool(forKey: "gamepadEnabled", default: gamepadEnabled)
        lastPlaneID = d.string(forKey: "lastPlaneID")
        hasSeenOnboarding = d.bool(forKey: "hasSeenOnboarding", default: false)
    }

    func resetFlightTuning() {
        tiltMaxAngle = 45
        deadzone = 0.05
        expo = 0.25
        rudderTrim = 0
        rudderRate = 1
        rudderReversed = false
        flightAssist = true
        leftRudderScale = 0.75
        turnBoost = true
        maxThrottle = 1
        throttleRampSeconds = 0.25
        sendRateHz = 25
    }

    private func save(_ key: String, _ value: Any?) {
        if let value { Self.defaults.set(value, forKey: key) } else { Self.defaults.removeObject(forKey: key) }
    }

    // MARK: - Custom protocol mappings (per peripheral)

    func customProfile(for peripheralID: UUID) -> PlaneProfile? {
        guard let data = Self.defaults.data(forKey: "custom-\(peripheralID.uuidString)") else { return nil }
        return try? JSONDecoder().decode(PlaneProfile.self, from: data)
    }

    func setCustomProfile(_ profile: PlaneProfile?, for peripheralID: UUID) {
        let key = "custom-\(peripheralID.uuidString)"
        if let profile, let data = try? JSONEncoder().encode(profile) {
            Self.defaults.set(data, forKey: key)
        } else {
            Self.defaults.removeObject(forKey: key)
        }
    }
}

private extension UserDefaults {
    func double(forKey key: String, default fallback: Double) -> Double {
        object(forKey: key) == nil ? fallback : double(forKey: key)
    }

    func bool(forKey key: String, default fallback: Bool) -> Bool {
        object(forKey: key) == nil ? fallback : bool(forKey: key)
    }
}
