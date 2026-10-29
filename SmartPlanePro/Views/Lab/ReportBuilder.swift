import Foundation

/// Builds a plain-text dump of everything known about a device, handy for
/// sharing with the community or for reverse engineering on a computer.
enum ReportBuilder {
    static func build(device: ScannedDevice?, session: PeripheralSession?) -> String {
        var lines: [String] = []
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        lines.append("SmartPlane PRO Control – BLE-Bericht")
        lines.append("Erstellt: \(Date().formatted(date: .abbreviated, time: .standard)) · App \(appVersion)")
        lines.append(String(repeating: "=", count: 48))

        if let device {
            let ad = device.advertisement
            lines.append("Gerät: \(device.displayName)")
            lines.append("iOS-ID: \(device.id.uuidString)")
            lines.append("RSSI: \(device.smoothedRSSI) dBm · Pakete: \(device.packetCount)")
            lines.append("")
            lines.append("[Advertisement]")
            lines.append("  Local Name: \(ad.localName ?? "-")")
            lines.append("  Verbindbar: \(ad.isConnectable.map { $0 ? "ja" : "nein" } ?? "-")")
            if let power = ad.txPowerLevel { lines.append("  TX Power: \(power) dBm") }
            if let data = ad.manufacturerData {
                lines.append("  Herstellerdaten: \(data.hexString) (\(ad.companyName ?? "?"))")
            }
            for uuid in ad.serviceUUIDs { lines.append("  Service UUID: \(uuid.uuidString) \(UUIDCatalog.name(for: uuid) ?? "")") }
            for uuid in ad.overflowServiceUUIDs { lines.append("  Overflow UUID: \(uuid.uuidString)") }
            for (uuid, data) in ad.serviceData { lines.append("  Service Data \(uuid.uuidString): \(data.hexString)") }
        }

        if let session {
            lines.append("")
            lines.append("[Verbindung] \(session.state.label)")
            lines.append("  Max. Schreiblänge: \(session.maxWriteWithoutResponse) / \(session.maxWriteWithResponse) Bytes")
            let info = FirmwareInfo.gather(from: session)
            if !info.isEmpty {
                lines.append("")
                lines.append("[Geräte- & Firmware-Infos]")
                for row in info.rows { lines.append("  \(row.label): \(row.value)") }
            }
            lines.append("")
            lines.append("[GATT-Tabelle]")
            for service in session.services {
                lines.append("Service \(service.uuid.uuidString) – \(service.name)\(service.isPrimary ? "" : " (sekundär)")")
                for node in service.characteristics {
                    lines.append("  ├ Char \(node.uuid.uuidString) – \(node.name)")
                    lines.append("  │   Eigenschaften: \(node.propertyLabels.joined(separator: ", "))")
                    if let value = node.value {
                        var text = "  │   Wert: \(value.isEmpty ? "(leer)" : value.hexString)"
                        if let printable = value.printableString { text += "  \"\(printable)\"" }
                        lines.append(text)
                    }
                    for descriptor in node.descriptors {
                        lines.append("  │   Desc \(descriptor.uuid.uuidString) \(descriptor.name): \(descriptor.value ?? "-")")
                    }
                }
            }
            if let resolved = PlaneResolver.resolve(session: session, custom: nil, preferred: "auto") {
                lines.append("")
                lines.append("[Flugzeug-Protokoll] \(resolved.profile.name) via \(resolved.detection)")
            } else {
                lines.append("")
                lines.append("[Flugzeug-Protokoll] kein bekanntes Profil gefunden")
            }
        } else {
            lines.append("")
            lines.append("(Nicht verbunden – für die GATT-Tabelle bitte verbinden.)")
        }
        return lines.joined(separator: "\n")
    }
}
