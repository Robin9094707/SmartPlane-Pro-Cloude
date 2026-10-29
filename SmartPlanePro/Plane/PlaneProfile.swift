import CoreBluetooth
import Foundation

/// Describes where a plane expects its motor / rudder values.
///
/// The built-in profiles come from TobyRich's own open-source SmartLink stack
/// (github.com/TobyRich/app-smartplane-android, `res/raw/services.plist`, and
/// lib-smartlink-android `BLESmartplaneService.java`):
///
/// * engine  – UInt8, 0 … 254, written *without response*
/// * rudder  – Int8, −126 … +126 (0 = centre, + = right), written *without response*
/// * charge status – UInt8, 0 = not charging, read periodically
/// * Battery Service 0x180F / 0x2A19 – percent, notify
/// * TI OAD service 0xFFC0 – firmware image identification
struct PlaneProfile: Identifiable, Hashable, Codable {
    enum ValueFormat: String, Codable, CaseIterable, Identifiable {
        case uint8 = "UInt8"
        case int8 = "Int8"
        var id: String { rawValue }
    }

    var id: String
    var name: String
    var detail: String
    var service: String?
    var engine: String
    var rudder: String
    var temperature: String?
    var chargeStatus: String?
    var engineMax: Int = 254
    var rudderMax: Int = 126
    /// For custom mappings: how rudder values are encoded.
    var rudderFormat: ValueFormat = .int8
    /// For custom mappings on UInt8 rudders: value representing centre (usually 127/128).
    var rudderCenter: Int = 0

    static let smartPlane = PlaneProfile(
        id: "smartplane",
        name: "TobyRich SmartPlane / PRO",
        detail: "Original SmartLink-Protokoll (Service 75B64E51-F171)",
        service: "75B64E51-F171-4ED1-921A-476090D80BA7",
        engine: "75B64E51-0010-4ED1-921A-476090D80BA7",
        rudder: "75B64E51-0021-4ED1-921A-476090D80BA7",
        temperature: "75B64E51-0030-4ED1-921A-476090D80BA7",
        chargeStatus: "75B64E51-0040-4ED1-921A-476090D80BA7"
    )

    static let smartPlanePrototype = PlaneProfile(
        id: "sml1test",
        name: "SmartPlane Prototyp (SML1)",
        detail: "Frühe Firmware (Service 75B64E51-F181)",
        service: "75B64E51-F181-4ED1-921A-476090D80BA7",
        engine: "75B64E51-F184-4ED1-921A-476090D80BA7",
        rudder: "75B64E51-F185-4ED1-921A-476090D80BA7"
    )

    static let powerUp = PlaneProfile(
        id: "powerup",
        name: "PowerUp 3.0 / SmartLink-kompatibel",
        detail: "Gleiche Firmware-Familie (Service 86C3810E-F171)",
        service: "86C3810E-F171-40D9-A117-26B300768CD6",
        engine: "86C3810E-0010-40D9-A117-26B300768CD6",
        rudder: "86C3810E-0021-40D9-A117-26B300768CD6",
        temperature: "86C3810E-0030-40D9-A117-26B300768CD6",
        chargeStatus: "86C3810E-0040-40D9-A117-26B300768CD6"
    )

    static let builtIn: [PlaneProfile] = [.smartPlane, .smartPlanePrototype, .powerUp]

    static let builtInServiceUUIDs: Set<CBUUID> = Set(builtIn.compactMap { $0.service.map(CBUUID.init(string:)) })

    var isCustom: Bool { id.hasPrefix("custom") }

    func encodeEngine(_ normalized: Double) -> Data {
        let value = Int((normalized.clamped(to: 0...1) * Double(engineMax)).rounded())
        return Data([UInt8(value.clamped(to: 0...255))])
    }

    func encodeRudder(_ normalized: Double) -> Data {
        let scaled = Int((normalized.clamped(to: -1...1) * Double(rudderMax)).rounded())
        switch rudderFormat {
        case .int8:
            let value = scaled.clamped(to: -128...127)
            return Data([UInt8(bitPattern: Int8(value))])
        case .uint8:
            return Data([UInt8((rudderCenter + scaled).clamped(to: 0...255))])
        }
    }
}

/// A profile bound to actual characteristics of a connected peripheral.
struct ResolvedPlane {
    let profile: PlaneProfile
    let engine: CharacteristicNode
    let rudder: CharacteristicNode
    let temperature: CharacteristicNode?
    let chargeStatus: CharacteristicNode?
    let battery: CharacteristicNode?
    let oadIdentify: CharacteristicNode?
    let oadBlock: CharacteristicNode?
    let detection: String
}

