import CoreBluetooth
import Foundation
import Observation

/// One connected (or connecting) peripheral. Performs a full GATT discovery
/// (services → characteristics → descriptors) and offers read / write / notify.
/// Used by both the flight cockpit (PlaneLink) and the Bluetooth Lab.
@Observable
final class PeripheralSession: NSObject, CBPeripheralDelegate, Identifiable {
    enum State: Equatable {
        case disconnected
        case connecting
        case discovering
        case ready
        case failed(String)

        var label: String {
            switch self {
            case .disconnected: return "Getrennt"
            case .connecting: return "Verbinde …"
            case .discovering: return "Lese GATT-Tabelle …"
            case .ready: return "Verbunden"
            case .failed(let reason): return "Fehler: \(reason)"
            }
        }

        var isActive: Bool {
            switch self {
            case .connecting, .discovering, .ready: return true
            default: return false
            }
        }
    }

    let id: UUID
    let peripheral: CBPeripheral
    private(set) var state: State = .disconnected
    private(set) var services: [ServiceNode] = []
    private(set) var rssi: Int?
    private(set) var connectedAt: Date?
    private(set) var discoveryDuration: TimeInterval?
    private(set) var name: String?
    /// Read every readable characteristic right after discovery (Lab mode).
    var autoReadAll = true

    @ObservationIgnored var onReady: ((PeripheralSession) -> Void)?
    @ObservationIgnored var onDisconnect: ((PeripheralSession, Error?) -> Void)?
    @ObservationIgnored var onValueUpdate: ((CharacteristicNode) -> Void)?
    @ObservationIgnored var onReadyToSendWithoutResponse: (() -> Void)?

    @ObservationIgnored private var characteristicNodes: [ObjectIdentifier: CharacteristicNode] = [:]
    @ObservationIgnored private var descriptorNodes: [ObjectIdentifier: DescriptorNode] = [:]
    @ObservationIgnored private var pendingDiscoveries = 0
    @ObservationIgnored private var pendingReads: Set<ObjectIdentifier> = []
    @ObservationIgnored private var discoveryStart: Date?
    @ObservationIgnored private var rssiTimer: Timer?

    init(peripheral: CBPeripheral) {
        self.id = peripheral.identifier
        self.peripheral = peripheral
        self.name = peripheral.name
        super.init()
        peripheral.delegate = self
    }

    deinit { rssiTimer?.invalidate() }

    // MARK: - Lifecycle (driven by BLECentral)

    func willConnect() {
        state = .connecting
        services = []
        characteristicNodes = [:]
        descriptorNodes = [:]
    }

