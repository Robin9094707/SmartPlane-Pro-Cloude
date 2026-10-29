import CoreBluetooth
import Foundation

/// TI OAD (Over-the-Air Download) image header as reported by the
/// `F000FFC1` "Image Identify" characteristic. Layout (little endian):
/// `uint16 version` (bit 0 = image B), `uint16 length` (in 4-byte words), `uint8 id[4]`.
struct OADImageHeader: Equatable {
    let versionCode: UInt16
    let lengthWords: UInt16
    let imageID: String
    let raw: Data

    init?(data: Data) {
        guard data.count >= 4, let version = data.uint16LE(at: 0), let length = data.uint16LE(at: 2) else { return nil }
        versionCode = version
        lengthWords = length
        if data.count >= 8 {
            let idBytes = data.subdata(in: data.startIndex + 4 ..< data.startIndex + 8)
            imageID = String(bytes: idBytes, encoding: .ascii)?
                .trimmingCharacters(in: .controlCharacters.union(.whitespaces)) ?? idBytes.hexString
        } else {
            imageID = "----"
        }
        raw = data
    }

    var versionNumber: Int { Int(versionCode >> 1) }
    var imageSlot: String { versionCode & 0x1 == 0 ? "A" : "B" }
    var sizeBytes: Int { Int(lengthWords) * 4 }

    /// Same format as TobyRich's app: `<ID>-<version>-<A|B>`.
    var shortDescription: String { "\(imageID.isEmpty ? "----" : imageID)-\(versionNumber)-\(imageSlot)" }
}

/// Everything we could learn about the plane / peripheral, gathered from
/// standard services (0x180A, 0x1800, 0x180F) and the TI OAD service.
struct FirmwareInfo {
    var deviceName: String?
    var manufacturer: String?
    var model: String?
    var serial: String?
    var hardwareRevision: String?
    var firmwareRevision: String?
    var softwareRevision: String?
    var systemID: String?
    var pnpID: String?
    var appearance: String?
    var connectionParameters: String?
    var oadImage: OADImageHeader?

    var rows: [InfoRow] {
        var result: [InfoRow] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { result.append(InfoRow(label, value)) }
        }
        add("Gerätename", deviceName)
        add("Hersteller", manufacturer)
        add("Modell", model)
        add("Seriennummer", serial)
        add("Hardware", hardwareRevision)
        add("Firmware", firmwareRevision)
        add("Software", softwareRevision)
        add("System-ID", systemID)
        add("PnP-ID", pnpID)
        add("Appearance", appearance)
        add("Verb.-Parameter", connectionParameters)
        if let oad = oadImage {
            add("OAD-Image", oad.shortDescription)
            add("OAD-Größe", "\(oad.sizeBytes) Bytes (\(oad.lengthWords) Wörter)")
        }
        return result
    }

    var isEmpty: Bool { rows.isEmpty }

    static func gather(from session: PeripheralSession) -> FirmwareInfo {
        var info = FirmwareInfo()
        func text(_ uuid: String) -> String? {
            guard let data = session.characteristic(CBUUID(string: uuid))?.value, !data.isEmpty else { return nil }
            return data.printableString ?? data.hexString
        }
        info.deviceName = text("2A00")
        info.manufacturer = text("2A29")
        info.model = text("2A24")
        info.serial = text("2A25")
        info.hardwareRevision = text("2A27")
        info.firmwareRevision = text("2A26")
        info.softwareRevision = text("2A28")

        if let data = session.characteristic(CBUUID(string: "2A23"))?.value, data.count >= 8 {
            // TobyRich formats the System ID as bytes 0-2 + 5-7, reversed (≈ MAC address).
            var bytes = Array(data.prefix(3)) + Array(data[(data.startIndex + 5)..<(data.startIndex + 8)])
            bytes.reverse()
            info.systemID = bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
        }
        if let data = session.characteristic(CBUUID(string: "2A50"))?.value, data.count >= 7,
           let vendor = data.uint16LE(at: 1), let product = data.uint16LE(at: 3), let version = data.uint16LE(at: 5) {
            let source = data.uint8(at: 0) == 1 ? "Bluetooth SIG" : "USB-IF"
            let company = UUIDCatalog.companies[vendor] ?? String(format: "0x%04X", vendor)
            info.pnpID = "\(company) (\(source)), Produkt 0x\(String(format: "%04X", product)), v\(version)"
        }
        if let data = session.characteristic(CBUUID(string: "2A01"))?.value, let value = data.uint16LE(at: 0) {
            info.appearance = String(format: "0x%04X", value)
        }
        if let data = session.characteristic(CBUUID(string: "2A04"))?.value, data.count >= 8,
           let minInterval = data.uint16LE(at: 0), let maxInterval = data.uint16LE(at: 2),
           let latency = data.uint16LE(at: 4), let timeout = data.uint16LE(at: 6) {
            info.connectionParameters = String(
                format: "%.1f–%.1f ms, Latenz %d, Timeout %d ms",
                Double(minInterval) * 1.25, Double(maxInterval) * 1.25, Int(latency), Int(timeout) * 10
            )
        }
        if let data = session.characteristic(PlaneResolver.oadIdentify, in: PlaneResolver.oadService)?.value {
            info.oadImage = OADImageHeader(data: data)
        }
        return info
    }
}

/// Reads the firmware image header via TI OAD exactly like the original TobyRich app:
/// enable notifications on Image Identify, write 0x00 (asks image A), after 1.5 s
/// write 0x01 (asks image B). The plane answers with the header of the image that is
/// *not* the one asked for, i.e. the currently running one. Nothing gets flashed.
final class OADQuery {
    private weak var session: PeripheralSession?
    private var timer: Timer?

    init(session: PeripheralSession) { self.session = session }

    func start() {
        guard let session,
              let identify = session.characteristic(PlaneResolver.oadIdentify, in: PlaneResolver.oadService) else {
            appLog(.warning, "Firmware", "Kein TI-OAD-Service vorhanden")
            return
        }
        appLog(.info, "Firmware", "Frage Firmware-Image-Header ab (TI OAD, nur lesen)")
        session.setNotify(true, for: identify)
        session.write(Data([0x00]), to: identify)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self, let session = self.session else { return }
            session.write(Data([0x01]), to: identify)
        }
    }

    func cancel() { timer?.invalidate() }
}
