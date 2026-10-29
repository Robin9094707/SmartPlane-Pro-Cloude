import CoreBluetooth
import SwiftUI

struct CharacteristicDetailView: View {
    @Environment(AppModel.self) private var model
    let node: CharacteristicNode
    let session: PeripheralSession

    enum ProbeFormat: String, CaseIterable, Identifiable {
        case uint8 = "UInt8 (0…255)"
        case int8 = "Int8 (−128…127)"
        var id: String { rawValue }
    }

    @State private var hexInput = ""
    @State private var writeWithResponse = false
    @State private var inputError: String?
    @State private var probeFormat: ProbeFormat = .uint8
    @State private var probeValue: Double = 0
    @State private var probeLive = false
    @State private var lastProbeWrite = Date.distantPast
    @State private var assignedMessage: String?
    @State private var rudderFormat: PlaneProfile.ValueFormat = .int8

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(node.name).font(.title3.bold())
                    Text(node.uuid.uuidString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    HStack(spacing: 4) {
                        ForEach(node.propertyLabels, id: \.self) { Chip(text: $0, color: .blue) }
                    }
                    if let service = node.service {
                        Text("Service: \(service.name)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                if let value = node.value {
                    ForEach(ValueInterpretations(data: value).rows) { row in
                        LabeledContent(row.label) {
                            Text(row.value)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if let date = node.lastUpdate {
                        LabeledContent("Aktualisiert", value: date.formatted(date: .omitted, time: .standard))
                    }
                } else {
                    Text(node.canRead ? "Noch nicht gelesen" : "Nicht lesbar").foregroundStyle(.secondary)
                }
                if let error = node.lastError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.danger)
                }
                HStack {
                    if node.canRead {
                        Button("Lesen", systemImage: "arrow.down.circle") { session.read(node) }
                            .glassButtonStyle()
                    }
                    if node.canNotify {
                        Button(node.isNotifying ? "Notify aus" : "Notify an", systemImage: node.isNotifying ? "bell.slash" : "bell") {
                            session.setNotify(!node.isNotifying, for: node)
                        }
                        .glassButtonStyle(prominent: node.isNotifying)
                    }
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Wert")
            }

            if node.isWritable {
                writeSection
                probeSection
                assignSection
            }

            if !node.descriptors.isEmpty {
                Section("Descriptors") {
                    ForEach(node.descriptors) { descriptor in
                        LabeledContent(descriptor.name) {
                            Text(descriptor.value ?? descriptor.uuid.uuidString)
                                .font(.caption.monospaced())
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }

            if !node.history.isEmpty {
                Section("Verlauf (\(node.history.count))") {
                    ForEach(node.history.suffix(30).reversed()) { sample in
                        HStack {
                            Image(systemName: sample.isNotification ? "bell.fill" : "arrow.down")
                                .font(.caption2)
                                .foregroundStyle(sample.isNotification ? Theme.accent : .secondary)
                            Text(sample.date.formatted(date: .omitted, time: .standard))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(sample.data.hexString).font(.caption.monospaced())
                        }
                    }
                }
            }
        }
        .navigationTitle(node.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            writeWithResponse = !node.canWriteWithoutResponse
        }
        .onDisappear {
            if probeLive { probeLive = false }
        }
    }

    // MARK: - Writing

    private var writeSection: some View {
        Section {
            TextField("Hex, z. B. 00 7F FE", text: $hexInput)
                .font(.body.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onSubmit(sendHex)
            if node.canWrite && node.canWriteWithoutResponse {
                Toggle("Mit Antwort schreiben", isOn: $writeWithResponse)
            }
            HStack {
                ForEach(["00", "01", "7F", "80", "FE"], id: \.self) { preset in
                    Button(preset) {
                        hexInput = preset
                        sendHex()
                    }
                    .font(.caption.monospaced())
                    .glassButtonStyle()
                }
            }
            .buttonStyle(.borderless)
            Button("Senden", systemImage: "paperplane.fill", action: sendHex)
                .glassButtonStyle(prominent: true)
                .buttonStyle(.borderless)
            if let inputError {
                Text(inputError).font(.caption).foregroundStyle(Theme.danger)
            }
        } header: {
            Text("Schreiben")
        } footer: {
            Text("Vorsicht: Bei Motor-Characteristics kann der Propeller sofort anlaufen. Flugzeug festhalten!")
        }
    }

    private func sendHex() {
        guard let data = Data(hexInput: hexInput) else {
            inputError = "Ungültige Hex-Eingabe"
            return
        }
        inputError = nil
        if !session.write(data, to: node, withResponse: writeWithResponse) {
            inputError = "Konnte nicht schreiben (nicht verbunden oder Puffer voll)"
        }
    }

    // MARK: - Live probe

    private var probeSection: some View {
        Section {
            Picker("Format", selection: $probeFormat) {
                ForEach(ProbeFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            .onChange(of: probeFormat) { _, _ in probeValue = 0 }
            VStack(alignment: .leading) {
                HStack {
                    Text("Wert")
                    Spacer()
                    Text("\(Int(probeValue)) · 0x\(String(format: "%02X", probeByte))")
                        .font(.body.monospacedDigit())
                }
                Slider(value: $probeValue, in: probeFormat == .uint8 ? 0...255 : -128...127, step: 1)
                    .disabled(!probeLive)
                    .onChange(of: probeValue) { _, _ in writeProbe() }
            }
            Toggle("Live senden", isOn: $probeLive)
                .onChange(of: probeLive) { _, live in
                    if !live { resetProbe() }
                }
            Button("Auf 0 zurücksetzen", systemImage: "arrow.uturn.backward", action: resetProbe)
        } header: {
            Text("Live-Regler (Protokoll finden)")
        } footer: {
            Text("Schiebe den Regler und beobachte das Flugzeug. Bewegt sich das Ruder, ist es meist Int8; dreht der Motor hoch, meist UInt8. Beim Ausschalten wird automatisch 0 gesendet.")
        }
    }

    private var probeByte: UInt8 {
        switch probeFormat {
        case .uint8: return UInt8(Int(probeValue).clamped(to: 0...255))
        case .int8: return UInt8(bitPattern: Int8(Int(probeValue).clamped(to: -128...127)))
        }
    }

    private func writeProbe() {
        guard probeLive else { return }
        // Limit to ~30 writes per second.
        guard Date().timeIntervalSince(lastProbeWrite) > 0.033 else { return }
        lastProbeWrite = Date()
        session.write(Data([probeByte]), to: node, quiet: true)
    }

    private func resetProbe() {
        probeValue = 0
        session.write(Data([0]), to: node, withResponse: nil)
    }

    // MARK: - Assign to plane controls

    private var assignSection: some View {
        Section {
            Button {
                assign(asEngine: true)
            } label: {
                Label("Als Motor verwenden (UInt8 0…254)", systemImage: "fanblades")
            }
            Picker("Ruder-Format", selection: $rudderFormat) {
                Text("Int8 (Mitte 0)").tag(PlaneProfile.ValueFormat.int8)
                Text("UInt8 (Mitte 128)").tag(PlaneProfile.ValueFormat.uint8)
            }
            Button {
                assign(asEngine: false)
            } label: {
                Label("Als Ruder verwenden", systemImage: "arrow.left.and.right")
            }
            if let assignedMessage {
                Label(assignedMessage, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
            }
        } header: {
            Text("Dem Flugzeug zuordnen")
        } footer: {
            Text("Die Zuordnung wird für dieses Gerät gespeichert und hat Vorrang vor den eingebauten Profilen. Sind Motor und Ruder zugeordnet, kannst du in der Geräteansicht „Mit diesem Gerät fliegen“ wählen.")
        }
    }

    private func assign(asEngine: Bool) {
        var profile = model.settings.customProfile(for: session.id) ?? PlaneProfile(
            id: "custom-\(session.id.uuidString.prefix(8))",
            name: "Eigene Zuordnung",
            detail: "Im Labor erstellt",
            service: nil,
            engine: "",
            rudder: ""
        )
        let uuid = node.uuid.uuidString
        if asEngine {
            profile.engine = uuid
            assignedMessage = "Als Motor gespeichert"
        } else {
            profile.rudder = uuid
            profile.rudderFormat = rudderFormat
            profile.rudderCenter = rudderFormat == .uint8 ? 128 : 0
            profile.rudderMax = rudderFormat == .uint8 ? 127 : 126
            assignedMessage = "Als Ruder gespeichert"
        }
        // When both live in the same service, pin the service to avoid ambiguity.
        if let serviceUUID = node.service?.uuid.uuidString,
           let other = session.characteristic(CBUUID(string: asEngine ? (profile.rudder.isEmpty ? uuid : profile.rudder) : (profile.engine.isEmpty ? uuid : profile.engine))),
           other.service?.uuid.uuidString == serviceUUID {
            profile.service = serviceUUID
        } else {
            profile.service = nil
        }
        model.settings.setCustomProfile(profile, for: session.id)
        appLog(.info, "Labor", "Eigene Zuordnung: Motor=\(profile.engine.isEmpty ? "–" : profile.engine) Ruder=\(profile.rudder.isEmpty ? "–" : profile.rudder)")
    }
}