    func didConnect() {
        connectedAt = Date()
        peripheral.delegate = self
        startDiscovery()
        rssiTimer?.invalidate()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.peripheral.state == .connected else { return }
            self.peripheral.readRSSI()
        }
    }

    func didFailToConnect(_ error: Error?) {
        state = .failed(error?.localizedDescription ?? "Verbindung fehlgeschlagen")
        rssiTimer?.invalidate()
    }

    func didDisconnect(_ error: Error?) {
        rssiTimer?.invalidate()
        rssiTimer = nil
        connectedAt = nil
        if let error {
            state = .failed(error.localizedDescription)
        } else {
            state = .disconnected
        }
        for node in characteristicNodes.values { node.isNotifying = false }
        onDisconnect?(self, error)
    }

    func startDiscovery() {
        state = .discovering
        services = []
        characteristicNodes = [:]
        descriptorNodes = [:]
        pendingDiscoveries = 1
        discoveryStart = Date()
        appLog(.info, "GATT", "\(displayName): Starte Service-Discovery")
        peripheral.discoverServices(nil)
    }

    var displayName: String { name ?? peripheral.name ?? peripheral.identifier.uuidString.prefix(8).description }

    var maxWriteWithoutResponse: Int { peripheral.maximumWriteValueLength(for: .withoutResponse) }
    var maxWriteWithResponse: Int { peripheral.maximumWriteValueLength(for: .withResponse) }

    var allCharacteristics: [CharacteristicNode] { services.flatMap(\.characteristics) }

    // MARK: - Lookup

    func service(_ uuid: CBUUID) -> ServiceNode? {
        services.first { $0.uuid == uuid }
    }

    func characteristic(_ uuid: CBUUID, in serviceUUID: CBUUID? = nil) -> CharacteristicNode? {
        let candidates = serviceUUID.map { uuid in services.filter { $0.uuid == uuid } } ?? services
        for service in candidates {
            if let node = service.characteristics.first(where: { $0.uuid == uuid }) { return node }
        }
        return nil
    }

    // MARK: - Operations

    func read(_ node: CharacteristicNode) {
        guard peripheral.state == .connected, node.canRead else { return }
        pendingReads.insert(ObjectIdentifier(node.characteristic))
        peripheral.readValue(for: node.characteristic)
    }

    func readAll() {
        for node in allCharacteristics where node.canRead { read(node) }
    }

    @discardableResult
    func write(_ data: Data, to node: CharacteristicNode, withResponse: Bool? = nil, quiet: Bool = false) -> Bool {
        guard peripheral.state == .connected, node.isWritable else { return false }
        var type: CBCharacteristicWriteType = node.canWriteWithoutResponse ? .withoutResponse : .withResponse
        if let withResponse {
            type = withResponse ? .withResponse : .withoutResponse
        }
        // Never ask CoreBluetooth for a write type the characteristic does not declare.
        if type == .withResponse && !node.canWrite { type = .withoutResponse }
        if type == .withoutResponse && !node.canWriteWithoutResponse { type = .withResponse }
        if type == .withoutResponse && !peripheral.canSendWriteWithoutResponse {
            return false
        }
        peripheral.writeValue(data, for: node.characteristic, type: type)
        node.writeCount += 1
        if !quiet || EventLog.shared.logControlTraffic {
            appLog(.tx, "GATT", "\(node.name) ← \(data.hexString) (\(type == .withResponse ? "mit Antwort" : "ohne Antwort"))")
        }
        return true
    }

    func setNotify(_ enabled: Bool, for node: CharacteristicNode) {
        guard peripheral.state == .connected, node.canNotify else { return }
        peripheral.setNotifyValue(enabled, for: node.characteristic)
    }

    func subscribeAll() {
        for node in allCharacteristics where node.canNotify && !node.isNotifying {
            setNotify(true, for: node)
        }
    }

    // MARK: - CBPeripheralDelegate

    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        name = peripheral.name
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        appLog(.warning, "GATT", "Peripherie hat Services geändert – erneute Discovery")
        startDiscovery()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        pendingDiscoveries -= 1
        if let error {
            appLog(.error, "GATT", "Service-Discovery: \(error.localizedDescription)")
        }
        for service in peripheral.services ?? [] {
            let node = ServiceNode(service: service)
            services.append(node)
            pendingDiscoveries += 1
            peripheral.discoverCharacteristics(nil, for: service)
            pendingDiscoveries += 1
            peripheral.discoverIncludedServices(nil, for: service)
            appLog(.info, "GATT", "Service \(service.uuid.uuidString) – \(UUIDCatalog.displayName(for: service.uuid))")
        }
        finishDiscoveryIfDone()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: Error?) {
        pendingDiscoveries -= 1
        if let node = services.first(where: { $0.service === service }) {
            node.includedServices = (service.includedServices ?? []).map(\.uuid)
        }
        finishDiscoveryIfDone()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        pendingDiscoveries -= 1
        if let error {
            appLog(.error, "GATT", "Characteristics für \(service.uuid): \(error.localizedDescription)")
        }
        guard let serviceNode = services.first(where: { $0.service === service }) else {
            finishDiscoveryIfDone()
            return
        }
        for characteristic in service.characteristics ?? [] {
            let node = CharacteristicNode(characteristic: characteristic, service: serviceNode)
            serviceNode.characteristics.append(node)
            characteristicNodes[ObjectIdentifier(characteristic)] = node
            pendingDiscoveries += 1
            peripheral.discoverDescriptors(for: characteristic)
        }
        finishDiscoveryIfDone()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        pendingDiscoveries -= 1
        if let node = characteristicNodes[ObjectIdentifier(characteristic)] {
            node.descriptors = (characteristic.descriptors ?? []).map { descriptor in
                let descriptorNode = DescriptorNode(descriptor: descriptor)
                descriptorNodes[ObjectIdentifier(descriptor)] = descriptorNode
                // User description / presentation format are cheap and very informative.
                let interesting = ["2901", "2904", "2900"]
                if interesting.contains(descriptor.uuid.uuidString.uppercased()) {
                    peripheral.readValue(for: descriptor)
                }
                return descriptorNode
            }
        }
        finishDiscoveryIfDone()
    }

    private func finishDiscoveryIfDone() {
        guard pendingDiscoveries <= 0, state == .discovering else { return }
        state = .ready
        discoveryDuration = discoveryStart.map { Date().timeIntervalSince($0) }
        let characteristicCount = allCharacteristics.count
        appLog(.info, "GATT", "\(displayName): \(services.count) Services, \(characteristicCount) Characteristics gefunden")
        if autoReadAll { readAll() }
        onReady?(self)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let node = characteristicNodes[ObjectIdentifier(characteristic)] else { return }
        let key = ObjectIdentifier(characteristic)
        let wasRead = pendingReads.remove(key) != nil
        if let error {
            node.lastError = error.localizedDescription
            appLog(.error, "GATT", "Lesen \(node.name): \(error.localizedDescription)")
            return
        }
        let data = characteristic.value ?? Data()
        node.record(data, notification: !wasRead)
        if !wasRead || !node.isNotifying {
            appLog(.rx, "GATT", "\(node.name) → \(data.isEmpty ? "(leer)" : data.hexString)\(wasRead ? "" : " [notify]")")
        }
        onValueUpdate?(node)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let node = characteristicNodes[ObjectIdentifier(characteristic)] else { return }
        if let error {
            node.lastError = error.localizedDescription
            appLog(.error, "GATT", "Schreiben \(node.name): \(error.localizedDescription)")
        } else {
            appLog(.debug, "GATT", "Schreiben bestätigt: \(node.name)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard let node = characteristicNodes[ObjectIdentifier(characteristic)] else { return }
        if let error {
            node.lastError = error.localizedDescription
            appLog(.error, "GATT", "Notify \(node.name): \(error.localizedDescription)")
        }
        node.isNotifying = characteristic.isNotifying
        appLog(.info, "GATT", "Notify \(node.name): \(characteristic.isNotifying ? "aktiv" : "aus")")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        guard let node = descriptorNodes[ObjectIdentifier(descriptor)] else { return }
        if let error {
            node.value = "Fehler: \(error.localizedDescription)"
            return
        }
        node.value = Self.describe(descriptorValue: descriptor.value, uuid: descriptor.uuid)
        if descriptor.uuid.uuidString.uppercased() == "2901", let text = descriptor.value as? String,
           let characteristic = descriptor.characteristic,
           let owner = characteristicNodes[ObjectIdentifier(characteristic)] {
            owner.userDescription = text
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        rssi = RSSI.intValue
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        onReadyToSendWithoutResponse?()
    }

    // MARK: - Helpers

    static func describe(descriptorValue value: Any?, uuid: CBUUID) -> String {
        switch value {
        case let text as String:
            return "\"\(text)\""
        case let number as NSNumber:
            if uuid.uuidString.uppercased() == "2902" {
                let flags = number.uint16Value
                var parts: [String] = []
                if flags & 0x1 != 0 { parts.append("Notify") }
                if flags & 0x2 != 0 { parts.append("Indicate") }
                return parts.isEmpty ? "aus (0x0000)" : parts.joined(separator: " + ")
            }
            return number.stringValue
        case let data as Data:
            if uuid.uuidString.uppercased() == "2904", data.count >= 7 {
                return PresentationFormat(data: data).description
            }
            return data.hexString
        case nil:
            return "–"
        default:
            return String(describing: value!)
        }
    }
}

/// Decodes the 0x2904 Characteristic Presentation Format descriptor.
struct PresentationFormat: CustomStringConvertible {
    let format: UInt8
    let exponent: Int8
    let unit: UInt16

    init(data: Data) {
        format = data.uint8(at: 0) ?? 0
        exponent = Int8(bitPattern: data.uint8(at: 1) ?? 0)
        unit = data.uint16LE(at: 2) ?? 0
    }

    var description: String {
        let formats: [UInt8: String] = [
            0x01: "bool", 0x04: "uint8", 0x06: "uint16", 0x08: "uint32", 0x0C: "int8",
            0x0E: "int16", 0x10: "int32", 0x14: "float32", 0x19: "utf8", 0x1B: "struct",
        ]
        let units: [UInt16: String] = [
            0x2700: "einheitenlos", 0x272F: "°C", 0x27AD: "%", 0x2728: "V", 0x2704: "A", 0x2763: "dBm",
        ]
        let formatName = formats[format] ?? String(format: "0x%02X", format)
        let unitName = units[unit] ?? String(format: "Unit 0x%04X", unit)
        return "\(formatName), Exp \(exponent), \(unitName)"
    }
}
