import CoreBluetooth
import Foundation
import Observation

@Observable
final class ServiceNode: Identifiable {
    let id = UUID()
    let service: CBService
    var characteristics: [CharacteristicNode] = []
    var includedServices: [CBUUID] = []

    init(service: CBService) { self.service = service }

    var uuid: CBUUID { service.uuid }
    var name: String { UUIDCatalog.displayName(for: service.uuid) }
    var isPrimary: Bool { service.isPrimary }
}

@Observable
final class DescriptorNode: Identifiable {
    let id = UUID()
    let descriptor: CBDescriptor
    var value: String?

    init(descriptor: CBDescriptor) { self.descriptor = descriptor }

    var uuid: CBUUID { descriptor.uuid }
    var name: String { UUIDCatalog.name(for: descriptor.uuid) ?? descriptor.uuid.uuidString }
}

@Observable
final class CharacteristicNode: Identifiable {
    struct Sample: Identifiable, Hashable {
        let id = UUID()
        let date: Date
        let data: Data
        let isNotification: Bool
    }

    let id = UUID()
    let characteristic: CBCharacteristic
    @ObservationIgnored weak var service: ServiceNode?
    var value: Data?
    var lastUpdate: Date?
    var history: [Sample] = []
    var isNotifying = false
    var descriptors: [DescriptorNode] = []
    var lastError: String?
    var writeCount = 0
    /// Text from the 0x2901 "User Description" descriptor if the firmware provides one.
    var userDescription: String?

    init(characteristic: CBCharacteristic, service: ServiceNode) {
        self.characteristic = characteristic
        self.service = service
    }

    var uuid: CBUUID { characteristic.uuid }
    var properties: CBCharacteristicProperties { characteristic.properties }

    var name: String {
        if let known = UUIDCatalog.name(for: characteristic.uuid) { return known }
        if let userDescription, !userDescription.isEmpty { return userDescription }
        return "Unbekannte Characteristic"
    }

    var canRead: Bool { properties.contains(.read) }
    var canWrite: Bool { properties.contains(.write) }
    var canWriteWithoutResponse: Bool { properties.contains(.writeWithoutResponse) }
    var isWritable: Bool { canWrite || canWriteWithoutResponse }
    var canNotify: Bool { properties.contains(.notify) || properties.contains(.indicate) }

    var propertyLabels: [String] {
        var labels: [String] = []
        if properties.contains(.broadcast) { labels.append("Broadcast") }
        if properties.contains(.read) { labels.append("Read") }
        if properties.contains(.writeWithoutResponse) { labels.append("Write NR") }
        if properties.contains(.write) { labels.append("Write") }
        if properties.contains(.notify) { labels.append("Notify") }
        if properties.contains(.indicate) { labels.append("Indicate") }
        if properties.contains(.authenticatedSignedWrites) { labels.append("Signed") }
        if properties.contains(.extendedProperties) { labels.append("Extended") }
        return labels
    }

    func record(_ data: Data, notification: Bool) {
        value = data
        lastUpdate = Date()
        lastError = nil
        history.append(Sample(date: Date(), data: data, isNotification: notification))
        if history.count > 200 { history.removeFirst(history.count - 200) }
    }
}

extension CBCharacteristicProperties {
    var shortDescription: String {
        var parts: [String] = []
        if contains(.read) { parts.append("R") }
        if contains(.write) { parts.append("W") }
        if contains(.writeWithoutResponse) { parts.append("WnR") }
        if contains(.notify) { parts.append("N") }
        if contains(.indicate) { parts.append("I") }
        return parts.joined(separator: "/")
    }
}
