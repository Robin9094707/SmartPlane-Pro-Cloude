import SwiftUI

struct CockpitView: View {
    @Environment(AppModel.self) private var model
    var openLab: () -> Void

    @State private var showConnect = false
    @State private var armError: String?

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                HorizonView(roll: model.motion.tiltDegrees - model.settings.tiltOffset, pitch: model.motion.pitchDegrees)
                LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                if landscape {
                    landscapeLayout(size: geo.size)
                } else {
                    portraitLayout(size: geo.size)
                }
            }
            .onAppear { updateOrientation() }
            .onChange(of: landscape) { _, _ in updateOrientation() }
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            model.motion.start("cockpit")
            if !model.link.isReady && !model.link.phase.isBusy { model.link.startSearching() }
        }
        .onDisappear { model.motion.stop("cockpit") }
        .sheet(isPresented: $showConnect) {
            ConnectSheet(openLab: {
                showConnect = false
                openLab()
            })
            .presentationDetents([.medium, .large])
        }
        .alert("Nicht scharfgeschaltet", isPresented: Binding(get: { armError != nil }, set: { if !$0 { armError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(armError ?? "")
        }
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Layouts

    private func portraitLayout(size: CGSize) -> some View {
        VStack(spacing: 14) {
            StatusStrip { showConnect = true }
            if !model.link.isReady {
                ConnectionCard(showAll: { showConnect = true }, openLab: openLab)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            centerHUD
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 16) {
                ThrottleSlider(
                    value: Bindable(model.flight).throttleInput,
                    output: model.flight.throttleOutput,
                    armed: model.flight.isArmed,
                    haptics: model.settings.haptics
                )
                .frame(width: 92, height: min(320, size.height * 0.38))
                VStack(spacing: 12) {
                    modePicker
                    steeringControl
                        .frame(height: model.settings.controlMode == .joystick && !model.gamepad.isConnected ? 86 : nil)
                    QuickStats()
                }
            }
            HStack(spacing: 12) {
                armButton
                StopButton { model.flight.cutMotor() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.smooth, value: model.link.isReady)
    }

    private func landscapeLayout(size: CGSize) -> some View {
        HStack(alignment: .center, spacing: 18) {
            ThrottleSlider(
                value: Bindable(model.flight).throttleInput,
                output: model.flight.throttleOutput,
                armed: model.flight.isArmed,
                haptics: model.settings.haptics
            )
            .frame(width: 96, height: size.height * 0.82)

            VStack(spacing: 12) {
                StatusStrip { showConnect = true }
                if !model.link.isReady {
                    ConnectionCard(showAll: { showConnect = true }, openLab: openLab)
                } else {
                    Spacer(minLength: 0)
                    centerHUD
                }
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    armButton
                    StopButton { model.flight.cutMotor() }
                }
            }
            .frame(maxWidth: 460)

            VStack(spacing: 12) {
                modePicker
                Spacer(minLength: 0)
                steeringControl
                    .frame(height: model.settings.controlMode == .joystick && !model.gamepad.isConnected ? 110 : nil)
                QuickStats()
            }
            .frame(width: min(300, size.width * 0.3))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Pieces

    private var centerHUD: some View {
        VStack(spacing: 16) {
            AttitudeOverlay(roll: model.motion.tiltDegrees - model.settings.tiltOffset, rudder: model.flight.rudderOutput)
                .frame(height: 170)
            if let stunt = model.flight.stunt {
                HStack(spacing: 12) {
                    Image(systemName: stunt.stunt.symbol)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stunt.stunt.name).font(.headline)
                        ProgressView(value: model.flight.stuntProgress).tint(Theme.accent)
                    }
                    Button("Abbrechen", systemImage: "xmark") { model.flight.cancelStunt() }
                        .labelStyle(.iconOnly)
                        .glassButtonStyle()
                }
                .padding(14)
                .frame(maxWidth: 320)
                .glassPanel(cornerRadius: 22, tint: Theme.accent.opacity(0.5))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.smooth, value: model.flight.stunt?.stunt.id)
    }

    private var modePicker: some View {
        Picker("Steuerung", selection: Bindable(model.settings).controlMode) {
            ForEach(ControlMode.allCases) { mode in
                Label(mode.label, systemImage: mode.symbol).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .disabled(model.gamepad.isConnected && model.settings.gamepadEnabled)
    }

    @ViewBuilder
    private var steeringControl: some View {
        if model.gamepad.isConnected && model.settings.gamepadEnabled {
            HStack {
                Image(systemName: "gamecontroller.fill").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading) {
                    Text(model.gamepad.controllerName ?? "Controller").font(.subheadline.weight(.semibold))
                    Text("R2/RT = Gas · Stick = Ruder · B = Stop").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .glassPanel(cornerRadius: 22)
        } else if model.settings.controlMode == .joystick {
            RudderPad(value: Bindable(model.flight).joystickRudder, haptics: model.settings.haptics)
        } else {
            TiltIndicator(
                input: model.flight.rudderInputRaw,
                output: model.flight.rudderOutput,
                onCalibrate: { model.flight.calibrateTilt() }
            )
        }
    }

    private var armButton: some View {
        ArmButton(
            armed: model.flight.isArmed,
            enabled: model.link.isReady,
            haptics: model.settings.haptics,
            onArm: {
                switch model.flight.arm() {
                case .success: break
                case .failure(.notConnected): armError = "Das Flugzeug ist nicht verbunden."
                case .failure(.throttleNotZero): armError = "Zieh den Gashebel zuerst ganz nach unten (0 %)."
                }
            },
            onDisarm: { model.flight.disarm() }
        )
    }

    private func updateOrientation() {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        if let orientation = scene?.effectiveGeometry.interfaceOrientation {
            model.motion.interfaceOrientation = orientation
        }
    }
}

/// Small telemetry row below the steering control.
struct QuickStats: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            stat("Ruder", "\(Int((model.flight.rudderOutput * 100).rounded()))")
            Divider().frame(height: 26)
            stat("Flugzeit", timeString(model.flight.flightTime))
            Divider().frame(height: 26)
            stat("Pakete", "\(model.link.packetsSent)")
        }
        .padding(.vertical, 10)
        .glassPanel(cornerRadius: 20)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Shown in the cockpit while no plane is ready.
struct ConnectionCard: View {
    @Environment(AppModel.self) private var model
    var showAll: () -> Void
    var openLab: () -> Void

    var body: some View {
        let link = model.link
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RadarPulse(active: link.phase == .searching)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(link.phase)).font(.headline)
                    Text(subtitle(link.phase))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !model.central.isPoweredOn {
                Label(model.central.stateDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }

            let candidates = Array(model.central.planeCandidates.prefix(3))
            if link.phase == .searching && !candidates.isEmpty {
                ForEach(candidates) { device in
                    Button {
                        link.connect(to: device)
                    } label: {
                        HStack {
                            Image(systemName: "airplane")
                            Text(device.displayName).lineLimit(1)
                            Spacer()
                            SignalBars(rssi: device.smoothedRSSI)
                        }
                        .padding(.vertical, 4)
                    }
                    .glassButtonStyle()
                }
            }

            HStack(spacing: 10) {
                switch link.phase {
                case .idle, .failed:
                    Button("Suchen", systemImage: "magnifyingglass") { link.startSearching() }
                        .glassButtonStyle(prominent: true)
                case .unsupported:
                    Button("Im Labor untersuchen", systemImage: "stethoscope", action: openLab)
                        .glassButtonStyle(prominent: true)
                default:
                    EmptyView()
                }
                Button("Alle Geräte", systemImage: "list.bullet", action: showAll)
                    .glassButtonStyle()
            }
            .controlSize(.regular)
        }
        .card(padding: 16)
    }

    private func title(_ phase: PlaneLink.Phase) -> String {
        switch phase {
        case .unsupported: return "Protokoll nicht erkannt"
        case .failed: return "Verbindung getrennt"
        default: return phase.label
        }
    }

    private func subtitle(_ phase: PlaneLink.Phase) -> String {
        switch phase {
        case .searching: return "Flugzeug einschalten (LED blinkt) und Handy nah dranhalten."
        case .unsupported: return "Das Gerät spricht ein anderes Protokoll. Im Labor kannst du Motor und Ruder selbst zuordnen."
        case .failed(let reason): return reason
        case .idle: return "Tippe auf Suchen, um dein SmartPlane zu finden."
        default: return "Einen Moment …"
        }
    }
}

struct RadarPulse: View {
    var active: Bool
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(Theme.accent.opacity(0.6), lineWidth: 1.5)
                    .scaleEffect(animate ? 1.0 : 0.2)
                    .opacity(animate ? 0 : 1)
                    .animation(
                        active ? .easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(Double(ring) * 0.6) : .default,
                        value: animate
                    )
            }
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(Theme.accent)
        }
        .onAppear { animate = active }
        .onChange(of: active) { _, value in animate = value }
    }
}
