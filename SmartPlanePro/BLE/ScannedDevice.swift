import CoreBluetooth
import Foundation

/// Parsed contents of a BLE advertisement packet (+ scan response).
struct AdvertisementInfo {
    var localName: String?
    var manufacturerData: Data?
    var serviceUUIDs: [CBUUID] = []
    var overflowServiceUUIDs: [CBUUID] = []
    var solicitedServiceUUIDs: [CBUUID] = []
    var serviceData: [CBUUID: Data] = [:]
    var txPowerLevel: Int?
    var isConnectable: Bool?

    init() {}

    init(_ raw: [String: Any]) {
        localName = raw[CBAdvertisementDataLocalNameKey] as? String
        manufacturerData = raw[CBAdvertisementDataManufacturerDataKey] as? Data
        serviceUUIDs = raw[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        overflowServiceUUIDs = raw[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? []
        solicitedServiceUUIDs = raw[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID] ?? []
        serviceData = raw[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:]
        txPowerLevel = (raw[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue
        isConnectable = (raw[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
    }

    /// Advertisements arrive split over ADV_IND and SCAN_RSP, so merge instead of replacing.
    mutating func merge(_ other: AdvertisementInfo) {
        if let name = other.localName { localName = name }
        if let data = other.manufacturerData { manufacturerData = data }
        if !other.serviceUUIDs.isEmpty { serviceUUIDs = other.serviceUUIDs }
        if !other.overflowServiceUUIDs.isEmpty { overflowServiceUUIDs = other.overflowServiceUUIDs }
        if !other.solicitedServiceUUIDs.isEmpty { solicitedServiceUUIDs = other.solicitedServiceUUIDs }
        serviceData.merge(other.serviceData) { _, new in new }
        if let power = other.txPowerLevel { txPowerLevel = power }
        if let connectable = other.isConnectable { isConnectable = connectable }
    }

    var companyID: UInt16? { manufacturerData?.uint16LE(at: 0) }

    var companyName: String? {
        guard let id = companyID else { return nil }
        return UUIDCatalog.companies[id] ?? String(format: "Firma 0x%04X", id)
    }

    var allServiceUUIDs: [CBUUID] { serviceUUIDs + overflowServiceUUIDs + Array(serviceData.keys) }
}

struct ScannedDevice: Identifiable {
    enum PlaneMatch: Int, Comparable {
        case none = 0, likely = 1, certain = 2

        static func < (lhs: PlaneMatch, rhs: PlaneMatch) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let id: UUID
    let peripheral: CBPeripheral
    var advertisement: AdvertisementInfo
    var rssi: Int
    var rssiHistory: [Int]
    var firstSeen: Date
    var lastSeen: Date
    var packetCount: Int

    var name: String? { advertisement.localName ?? peripheral.name }
    var displayName: String { name ?? "Unbenanntes Gerät" }

    var planeMatch: PlaneMatch {
        if advertisement.allServiceUUIDs.contains(where: { PlaneProfile.builtInServiceUUIDs.contains($0) }) {
            return .certain
        }
        let lowered = (name ?? "").lowercased()
        let hints = ["smartplane", "smart plane", "tobyrich", "toby", "vegas", "powerup", "sml", "plane", "sp pro", "sppro"]
        if hints.contains(where: { lowered.contains($0) }) { return .likely }
        return .none
    }

    /// Rough distance estimate (log-distance path loss, n = 2.2).
    var estimatedDistance: Double? {
        guard rssi < 0 else { return nil }
        let measuredPower = Double(advertisement.txPowerLevel.map { $0 - 41 } ?? -59)
        return pow(10, (measuredPower - Double(rssi)) / (10 * 2.2))
    }

    var smoothedRSSI: Int {
        let recent = rssiHistory.suffix(5)
        guard !recent.isEmpty else { return rssi }
        return recent.reduce(0, +) / recent.count
    }
}
