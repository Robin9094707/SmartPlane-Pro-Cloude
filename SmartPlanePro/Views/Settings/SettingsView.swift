import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            Form {
                Section {
                    Picker("Steuerung", selection: $settings.controlMode) {
                        ForEach(ControlMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    if settings.controlMode == .tilt {
                        sliderRow("Voller Ausschlag bei", value: $settings.tiltMaxAngle, range: 15...70, step: 1, format: { "\(Int($0))°" })
                        HStack {
                            Text("Nullpunkt")
                            Spacer()
                            Text(String(format: "%.1f°", settings.tiltOffset)).monospacedDigit().foregroundStyle(.secondary)
                            Button("Jetzt nullen") { model.flight.calibrateTilt() }
                                .buttonStyle(.borderless)
                        }
                    }
                    sliderRow("Totzone", value: $settings.deadzone, range: 0...0.25, step: 0.01, format: percent)
                    sliderRow("Expo", value: $settings.expo, range: 0...0.9, step: 0.05, format: percent)
                    ExpoCurve(expo: settings.expo, deadzone: settings.deadzone)
                        .frame(height: 90)
                        .listRowBackground(Color.clear)
                    sliderRow("Ruder-Ausschlag", value: $settings.rudderRate, range: 0.3...1, step: 0.05, format: percent)
                    sliderRow("Trimmung", value: $settings.rudderTrim, range: -0.3...0.3, step: 0.01, format: { String(format: "%+.0f %%", $0 * 100) })
                    Toggle("Ruder umkehren", isOn: $settings.rudderReversed)
                } header: {
                    Text("Steuerung")
                } footer: {
                    Text("Expo macht kleine Bewegungen feiner. Trimmung gleicht ein Flugzeug aus, das von selbst zur Seite zieht.")
                }

                Section {
                    Toggle("Flight Assist", isOn: $settings.flightAssist)
                    if settings.flightAssist {
                        sliderRow("Linksruder-Ausgleich", value: $settings.leftRudderScale, range: 0.5...1, step: 0.05, format: percent)
                        Toggle("Mehr Gas in Kurven", isOn: $settings.turnBoost)
                    }
                } header: {
                    Text("Flight Assist")
                } footer: {
                    Text("Wie in der Original-App: Das Ruder zieht nach links stärker, daher wird Linksausschlag gedämpft, und in Kurven gibt es bis zu 30 % Zusatzschub.")
                }

                Section("Motor") {
                    sliderRow("Maximales Gas", value: $settings.maxThrottle, range: 0.3...1, step: 0.05, format: percent)
                    sliderRow("Gas-Rampe", value: $settings.throttleRampSeconds, range: 0...1.5, step: 0.05, format: { String(format: "%.2f s", $0) })
                    Toggle("Scharfschalten nur bei 0 % Gas", isOn: $settings.requireZeroThrottleToArm)
                    Toggle("Haptisches Feedback", isOn: $settings.haptics)
                }

                Section {
                    Toggle("Automatisch verbinden", isOn: $settings.autoConnect)
                    if settings.autoConnect {
                        sliderRow("Ab Signalstärke", value: $settings.autoConnectRSSI, range: -95...(-40), step: 5, format: { "\(Int($0)) dBm" })
                    }
                    Picker("Protokoll", selection: $settings.preferredProfile) {
                        Text("Automatisch").tag("auto")
                        ForEach(PlaneProfile.builtIn) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    sliderRow("Senderate", value: $settings.sendRateHz, range: 10...50, step: 5, format: { "\(Int($0)) Hz" })
                        .onChange(of: settings.sendRateHz) { _, _ in model.flight.restartLoop() }
                    Toggle("Keep-Alive (Werte alle 0,3 s erneut senden)", isOn: $settings.keepAlive)
                    Toggle("Akku-Spannungseinbruch ausgleichen", isOn: $settings.batteryCompensation)
                    if let lastID = settings.lastPlaneID {
                        LabeledContent("Zuletzt geflogen", value: String(lastID.prefix(8)))
                        Button("Gespeichertes Flugzeug vergessen", role: .destructive) { settings.lastPlaneID = nil }
                    }
                } header: {
                    Text("Verbindung")
                } footer: {
                    Text("Die Original-Firmware erwartet Motor 0…254 (UInt8) und Ruder −126…126 (Int8), gesendet ohne Antwort.")
                }

                Section("Gamepad & Labor") {
                    Toggle("Gamepad verwenden", isOn: $settings.gamepadEnabled)
                    LabeledContent("Controller", value: model.gamepad.controllerName ?? "keiner verbunden")
                    Toggle("Im Labor alles automatisch lesen", isOn: $settings.labAutoReadAll)
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Bluetooth", value: model.central.stateDescription)
                    Link(destination: URL(string: "https://github.com/TobyRich/app-smartplane-android")!) {
                        Label("Protokollquelle: TobyRich (BSD)", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Button("Steuerung auf Standard zurücksetzen", role: .destructive) { confirmReset = true }
                    Button("Einführung erneut zeigen") { settings.hasSeenOnboarding = false }
                } header: {
                    Text("Über")
                } footer: {
                    Text("Inoffizielle Community-App. Nicht mit der TobyRich GmbH verbunden. Fliege verantwortungsvoll.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground())
            .navigationTitle("Einstellungen")
            .confirmationDialog("Alle Steuer-Einstellungen zurücksetzen?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Zurücksetzen", role: .destructive) {
                    model.settings.resetFlightTuning()
                    model.flight.restartLoop()
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                           format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}

/// Visualises deadzone + expo response curve.
struct ExpoCurve: View {
    var expo: Double
    var deadzone: Double

    var body: some View {
        Canvas { context, size in
            var grid = Path()
            grid.move(to: CGPoint(x: size.width / 2, y: 0))
            grid.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            grid.move(to: CGPoint(x: 0, y: size.height / 2))
            grid.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(grid, with: .color(.secondary.opacity(0.4)), lineWidth: 1)

            var linear = Path()
            linear.move(to: CGPoint(x: 0, y: size.height))
            linear.addLine(to: CGPoint(x: size.width, y: 0))
            context.stroke(linear, with: .color(.secondary.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

            var curve = Path()
            for index in 0...100 {
                let x = Double(index) / 50 - 1
                let y = FlightController.shape(x, deadzone: deadzone, expo: expo)
                let point = CGPoint(x: (x + 1) / 2 * size.width, y: (1 - (y + 1) / 2) * size.height)
                if index == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
            }
            context.stroke(curve, with: .color(Theme.accent), lineWidth: 2.5)
        }
        .padding(.vertical, 4)
    }
}
