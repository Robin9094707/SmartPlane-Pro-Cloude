import Charts
import CoreBluetooth
import SwiftUI

struct DeviceDetailView: View {
    @Environment(AppModel.self) private var model
    let deviceID: UUID
    var openCockpit: () -> Void

    @State private var oadQuery: OADQuery?

    private var device: ScannedDevice? { model.central.devices[deviceID] }
    private var session: PeripheralSession? { model.central.sessions[deviceID] }

    var body: some View {
        List {
            Section {
                headerCard
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))

            if let session, session.state == .ready {
                protocolSection(session)
                infoSection(session)
                ForEach(session.services) { service in
                    serviceSection(service, session: session)
                }
            } else if let session, session.state.isActive {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(session.state.label)
                    }
                }
            }

            if let device {
                advertisementSection(device)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AmbientBackground())
        .navigationTitle(device?.displayName ?? session?.displayName ?? "Gerät")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let session, session.state == .ready {
                        Button("Alle Werte lesen", systemImage: "arrow.down.doc") { session.readAll() }
                        Button("Alle Notifications abonnieren", systemImage: "bell.badge") { session.subscribeAll() }
                        Button("GATT neu einlesen", systemImage: "arrow.clockwise") { session.startDiscovery() }
                    }
                    ShareLink(item: ReportBuilder.build(device: device, session: session)) {
                        Label("Bericht teilen", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label("Aktionen", systemImage: "ellipsis.circle")
                }
            }
        }
        .onAppear { model.central.requestScan("detail") }
        .onDisappear {
            model.central.releaseScan("detail")
            oadQuery?.cancel()
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device?.displayName ?? session?.displayName ?? "Gerät")
                        .font(.title2.bold())
                        .fontDesign(.rounded)
                    Text(deviceID.uuidString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                if let device, device.planeMatch != .none {
                    Chip(text: device.planeMatch == .certain ? "SmartLink" : "Flugzeug?", color: Theme.accent)
                }
            }

            if let device, device.rssiHistory.count > 1 {
                Chart(Array(device.rssiHistory.enumerated()), id: \.offset) { item in
                    LineMark(x: .value("Paket", item.offset), y: .value("dBm", item.element))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.accent.gradient)
                    AreaMark(x: .value("Paket", item.offset), y: .value("dBm", item.element))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.accent.opacity(0.15).gradient)
                }
                .chartYScale(domain: -105 ... -20)
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .leading, values: [-100, -80, -60, -40]) }
                .frame(height: 80)
            }

            HStack(spacing: 18) {
                metric("RSSI", "\(session?.rssi ?? device?.smoothedRSSI ?? 0) dBm")
                if let distance = device?.estimatedDistance {
                    metric("Entfernung", distance < 10 ? String(format: "~%.1f m", distance) : String(format: "~%.0f m", distance))
                }
                if let device {
                    metric("Pakete", "\(device.packetCount)")
                }
            }

            connectButton
        }
        .card(padding: 18)
    }

    @ViewBuilder
    private var connectButton: some View {
        if let session, session.state.isActive {
            Button(role: .destructive) {
                if model.link.session === session { model.flight.cutMotor() }
                model.central.disconnect(session)
            } label: {
                Label("Trennen", systemImage: "xmark.circle").frame(maxWidth: .infinity)
            }
            .glassButtonStyle()
        } else {
            Button {
                connect()
            } label: {
                Label("Verbinden & alles auslesen", systemImage: "link").frame(maxWidth: .infinity)
            }
            .glassButtonStyle(prominent: true)
            .disabled(device == nil && model.central.retrieveKnownPeripheral(deviceID) == nil)
        }
    }

    private func connect() {
        let session: PeripheralSession
        if let device {
            session = model.central.connect(device)
        } else if let peripheral = model.central.retrieveKnownPeripheral(deviceID) {
            session = model.central.connect(peripheral)
        } else {
            return
        }
        session.autoReadAll = model.settings.labAutoReadAll
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.headline, design: .rounded)).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Sections

    private func protocolSection(_ session: PeripheralSession) -> some View {
        let custom = model.settings.customProfile(for: session.id)
        let resolved = PlaneResolver.resolve(session: session, custom: custom, preferred: model.settings.preferredProfile)
        return Section {
            if let resolved {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(resolved.profile.name).font(.headline)
                        Text("Erkannt über: \(resolved.detection)").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.accent)
                }
                LabeledContent("Motor", value: resolved.engine.uuid.uuidString).font(.caption.monospaced())
                LabeledContent("Ruder", value: resolved.rudder.uuid.uuidString).font(.caption.monospaced())
                Button {
                    model.link.adopt(session)
                    openCockpit()
                } label: {
                    Label("Mit diesem Gerät fliegen", systemImage: "airplane.departure")
                }
            } else {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Kein bekanntes Steuerprotokoll").font(.headline)
                        Text("Öffne eine beschreibbare Characteristic, teste sie mit dem Live-Regler und ordne sie als Motor bzw. Ruder zu.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "questionmark.diamond.fill").foregroundStyle(Theme.warning)
                }
            }
            if let custom {
                LabeledContent("Eigene Zuordnung", value: "Motor …\(custom.engine.suffix(12)) · Ruder …\(custom.rudder.suffix(12))")
                    .font(.caption)
                Button("Eigene Zuordnung löschen", systemImage: "trash", role: .destructive) {
                    model.settings.setCustomProfile(nil, for: session.id)
                }
            }
        } header: {
            Text("Flugzeug-Protokoll")
        }
    }

    private func infoSection(_ session: PeripheralSession) -> some View {
        let info = FirmwareInfo.gather(from: session)
        let hasOAD = session.service(PlaneResolver.oadService) != nil
        return Section {
            LabeledContent("Status", value: session.state.label)
            LabeledContent("Services / Characteristics", value: "\(session.services.count) / \(session.allCharacteristics.count)")
            LabeledContent("Max. Schreiblänge", value: "\(session.maxWriteWithoutResponse) B (ohne Antwort) · \(session.maxWriteWithResponse) B")
            if let duration = session.discoveryDuration {
                LabeledContent("Discovery", value: String(format: "%.2f s", duration))
            }
            ForEach(info.rows) { row in
                LabeledContent(row.label) {
                    Text(row.value).textSelection(.enabled).multilineTextAlignment(.trailing)
                }
            }
            if info.isEmpty {
                Text("Keine Device-Information-Daten gelesen. Tippe auf „Alle Werte lesen“.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if hasOAD {
                Button {
                    let query = OADQuery(session: session)
                    oadQuery = query
                    query.start()
                } label: {
                    Label("Firmware-Image abfragen (TI OAD)", systemImage: "cpu")
                }
            }
        } header: {
            Text("Geräte- & Firmware-Infos")
        } footer: {
            if hasOAD {
                Text("Die OAD-Abfrage liest nur den Image-Header (Version, A/B-Slot, Größe). Es wird nichts geflasht.")
            }
        }
    }

    private func serviceSection(_ service: ServiceNode, session: PeripheralSession) -> some View {
        Section {
            ForEach(service.characteristics) { node in
                NavigationLink {
                    CharacteristicDetailView(node: node, session: session)
                } label: {
                    CharacteristicRow(node: node)
                }
            }
            if service.characteristics.isEmpty {
                Text("Keine Characteristics").foregroundStyle(.secondary)
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                Text(service.uuid.uuidString)
                    .font(.caption2.monospaced())
                    .textCase(nil)
            }
        }
    }

    private func advertisementSection(_ device: ScannedDevice) -> some View {
        let ad = device.advertisement
        return Section("Advertisement") {
            LabeledContent("Local Name", value: ad.localName ?? "–")
            LabeledContent("Verbindbar", value: ad.isConnectable.map { $0 ? "Ja" : "Nein" } ?? "–")
            if let power = ad.txPowerLevel { LabeledContent("TX Power", value: "\(power) dBm") }
            if let data = ad.manufacturerData {
                LabeledContent("Hersteller", value: ad.companyName ?? "–")
                LabeledContent("Herstellerdaten") {
                    Text(data.hexString).font(.caption.monospaced()).textSelection(.enabled).multilineTextAlignment(.trailing)
                }
            }
            ForEach(ad.allServiceUUIDs, id: \.self) { uuid in
                LabeledContent(UUIDCatalog.displayName(for: uuid)) {
                    Text(uuid.uuidString).font(.caption2.monospaced()).textSelection(.enabled)
                }
            }
            ForEach(Array(ad.serviceData.keys), id: \.self) { uuid in
                LabeledContent("Service Data \(uuid.uuidString)") {
                    Text(ad.serviceData[uuid]?.hexString ?? "").font(.caption.monospaced())
                }
            }
            LabeledContent("Zuerst gesehen", value: device.firstSeen.formatted(date: .omitted, time: .standard))
        }
    }
}

struct CharacteristicRow: View {
    let node: CharacteristicNode

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(node.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if node.isNotifying {
                    Image(systemName: "bell.fill").font(.caption).foregroundStyle(Theme.accent)
                }
            }
            Text(node.uuid.uuidString)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 4) {
                ForEach(node.propertyLabels, id: \.self) { label in
                    Chip(text: label, color: label.hasPrefix("Write") ? Theme.warning : .blue)
                }
            }
            if let value = node.value {
                Text(value.printableString.map { "\"\($0)\"" } ?? (value.isEmpty ? "(leer)" : value.hexString))
                    .font(.caption.monospaced())
                    .lineLimit(2)
                    .foregroundStyle(Color.primary.opacity(0.8))
            }
            if let error = node.lastError {
                Text(error).font(.caption2).foregroundStyle(Theme.danger)
            }
        }
        .padding(.vertical, 2)
    }
}
