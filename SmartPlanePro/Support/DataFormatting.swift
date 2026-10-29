import Foundation

extension Data {
    /// "0A FF 12"
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    var compactHex: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Parses "0a ff", "0x0AFF", "0a:ff" or "0AFF" into bytes.
    init?(hexInput: String) {
        var cleaned = hexInput.lowercased()
            .replacingOccurrences(of: "0x", with: "")
            .filter { !" :,-_\n\t".contains($0) }
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isHexDigit }) else { return nil }
        if cleaned.count % 2 == 1 { cleaned = "0" + cleaned }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    /// UTF-8 text if the payload looks like printable text.
    var printableString: String? {
        guard !isEmpty else { return nil }
        var trimmed = self
        while let last = trimmed.last, last == 0 { trimmed.removeLast() }
        guard !trimmed.isEmpty, let text = String(data: trimmed, encoding: .utf8) else { return nil }
        let printable = text.unicodeScalars.allSatisfy { scalar in
            scalar.properties.isAlphabetic || scalar.properties.numericType != nil ||
            CharacterSet.punctuationCharacters.contains(scalar) ||
            CharacterSet.symbols.contains(scalar) || scalar == " "
        }
        return printable ? text.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    func uint8(at offset: Int) -> UInt8? {
        guard offset >= 0, offset < count else { return nil }
        return self[startIndex + offset]
    }

    func uint16LE(at offset: Int) -> UInt16? {
        guard let lo = uint8(at: offset), let hi = uint8(at: offset + 1) else { return nil }
        return UInt16(lo) | (UInt16(hi) << 8)
    }

    func uint32LE(at offset: Int) -> UInt32? {
        guard let lo = uint16LE(at: offset), let hi = uint16LE(at: offset + 2) else { return nil }
        return UInt32(lo) | (UInt32(hi) << 16)
    }
}

struct InfoRow: Identifiable, Hashable {
    let label: String
    let value: String
    var id: String { label }

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

/// Several interpretations of a raw characteristic value, shown side by side in the Lab.
struct ValueInterpretations {
    let data: Data

    var rows: [InfoRow] {
        var result: [InfoRow] = [InfoRow("Hex", data.isEmpty ? "–" : data.hexString), InfoRow("Bytes", "\(data.count)")]
        if let text = data.printableString { result.append(InfoRow("UTF-8", "\"\(text)\"")) }
        if data.count >= 1, let byte = data.uint8(at: 0) {
            result.append(InfoRow("UInt8", "\(byte)"))
            result.append(InfoRow("Int8", "\(Int8(bitPattern: byte))"))
        }
        if data.count >= 2, let value = data.uint16LE(at: 0) {
            result.append(InfoRow("UInt16 LE", "\(value)"))
            result.append(InfoRow("Int16 LE", "\(Int16(bitPattern: value))"))
        }
        if data.count >= 4, let value = data.uint32LE(at: 0) {
            result.append(InfoRow("UInt32 LE", "\(value)"))
            result.append(InfoRow("Float32 LE", String(format: "%.4g", Float(bitPattern: value))))
        }
        if data.count <= 8 {
            result.append(InfoRow("Binär", data.map { byte in
                let bits = String(byte, radix: 2)
                return String(repeating: "0", count: 8 - bits.count) + bits
            }.joined(separator: " ")))
        }
        return result
    }
}

extension Int {
    /// Classic five-step signal bars from an RSSI value in dBm.
    var rssiBars: Int {
        switch self {
        case 0...: return 0 // 127 = unavailable
        case -55...: return 4
        case -67...: return 3
        case -80...: return 2
        case -92...: return 1
        default: return 0
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
