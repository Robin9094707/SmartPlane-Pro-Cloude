import CoreBluetooth
import Foundation
import Observation

/// High level connection to the SmartPlane: finds it, connects, resolves the
/// protocol, transmits motor/rudder values and reads battery / charge / temperature.
@Observable
final class PlaneLink {
    enum Phase: Equatable {
        case idle
        case searching
        case connecting(String)
        case discovering
        case ready
        case unsupported
        case failed(String)

        var label: String {
            switch self {
            case .idle: return "Nicht verbunden"
            case .searching: return "Suche Flugzeug …"
            case .connecting(let name): return "Verbinde mit \(name) …"
            case .discovering: return "Lese Protokoll …"
            case .ready: return "Bereit"
            case .unsupported: return "Unbekanntes Protokoll"
            case .failed(let reason): return reason
            }
        }

        var isBusy: Bool {
            switch self {
            case .searching, .connecting, .discovering: return true
            default: return false
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var session: PeripheralSession?
    private(set) var plane: ResolvedPlane?
    private(set) var batteryReported: Int?
    private(set) var isCharging: Bool?
    private(set) var temperatureRaw: Int?
    private(set) var firmware = FirmwareInfo()
    private(set) var sentEngine: UInt8 = 0
    private(set) var sentRudder: Int8 = 0
    private(set) var packetsSent = 0
    private(set) var packetsDropped = 0
    private(set) var lastSendDate: Date?

    private let central: BLECentral
    private let settings: AppSettings
    @ObservationIgnored private var statusTimer: Timer?
    @ObservationIgnored private var lastEngineData = Data()
    @ObservationIgnored private var lastRudderData = Data()
    @ObservationIgnored private var lastEngineWrite = Date.distantPast
    @ObservationIgnored private var lastRudderWrite = Date.distantPast
    @ObservationIgnored private var oadQuery: OADQuery?
    /// Last throttle actually sent (0…1), used for battery sag compensation.
    @ObservationIgnored private var lastThrottle: Double = 0
    @ObservationIgnored private var autoConnectTimer: Timer?

    init(central: BLECentral, settings: AppSettings) {
        self.central = central
        self.settings = settings
    }

    var isReady: Bool { phase == .ready && plane != nil && session?.state == .ready }
    var rssi: Int? { session?.rssi }
    var name: String { session?.displayName ?? "SmartPlane" }

    /// Battery percentage corrected for voltage sag under motor load, using
    /// TobyRich's own model (R_batt = 0.52 Ω, 0.5 A motor at full throttle, 3.0–3.75 V).
    var batteryPercent: Int? {
        guard let reported = batteryReported else { return nil }
        guard settings.batteryCompensation else { return reported }
        let motorCurrent = lastThrottle * 0.5
        let auxCurrent = motorCurrent == 0 ? 0 : 0.013 + 0.019
        let drop = (motorCurrent + auxCurrent) * 0.520
        let measured = 3.0 + 0.75 * Double(reported) / 100
        let corrected = Int((100 * ((measured + drop) - 3.0) / 0.75).rounded())
        return corrected.clamped(to: 0...100)
    }

    // MARK: - Connecting

    func startSearching() {
        guard !phase.isBusy, !isReady else { return }
        phase = .searching
        central.requestScan("plane")
        autoConnectTimer?.invalidate()
        autoConnectTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.autoConnectTick()
        }
        appLog(.info, "Flugzeug", "Suche nach SmartPlane …")
    }

    func stopSearching() {
        autoConnectTimer?.invalidate()
        autoConnectTimer = nil
        central.releaseScan("plane")
        if phase == .searching { phase = .idle }
    }

    private func autoConnectTick() {
        guard phase == .searching, settings.autoConnect else { return }
        // Prefer the last flown plane, then any certain match, then the nearest likely one.
        let candidates = central.planeCandidates
        if let lastID = settings.lastPlaneID,
           let known = candidates.first(where: { $0.id.uuidString == lastID }) {
            connect(to: known)
            return
        }
        if let certain = candidates.first(where: { $0.planeMatch == .certain && $0.smoothedRSSI > Int(settings.autoConnectRSSI) }) {
            connect(to: certain)
        }
    }

    func connect(to device: ScannedDevice) {
        autoConnectTimer?.invalidate()
        autoConnectTimer = nil
        central.releaseScan("plane")
        if let current = session, current.id != device.id, current.state.isActive {
            central.disconnect(current)
        }
        phase = .connecting(device.displayName)
        let session = central.connect(device)
        attach(session)
    }

    /// Uses an already connected Lab session as the plane (e.g. after a custom mapping).
    func adopt(_ session: PeripheralSession) {
        autoConnectTimer?.invalidate()
        central.releaseScan("plane")
        attach(session)
        if session.state == .ready { resolve() } else { phase = .discovering }
    }

    private func attach(_ session: PeripheralSession) {
        self.session = session
        session.onReady = { [weak self] _ in self?.resolve() }
        session.onDisconnect = { [weak self] _, error in self?.handleDisconnect(error) }
        session.onValueUpdate = { [weak self] node in self?.handleValue(node) }
    }

    func disconnect() {
        stopSearching()
        if let session {
            sendNeutral()
            central.disconnect(session)
        }
    }

    private func handleDisconnect(_ error: Error?) {
        statusTimer?.invalidate()
        statusTimer = nil
        plane = nil
        sentEngine = 0
        sentRudder = 0
        lastEngineData = Data()
        lastRudderData = Data()
        phase = error == nil ? .idle : .failed("Verbindung verloren")
    }

    /// Called after discovery: figure out which characteristics control the plane.
    func resolve() {
        guard let session else { return }
        phase = .discovering
        let custom = settings.customProfile(for: session.id)
        guard let resolved = PlaneResolver.resolve(session: session, custom: custom, preferred: settings.preferredProfile) else {
            phase = .unsupported
            plane = nil
            appLog(.warning, "Flugzeug", "Kein bekanntes Steuerprotokoll gefunden – bitte im Labor untersuchen und Motor/Ruder zuordnen.")
            firmware = FirmwareInfo.gather(from: session)
            return
        }
        plane = resolved
        phase = .ready
        settings.lastPlaneID = session.id.uuidString
        appLog(.info, "Flugzeug", "Protokoll: \(resolved.profile.name) [\(resolved.detection)]")

        // Same init sequence as the original firmware driver: zero motor + rudder.
        lastEngineData = Data()
        lastRudderData = Data()
        send(throttle: 0, rudder: 0, force: true)

        if let battery = resolved.battery {
            session.read(battery)
            if battery.canNotify { session.setNotify(true, for: battery) }
        }
        refreshStatus()
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
        // The OAD header is only queried on request (Labor → Firmware), the original
        // SmartPlane app never touched the OAD service during normal flight either.
        firmware = FirmwareInfo.gather(from: session)
    }

    private func refreshStatus() {
        guard let session, let plane else { return }
        if let charge = plane.chargeStatus { session.read(charge) }
        if let temperature = plane.temperature { session.read(temperature) }
        if let battery = plane.battery, !battery.isNotifying { session.read(battery) }
    }

    private func handleValue(_ node: CharacteristicNode) {
        guard let plane, let session else { return }
        let data = node.value ?? Data()
        if node === plane.battery, let level = data.uint8(at: 0) {
            batteryReported = Int(level)
        } else if node === plane.chargeStatus, let status = data.uint8(at: 0) {
            let charging = status != 0
            if charging != isCharging {
                appLog(.info, "Flugzeug", charging ? "Akku wird geladen" : "Akku lädt nicht")
            }
            isCharging = charging
        } else if node === plane.temperature, let raw = data.uint8(at: 0) {
            temperatureRaw = Int(Int8(bitPattern: raw))
        } else if node === plane.oadIdentify {
            firmware = FirmwareInfo.gather(from: session)
        } else if node.service?.uuid == CBUUID(string: "180A") || node.service?.uuid == CBUUID(string: "1800") {
            firmware = FirmwareInfo.gather(from: session)
        }
    }

    func requestFirmwareHeader() {
        guard let session else { return }
        oadQuery = OADQuery(session: session)
        oadQuery?.start()
    }

    // MARK: - Transmission

    /// Sends normalized values: throttle 0…1, rudder −1…1 (+ = right).
    /// Values are only re-sent when they change, plus an optional keep-alive refresh.
    func send(throttle: Double, rudder: Double, force: Bool = false) {
        guard let session, let plane, session.state == .ready else { return }
        let engineData = plane.profile.encodeEngine(throttle)
        let rudderData = plane.profile.encodeRudder(rudder)
        let now = Date()
        let refresh: TimeInterval = settings.keepAlive ? 0.3 : .infinity

        if force || engineData != lastEngineData || now.timeIntervalSince(lastEngineWrite) > refresh {
            if session.write(engineData, to: plane.engine, quiet: !force) {
                lastEngineData = engineData
                lastEngineWrite = now
                sentEngine = engineData.first ?? 0
                lastThrottle = throttle
                packetsSent += 1
                lastSendDate = now
            } else {
                packetsDropped += 1
            }
        }
        if force || rudderData != lastRudderData || now.timeIntervalSince(lastRudderWrite) > refresh {
            if session.write(rudderData, to: plane.rudder, quiet: !force) {
                lastRudderData = rudderData
                lastRudderWrite = now
                sentRudder = Int8(bitPattern: rudderData.first ?? 0)
                packetsSent += 1
                lastSendDate = now
            } else {
                packetsDropped += 1
            }
        }
    }

    func sendNeutral() {
        send(throttle: 0, rudder: 0, force: true)
    }
}
