import SwiftUI

/// Bluetooth Lab: generic BLE scanner & GATT explorer.
struct LabView: View {
    @Environment(AppModel.self) private var model
    var openCockpit: () -> Void

    enum SortMode: String, CaseIterable, Identifiable {
        case signal = "Signal"
        case name = "Name"
        case recent = "Zuerst gesehen"
        var id: String { rawValue }
    }

    @State private var search = ""
    @State private var onlyNamed = false
    @State private var onlyConnectable = false
    @State private var minRSSI: Double = -100
    @State private var sort: SortMode = .signal
    @State private var paused = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                let connected = model.central.sessions.values.filter { $0.state.isActive }
                if !connected.isEmpty {
                    Section("Verbunden") {
                        ForEach(connected) { session in
                            NavigationLink {
                                DeviceDetailView(deviceID: session.id, openCockpit: openCockpit)
                            } label: {
                                HStack {
                                    Image(systemName: "link").foregroundStyle(Theme.accent)
                                    VStack(alignment: .leading) {
                                        Text(session.displayName).font(.body.weight(.semibold))
                                        Text(session.state.label).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    SignalBars(rssi: session.rssi)
                                }
                            }
                        }
                    }
                }

                Section {
                    if filteredDevices.isEmpty {
                        ContentUnavailableView(
                            model.central.isPoweredOn ? "Keine Geräte" : "Bluetooth nicht bereit",
                            systemImage: "antenna.radiowaves.left.and.right.slash",
                            description: Text(model.central.isPoweredOn ? "Schalte das Flugzeug ein oder lockere die Filter." : model.central.stateDescription)
                        )
                    }
                    ForEach(filteredDevices) { device in
                        NavigationLink {
                            DeviceDetailView(deviceID: device.id, openCockpit: openCockpit)
                        } label: {
                            DeviceRow(device: device)
                        }
                    }
                } header: {
                    HStack {
                        Text("\(filteredDevices.count) von \(model.central.devices.count) Geräten")
                        Spacer()
                        if model.central.isScanning { ProgressView().controlSize(.mini) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground())
            .navigationTitle("Bluetooth-Labor")
            .searchable(text: $search, prompt: "Name, UUID, Hersteller")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(paused ? "Scan fortsetzen" : "Scan pausieren", systemImage: paused ? "play.fill" : "pause.fill") {
                        paused.toggle()
                        if paused { model.central.releaseScan("lab") } else { model.central.requestScan("lab") }
                    }
                    NavigationLink {
                        LogView()
                    } label: {
                        Label("Protokoll", systemImage: "list.bullet.rectangle")
                    }
                    Menu {
                        Picker("Sortierung", selection: $sort) {
                            ForEach(SortMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Toggle("Nur mit Namen", isOn: $onlyNamed)
                        Toggle("Nur verbindbare", isOn: $onlyConnectable)
                        Button("Liste leeren", systemImage: "trash") { model.central.clearDevices() }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .onAppear { if !paused { model.central.requestScan("lab") } }
        .onDisappear { model.central.releaseScan("lab") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RadarPulse(active: model.central.isScanning)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.central.isScanning ? "Scanne alle BLE-Geräte" : (paused ? "Scan pausiert" : model.central.stateDescription))
                        .font(.headline)
                    Text("Flugzeug-Kandidaten werden oben einsortiert. Tippe ein Gerät an, um alle Services, Characteristics und Firmware-Daten zu lesen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Mindest-Signal")
                    Spacer()
                    Text(minRSSI <= -100 ? "alle" : "\(Int(minRSSI)) dBm").monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.caption)
                Slider(value: $minRSSI, in: -100...(-30), step: 5)
            }
        }
        .card(padding: 16)
    }

    private var filteredDevices: [ScannedDevice] {
        var devices = model.central.sortedDevices
        if minRSSI > -100 { devices = devices.filter { $0.smoothedRSSI >= Int(minRSSI) } }
        if onlyNamed { devices = devices.filter { $0.name != nil } }
        if onlyConnectable { devices = devices.filter { $0.advertisement.isConnectable != false } }
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            devices = devices.filter { device in
                device.displayName.lowercased().contains(query)
                    || device.id.uuidString.lowercased().contains(query)
                    || (device.advertisement.companyName?.lowercased().contains(query) ?? false)
                    || device.advertisement.allServiceUUIDs.contains { $0.uuidString.lowercased().contains(query) }
            }
        }
        switch sort {
        case .signal: break
        case .name: devices.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .recent: devices.sort { $0.firstSeen < $1.firstSeen }
        }
        return devices
    }
}
