import CoreBluetooth
import Foundation
import Observation

/// Owns the single CBCentralManager of the app: scanning, connecting and
/// routing connection events to `PeripheralSession`s.
@Observable
final class BLECentral: NSObject, CBCentralManagerDelegate {
    private(set) var state: CBManagerState = .unknown
    private(set) var isScanning = false
    private(set) var devices: [UUID: ScannedDevice] = [:]
    private(set) var sessions: [UUID: PeripheralSession] = [:]

    @ObservationIgnored private var manager: CBCentralManager!
    @ObservationIgnored private var scanRequests = Set<String>()
    @ObservationIgnored private var pruneTimer: Timer?
    @ObservationIgnored private var pendingScanStart = false
    /// Advertisements arrive dozens of times per second; they are collected here and
    /// published to `devices` a few times per second to keep SwiftUI smooth.
    @ObservationIgnored private var buffer: [UUID: ScannedDevice] = [:]
    @ObservationIgnored private var bufferDirty = false

    override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: .main, options: [
            CBCentralManagerOptionShowPowerAlertKey: true,
        ])
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.flushBuffer()
        }
    }

    var isPoweredOn: Bool { state == .poweredOn }

    var stateDescription: String {
        switch state {
        case .poweredOn: return "Bluetooth bereit"
        case .poweredOff: return "Bluetooth ist ausgeschaltet"
        case .unauthorized: return "Bluetooth-Zugriff nicht erlaubt – bitte in den Einstellungen freigeben"
        case .unsupported: return "Dieses Gerät unterstützt kein Bluetooth LE"
        case .resetting: return "Bluetooth wird neu gestartet …"
        case .unknown: return "Bluetooth-Status unbekannt"
        @unknown default: return "Bluetooth-Status unbekannt"
        }
    }

    var sortedDevices: [ScannedDevice] {
        devices.values.sorted { lhs, rhs in
            if lhs.planeMatch != rhs.planeMatch { return lhs.planeMatch > rhs.planeMatch }
            return lhs.smoothedRSSI > rhs.smoothedRSSI
        }
    }

    var planeCandidates: [ScannedDevice] {
        sortedDevices.filter { $0.planeMatch != .none }
    }

    // MARK: - Scanning

    /// Several screens can request scanning at once; scanning stops when the last one releases it.
    func requestScan(_ owner: String) {
        scanRequests.insert(owner)
        startScanIfPossible()
    }

    func releaseScan(_ owner: String) {
        scanRequests.remove(owner)
        if scanRequests.isEmpty, isScanning {
            manager.stopScan()
            isScanning = false
            appLog(.info, "Scan", "Scan gestoppt")
        }
    }

    func clearDevices() {
        buffer = buffer.filter { sessions[$0.key]?.state.isActive == true }
        devices = buffer
    }

    private func startScanIfPossible() {
        guard !scanRequests.isEmpty else { return }
        guard state == .poweredOn else {
            pendingScanStart = true
            return
        }
        guard !isScanning else { return }
        // No service filter: the SmartPlane PRO may not advertise its control service,
        // and the Lab should see everything anyway.
        manager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true,
        ])
        isScanning = true
        appLog(.info, "Scan", "Scan gestartet (alle BLE-Geräte)")
    }

    private func flushBuffer() {
        let cutoff = Date().addingTimeInterval(-20)
        let stale = buffer.filter { $0.value.lastSeen < cutoff && sessions[$0.key]?.state.isActive != true }
        for key in stale.keys { buffer.removeValue(forKey: key) }
        if bufferDirty || !stale.isEmpty {
            devices = buffer
            bufferDirty = false
        }
    }

    // MARK: - Connections

    func session(for peripheral: CBPeripheral) -> PeripheralSession {
        if let existing = sessions[peripheral.identifier] { return existing }
        let session = PeripheralSession(peripheral: peripheral)
        sessions[peripheral.identifier] = session
        return session
    }

    @discardableResult
    func connect(_ device: ScannedDevice) -> PeripheralSession {
        connect(device.peripheral)
    }

    @discardableResult
    func connect(_ peripheral: CBPeripheral) -> PeripheralSession {
        let session = session(for: peripheral)
        if peripheral.state == .connected {
            if session.state != .ready && session.state != .discovering { session.startDiscovery() }
            return session
        }
        session.willConnect()
        appLog(.info, "Verbindung", "Verbinde mit \(session.displayName) …")
        manager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
        ])
        return session
    }

    func disconnect(_ session: PeripheralSession) {
        appLog(.info, "Verbindung", "Trenne \(session.displayName)")
        manager.cancelPeripheralConnection(session.peripheral)
    }

    func retrieveKnownPeripheral(_ identifier: UUID) -> CBPeripheral? {
        manager.retrievePeripherals(withIdentifiers: [identifier]).first
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        appLog(state == .poweredOn ? .info : .warning, "Bluetooth", stateDescription)
        if state == .poweredOn {
            if pendingScanStart || !scanRequests.isEmpty {
                pendingScanStart = false
                isScanning = false
                startScanIfPossible()
            }
        } else {
            isScanning = false
            for session in sessions.values where session.state.isActive {
                session.didDisconnect(nil)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let rssi = RSSI.intValue
        let info = AdvertisementInfo(advertisementData)
        let now = Date()
        bufferDirty = true
        if var existing = buffer[peripheral.identifier] {
            existing.advertisement.merge(info)
            if rssi != 127 {
                existing.rssi = rssi
                existing.rssiHistory.append(rssi)
                if existing.rssiHistory.count > 60 { existing.rssiHistory.removeFirst() }
            }
            existing.lastSeen = now
            existing.packetCount += 1
            buffer[peripheral.identifier] = existing
        } else {
            let device = ScannedDevice(
                id: peripheral.identifier,
                peripheral: peripheral,
                advertisement: info,
                rssi: rssi,
                rssiHistory: rssi == 127 ? [] : [rssi],
                firstSeen: now,
                lastSeen: now,
                packetCount: 1
            )
            buffer[peripheral.identifier] = device
            if device.planeMatch != .none {
                appLog(.info, "Scan", "Flugzeug-Kandidat gefunden: \(device.displayName) (\(rssi) dBm)")
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let session = session(for: peripheral)
        appLog(.info, "Verbindung", "Verbunden mit \(session.displayName)")
        session.didConnect()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let session = session(for: peripheral)
        appLog(.error, "Verbindung", "Verbindung zu \(session.displayName) fehlgeschlagen: \(error?.localizedDescription ?? "unbekannt")")
        session.didFailToConnect(error)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let session = session(for: peripheral)
        appLog(error == nil ? .info : .warning, "Verbindung",
               "Getrennt von \(session.displayName)\(error.map { ": \($0.localizedDescription)" } ?? "")")
        session.didDisconnect(error)
    }
}
