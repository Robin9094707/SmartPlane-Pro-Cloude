import SwiftUI

/// Pick the plane manually from all nearby Bluetooth devices.
struct ConnectSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var openLab: () -> Void
    @State private var showAll = false

    var body: some View {
        NavigationStack {
            List {
                if model.link.isReady || model.link.session?.state.isActive == true {
                    Section("Aktuelle Verbindung") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.link.name).font(.headline)
                            Text(model.link.phase.label).font(.subheadline).foregroundStyle(.secondary)
                            if let plane = model.link.plane {
                                Text("\(plane.profile.name) · \(plane.detection)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(model.link.firmware.rows) { row in
                            LabeledContent(row.label, value: row.value)
                        }
                        Button("Trennen", systemImage: "xmark.circle", role: .destructive) {
                            model.flight.cutMotor()
                            model.link.disconnect()
                        }
                    }
                }

                Section {
                    let devices = showAll ? model.central.sortedDevices : model.central.planeCandidates
                    if devices.isEmpty {
                        HStack(spacing: 14) {
                            RadarPulse(active: model.central.isScanning).frame(width: 36, height: 36)
                            VStack(alignment: .leading) {
                                Text(showAll ? "Suche Geräte …" : "Noch kein Flugzeug gefunden")
                                    .font(.subheadline.weight(.semibold))
                                Text("Flugzeug einschalten. Die PRO-Version kann sich anders melden – aktiviere „Alle Geräte“.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    ForEach(devices) { device in
                        Button {
                            model.link.connect(to: device)
                            dismiss()
                        } label: {
                            DeviceRow(device: device)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text(showAll ? "Alle Bluetooth-Geräte" : "Flugzeuge in der Nähe")
                        Spacer()
                        if model.central.isScanning { ProgressView().controlSize(.mini) }
                    }
                } footer: {
                    Toggle("Alle Geräte anzeigen", isOn: $showAll)
                        .font(.footnote)
                        .padding(.top, 6)
                }

                Section {
                    Button("Bluetooth-Labor öffnen", systemImage: "antenna.radiowaves.left.and.right", action: openLab)
                } footer: {
                    Text("Im Labor siehst du alle Services, Characteristics und Firmware-Infos und kannst Motor/Ruder manuell zuordnen.")
                }
            }
            .navigationTitle("Flugzeug verbinden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .onAppear { model.central.requestScan("connect-sheet") }
        .onDisappear { model.central.releaseScan("connect-sheet") }
    }
}

struct DeviceRow: View {
    let device: ScannedDevice

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.18))
                Image(systemName: device.planeMatch == .none ? "dot.radiowaves.left.and.right" : "airplane")
                    .foregroundStyle(iconColor)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(device.displayName)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if device.planeMatch == .certain {
                        Chip(text: "SmartLink", color: Theme.accent)
                    } else if device.planeMatch == .likely {
                        Chip(text: "Flugzeug?", color: Theme.warning)
                    }
                }
                HStack(spacing: 6) {
                    Text(device.id.uuidString.prefix(8))
                        .font(.caption.monospaced())
                    if let company = device.advertisement.companyName {
                        Text("· \(company)")
                    }
                    if !device.advertisement.allServiceUUIDs.isEmpty {
                        Text("· \(device.advertisement.allServiceUUIDs.count) Services")
                    }
                    if device.advertisement.isConnectable == false {
                        Text("· nicht verbindbar")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                SignalBars(rssi: device.smoothedRSSI)
                Text("\(device.smoothedRSSI) dBm")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private var iconColor: Color {
        switch device.planeMatch {
        case .certain: return Theme.accent
        case .likely: return Theme.warning
        case .none: return .blue
        }
    }
}
