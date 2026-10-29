import CoreBluetooth

/// Human readable names for well known Bluetooth SIG UUIDs plus all vendor UUIDs
/// we know from the TobyRich / PowerUp / TI ecosystem.
enum UUIDCatalog {
    static func name(for uuid: CBUUID) -> String? {
        let key = uuid.uuidString.uppercased()
        if let vendor = vendor[key] { return vendor }
        if key.count == 4 { return sig[key] }
        // 128-bit form of a SIG UUID: 0000XXXX-0000-1000-8000-00805F9B34FB
        if key.hasPrefix("0000"), key.hasSuffix("-0000-1000-8000-00805F9B34FB") {
            let short = String(key.dropFirst(4).prefix(4))
            return sig[short]
        }
        return nil
    }

    static func displayName(for uuid: CBUUID) -> String {
        name(for: uuid) ?? "Unbekannt (herstellerspezifisch)"
    }

    static func isVendorSpecific(_ uuid: CBUUID) -> Bool {
        uuid.uuidString.count > 8 && !uuid.uuidString.uppercased().hasSuffix("-0000-1000-8000-00805F9B34FB")
    }

    static let vendor: [String: String] = [
        // TobyRich SmartPlane (from TobyRich's open source services.plist)
        "75B64E51-F171-4ED1-921A-476090D80BA7": "SmartPlane Control Service",
        "75B64E51-0010-4ED1-921A-476090D80BA7": "SmartPlane Motor (UInt8 0…254)",
        "75B64E51-0020-4ED1-921A-476090D80BA7": "SmartPlane Ruder (alt)",
        "75B64E51-0021-4ED1-921A-476090D80BA7": "SmartPlane Ruder (Int8 −126…126)",
        "75B64E51-0030-4ED1-921A-476090D80BA7": "SmartPlane Temperatur",
        "75B64E51-0040-4ED1-921A-476090D80BA7": "SmartPlane Ladestatus",
        "75B64E51-F181-4ED1-921A-476090D80BA7": "SmartPlane Prototyp-Service (SML1)",
        "75B64E51-F184-4ED1-921A-476090D80BA7": "SmartPlane Prototyp Motor",
        "75B64E51-F185-4ED1-921A-476090D80BA7": "SmartPlane Prototyp Ruder",
        // PowerUp 3.0 (same SmartLink firmware family)
        "86C3810E-F171-40D9-A117-26B300768CD6": "PowerUp Control Service",
        "86C3810E-0010-40D9-A117-26B300768CD6": "PowerUp Motor",
        "86C3810E-0020-40D9-A117-26B300768CD6": "PowerUp Ruder (alt)",
        "86C3810E-0021-40D9-A117-26B300768CD6": "PowerUp Ruder",
        "86C3810E-0030-40D9-A117-26B300768CD6": "PowerUp Temperatur",
        "86C3810E-0040-40D9-A117-26B300768CD6": "PowerUp Lade-/Statusfeld",
        // Texas Instruments Over-the-Air Download (firmware update)
        "F000FFC0-0451-4000-B000-000000000000": "TI OAD Firmware-Service",
        "F000FFC1-0451-4000-B000-000000000000": "TI OAD Image Identify",
        "F000FFC2-0451-4000-B000-000000000000": "TI OAD Image Block",
        "F000FFC3-0451-4000-B000-000000000000": "TI OAD Image Count",
        "F000FFC4-0451-4000-B000-000000000000": "TI OAD Image Status",
        "F000CCC0-0451-4000-B000-000000000000": "TI Connection Control",
        "F000CCC1-0451-4000-B000-000000000000": "TI Conn. Parameter",
        "F000CCC2-0451-4000-B000-000000000000": "TI Conn. Request",
        "F000CCC3-0451-4000-B000-000000000000": "TI Conn. Disconnect",
        // Common third-party services
        "6E400001-B5A3-F393-E0A9-E50E24DCCA9E": "Nordic UART Service",
        "6E400002-B5A3-F393-E0A9-E50E24DCCA9E": "Nordic UART RX",
        "6E400003-B5A3-F393-E0A9-E50E24DCCA9E": "Nordic UART TX",
        "8EC90001-F315-4F60-9FB8-838830DAEA50": "Nordic Buttonless DFU",
        "00001530-1212-EFDE-1523-785FEABCD123": "Nordic Legacy DFU",
        "0000FFE0-0000-1000-8000-00805F9B34FB": "HM-10 / CC254x Serial",
        "D0611E78-BBB4-4591-A5F8-487910AE4366": "Apple Continuity",
        "9FA480E0-4967-4542-9390-D343DC5D04AE": "Apple Nearby",
        "7905F431-B5CE-4E99-A40F-4B1E122D00D0": "Apple Notification Center",
    ]

    static let sig: [String: String] = [
        // Services
        "1800": "Generic Access", "1801": "Generic Attribute", "1802": "Immediate Alert",
        "1803": "Link Loss", "1804": "Tx Power", "1805": "Current Time", "180A": "Device Information",
        "180D": "Heart Rate", "180F": "Battery", "1812": "Human Interface Device",
        "1813": "Scan Parameters", "181A": "Environmental Sensing", "181C": "User Data",
        "1819": "Location and Navigation", "1826": "Fitness Machine", "FE59": "Nordic DFU",
        "FFE0": "Serial (HM-10)", "FFF0": "Vendor Serial", "FEF5": "Dialog Semiconductor",
        "FD6F": "Exposure Notification", "FEAA": "Eddystone", "FE9F": "Google", "FEED": "Tile",
        // Characteristics
        "2A00": "Device Name", "2A01": "Appearance", "2A02": "Peripheral Privacy Flag",
        "2A03": "Reconnection Address", "2A04": "Peripheral Preferred Connection Parameters",
        "2A05": "Service Changed", "2A06": "Alert Level", "2A07": "Tx Power Level",
        "2A19": "Battery Level", "2A23": "System ID", "2A24": "Model Number String",
        "2A25": "Serial Number String", "2A26": "Firmware Revision String",
        "2A27": "Hardware Revision String", "2A28": "Software Revision String",
        "2A29": "Manufacturer Name String", "2A2A": "IEEE 11073-20601 Regulatory",
        "2A50": "PnP ID", "2A6E": "Temperature", "2A1C": "Temperature Measurement",
        "2AA6": "Central Address Resolution", "2AC9": "Resolvable Private Address Only",
        "2B29": "Client Supported Features", "2B2A": "Database Hash", "2B3A": "Server Supported Features",
        // Descriptors
        "2900": "Characteristic Extended Properties", "2901": "Characteristic User Description",
        "2902": "Client Characteristic Configuration", "2903": "Server Characteristic Configuration",
        "2904": "Characteristic Presentation Format", "2905": "Characteristic Aggregate Format",
    ]

    /// Bluetooth SIG company identifiers that commonly show up in manufacturer data.
    static let companies: [UInt16: String] = [
        0x0000: "Ericsson", 0x0002: "Intel", 0x0006: "Microsoft", 0x000A: "Qualcomm",
        0x000D: "Texas Instruments", 0x000F: "Broadcom", 0x004C: "Apple", 0x0059: "Nordic Semiconductor",
        0x0075: "Samsung", 0x0087: "Garmin", 0x00E0: "Google", 0x0131: "Cypress",
        0x0157: "Huami", 0x02E5: "Espressif", 0x038F: "Xiaomi", 0x0499: "Ruuvi",
        0x0822: "Adafruit", 0xFFFF: "Test / nicht registriert",
    ]
}