enum PlaneResolver {
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")
    static let oadService = CBUUID(string: "F000FFC0-0451-4000-B000-000000000000")
    static let oadIdentify = CBUUID(string: "F000FFC1-0451-4000-B000-000000000000")
    static let oadBlock = CBUUID(string: "F000FFC2-0451-4000-B000-000000000000")

    /// Tries (1) a stored custom mapping, (2) the built-in profiles, (3) a structural
    /// heuristic for unknown SmartLink variants (`xxxxxxxx-F171-…` service with
    /// `-0010-` / `-0021-` characteristics).
    static func resolve(session: PeripheralSession, custom: PlaneProfile?, preferred: String) -> ResolvedPlane? {
        var candidates: [PlaneProfile] = []
        if let custom { candidates.append(custom) }
        if preferred != "auto", let forced = PlaneProfile.builtIn.first(where: { $0.id == preferred }) {
            candidates.append(forced)
        }
        candidates.append(contentsOf: PlaneProfile.builtIn)

        for profile in candidates {
            // Custom mappings may be half finished (only motor or only rudder assigned).
            guard isValidUUID(profile.engine), isValidUUID(profile.rudder),
                  profile.service.map(isValidUUID) ?? true else { continue }
            let serviceUUID = profile.service.map(CBUUID.init(string:))
            if let serviceUUID, session.service(serviceUUID) == nil { continue }
            guard let engine = session.characteristic(CBUUID(string: profile.engine), in: serviceUUID),
                  let rudder = session.characteristic(CBUUID(string: profile.rudder), in: serviceUUID),
                  engine.isWritable, rudder.isWritable else { continue }
            let how = profile.isCustom ? "eigene Zuordnung" : "bekanntes Profil"
            return bind(profile, engine: engine, rudder: rudder, session: session, detection: how)
        }

        if let heuristic = heuristicProfile(session: session) {
            return heuristic
        }
        return nil
    }

    /// `CBUUID(string:)` throws an Objective-C exception on malformed input, so validate first.
    static func isValidUUID(_ string: String) -> Bool {
        let hex = string.filter { $0 != "-" }
        guard [4, 8, 32].contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return false }
        return hex.count != 32 || UUID(uuidString: string) != nil
    }

    private static func heuristicProfile(session: PeripheralSession) -> ResolvedPlane? {
        for service in session.services {
            let uuid = service.uuid.uuidString.uppercased()
            guard uuid.count == 36 else { continue }
            let parts = uuid.split(separator: "-")
            guard parts.count == 5 else { continue }
            func sibling(_ middle: String) -> CharacteristicNode? {
                let target = "\(parts[0])-\(middle)-\(parts[2])-\(parts[3])-\(parts[4])"
                return service.characteristics.first { $0.uuid.uuidString.uppercased() == target }
            }
            guard let engine = sibling("0010"), let rudder = sibling("0021") ?? sibling("0020"),
                  engine.isWritable, rudder.isWritable else { continue }
            let profile = PlaneProfile(
                id: "heuristic-\(parts[0])",
                name: "SmartLink-Variante (automatisch erkannt)",
                detail: "Service \(uuid)",
                service: uuid,
                engine: engine.uuid.uuidString,
                rudder: rudder.uuid.uuidString,
                temperature: sibling("0030")?.uuid.uuidString,
                chargeStatus: sibling("0040")?.uuid.uuidString
            )
            return bind(profile, engine: engine, rudder: rudder, session: session, detection: "Heuristik (F171-Muster)")
        }
        return nil
    }

    private static func bind(_ profile: PlaneProfile, engine: CharacteristicNode, rudder: CharacteristicNode,
                             session: PeripheralSession, detection: String) -> ResolvedPlane {
        let serviceUUID = profile.service.map(CBUUID.init(string:))
        return ResolvedPlane(
            profile: profile,
            engine: engine,
            rudder: rudder,
            temperature: profile.temperature.flatMap { session.characteristic(CBUUID(string: $0), in: serviceUUID) },
            chargeStatus: profile.chargeStatus.flatMap { session.characteristic(CBUUID(string: $0), in: serviceUUID) },
            battery: session.characteristic(batteryLevel, in: batteryService),
            oadIdentify: session.characteristic(oadIdentify, in: oadService),
            oadBlock: session.characteristic(oadBlock, in: oadService),
            detection: detection
        )
    }
}
